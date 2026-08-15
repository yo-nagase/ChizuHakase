#!/usr/bin/env python3
"""Turn the hand-made specialty illustrations into card art (CLAUDE.md §4).

The source images in assets/meisanhin-cards/ are 1254px painted cards, ~2.6MB
each. Shipping them as-is would add ~50MB to a bundle whose entire point is
working offline on a family iPad, so they are resized and palette-reduced here
and the result is committed alongside the other generated resources.

Run from the repository root, only when the illustrations change:

    python3 tools/build_card_art.py

Writes:
    ChizuHakase/Resources/Assets.xcassets/CardArt/card-<id>.imageset/
    ChizuHakase/Resources/SpecialtyCards.json   ("art" field)
"""

from __future__ import annotations

import json
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE_DIR = os.path.join(ROOT, "assets", "meisanhin-cards")
CATALOG = os.path.join(ROOT, "ChizuHakase", "Resources", "Assets.xcassets", "CardArt")
CARDS_JSON = os.path.join(ROOT, "ChizuHakase", "Resources", "SpecialtyCards.json")

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
    "hokkaido-kani": "01-1",         # 蟹
    "hokkaido-dairy": "01-2",        # 乳製品
    "hokkaido-lavender": "01-3",     # ラベンダー
    "aomori-ringo": "02-1",          # 林檎
    "aomori-nebuta": "02-2",         # ねぶた
    "aomori-hotate": "02-3",         # 帆立
    "iwate-wankosoba": "03-1",       # わんこそば
    "iwate-nanbu-tekki": "03-2",      # 南部鉄器
    "iwate-ryusendo": "03-3",         # 龍泉洞
    "miyagi-gyutan": "04-1",          # 牛タン
    "miyagi-zundamochi": "04-2",     # ずんだ餅
    "miyagi-matsushima": "04-3",      # 松島
    "akita-kiritanpo": "05-1",       # きりたんぽ
    "akita-namahage": "05-2",         # なまはげ
    "akita-inu": "05-3",              # 秋田犬
    "yamagata-sakuranbo": "06-1",    # さくらんぼ
    "yamagata-imoni": "06-2",         # 芋煮
    "yamagata-benibana": "06-3",      # 紅花
    "fukushima-momo": "07-1",        # 桃
    "fukushima-akabeko": "07-2",     # 赤べこ
    "fukushima-tsurugajo": "07-3",   # 鶴ヶ城
    "ibaraki-natto": "08-1",         # 納豆
    "ibaraki-melon": "08-2",         # メロン
    "ibaraki-tsukubasan": "08-3",    # 筑波山
    "tochigi-ichigo": "09-1",        # 苺
    "tochigi-nikko-toshogu": "09-2", # 日光東照宮
    "tochigi-gyoza": "09-3",         # 餃子
    "gunma-konnyaku": "10-1",        # 蒟蒻
    "gunma-daruma": "10-2",          # だるま
    "gunma-kusatsu-onsen": "10-3",   # 草津温泉
    "saitama-soka-senbei": "11-1",   # 草加せんべい
    "saitama-fukaya-negi": "11-2",   # 深谷ねぎ
    "saitama-hina-ningyo": "11-3",   # 雛人形
    "chiba-rakkasei": "12-1",        # 落花生
    "chiba-inubosaki": "12-2",       # 犬吠埼
    "chiba-shoyu": "12-3",           # 醤油
    "tokyo-tower": "13-1",           # 東京タワー
    "tokyo-edomae-sushi": "13-2",    # 江戸前寿司
    "tokyo-edo-kiriko": "13-3",      # 江戸切子
    "kanagawa-kamakura-daibutsu": "14-1",  # 鎌倉大仏
    "kanagawa-shirasu": "14-2",      # しらす
    "kanagawa-yosegi-zaiku": "14-3", # 寄木細工
    "niigata-koshihikari": "15-1",   # こしひかり
    "niigata-nishikigoi": "15-2",    # 錦鯉
    "niigata-sasa-dango": "15-3",    # 笹団子
    "toyama-hotaru-ika": "16-1",     # ホタルイカ
    "toyama-kurobe-dam": "16-2",     # 黒部ダム
    # Two takes on ます寿司; this is the later one.
    "toyama-masuzushi": "16-3",      # ます寿司
    "ishikawa-kenrokuen": "17-1",    # 兼六園
    "ishikawa-kutani-yaki": "17-2",  # 九谷焼
    "ishikawa-kinpaku": "17-3",      # 金箔
    "fukui-echizen-gani": "18-1",    # 越前がに
    "fukui-kyoryu": "18-2",          # 恐竜
    "fukui-megane": "18-3",          # 眼鏡
    "yamanashi-budo": "19-1",        # 葡萄
    "yamanashi-fujisan": "19-2",     # 富士山
    "yamanashi-hoto": "19-3",        # ほうとう
    "nagano-shinshu-soba": "20-1",   # 蕎麦
    "nagano-matsumotojo": "20-2",    # 松本城
    "nagano-kamikochi": "20-3",      # 上高地
    "gifu-shirakawago": "21-1",      # 白川郷
    "gifu-mino-washi": "21-2",       # 美濃和紙
    "gifu-hidagyu": "21-3",          # 飛騨牛
    "aichi-uiro": "23-1",            # ういろう
    # Two takes on Shizuoka tea exist. -ocha titles itself 「お茶」 and -cha
    # 「静岡茶」; the picture's own title is what a child reads, because an
    # illustrated chip drops the caption underneath (§4).
    "shizuoka-ocha": "22-1",         # 茶
    "shizuoka-unagi": "22-2",        # 鰻
    "shizuoka-miho-no-matsubara": "22-3",  # 三保松原
    "aichi-nagoyajo": "23-2",        # 名古屋城
    "mie-ise-udon": "24-3",          # 伊勢うどん
    "shiga-funazushi": "25-3",       # 鮒ずし
    "kyoto-uji-matcha": "26-2",      # 抹茶
    "kyoto-nishijin-ori": "26-3",    # 西陣織
    "osaka-takoyaki": "27-1",        # たこ焼き
    "hyogo-akashiyaki": "28-3",      # 明石焼
    "nara-kakinoha-zushi": "29-3",   # 柿の葉寿司
    "wakayama-umeboshi": "30-1",     # 梅干し
    "tottori-sakkyu": "31-1",        # 鳥取砂丘
    "tottori-nijisseiki-nashi": "31-2",  # 梨
    "shimane-izumo-soba": "32-2",    # 出雲そば
    "okayama-hakuto": "33-3",        # 白桃
    "hiroshima-momiji-manju": "34-1",  # もみじ饅頭
    "hiroshima-kaki": "34-3",        # 牡蠣
    "yamaguchi-fugu": "35-1",        # 河豚
    "tokushima-awa-odori": "36-1",   # 阿波踊り
    "tokushima-sudachi": "36-2",     # 酢橘
    "kagawa-sanuki-udon": "37-1",    # 讃岐うどん
    "ehime-mikan": "38-1",           # 蜜柑
    "kochi-katsuo-tataki": "39-1",   # 鰹のたたき
    "fukuoka-mentaiko": "40-1",      # 明太子
    "saga-aritayaki": "41-1",        # 有田焼
    "nagasaki-castella": "42-1",     # カステラ
    "kumamoto-karashi-renkon": "43-3",  # 辛子蓮根
    "oita-kabosu": "44-3",           # かぼす
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
    # Pillow versions disagree about whether a 192-colour indexed PNG should
    # carry a 192- or 256-entry palette. The decoded pixels are identical, but
    # blindly saving again rewrites every existing card and creates a noisy
    # binary diff. Preserve the committed file whenever the rendered RGBA
    # pixels have not actually changed.
    should_write = True
    if os.path.isfile(out):
        with Image.open(out) as existing:
            should_write = (existing.size != reduced.size
                            or existing.convert("RGBA").tobytes()
                            != reduced.convert("RGBA").tobytes())
    if should_write:
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
