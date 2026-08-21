#!/usr/bin/env python3
"""収録国 → WorldCards.json (SpecialtyCards.json の世界版).

設計 (docs/plans/2026-08-16-world-atlas-design.md §5): 1 国 2 枚。
国旗カード ({code}-1) は全収録国に配り、オリジナル ({code}-2) は下の
ORIGINALS に題材が確定した国だけに配る (P8 裁定 1: 題材が作画指示その
ものなので絵文字先行、手描きの絵は後続バッチ)。国旗は絵文字 (ISO alpha-2
由来の地域指標記号) なので画像もライセンス表記も要らない — 描くのは
端末のフォント。

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

# オリジナル札 ({code}-2)。build_card_art.py の ART_FOR_CARD と同じ流儀で
# code → 題材を明示的に書く (名前や属性からの推測をしない)。編集規範
# (docs/plans/2026-08-21-world-original-cards-plan.md): その国の代表物 1 つ、
# 政治・軍事に触れない実在の事実、description はひらがな + 語間スペースの
# 〜だよ/〜よ調 (12〜20 文字程度) で国名は言わない (札は国のマスに綴じられて
# いる)。emoji は題材そのもの 1 つで、国旗絵文字は使わない (-1 の持ち場)。
# id はセーブキーなので、公開後の題材変更は不可 (日本版 §4 と同じ)。
# まずは ひがしアジア 6 カ国のパイロット — 残りはサインオフ後のバッチで足す。
ORIGINALS = {
    156: {"emoji": "🧱", "nameKana": "ばんりのちょうじょう",
          "nameKanji": "万里の長城", "category": "landmark",
          "description": "やまに そって ながく つづく かべだよ"},
    158: {"emoji": "🧋", "nameKana": "たぴおかみるくてぃー",
          "nameKanji": "タピオカミルクティー", "category": "food",
          "description": "もちもちの つぶが はいった おちゃだよ"},
    392: {"emoji": "🗻", "nameKana": "ふじさん",
          "nameKanji": "富士山", "category": "nature",
          "description": "くにで いちばん たかい やまだよ"},
    408: {"emoji": "🍜", "nameKana": "れいめん",
          "nameKanji": "冷麺", "category": "food",
          "description": "つめたい スープの つるつる めんだよ"},
    410: {"emoji": "🥬", "nameKana": "きむち",
          "nameKanji": "キムチ", "category": "food",
          "description": "はくさいを からく つけた おかずだよ"},
    496: {"emoji": "⛺", "nameKana": "げる",
          "nameKanji": "ゲル", "category": "craft",
          "description": "はこんで たてられる まるい いえだよ"},
}

# 国旗以外の札種 (SpecialtyCard.Category)。flag はここに無い — -2 が flag を
# 名乗ると「各国の先頭 = 国旗」の契約が絵の上で嘘になる。
ORIGINAL_CATEGORIES = {"food", "landmark", "nature", "craft"}


def flag_emoji(alpha2: str) -> str:
    """ISO alpha-2 → 地域指標記号 2 文字 (例: JP → 🇯🇵)。"""
    return "".join(chr(0x1F1E6 + ord(c) - ord("A")) for c in alpha2)


def is_kids_text(s: str) -> bool:
    """こども表記か: ひらがな・カタカナ・語間スペース・長音だけを許す。
    漢字だけでなく句読点や数字も弾く — 説明文は読めない子に届く札の声。"""
    return all(
        o == 0x20 or o == 0x30FC
        or 0x3041 <= o <= 0x3096 or 0x30A1 <= o <= 0x30FA
        for o in map(ord, s))


def is_flag_emoji(s: str) -> bool:
    """地域指標記号 2 文字 (国旗絵文字) か。オリジナル札には禁止 — 国旗は
    -1 の持ち場で、二重に配ると札種の違いが絵から消える。"""
    return len(s) == 2 and all(0x1F1E6 <= ord(c) <= 0x1F1FF for c in s)


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

    # ORIGINALS の持ち主は収録国であること。ここで止めないと、コードの
    # 打ち間違いが「札が静かに出ない」だけになり誰も気づかない。
    unknown = sorted(set(ORIGINALS) - {c["code"] for c in recorded})
    if unknown:
        sys.exit(f"ORIGINALS codes not in the recorded countries: {unknown}")

    cards = []
    for country in recorded:
        code = country["code"]
        # かなは名前の持ち主 (国) 側にある。カード名は「こっき」で固定 —
        # 蟹が北海道の札であるのと同じで、国名は所属 (prefectureCode) が運ぶ。
        description = f"{country['kana']}の こっきだよ"
        if not is_kids_text(description):
            sys.exit(f"description for {code} is not kids text: {description}")
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
        original = ORIGINALS.get(code)
        if original is None:
            continue  # 題材が未確定の国は従来どおり国旗のみ。
        if original["category"] not in ORIGINAL_CATEGORIES:
            sys.exit(f"original for {code} has bad category: "
                     f"{original['category']}")
        if not is_kids_text(original["description"]):
            sys.exit(f"description for {code}-2 is not kids text: "
                     f"{original['description']}")
        if is_flag_emoji(original["emoji"]):
            sys.exit(f"original for {code} uses a flag emoji")
        cards.append({
            "id": f"{code}-2",
            "prefectureCode": code,
            "emoji": original["emoji"],
            "nameKana": original["nameKana"],
            "nameKanji": original["nameKanji"],
            "category": original["category"],
            "description": original["description"],
            # "art" は無し: 絵文字先行 (P8 裁定 1)。手描きが揃った札から
            # build_card_art.py と同じ流儀で足す。
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

    if len(cards) != len(recorded) + len(ORIGINALS):
        sys.exit(f"card count drifted: {len(cards)} != "
                 f"{len(recorded)} + {len(ORIGINALS)}")
    if len({c["id"] for c in cards}) != len(cards):
        sys.exit("duplicate card id")

    dst = os.path.join(here, DST)
    with open(dst, "w", encoding="utf-8") as fh:
        json.dump({"cards": cards}, fh, ensure_ascii=False, indent=2)
        fh.write("\n")

    size = os.path.getsize(dst)
    print(f"wrote {os.path.relpath(dst, here)}")
    print(f"  cards : {len(cards)} ({len(recorded)} flags "
          f"+ {len(ORIGINALS)} originals) for {len(seen)} countries")
    print(f"  size  : {size / 1024:.1f} KB")


if __name__ == "__main__":
    main()
