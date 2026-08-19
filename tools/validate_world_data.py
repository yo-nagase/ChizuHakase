#!/usr/bin/env python3
"""WorldShapes.json の健全性チェック (世界アトラス版).

build_world_map_data.py で再生成するたびに実行する。落ちたらコミットしない。

Run from tools/:
    python3 validate_world_data.py [path/to/WorldShapes.json]

引数を省略するとスクリプト位置基準で ../ChizuHakase/Resources/WorldShapes.json
を見る (CWD に依存しない)。検査はすべて assert で、失敗すれば非ゼロ終了
(assert が剥がれる -O での実行は冒頭で拒否する)。
ファイルサイズ超過だけは警告に留める — 黙って簡略化率を上げず、人が判断する
(build_world_map_data.py の WARNING と同じ扱い)。
"""

from __future__ import annotations

import json
import os
import sys
from collections import Counter

import world_countries as wc

DEFAULT_DST = os.path.join("..", "ChizuHakase", "Resources", "WorldShapes.json")

# build_world_map_data.py の COORD_DECIMALS / INSET_MIN_TOTAL_PTS /
# URAL_LON / サイズ予算と同じ値。生成側の契約をこちらでも言い直して、
# 片側だけ変わったらここで気づけるようにする。
COORD_DECIMALS = 4
INSET_MIN_TOTAL_PTS = 20
URAL_LON = 60.0
SIZE_BUDGET = 400 * 1024


def is_pure_hiragana(s: str) -> bool:
    # build_world_map_data.py の同名関数と同じ規則 (長音「ー」だけ許す)
    return bool(s) and all(0x3041 <= ord(c) <= 0x3096 or c == "ー" for c in s)


def check_decimals(values, where):
    # 丸め漏れの桁はファイルを太らせ diff を揺らすだけ (COORD_DECIMALS の契約)
    for v in values:
        assert round(v, COORD_DECIMALS) == v, (where, v, "座標が 4 桁を超える")


def check_rings(rings, where):
    assert rings, (where, "リングが無い")
    for ring in rings:
        assert len(ring) >= 4, (where, "リングが退化している")
        assert ring[0] == ring[-1], (where, "リングが閉じていない")
        check_decimals((v for pt in ring for v in pt), where)


def main():
    # -O は assert を剥がす — 通っても何も検査していない偽の合格になる
    if sys.flags.optimize:
        sys.exit("assert が消えるので -O では実行しない")

    here = os.path.dirname(os.path.abspath(__file__))
    path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, DEFAULT_DST)
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)

    countries = data["countries"]
    recorded = [c for c in countries if "stage" in c]
    # 数の比較では「1 国消えて別の 1 国が湧いた」相殺ドリフトが見えない。
    # 集合差で両方向を名指しする
    recorded_codes = {c["code"] for c in recorded}
    master_codes = set(wc.STAGE_OF_COUNTRY)
    assert recorded_codes == master_codes, \
        ("出力に無い", sorted(master_codes - recorded_codes),
         "マスタに無い", sorted(recorded_codes - master_codes))

    # 昇順・重複なしは Swift ローダが辞書化・二分探索で前提にしてよい契約
    codes = [c["code"] for c in countries]
    assert codes == sorted(codes), "countries がコード昇順でない"
    dupes = sorted(code for code, n in Counter(codes).items() if n > 1)
    assert not dupes, ("国コードが重複している", dupes)

    for c in recorded:
        code = c["code"]
        check_rings(c["rings"], code)
        assert c["nameJa"], (code, "nameJa が空")
        assert is_pure_hiragana(c["kana"]), (code, c["kana"], "かなが純ひらがなでない")
        assert 0 <= c["stage"] < len(wc.STAGES), (code, c["stage"], "ステージ番号が範囲外")
        assert c["stage"] == wc.STAGE_OF_COUNTRY.get(code), \
            (code, c["stage"], "ステージがマスタと食い違う")

        x0, y0, x1, y1 = c["bbox"]
        # 正規化後の最小スパンは実在の国なら必ず 180° 未満に収まる。
        # ここで落ちたら上流データの変化 (build と同じ契約)
        assert 0 < x1 - x0 < 180, (code, "日付変更線の正規化漏れ")
        xs = [x for r in c["rings"] for x, _ in r]
        ys = [y for r in c["rings"] for _, y in r]
        assert [x0, y0, x1, y1] == [min(xs), min(ys), max(xs), max(ys)], \
            (code, "bbox がリングの実範囲と食い違う")
        check_decimals(c["bbox"], code)
        check_decimals(c["centroid"], code)

    used = {c["stage"] for c in recorded}
    assert used == set(range(len(wc.STAGES))), \
        ("空のステージがある", sorted(set(range(len(wc.STAGES))) - used))

    code_set = set(codes)
    assert wc.INSET_COUNTRIES <= code_set, "インセット対象が収録に無い"
    assert 392 in code_set, "日本が世界地図にいない"
    assert 158 in code_set, "台湾の裁定が反映されていない"
    assert 48 not in code_set, "バーレーンは収録外の裁定"

    # ひがしヨーロッパの枠はロシアのヨーロッパ側だけで計算する契約。
    # 持ち主はロシアただ 1 国、東端はウラル線 (build の URAL_LON) そのもの
    euro = [c for c in countries if "europeBbox" in c]
    assert [c["code"] for c in euro] == [643], \
        ("europeBbox の持ち主がロシアだけでない", [c["code"] for c in euro])
    ex0, ey0, ex1, ey1 = euro[0]["europeBbox"]
    assert ex1 == URAL_LON, ("europeBbox の東端がウラル線でない", ex1)
    assert ex0 < ex1 and ey0 < ey1, ("europeBbox が潰れている", euro[0]["europeBbox"])
    check_decimals(euro[0]["europeBbox"], 643)

    # 背景はコード無しの海岸線。持ってよいキーは rings だけ (白リスト) —
    # 収録国に見えるメタデータの混入をキー単位で締め出す
    for i, entry in enumerate(data["background"]):
        assert set(entry) == {"rings"}, \
            (f"background[{i}]", "rings 以外のキーがある", sorted(set(entry) - {"rings"}))
        check_rings(entry["rings"], f"background[{i}]")

    inset_codes = [i["code"] for i in data["insets"]]
    assert len(inset_codes) == len(set(inset_codes)) \
        and set(inset_codes) == wc.INSET_COUNTRIES, \
        ("insets がマスタと食い違う", inset_codes)
    for inset in data["insets"]:
        assert inset["scale"] > 1, (inset["code"], "縮小するインセットは無意味")
    by_code = {c["code"]: c for c in countries}
    for code in sorted(wc.INSET_COUNTRIES):
        # 拡大して見せる国が三角形では種明かしになる (build の INSET_MIN_TOTAL_PTS)
        pts = sum(len(r) for r in by_code[code]["rings"])
        assert pts >= INSET_MIN_TOTAL_PTS, (code, pts, "インセット国の輪郭が痩せている")

    size = os.path.getsize(path)
    if size > SIZE_BUDGET:
        print(f"WARNING: {size / 1024:.1f} KB > {SIZE_BUDGET // 1024} KB budget - "
              "黙って簡略化率を上げず、報告して判断を仰ぐこと")

    print(f"OK: {len(recorded)} countries recorded")


if __name__ == "__main__":
    main()
