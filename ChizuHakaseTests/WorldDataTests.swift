import CoreGraphics
import Foundation
import SwiftUI
import Testing

@testable import ChizuHakase

/// 世界アトラス Task 4(docs/plans/2026-08-19-world-atlas-implementation.md)。
/// WorldShapes.json → WorldMapData のデコードと投影を検証する。
/// 日本版の MapDataTests と同じく、資源は TestResources 経由で実バンドルから読む。
@MainActor
struct WorldDataTests {

    /// 1 回だけデコードして全テストで共有する。`Result` に包むのは、
    /// static 初期化子では try が書けず、`try!`(§11 で禁止)を避けるため。
    static let world = Result {
        try WorldDataLoader.load(contentsOf: TestResources.require("WorldShapes"))
    }

    private func loadedWorld() throws -> WorldMapData {
        try Self.world.get()
    }

    // MARK: - 収録国

    @Test func 全収録国のパスが空でない() throws {
        let world = try loadedWorld()
        // 167 は tools/world_countries.py の STAGE_OF_COUNTRY の総数。
        // ステージ別内訳のテストが同じ正本を参照するので、ここも厳密に数える。
        #expect(world.recordedCountries.count == 167)
        for country in world.recordedCountries {
            let path = PrefectureGeometry.path(rings: country.flatRings, transform: .identity)
            #expect(!path.isEmpty, "code \(country.code) produced an empty Path")
            #expect(!country.kana.isEmpty, "code \(country.code) has no kana")
            #expect(!country.nameJa.isEmpty, "code \(country.code) has no name")
        }
    }

    @Test func 国コードで引ける() throws {
        let world = try loadedWorld()
        #expect(world[392]?.nameJa == "日本")
        #expect(world[392]?.kana == "にほん")
        // 台湾は収録・バーレーンは背景、という裁定(2026-08-18-world-stages.md)が
        // データまで届いていることの確認。
        #expect(world[158] != nil)
        #expect(world[48] == nil)
    }

    /// 重心はラベルとエフェクトの錨なので、自国の中に無いと嘘の位置に出る。
    /// インセット国は除外: モルディブは環礁の列で、重心が海に落ちるのは
    /// 形状の性質であり、拡大表示(インセット)側で扱う問題だから。
    /// bbox 中心へのフォールバックは CGPath の数値誤差の逃げ道として残すが、
    /// パイプラインは pole of inaccessibility を出すので件数はごく少ないはず。
    @Test func 重心が自国に含まれる() throws {
        let world = try loadedWorld()
        var fallbackCount = 0
        for country in world.recordedCountries where !country.isInset {
            let inside = PrefectureGeometry.contains(
                country.flatCentroid, rings: country.flatRings, transform: .identity)
            if inside { continue }
            let center = CGPoint(x: country.flatBbox.midX, y: country.flatBbox.midY)
            let centerInside = PrefectureGeometry.contains(
                center, rings: country.flatRings, transform: .identity)
            #expect(centerInside, "code \(country.code): 重心も bbox 中心も外")
            fallbackCount += 1
        }
        #expect(fallbackCount <= 15, "bbox フォールバックが \(fallbackCount) 件")
    }

    // MARK: - ステージ

    @Test func ステージの国数が設計と一致する() throws {
        let world = try loadedWorld()
        // 正本は tools/world_countries.py の STAGE_OF_COUNTRY。
        // ステージ表(2026-08-18-world-stages.md)の「収録」列と同じ並び。
        let expectedCounts = [10, 6, 12, 10, 7, 10, 12, 6, 15, 8, 15, 5, 16, 5, 9, 6, 11, 4]
        #expect(world.stages.count == 18)
        #expect(world.stages.map(\.codes.count) == expectedCounts)

        let allCodes = world.stages.flatMap(\.codes)
        #expect(allCodes.count == world.recordedCountries.count)
        #expect(Set(allCodes).count == allCodes.count, "国が複数ステージに重複")
        #expect(Set(allCodes) == Set(world.recordedCountries.map(\.code)))
    }

