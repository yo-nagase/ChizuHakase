#!/usr/bin/env python3
"""Build painted world-card illustrations into the asset catalog.

World and Japan card IDs overlap (for example, ``12-2``), so world artwork
uses the explicit ``world-card-<id>`` asset namespace.  Add an entry to
``ART_FOR_CARD`` only after the illustration and the card describe the same
subject; this is the world counterpart of ``build_card_art.py``.

Run from the repository root after adding an illustration:

    python3 tools/build_world_card_art.py

Writes the matching imagesets below ``Assets.xcassets/CardArt`` and stamps the
asset name into ``WorldCards.json``.  Re-running is deterministic.
"""

from __future__ import annotations

import json
import os
import sys

from PIL import Image


ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE_DIR = os.path.join(ROOT, "assets", "world-cards")
CATALOG = os.path.join(
    ROOT, "ChizuHakase", "Resources", "Assets.xcassets", "CardArt"
)
CARDS_JSON = os.path.join(ROOT, "ChizuHakase", "Resources", "WorldCards.json")

SIZE = 480
PALETTE_COLOURS = 192

# Illustration slug -> world card id.  Never infer this relationship from a
# filename: a mismatched picture would teach a child the wrong subject.
ART_FOR_CARD = {
    "belize-great-blue-hole": "84-2",  # グレート・ブルーホール
    "canada-sugar-maple": "124-2",  # サトウカエデ
    "costa-rica-sloth": "188-2",  # ナマケモノ
    "el-salvador-pupusa": "222-2",  # ププサ
    "guatemala-quetzal": "320-2",  # ケツァール
    "honduras-copan-ruins": "340-2",  # コパン遺跡
    "mexico-tacos": "484-2",  # タコス
    "nicaragua-momotombo-volcano": "558-2",  # モモトンボ火山
    "panama-canal": "591-2",  # パナマ運河
    "united-states-grand-canyon": "840-2",  # グランドキャニオン
    "bahamas-pink-conch-shell": "44-2",  # ピンクの貝殻
    "cuba-classic-car": "192-2",  # クラシックカー
    "dominican-republic-cacao": "214-2",  # カカオ
    "haiti-tin-art": "332-2",  # ブリキアート
    "jamaica-blue-mountain-coffee": "388-2",  # ブルーマウンテンコーヒー
    "trinidad-and-tobago-steelpan": "780-2",  # スティールパン
    "argentina-empanada": "32-2",  # エンパナーダ
    "bolivia-uyuni-salt-flat": "68-2",  # ウユニ塩湖
    "brazil-amazon-rainforest": "76-2",  # アマゾンの森
    "chile-moai": "152-2",  # モアイ
    "colombia-coffee": "170-2",  # コーヒー
    "ecuador-galapagos-giant-tortoise": "218-2",  # ガラパゴスゾウガメ
    "guyana-kaieteur-falls": "328-2",  # カイエトゥールの滝
    "paraguay-terere": "600-2",  # テレレ
    "peru-machu-picchu": "604-2",  # マチュ・ピチュ
    "suriname-tropical-rainforest": "740-2",  # 熱帯雨林
    "uruguay-mate": "858-2",  # マテ茶
    "venezuela-angel-falls": "862-2",  # エンジェルフォール
    "denmark-little-mermaid-statue": "208-2",  # 人魚姫の像
    "estonia-bog": "233-2",  # 湿原
    "finland-sauna": "246-2",  # サウナ
    "iceland-geysir": "352-2",  # ゲイシール
    "ireland-irish-harp": "372-2",  # アイリッシュハープ
    "latvia-amber": "428-2",  # 琥珀
    "lithuania-rye-bread": "440-2",  # ライ麦パン
    "norway-fjord": "578-2",  # フィヨルド
    "sweden-dala-horse": "752-2",  # ダーラナホース
    "united-kingdom-big-ben": "826-2",  # ビッグ・ベン
    "austria-sachertorte": "40-2",  # ザッハトルテ
    "belgium-waffle": "56-2",  # ベルギーワッフル
    "france-eiffel-tower": "250-2",  # エッフェル塔
    "germany-pretzel": "276-2",  # プレッツェル
    "luxembourg-vianden-castle": "442-2",  # ヴィアンデン城
    "netherlands-windmill": "528-2",  # 風車
    "switzerland-cheese": "756-2",  # チーズ
    "bulgaria-rose": "100-2",  # バラ
    "belarus-european-bison": "112-2",  # ヨーロッパバイソン
    "czech-astronomical-clock": "203-2",  # 天文時計
    "hungary-goulash": "348-2",  # グヤーシュ
    "moldova-grapes": "498-2",  # ブドウ
    "poland-pierogi": "616-2",  # ピエロギ
    "romania-painted-eggs": "642-2",  # 彩色卵
    "russia-matryoshka": "643-2",  # マトリョーシカ
    "slovakia-spis-castle": "703-2",  # スピシュ城
    "ukraine-sunflowers": "804-2",  # ヒマワリ
    "albania-berat-townscape": "8-2",  # ベラトの街並み
    "bosnia-herzegovina-mostar-old-bridge": "70-2",  # モスタルの古い橋
    "croatia-plitvice-lakes": "191-2",  # プリトヴィツェ湖群
    "greece-parthenon": "300-2",  # パルテノン神殿
    "italy-colosseum": "380-2",  # コロッセオ
    "malta-luzzu": "470-2",  # ルッツ
    "montenegro-bay-of-kotor": "499-2",  # コトル湾
    "portugal-azulejo": "620-2",  # アズレージョ
    "serbia-ajvar": "688-2",  # アイバル
    "slovenia-lake-bled": "705-2",  # ブレッド湖
    "spain-paella": "724-2",  # パエリア
    "north-macedonia-lake-ohrid": "807-2",  # オフリド湖
    "algeria-sahara-desert": "12-2",  # サハラ砂漠
    "libya-leptis-magna": "434-2",  # レプティス・マグナ遺跡
    "morocco-tagine": "504-2",  # タジン
    "sudan-meroe-pyramids": "729-2",  # メロエのピラミッド
    "tunisia-mosaic": "788-2",  # モザイク
    "egypt-pyramids": "818-2",  # ピラミッド
    "benin-bronze-sculpture": "204-2",  # ブロンズ彫刻
    "gambia-river": "270-2",  # ガンビア川
    "ghana-kente": "288-2",  # ケンテ
    "guinea-djembe": "324-2",  # ジャンベ
    "cote-divoire-cacao": "384-2",  # カカオ
    "liberia-pygmy-hippo": "430-2",  # コビトカバ
    "mali-bogolanfini": "466-2",  # ボゴランフィニ
    "mauritania-richat-structure": "478-2",  # リシャット構造
    "niger-west-african-giraffe": "562-2",  # ニシアフリカキリン
    "nigeria-nok-terracotta": "566-2",  # ノクの土偶
    "guinea-bissau-cashews": "624-2",  # カシューナッツ
    "senegal-baobab": "686-2",  # バオバブ
    "sierra-leone-chimpanzee": "694-2",  # チンパンジー
    "togo-takienta-house": "768-2",  # タキエンタの家
    "burkina-faso-bronze-sculpture": "854-2",  # ブロンズ彫刻
    "angola-giant-sable-antelope": "24-2",  # オオセーブルアンテロープ
    "cameroon-mount-cameroon": "120-2",  # カメルーン山
    "central-african-republic-western-lowland-gorilla": "140-2",  # ニシローランドゴリラ
    "chad-ennedi-rocks": "148-2",  # エネディの岩
    "republic-congo-western-lowland-gorilla": "178-2",  # ニシローランドゴリラ
    "dr-congo-okapi": "180-2",  # オカピ
    "equatorial-guinea-cacao": "226-2",  # カカオ
    "gabon-forest-elephant": "266-2",  # マルミミゾウ
    "burundi-drums": "108-2",  # ブルンジの太鼓
    "ethiopia-coffee-ceremony": "231-2",  # コーヒーセレモニー
    "eritrea-red-sea-coral": "232-2",  # 紅海のサンゴ
    "djibouti-lake-assal": "262-2",  # アッサル湖
    "kenya-giraffe": "404-2",  # キリン
    "madagascar-baobab": "450-2",  # バオバブ
    "malawi-cichlid": "454-2",  # シクリッド
    "mozambique-cashews": "508-2",  # カシューナッツ
    "rwanda-mountain-gorilla": "646-2",  # マウンテンゴリラ
    "somalia-camel": "706-2",  # ラクダ
    "zimbabwe-victoria-falls": "716-2",  # ビクトリアの滝
    "south-sudan-shoebill": "728-2",  # ハシビロコウ
    "uganda-coffee": "800-2",  # コーヒー
    "tanzania-kilimanjaro": "834-2",  # キリマンジャロ
    "zambia-emerald": "894-2",  # エメラルド
    "botswana-okavango-delta": "72-2",  # オカバンゴ・デルタ
    "lesotho-basotho-blanket": "426-2",  # バソトブランケット
    "namibia-namib-desert": "516-2",  # ナミブ砂漠
    "south-africa-protea": "710-2",  # プロテア
    "eswatini-white-rhino": "748-2",  # シロサイ
    "azerbaijan-mud-volcanoes": "31-2",  # 泥火山
    "armenia-lavash": "51-2",  # ラヴァシュ
    "cyprus-halloumi": "196-2",  # ハルミチーズ
    "georgia-khachapuri": "268-2",  # ハチャプリ
    "iraq-dates": "368-2",  # デーツ
    "israel-dead-sea": "376-2",  # 死海
    "jordan-petra": "400-2",  # ペトラ遺跡
    "kuwait-dhow": "414-2",  # ダウ船
    "lebanon-cedar": "422-2",  # レバノンスギ
    "oman-frankincense": "512-2",  # 乳香
    "qatar-pearls": "634-2",  # 真珠
    "saudi-arabia-dates": "682-2",  # デーツ
    "syria-aleppo-soap": "760-2",  # アレッポ石鹸
    "uae-burj-khalifa": "784-2",  # ブルジュ・ハリファ
    "turkey-cappadocia": "792-2",  # カッパドキア
    "yemen-dragon-blood-tree": "887-2",  # 竜血樹
    "kazakhstan-apples": "398-2",  # リンゴ
    "kyrgyzstan-felt-carpet": "417-2",  # フェルトの絨毯
    "tajikistan-pamir-plateau": "762-2",  # パミール高原
    "turkmenistan-akhal-teke": "795-2",  # アハルテケ
    "uzbekistan-registan": "860-2",  # レギスタン広場
    "afghanistan-lapis-lazuli": "4-2",  # ラピスラズリ
    "bangladesh-bengal-tiger": "50-2",  # ベンガルトラ
    "bhutan-takin": "64-2",  # ターキン
    "sri-lanka-ceylon-tea": "144-2",  # セイロンティー
    "india-taj-mahal": "356-2",  # タージ・マハル
    "iran-persian-carpet": "364-2",  # ペルシャ絨毯
    "maldives-coral-atoll": "462-2",  # サンゴの環礁
    "nepal-himalayas": "524-2",  # ヒマラヤ山脈
    "pakistan-k2": "586-2",  # ケーツー
    "china-great-wall": "156-2",  # 万里の長城
    "taiwan-bubble-milk-tea": "158-2",  # タピオカミルクティー
    "japan-mount-fuji": "392-2",  # 富士山
    "north-korea-cold-noodles": "408-2",  # 冷麺
    "south-korea-kimchi": "410-2",  # キムチ
    "mongolia-ger": "496-2",  # ゲル
    "brunei-kampong-ayer": "96-2",  # カンポン・アイール
    "myanmar-lacquerware": "104-2",  # 漆器
    "cambodia-angkor-wat": "116-2",  # アンコール・ワット
    "indonesia-komodo-dragon": "360-2",  # コモドオオトカゲ
    "laos-khao-niao": "418-2",  # カオニャオ
    "malaysia-petronas-twin-towers": "458-2",  # ペトロナスツインタワー
    "philippines-jeepney": "608-2",  # ジープニー
    "timor-leste-tais": "626-2",  # タイス
    "singapore-merlion": "702-2",  # マーライオン
    "vietnam-pho": "704-2",  # フォー
    "thailand-tuk-tuk": "764-2",  # トゥクトゥク
    "australia-great-barrier-reef": "36-2",  # グレートバリアリーフ
    "fiji-coral-reef": "242-2",  # サンゴ礁
    "new-zealand-kiwi": "554-2",  # キーウィ
    "papua-new-guinea-bird-of-paradise": "598-2",  # ゴクラクチョウ
}


