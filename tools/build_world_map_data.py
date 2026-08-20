#!/usr/bin/env python3
"""GeoJSON -> WorldShapes.json (世界アトラス版。日本版 build_map_data.py の姉妹編).

ne_50m_simplified.geojson (mapshaper 出力) と world_countries.py (収録国マスタ)
を突き合わせ、世界地図リソースを出す。国境を接しない小国の形は生データ
ne_50m_countries.geojson から、インセット 4 カ国はさらに詳細な 1:10m から
取り直すので、3 つの入力ファイルが要る (10m は無ければ自動ダウンロード)。

日本版との最大の違い: 座標は緯度経度のまま出す。地球儀モード (設計文書
2026-08-16 §7) が平面への焼き込みを許さないため、投影は実行時に行う。

Run from tools/:
    curl -sL -o ne_10m_countries.geojson \\
        https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_10m_admin_0_countries.geojson
    npx mapshaper ne_50m_countries.geojson \\
        -simplify visvalingam 4% keep-shapes -clean \\
        -o ne_50m_simplified.geojson format=geojson
    python3 build_world_map_data.py
    mv WorldShapes.json ../ChizuHakase/Resources/
"""

from __future__ import annotations

import json
import math
import os
import sys

import world_countries as wc
from map_geometry import (bbox_gap, bbox_of, dist_to_segment_sq,
                          point_in_rings, pole_of_inaccessibility, ring_area)

SRC = "ne_50m_simplified.geojson"
RAW_SRC = "ne_50m_countries.geojson"
RAW_10M_SRC = "ne_10m_countries.geojson"
NE_10M_URL = ("https://raw.githubusercontent.com/nvkelso/natural-earth-vector/"
              "master/geojson/ne_10m_admin_0_countries.geojson")
DST = "WorldShapes.json"

# 0.0001° ≈ 赤道で 11m。世界地図の視認単位よりはるかに細かく、
# これ以上の桁はファイルを太らせて diff を揺らすだけ。
COORD_DECIMALS = 4

# --- 国コードの解決 ---------------------------------------------------------
# Natural Earth は ISO_N3 に -99 を入れる地物がある。収録国のうち該当する
# フランスとノルウェーはここで手で解決する (world_countries.py 冒頭の約束)。
# ISO_N3_EH からの自動復元はしない — 豪州領インド洋地域も '036' を名乗る等、
# 属領がコードを横取りする側のフィールドなので。
HAND_RESOLVED_N3 = {"FRA": 250, "NOR": 578}

# 同じ ISO_N3 を複数地物が名乗る (オーストラリア 036 と
# アシュモア・カルティエ諸島 036)。収録国として採るのは主権国家の地物だけ。
# TYPE の語彙はステージ表の前提どおり: Sovereign country / Country /
# Sovereignty (キューバ・カザフスタン)、それにイスラエル (TYPE=Disputed) を
# 例外で足す。
SOVEREIGN_TYPES = {"Country", "Sovereign country", "Sovereignty"}
SOVEREIGN_DESPITE_TYPE = {376}  # イスラエル (ステージ表「+ イスラエル」)


def is_sovereign(props, code):
    """収録国として採ってよい地物か (上の 2 定数のコメント参照)。"""
    return (props.get("TYPE") in SOVEREIGN_TYPES
            or code in SOVEREIGN_DESPITE_TYPE)

# --- 遠隔領土の除去 ---------------------------------------------------------
# Natural Earth のフランスは仏領ギアナ・レユニオン等を含む 1 地物で、
# そのまま描くと「フランス」の bbox が地球の 2/3 に広がりステージ枠が壊れる。
# 主リング (最大面積) から始め、残したリング群の bbox から MAX_RING_GAP_DEG
# 以内のリングを連鎖的に拾う。「主リングからの距離」だけでは群島が切れる:
# インドネシアのパプアはカリマンタンから 11° 離れているが、
# スラウェシ→ハルマヘラと渡れば届く。連鎖にするのはそのため。
MAX_RING_GAP_DEG = 6.0   # マレーシア半島部⇄ボルネオ部の海峡 ≈5.4° が下限を決める。
                         # ポルトガルのマデイラ (≈7.7°)・ガラパゴス (≈8°) は落ちる側

# ≈250km² 未満の岩礁・小島を落とす (面積は経度緯度平面のシューレース値)。
# 主リングは面積によらず必ず残す — マルタやモルディブは国そのものが
# この閾値より小さい。
MIN_RING_AREA_DEG2 = 0.02

# 例外表 (明示)。ここに無い国はすべて上の中立規則で刈る。
KEEP_ALL_RINGS = {
    840,  # アメリカ: アラスカ・ハワイは本土から 6° を超えるが、学習上外せない
    643,  # ロシア: 全土を保持 (日付変更線は正規化)。ステージ枠が広がる問題は
          # europeBbox (下記) を枠計算に使うことで避ける — 描画と枠の分離
}
GAP_OVERRIDES = {
    578: 4.0,  # ノルウェー: スバールバル (本土から ≈5.2°) を落とす。残すと
               # きたヨーロッパの枠が北へ 10° 伸び、本土側の国が皆小さくなる
}

