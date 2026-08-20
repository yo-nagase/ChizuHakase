import CoreGraphics
import Foundation

// 世界地図の値型と投影はこのファイルに同居させている。Atlas 抽象(Task 5)で
// 置き場所が定まるまで、ファイルを散らさないための一時的な同居。

// MARK: - 値型

/// 収録国 1 つぶんの形とメタデータ。座標は投影済みの平面
/// (左上原点・y 下向き・幅 1000 正規化 — 日本版 `Prefecture` と同じ流儀)。
nonisolated struct WorldCountry: Identifiable, Sendable, Equatable {
    /// ISO 3166-1 numeric。公開後はセーブキーになるので変更しない。
    let code: Int
    /// おとな表記(「アメリカ合衆国」)。
    let nameJa: String
    /// よみ。問題文と読み上げに使う(「あめりか」)。
    let kana: String
    /// 所属ステージ(`WorldStage.index`)。
    let stage: Int
    /// 外周と穴。even-odd で塗り・判定する(日本版と同じ)。
    /// リング末尾の閉環重複点(先頭と同じ点)は落とさずに保持する:
    /// PrefectureShapes.json も同じ形で持っており、`closeSubpath` が零長辺として
    /// 無害に扱う。ここだけ落とすと 2 つの地図でデータ規約が割れる。
    let flatRings: [[CGPoint]]
    /// pole of inaccessibility(tools/build_world_map_data.py)。ラベル・
    /// エフェクトの錨。テストが保証するのは「重心か bbox 中心のどちらかが
    /// 自国内」まで — 環礁のような凹形状では重心が海に落ちることがある。
    let flatCentroid: CGPoint
    /// リングの正確な範囲(パイプラインが保証)。ステージ枠の計算に使う。
    let flatBbox: CGRect
    /// 小さすぎてタップできない国(シンガポール等)。true なら flatRings は
    /// すでに拡大されて破線枠の中へ移されている(`WorldInset` の註)。
    let isInset: Bool
    /// ロシアのみ: ウラルまでの欧州部分の枠。ひがしヨーロッパのステージ枠が
    /// シベリアまで広がらないようにするための切り取り線。他の用途に使わない。
    let europeBbox: CGRect?

    var id: Int { code }

    /// 問題文と読み上げに使うよみ(日本版 `Prefecture.spokenName` と同じ約束)。
    var spokenName: String { kana }
}

/// 収録外の海岸線 1 つぶん(属領・収録外国)。コードも名前も持たない —
/// 出題されず、タップもされず、ただ海を陸に見せるためだけの形。
nonisolated struct WorldBackgroundShape: Sendable, Equatable {
    let flatRings: [[CGPoint]]
}

/// インセット拡大の宣言(裁定 2026-08-19: シンガポール・マルタ・モルディブ・
/// フィジー)。対象国の `flatRings` はロード時に `scale` 倍されて `frame` の
/// 中心へ移されている — 沖縄と同じ「別枠」の仕組みで、違いは焼き込む場所
/// だけ(日本はパイプライン、世界はロード時。地球儀モードが lon/lat の
/// 実位置を要るため、JSON には本当の座標を残す)。
nonisolated struct WorldInset: Sendable, Equatable {
    let code: Int
    let scale: CGFloat
    /// 破線枠(投影済みの平面座標)。位置はパイプラインがステージ枠内の
    /// 空き海域を走査して決める(tools/build_world_map_data.py。手置きしない)。
    let frame: CGRect
}

/// WorldShapes.json をデコード・投影し終えた全体。
nonisolated struct WorldMapData: Sendable {
    /// コード昇順。出題・カードの対象になる 167 カ国。
    let recordedCountries: [WorldCountry]
    /// index 順の 18 ステージ。名前は `WorldStage.names`、所属は JSON から。
    let stages: [WorldStage]
    let background: [WorldBackgroundShape]
    let insets: [WorldInset]

    private let byCode: [Int: WorldCountry]

    init(recordedCountries: [WorldCountry],
         stages: [WorldStage],
         background: [WorldBackgroundShape],
         insets: [WorldInset]) {
        self.recordedCountries = recordedCountries
        self.stages = stages
        self.background = background
        self.insets = insets
        // コードの一意性はローダが検証済みだが、init は公開されているので
        // 重複でクラッシュ(uniqueKeysWithValues は trap)しない側を選ぶ。
        self.byCode = Dictionary(recordedCountries.map { ($0.code, $0) },
                                 uniquingKeysWith: { first, _ in first })
    }

    subscript(code: Int) -> WorldCountry? { byCode[code] }
}

