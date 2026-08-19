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
/// ## コードの衝突(SaveData v7 で解決済み)
/// 県コード 1–47 と ISO 3166-1 numeric は重なる(例: 44 は大分県でも
/// バハマでもある)。コードが一意なのは **1 冊のアトラスの中だけ**で、
/// セーブデータはアトラス名前空間(`atlases["japan"]` / `atlases["world"]`)で
/// 分ける。進捗の読みは `SaveData.atlas(saveKey)`、書き込みは
/// `SaveStore.applyStageResult(_:catalog:atlas:)` に `saveKey` を渡す —
/// 名前空間を経由しない読み書きはコードを別の本の記録に化けさせる。
nonisolated struct Atlas: Sendable {
    let mapData: MapData
    let stages: [Stage]
    /// 日本は SpecialtyCards.json、世界は WorldCards.json(国旗のみ。
    /// オリジナル札は P6)。読み込み失敗は空(空の本 > クラッシュ)。
    let cards: CardCatalog
    /// カード抽選の方針(設計 §5「規則の差分」)。日本と世界の唯一の規則差で、
    /// アトラスが値として運び、利用側は `GameRules.drawCard` へ渡すだけ —
    /// view にも ViewModel にも「どちらの本か」の分岐は生まれない。
    let drawPolicy: GameRules.DrawPolicy
    /// セーブの名前空間(`SaveData.atlases` のキー)。資源と一緒に運ぶのは、
    /// 「どの本を遊んだか」と「どこへ記録するか」を別々に選べる形にすると
    /// いつか必ず食い違うから。
    let saveKey: String

    /// 音声入力へ渡す語彙(よみ + 表記)。AppState が起動時に組み立てていた
    /// 式をアトラス側へ移しただけで、日本版の挙動は変えていない。世界版の
    /// 表記ゆれ吸収(「あめりか」「あめりかがっしゅうこく」)は音声タスクの仕事。
    var voiceVocabulary: [String] {
        mapData.prefectures.flatMap { [$0.kana, $0.name] }
    }

    /// index からステージを引く(日本版 `Stage.stage(at:)` の、どちらの本でも
    /// 使える形)。index はアトラス内でだけ意味を持つ(セーブの records と同じ)。
    func stage(at index: Int) -> Stage? {
        stages.first { $0.index == index }
    }

    private static let log = Logger(subsystem: "com.wakuwaku.chizuhakase", category: "Atlas")

    // MARK: - 日本

    /// 現行アプリそのまま: ローダの結果と `Stage.all` を束ねるだけで、
    /// データにも挙動にも手を加えない。
    static func japan(mapData: MapData, cards: CardCatalog) -> Atlas {
        Atlas(mapData: mapData, stages: Stage.all, cards: cards,
              drawPolicy: .random, saveKey: SaveData.japanAtlas)
    }

    // MARK: - 世界

    /// バンドルの WorldShapes.json + WorldCards.json から世界アトラスを作る。
    ///
    /// `WorldDataLoader` は投げる設計で、失敗の吸収はここが引き受ける:
    /// 空のアトラスへ倒して記録し、決してクラッシュさせない(CLAUDE.md §11)。
    /// 子どもにとって空の世界地図は悪いが、起動できないアプリはもっと悪い —
    /// 日本版 `MapDataLoader` と同じ判断。カード側の失敗吸収は
    /// `MapDataLoader.loadCards` がすでに持っている(空目録へ倒す)。
    static func loadWorld(bundle: Bundle = .main) -> Atlas {
        world(cards: loadWorldCards(bundle: bundle)) {
            try WorldDataLoader.load(bundle: bundle)
        }
    }

    /// テスト用: 地図だけを指定 URL から読む(カードは空)。
    static func loadWorld(contentsOf url: URL) -> Atlas {
        world(cards: .empty) { try WorldDataLoader.load(contentsOf: url) }
    }

    private static func loadWorldCards(bundle: Bundle) -> CardCatalog {
        guard let url = bundle.url(forResource: "WorldCards", withExtension: "json") else {
            log.error("WorldCards.json missing from bundle")
            return .empty
        }
        return MapDataLoader.loadCards(contentsOf: url)
    }

    private static func world(cards: CardCatalog,
                              loading load: () throws -> WorldMapData) -> Atlas {
        do {
            return world(from: try load(), cards: cards)
        } catch {
            log.error("world atlas load failed: \(error.localizedDescription, privacy: .public)")
            // 空へ倒れても方針と名前空間は世界のまま — カードを失っても
            // 「どの本か」までは失わない。
            return Atlas(mapData: .empty, stages: [], cards: .empty,
                         drawPolicy: .flagFirstSilverGate, saveKey: SaveData.worldAtlas)
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
    static func world(from world: WorldMapData, cards: CardCatalog = .empty) -> Atlas {
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
            return Atlas(mapData: .empty, stages: stages, cards: cards,
                         drawPolicy: .flagFirstSilverGate, saveKey: SaveData.worldAtlas)
        }
        let mapData = MapData(width: bounds.maxX,
                              height: bounds.maxY,
                              // 沖縄インセットは日本の地図だけの持ち物。
                              // zero = 枠なし(MapData.empty と同じ流儀)。
                              okinawaInset: .zero,
                              prefectures: prefectures)
        // 国旗カードが銀になるまでオリジナルを配らないゲート(設計 §5)。
        return Atlas(mapData: mapData, stages: stages, cards: cards,
                     drawPolicy: .flagFirstSilverGate, saveKey: SaveData.worldAtlas)
    }
}