# --- 小国の形の取り直し -----------------------------------------------------
# 4% 簡略化は世界全体には十分だが、小さい国を三角形まで潰す (シンガポール・
# マルタ・モルディブは 4 点リングになる)。主リングがこの点数を割った国は
# 生データから形を取り直し、控えめな Douglas-Peucker で間引き直す。
# ただし**陸の国境を接する国は取り直さない**: mapshaper は隣接国の共有国境を
# 同じ折れ線として簡略化しており、片側だけ生データに替えると国境が二重に
# ずれて隙間と重なりのすき間ができる (タップ判定も曖昧になる)。国境を接する
# かどうかは「簡略化データで他の地物と頂点を共有するか」で機械判定する —
# インセット 4 カ国を含む島国だけが取り直しの対象になる。
RESOURCE_MIN_MAIN_PTS = 8
RESOURCE_DP_RATIO = 0.003  # 許容誤差 = 国の bbox 長辺 x これ。国の大きさに比例
                           # させ、極小国 (シンガポール等) は生の点をほぼ全部残す
RESOURCE_DP_MIN_PTS = 30   # これ以下のリングは間引かない。取り直しの目的は輪郭を
                           # 返すことで、モルディブの環礁 (生 13 点) は 1 点も
                           # 無駄にできない
# 取り直した国は国自体が小さく、絶対面積の床 (MIN_RING_AREA_DEG2) では
# ゴゾ島 (マルタの 1/4) まで消える。日本版と同じ相対床に切り替える。
RESOURCE_RING_AREA_RATIO = 0.015

# ロシアの「ヨーロッパ側」の東端 (ウラル線)。ひがしヨーロッパのステージ枠を
# ベーリング海峡まで伸ばさないための分離線 (ステージ表の技術ノート)。
RUSSIA = 643
URAL_LON = 60.0

# インセット拡大の倍率 (裁定 2026-08-19 の 4 カ国)。
# 倍率は日本版の沖縄 1.6 より強い 2.5 — どの国も単独では 10pt に届かないため。
# 実機で見て調整する暫定値。コードごとに変えてよい (表がそのまま調整口)。
INSET_SCALE = {702: 2.5, 470: 2.5, 462: 2.5, 242: 2.5}

# --- インセット枠の配置 (沖縄方式の一般化) -----------------------------------
# 拡大した国を入れる破線枠を「いまのステージ枠の中の空き海域」から機械的に
# 選ぶ。手置きしない — 上流の簡略化が変われば走査が置き直す (日本版
# build_map_data.py の沖縄と同じ理由)。満たす条件も沖縄の 2 条件の一般化:
#   1. ステージ枠 (メンバー国 bbox の連結。ロシアは europeBbox、インセット国は
#      実位置) の内側に収める — 枠を 1 度も広げない
#   2. 空き候補のうち実位置に最も近いものを選ぶ — 本当の場所の記憶を保つ
# 空きの判定は bbox ではなくリング実形状で行う: 東南アジアの海はインドネシアの
# bbox にほぼ覆われていて、bbox 判定では置き場所が 1 つも残らない。
# 走査は Swift と同じ cos 補正の投影座標で行う — 枠の縦横比は画面での
# 見た目そのものだから。基準緯度は WorldProjection.referenceLatitudeDegrees
# の写し。ずらすと「置いた枠」と「描かれる枠」の比が食い違う。
PROJ_REF_LAT_DEG = 30.0
PROJ_COS = math.cos(math.radians(PROJ_REF_LAT_DEG))
# 破線枠と国の間の余白 = ステージ長辺 × これ。国ではなくステージ基準なのは
# 沖縄 (main_h × 0.012) と同じ — 国の縦横比に余白が引きずられると、
# モルディブのような細長い国で枠の横幅が国の 3 倍になる。
INSET_PAD_RATIO = 0.012
# 走査グリッドの分割数 (ステージ長辺基準)。モルディブの枠はアラビア海の
# 空き縦帯にほぼぴったりで、粗いグリッドだと入口を跨いで見落とす。
INSET_SCAN_STEPS = 200

# インセット国は 2.5 倍に拡大して見せる国そのものなので、形だけは 1:10m から
# 取る (1:50m のマルタは 8 点、シンガポールは 9 点しかなく、拡大すると
# 多角形の種明かしになる)。全て島国で陸国境を接しないから、50m 側の
# 共有国境トポロジー (取り直し規則のコメント参照) を壊す心配はない —
# それでもビルド時に検証する。主リングは DP でこの点数まで間引く。
INSET_MAX_RING_PTS = 80
# 三角形への退行をビルドで捕まえる床。モルディブは最大の島でも生 16 点
# しかない (国が環礁の集まり) ので、リング単位ではなく国の総点数で見る。
INSET_MIN_TOTAL_PTS = 20
# thin_rings が収まるまで許容誤差を掛け上げる倍率。DP は誤差の増加で点数が
# 単調に減るので、この幾何級数で必ず止まる。
THIN_TOL_GROWTH = 1.3
# 停止性の前提: simplify_ring は RESOURCE_DP_MIN_PTS 以下のリングに触れない。
# この関係が崩れると「間引けないのに上限超過」で thin_rings が回り続ける。
assert RESOURCE_DP_MIN_PTS < INSET_MAX_RING_PTS