// MARK: - 投影

/// 緯度経度 → アプリの平面座標(左上原点・y 下向き)への純関数。
///
/// 単純な cos 補正付きエクイレクタングラー(設計 §7)。いまは全世界を
/// 1 枚の平面に置くだけで、ステージごとの投影(帯ごとの基準緯度で
/// 歪みを減らす)は後続タスクに明示的に先送りしている — データ層の
/// 座標系が 1 つなら、セーブもテストも描画も同じ数字を見られるため。
nonisolated struct WorldProjection: Sendable, Equatable {

    /// cos 補正の基準緯度。主要ステージ帯(北米・欧州 40–60°N、アジア・
    /// アフリカ 0–40°N)の折衷として 30° を採る。どこかの帯に合わせるほど
    /// 別の帯が歪む — 全ステージ共通の妥協点であって最適点ではない。
    static let referenceLatitudeDegrees: Double = 30

    /// 平面の左端に写る経度。
    let lonMin: Double
    /// 平面の上端(y = 0)に写る緯度。JSON は y 上向きなので、ここから
    /// 引き算することで y 下向き(SwiftUI と同じ)へ反転する。
    let latMax: Double
    /// 度 → 平面単位の一様スケール(経度側は cos 補正後)。
    let scale: Double

    private static let cosReference = cos(referenceLatitudeDegrees * .pi / 180)

    /// 幅 `width` に `lonMin...lonMax` がちょうど収まる投影。
    /// 範囲が退化していたら nil(ゼロ除算やスケール 0 の地図を作らない)。
    init?(lonMin: Double, lonMax: Double, latMax: Double, width: Double = 1000) {
        guard lonMax > lonMin, width > 0 else { return nil }
        self.lonMin = lonMin
        self.latMax = latMax
        self.scale = width / ((lonMax - lonMin) * Self.cosReference)
    }

    func point(lon: Double, lat: Double) -> CGPoint {
        CGPoint(x: (lon - lonMin) * Self.cosReference * scale,
                y: (latMax - lat) * scale)
    }

    /// 緯度経度の範囲 → 平面の CGRect。y 反転により北端(latMax)が
    /// minY に来る。範囲が裏返っていたら nil(負のサイズの矩形を作らない)。
    /// ワイヤ形式(`[lon0, lat0, lon1, lat1]`)の配列長検査はローダの仕事。
    func rect(lonMin: Double, latMin: Double, lonMax: Double, latMax: Double) -> CGRect? {
        let topLeft = point(lon: lonMin, lat: latMax)
        let bottomRight = point(lon: lonMax, lat: latMin)
        guard bottomRight.x >= topLeft.x, bottomRight.y >= topLeft.y else { return nil }
        return CGRect(x: topLeft.x,
                      y: topLeft.y,
                      width: bottomRight.x - topLeft.x,
                      height: bottomRight.y - topLeft.y)
    }
}

// MARK: - ローダ