    @Test func ステージ名が正本と揃っている() throws {
        let world = try loadedWorld()
        // 名前の正本は tools/world_countries.py の STAGES(JSON には入っていない)。
        #expect(world.stages.map(\.index) == Array(0...17))
        #expect(world.stages[0].name == "きた・ちゅうおうアメリカ")
        #expect(world.stages[0].kanjiName == "北・中央アメリカ")
        #expect(world.stages[17].name == "オセアニア")
        for stage in world.stages {
            #expect(!stage.name.isEmpty && !stage.kanjiName.isEmpty, "stage \(stage.index)")
        }
    }

    // MARK: - インセット・背景・ヨーロッパ枠

    @Test func インセット宣言と国のフラグが一致する() throws {
        let world = try loadedWorld()
        // 裁定(2026-08-19): シンガポール・マルタ・モルディブ・フィジーを拡大する。
        #expect(Set(world.insets.map(\.code)) == [242, 462, 470, 702])
        for inset in world.insets {
            #expect(inset.scale > 1, "code \(inset.code) の倍率が拡大になっていない")
        }
        let flagged = Set(world.recordedCountries.filter(\.isInset).map(\.code))
        #expect(flagged == Set(world.insets.map(\.code)))
    }

    /// インセット国はロード時に scale 倍され、破線枠の中心へ移されている
    /// (`WorldInset` の註 — 沖縄の別枠と同じ見た目・同じタップの仕組み)。
    @Test func インセット国は枠の中へ拡大されて置かれる() throws {
        let world = try loadedWorld()
        for inset in world.insets {
            let country = try #require(world[inset.code])
            #expect(inset.frame.width > 0 && inset.frame.height > 0,
                    "code \(inset.code) の枠が潰れている")
            #expect(inset.frame.contains(country.flatBbox),
                    "code \(inset.code): \(country.flatBbox) が枠 \(inset.frame) の外")
            // 中心合わせ: 拡大後の形の中心 = 枠の中心(ローダの relocation)。
            #expect(abs(country.flatBbox.midX - inset.frame.midX) < 0.01, "code \(inset.code)")
            #expect(abs(country.flatBbox.midY - inset.frame.midY) < 0.01, "code \(inset.code)")
            // 錨も形と一緒に動く — ラベルやポップが枠の外に出ない。
            #expect(inset.frame.contains(country.flatCentroid), "code \(inset.code)")
        }
    }

    @Test func 背景の海岸線が同じ平面に載る() throws {
        let world = try loadedWorld()
        #expect(!world.background.isEmpty)
        for shape in world.background {
            #expect(!shape.flatRings.isEmpty)
            #expect(shape.flatRings.allSatisfy { $0.count >= 3 })
        }
    }

    @Test func ロシアだけがヨーロッパ枠を持つ() throws {
        let world = try loadedWorld()
        let russia = try #require(world[643])
        let box = try #require(russia.europeBbox)
        #expect(box.width > 0 && box.height > 0)
        // 枠はロシア自身の範囲の内側(平面座標で比較できることの確認も兼ねる)
        #expect(russia.flatBbox.contains(box))
        for country in world.recordedCountries where country.code != 643 {
            #expect(country.europeBbox == nil, "code \(country.code)")
        }
    }

    // MARK: - 投影(データ全体)

    @Test func 幅が1000に正規化される() throws {
        let world = try loadedWorld()
        // 幅の基準は収録国のみ。背景には日付変更線をまたぐ南極大陸が
        // +360 正規化で入っており、含めると横幅の 1/3 が空の海になる。
        let xs = world.recordedCountries.flatMap { $0.flatRings.flatMap { $0.map(\.x) } }
        let maxX = try #require(xs.max())
        let minX = try #require(xs.min())
        #expect(abs(maxX - 1000) < 0.5, "max x = \(maxX)")
        #expect(abs(minX) < 0.5, "min x = \(minX)")
    }

    @Test func 北の国が南の国より上に描かれる() throws {
        let world = try loadedWorld()
        // JSON は lat が上向き。y 反転を忘れると世界が上下逆さまになる。
        let iceland = try #require(world[352])
        let australia = try #require(world[36])
        #expect(iceland.flatCentroid.y < australia.flatCentroid.y)
    }

    @Test func フィジーが日付変更線で割れない() throws {
        let world = try loadedWorld()
        // パイプラインが 180° またぎを +360 正規化済み。生の ±180 のままだと
        // フィジーの平面 x は 900 以上に散らばる。細い帯に収まることを確認する。
        let fiji = try #require(world[242])
        let xs = fiji.flatRings.flatMap { $0.map(\.x) }
        let spread = try #require(xs.max()) - (try #require(xs.min()))
        #expect(spread < 40, "フィジーの x 帯域 = \(spread)")
    }
}