# --- かな変換 ---------------------------------------------------------------
# 機械変換の契約 (world_countries.py KANA_OVERRIDES の冒頭コメントと対):
#   カタカナ→ひらがな、長音「ー」は保持、接尾辞「共和国/王国/連邦」を除去
#   (「国」1 文字は削らない — モンゴル国)、中黒「・」は捨てる。
# 変換後にひらがな以外が残った収録国はエラーで止める —
# 壊れた名前を出荷するのではなく KANA_OVERRIDES への追記を強制する。
KANA_SUFFIXES = ("共和国", "王国", "連邦")


def mechanical_kana(name_ja: str) -> str:
    for suffix in KANA_SUFFIXES:
        if name_ja.endswith(suffix):
            name_ja = name_ja[: -len(suffix)]
            break
    out = []
    for ch in name_ja:
        if ch == "・":
            continue
        o = ord(ch)
        if 0x30A1 <= o <= 0x30F6:  # ァ..ヶ → ぁ..ゖ
            out.append(chr(o - 0x60))
        else:
            out.append(ch)  # 「ー」や漢字はそのまま (漢字は下の検査が捕まえる)
    return "".join(out)


def is_pure_hiragana(s: str) -> bool:
    return bool(s) and all(0x3041 <= ord(c) <= 0x3096 or c == "ー" for c in s)


def kana_for(code: int, name_ja: str) -> str:
    if code in wc.KANA_OVERRIDES:
        return wc.KANA_OVERRIDES[code]
    kana = mechanical_kana(name_ja)
    if not is_pure_hiragana(kana):
        sys.exit(
            f"kana conversion failed for {code} ({name_ja} -> {kana!r}); "
            "add a KANA_OVERRIDES entry in world_countries.py"
        )
    return kana


# 幾何の純関数 (ring_area, polylabel など) は map_geometry.py にあり、
# 日本版パイプラインと共有する。

# --- world-specific transforms ----------------------------------------------

def normalize_dateline(rings):
    """経度スパン > 180° の地物は西半球側を +360 して最小スパンに揃える。

    ロシア (チュクチ)・アメリカ (アリューシャン)・フィジー・NZ (チャタム) は
    生の経度で束ねると bbox が地球一周分になり、ステージ枠も遠隔領土の距離
    判定も壊れる (ステージ表の技術ノート)。シフトで縮まない地物 (南極など
    本当に全周あるもの) はそのまま返す。
    """
    lons = [x for r in rings for x, _ in r]
    span = max(lons) - min(lons)
    if span <= 180.0:
        return rings
    shifted = [[(x + 360.0, y) if x < 0.0 else (x, y) for x, y in r]
               for r in rings]
    slons = [x for r in shifted for x, _ in r]
    if max(slons) - min(slons) >= span:
        return rings
    return shifted


def clip_rings_to_west(rings, lon_max):
    """リング群を経度 lon_max 以西へ切り取る (Sutherland-Hodgman の半平面版)。

    ロシアの錨 (centroid) 探し専用。出荷する形には使わない — 描画は全土のまま
    で、ここで切るのはヨーロッパ側に錨を落とすための一時的な形だけ。
    """
    out = []
    for ring in rings:
        pts = ring[:-1] if ring[0] == ring[-1] else list(ring)
        clipped = []
        for i in range(len(pts)):
            x1, y1 = pts[i]
            x2, y2 = pts[(i + 1) % len(pts)]
            if x1 <= lon_max:
                clipped.append((x1, y1))
            if (x1 <= lon_max) != (x2 <= lon_max):
                t = (lon_max - x1) / (x2 - x1)
                clipped.append((lon_max, y1 + t * (y2 - y1)))
        if len(clipped) >= 3:
            clipped.append(clipped[0])
            if ring_area(clipped) > 0.0:
                out.append(clipped)
    return out


# --- インセット枠の走査 (定数と方針は INSET_SCAN_STEPS 周辺のコメント) -------

def project_pt(pt):
    """lon/lat (y 上向き) -> 走査用の投影座標 (y 下向き、cos 補正)。"""
    return (pt[0] * PROJ_COS, -pt[1])


def unproject_rect(rect):
    """投影座標の矩形 -> lon/lat の [lon0, lat0, lon1, lat1] (y 反転を戻す)。"""
    x0, y0, x1, y1 = rect
    return [x0 / PROJ_COS, -y1, x1 / PROJ_COS, -y0]