/// WorldShapes.json のデコード(CLAUDE.md §3 の世界版)。
///
/// 日本版 `MapDataLoader` は「空地図 > クラッシュ」で握りつぶすが、こちらは
/// 投げる: 世界地図はまだ起動経路に乗っておらず、失敗をどう吸収するかは
/// Atlas 抽象(Task 5)が決める。ローダが黙って空を返すと、その判断の
/// 機会ごと失われる。
nonisolated enum WorldDataLoader {

    enum WorldDataError: Error, Equatable {
        case resourceMissing
        case malformedCountry(code: Int)
        case countriesNotSortedUniquely
        case unknownStage(countryCode: Int, stage: Int)
        case degenerateExtent
        case malformedInset(code: Int)
    }

    // MARK: 生の JSON 形

    private struct WorldFile: Decodable {
        struct Country: Decodable {
            let code: Int
            let nameJa: String
            let kana: String
            let stage: Int
            let bbox: [Double]
            let centroid: [Double]
            let rings: [[[Double]]]
            let europeBbox: [Double]?
        }
        struct Background: Decodable {
            let rings: [[[Double]]]
        }
        struct Inset: Decodable {
            let code: Int
            let scale: Double
            /// `[lon0, lat0, lon1, lat1]`(生成器が配置済みの破線枠)。
            let frame: [Double]
        }
        let countries: [Country]
        let background: [Background]
        let insets: [Inset]
    }

    // MARK: 読み込み

    static func load(bundle: Bundle = .main) throws -> WorldMapData {
        guard let url = bundle.url(forResource: "WorldShapes", withExtension: "json") else {
            throw WorldDataError.resourceMissing
        }
        return try load(contentsOf: url)
    }

    static func load(contentsOf url: URL) throws -> WorldMapData {
        let file = try JSONDecoder().decode(WorldFile.self, from: Data(contentsOf: url))

        // コード昇順・一意は生成器の契約(tools/validate_world_data.py)。
        // 破れていたらデータが別物なので、続けずに投げる。
        let codes = file.countries.map(\.code)
        guard zip(codes, codes.dropFirst()).allSatisfy({ $0 < $1 }) else {
            throw WorldDataError.countriesNotSortedUniquely
        }

        let projection = try makeProjection(for: file.countries)
        let insets = try file.insets.map { inset -> WorldInset in
            // 拡大が 1 倍以下・枠が退化、はどちらも生成器の契約違反。
            guard inset.scale > 1,
                  let frame = rect(fromWire: inset.frame, with: projection),
                  frame.width > 0, frame.height > 0 else {
                throw WorldDataError.malformedInset(code: inset.code)
            }
            return WorldInset(code: inset.code, scale: inset.scale, frame: frame)
        }
        // 重複コードは黙って 1 つに畳まない: insets の配列はこのまま
        // MapData.insets → ForEach(id: \.code) へ流れ、重複 ID の描画は
        // 未定義。並びの契約 (countriesNotSortedUniquely) と同じ生成器の
        // 契約違反として投げる。
        var insetByCode: [Int: WorldInset] = [:]
        for inset in insets {
            guard insetByCode.updateValue(inset, forKey: inset.code) == nil else {
                throw WorldDataError.malformedInset(code: inset.code)
            }
        }
        let countries = try file.countries.map {
            try makeCountry($0, projection: projection, inset: insetByCode[$0.code])
        }
        return WorldMapData(
            recordedCountries: countries,
            stages: makeStages(from: countries),
            background: file.background.map {
                WorldBackgroundShape(flatRings: projectRings($0.rings, with: projection))
            },
            insets: insets)
    }

    // MARK: 変換

    /// 投影の枠は収録国の範囲だけから決める。背景には日付変更線をまたぐ
    /// 南極大陸(+360 正規化で経度 0–354)が入っており、これを含めると
    /// 幅 1000 の 1/3 が誰も遊ばない海になる。背景は同じ投影で写すだけで、
    /// 平面の 0...1000 からはみ出してよい(ステージ枠が後で切り取る)。
    private static func makeProjection(for countries: [WorldFile.Country]) throws -> WorldProjection {
        var lonMin = Double.greatestFiniteMagnitude
        var lonMax = -Double.greatestFiniteMagnitude
        var latMax = -Double.greatestFiniteMagnitude
        for country in countries {
            // bbox はリングの正確な範囲(パイプラインの契約)なので、
            // 全点を舐めずに bbox の集計で足りる。
            guard country.bbox.count >= 4 else {
                throw WorldDataError.malformedCountry(code: country.code)
            }
            lonMin = min(lonMin, country.bbox[0])
            lonMax = max(lonMax, country.bbox[2])
            latMax = max(latMax, country.bbox[3])
        }
        guard let projection = WorldProjection(lonMin: lonMin, lonMax: lonMax, latMax: latMax) else {
            throw WorldDataError.degenerateExtent
        }
        return projection
    }

    private static func makeCountry(_ country: WorldFile.Country,
                                    projection: WorldProjection,
                                    inset: WorldInset?) throws -> WorldCountry {
        // 国のリングは投影の前に生データのまま厳格に検証する。日本版は
        // 1 県落として続行するが、世界版は生成データの破損として全体を
        // 失敗させる方針(ファイル冒頭)。点が欠けた形を黙って繕うと、
        // 出題での見た目とタップ判定がデータと食い違う。
        guard !country.rings.isEmpty,
              country.rings.allSatisfy({ ring in
                  ring.count >= 3 && ring.allSatisfy { $0.count >= 2 }
              }),
              country.centroid.count >= 2,
              let flatBbox = rect(fromWire: country.bbox, with: projection)
        else {
            throw WorldDataError.malformedCountry(code: country.code)
        }
        guard (0..<WorldStage.names.count).contains(country.stage) else {
            throw WorldDataError.unknownStage(countryCode: country.code, stage: country.stage)
        }
        // インセット国はここで拡大して破線枠の中心へ移す(WorldInset の註)。
        // JSON は実位置のままなので、移動は投影と同じ「ロード時の座標変換」の
        // 一部になる。投影はアフィンだから、拡大後の形・重心・bbox の整合は
        // そのまま保たれ、タップ判定も枠の中で普通に成立する(沖縄と同じ)。
        let place = inset.map { relocation(for: $0, originalBbox: flatBbox) } ?? .identity
        return WorldCountry(
            code: country.code,
            nameJa: country.nameJa,
            kana: country.kana,
            stage: country.stage,
            flatRings: country.rings.map { ring in
                ring.map { projection.point(lon: $0[0], lat: $0[1]).applying(place) }
            },
            flatCentroid: projection.point(lon: country.centroid[0],
                                           lat: country.centroid[1]).applying(place),
            flatBbox: flatBbox.applying(place),
            isInset: inset != nil,
            europeBbox: country.europeBbox.flatMap { rect(fromWire: $0, with: projection) })
    }

    /// 実位置の形を `scale` 倍し、拡大後の中心が破線枠の中心に重なるよう
    /// 移す変換: p' = frame中心 + (p − 元bbox中心) × scale。
    private static func relocation(for inset: WorldInset,
                                   originalBbox: CGRect) -> CGAffineTransform {
        CGAffineTransform(
            translationX: inset.frame.midX - originalBbox.midX * inset.scale,
            y: inset.frame.midY - originalBbox.midY * inset.scale)
            .scaledBy(x: inset.scale, y: inset.scale)
    }

    /// 名前は `WorldStage.names`(写し)、所属は JSON、という組み立て。
    /// 国はコード昇順で届くので、各ステージの codes も自然に昇順になる。
    private static func makeStages(from countries: [WorldCountry]) -> [WorldStage] {
        let byStage = Dictionary(grouping: countries, by: \.stage)
        return WorldStage.names.indices.map { index in
            WorldStage(index: index,
                       name: WorldStage.names[index].name,
                       kanjiName: WorldStage.names[index].kanjiName,
                       codes: (byStage[index] ?? []).map(\.code))
        }
    }

    /// `[lon0, lat0, lon1, lat1]` の生配列 → 平面の CGRect。
    /// 配列長の検査はワイヤ形式の都合なので、投影(純関数)ではなく
    /// ローダ側で行う。
    private static func rect(fromWire bbox: [Double],
                             with projection: WorldProjection) -> CGRect? {
        guard bbox.count >= 4 else { return nil }
        return projection.rect(lonMin: bbox[0], latMin: bbox[1],
                               lonMax: bbox[2], latMax: bbox[3])
    }

    /// 背景専用の寛容な投影。欠けた点や退化したリングは黙って落とす —
    /// 背景は装飾で、1 リング欠けても海が少し広く見えるだけだから。
    /// 出題対象になる国のリングは `makeCountry` が投影前に厳格検証して投げる。
    private static func projectRings(_ rings: [[[Double]]],
                                     with projection: WorldProjection) -> [[CGPoint]] {
        rings.compactMap { ring -> [CGPoint]? in
            let points = ring.compactMap { pair -> CGPoint? in
                pair.count >= 2 ? projection.point(lon: pair[0], lat: pair[1]) : nil
            }
            return points.count >= 3 ? points : nil
        }
    }
}
