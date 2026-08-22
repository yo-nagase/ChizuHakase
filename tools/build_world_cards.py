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
# パイロット 6 カ国のサインオフ後、全 167 カ国へ展開した。どの値も
# 国名から自動生成せず、子どもへ見せる題材として 1 件ずつ編集している。
def original(emoji: str, kana: str, kanji: str, category: str,
             description: str) -> dict[str, str]:
    return {"emoji": emoji, "nameKana": kana, "nameKanji": kanji,
            "category": category, "description": description}


ORIGINALS = {
    4: original("💎", "らぴすらずり", "ラピスラズリ", "nature",
                "あおく かがやく うつくしい いしだよ"),
    8: original("🏘️", "べらとの まちなみ", "ベラトの街並み", "landmark",
                "しろい いえが おかに ならぶ まちだよ"),
    12: original("🏜️", "さはらさばく", "サハラ砂漠", "nature",
                 "すなが どこまでも ひろがる さばくだよ"),
    24: original("🦌", "おおせーぶるあんてろーぷ", "オオセーブルアンテロープ", "nature",
                 "ながい つのを もつ めずらしい どうぶつだよ"),
    31: original("🌋", "でいかざん", "泥火山", "nature",
                 "どろと ガスが ふきだす ふしぎな おかだよ"),
    32: original("🥟", "えんぱなーだ", "エンパナーダ", "food",
                 "ぐを かわで つつんで やいた りょうりだよ"),
    36: original("🪸", "ぐれーとばりありーふ", "グレートバリアリーフ", "nature",
                 "さんごしょうが ながく つづく うみだよ"),
    40: original("🍰", "ざっはとるて", "ザッハトルテ", "food",
                 "ちょこれーとを つかった あまい けーきだよ"),
    44: original("🐚", "ぴんくの かいがら", "ピンクの貝殻", "nature",
                 "うすい ぴんくいろの おおきな かいだよ"),
    50: original("🐅", "べんがるとら", "ベンガルトラ", "nature",
                 "しまもようで もりに くらす おおきな とらだよ"),
    51: original("🫓", "らゔぁしゅ", "ラヴァシュ", "food",
                 "うすく のばして やく ぱんだよ"),
    56: original("🧇", "べるぎーわっふる", "ベルギーワッフル", "food",
                 "あみめの かたちに やいた おかしだよ"),
    64: original("🐐", "たーきん", "ターキン", "nature",
                 "やまの もりに くらす ひづめの どうぶつだよ"),
    68: original("🪞", "うゆにえんこ", "ウユニ塩湖", "nature",
                 "あめの あとは そらを うつす しおの だいちだよ"),
    70: original("🌉", "もすたるの ふるいはし", "モスタルの古い橋", "landmark",
                 "いしで できた おおきな あーちの はしだよ"),
    72: original("🐘", "おかばんごでるた", "オカバンゴ・デルタ", "nature",
                 "さばくの なかに ひろがる みずべだよ"),
    76: original("🦜", "あまぞんの もり", "アマゾンの森", "nature",
                 "おおきな かわと みどりが ひろがる もりだよ"),
    84: original("🌊", "ぐれーとぶるーほーる", "グレート・ブルーホール", "nature",
                 "うみに まるく ひらいた ふかい あなだよ"),
    96: original("🛶", "かんぽんあいる", "カンポン・アイール", "landmark",
                 "みずの うえに いえが ならぶ むらだよ"),
    100: original("🌹", "ばら", "バラ", "nature",
                  "かおりの よい はなが たくさん そだつよ"),
    104: original("🥣", "うるしき", "漆器", "craft",
                  "うるしを ぬって つやを だす うつわだよ"),
    108: original("🥁", "ぶるんじの たいこ", "ブルンジの太鼓", "craft",
                  "おおぜいで かなでる おおきな たいこだよ"),
    112: original("🦬", "よーろっぱばいそん", "ヨーロッパバイソン", "nature",
                  "もりに くらす からだの おおきな うしだよ"),
    116: original("🛕", "あんこーるわっと", "アンコール・ワット", "landmark",
                  "いしの とうが ならぶ おおきな いせきだよ"),
    120: original("🌋", "かめるーんざん", "カメルーン山", "nature",
                  "うみの ちかくに そびえる かざんだよ"),
    124: original("🍁", "さとうかえで", "サトウカエデ", "nature",
                  "あきに はっぱが あかく そまる きだよ"),
    140: original("🦍", "にしろーらんどごりら", "ニシローランドゴリラ", "nature",
                  "あつい もりに くらす おおきな さるだよ"),
    144: original("🍵", "せいろんてぃー", "セイロンティー", "food",
                  "こうちで そだつ かおりの よい おちゃだよ"),
    148: original("🪨", "えねでぃの いわ", "エネディの岩", "nature",
                  "かぜが つくった あーちの いわだよ"),
    152: original("🗿", "もあい", "モアイ", "landmark",
                  "しまに ならぶ おおきな いしの ぞうだよ"),
    156: original("🧱", "ばんりのちょうじょう", "万里の長城", "landmark",
                  "やまに そって ながく つづく かべだよ"),
    158: original("🧋", "たぴおかみるくてぃー", "タピオカミルクティー", "food",
                  "もちもちの つぶが はいった おちゃだよ"),
    170: original("☕", "こーひー", "コーヒー", "food",
                  "やまの はたけで かおりの よい まめが そだつよ"),
    178: original("🦍", "にしろーらんどごりら", "ニシローランドゴリラ", "nature",
                  "あつい もりに くらす おおきな さるだよ"),
    180: original("🦓", "おかぴ", "オカピ", "nature",
                  "あしに しまもようが ある もりの どうぶつだよ"),
    188: original("🦥", "なまけもの", "ナマケモノ", "nature",
                  "きの うえで ゆっくり くらす どうぶつだよ"),
    191: original("🏞️", "ぷりとゔぃつぇこぐん", "プリトヴィツェ湖群", "nature",
                  "たきと みずうみが つながる もりだよ"),
    192: original("🚗", "くらしっくかー", "クラシックカー", "craft",
                  "いろあざやかな むかしの くるまだよ"),
    196: original("🧀", "はるみちーず", "ハルミチーズ", "food",
                  "やいても とけにくい しおあじの ちーずだよ"),
    203: original("🕰️", "てんもんどけい", "天文時計", "landmark",
                  "ほしや たいようの うごきも しめす とけいだよ"),
    204: original("🗿", "ぶろんずちょうこく", "ブロンズ彫刻", "craft",
                  "きんぞくを とかして つくる ぞうだよ"),
    208: original("🧜", "にんぎょひめの ぞう", "人魚姫の像", "landmark",
                  "うみべの いわに すわる ちいさな ぞうだよ"),
    214: original("🍫", "かかお", "カカオ", "food",
                  "ちょこれーとの もとに なる みが そだつよ"),
    218: original("🐢", "がらぱごすぞうがめ", "ガラパゴスゾウガメ", "nature",
                  "しまに くらす とても おおきな かめだよ"),
    222: original("🫓", "ぷぷさ", "ププサ", "food",
                  "とうもろこしの きじで ぐを つつむよ"),
    226: original("🍫", "かかお", "カカオ", "food",
                  "あつい もりで ちょこれーとの みが そだつよ"),
    231: original("☕", "こーひーせれもにー", "コーヒーセレモニー", "food",
                  "まめを いって ゆっくり おちゃを いれるよ"),
    232: original("🪸", "こうかいの さんご", "紅海のサンゴ", "nature",
                  "あたたかい うみに さんごが ひろがるよ"),
    233: original("🌿", "しつげん", "湿原", "nature",
                  "みずと こけが ひろがる しずかな のはらだよ"),
    242: original("🪸", "さんごしょう", "サンゴ礁", "nature",
                  "あたたかい うみに いろとりどりの さんごが そだつよ"),
    246: original("🧖", "さうな", "サウナ", "craft",
                  "あつい へやで からだを あたためるよ"),
    250: original("🗼", "えっふぇるとう", "エッフェル塔", "landmark",
                  "てつで できた たかい とうだよ"),
    262: original("🧂", "あっさるこ", "アッサル湖", "nature",
                  "しおが しろく ひろがる みずうみだよ"),
    266: original("🐘", "まるみみぞう", "マルミミゾウ", "nature",
                  "あつい もりを あるく ちいさめの ぞうだよ"),
    268: original("🫓", "はちゃぷり", "ハチャプリ", "food",
                  "ぱんに ちーずを のせて やく りょうりだよ"),
    270: original("🌊", "がんびあがわ", "ガンビア川", "nature",
                  "くにの なかを ながく ながれる かわだよ"),
    276: original("🥨", "ぷれっつぇる", "プレッツェル", "food",
                  "むすんだ かたちの こうばしい ぱんだよ"),
    288: original("🧵", "けんて", "ケンテ", "craft",
                  "あざやかな いろを おった ぬのだよ"),
    300: original("🏛️", "ぱるてのんしんでん", "パルテノン神殿", "landmark",
                  "おかの うえに たつ いしの しんでんだよ"),
    320: original("🐦", "けつぁーる", "ケツァール", "nature",
                  "ながい おとばねを もつ みどりの とりだよ"),
    324: original("🪘", "じゃんべ", "ジャンベ", "craft",
                  "てで たたいて ならす さかずきがたの たいこだよ"),
    328: original("💧", "かいえとぅーるの たき", "カイエトゥールの滝", "nature",
                  "もりの なかを いっきに おちる おおきな たきだよ"),
    332: original("🔨", "ぶりきあーと", "ブリキアート", "craft",
                  "きんぞくを きって もようを つくる こうげいだよ"),
    340: original("🗿", "こぱんいせき", "コパン遺跡", "landmark",
                  "もじを きざんだ いしの ぞうが ならぶよ"),
    348: original("🍲", "ぐやーしゅ", "グヤーシュ", "food",
                  "にくと やさいを にこんだ あたたかい すーぷだよ"),
    352: original("♨️", "げいしーる", "ゲイシール", "nature",
                  "じめんから あつい みずが ふきあがるよ"),
    356: original("🕌", "たーじまはる", "タージ・マハル", "landmark",
                  "しろい いしで できた おおきな たてものだよ"),
    360: original("🦎", "こもどおおとかげ", "コモドオオトカゲ", "nature",
                  "しまに くらす からだの おおきな とかげだよ"),
    364: original("🧶", "ぺるしゃじゅうたん", "ペルシャ絨毯", "craft",
                  "こまかな もようを おりこんだ じゅうたんだよ"),
    368: original("🌴", "でーつ", "デーツ", "food",
                  "なつめやしに なる あまい みだよ"),
    372: original("🎵", "あいるらんどの はーぷ", "アイリッシュハープ", "craft",
                  "たくさんの いとを ゆびで はじく がっきだよ"),
    376: original("🧂", "しかい", "死海", "nature",
                  "しおが おおくて からだが うきやすい みずうみだよ"),
    380: original("🏛️", "ころっせお", "コロッセオ", "landmark",
                  "むかしの ひとが あつまった まるい たてものだよ"),
    384: original("🍫", "かかお", "カカオ", "food",
                  "ちょこれーとの もとに なる みが たくさん そだつよ"),
    388: original("☕", "ぶるーまうんてんこーひー", "ブルーマウンテンコーヒー", "food",
                  "やまの はたけで かおりの よい まめが そだつよ"),
    392: original("🗻", "ふじさん", "富士山", "nature",
                  "くにで いちばん たかい やまだよ"),
    398: original("🍎", "りんご", "リンゴ", "food",
                  "ひろい だいちで あかい みが そだつよ"),
    400: original("🏜️", "ぺとらいせき", "ペトラ遺跡", "landmark",
                  "あかい いわを けずって つくった まちだよ"),
    404: original("🦒", "きりん", "キリン", "nature",
                  "そうげんで たかい きの はを たべるよ"),
    408: original("🍜", "れいめん", "冷麺", "food",
                  "つめたい スープの つるつる めんだよ"),
    410: original("🥬", "きむち", "キムチ", "food",
                  "はくさいを からく つけた おかずだよ"),
    414: original("⛵", "だうせん", "ダウ船", "craft",
                  "さんかくの ほを はった きの ふねだよ"),
    417: original("🧶", "ふぇるとの じゅうたん", "フェルトの絨毯", "craft",
                  "ひつじの けを かためて もようを つけるよ"),
    418: original("🍚", "かおにゃお", "カオニャオ", "food",
                  "もちごめを むして てで まるめて たべるよ"),
    422: original("🌲", "ればのんすぎ", "レバノンスギ", "nature",
                  "えだを よこに ひろげる おおきな きだよ"),
    426: original("🧣", "ばそとぶらんけっと", "バソトブランケット", "craft",
                  "あつでで もようの ある あたたかい ぬのだよ"),
    428: original("💎", "こはく", "琥珀", "nature",
                  "むかしの きの しずくが かたまった いしだよ"),
    430: original("🦛", "こびとかば", "コビトカバ", "nature",
                  "もりの みずべに くらす ちいさな かばだよ"),
    434: original("🏛️", "れぷてぃすまぐないせき", "レプティス・マグナ遺跡", "landmark",
                  "うみの ちかくに のこる いしの まちだよ"),
    440: original("🍞", "らいむぎぱん", "ライ麦パン", "food",
                  "らいむぎで つくる くろっぽい ぱんだよ"),
    442: original("🏰", "ゔぃあんでんじょう", "ヴィアンデン城", "landmark",
                  "もりの おかに たつ おおきな しろだよ"),
    450: original("🌳", "ばおばぶ", "バオバブ", "nature",
                  "ふとい みきに みずを ためる おおきな きだよ"),
    454: original("🐟", "しくりっど", "シクリッド", "nature",
                  "みずうみに いろとりどりの さかなが くらすよ"),
    458: original("🏙️", "ぺとろなすついんたわー", "ペトロナスツインタワー", "landmark",
                  "ふたつの たかい とうが はしで つながるよ"),
    462: original("🪸", "さんごの かんしょう", "サンゴの環礁", "nature",
                  "さんごの しまが わの ように ならぶよ"),
    466: original("🧵", "ぼごらんふぃに", "ボゴランフィニ", "craft",
                  "どろで もようを そめる めんの ぬのだよ"),
    470: original("⛵", "るっつ", "ルッツ", "craft",
                  "めの もようを えがいた いろあざやかな ふねだよ"),
    478: original("🌀", "りしゃっとこうぞう", "リシャット構造", "nature",
                  "さばくに ひろがる おおきな わの もようだよ"),
    484: original("🌮", "たこす", "タコス", "food",
                  "うすい きじで にくや やさいを つつむよ"),
    496: original("⛺", "げる", "ゲル", "craft",
                  "はこんで たてられる まるい いえだよ"),
    498: original("🍇", "ぶどう", "ブドウ", "food",
                  "ひあたりの よい おかで あまい みが そだつよ"),
    499: original("⛰️", "ことるわん", "コトル湾", "nature",
                  "たかい やまに かこまれた ほそながい いりえだよ"),
    504: original("🍲", "たじん", "タジン", "food",
                  "とんがりぼうしの なべで むしにする りょうりだよ"),
    508: original("🌰", "かしゅーなっつ", "カシューナッツ", "food",
                  "まがった かたちの こうばしい きのみだよ"),
    512: original("🕯️", "にゅうこう", "乳香", "nature",
                  "きの しるを かためた かおりの よい かたまりだよ"),
    516: original("🏜️", "なみぶさばく", "ナミブ砂漠", "nature",
                  "あかい すなのおかが うみまで つづくよ"),
    524: original("🏔️", "ひまらやさんみゃく", "ヒマラヤ山脈", "nature",
                  "せかいで いちばん たかい やまが あるよ"),
    528: original("🌬️", "ふうしゃ", "風車", "landmark",
                  "おおきな はねを かぜで まわす たてものだよ"),
    554: original("🐦", "きーうぃ", "キーウィ", "nature",
                  "じめんを あるく つばさの ちいさな とりだよ"),
    558: original("🌋", "ももとんぼかざん", "モモトンボ火山", "nature",
                  "みずうみの そばに そびえる かざんだよ"),
    562: original("🦒", "にしあふりかきりん", "ニシアフリカキリン", "nature",
                  "しろっぽい からだに あみめが ある きりんだよ"),
    566: original("🗿", "のくの どぐう", "ノクの土偶", "craft",
                  "つちを やいて つくった むかしの ぞうだよ"),
    578: original("⛰️", "ふぃよるど", "フィヨルド", "nature",
                  "こおりが けずった ふかい いりえだよ"),
    586: original("🏔️", "けーつー", "ケーツー", "nature",
                  "ゆきと こおりに おおわれた とても たかい やまだよ"),
    591: original("🚢", "ぱなまうんが", "パナマ運河", "landmark",
                  "ふたつの うみを つなぐ ふねの みちだよ"),
    598: original("🐦", "ごくらくちょう", "ゴクラクチョウ", "nature",
                  "あざやかな かざりばねを もつ とりだよ"),
    600: original("🧉", "てれれ", "テレレ", "food",
                  "つめたい みずで いれる はっぱの のみものだよ"),
    604: original("🏔️", "まちゅぴちゅ", "マチュ・ピチュ", "landmark",
                  "たかい やまの うえに のこる いしの まちだよ"),
    608: original("🚌", "じーぷにー", "ジープニー", "craft",
                  "いろあざやかに かざった のりあいぐるまだよ"),
    616: original("🥟", "ぴえろぎ", "ピエロギ", "food",
                  "かわで じゃがいもなどを つつむ りょうりだよ"),
    620: original("🟦", "あずれーじょ", "アズレージョ", "craft",
                  "たてものを かざる いろもようの たいるだよ"),
    624: original("🌰", "かしゅーなっつ", "カシューナッツ", "food",
                  "あつい ちいきで こうばしい きのみが そだつよ"),
    626: original("🧵", "たいす", "タイス", "craft",
                  "いろいろな もようを おった ぬのだよ"),
    634: original("🦪", "しんじゅ", "真珠", "nature",
                  "かいの なかで まるく そだつ たからものだよ"),
    642: original("🥚", "いーすたーえっぐ", "彩色卵", "craft",
                  "たまごの からに こまかな もようを えがくよ"),
    643: original("🪆", "まとりょーしか", "マトリョーシカ", "craft",
                  "なかから つぎつぎ にんぎょうが でてくるよ"),
    646: original("🦍", "まうんてんごりら", "マウンテンゴリラ", "nature",
                  "たかい もりに くらす おおきな ごりらだよ"),
    682: original("🌴", "でーつ", "デーツ", "food",
                  "さばくの おあしすで あまい みが そだつよ"),
    686: original("🌳", "ばおばぶ", "バオバブ", "nature",
                  "ふとい みきと おおきな えだを もつ きだよ"),
    688: original("🫑", "あいばる", "アイバル", "food",
                  "あかい ぱぷりかを にこんだ ぺーすとだよ"),
    694: original("🐒", "ちんぱんじー", "チンパンジー", "nature",
                  "あつい もりで なかまと くらす さるだよ"),
    702: original("🦁", "まーらいおん", "マーライオン", "landmark",
                  "さかなの からだを もつ ししの ぞうだよ"),
    703: original("🏰", "すぴしゅじょう", "スピシュ城", "landmark",
                  "ひろい おかの うえに のこる いしの しろだよ"),
    704: original("🍜", "ふぉー", "フォー", "food",
                  "こめの めんを すーぷに いれた りょうりだよ"),
    705: original("🏞️", "ぶれっどこ", "ブレッド湖", "nature",
                  "しまの きょうかいが みずうみに うかぶよ"),
    706: original("🐪", "らくだ", "ラクダ", "nature",
                  "かわいた だいちで ひとや にもつを はこぶよ"),
    710: original("🌺", "ぷろてあ", "プロテア", "nature",
                  "おおきな はなびらの ように みえる はなだよ"),
    716: original("💧", "びくとりあの たき", "ビクトリアの滝", "nature",
                  "おおきな かわから みずが いっせいに おちるよ"),
    724: original("🥘", "ぱえりあ", "パエリア", "food",
                  "こめと うみの さちを ひらたい なべで たくよ"),
    728: original("🐦", "はしびろこう", "ハシビロコウ", "nature",
                  "おおきな くちばしで みずべに たつ とりだよ"),
    729: original("🔺", "めろえの ぴらみっど", "メロエのピラミッド", "landmark",
                  "さばくに ちいさな ぴらみっどが ならぶよ"),
    740: original("🦜", "ねったいうりん", "熱帯雨林", "nature",
                  "おおきな かわの そばに みどりの もりが ひろがるよ"),
    748: original("🦏", "しろさい", "シロサイ", "nature",
                  "そうげんに くらす おおきな つのの どうぶつだよ"),
    752: original("🐴", "だーらなほーす", "ダーラナホース", "craft",
                  "あざやかな もようを えがいた きの うまだよ"),
    756: original("🧀", "ちーず", "チーズ", "food",
                  "やまの ちちから いろいろな ちーずを つくるよ"),
    760: original("🧼", "あれっぽせっけん", "アレッポ石鹸", "craft",
                  "おりーぶの あぶらなどで つくる せっけんだよ"),
    762: original("🏔️", "ぱみーるこうげん", "パミール高原", "nature",
                  "ゆきの やまが つづく たかい だいちだよ"),
    764: original("🛺", "とぅくとぅく", "トゥクトゥク", "craft",
                  "さんりんで まちを はしる ちいさな のりものだよ"),
    768: original("🛖", "たきえんたの いえ", "タキエンタの家", "landmark",
                  "つちで つくった とうの ような いえだよ"),
    780: original("🥁", "すてぃーるぱん", "スティールパン", "craft",
                  "きんぞくの うつわを たたいて かなでる がっきだよ"),
    784: original("🏙️", "ぶるじゅはりふぁ", "ブルジュ・ハリファ", "landmark",
                  "くもに とどきそうな とても たかい たてものだよ"),
    788: original("🧩", "もざいく", "モザイク", "craft",
                  "ちいさな いしを ならべて えや もようを つくるよ"),
    792: original("🎈", "かっぱどきあ", "カッパドキア", "landmark",
                  "ふしぎな いわの うえを ききゅうが とぶよ"),
    795: original("🐎", "あはるてけ", "アハルテケ", "nature",
                  "きんいろに かがやく ほそみの うまだよ"),
    800: original("☕", "こーひー", "コーヒー", "food",
                  "みどりの おかで かおりの よい まめが そだつよ"),
    804: original("🌻", "ひまわり", "ヒマワリ", "nature",
                  "ひろい はたけに きいろい はなが ならぶよ"),
    807: original("🏞️", "おふりどこ", "オフリド湖", "nature",
                  "やまに かこまれた とうめいな みずうみだよ"),
    818: original("🔺", "ぴらみっど", "ピラミッド", "landmark",
                  "おおきな いしを つんだ さんかくの いせきだよ"),
    826: original("🕰️", "びっぐべん", "ビッグ・ベン", "landmark",
                  "おおきな とけいが ついた たかい とうだよ"),
    834: original("🏔️", "きりまんじゃろ", "キリマンジャロ", "nature",
                  "あかみちかくに そびえる とても たかい やまだよ"),
    840: original("🏜️", "ぐらんどきゃにおん", "グランドキャニオン", "nature",
                  "かわが けずった おおきな たにだよ"),
    854: original("🗿", "ぶろんずちょうこく", "ブロンズ彫刻", "craft",
                  "きんぞくを とかして ひとや どうぶつを つくるよ"),
    858: original("🧉", "まてちゃ", "マテ茶", "food",
                  "はっぱを いれた うつわから すって のむ おちゃだよ"),
    860: original("🕌", "れぎすたんひろば", "レギスタン広場", "landmark",
                  "あおい たいるの おおきな たてものが ならぶよ"),
    862: original("💧", "えんじぇるふぉーる", "エンジェルフォール", "nature",
                  "たかい だいちから ながく おちる たきだよ"),
    887: original("🌳", "りゅうけつじゅ", "竜血樹", "nature",
                  "かさの ように えだを ひろげる ふしぎな きだよ"),
    894: original("💎", "えめらるど", "エメラルド", "nature",
                  "みどりいろに かがやく うつくしい いしだよ"),
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
    missing_originals = sorted({c["code"] for c in recorded} - set(ORIGINALS))
    if missing_originals:
        sys.exit(f"recorded countries without originals: {missing_originals}")

    cards = []
    for country in recorded:
        code = country["code"]
        # 国旗だけでは国を見分けにくいので、札面のタイトルは国名にする。
        # category は flag のままなので、カード種別と国名は混同しない。
        # 国名は WorldShapes.json から引き、ここに第 2 の正本を作らない。
        description = f"{country['kana']}の こっきだよ"
        if not is_kids_text(description):
            sys.exit(f"description for {code} is not kids text: {description}")
        cards.append({
            "id": f"{code}-1",
            "prefectureCode": code,
            "emoji": flag_emoji(alpha2[code]),
            "nameKana": country["kana"],
            "nameKanji": country["nameJa"],
            "category": "flag",
            "description": description,
            # "art" は無し: 絵文字がそのまま国旗で、プレースホルダを作らない。
        })
        original = ORIGINALS.get(code)
        if original is None:
            continue  # 上の完全性検査があるため到達しない防御。
        if original["category"] not in ORIGINAL_CATEGORIES:
            sys.exit(f"original for {code} has bad category: "
                     f"{original['category']}")
        if not is_kids_text(original["nameKana"]):
            sys.exit(f"nameKana for {code}-2 is not kids text: "
                     f"{original['nameKana']}")
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
