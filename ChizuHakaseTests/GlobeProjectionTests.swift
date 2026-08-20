import CoreGraphics
import Foundation
import SwiftUI
import Testing

@testable import ChizuHakase

/// 地球儀 P7 Task 1(docs/plans/2026-08-20-world-globe-challenge-plan.md)。
/// 正射図法(GlobeProjection)を手計算値でピン留めする。
/// ロード済みデータに依存しない純関数のテスト(WorldProjectionTests と同じ流儀)。
struct GlobeProjectionTests {

    /// R = 100pt、スクリーン中心 (200, 300) の標準投影。
    private func makeProjection(lon0: Double = 0, lat0: Double = 0) -> GlobeProjection {
        GlobeProjection(centerLongitude: lon0,
                        centerLatitude: lat0,
                        radius: 100,
                        screenCenter: CGPoint(x: 200, y: 300))
    }

    // MARK: - 前方投影

    @Test func 正面の点がスクリーン中心に写る() {
        let projection = makeProjection()
        let point = projection.point(lon: 0, lat: 0)
        #expect(abs(point.x - 200) < 1e-9)
        #expect(abs(point.y - 300) < 1e-9)
        #expect(projection.isVisible(lon: 0, lat: 0))
    }

    @Test func 東へ90度の点が右端に写る() {
        // x = R·cos(0)·sin(90°) = R。地平線上なので位置はリムそのもの。
        let point = makeProjection().point(lon: 90, lat: 0)
        #expect(abs(point.x - 300) < 1e-9)
        #expect(abs(point.y - 300) < 1e-9)
    }

    @Test func 北へ90度の点が上端に写る() {
        // y′ = R·sin(90°) = R。スクリーンは y 下向きなので上端は C.y − R。
        let point = makeProjection().point(lon: 0, lat: 90)
        #expect(abs(point.x - 200) < 1e-9)
        #expect(abs(point.y - 200) < 1e-9)
    }

    @Test func ちょうど90度離れた点は不可視() {
        // cosC = 0 は「エッジオン」— 見かけの幅がゼロなので不可視側に倒す。
        // 浮動小数の cos(π/2) ≈ 6e-17 > 0 に騙されないこともここで保証する。
        let projection = makeProjection()
        #expect(!projection.isVisible(lon: 90, lat: 0))
        #expect(!projection.isVisible(lon: 0, lat: 90))
    }

    @Test func 裏側の点はリムへクランプされる() {
        // (150, 0) の生の投影は x = R·sin(150°) = R/2 だが、裏側なので
        // 長さ R に正規化されてリム (C.x + R, C.y) に乗る。
        let projection = makeProjection()
        #expect(!projection.isVisible(lon: 150, lat: 0))
        let point = projection.point(lon: 150, lat: 0)
        #expect(abs(point.x - 300) < 1e-9)
        #expect(abs(point.y - 300) < 1e-9)
    }

    @Test func 対蹠点もリムに乗る() {
        // 真裏は (x, y′) = (0, 0) に写り正規化の向きが定まらないが、
        // どこであれ中心から距離 R の縁に決定的に置かれること。
        let projection = makeProjection()
        let point = projection.point(lon: 180, lat: 0)
        let dx = point.x - 200
        let dy = point.y - 300
        #expect(abs((dx * dx + dy * dy).squareRoot() - 100) < 1e-9)
        #expect(!projection.isVisible(lon: 180, lat: 0))
    }

    @Test func 傾いた中心では緯度項が可視を決める() {
        // cosC = sin(lat0)·sin(lat) + cos(lat0)·cos(lat)·cosΔλ の第 1 項は
        // lat0 = 0 だと消えて、どの符号でもテストが通ってしまう。北へ 60°
        // 傾けた中心から南緯 45° は cosC = sin60·sin(−45) + cos60·cos(−45)
        // ≈ −0.259 で不可視。第 1 項の符号を間違えると ≈ +0.966 で可視に
        // 化けるので、ここで殺す。
        let projection = makeProjection(lat0: 60)
        #expect(!projection.isVisible(lon: 0, lat: -45))
    }

    @Test func 地平線の手前は可視のまま() {
        // 不可視側のしきい値は丸め誤差ぶんの幅しかないはず。しきい値が
        // 育って実在の点(89.9° 離れ ≈ cosC 0.0017)を飲み込んだら
        // ここで気づく。
        #expect(makeProjection().isVisible(lon: 89.9, lat: 0))
    }