def asset_name(card_id: str) -> str:
    return f"world-card-{card_id}"


def build_imageset(slug: str, card_id: str) -> int:
    source = os.path.join(SOURCE_DIR, f"{slug}-transparent.png")
    if not os.path.isfile(source):
        raise SystemExit(f"missing illustration: {source}")

    name = asset_name(card_id)
    folder = os.path.join(CATALOG, f"{name}.imageset")
    os.makedirs(folder, exist_ok=True)

    image = Image.open(source).convert("RGBA")
    if image.width != image.height:
        raise SystemExit(f"{slug}: expected a square card, got {image.size}")

    resized = image.resize((SIZE, SIZE), Image.LANCZOS)
    reduced = resized.quantize(colors=PALETTE_COLOURS, method=Image.FASTOCTREE)
    filename = f"{name}.png"
    output = os.path.join(folder, filename)

    should_write = True
    if os.path.isfile(output):
        with Image.open(output) as existing:
            should_write = (
                existing.size != reduced.size
                or existing.convert("RGBA").tobytes()
                != reduced.convert("RGBA").tobytes()
            )
    if should_write:
        reduced.save(output, optimize=True)

    with open(os.path.join(folder, "Contents.json"), "w") as file:
        json.dump(
            {
                "images": [{"filename": filename, "idiom": "universal"}],
                "info": {"author": "xcode", "version": 1},
                "properties": {"template-rendering-intent": "original"},
            },
            file,
            indent=2,
        )
        file.write("\n")

    return os.path.getsize(output)


