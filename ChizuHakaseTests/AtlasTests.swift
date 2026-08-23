import CoreGraphics
import Foundation
import SwiftUI
import Testing

@testable import ChizuHakase

/// 世界アトラス Task 5: Atlas 抽象。
///
/// アトラスは境界で世界データを既存の値型(MapData / Stage / CardCatalog)へ
/// 流し込む変換器なので、ここで検証するのは 2 点だけ:
/// 日本アトラスが現行ローダと同一のデータを運ぶこと(挙動が変わっていない)、
/// 世界アトラスの変換がフィールドを 1:1 で保つこと。
@MainActor
struct AtlasTests {

    static let japanMap = MapDataLoader.loadMapData(contentsOf: TestResources.require("PrefectureShapes"))
    static let japanCards = MapDataLoader.loadCards(contentsOf: TestResources.require("SpecialtyCards"))
    static let worldCards = MapDataLoader.loadCards(contentsOf: TestResources.require("WorldCards"))

    /// WorldDataTests と同じく `Result` 包み: static 初期化子では try が
    /// 書けず、`try!`(§11 で禁止)を避けるため。
    static let world = Result {
        try WorldDataLoader.load(contentsOf: TestResources.require("WorldShapes"))
    }

    private var japanAtlas: Atlas {
        Atlas.japan(mapData: Self.japanMap, cards: Self.japanCards)
    }

    private func worldAtlas() throws -> Atlas {
        Atlas.world(from: try Self.world.get(), cards: Self.worldCards)
    }

    // MARK: - 日本アトラス(現行データがそのまま出てくること)

    @Test func 日本アトラスは現行ローダと同一のデータを運ぶ() {
        let atlas = japanAtlas
        #expect(atlas.mapData.prefectures.count == 47)
        #expect(atlas.mapData.prefectures == Self.japanMap.prefectures)
        #expect(atlas.mapData.width == Self.japanMap.width)
        #expect(atlas.mapData.height == Self.japanMap.height)
        #expect(atlas.mapData.insets == Self.japanMap.insets)
        #expect(atlas.mapData.background.isEmpty)
        #expect(atlas.mapData[13]?.name == "東京都")
        #expect(atlas.mapData[1]?.kana == "ほっかいどう")
    }

    @Test func 日本アトラスのステージとカードは現行のまま() {
        let atlas = japanAtlas
        #expect(atlas.stages == Stage.all)
        #expect(atlas.cards.count == 141)
        #expect(atlas.cards.all == Self.japanCards.all)
    }

    /// AppState が起動時に組み立てていた語彙(かな + 表記)と同じもの。
    @Test func 日本アトラスの語彙はよみと表記の両方を含む() {
        let vocabulary = japanAtlas.voiceVocabulary
        #expect(vocabulary.count == 47 * 2)
        #expect(vocabulary.contains("ほっかいどう"))
        #expect(vocabulary.contains("北海道"))
    }

    // MARK: - 世界アトラス(変換が 1:1 であること)

    @Test func 世界アトラスは167カ国を県として運ぶ() throws {
        let atlas = try worldAtlas()
        #expect(atlas.mapData.prefectures.count == 167)
        let codes = atlas.mapData.prefectures.map(\.code)
        #expect(zip(codes, codes.dropFirst()).allSatisfy { $0 < $1 }, "コードが昇順・一意でない")
    }

    @Test func 変換がフィールドを1対1で保つ() throws {
        let world = try Self.world.get()
        let atlas = Atlas.world(from: world)
        for (country, pref) in zip(world.recordedCountries, atlas.mapData.prefectures) {
            #expect(pref.code == country.code)
            #expect(pref.name == country.nameJa, "code \(country.code)")
            #expect(pref.kana == country.kana, "code \(country.code)")
            #expect(pref.centroid == country.flatCentroid, "code \(country.code)")
            #expect(pref.bbox == country.flatBbox, "code \(country.code)")
            #expect(pref.rings == country.flatRings, "code \(country.code)")
        }
        // 名前とよみのスポットチェック(zip が空回りしていないことの錨)
        #expect(atlas.mapData[392]?.name == "日本")
        #expect(atlas.mapData[392]?.kana == "にほん")
    }

    /// インセット国(裁定 2026-08-19)も普通の収録国として変換される。
    /// 拡大表示は描画側の後続タスクで、データからは消えない。
    @Test func インセット国も収録国として存在する() throws {
        let atlas = try worldAtlas()
        for code in [242, 462, 470, 702] {
            #expect(atlas.mapData[code] != nil, "code \(code) が地図から消えた")
        }
    }

    @Test func 世界アトラスの全パスが空でない() throws {
        let atlas = try worldAtlas()
        for pref in atlas.mapData.prefectures {
            let path = PrefectureGeometry.path(for: pref, transform: .identity)
            #expect(!path.isEmpty, "code \(pref.code) produced an empty Path")
        }
    }