def rects_overlap(a, b):
    return a[0] < b[2] and a[2] > b[0] and a[1] < b[3] and a[3] > b[1]


def segs_cross(p1, p2, p3, p4):
    def orient(a, b, c):
        return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
    d1, d2 = orient(p3, p4, p1), orient(p3, p4, p2)
    d3, d4 = orient(p1, p2, p3), orient(p1, p2, p4)
    # 共線で触れるだけの縮退は無視する — 余白と走査の粗さより細かい。
    return (d1 > 0) != (d2 > 0) and (d3 > 0) != (d4 > 0)


def seg_hits_rect(p1, p2, rect):
    x0, y0, x1, y1 = rect
    if max(p1[0], p2[0]) < x0 or min(p1[0], p2[0]) > x1 \
            or max(p1[1], p2[1]) < y0 or min(p1[1], p2[1]) > y1:
        return False
    corners = [(x0, y0), (x1, y0), (x1, y1), (x0, y1), (x0, y0)]
    return any(segs_cross(p1, p2, corners[i], corners[i + 1]) for i in range(4))


def rect_hits_ring(rect, pts, pts_bbox):
    """矩形とリング (投影座標の閉じた点列) が触れるか。

    3 段で漏れなく見る: リングの頂点が矩形内 / 矩形の角がリング内 /
    辺どうしの交差 (頂点も角も入らない斜め横断)。リングは 1 枚の面として
    扱う — 穴の中に枠を置ける判定はしない (保守側)。
    """
    if not rects_overlap(rect, pts_bbox):
        return False
    x0, y0, x1, y1 = rect
    for px, py in pts:
        if x0 <= px <= x1 and y0 <= py <= y1:
            return True
    for cx, cy in ((x0, y0), (x1, y0), (x1, y1), (x0, y1)):
        if point_in_rings(cx, cy, [pts]):
            return True
    return any(seg_hits_rect(pts[i], pts[i + 1], rect) for i in range(len(pts) - 1))


def place_inset_frames(countries, background):
    """インセット国ごとに破線枠 (lon/lat の [lon0, lat0, lon1, lat1]) を選ぶ。

    Swift 側 (WorldDataLoader) はこの枠の中心へ国を scale 倍して置き、枠を
    破線で描き、拡大後の形でタップを判定する。リング座標そのものは実位置の
    まま出す — 地球儀モード (設計 §7) が焼き込みを許さないため、移動は
    ロード時に行う。日本版が沖縄を焼き込むのとの唯一の意図的な違い。
    """
    by_code = {c["code"]: c for c in countries}

    # 障害物: 全収録国 (置く国自身は実位置が空くので除く) + 背景 + 置いた枠。
    # 他ステージの国も避ける — ステージ画面には描かれないが、マイマップは
    # 全収録国を 1 枚に描くので、そこで枠が大陸に重なる。
    obstacles = []  # (owner_code or None, ring_bbox, pts) すべて投影座標
    for c in countries:
        for ring in c["rings"]:
            pts = [project_pt(p) for p in ring]
            obstacles.append((c["code"], bbox_of(pts), pts))
    for entry in background:
        for ring in entry["rings"]:
            pts = [project_pt(p) for p in ring]
            obstacles.append((None, bbox_of(pts), pts))

    frames = {}        # code -> lon/lat frame
    placed_rects = []  # 投影座標。後続のインセットが避ける
    for code in sorted(INSET_SCALE):
        country = by_code[code]
        scale = INSET_SCALE[code]

        # ステージ枠 = メンバーの枠 bbox の連結 (ロシアは europeBbox、
        # 置く国自身は実位置)。これが「今日の枠」で、枠の外には置かない。
        sx0 = sy0 = float("inf")
        sx1 = sy1 = -float("inf")
        for member in countries:
            if member["stage"] != country["stage"]:
                continue
            b = member.get("europeBbox", member["bbox"])
            (mx0, my0), (mx1, my1) = project_pt(b[:2]), project_pt(b[2:])
            sx0, sy0 = min(sx0, mx0), min(sy0, my1)  # y 反転で上下が入れ替わる
            sx1, sy1 = max(sx1, mx1), max(sy1, my0)
        stage_w, stage_h = sx1 - sx0, sy1 - sy0

        (bx0, by0), (bx1, by1) = project_pt(country["bbox"][:2]), project_pt(country["bbox"][2:])
        by0, by1 = min(by0, by1), max(by0, by1)
        w, h = (bx1 - bx0) * scale, (by1 - by0) * scale
        pad = INSET_PAD_RATIO * max(stage_w, stage_h)
        fw, fh = w + 2 * pad, h + 2 * pad
        if fw > stage_w or fh > stage_h:
            sys.exit(f"inset frame for {code} ({fw:.1f}x{fh:.1f}) does not fit "
                     f"its stage frame ({stage_w:.1f}x{stage_h:.1f}) - "
                     "lower INSET_SCALE or revisit the stage split")

        # 実位置の中心に近い順で空き候補を試す (条件 2)。
        true_cx, true_cy = (bx0 + bx1) / 2, (by0 + by1) / 2
        step = max(stage_w, stage_h) / INSET_SCAN_STEPS
        near = [ob for ob in obstacles
                if ob[0] != code and rects_overlap((sx0, sy0, sx1, sy1), ob[1])]
        candidates = []
        cy = sy0 + fh / 2
        while cy <= sy1 - fh / 2:
            cx = sx0 + fw / 2
            while cx <= sx1 - fw / 2:
                candidates.append((math.hypot(cx - true_cx, cy - true_cy), cx, cy))
                cx += step
            cy += step
        candidates.sort()

        chosen = None
        for _, cx, cy in candidates:
            rect = (cx - fw / 2, cy - fh / 2, cx + fw / 2, cy + fh / 2)
            if any(rects_overlap(rect, r) for r in placed_rects):
                continue
            if any(rect_hits_ring(rect, pts, rb) for _, rb, pts in near):
                continue
            chosen = rect
            break
        if chosen is None:
            sys.exit(f"no free water inside the stage frame for inset {code} - "
                     "upstream data changed, or the scale is too big")

        placed_rects.append(chosen)
        frames[code] = [round(v, COORD_DECIMALS) for v in unproject_rect(chosen)]
    return frames