    @Test func 高緯度ほど経度1度が狭く写る() {
        // 緯度 60° では cos(60°) = 0.5 — 赤道の半分の幅。
        // この前縮みが無いと地球儀が円筒に見える。
        let projection = makeProjection()
        let atEquator = projection.point(lon: 1, lat: 0).x - 200
        let atSixty = projection.point(lon: 1, lat: 60).x - 200
        #expect(abs(atSixty / atEquator - 0.5) < 1e-9)
    }

    @Test func 日付変更線をまたいだ正規化経度が等価に写る() {
        // フィジーは +360 正規化で lon 189.75 を持つ(WorldDataTests)。
        // 三角関数上 −170.25 と等価なので、そのまま食わせて同じ点に写ること。
        let projection = makeProjection(lon0: 180, lat0: -17)
        let normalized = projection.point(lon: 189.75, lat: -17)
        let wrapped = projection.point(lon: -170.25, lat: -17)
        #expect(abs(normalized.x - wrapped.x) < 1e-9)
        #expect(abs(normalized.y - wrapped.y) < 1e-9)
        #expect(projection.isVisible(lon: 189.75, lat: -17))
    }

    // MARK: - ドラッグ回転

    @Test func 右ドラッグで中心経度が減る() {
        // 右へ引くと西側が正面に来る = lon0 が減る。Δlon = −Δx/R·(180/π)。
        let dragged = makeProjection().dragged(by: CGSize(width: 10, height: 0))
        let expected = -10.0 / 100.0 * 180 / Double.pi
        #expect(dragged.centerLongitude < 0)
        #expect(abs(dragged.centerLongitude - expected) < 1e-9)
        #expect(dragged.centerLatitude == 0)
    }

    @Test func 下ドラッグで中心緯度が増える() {
        // 下へ引くと北側が正面に来る = lat0 が増える。Δlat = +Δy/R·(180/π)。
        let dragged = makeProjection().dragged(by: CGSize(width: 0, height: 10))
        let expected = 10.0 / 100.0 * 180 / Double.pi
        #expect(dragged.centerLatitude > 0)
        #expect(abs(dragged.centerLatitude - expected) < 1e-9)
        #expect(dragged.centerLongitude == 0)
    }

    @Test func 中心緯度は85度でクランプされる() {
        let limit = GlobeProjection.centerLatitudeLimitDegrees
        let north = makeProjection(lat0: 80).dragged(by: CGSize(width: 0, height: 3000))
        #expect(north.centerLatitude == limit)
        let south = makeProjection(lat0: -80).dragged(by: CGSize(width: 0, height: -3000))
        #expect(south.centerLatitude == -limit)
    }

    @Test func 西へドラッグし続けても経度が壊れない() {
        // 左ドラッグ 100 回 = 累計 +2864.79°。wrap しないと Double の
        // 分解能が落ちていく。(−180, 180] に畳まれ、値も合っていること。
        var projection = makeProjection()
        let step = CGSize(width: -50, height: 0)
        for _ in 0..<100 { projection = projection.dragged(by: step) }
        #expect(projection.centerLongitude.isFinite)
        #expect(projection.centerLongitude > -180)
        #expect(projection.centerLongitude <= 180)
        var expected = 100 * (50.0 / 100.0 * 180 / Double.pi)
        while expected > 180 { expected -= 360 }
        #expect(abs(projection.centerLongitude - expected) < 1e-6)
    }

    @Test func 半径ゼロのドラッグは投影を変えない() {
        // レイアウト初回のサイズ 0 の瞬間にドラッグが届くと、ゼロ除算の
        // NaN が状態を恒久的に汚す。素通しで守る。
        let degenerate = GlobeProjection(centerLongitude: 12,
                                         centerLatitude: 34,
                                         radius: 0,
                                         screenCenter: .zero)
        let dragged = degenerate.dragged(by: CGSize(width: 10, height: 10))
        #expect(dragged == degenerate)
    }
}

/// 球面版ジオメトリ(GlobeGeometry)。度数リングの合成国でピン留めする。
struct GlobeGeometryTests {

    private func makeProjection(lon0: Double = 0, lat0: Double = 0) -> GlobeProjection {
        GlobeProjection(centerLongitude: lon0,
                        centerLatitude: lat0,
                        radius: 100,
                        screenCenter: CGPoint(x: 200, y: 300))
    }

