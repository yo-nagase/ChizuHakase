#!/usr/bin/env python3
"""収録国 → WorldCards.json (国旗カードのみ。SpecialtyCards.json の世界版).

設計 (docs/plans/2026-08-16-world-atlas-design.md §5): 1 国 2 枚のうち、
まず国旗カード ({code}-1) だけを配る。オリジナル ({code}-2) は手描きが
できてから足す (P6)。国旗は絵文字 (ISO alpha-2 由来の地域指標記号) なので
画像もライセンス表記も要らない — 描くのは端末のフォント。

入力は 2 つで、どちらも既にあるものから引く:
- ../ChizuHakase/Resources/WorldShapes.json — code / kana / nameJa の正本。
  国名の綴りをここで二重管理しない (再変換すると 2 つの正本ができる)。
- ne_50m_countries.geojson — ISO alpha-2 (国旗絵文字の材料)。数字コードと
  同じく Natural Earth を出典にする。

Run from tools/ (WorldShapes.json を再生成したら続けてこれも):
    python3 build_world_cards.py

出力は ../ChizuHakase/Resources/WorldCards.json に直接書く。地図と違い
中間ファイルが無いので mv の段は要らない。決定的 (同じ入力 → 同じバイト列)。
"""

from __future__ import annotations

import json
import os
import re
import sys

from build_world_map_data import is_sovereign, load_features, resolve_code

GEO_SRC = "ne_50m_countries.geojson"
SHAPES = os.path.join("..", "ChizuHakase", "Resources", "WorldShapes.json")
DST = os.path.join("..", "ChizuHakase", "Resources", "WorldCards.json")

# ISO_A2 が使えない地物の手動解決 (build_world_map_data.HAND_RESOLVED_N3 と
# 同じ流儀)。フランス・ノルウェーは -99、台湾は "CN-TW"。ISO_A2_EH からの
# 自動復元はしない — numeric 側と同じく、属領がコードを名乗るフィールドを
# 信用しない約束。ここに無い不正値が出たらエラーで止めて追記を強制する。
HAND_RESOLVED_A2 = {158: "TW", 250: "FR", 578: "NO"}

ALPHA2_RE = re.compile(r"^[A-Z]{2}$")


def flag_emoji(alpha2: str) -> str:
    """ISO alpha-2 → 地域指標記号 2 文字 (例: JP → 🇯🇵)。"""
    return "".join(chr(0x1F1E6 + ord(c) - ord("A")) for c in alpha2)


def has_kanji(s: str) -> bool:
    return any(0x4E00 <= ord(c) <= 0x9FFF for c in s)


def alpha2_by_code(path: str) -> dict[int, str]:
    out = {}
    for feat in load_features(path):
        props = feat["props"]
        code = resolve_code(props)
        if code is None or not is_sovereign(props, code):
            continue
        a2 = HAND_RESOLVED_A2.get(code, props.get("ISO_A2"))
        if isinstance(a2, str) and ALPHA2_RE.match(a2):
            out[code] = a2
    return out


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    geo_src = os.path.join(here, GEO_SRC)
    shapes = os.path.join(here, SHAPES)
    if not os.path.exists(geo_src):
        sys.exit(f"missing {GEO_SRC} - download it first "
                 "(build_world_map_data.py module docstring)")
    if not os.path.exists(shapes):
        sys.exit(f"missing {shapes} - run build_world_map_data.py first")

    with open(shapes, encoding="utf-8") as fh:
        recorded = [c for c in json.load(fh)["countries"] if "stage" in c]

    alpha2 = alpha2_by_code(geo_src)
    missing = sorted(c["code"] for c in recorded if c["code"] not in alpha2)
    if missing:
        sys.exit(f"no usable ISO alpha-2 for recorded countries {missing}; "
                 "add HAND_RESOLVED_A2 entries")

    cards = []
    for country in recorded:
        code = country["code"]
        # かなは名前の持ち主 (国) 側にある。カード名は「こっき」で固定 —
        # 蟹が北海道の札であるのと同じで、国名は所属 (prefectureCode) が運ぶ。
        description = f"{country['kana']}の こっきだよ"
        if has_kanji(description):
            sys.exit(f"description for {code} contains kanji: {description}")
        cards.append({
            "id": f"{code}-1",
            "prefectureCode": code,
            "emoji": flag_emoji(alpha2[code]),
            "nameKana": "こっき",
            "nameKanji": "国旗",
            "category": "flag",
            "description": description,
            # "art" は無し: 絵文字がそのまま国旗で、プレースホルダを作らない。
        })

    # 並びの契約: (国コード, 連番) 昇順で、各国の先頭は必ず国旗。
    # 消費者は GameRules.DrawPolicy.flagFirstSilverGate — CardCatalog が
    # 「各国の最初の札 = 国旗」をこの並びから受け取り、抽選ゲートが
    # その先頭札に星を積む。連番はセーブキー (id) の一部なので、
    # オリジナル ({code}-2) を足すときもこのソートが順序を保証する。
    # 検査は sys.exit で行う (build_world_map_data.py と同じ流儀) —
    # bare assert は python3 -O で剥がれ、通っても何も検査していない
    # 偽の合格になる。
    cards.sort(key=lambda c: (c["prefectureCode"],
                              int(c["id"].split("-", 1)[1])))
    seen = set()
    for card in cards:
        code = card["prefectureCode"]
        if code not in seen:
            if card["id"] != f"{code}-1":
                sys.exit(f"first card for country {code} is {card['id']}, "
                         "not the flag")
            seen.add(code)

    if len(cards) != len(recorded):
        sys.exit(f"card count drifted: {len(cards)} != {len(recorded)}")
    if len({c["id"] for c in cards}) != len(cards):
        sys.exit("duplicate card id")

    dst = os.path.join(here, DST)
    with open(dst, "w", encoding="utf-8") as fh:
        json.dump({"cards": cards}, fh, ensure_ascii=False, indent=2)
        fh.write("\n")

    size = os.path.getsize(dst)
    print(f"wrote {os.path.relpath(dst, here)}")
    print(f"  cards : {len(cards)} flags for {len(seen)} countries")
    print(f"  size  : {size / 1024:.1f} KB")


if __name__ == "__main__":
    main()