def main() -> None:
    with open(CARDS_JSON) as file:
        catalog = json.load(file)
    cards = {card["id"]: card for card in catalog["cards"]}

    unknown = sorted(set(ART_FOR_CARD.values()) - set(cards))
    if unknown:
        raise SystemExit(f"mapped to card ids that do not exist: {unknown}")

    total = 0
    for slug, card_id in sorted(ART_FOR_CARD.items(), key=lambda item: item[1]):
        total += build_imageset(slug, card_id)

    for card in catalog["cards"]:
        card.pop("art", None)
    for card_id in ART_FOR_CARD.values():
        cards[card_id]["art"] = asset_name(card_id)

    with open(CARDS_JSON, "w") as file:
        json.dump(catalog, file, ensure_ascii=False, indent=2)
        file.write("\n")

    print(
        f"{len(ART_FOR_CARD)} of {len(cards)} world cards have art "
        f"({total / 1024:.0f} KB total)"
    )

    available = {
        filename[: -len("-transparent.png")]
        for filename in os.listdir(SOURCE_DIR)
        if filename.endswith("-transparent.png")
    }
    orphans = sorted(available - set(ART_FOR_CARD))
    if orphans:
        print("\nillustrations with no matching card:", file=sys.stderr)
        for slug in orphans:
            print(f"  {slug}", file=sys.stderr)


if __name__ == "__main__":
    main()
