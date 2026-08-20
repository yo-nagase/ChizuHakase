import CoreGraphics
import Foundation
import OSLog

/// ステージ棚のセクション見出し。世界は大陸ごと、日本は空 = 見出しなし。
/// View は `Atlas.stageShelves` を並べるだけで japan/world を知らない(設計 §3)—
/// 見出しの有無も文言も、この値がアトラスと一緒に運ぶ。
nonisolated struct AtlasSection: Sendable, Equatable {
    /// 見出しの文字。大陸名はこども・おとな表記ともカタカナなので 1 本で足りる
    /// (漢字にするのが自然な大陸名は無い)。
    let title: String
    /// この見出しの下に並ぶステージ index の区間。名前ではなく区間で持つのは、
    /// ステージ index が大陸ごとに連続していて機械的に引けるから
    /// (ステージ選択 UI 決定 2026-08-20 — docs/plans/2026-08-18-world-stages.md)。
    let stageIndexes: Range<Int>
}

/// チャレンジステージの地図に出すワンプレスズーム 1 個: ボタンの語と、
/// 押したとき枠に収めるコードの集まり。アトラスが運ぶ — ボタンは地理そのもので、
/// View はどの本の地理かを知らないまま並べるだけ(日本の県コード 1–47 を
/// 直に持った旧 `Stage.eastJapanCodes` は、世界では別の国の ISO コードを
/// でたらめに囲む罠だった)。
nonisolated struct RegionZoom: Sendable, Equatable, Identifiable {
    /// ボタンの語。こども ⇄ おとな の解決は `AtlasNoun.label(_:)` のまま —
    /// 語彙は従来どおり TextMode.swift に綴じてある。
    let label: AtlasNoun
    let codes: [Int]

    var id: String { label.kids }

    /// 全国チャレンジの 3 分割。カメラの的であって区分けではない — 大阪と
    /// 兵庫は 2 つの枠に現れ、所属を数える者はいない。半分ではなく 3 分の 1
    /// なのは、半分ではほとんど拡大にならないから: 北海道〜愛知が 1 枠でも
    /// 国の対角線の大半のままで、押しても変わらないズームは「このボタンは
    /// 何もしない」を教えてしまう。
    ///
    /// にしにほんは中国ステージで切らず大阪から西へ: ふだんの言葉で大阪は
    /// 西日本で、大阪の入らない「にし」はボタンの語を裏切る。奈良と和歌山は
    /// 枠自身の余白に同乗する。並びは画面の縦積み順 — 東が上、西が下
    /// (列島が斜めに走る向きに合わせる)。
    static let japanThirds: [RegionZoom] = [
        RegionZoom(label: .eastJapan, codes: Array(1...14)),    // 北海道・東北 + 関東
        RegionZoom(label: .middleJapan, codes: Array(15...30)), // 中部 + 近畿
        RegionZoom(label: .westJapan,
                   codes: [27, 28] + Array(31...47)),           // 大阪から西
    ]
}

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
    /// 地球儀モードの度数データ(P7)。世界だけが運び、日本と空へ倒れた
    /// 世界は nil — View は「globe の有無」で振る舞いを変えるだけで、
    /// どの本かでは分岐しない(インセット判定と同じ規律)。
    let globe: GlobeData?
    let stages: [Stage]
    /// ステージ棚の区切り(世界 = 大陸見出し、日本 = 空)。
    let sections: [AtlasSection]
    /// チャレンジステージのワンプレスズーム(日本 = 3 分割、世界 = 空 —
    /// 世界チャレンジの平面は地球儀の控えで、ボタンを育てる場所ではない)。
    let regionZooms: [RegionZoom]
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
    /// この本の 1 マスを指す名詞(けん ⇄ くに)。文はどちらの本でも同じ形で、
    /// 差はこの語だけ — 抽選方針と同じく値で運び、view は本を知らない
    /// (P6 Task 6: 世界の結果画面に「けん」が出た穴を語彙の綴じ込みで塞ぐ)。
    let regionNoun: AtlasNoun
    /// カード欄の見出し(とくさんひん カード ⇄ せかいの カード)。
    let cardNoun: AtlasNoun

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

    /// ステージ選択の棚 1 段: 見出し(なければ nil)とその下のステージ。
    nonisolated struct StageShelf: Sendable, Equatable, Identifiable {
        let title: String?
        let stages: [Stage]
        /// 棚は空では作られない(下の compactMap / isEmpty ガード)ので
        /// 先頭ステージの index がそのまま棚の同一性になる。
        var id: Int { stages.first?.index ?? -1 }
    }

    /// ステージ選択が並べる棚。sections が空(日本)なら見出しなしの 1 段 —
    /// 今日の日本版と 1 ピクセルも変わらない形。世界は大陸ごとの段になる。
    ///
    /// 区間に入らないステージは落とさず見出しなしで末尾へ、中身のない見出しは
    /// 並べない: データが食い違ったとき、棚からステージが消える・空の見出しが
    /// 立つ、のどちらの壊れ方もしない。
    ///
    /// P7 のワールドチャレンジ段をこの「余り」枝に乗せないこと — 総合ステージは
    /// `sections` に自分の区間として明示的に足す。余り枝はデータ食い違いの
    /// 診断用で、正規のステージが日常的に流れ着く場所にした瞬間、
    /// 壊れ方の検出器ではなくなる。
    var stageShelves: [StageShelf] {
        guard !sections.isEmpty else {
            return stages.isEmpty ? [] : [StageShelf(title: nil, stages: stages)]
        }
        var shelves = sections.compactMap { section -> StageShelf? in
            let members = stages.filter { section.stageIndexes.contains($0.index) }
            return members.isEmpty ? nil : StageShelf(title: section.title, stages: members)
        }
        let covered = sections.reduce(into: Set<Int>()) { $0.formUnion($1.stageIndexes) }
        let leftovers = stages.filter { !covered.contains($0.index) }
        if !leftovers.isEmpty {
            shelves.append(StageShelf(title: nil, stages: leftovers))
        }
        return shelves
    }

    private static let log = Logger(subsystem: "com.wakuwaku.chizuhakase", category: "Atlas")

    // MARK: - 日本

    /// 現行アプリそのまま: ローダの結果と `Stage.all` を束ねるだけで、
    /// データにも挙動にも手を加えない。
    static func japan(mapData: MapData, cards: CardCatalog) -> Atlas {
        Atlas(mapData: mapData, globe: nil, stages: Stage.all, sections: [],
              regionZooms: RegionZoom.japanThirds, cards: cards,
              drawPolicy: .random, saveKey: SaveData.japanAtlas,
              regionNoun: .prefecture, cardNoun: .specialtyCards)
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
            // 空へ倒れても方針・名前空間・見出し定義・語彙は世界のまま —
            // カードを失っても「どの本か」までは失わない(棚はステージが無いので空)。
            return Atlas(mapData: .empty, globe: nil, stages: [],
                         sections: WorldStage.sections, regionZooms: [],
                         cards: .empty, drawPolicy: .flagFirstSilverGate,
                         saveKey: SaveData.worldAtlas,
                         regionNoun: .country, cardNoun: .worldCards)
        }
    }

    /// `WorldMapData` → 既存の値型への純変換。フィールドは 1:1 に写る
    /// (code = ISO numeric, name = nameJa, kana = kana, rings = flatRings,
    /// centroid = flatCentroid, bbox = flatBbox, frameBbox = europeBbox)。
    /// `insets`(破線枠)と `background`(収録外の海岸線)も MapData が
    /// そのまま運び、描画側は日本と同じ道具で描く — 分岐はここにも無い。
    static func world(from world: WorldMapData, cards: CardCatalog = .empty) -> Atlas {
        let prefectures = world.recordedCountries.map { country in
            Prefecture(code: country.code,
                       name: country.nameJa,
                       kana: country.kana,
                       bbox: country.flatBbox,
                       centroid: country.flatCentroid,
                       rings: country.flatRings,
                       frameBbox: country.europeBbox)
        }
        // isNationwide(== 47 県)と地域ズームの 2 つの罠は P7 Task 4/5 で
        // 解決済み: 総合ステージは stored な `Stage.isChallenge` になり、
        // JSON 由来の 18 面は既定 false のまま通る(全部 2 回出題の地方
        // ステージ)。isChallenge: true を名乗るのは下で束ねる 19 面目
        // 「せかい チャレンジ」だけで、この変換が明示的に渡す。
        // ズームボタンの県コードは `Atlas.regionZooms` が運ぶ(世界は空)。
        let regionalStages = world.stages.map { stage in
            Stage(index: stage.index,
                  name: stage.name,
                  kanjiName: stage.kanjiName,
                  codes: stage.codes)
        }
        // 投影は収録国の西端を x=0・北端を y=0 に置く(WorldProjection)ので、
        // bbox の和の右下がそのままキャンバス寸法になる。
        let bounds = prefectures.map(\.bbox).reduce(CGRect.null) { $0.union($1) }
        guard !bounds.isNull else {
            // 収録国が無いなら球に描く物も無い — globe も一緒に落として、
            // View の「有無」判定が平面と食い違わないようにする。
            // ローダ経由ではここに届かない(国が 0 件なら makeProjection が
            // degenerateExtent を先に投げる)— `world(from:)` を直接組んだ
            // WorldMapData のための防衛線。チャレンジもここには足さない:
            // 収録国の無い本に 0 問の総合ステージを立てても、棚に「遊べない
            // 面」が増えるだけだから(globe を落とすのと同じ判断)。
            return Atlas(mapData: .empty, globe: nil, stages: regionalStages,
                         sections: WorldStage.sections, regionZooms: [],
                         cards: cards, drawPolicy: .flagFirstSilverGate,
                         saveKey: SaveData.worldAtlas,
                         regionNoun: .country, cardNoun: .worldCards)
        }
        let mapData = MapData(width: bounds.maxX,
                              height: bounds.maxY,
                              insets: world.insets.map {
                                  MapInset(code: $0.code, frame: $0.frame)
                              },
                              background: world.background.map { shape in
                                  MapBackgroundShape(
                                      rings: shape.flatRings,
                                      bbox: boundingBox(of: shape.flatRings))
                              },
                              prefectures: prefectures)
        // 19 面目「せかい チャレンジ」(設計 §8、P7 Task 5)。本の全収録国を
        // 1 面に束ね、isChallenge はこの 1 行だけが明示的に名乗る。codes は
        // 全 167 だが 1 回の出題は 47 問 — どの国が入るかは questionCount では
        // なく抽選(GameRules.challengeSelection)の仕事。
        let challenge = Stage(index: WorldStage.challengeIndex,
                              name: WorldStage.challengeName,
                              kanjiName: WorldStage.challengeKanjiName,
                              codes: prefectures.map(\.code),
                              isChallenge: true)
        // 国旗カードが銀になるまでオリジナルを配らないゲート(設計 §5)。
        return Atlas(mapData: mapData, globe: world.globe,
                     stages: regionalStages + [challenge],
                     sections: WorldStage.sections, regionZooms: [],
                     cards: cards, drawPolicy: .flagFirstSilverGate,
                     saveKey: SaveData.worldAtlas,
                     regionNoun: .country, cardNoun: .worldCards)
    }

    /// 背景の海岸線には bbox が付いて来ない(WorldShapes.json は名も範囲も
    /// 持たない裸のリング)ので、描画の間引きに使う範囲をここで測る。
    private static func boundingBox(of rings: [[CGPoint]]) -> CGRect {
        rings.flatMap { $0 }.reduce(CGRect.null) { box, point in
            box.union(CGRect(origin: point, size: .zero))
        }
    }
}