def prune_rings(code, rings, min_area=MIN_RING_AREA_DEG2):
    """遠隔領土と岩礁を刈る (冒頭の定数と例外表を参照)。

    (残すリング, 距離で外した遠隔リング) を返す。どちらも大きい順。
    遠隔リングは捨てずに呼び出し側が背景へ回す — 仏領ギアナを消すと南米に
    嘘の海岸線ができる (ステージ表の技術ノート「属領は背景描画」)。
    床面積未満の岩礁と飛び地の穴だけは黙って捨てる。
    """
    scored = sorted(((ring_area(r), r) for r in rings), key=lambda t: -t[0])
    main_ring = scored[0][1]
    candidates = [(area, ring) for area, ring in scored[1:]
                  if area >= min_area]

    if code in KEEP_ALL_RINGS:
        return [main_ring] + [ring for _, ring in candidates], []

    max_gap = GAP_OVERRIDES.get(code, MAX_RING_GAP_DEG)
    kept = [main_ring]
    kept_boxes = [bbox_of(main_ring)]
    pending = [(area, ring, bbox_of(ring)) for area, ring in candidates]
    grew = True
    while grew and pending:
        grew = False
        rest = []
        for area, ring, box in pending:
            if any(bbox_gap(box, kb) <= max_gap for kb in kept_boxes):
                kept.append(ring)
                kept_boxes.append(box)
                grew = True
            else:
                rest.append((area, ring, box))
        pending = rest
    pruned = [ring for _, ring, _ in pending]
    return (sorted(kept, key=lambda r: -ring_area(r)),
            sorted(pruned, key=lambda r: -ring_area(r)))


def simplify_ring(ring, tolerance):
    """Douglas-Peucker (閉リング版)。始点と最遠点を錨に両弧を別々に間引く。"""
    if len(ring) <= RESOURCE_DP_MIN_PTS:
        return ring
    pts = ring[:-1]
    x0, y0 = pts[0]
    far = max(range(1, len(pts)),
              key=lambda i: (pts[i][0] - x0) ** 2 + (pts[i][1] - y0) ** 2)
    tol_sq = tolerance * tolerance

    def dp(seq):
        keep = [False] * len(seq)
        keep[0] = keep[-1] = True
        stack = [(0, len(seq) - 1)]
        while stack:
            i0, i1 = stack.pop()
            if i1 - i0 < 2:
                continue
            ax, ay = seq[i0]
            bx, by = seq[i1]
            best_d, best_i = -1.0, -1
            for i in range(i0 + 1, i1):
                d = dist_to_segment_sq(seq[i][0], seq[i][1], ax, ay, bx, by)
                if d > best_d:
                    best_d, best_i = d, i
            if best_d > tol_sq:
                keep[best_i] = True
                stack.append((i0, best_i))
                stack.append((best_i, i1))
        return [seq[i] for i in range(len(seq)) if keep[i]]

    arc1 = dp(pts[: far + 1])
    arc2 = dp(pts[far:] + [pts[0]])
    out = arc1[:-1] + arc2[:-1]
    if len(out) < 3:
        return ring
    out.append(out[0])
    return out


def thin_rings(rings, base_tol, max_pts):
    """全リングを DP で間引き、最大点数に収まるまで許容誤差を上げる。"""
    tol = base_tol
    out = [simplify_ring(r, tol) for r in rings]
    while max(len(r) for r in out) > max_pts:
        tol *= THIN_TOL_GROWTH
        out = [simplify_ring(r, tol) for r in rings]
    return out


