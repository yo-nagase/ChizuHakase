#!/usr/bin/env python3
"""GeoJSON -> WorldShapes.json (世界アトラス版。日本版 build_map_data.py の姉妹編).

ne_50m_simplified.geojson (mapshaper 出力) と world_countries.py (収録国マスタ)
を突き合わせ、世界地図リソースを出す。国境を接しない小国の形は生データ
ne_50m_countries.geojson から取り直すので、両方のファイルが要る。

日本版との最大の違い: 座標は緯度経度のまま出す。地球儀モード (設計文書
2026-08-16 §7) が平面への焼き込みを許さないため、投影は実行時に行う。

Run from tools/:
    npx mapshaper ne_50m_countries.geojson \
        -simplify visvalingam 4% keep-shapes -clean \
        -o ne_50m_simplified.geojson format=geojson
    python3 build_world_map_data.py
    mv WorldShapes.json ../ChizuHakase/Resources/
"""

from __future__ import annotations

import heapq
import json
import math
import os
import sys

import world_countries as wc

SRC = "ne_50m_simplified.geojson"
RAW_SRC = "ne_50m_countries.geojson"
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

# インセット拡大の倍率 (裁定 2026-08-19 の 4 カ国)。配置は Swift 側が決める。
# 倍率は日本版の沖縄 1.6 より強い 2.5 — どの国も単独では 10pt に届かないため。
# 実機で見て調整する暫定値。
INSET_SCALE = {702: 2.5, 470: 2.5, 462: 2.5, 242: 2.5}

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


# --- geometry helpers (日本版と同じ純関数) ----------------------------------

def ring_area(ring):
    """Unsigned shoelace area."""
    s = 0.0
    for i in range(len(ring) - 1):
        x1, y1 = ring[i]
        x2, y2 = ring[i + 1]
        s += x1 * y2 - x2 * y1
    return abs(s) * 0.5


def bbox_of(points):
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    return [min(xs), min(ys), max(xs), max(ys)]


def bbox_gap(a, b):
    """Shortest distance between two axis-aligned bboxes (0 if they overlap)."""
    dx = max(a[0] - b[2], b[0] - a[2], 0.0)
    dy = max(a[1] - b[3], b[1] - a[3], 0.0)
    return math.hypot(dx, dy)


def point_in_rings(px, py, rings):
    """Even-odd containment, matching Path.contains(_:eoFill: true) on iOS."""
    inside = False
    for ring in rings:
        for i in range(len(ring) - 1):
            x1, y1 = ring[i]
            x2, y2 = ring[i + 1]
            if (y1 > py) != (y2 > py):
                t = (py - y1) / (y2 - y1)
                if px < x1 + t * (x2 - x1):
                    inside = not inside
    return inside


def dist_to_segment_sq(px, py, x1, y1, x2, y2):
    dx, dy = x2 - x1, y2 - y1
    if dx == 0.0 and dy == 0.0:
        return (px - x1) ** 2 + (py - y1) ** 2
    t = ((px - x1) * dx + (py - y1) * dy) / (dx * dx + dy * dy)
    t = max(0.0, min(1.0, t))
    ox, oy = x1 + t * dx, y1 + t * dy
    return (px - ox) ** 2 + (py - oy) ** 2


def signed_distance(px, py, rings):
    """Distance to the nearest edge; positive inside, negative outside."""
    best = float("inf")
    for ring in rings:
        for i in range(len(ring) - 1):
            best = min(best, dist_to_segment_sq(px, py, *ring[i], *ring[i + 1]))
    d = math.sqrt(best)
    return d if point_in_rings(px, py, rings) else -d