    @Test func 世界アトラスの地方18面が全国を尽くしチャレンジが19面目に立つ() throws {
        let world = try Self.world.get()
        let atlas = Atlas.world(from: world)
        #expect(atlas.stages.count == 19)
        #expect(atlas.stages.map(\.index) == Array(0...18))
        for (worldStage, stage) in zip(world.stages, atlas.stages) {
            #expect(stage.name == worldStage.name, "stage \(stage.index)")
            #expect(stage.kanjiName == worldStage.kanjiName, "stage \(stage.index)")
            #expect(stage.codes == worldStage.codes, "stage \(stage.index)")
        }
        // 地方 18 面が全国を過不足なく尽くす(チャレンジは同じ 167 の再掲)。
        let regionalCodes = atlas.stages.dropLast().flatMap(\.codes)
        #expect(regionalCodes.count == 167)
        #expect(Set(regionalCodes).count == regionalCodes.count, "国が複数ステージに重複")
        #expect(Set(regionalCodes) == Set(atlas.mapData.prefectures.map(\.code)))
        // 19 面目は本の全収録国をコード昇順で束ねる。
        #expect(atlas.stages.last?.codes == atlas.mapData.prefectures.map(\.code))
    }

    /// `Stage.isChallenge` は stored で既定 false(P7 Task 4 — 「47 県か」の
    /// 導出をやめた)。JSON 由来の 18 面は既定のまま通り、設計どおり全部が
    /// 1 国 2 回出題の地方ステージになる。
    @Test func 世界の地方ステージはすべて2回出題() throws {
        let atlas = try worldAtlas()
        for stage in atlas.stages where stage.index != WorldStage.challengeIndex {
            #expect(!stage.isChallenge, "stage \(stage.index)")
            #expect(stage.asksEachTwice, "stage \(stage.index)")
            #expect(stage.questionCount == stage.codes.count * 2, "stage \(stage.index)")
        }
    }