def rounded_rings(rings):
    out = []
    for ring in rings:
        r = [[round(x, COORD_DECIMALS), round(y, COORD_DECIMALS)]
             for x, y in ring]
        # 丸めで始終点がずれることは無いはずだが、Swift 側に開いたリングを
        # 見せない保険は日本版と同じく残す。
        if r[0] != r[-1]:
            r.append(list(r[0]))
        out.append(r)
    return out


# --- pipeline ---------------------------------------------------------------

def load_features(path):
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
    out = []
    for feat in data["features"]:
        geom = feat["geometry"]
        if geom is None:
            continue
        polys = (geom["coordinates"] if geom["type"] == "MultiPolygon"
                 else [geom["coordinates"]])
        rings = []
        for poly in polys:
            for ring in poly:
                r = [(float(x), float(y)) for x, y in ring]
                if r[0] != r[-1]:
                    r.append(r[0])
                if len(r) >= 4:
                    rings.append(r)
        if rings:
            out.append({"props": feat["properties"], "rings": rings})
    return out


def resolve_code(props):
    """地物の ISO 3166-1 numeric を返す。解決できない地物は None (背景行き)。"""
    adm0 = props.get("ADM0_A3")
    if adm0 in HAND_RESOLVED_N3:
        return HAND_RESOLVED_N3[adm0]
    try:
        code = int(props.get("ISO_N3"))
    except (TypeError, ValueError):
        return None
    return code if code > 0 else None


def ensure_10m(path):
    """1:10m の生データを確保する。あればそのまま使い、無ければ落としてくる。

    落とせない環境では止めて手順を示す — 黙って 50m の三角形に
    フォールバックすると、インセットの意味が静かに壊れるため。
    """
    if os.path.exists(path):
        return
    print(f"downloading {RAW_10M_SRC} (one-time, ~13MB)...")
    part = path + ".part"
    try:
        import urllib.request
        with urllib.request.urlopen(NE_10M_URL, timeout=300) as resp:
            with open(part, "wb") as out:
                out.write(resp.read())
        os.replace(part, path)
    except Exception as exc:
        if os.path.exists(part):
            os.remove(part)
        sys.exit(
            f"could not download {RAW_10M_SRC} ({exc}).\n"
            "Fetch it manually and re-run:\n"
            f"    curl -sL -o {RAW_10M_SRC} {NE_10M_URL}"
        )


