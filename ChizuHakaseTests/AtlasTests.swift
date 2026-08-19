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
        #expect(atlas.mapData.okinawaInset == Self.japanMap.okinawaInset)
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

    @Test func 世界アトラスのステージが18面で全国を尽くす() throws {
        let world = try Self.world.get()
        let atlas = Atlas.world(from: world)
        #expect(atlas.stages.count == 18)
        #expect(atlas.stages.map(\.index) == Array(0...17))
        for (worldStage, stage) in zip(world.stages, atlas.stages) {
            #expect(stage.name == worldStage.name, "stage \(stage.index)")
            #expect(stage.kanjiName == worldStage.kanjiName, "stage \(stage.index)")
            #expect(stage.codes == worldStage.codes, "stage \(stage.index)")
        }
        let allCodes = atlas.stages.flatMap(\.codes)
        #expect(allCodes.count == 167)
        #expect(Set(allCodes).count == allCodes.count, "国が複数ステージに重複")
        #expect(Set(allCodes) == Set(atlas.mapData.prefectures.map(\.code)))
    }

    /// `Stage.isNationwide` は「47 県」で判定している。世界の 18 ステージは
    /// 最大 16 カ国なので誤爆せず、設計どおり全ステージが 1 国 2 回出題になる。
    @Test func 世界のステージはすべて2回出題の地方ステージ() throws {
        let atlas = try worldAtlas()
        for stage in atlas.stages {
            #expect(!stage.isNationwide, "stage \(stage.index)")
            #expect(stage.asksEachTwice, "stage \(stage.index)")
            #expect(stage.questionCount == stage.codes.count * 2, "stage \(stage.index)")
        }
    }

    // MARK: - ステージ棚のセクション(大陸見出し — UI 決定 2026-08-20)

    /// 日本は見出しなし: 棚は 1 段で、今日のステージ選択と 1 ピクセルも
    /// 変わらない並びのまま。
    @Test func 日本の棚は見出しなしの1段() {
        let atlas = japanAtlas
        #expect(atlas.sections.isEmpty)
        #expect(atlas.stageShelves == [Atlas.StageShelf(title: nil, stages: Stage.all)])
    }

    /// 見出しは stage index 区間から機械的に引く
    /// (0–2 アメリカ / 3–6 ヨーロッパ / 7–11 アフリカ / 12–16 アジア / 17 オセアニア)。
    @Test func 世界の棚は5大陸の見出しで区切られる() throws {
        let atlas = try worldAtlas()
        #expect(atlas.sections == WorldStage.sections)
        let shelves = atlas.stageShelves
        #expect(shelves.map(\.title)
                == ["アメリカ", "ヨーロッパ", "アフリカ", "アジア", "オセアニア"])
        #expect(shelves.map { $0.stages.map(\.index) }
                == [[0, 1, 2], [3, 4, 5, 6], [7, 8, 9, 10, 11],
                    [12, 13, 14, 15, 16], [17]])
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
        let atlas = Atlas(mapData: .empty, stages: Stage.all + [stray],
                          sections: [AtlasSection(title: "テスト", stageIndexes: 0..<7)],
                          cards: .empty, drawPolicy: .random, saveKey: "test")
        let shelves = atlas.stageShelves
        #expect(shelves.count == 2)
        #expect(shelves.first?.title == "テスト")
        #expect(shelves.first?.stages == Stage.all)
        #expect(shelves.last == Atlas.StageShelf(title: nil, stages: [stray]))
    }

    // MARK: - 世界のカード目録(WorldCards.json)

    /// 1 国 1 枚の国旗カード。オリジナル札(-2)は P6 の手描きが揃ってから。
    @Test func 世界の目録は167カ国ぶんの国旗カード() throws {
        let atlas = try worldAtlas()
        #expect(atlas.cards.count == 167)
        for card in atlas.cards.all {
            #expect(card.category == .flag, "\(card.id) is not a flag card")
            #expect(card.art == nil, "\(card.id): 絵文字が国旗そのもの、絵は持たない")
        }
        // 収録国とカードの持ち主が過不足なく一致する。
        let countryCodes = Set(atlas.mapData.prefectures.map(\.code))
        #expect(Set(atlas.cards.all.map(\.prefectureCode)) == countryCodes)
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
        }
    }

    /// 国旗の絵文字は地域指標記号 2 文字(端末フォントが描く実物の国旗)。
    @Test func 国旗カードの絵文字は地域指標記号() throws {
        let indicators: ClosedRange<UInt32> = 0x1F1E6...0x1F1FF
        for card in try worldAtlas().cards.all {
            let scalars = card.emoji.unicodeScalars
            #expect(scalars.count == 2 && scalars.allSatisfy { indicators.contains($0.value) },
                    "\(card.id): \(card.emoji) is not a flag emoji")
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
        #expect(Atlas.loadWorld().cards.count == 167)
    }

    @Test func 世界アトラスの地図寸法が投影と一致する() throws {
        let atlas = try worldAtlas()
        // 幅 1000 正規化は収録国基準(WorldDataTests と同じ根拠)。
        #expect(abs(atlas.mapData.width - 1000) < 0.5, "width = \(atlas.mapData.width)")
        #expect(atlas.mapData.height > 0)
        // 沖縄インセットは日本の地図だけの持ち物。zero = 枠なし(MapData.empty と同じ)。
        #expect(atlas.mapData.okinawaInset == .zero)
    }

    @Test func 世界アトラスの語彙はよみと表記の両方を含む() throws {
        let vocabulary = try worldAtlas().voiceVocabulary
        #expect(vocabulary.count == 167 * 2)
        #expect(vocabulary.contains("にほん"))
        #expect(vocabulary.contains("日本"))
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
        #expect(try worldAtlas().stage(at: 18) == nil)
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
