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

    /// WorldDataTests と同じく `Result` 包み: static 初期化子では try が
    /// 書けず、`try!`(§11 で禁止)を避けるため。
    static let world = Result {
        try WorldDataLoader.load(contentsOf: TestResources.require("WorldShapes"))
    }

    private var japanAtlas: Atlas {
        Atlas.japan(mapData: Self.japanMap, cards: Self.japanCards)
    }

    private func worldAtlas() throws -> Atlas {
        Atlas.world(from: try Self.world.get())
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

    /// WorldCards.json は Task 8 まで存在しない。それまで世界アトラスの
    /// カードは空 — 空であることが「まだ配らない」の表明になっている。
    @Test func 世界アトラスのカードはまだ空() throws {
        let atlas = try worldAtlas()
        #expect(atlas.cards.count == 0)
        #expect(atlas.cards.all.isEmpty)
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
