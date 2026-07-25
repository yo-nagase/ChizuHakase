#!/usr/bin/env python3
"""Turn the hand-made specialty illustrations into card art (CLAUDE.md §4).

The source images in assets/meisanhin-cards/ are 1254px painted cards, ~2.6MB
each. Shipping them as-is would add ~50MB to a bundle whose entire point is
working offline on a family iPad, so they are resized and palette-reduced here
and the result is committed alongside the other generated resources.

Run from the repository root, only when the illustrations change:

    python3 tools/build_card_art.py

Writes:
    WakuwakuChizu/Resources/Assets.xcassets/CardArt/card-<id>.imageset/
    WakuwakuChizu/Resources/SpecialtyCards.json   ("art" field)
"""

from __future__ import annotations

import json
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE_DIR = os.path.join(ROOT, "assets", "meisanhin-cards")
CATALOG = os.path.join(ROOT, "WakuwakuChizu", "Resources", "Assets.xcassets", "CardArt")
CARDS_JSON = os.path.join(ROOT, "WakuwakuChizu", "Resources", "SpecialtyCards.json")

# Card art is only ever shown at chip size, so 480px covers a 160pt chip on a
# 3x screen with room to spare.
SIZE = 480

# 192 colours holds the watercolour gradients without visible banding and takes
# each card from ~390KB to ~66KB. Anything below ~128 starts to post-edge the
# soft petal washes.
PALETTE_COLOURS = 192

# Illustration -> card id, written out rather than matched on the name.
#
# The illustrations were drawn independently of SpecialtyCards.json, so this is
# where the two are reconciled. An entry only belongs here when the picture is
# of the same thing the card names: art that says 乳製品 on a card that says 蟹
# would be a lie told to a child who is trying to learn.
# Five cards were rewritten to the subject that had been painted — same
# prefecture, same category, so the ずかん filter keeps its balance. That is only
# safe before release: after it, an id is a save key (§4) and its card must
# stay the same card.
ART_FOR_CARD = {
    "hokkaido-dairy": "01-2",        # 乳製品
    "aomori-ringo": "02-1",          # 林檎
    "iwate-wankosoba": "03-1",       # わんこそば
    "miyagi-zundamochi": "04-2",     # ずんだ餅
    "akita-kiritanpo": "05-1",       # きりたんぽ
    "yamagata-sakuranbo": "06-1",    # さくらんぼ
    "fukushima-momo": "07-1",        # 桃
    "ibaraki-natto": "08-1",         # 納豆
    "tochigi-ichigo": "09-1",        # 苺
    "gunma-konnyaku": "10-1",        # 蒟蒻
    "saitama-soka-senbei": "11-1",   # 草加せんべい
    "chiba-rakkasei": "12-1",        # 落花生
    "tokyo-edomae-sushi": "13-2",    # 江戸前寿司
    "kanagawa-shirasu": "14-2",      # しらす
    "niigata-koshihikari": "15-1",   # こしひかり
    "toyama-masu-zushi": "16-3",     # ます寿司
    "ishikawa-kinpaku": "17-3",      # 金箔
    "fukui-echizen-gani": "18-1",    # 越前がに
    "yamanashi-hoto": "19-3",        # ほうとう
    "nagano-shinshu-soba": "20-1",   # 蕎麦
    "gifu-hidagyu": "21-3",          # 飛騨牛
    "aichi-uiro": "23-1",            # ういろう
    # Two takes on Shizuoka tea exist. -ocha titles itself 「お茶」 and -cha
    # 「静岡茶」; the picture's own title is what a child reads, because an
    # illustrated chip drops the caption underneath (§4).
    "shizuoka-ocha": "22-1",         # 茶
    "kyoto-uji-matcha": "26-2",      # 抹茶
    "okayama-hakuto": "33-3",        # 白桃
    "hiroshima-momiji-manju": "34-1",  # もみじ饅頭
    "hiroshima-kaki": "34-3",        # 牡蠣
    "ehime-mikan": "38-1",           # 蜜柑
    "miyazaki-mango": "45-1",        # マンゴー
    "kagoshima-kurobuta": "46-2",    # 黒豚
    "okinawa-pineapple": "47-2",     # パイナップル
}


def asset_name(card_id: str) -> str:
    return f"card-{card_id}"


def build_imageset(slug: str, card_id: str) -> int:
    """Resize one illustration into its own imageset. Returns bytes written."""
    source = os.path.join(SOURCE_DIR, f"{slug}-transparent.png")
    name = asset_name(card_id)
    folder = os.path.join(CATALOG, f"{name}.imageset")
    os.makedirs(folder, exist_ok=True)

    image = Image.open(source).convert("RGBA")
    if image.width != image.height:
        raise SystemExit(f"{slug}: expected a square card, got {image.size}")

    resized = image.resize((SIZE, SIZE), Image.LANCZOS)
    # FASTOCTREE is the only PIL method that keeps the alpha channel, which the
    # rounded corners need.
    reduced = resized.quantize(colors=PALETTE_COLOURS, method=Image.FASTOCTREE)

    filename = f"{name}.png"
    out = os.path.join(folder, filename)
    reduced.save(out, optimize=True)

    with open(os.path.join(folder, "Contents.json"), "w") as f:
        json.dump({
            "images": [{"filename": filename, "idiom": "universal"}],
            "info": {"author": "xcode", "version": 1},
            # The source is a single high-resolution painting; letting the
            # catalog treat it as scale-agnostic avoids shipping three copies.
            "properties": {"template-rendering-intent": "original"},
        }, f, indent=2)
        f.write("\n")

    return os.path.getsize(out)


def main() -> None:
    if not os.path.isdir(SOURCE_DIR):
        raise SystemExit(f"no illustrations at {SOURCE_DIR}")

    with open(CARDS_JSON) as f:
        catalog = json.load(f)
    cards = {card["id"]: card for card in catalog["cards"]}

    unknown = sorted(set(ART_FOR_CARD.values()) - set(cards))
    if unknown:
        raise SystemExit(f"mapped to card ids that do not exist: {unknown}")

    os.makedirs(CATALOG, exist_ok=True)
    with open(os.path.join(CATALOG, "Contents.json"), "w") as f:
        json.dump({"info": {"author": "xcode", "version": 1}}, f)
        f.write("\n")

    total = 0
    for slug, card_id in sorted(ART_FOR_CARD.items(), key=lambda kv: kv[1]):
        total += build_imageset(slug, card_id)

    # Stamp the asset name onto the card so the app never guesses at one.
    for card in catalog["cards"]:
        card.pop("art", None)
    for card_id in ART_FOR_CARD.values():
        cards[card_id]["art"] = asset_name(card_id)

    with open(CARDS_JSON, "w") as f:
        json.dump(catalog, f, ensure_ascii=False, indent=2)
        f.write("\n")

    print(f"{len(ART_FOR_CARD)} of {len(cards)} cards have art "
          f"({total / 1024:.0f} KB total, {total / len(ART_FOR_CARD) / 1024:.0f} KB each)")

    available = {f[:-len("-transparent.png")]
                 for f in os.listdir(SOURCE_DIR) if f.endswith("-transparent.png")}
    orphans = sorted(available - set(ART_FOR_CARD))
    if orphans:
        print("\nillustrations with no matching card:", file=sys.stderr)
        for slug in orphans:
            print(f"  {slug}", file=sys.stderr)


if __name__ == "__main__":
    main()