def pole_of_inaccessibility(rings, precision_ratio=0.002):
    """内部で最も縁から遠い点 (Mapbox polylabel の quadtree 版)。

    面積重心はここでは使えない: 群島国 (フィリピン等) や凹形状の国
    (クロアチア等) で海に落ちる。ラベル・エフェクトの錨は必ず自国の中に
    要るので、平均ではなく保証つきの内部点を探す。日本版と同じ実装。
    """
    x0, y0, x1, y1 = bbox_of([p for r in rings for p in r])
    w, h = x1 - x0, y1 - y0
    cell = min(w, h)
    if cell == 0:
        return (x0, y0)

    precision = max(w, h) * precision_ratio
    half = cell / 2.0

    def potential(cx, cy, hh):
        return signed_distance(cx, cy, rings) + hh * math.sqrt(2)

    queue = []
    counter = 0
    best_x = x0 + w / 2.0
    best_y = y0 + h / 2.0
    best_d = signed_distance(best_x, best_y, rings)

    cy = y0 + half
    while cy < y1 + half:
        cx = x0 + half
        while cx < x1 + half:
            d = signed_distance(cx, cy, rings)
            if d > best_d:
                best_d, best_x, best_y = d, cx, cy
            heapq.heappush(queue, (-(d + half * math.sqrt(2)), counter, cx, cy, half))
            counter += 1
            cx += cell
        cy += cell

    while queue:
        neg_pot, _, cx, cy, hh = heapq.heappop(queue)
        if -neg_pot - best_d <= precision:
            break
        hh /= 2.0
        for ox, oy in ((-hh, -hh), (hh, -hh), (-hh, hh), (hh, hh)):
            nx, ny = cx + ox, cy + oy
            d = signed_distance(nx, ny, rings)
            if d > best_d:
                best_d, best_x, best_y = d, nx, ny
            heapq.heappush(queue, (-potential(nx, ny, hh), counter, nx, ny, hh))
            counter += 1

    return (best_x, best_y)


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
    if not os.path.exists(src):
        sys.exit(f"missing {SRC} - run the mapshaper step first (module docstring)")
    if not os.path.exists(raw_src):
        sys.exit(f"missing {RAW_SRC} - download it first (module docstring)")

    feats = load_features(src)

    # 収録国: コード -> 地物。属領がコードを名乗る衝突は主権国家側を採る。
    recorded_feats = {}
    background_feats = []
    for feat in feats:
        code = resolve_code(feat["props"])
        if code in wc.STAGE_OF_COUNTRY:
            if (feat["props"].get("TYPE") in SOVEREIGN_TYPES
                    or code in SOVEREIGN_DESPITE_TYPE):
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
        if code in wc.STAGE_OF_COUNTRY and (
                feat["props"].get("TYPE") in SOVEREIGN_TYPES
                or code in SOVEREIGN_DESPITE_TYPE):
            raw_by_code[code] = feat

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
        touches_border = any(pt in shared for r in feat["rings"] for pt in r)

        if main_pts < RESOURCE_MIN_MAIN_PTS and not touches_border and code in raw_by_code:
            # 三角形に潰れた島国は生データから形を取り直す (冒頭のコメント)。
            raw_rings = normalize_dateline(raw_by_code[code]["rings"])
            floor = (ring_area(max(raw_rings, key=ring_area))
                     * RESOURCE_RING_AREA_RATIO)
            kept, pruned = prune_rings(code, raw_rings, min_area=floor)
            gx0, gy0, gx1, gy1 = bbox_of([p for r in kept for p in r])
            tol = RESOURCE_DP_RATIO * max(gx1 - gx0, gy1 - gy0)
            kept = [simplify_ring(r, tol) for r in kept]
            pruned = [simplify_ring(r, tol) for r in pruned]
            speck_rings += len(raw_rings) - len(kept) - len(pruned)
            resourced.append(code)
        else:
            kept, pruned = prune_rings(code, rings)
            speck_rings += len(rings) - len(kept) - len(pruned)

        if pruned:
            pruned_entries.append((props["ADMIN"], rounded_rings(pruned)))

        cx, cy = pole_of_inaccessibility(kept)
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

        entry = {
            "code": code,
            "nameJa": wc.NAMEJA_OVERRIDES.get(code, name_ja),
            "kana": kana_for(code, name_ja),
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

    out = {
        "countries": countries,
        "background": background,
        "insets": [{"code": code, "scale": INSET_SCALE[code]}
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
    print(f"  to backgrnd: {sum(len(r) for _, r in pruned_entries)} pruned "
          f"remote rings from {len(pruned_entries)} countries")
    print(f"  background : {len(background)} features, {bg_pts} pts")
    print(f"  rings      : min {ring_counts[min_rings]} (code {min_rings}), "
          f"max {ring_counts[max_rings]} (code {max_rings})")
    print(f"  insets     : {sorted(INSET_SCALE)}")
    print(f"  size       : {size / 1024:.1f} KB")
    if size > 400 * 1024:
        # 超過は報告して人が判断する。黙って簡略化率を上げない。
        print("  WARNING: over the 400 KB budget")


if __name__ == "__main__":
    main()