/// 純関数としての投影の性質。ロード済みデータに依存しない。
struct WorldProjectionTests {

    private func makeProjection() throws -> WorldProjection {
        try #require(WorldProjection(lonMin: 10, lonMax: 110, latMax: 50))
    }

    @Test func 基準点が原点に写る() throws {
        let projection = try makeProjection()
        let origin = projection.point(lon: 10, lat: 50)
        #expect(abs(origin.x) < 1e-9)
        #expect(abs(origin.y) < 1e-9)
    }

    @Test func 経度の右端が幅いっぱいに写る() throws {
        let projection = try makeProjection()
        #expect(abs(projection.point(lon: 110, lat: 50).x - 1000) < 1e-9)
    }

    @Test func 北ほどyが小さい() throws {
        let projection = try makeProjection()
        let north = projection.point(lon: 60, lat: 40)
        let south = projection.point(lon: 60, lat: 10)
        #expect(north.y < south.y)
    }

    @Test func 緯度1度は経度1度よりcos補正ぶん長い() throws {
        // cos 補正の存在確認。補正が無いと縦横 1° が同じ長さになり、
        // 中緯度の国が縦につぶれて見える。
        let projection = try makeProjection()
        let dx = projection.point(lon: 61, lat: 40).x - projection.point(lon: 60, lat: 40).x
        let dy = projection.point(lon: 60, lat: 39).y - projection.point(lon: 60, lat: 40).y
        let expectedRatio = 1 / cos(WorldProjection.referenceLatitudeDegrees * .pi / 180)
        #expect(abs(dy / dx - expectedRatio) < 1e-9)
    }

    @Test func 退化した範囲は作れない() {
        #expect(WorldProjection(lonMin: 10, lonMax: 10, latMax: 50) == nil)
        #expect(WorldProjection(lonMin: 20, lonMax: 10, latMax: 50) == nil)
    }

    @Test func 緯度経度の範囲が平面の矩形に写る() throws {
        let projection = try makeProjection()
        // 北端(latMax)が minY に来る(y 反転)。
        let rect = try #require(projection.rect(lonMin: 20, latMin: 30, lonMax: 40, latMax: 45))
        let topLeft = projection.point(lon: 20, lat: 45)
        let bottomRight = projection.point(lon: 40, lat: 30)
        #expect(abs(rect.minX - topLeft.x) < 1e-9)
        #expect(abs(rect.minY - topLeft.y) < 1e-9)
        #expect(abs(rect.maxX - bottomRight.x) < 1e-9)
        #expect(abs(rect.maxY - bottomRight.y) < 1e-9)
        #expect(rect.width > 0 && rect.height > 0)
        // 裏返った範囲は矩形にしない
        #expect(projection.rect(lonMin: 40, latMin: 30, lonMax: 20, latMax: 45) == nil)
    }
}

/// 壊れた生成データを黙って読まないことの検証。`WorldDataError` が
/// Equatable なのは、ここで `#expect(throws:)` の比較に使うため。
struct WorldDataLoaderErrorTests {

    /// 最小限の妥当な国 1 件ぶんの JSON 断片。引数で壊し方を選ぶ。
    private func countryJSON(code: Int, stage: Int = 0,
                             rings: String = "[[[0, 0], [2, 0], [2, 2], [0, 0]]]") -> String {
        """
        {"code": \(code), "nameJa": "テスト", "kana": "てすと", "stage": \(stage), \
        "bbox": [0, 0, 2, 2], "centroid": [1.2, 0.7], "rings": \(rings)}
        """
    }