    /// 度数の矩形国。リング末尾は実データと同じく閉環重複点を持つ。
    private func box(code: Int,
                     lon: ClosedRange<CGFloat>,
                     lat: ClosedRange<CGFloat>) -> GlobeShape {
        let ring = [
            CGPoint(x: lon.lowerBound, y: lat.lowerBound),
            CGPoint(x: lon.upperBound, y: lat.lowerBound),
            CGPoint(x: lon.upperBound, y: lat.upperBound),
            CGPoint(x: lon.lowerBound, y: lat.upperBound),
            CGPoint(x: lon.lowerBound, y: lat.lowerBound),
        ]
        return GlobeShape(code: code,
                          rings: [ring],
                          centroid: CGPoint(x: (lon.lowerBound + lon.upperBound) / 2,
                                            y: (lat.lowerBound + lat.upperBound) / 2))
    }

    /// 原点中心 ±5° の正方形国。
    private var frontBox: GlobeShape { box(code: 1, lon: -5...5, lat: -5...5) }

    // MARK: - Path

    @Test func 正面の国のパスが描かれる() {
        let path = GlobeGeometry.path(rings: frontBox.rings, projection: makeProjection())
        #expect(!path.isEmpty)
    }

    @Test func 全点が裏側のリングは描かれない() {
        let farSide = box(code: 9, lon: 175...185, lat: -5...5)
        let path = GlobeGeometry.path(rings: farSide.rings, projection: makeProjection())
        #expect(path.isEmpty)
    }

    // MARK: - ヒットテスト