    /// 総合ステージだけが isChallenge を名乗る — VM/ステージ突き合わせテスト
    /// (QuizViewModelTests)が捕まえられない逆方向(19 面目が false のまま
    /// 334 問で自己整合する壊れ方)を、こちら側で塞ぐピン。
    /// ★名前は仮文言(ユーザーサインオフ待ち — 「ぜんこく チャレンジ」と同型)。
    @Test func 世界の19面目だけがチャレンジを名乗る() throws {
        let atlas = try worldAtlas()
        let challenges = atlas.stages.filter(\.isChallenge)
        #expect(challenges.map(\.index) == [WorldStage.challengeIndex])
        let challenge = try #require(challenges.first)
        #expect(challenge.name == "せかい チャレンジ")
        #expect(challenge.kanjiName == "世界チャレンジ")
        #expect(challenge.codes.count == 167)
        #expect(!challenge.asksEachTwice)
        #expect(challenge.questionCount == GameRules.challengeQuestionCount,
                "the sitting is \(challenge.questionCount) questions, not 47")
    }

    // MARK: - 地域ズーム(P7 Task 4 — ボタンの地理も Atlas が運ぶ)

    /// 日本は従来の 3 分割(コードは旧 `Stage.eastJapanCodes` らと同値)。
    /// 並びは画面の縦積み順 — 東が上、西が下(列島の斜めに合わせる)。
    @Test func 日本アトラスは3つの地域ズームを運ぶ() {
        let zooms = japanAtlas.regionZooms
        #expect(zooms.map(\.codes) == [Array(1...14), Array(15...30),
                                       [27, 28] + Array(31...47)])
        #expect(zooms.map { $0.label.label(.kids) }
                == ["ひがしにほん", "なかにほん", "にしにほん"])
        #expect(zooms.map { $0.label.label(.adult) }
                == ["東日本", "中日本", "西日本"])
    }

    /// `RegionZoom.id` はボタンの語(label.kids)そのもの。QuizView の
    /// ForEach がこの id に乗るので、同じ語が 2 つのズームに付くと描画が
    /// 未定義になる — 一意性をここで釘打つ。
    @Test func 地域ズームのidは一意() {
        let ids = RegionZoom.japanThirds.map(\.id)
        #expect(Set(ids).count == ids.count, "ids = \(ids)")
    }

    /// 世界は空 — 1–47 は世界では別の国の ISO コードで、日本の分割は世界地図を
    /// でたらめに囲む(Atlas.swift の旧道標が言っていた罠)。ワールドチャレンジの
    /// 平面は地球儀の控えなので、世界用の分割も足さない(YAGNI)。
    @Test func 世界アトラスは地域ズームを運ばない() throws {
        #expect(try worldAtlas().regionZooms.isEmpty)
        let missing = URL(fileURLWithPath: "/nonexistent/WorldShapes.json")
        #expect(Atlas.loadWorld(contentsOf: missing).regionZooms.isEmpty)
    }

    // MARK: - ステージ棚のセクション(大陸見出し — UI 決定 2026-08-20)

    /// 日本は見出しなし: 棚は 1 段で、今日のステージ選択と 1 ピクセルも
    /// 変わらない並びのまま。
    @Test func 日本の棚は見出しなしの1段() {
        let atlas = japanAtlas
        #expect(atlas.sections.isEmpty)
        #expect(atlas.stageShelves == [Atlas.StageShelf(title: nil, stages: Stage.all)])
    }

    /// 見出しは stage index 区間から機械的に引く(0–2 アメリカ / 3–6 ヨーロッパ /
    /// 7–11 アフリカ / 12–16 アジア / 17 オセアニア / 18 そうごう)。
    /// チャレンジは「余り」枝(title: nil)ではなく自分の見出しの下に立つ —
    /// 余り枝はデータ食い違いの診断用で、正規ステージの置き場ではない。
    @Test func 世界の棚は5大陸とそうごうの見出しで区切られる() throws {
        let atlas = try worldAtlas()
        #expect(atlas.sections == WorldStage.sections)
        let shelves = atlas.stageShelves
        #expect(shelves.map(\.title)
                == ["アメリカ", "ヨーロッパ", "アフリカ", "アジア", "オセアニア",
                    "そうごう"])
        #expect(shelves.map { $0.stages.map(\.index) }
                == [[0, 1, 2], [3, 4, 5, 6], [7, 8, 9, 10, 11],
                    [12, 13, 14, 15, 16], [17], [18]])
        // 棚に組み替えてもステージは 1 面も消えず、順も変わらない。
        #expect(shelves.flatMap(\.stages) == atlas.stages)
    }

    /// 空へ倒れた世界アトラスは見出し定義こそ世界のままだが、中身のない
    /// 見出しは棚に立てない(空の棚 > 空の見出しの列)。
    @Test func 空へ倒れた世界アトラスの棚は空() {
        let missing = URL(fileURLWithPath: "/nonexistent/WorldShapes.json")
        let atlas = Atlas.loadWorld(contentsOf: missing)
        #expect(atlas.sections == WorldStage.sections)
        #expect(atlas.stageShelves.isEmpty)
    }

    /// 区間が尽くしていないステージも棚から消えない — 見出しなしで末尾に残る。
    /// (データの食い違いでステージが遊べなくなる壊れ方だけはしない。)
    @Test func 区間から漏れたステージは見出しなしで末尾に残る() {
        let stray = Stage(index: 99, name: "はぐれ", kanjiName: "逸れ", codes: [1])
        let atlas = Atlas(mapData: .empty, globe: nil, stages: Stage.all + [stray],
                          stageLandmarkAssetNames: Stage.landmarkAssetNames,
                          sections: [AtlasSection(title: "テスト", stageIndexes: 0..<7)],
                          regionZooms: [], cards: .empty, drawPolicy: .random,
                          saveKey: "test",
                          regionNoun: .prefecture, cardNoun: .specialtyCards)
        let shelves = atlas.stageShelves
        #expect(shelves.count == 2)
        #expect(shelves.first?.title == "テスト")
        #expect(shelves.first?.stages == Stage.all)
        #expect(shelves.last == Atlas.StageShelf(title: nil, stages: [stray]))
    }

    // MARK: - 世界のカード目録(WorldCards.json)

    /// 全 167 カ国が国旗 + オリジナルを 1 枚ずつ持つ。
    /// オリジナルは絵文字先行(P8 裁定 1)— 絵は後続バッチが持ってくる。
    @Test func 世界の目録は国旗とオリジナルが167枚ずつ() throws {
        let atlas = try worldAtlas()
        #expect(atlas.cards.count == 334)
        let flags = atlas.cards.all.filter { $0.category == .flag }
        let originals = atlas.cards.all.filter { $0.category != .flag }
        #expect(flags.count == 167)
        #expect(originals.count == 167)
        for card in flags {
            #expect(card.art == nil, "\(card.id): 絵文字が国旗そのもの、絵は持たない")
        }
    }

    /// 収録国とカードの持ち主が過不足なく一致する — `SaveStore.applyStageResult`
    /// の一巡判定(チャレンジ履歴の lap リセット)が「全収録国」の分母を
    /// 目録から引くための土台で、これが割れると 2 周目が来ない/早く来る。
    /// P8 でオリジナル札が並んでも(1 国複数枚になっても)この対応は
    /// 崩れない — 崩すならリセットの分母ごと設計し直すこと。
    @Test func 目録の持ち主は収録国と過不足なく一致する() throws {
        let atlas = try worldAtlas()
        #expect(Set(atlas.cards.all.map(\.prefectureCode))
                == Set(atlas.mapData.prefectures.map(\.code)))
    }

    /// 各国の先頭札は国旗 — `GameRules.DrawPolicy.flagFirstSilverGate` が
    /// `catalog.cards(for:).first` から受け取る契約。テストは id を読んで
    /// 確かめてよいが、製品コードは並びだけを信じる(id の解析はしない)。
    @Test func 各国の先頭札は国旗() throws {
        let atlas = try worldAtlas()
        for pref in atlas.mapData.prefectures {
            let cards = atlas.cards.cards(for: pref.code)
            #expect(!cards.isEmpty, "code \(pref.code) has no cards")
            #expect(cards.first?.id == "\(pref.code)-1",
                    "code \(pref.code): first card is \(cards.first?.id ?? "nil")")
            #expect(cards.first?.category == .flag,
                    "code \(pref.code): 先頭札が国旗を名乗っていない")
        }
    }

    /// 国旗の絵だけでは国を見分けられない子もいるため、札面のタイトルは
    /// 「国旗」ではなく持ち主の国名を表示する。かな/通常表記とも地図データを
    /// 正本にして、図鑑とクイズで国名が食い違わないようにする。
    @Test func 国旗カードのタイトルは国名() throws {
        let atlas = try worldAtlas()
        for pref in atlas.mapData.prefectures {
            let flag = try #require(atlas.cards.cards(for: pref.code).first)
            #expect(flag.nameKana == pref.kana, "code \(pref.code)")
            #expect(flag.nameKanji == pref.name, "code \(pref.code)")
        }
    }

    /// オリジナル札(P8): id は "{code}-2" で、国旗の直後 = その国の 2 枚目に
    /// 立つ。国旗は -1 の持ち場なので、-2 が flag を名乗ったら生成器の誤り。
    @Test func オリジナル札は国旗の直後に立ち国旗を名乗らない() throws {
        let atlas = try worldAtlas()
        let originals = atlas.cards.all.filter { $0.category != .flag }
        #expect(!originals.isEmpty, "オリジナル札がまだ目録に無い")
        for card in originals {
            #expect(card.id == "\(card.prefectureCode)-2", "id \(card.id)")
            let siblings = atlas.cards.cards(for: card.prefectureCode)
            #expect(siblings.count == 2, "code \(card.prefectureCode)")
            #expect(siblings.last == card,
                    "code \(card.prefectureCode): -2 が 2 枚目に居ない")
        }
    }

    /// パイロットのサインオフ後に全地域へ展開済み。国旗先行ゲートは 2 枚目が
    /// ある前提で解放を約束するので、1 国でも欠けたら目録を出荷しない。
    @Test func 全収録国がオリジナル札を持つ() throws {
        let atlas = try worldAtlas()
        for pref in atlas.mapData.prefectures {
            let cards = atlas.cards.cards(for: pref.code)
            #expect(cards.count == 2, "code \(pref.code)")
            #expect(cards.last?.id == "\(pref.code)-2", "code \(pref.code)")
        }
    }

    /// 読みと説明文はこども表記: ひらがな・カタカナ・語間スペース・長音だけ。
    /// 漢字が混ざったら生成器の検査漏れ(読めない子に届かない札になる)。
    @Test func 全札の読みと説明はかなとスペースだけでできている() throws {
        for card in try worldAtlas().cards.all {
            for text in [card.nameKana, card.description] {
                for scalar in text.unicodeScalars {
                    let value = scalar.value
                    let allowed = value == 0x20 || value == 0x30FC
                        || (0x3041...0x3096).contains(value)
                        || (0x30A1...0x30FA).contains(value)
                    #expect(allowed, "\(card.id): \(text) に \(scalar)")
                }
            }
        }
    }

    /// 国旗の絵文字は地域指標記号 2 文字(端末フォントが描く実物の国旗)。
    /// オリジナル札は題材の絵文字で、国旗絵文字は使わない — 国旗は -1 の
    /// 持ち場で、二重に配ると札種の違いが絵から消える。
    @Test func 国旗カードの絵文字は地域指標記号() throws {
        let indicators: ClosedRange<UInt32> = 0x1F1E6...0x1F1FF
        for card in try worldAtlas().cards.all {
            let scalars = card.emoji.unicodeScalars
            let isFlagEmoji = scalars.count == 2
                && scalars.allSatisfy { indicators.contains($0.value) }
            #expect(isFlagEmoji == (card.category == .flag),
                    "\(card.id): \(card.emoji)")
        }
    }

    /// 出荷される WorldCards.json そのものの並びの契約(生成器のソートを
    /// リソース側で固定する): (国コード, 連番) 昇順で、各国の先頭が連番 1。
    /// `CardCatalog` は Dictionary(grouping:) で並びを保持するだけなので、
    /// この配列順が崩れたら抽選ゲートは静かに壊れる — だからファイルを直接読む。
    @Test func 出荷リソースの並びは国コードと連番の昇順() throws {
        struct File: Decodable {
            struct Card: Decodable {
                let id: String
                let prefectureCode: Int
            }
            let cards: [Card]
        }
        let file = try JSONDecoder().decode(
            File.self, from: Data(contentsOf: TestResources.require("WorldCards")))
        let keys = try file.cards.map { card -> (Int, Int) in
            let ordinal = try #require(Int(card.id.split(separator: "-").last ?? ""),
                                       "malformed id \(card.id)")
            #expect(card.id == "\(card.prefectureCode)-\(ordinal)",
                    "id \(card.id) does not carry its own country code")
            return (card.prefectureCode, ordinal)
        }
        #expect(zip(keys, keys.dropFirst()).allSatisfy { $0 < $1 },
                "cards are not sorted by (code, ordinal)")
        var seen = Set<Int>()
        for (code, ordinal) in keys where seen.insert(code).inserted {
            #expect(ordinal == 1, "code \(code): first card is not the flag")
        }
    }

    /// バンドル配線の確認: 実バンドルの `loadWorld()` が目録まで運ぶこと。
    /// (上のテストはテスト用 URL 経由なので、リソースがアプリターゲットに
    /// 入り忘れてもすり抜ける。)
    @Test func バンドルからの読み込みもカードを運ぶ() {
        #expect(Atlas.loadWorld().cards.count == 334)
    }

    /// 引き継ぎ 2 の罠を実データで固定する: カード ID は 2 冊の間で文字列
    /// 衝突する(日本 "12-1" = 千葉の らっかせい、世界 "12-1" = アルジェリア
    /// の国旗)。結果・ずかん・マイマップの札解決が atlas.cards を通るのは
    /// これが理由で、「目録は 1 本にまとめられる」式の簡素化はこのテストが
    /// 落ちて止める。衝突が現に存在すること自体も pin する — 衝突が消えたら
    /// このガードの前提ごと見直してよい。
    @Test func カードIDは本の間で衝突し目録ごとに別の札へ解決する() {
        let japanIDs = Set(Self.japanCards.all.map(\.id))
        let collisions = japanIDs.intersection(Self.worldCards.all.map(\.id))
        let expected = Set([12, 24, 31, 32, 36, 40, 44].flatMap {
            ["\($0)-1", "\($0)-2"]
        })
        #expect(collisions == expected, "collisions = \(collisions.sorted())")
        for id in collisions {
            #expect(Self.japanCards[id]?.category != .flag,
                    "\(id): japan's card should not be a flag")
            #expect((Self.worldCards[id]?.category == .flag) == id.hasSuffix("-1"),
                    "\(id): world's first card alone should be a flag")
            #expect(Self.japanCards[id] != Self.worldCards[id],
                    "\(id): the two books resolved to the same card")
        }
    }

    @Test func 世界アトラスの地図寸法が投影と一致する() throws {
        let atlas = try worldAtlas()
        // 幅 1000 正規化は収録国基準(WorldDataTests と同じ根拠)。
        #expect(abs(atlas.mapData.width - 1000) < 0.5, "width = \(atlas.mapData.width)")
        #expect(atlas.mapData.height > 0)
    }

    /// インセット枠・背景海岸線・ロシアの枠 bbox が MapData まで届くこと。
    /// 描画側(PrefectureMapView)はこの値を見るだけで、japan/world を知らない。
    @Test func 世界アトラスは枠と背景を地図ごと運ぶ() throws {
        let world = try Self.world.get()
        let atlas = Atlas.world(from: world)

        // 破線枠は裁定の 4 カ国ぶん。対象国の形(ロード時に拡大・移動済み)は
        // 自分の枠の中に収まる — 沖縄と同じ「別枠」の見た目が成立する条件。
        #expect(atlas.mapData.insets.map(\.code).sorted() == [242, 462, 470, 702])
        for inset in atlas.mapData.insets {
            let country = try #require(atlas.mapData[inset.code])
            #expect(inset.frame.contains(country.bbox),
                    "code \(inset.code): \(country.bbox) escapes \(inset.frame)")
            #expect(inset.frame.contains(country.centroid), "code \(inset.code)")
        }

        // 背景は「コード無しの海岸線」のまま、間引き用の bbox が付いて渡る。
        #expect(!atlas.mapData.background.isEmpty)
        for (shape, source) in zip(atlas.mapData.background, world.background) {
            #expect(shape.rings == source.flatRings)
            for point in shape.rings.flatMap({ $0 }) {
                #expect(shape.bbox.insetBy(dx: -0.01, dy: -0.01).contains(point))
            }
        }

        // ロシアだけがステージ枠用の frameBbox(= europeBbox)を運ぶ。
        let russia = try #require(atlas.mapData[643])
        #expect(russia.frameBbox == world[643]?.europeBbox)
        for pref in atlas.mapData.prefectures where pref.code != 643 {
            #expect(pref.frameBbox == nil, "code \(pref.code)")
        }
    }

    /// インセット国のタップは沖縄と同じ仕組みで成立する: 形が拡大されて
    /// 枠内に実在するので、既存の resolveTap がそのまま当てる。枠のそばの
    /// 近いはずれも許容(§3 の 22pt)に拾われる — 別枠は空き海域に置かれる
    /// ので、競合する隣国がいない。
    @Test func インセット国は枠内のタップで当たる() throws {
        let atlas = try worldAtlas()
        for inset in atlas.mapData.insets {
            let country = try #require(atlas.mapData[inset.code])
            let stage = try #require(atlas.stages.first {
                $0.codes.contains(inset.code)
            })
            let members = atlas.mapData.prefectures(in: stage.codes)
            let transform = PrefectureGeometry.fitTransform(
                bounds: PrefectureGeometry.boundingBox(of: members),
                into: CGSize(width: 380, height: 380))
            // ど真ん中(重心)への直撃。
            let centroid = PrefectureGeometry.screenCentroid(
                of: country, transform: transform)
            #expect(PrefectureGeometry.resolveTap(
                at: centroid, target: country, among: members,
                transform: transform)?.code == inset.code, "code \(inset.code)")
            // 少し外した指(10pt 右)も、訊かれている国なら拾われる。
            let near = CGPoint(x: centroid.x + 10, y: centroid.y)
            #expect(PrefectureGeometry.resolveTap(
                at: near, target: country, among: members,
                transform: transform)?.code == inset.code, "code \(inset.code)")
        }
    }

    /// インセットの存在理由をそのまま数字で固定する: 拡大後の国はステージ表の
    /// 機械判定の帯(10pt 未満は収録外候補)を、自分のステージの 380pt
    /// パネル基準で超えている。倍率はパイプラインが帯から導く
    /// (tools/build_world_map_data.py の INSET_SCALE_FLOOR 周辺)ので、
    /// ここが割れたら生成規則と画面の換算がずれている。
    @Test func インセット国は拡大後に10ptの帯へ届く() throws {
        let atlas = try worldAtlas()
        for inset in atlas.mapData.insets {
            let country = try #require(atlas.mapData[inset.code])
            let stage = try #require(atlas.stages.first {
                $0.codes.contains(inset.code)
            })
            let frame = PrefectureGeometry.boundingBox(
                of: atlas.mapData.prefectures(in: stage.codes))
            // パイプラインと同じ幅基準の換算(パネルは幅で決まり、高さは
            // aspect fit で付いてくる)。定数は GameRules の実物から引く。
            let ptPerUnit = (380 - 2 * GameRules.mapPaddingPoints)
                / (frame.width * (1 + 2 * GameRules.mapPaddingRatio))
            let size = max(country.bbox.width, country.bbox.height) * ptPerUnit
            #expect(size >= 10, "code \(inset.code) is \(size)pt — 帯に届かない")
        }
    }

    /// モルドバ 13pt 問題(2026-08-18-world-stages.md)の解消を数字で固定する:
    /// ひがしヨーロッパのステージ枠はロシアの europeBbox までで、その枠を
    /// 380pt に収めたときモルドバが日本版の香川帯(10–22pt)を超えて描かれる。
    @Test func ひがしヨーロッパの枠でモルドバがタップ寸法に届く() throws {
        let atlas = try worldAtlas()
        let stage = try #require(atlas.stage(at: 5))
        let members = atlas.mapData.prefectures(in: stage.codes)
        let frame = PrefectureGeometry.boundingBox(of: members)
        let russia = try #require(atlas.mapData[643])
        // 枠はウラル線まで — 全土 bbox ならこの 2.5 倍を超えて広がる。
        #expect(frame.width < russia.bbox.width * 0.5,
                "frame \(frame) still spans Siberia")
        let transform = PrefectureGeometry.fitTransform(
            bounds: frame, into: CGSize(width: 380, height: 380))
        let moldova = try #require(atlas.mapData[498]).bbox.applying(transform)
        #expect(max(moldova.width, moldova.height) > 22,
                "Moldova is \(moldova.size) on a 380pt panel")
    }

    @Test func 世界アトラスの語彙はよみと表記の両方を含む() throws {
        let vocabulary = try worldAtlas().voiceVocabulary
        #expect(vocabulary.count == 167 * 2)
        #expect(vocabulary.contains("にほん"))
        #expect(vocabulary.contains("日本"))
        // ゆれ吸収の 2 系(P6 Task 5): 短いよみと正式表記の両方が
        // contextualStrings に乗る — 「あめりか」「アメリカ合衆国」のどちらで
        // 認識されても照合器(PrefectureNameMatcher)側に受理形がある。
        #expect(vocabulary.contains("あめりか"))
        #expect(vocabulary.contains("アメリカ合衆国"))
        #expect(vocabulary.allSatisfy { !$0.isEmpty })
    }

    // MARK: - 地球儀データ(P7 Task 2 — View は本ではなくこの値の有無で分岐)

    /// 地球儀は世界だけが運ぶ。日本と、空へ倒れた世界は nil — View は
    /// 「globe の有無」を見るだけで japan/world を知らない(インセット判定と
    /// 同じ規律)。
    @Test func 地球儀データは世界だけが運ぶ() throws {
        #expect(japanAtlas.globe == nil)
        let world = try worldAtlas()
        #expect(world.globe?.shapes.count == 167)
        let missing = URL(fileURLWithPath: "/nonexistent/WorldShapes.json")
        #expect(Atlas.loadWorld(contentsOf: missing).globe == nil)
    }

    // MARK: - 抽選方針(設計 §5: 日本との差分は抽選だけ、データが運ぶ)

    /// 方針はアトラスの属性。view は分岐を見ず、QuizViewModel は
    /// この値を GameRules.drawCard へ渡すだけになる(P5 の配線)。
    @Test func 日本アトラスは従来ランダムの抽選方針を運ぶ() {
        #expect(japanAtlas.drawPolicy == .random)
    }

    @Test func 世界アトラスは国旗先行の抽選方針を運ぶ() throws {
        #expect(try worldAtlas().drawPolicy == .flagFirstSilverGate)
        // 読み込みに失敗して空へ倒れたアトラスも世界の方針のまま —
        // カードが空でも「どの本か」までは失わない。
        let missing = URL(fileURLWithPath: "/nonexistent/WorldShapes.json")
        #expect(Atlas.loadWorld(contentsOf: missing).drawPolicy == .flagFirstSilverGate)
    }

    // MARK: - 解放予告(P8 Task 2 — 札 → 解放される物の名詞)

    /// 国旗がシルバーに達するとオリジナル札が解放される(flagFirstSilverGate)
    /// ので、その国旗の「あと◯」はシルバーではなく解放される物を名乗る。
    /// 予告は嘘をつかない(P8 裁定 3): 全収録国に 2 枚目が実在するので、
    /// すべての国旗がオリジナルカードの解放を名乗る。
    @Test func 世界の国旗札はオリジナル解放を予告する() throws {
        let atlas = try worldAtlas()
        for pref in atlas.mapData.prefectures {
            let flag = try #require(atlas.cards["\(pref.code)-1"])
            #expect(atlas.unlockGoalNoun(for: flag) == .originalCard,
                    "code \(pref.code)")
        }
    }

    /// 解放される側の札に予告する物は無い — シルバーの先はただのゴールド。
    @Test func オリジナル札そのものは解放を予告しない() throws {
        let atlas = try worldAtlas()
        let original = try #require(atlas.cards["156-2"])
        #expect(atlas.unlockGoalNoun(for: original) == nil)
    }

    /// 日本の抽選は .random でゲートが無い — どの札も解放を予告しない。
    @Test func 日本の札は解放を予告しない() {
        let atlas = japanAtlas
        for card in atlas.cards.all {
            #expect(atlas.unlockGoalNoun(for: card) == nil, "\(card.id)")
        }
    }

    // MARK: - 語彙(名詞もアトラスが運ぶ — view に japan/world 分岐を作らない)

    /// 結果画面の「✨ おぼえた ◯!」やなまえあての問いに入る名詞(P6 Task 6)。
    /// 世界の結果画面に「けん」が出た Task 3 レビューへの答えで、語は文言の
    /// 分岐ではなくデータとして本に綴じる — 抽選方針や saveKey と同じ運び方。
    @Test func アトラスは地域の名詞を運ぶ() throws {
        #expect(japanAtlas.regionNoun == .prefecture)
        #expect(try worldAtlas().regionNoun == .country)
        // 読み込みに失敗して空へ倒れた世界も、語までは失わない。
        let missing = URL(fileURLWithPath: "/nonexistent/WorldShapes.json")
        #expect(Atlas.loadWorld(contentsOf: missing).regionNoun == .country)
    }

    /// カード欄の見出し: 日本は とくさんひん、世界は(国旗しかない今も P8 で
    /// オリジナル札が並んだ後も嘘にならない)せかいの カード。
    @Test func アトラスはカード欄の見出しを運ぶ() throws {
        #expect(japanAtlas.cardNoun == .specialtyCards)
        #expect(try worldAtlas().cardNoun == .worldCards)
        let missing = URL(fileURLWithPath: "/nonexistent/WorldShapes.json")
        #expect(Atlas.loadWorld(contentsOf: missing).cardNoun == .worldCards)
    }

    // MARK: - セーブの名前空間とステージ引き

    /// セーブの名前空間は資源と同じ値の中を旅する。空へ倒れた世界アトラスも
    /// 世界のキーのまま — 間違っても日本の記録へ書きにいかない。
    @Test func アトラスはセーブの名前空間キーを運ぶ() throws {
        #expect(japanAtlas.saveKey == SaveData.japanAtlas)
        #expect(try worldAtlas().saveKey == SaveData.worldAtlas)
        let missing = URL(fileURLWithPath: "/nonexistent/WorldShapes.json")
        #expect(Atlas.loadWorld(contentsOf: missing).saveKey == SaveData.worldAtlas)
    }

    /// index → ステージはアトラス内で引く。3 は日本では きんき、世界では
    /// きたヨーロッパ — 同じ数字が本ごとに別の場所を指す(records と同じ)。
    @Test func ステージはアトラス内のindexで引く() throws {
        #expect(japanAtlas.stage(at: 3)?.name == "きんき")
        #expect(try worldAtlas().stage(at: 3)?.name == "きたヨーロッパ")
        #expect(try worldAtlas().stage(at: 15)?.name == "ひがしアジア")
        #expect(try worldAtlas().stage(at: 18)?.name == "せかい チャレンジ")
        #expect(try worldAtlas().stage(at: 19) == nil)
    }

    // MARK: - 平面ズーム上限(P9: 世界チャレンジの平面地図)

    /// 上限は手置きではなくデータから導く(沖縄インセットの空き海域走査と
    /// 同じ流儀)。ここでも同じ比 — チャレンジ枠と各地方ステージ枠の
    /// `max(cw/w, ch/h)` — を独立に計算して、運ばれた値と突き合わせる。
    /// 枠は描画のフィットと同じ `frameBbox ?? bbox`(ロシアはヨーロッパ側の
    /// 枠だけがフィットに効き、シベリアは景色としてあふれる)— 生の bbox で
    /// 測ると frameBbox 持ちステージの比を過小評価する。
    @Test func 世界チャレンジの平面ズーム上限は最大のステージ枠比() throws {
        let atlas = try worldAtlas()
        let challenge = try #require(atlas.stages.first { $0.isChallenge })
        var frames: [Int: CGRect] = [:]
        for prefecture in atlas.mapData.prefectures {
            frames[prefecture.code] = prefecture.frameBbox ?? prefecture.bbox
        }
        let challengeBox = frames.values.reduce(CGRect.null) { $0.union($1) }
        let ratios = atlas.stages.filter { !$0.isChallenge }.map { stage in
            let box = stage.codes.compactMap { frames[$0] }
                .reduce(CGRect.null) { $0.union($1) }
            return max(challengeBox.width / box.width,
                       challengeBox.height / box.height)
        }
        let expected = try #require(ratios.max())
        #expect(expected > GameRules.mapMaxZoom)
        #expect(abs(challenge.flatMaxZoom - expected) < 0.001)
    }

    /// 実データの釘打ち: 最大比は stage 11 みなみアフリカの ≈ 17.1。
    /// 導出はコードなのでデータが変われば追従するが、桁が動いたら
    /// (投影や bbox の退行で)ここで気づく。
    ///
    /// 簡略化率を 4% → 20% に上げたとき ≈ 16.4 から動いた(2026-08-23)。
    /// 内訳は 2 つあり、**通してよかったのは前者だけ**:
    ///   - アリューシャン列島の西寄りの島が残るようになり、チャレンジ枠が
    ///     348° → 362° に広がった。実在の陸地なので受け入れる(全体が 4%
    ///     小さくなる)
    ///   - 同時に日付変更線の向こうの岩 3 つも残り、アメリカが丸ごと +360
    ///     側へ反転して枠が 434° に膨らんだ。こちらは事故で、この
    ///     アサーションが捕まえた。パイプライン側の DATELINE_OUTLIER_LON で
    ///     岩を背景へ回して直してある
    /// つまりこの上下限は「枠がじわじわ広がっていないか」の網であって、
    /// 広がったら黙って数字を書き換える場所ではない。動いたらまず
    /// どの国の bbox が伸びたのかを見ること。
    @Test func 世界チャレンジの上限はおよそ17() throws {
        let challenge = try #require(try worldAtlas().stages.first { $0.isChallenge })
        #expect(challenge.flatMaxZoom > 17.0)
        #expect(challenge.flatMaxZoom < 18.0)
    }

    /// 広がるのは世界チャレンジだけ。地方ステージはその地方が枠いっぱいに
    /// 描かれていて、4 を超える拡大は形を背後のディテールより大きくする
    /// (ZoomPan の既定の美観判断のまま)。
    @Test func 世界の地方ステージの平面ズーム上限は既定のまま() throws {
        for stage in try worldAtlas().stages where !stage.isChallenge {
            #expect(stage.flatMaxZoom == GameRules.mapMaxZoom)
        }
    }

    /// 日本は全国チャレンジ含め全ステージ既定 — 今日の挙動から 1 ピクセルも
    /// 動かさない。
    @Test func 日本の全ステージの平面ズーム上限は既定のまま() {
        for stage in Stage.all {
            #expect(stage.flatMaxZoom == GameRules.mapMaxZoom)
        }
    }

    // MARK: - 平面ズームの床(世界の地方ステージの縮小・2026-08-22 計画)

    /// 地方 18 面は全収録国の枠が入るまでピンチで引ける — 「この地方は
    /// 世界のどのあたりか」は地方の切り取りの外にしか描かれていない。
    /// 床は上限と同じ枠(`frameBbox ?? bbox`)から独立に再計算して
    /// 運ばれた値と突き合わせる。
    @Test func 世界の地方ステージは全体が入るまで縮小できる() throws {
        let atlas = try worldAtlas()
        var frames: [Int: CGRect] = [:]
        for prefecture in atlas.mapData.prefectures {
            frames[prefecture.code] = prefecture.frameBbox ?? prefecture.bbox
        }
        let bookBox = frames.values.reduce(CGRect.null) { $0.union($1) }
        for stage in atlas.stages where !stage.isChallenge {
            let box = stage.codes.compactMap { frames[$0] }
                .reduce(CGRect.null) { $0.union($1) }
            let expected = min(1, min(box.width / bookBox.width,
                                      box.height / bookBox.height))
            #expect(stage.flatMinZoom > 0)
            #expect(stage.flatMinZoom < 1)
            #expect(abs(stage.flatMinZoom - expected) < 0.001)
        }
    }

    /// せかいチャレンジの枠は既に全世界 — 引いて見せる外側が無いので
    /// 床は既定の 1 のまま。
    @Test func 世界チャレンジの床は既定のまま() throws {
        let challenge = try #require(try worldAtlas().stages.first { $0.isChallenge })
        #expect(challenge.flatMinZoom == 1)
    }

    /// 日本は全ステージ床 1 — 地方ステージは周辺県を描いておらず、縮小して
    /// 見えるのは偽の海だけ。今日の挙動から 1 ピクセルも動かさない。
    @Test func 日本の全ステージの縮小の床は既定のまま() {
        for stage in Stage.all {
            #expect(stage.flatMinZoom == 1)
        }
    }

    // MARK: - 読み込み失敗(CLAUDE.md §11: 握って初期状態へ)

    @Test func 世界データが無ければ空のアトラスに倒れる() {
        let missing = URL(fileURLWithPath: "/nonexistent/WorldShapes.json")
        let atlas = Atlas.loadWorld(contentsOf: missing)
        #expect(atlas.mapData.prefectures.isEmpty)
        #expect(atlas.stages.isEmpty)
        #expect(atlas.cards.all.isEmpty)
    }

    @Test func 壊れた世界データも空のアトラスに倒れる() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("corrupt-world-\(UUID().uuidString).json")
        try Data("{ this is not json".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let atlas = Atlas.loadWorld(contentsOf: url)
        #expect(atlas.mapData.prefectures.isEmpty)
        #expect(atlas.stages.isEmpty)
    }
}