    private func writeFixture(countries: [String], insets: String = "[]") throws -> URL {
        let json = """
        {"countries": [\(countries.joined(separator: ","))], "background": [], \
        "insets": \(insets)}
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorldDataTests-\(UUID().uuidString)")
            .appendingPathExtension("json")
        try Data(json.utf8).write(to: url)
        return url
    }

    @Test func 国コードの並びが壊れていたら投げる() throws {
        // コード昇順・一意は生成器の契約。降順はその破れの最小例。
        let url = try writeFixture(countries: [countryJSON(code: 20), countryJSON(code: 10)])
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: WorldDataLoader.WorldDataError.countriesNotSortedUniquely) {
            _ = try WorldDataLoader.load(contentsOf: url)
        }
    }

    @Test func 知らないステージ番号は投げる() throws {
        let url = try writeFixture(countries: [countryJSON(code: 10, stage: 99)])
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: WorldDataLoader.WorldDataError.unknownStage(countryCode: 10, stage: 99)) {
            _ = try WorldDataLoader.load(contentsOf: url)
        }
    }

    @Test func 面にならないリングは投げる() throws {
        // 2 点では面にならない。背景と違って国は黙って落とさない。
        let url = try writeFixture(countries: [countryJSON(code: 10, rings: "[[[0, 0], [2, 2]]]")])
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: WorldDataLoader.WorldDataError.malformedCountry(code: 10)) {
            _ = try WorldDataLoader.load(contentsOf: url)
        }
    }

    @Test func 座標が欠けた点は投げる() throws {
        // 経度だけの点([2])が混ざったリング。
        let url = try writeFixture(
            countries: [countryJSON(code: 10, rings: "[[[0, 0], [2, 0], [2], [0, 0]]]")])
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: WorldDataLoader.WorldDataError.malformedCountry(code: 10)) {
            _ = try WorldDataLoader.load(contentsOf: url)
        }
    }

    /// ローダのインセット移動そのものの検算(実データ非依存の固定値)。
    /// 国 bbox [0,0,2,2]・scale 2 に対し、枠は lon 3–7 / lat -3–1(ちょうど
    /// 拡大後の寸法)。投影して p' = 枠中心 + (p − 元中心) × 2 になること。
    @Test func インセットは枠の中心へ拡大して写される() throws {
        let url = try writeFixture(
            countries: [countryJSON(code: 10)],
            insets: #"[{"code": 10, "scale": 2, "frame": [3, -3, 7, 1]}]"#)
        defer { try? FileManager.default.removeItem(at: url) }
        let world = try WorldDataLoader.load(contentsOf: url)
        let country = try #require(world[10])
        let frame = try #require(world.insets.first).frame
        // 拡大後の bbox が枠と一致する(この固定値では寸法まで等しい)。
        #expect(abs(country.flatBbox.minX - frame.minX) < 0.01)
        #expect(abs(country.flatBbox.maxY - frame.maxY) < 0.01)
        #expect(abs(country.flatBbox.width - frame.width) < 0.01)
        // 元 (lon 0, lat 0) は枠の左下へ写る(投影は y 下向き)。
        let corner = try #require(country.flatRings.first?.first)
        #expect(abs(corner.x - frame.minX) < 0.01)
        #expect(abs(corner.y - frame.maxY) < 0.01)
        #expect(country.isInset)
    }

    @Test func 壊れたインセット宣言は投げる() throws {
        // 潰れた枠(経度スパン 0)。
        let flat = try writeFixture(
            countries: [countryJSON(code: 10)],
            insets: #"[{"code": 10, "scale": 2, "frame": [5, -3, 5, 1]}]"#)
        defer { try? FileManager.default.removeItem(at: flat) }
        #expect(throws: WorldDataLoader.WorldDataError.malformedInset(code: 10)) {
            _ = try WorldDataLoader.load(contentsOf: flat)
        }
        // 縮小(scale 1 以下)のインセットは無意味 — 生成器の契約違反。
        let shrink = try writeFixture(
            countries: [countryJSON(code: 10)],
            insets: #"[{"code": 10, "scale": 1, "frame": [3, -3, 7, 1]}]"#)
        defer { try? FileManager.default.removeItem(at: shrink) }
        #expect(throws: WorldDataLoader.WorldDataError.malformedInset(code: 10)) {
            _ = try WorldDataLoader.load(contentsOf: shrink)
        }
    }
}