    @Test func 国の内側の判定が成立する() {
        let projection = makeProjection()
        #expect(GlobeGeometry.contains(CGPoint(x: 200, y: 300),
                                       shape: frontBox, projection: projection))
        #expect(!GlobeGeometry.contains(CGPoint(x: 250, y: 300),
                                        shape: frontBox, projection: projection))
    }

    @Test func 穴の中は国の外() {
        // ドーナツ国: 外周 ±5°・穴 ±2°。even-odd なので穴の中(スクリーン
        // 中心)は外、外周と穴の間の帯は中。穴を別 path にすると帯ごと
        // 塗り潰されるので、この判定が描画規約(同一 path + even-odd)を守る。
        let outer = frontBox.rings[0]
        let hole = box(code: 0, lon: -2...2, lat: -2...2).rings[0]
        let donut = GlobeShape(code: 8, rings: [outer, hole], centroid: .zero)
        let projection = makeProjection()
        #expect(!GlobeGeometry.contains(CGPoint(x: 200, y: 300),
                                        shape: donut, projection: projection))
        // 帯の中ほど lon 3.5°: 穴の縁 ≈ 203.5、外周 ≈ 208.7 の間。
        #expect(GlobeGeometry.contains(CGPoint(x: 206.1, y: 300),
                                       shape: donut, projection: projection))
    }

    @Test func 直接ヒットで国に解決する() {
        let resolved = GlobeGeometry.resolveTap(at: CGPoint(x: 200, y: 300),
                                                target: nil,
                                                among: [frontBox],
                                                projection: makeProjection())
        #expect(resolved?.code == frontBox.code)
    }

    @Test func 輪郭の近くのタップが許容内で解決する() {
        // 右端 lon 5° は x ≈ 100·cos(5°)·sin(5°) ≈ 8.68 → スクリーン x ≈ 208.7。
        // (215, 300) は約 6.3pt の海 — 許容 22pt の内側。
        let resolved = GlobeGeometry.resolveTap(at: CGPoint(x: 215, y: 300),
                                                target: nil,
                                                among: [frontBox],
                                                projection: makeProjection())
        #expect(resolved?.code == frontBox.code)
    }

    @Test func 許容を超えたタップは海になる() {
        // (250, 300) は右端から約 41pt。許容 22pt の外。
        let resolved = GlobeGeometry.resolveTap(at: CGPoint(x: 250, y: 300),
                                                target: frontBox,
                                                among: [frontBox],
                                                projection: makeProjection())
        #expect(resolved == nil)
    }

    @Test func バイアスは許容を広げない() {
        // 右端(x ≈ 208.7)から約 26pt — 許容 22pt の外・バイアス 10pt の内。
        // 下駄は許容内の綱引きにだけ効き、届く範囲そのものは広げないこと
        // (バイアスを引いてから許容と比べる実装だとここで落ちる)。
        let resolved = GlobeGeometry.resolveTap(at: CGPoint(x: 235, y: 300),
                                                target: frontBox,
                                                among: [frontBox],
                                                projection: makeProjection())
        #expect(resolved == nil)
    }

    @Test func 裏側の国はタップに解決しない() {
        // 地球の裏へ回った国は描かれない — 描かれない国はタップも受けない。
        let projection = makeProjection(lon0: 180)
        let resolved = GlobeGeometry.resolveTap(at: CGPoint(x: 200, y: 300),
                                                target: frontBox,
                                                among: [frontBox],
                                                projection: projection)
        #expect(resolved == nil)
    }

    @Test func 出題中の国が等距離の綱引きに勝つ() {
        // 中心 (200, 300) は両国の縁からほぼ等距離(約 1.7pt)の海。
        // targetBias の下駄で、訊かれている側が勝つこと。
        let west = box(code: 1, lon: -10 ... -1, lat: -5...5)
        let east = box(code: 2, lon: 1...10, lat: -5...5)
        let projection = makeProjection()
        let tap = CGPoint(x: 200, y: 300)
        let toWest = GlobeGeometry.resolveTap(at: tap, target: west,
                                              among: [west, east], projection: projection)
        #expect(toWest?.code == west.code)
        let toEast = GlobeGeometry.resolveTap(at: tap, target: east,
                                              among: [west, east], projection: projection)
        #expect(toEast?.code == east.code)
    }

    // MARK: - 可視コード

    @Test func 投影後の重心が取れる() {
        // エフェクトのアンカー(平面版 screenCentroid の同型)。度数重心
        // (10, 20) の手計算: x = 100·cos(20°)·sin(10°) ≈ 16.3176、
        // y′ = 100·sin(20°) ≈ 34.2020(スクリーンでは C.y から引く)。
        let shape = box(code: 4, lon: 5...15, lat: 15...25)
        let point = GlobeGeometry.screenCentroid(of: shape, projection: makeProjection())
        #expect(abs(point.x - 216.31759111665348) < 1e-6)
        #expect(abs(point.y - 265.79798566743313) < 1e-6)
    }

    @Test func 重心が正面の国だけが可視コードに入る() {
        let front = frontBox
        let back = box(code: 2, lon: 175...185, lat: -5...5)
        let horizon = box(code: 3, lon: 85...95, lat: -5...5)  // 重心がちょうど 90°
        let codes = GlobeGeometry.visibleCodes(among: [front, back, horizon],
                                               projection: makeProjection())
        #expect(codes == [front.code])
    }

    // MARK: - Centering

    @Test func centeringで重心が正面に来る() {
        // シンガポールの度数重心(≈ 103.8E, 1.35N)を正面へ回すと、
        // その点はスクリーン中心に写り、可視になる。
        let centroid = CGPoint(x: 103.8, y: 1.35)
        let center = GlobeGeometry.centering(on: centroid)
        let projection = GlobeProjection(centerLongitude: center.longitude,
                                         centerLatitude: center.latitude,
                                         radius: 100,
                                         screenCenter: CGPoint(x: 200, y: 300))
        let point = projection.point(lon: 103.8, lat: 1.35)
        #expect(abs(point.x - 200) < 1e-9)
        #expect(abs(point.y - 300) < 1e-9)
        #expect(projection.isVisible(lon: 103.8, lat: 1.35))
    }

    @Test func centeringは形からも呼べる() {
        // 呼び手が度数重心を手で取り出さなくてよい形のオーバーロード。
        // CGPoint 版と同じく wrap(189.75 → −170.25)まで通ること。
        let fiji = box(code: 6, lon: 184.75...194.75, lat: (-22)...(-12))
        let center = GlobeGeometry.centering(on: fiji)
        #expect(abs(center.longitude - (-170.25)) < 1e-9)
        #expect(center.latitude == -17)
    }

    @Test func centeringは緯度をクランプし経度を畳む() {
        let polar = GlobeGeometry.centering(on: CGPoint(x: 0, y: 89))
        #expect(polar.latitude == GlobeProjection.centerLatitudeLimitDegrees)
        // フィジー流の +360 正規化重心は (−180, 180] に畳まれる。
        // 三角関数上は等価なので、畳んでも正面に来ること自体は変わらない。
        let fiji = GlobeGeometry.centering(on: CGPoint(x: 189.75, y: -17))
        #expect(abs(fiji.longitude - (-170.25)) < 1e-9)
        let projection = GlobeProjection(centerLongitude: fiji.longitude,
                                         centerLatitude: fiji.latitude,
                                         radius: 100,
                                         screenCenter: CGPoint(x: 200, y: 300))
        #expect(projection.isVisible(lon: 189.75, lat: -17))
        let point = projection.point(lon: 189.75, lat: -17)
        #expect(abs(point.x - 200) < 1e-9)
        #expect(abs(point.y - 300) < 1e-9)
    }
}