def shared_vertex_set(feats):
    """2 つ以上の地物が使っている頂点の集合。

    mapshaper は共有国境を 1 本の折れ線として簡略化するので、陸の国境は
    両側の地物にまったく同じ座標で現れる。これが「国境を接するか」の
    機械判定になる (島国は 0 個)。
    """
    owner = {}
    shared = set()
    for idx, feat in enumerate(feats):
        for ring in feat["rings"]:
            for pt in ring:
                prev = owner.setdefault(pt, idx)
                if prev != idx:
                    shared.add(pt)
    return shared


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    src = os.path.join(here, SRC)
    raw_src = os.path.join(here, RAW_SRC)
    raw_10m = os.path.join(here, RAW_10M_SRC)
    if not os.path.exists(src):
        sys.exit(f"missing {SRC} - run the mapshaper step first (module docstring)")
    if not os.path.exists(raw_src):
        sys.exit(f"missing {RAW_SRC} - download it first (module docstring)")
    ensure_10m(raw_10m)

    feats = load_features(src)

    # 収録国: コード -> 地物。属領がコードを名乗る衝突は主権国家側を採る。
    recorded_feats = {}
    background_feats = []
    for feat in feats:
        code = resolve_code(feat["props"])
        if code in wc.STAGE_OF_COUNTRY:
            if is_sovereign(feat["props"], code):
                if code in recorded_feats:
                    sys.exit(f"two sovereign features claim code {code}")
                recorded_feats[code] = feat
            else:
                background_feats.append(feat)  # 例: アシュモア諸島 (036)
        else:
            background_feats.append(feat)

    missing = sorted(set(wc.STAGE_OF_COUNTRY) - set(recorded_feats))
    if missing:
        sys.exit(f"source is missing recorded country codes: {missing}")

    # 取り直し用の生データ (収録国ぶんだけ引ければよい)
    raw_by_code = {}
    for feat in load_features(raw_src):
        code = resolve_code(feat["props"])
        if code in wc.STAGE_OF_COUNTRY and is_sovereign(feat["props"], code):
            raw_by_code[code] = feat

    # インセット国専用の 1:10m データ (INSET_MAX_RING_PTS のコメント参照)
    feats_10m = {}
    for feat in load_features(raw_10m):
        code = resolve_code(feat["props"])
        if code in wc.INSET_COUNTRIES and is_sovereign(feat["props"], code):
            feats_10m[code] = feat
    missing_10m = sorted(wc.INSET_COUNTRIES - set(feats_10m))
    if missing_10m:
        sys.exit(f"{RAW_10M_SRC} is missing inset countries: {missing_10m}")

    shared = shared_vertex_set(feats)

    countries = []
    total_pts = 0
    speck_rings = 0
    resourced = []
    pruned_entries = []  # (地物の ADMIN 名, 丸めたリング群) — 背景へ回す
    ring_counts = {}
    for code in sorted(recorded_feats):
        feat = recorded_feats[code]
        props = feat["props"]
        name_ja = props.get("NAME_JA")
        if not name_ja:
            sys.exit(f"NAME_JA missing for recorded country {code}")

        rings = normalize_dateline(feat["rings"])
        main_pts = len(max(rings, key=ring_area))
        # 頂点照合は読み込んだままの座標 (feat["rings"]) で行う。shared も
        # 同じ生座標で作ってあり、正規化で +360 した座標では完全一致が壊れる。
        touches_border = any(pt in shared for r in feat["rings"] for pt in r)

        if code in wc.INSET_COUNTRIES:
            # インセット国は 1:10m から形を取る (INSET_MAX_RING_PTS のコメント)。
            # 島国であることが前提なので、上流データが変わって陸国境が
            # 生えたら黙って進めずここで止まる。
            if touches_border:
                sys.exit(f"inset country {code} shares a land border in {SRC}; "
                         "resourcing from 10m would tear the shared topology")
            source_rings = normalize_dateline(feats_10m[code]["rings"])
            max_ring_pts = INSET_MAX_RING_PTS
        elif (main_pts < RESOURCE_MIN_MAIN_PTS and not touches_border
                and code in raw_by_code):
            # 三角形に潰れた島国は生データから形を取り直す (冒頭のコメント)。
            source_rings = normalize_dateline(raw_by_code[code]["rings"])
            max_ring_pts = None
        else:
            source_rings = None
            max_ring_pts = None

        if source_rings is not None:
            floor = (ring_area(max(source_rings, key=ring_area))
                     * RESOURCE_RING_AREA_RATIO)
            kept, pruned = prune_rings(code, source_rings, min_area=floor)
            gx0, gy0, gx1, gy1 = bbox_of([p for r in kept for p in r])
            tol = RESOURCE_DP_RATIO * max(gx1 - gx0, gy1 - gy0)
            if max_ring_pts is None:
                kept = [simplify_ring(r, tol) for r in kept]
                pruned = [simplify_ring(r, tol) for r in pruned]
            else:
                kept = thin_rings(kept, tol, max_ring_pts)
                pruned = thin_rings(pruned, tol, max_ring_pts) if pruned else []
            speck_rings += len(source_rings) - len(kept) - len(pruned)
            resourced.append(code)
        else:
            kept, pruned = prune_rings(code, rings)
            speck_rings += len(rings) - len(kept) - len(pruned)

        if (code in wc.INSET_COUNTRIES
                and sum(len(r) for r in kept) < INSET_MIN_TOTAL_PTS):
            sys.exit(f"inset country {code} has no silhouette "
                     f"({sum(len(r) for r in kept)} pts) - upstream data changed?")

        if pruned:
            pruned_entries.append((props["ADMIN"], rounded_rings(pruned)))

        # 面積重心はここでは使えない: 群島国 (フィリピン等) や凹形状の国
        # (クロアチア等) で海に落ちる。ラベル・エフェクトの錨は必ず自国の
        # 中に要るので、平均ではなく保証つきの内部点を探す。
        # ロシアだけはウラル線以西で探す: ひがしヨーロッパのステージ枠は
        # europeBbox (下記) までなので、全土の錨 (中央シベリア) だと正解の
        # ポップも特産絵文字も VoiceOver の位置も枠の外に出てしまう。
        # 切るのは錨探しの一時的な形だけで、出荷するリングは全土のまま。
        anchor_rings = kept
        if code == RUSSIA:
            anchor_rings = clip_rings_to_west(kept, URAL_LON)
            if not anchor_rings:
                sys.exit("russia has no area west of the ural line - "
                         "upstream data changed?")
        cx, cy = pole_of_inaccessibility(anchor_rings)
        if not point_in_rings(cx, cy, kept):
            sys.exit(f"centroid outside shape for code {code} ({name_ja})")

        rounded = rounded_rings(kept)
        total_pts += sum(len(r) for r in rounded)
        ring_counts[code] = len(rounded)

        bx0, by0, bx1, by1 = bbox_of([p for r in rounded for p in r])
        # 正規化後の最小スパンは実在の国なら必ず 180° 未満に収まる。
        # ここで落ちたら上流データの変化なので、黙って直さず人が見る。
        if not 0.0 < bx1 - bx0 < 180.0:
            sys.exit(f"bbox span not normalized for code {code}: {bx1 - bx0}")

        # かなも表示名から引く。将来カタカナだけの NAMEJA_OVERRIDES が入った
        # とき、ひらがな検査が旧名ではなく実際に見せる名前に掛かるように。
        display_name = wc.NAMEJA_OVERRIDES.get(code, name_ja)
        entry = {
            "code": code,
            "nameJa": display_name,
            "kana": kana_for(code, display_name),
            "stage": wc.STAGE_OF_COUNTRY[code],
            "bbox": [round(v, COORD_DECIMALS) for v in (bx0, by0, bx1, by1)],
            "centroid": [round(cx, COORD_DECIMALS), round(cy, COORD_DECIMALS)],
            "rings": rounded,
        }

        if code == RUSSIA:
            # ひがしヨーロッパの枠はロシアのヨーロッパ側だけで計算する
            # (全土だとベーリング海峡まで伸びてモルドバが 13pt になる)。
            # シベリアは枠外へはみ出す背景として描く — 枠と描画の分離。
            west = [p for r in kept for p in r if p[0] < URAL_LON]
            if not west:
                sys.exit("russia has no vertex west of the ural line - "
                         "upstream data changed?")
            wx0, wy0, _, wy1 = bbox_of(west)
            # 領土はウラル線をまたいで続くので、東端は線そのもの。
            entry["europeBbox"] = [round(wx0, COORD_DECIMALS),
                                   round(wy0, COORD_DECIMALS),
                                   URAL_LON,
                                   round(wy1, COORD_DECIMALS)]

        countries.append(entry)

    # 背景: 属領・収録外の国・南極、それに収録国から距離で外した遠隔領土
    # (仏領ギアナ・スバールバル等)。コード無しの海岸線 (海にすると嘘になる)。
    # 属領そのものへの距離刈りはしない — 元々 1 地物 1 領土で、刈る対象の
    # 「本土」概念が無い。岩礁の面積刈りだけ同じ規則で通す。
    # 並びは地物名 (ADMIN) で固定して diff を安定させる。
    bg_entries = list(pruned_entries)
    for feat in background_feats:
        rings = normalize_dateline(feat["rings"])
        scored = sorted(((ring_area(r), r) for r in rings), key=lambda t: -t[0])
        kept = [scored[0][1]] + [r for a, r in scored[1:]
                                 if a >= MIN_RING_AREA_DEG2]
        bg_entries.append((feat["props"]["ADMIN"], rounded_rings(kept)))
    bg_entries.sort(key=lambda e: e[0])
    background = [{"rings": rings} for _, rings in bg_entries]
    bg_pts = sum(len(r) for _, rings in bg_entries for r in rings)

    # --- ビルド時の健全性ガード (Task 1 レビューでパイプライン側に置いた) ---
    if len(countries) != len(wc.STAGE_OF_COUNTRY):
        sys.exit(f"recorded count drifted: {len(countries)} != "
                 f"{len(wc.STAGE_OF_COUNTRY)}")
    if set(INSET_SCALE) != wc.INSET_COUNTRIES:
        sys.exit("INSET_SCALE and world_countries.INSET_COUNTRIES disagree")
    recorded_codes = {c["code"] for c in countries}
    if not wc.INSET_COUNTRIES <= recorded_codes:
        sys.exit("inset country missing from recorded output")

    frames = place_inset_frames(countries, background)

    out = {
        "countries": countries,
        "background": background,
        "insets": [{"code": code, "scale": INSET_SCALE[code],
                    "frame": frames[code]}
                   for code in sorted(INSET_SCALE)],
    }

    dst = os.path.join(here, DST)
    with open(dst, "w", encoding="utf-8") as fh:
        json.dump(out, fh, ensure_ascii=False, separators=(",", ":"))

    size = os.path.getsize(dst)
    min_rings = min(ring_counts, key=ring_counts.get)
    max_rings = max(ring_counts, key=ring_counts.get)
    print(f"wrote {DST}")
    print(f"  recorded   : {len(countries)} countries, {total_pts} pts "
          f"(dropped {speck_rings} speck rings)")
    print(f"  resourced  : {len(resourced)} island countries from raw "
          f"({sorted(resourced)})")
    inset_pts = {c["code"]: [len(r) for r in c["rings"]]
                 for c in countries if c["code"] in wc.INSET_COUNTRIES}
    print("  inset 10m  : " + "; ".join(f"{code} {pts}"
                                        for code, pts in sorted(inset_pts.items())))
    print(f"  to backgrnd: {sum(len(r) for _, r in pruned_entries)} pruned "
          f"remote rings from {len(pruned_entries)} countries")
    print(f"  background : {len(background)} features, {bg_pts} pts")
    print(f"  rings      : min {ring_counts[min_rings]} (code {min_rings}), "
          f"max {ring_counts[max_rings]} (code {max_rings})")
    for code in sorted(INSET_SCALE):
        print(f"  inset frame: {code} x{INSET_SCALE[code]} -> {frames[code]}")
    print(f"  size       : {size / 1024:.1f} KB")
    if size > 400 * 1024:
        # 超過は報告して人が判断する。黙って簡略化率を上げない。
        print("  WARNING: over the 400 KB budget")


if __name__ == "__main__":
    main()
