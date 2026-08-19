import CoreGraphics
import Foundation
import OSLog

/// ちずちょう 1 冊ぶんの資源の束: 地図 + ステージ + カード(設計 §3)。
///
/// 「View はアトラス非依存のまま保つ」を、共通プロトコルではなく
/// **既存の値型へ流し込む**ことで実現している: 世界の国は境界で
/// `Prefecture` に、世界のステージは `Stage` に変換され、
/// `PrefectureMapView` / `QuizViewModel` などの利用側は日本と世界の
/// 区別を知らないまま動く。分岐はデータ(この型の作り方)に閉じる。
///
/// ## コードの衝突(解決は Task 6 / SaveData v7)
/// 県コード 1–47 と ISO 3166-1 numeric は重なる(例: 44 は大分県でも
/// バハマでもある)。コードが一意なのは **1 冊のアトラスの中だけ**で、
/// セーブデータはアトラス名前空間(`atlases["japan"]` / `atlases["world"]`)で
/// 分ける。名前空間化(v7)が入るまで、どちらのアトラスのコードも
/// SaveData へ書き込んではならない。
nonisolated struct Atlas: Sendable {
    let mapData: MapData
    let stages: [Stage]
    /// 世界版はいまは空 — WorldCards.json の生成と読み込みは Task 8。
    /// 世界版の抽選差分(国旗カードが銀になるまでオリジナルを配らない、
    /// 設計 §5)も Task 8 でアトラスの属性として GameRules へ渡す。
    let cards: CardCatalog

    /// 音声入力へ渡す語彙(よみ + 表記)。AppState が起動時に組み立てていた
    /// 式をアトラス側へ移しただけで、日本版の挙動は変えていない。世界版の
    /// 表記ゆれ吸収(「あめりか」「あめりかがっしゅうこく」)は音声タスクの仕事。
    var voiceVocabulary: [String] {
        mapData.prefectures.flatMap { [$0.kana, $0.name] }
    }

    private static let log = Logger(subsystem: "com.wakuwaku.chizuhakase", category: "Atlas")

    // MARK: - 日本

    /// 現行アプリそのまま: ローダの結果と `Stage.all` を束ねるだけで、
    /// データにも挙動にも手を加えない。
    static func japan(mapData: MapData, cards: CardCatalog) -> Atlas {
        Atlas(mapData: mapData, stages: Stage.all, cards: cards)
    }

    // MARK: - 世界

    /// バンドルの WorldShapes.json から世界アトラスを作る。
    ///
    /// `WorldDataLoader` は投げる設計で、失敗の吸収はここが引き受ける:
    /// 空のアトラスへ倒して記録し、決してクラッシュさせない(CLAUDE.md §11)。
    /// 子どもにとって空の世界地図は悪いが、起動できないアプリはもっと悪い —
    /// 日本版 `MapDataLoader` と同じ判断。
    static func loadWorld(bundle: Bundle = .main) -> Atlas {
        world { try WorldDataLoader.load(bundle: bundle) }
    }

    static func loadWorld(contentsOf url: URL) -> Atlas {
        world { try WorldDataLoader.load(contentsOf: url) }
    }

    private static func world(loading load: () throws -> WorldMapData) -> Atlas {
        do {
            return world(from: try load())
        } catch {
            log.error("world atlas load failed: \(error.localizedDescription, privacy: .public)")
            return Atlas(mapData: .empty, stages: [], cards: .empty)
        }
    }

    /// `WorldMapData` → 既存の値型への純変換。フィールドは 1:1 に写る
    /// (code = ISO numeric, name = nameJa, kana = kana, rings = flatRings,
    /// centroid = flatCentroid, bbox = flatBbox)。
    ///
    /// まだ運ばないもの: `background`(装飾の海岸線)・`insets`(拡大宣言)・
    /// `europeBbox`(ステージ枠の切り取り線)は既存の型に置き場所が無く、
    /// 世界地図の描画タスクが持ち方を決める。インセット国も収録国として
    /// 普通に変換される — 拡大は見せ方の問題で、データからは消えない。
    static func world(from world: WorldMapData) -> Atlas {
        let prefectures = world.recordedCountries.map { country in
            Prefecture(code: country.code,
                       name: country.nameJa,
                       kana: country.kana,
                       bbox: country.flatBbox,
                       centroid: country.flatCentroid,
                       rings: country.flatRings)
        }
        // `Stage.isNationwide`(== 47 県)は世界の 18 ステージ(最大 16 カ国)
        // には該当しないので、全ステージが設計どおり 1 国 2 回出題になる。
        // ワールドチャレンジ(167 カ国)を足すタスクは isNationwide の定義を
        // 見直すこと — 47 と比べたままだと 334 問の総合ステージができてしまう。
        let stages = world.stages.map { stage in
            Stage(index: stage.index,
                  name: stage.name,
                  kanjiName: stage.kanjiName,
                  codes: stage.codes)
        }
        // 投影は収録国の西端を x=0・北端を y=0 に置く(WorldProjection)ので、
        // bbox の和の右下がそのままキャンバス寸法になる。
        let bounds = prefectures.map(\.bbox).reduce(CGRect.null) { $0.union($1) }
        guard !bounds.isNull else {
            return Atlas(mapData: .empty, stages: stages, cards: .empty)
        }
        let mapData = MapData(width: bounds.maxX,
                              height: bounds.maxY,
                              // 沖縄インセットは日本の地図だけの持ち物。
                              // zero = 枠なし(MapData.empty と同じ流儀)。
                              okinawaInset: .zero,
                              prefectures: prefectures)
        return Atlas(mapData: mapData, stages: stages, cards: .empty)
    }
}
