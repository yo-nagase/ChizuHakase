import CoreGraphics
import SwiftUI

/// 球面版の Path 生成とヒットテスト — `PrefectureGeometry` の同型。
///
/// 純関数なのは平面版と同じ理由: 何が描かれ、タップが何に解決されるかを
/// 同じコードが決めるので、両者が食い違えない。違いは座標変換だけ —
/// `CGAffineTransform` の代わりに `GlobeProjection`(正射図法)を取る。
/// 小さな幾何ヘルパ(線分距離)は平面版の private の写し。共有のために
/// 公開を広げるより、鏡像ファイルとして独立させておく。
nonisolated enum GlobeGeometry {

    // MARK: - Paths

    /// 度数リング → 投影済み Path。点ごとにリムクランプされるので、
    /// 地平線をまたぐポリゴンも閉じたまま描ける。**全点が不可視のリングは
    /// 描かない**(裏側の国は存在しないのと同じ — 設計 §7)。
    /// 外周と穴は同じ path に入れ、even-odd が描画・判定時に選り分ける。
    static func path(rings: [[CGPoint]], projection: GlobeProjection) -> Path {
        var path = Path()
        for ring in visibleScreenRings(rings, projection: projection) {
            guard let first = ring.first else { continue }
            path.move(to: first)
            for point in ring.dropFirst() { path.addLine(to: point) }
            path.closeSubpath()
        }
        return path
    }

    static func path(for shape: GlobeShape, projection: GlobeProjection) -> Path {
        path(rings: shape.rings, projection: projection)
    }

    /// `path(rings:projection:)` と同じ幾何を CGPath で。
    ///
    /// ヒットテストに SwiftUI の `Path.contains(_:eoFill:)` を使わない理由は
    /// 平面版 `PrefectureGeometry.cgPath` の註のとおり: あの呼び出しは
    /// SwiftUI 自身が塗る結果と食い違うことがあり、CGPath の even-odd 判定は
    /// 描画と一致する。タップは子どもが色を見ている場所に落ちるべき。
    static func cgPath(rings: [[CGPoint]], projection: GlobeProjection) -> CGPath {
        let path = CGMutablePath()
        for ring in visibleScreenRings(rings, projection: projection) {
            guard let first = ring.first else { continue }
            path.move(to: first)
            for point in ring.dropFirst() { path.addLine(to: point) }
            path.closeSubpath()
        }
        return path
    }

    /// Even-odd の内側判定。描かれるものと必ず一致する。
    static func contains(_ point: CGPoint,
                         rings: [[CGPoint]],
                         projection: GlobeProjection) -> Bool {
        cgPath(rings: rings, projection: projection).contains(point, using: .evenOdd)
    }

    static func contains(_ point: CGPoint,
                         shape: GlobeShape,
                         projection: GlobeProjection) -> Bool {
        contains(point, rings: shape.rings, projection: projection)
    }

    // MARK: - ヒットテスト

    /// 指の真下にある国。無ければ nil(海)。
    ///
    /// 平面版と違い bbox の cheap reject は置かない — 投影が非線形なので
    /// タダで手に入る変換済み bbox が無く、タップは 1 回きりの計算だから
    /// 交差判定をそのまま回して足りる。
    static func directHit(at point: CGPoint,
                          among shapes: [GlobeShape],
                          projection: GlobeProjection) -> GlobeShape? {
        shapes.first { contains(point, shape: $0, projection: projection) }
    }

    /// 点から国の輪郭(可視リングのみ)までの距離。内側なら 0。
    /// 全リングが裏側の国は最大値 — 描かれない国はタップも引き寄せない。
    ///
    /// 重心でなく輪郭で測る理由は平面版と同じ: ロシアのような横長の国では
    /// 重心が端から遠すぎて、端へのタップを拾えない。
    static func distanceToOutline(_ point: CGPoint,
                                  of shape: GlobeShape,
                                  projection: GlobeProjection) -> CGFloat {
        if contains(point, shape: shape, projection: projection) { return 0 }
        var best = CGFloat.greatestFiniteMagnitude
        for ring in visibleScreenRings(shape.rings, projection: projection) {
            guard ring.count >= 2 else { continue }
            var previous = ring[0]
            for current in ring.dropFirst() {
                best = min(best, distanceToSegment(point, previous, current))
                previous = current
            }
        }
        return best
    }

    /// タップを国へ解決する(CLAUDE.md §3 の球面版)。
    ///
    /// 直接ヒット優先。外れたら許容 `tolerance` 内の最近傍輪郭が勝ち、
    /// 出題中の国には `targetBias` の下駄。半径式でなく最近傍 + バイアスに
    /// する理由づけは平面版 `PrefectureGeometry.resolveTap` の註のとおりで、
    /// 球でも変わらない — 地平線際で前縮みした国こそこの許容が効く(設計 §7)。
    static func resolveTap(
        at point: CGPoint,
        target: GlobeShape?,
        among shapes: [GlobeShape],
        projection: GlobeProjection,
        tolerance: CGFloat = GameRules.tapTolerancePoints,
        targetBias: CGFloat = GameRules.tapTargetBiasPoints
    ) -> GlobeShape? {
        if let hit = directHit(at: point, among: shapes, projection: projection) {
            return hit
        }
        var best: GlobeShape?
        var bestScore = CGFloat.greatestFiniteMagnitude
        for shape in shapes {
            let raw = distanceToOutline(point, of: shape, projection: projection)
            guard raw <= tolerance else { continue }
            let score = shape.code == target?.code ? raw - targetBias : raw
            if score < bestScore {
                best = shape
                bestScore = score
            }
        }
        return best
    }

    // MARK: - 可視と回転

    /// 投影後の重心(平面版 `screenCentroid` の同型)。正解 pop・絵文字
    /// 浮上・コンボの錨はここから取る — 呼び手に度数(x=lon, y=lat,
    /// y 上向き)の解釈をさせると、GlobeShape の註が警告する取り違えを
    /// 呼び手の数だけ再演することになる。
    static func screenCentroid(of shape: GlobeShape,
                               projection: GlobeProjection) -> CGPoint {
        projection.point(lon: Double(shape.centroid.x),
                         lat: Double(shape.centroid.y))
    }

    /// 重心が正面半球にある国(対話・VoiceOver の対象)。リングの一部が
    /// 地平線からのぞいていても重心が裏なら含めない — 読み上げても
    /// 子どもには押せないため。
    static func visibleCodes(among shapes: [GlobeShape],
                             projection: GlobeProjection) -> Set<Int> {
        Set(shapes
            .filter { projection.isVisible(lon: Double($0.centroid.x),
                                           lat: Double($0.centroid.y)) }
            .map(\.code))
    }

    /// 指定の度数重心を正面(スクリーン中心)に置く投影中心。
    /// ヒント(3 ミス)と nameIt の出題前回転に使う(設計 §7 未決の解決)。
    /// 緯度はドラッグと同じ ±85° に畳む — 実データの重心はそこまで北に
    /// ないので実質素通しだが、投影中心の不変条件を 1 カ所に保つ。
    static func centering(on centroid: CGPoint) -> (longitude: Double, latitude: Double) {
        (GlobeProjection.wrappedLongitude(Double(centroid.x)),
         GlobeProjection.clampedLatitude(Double(centroid.y)))
    }

    /// 形そのものから正面へ。CGPoint 版の引数は「度数の重心」であって
    /// スクリーン点ではないので、間違えようのないこちらを常用にする
    /// (平面版の rings:/prefecture: ペアと同じ気配り)。
    static func centering(on shape: GlobeShape) -> (longitude: Double, latitude: Double) {
        centering(on: shape.centroid)
    }

    // MARK: - Small helpers

    /// 可視点を 1 つでも含むリングだけを、投影済みスクリーン座標にして返す。
    /// 描画(path)と判定(contains / distance)が同じ選別を通ることで、
    /// 「見えないのに当たる」「見えるのに当たらない」を作らない。
    private static func visibleScreenRings(_ rings: [[CGPoint]],
                                           projection: GlobeProjection) -> [[CGPoint]] {
        rings.compactMap { ring in
            let projected = ring.map {
                projection.project(lon: Double($0.x), lat: Double($0.y))
            }
            guard projected.contains(where: { $0.isVisible }) else { return nil }
            return projected.map { $0.point }
        }
    }

    private static func distanceToSegment(_ p: CGPoint,
                                          _ a: CGPoint,
                                          _ b: CGPoint) -> CGFloat {
        let ab = CGPoint(x: b.x - a.x, y: b.y - a.y)
        let lengthSquared = ab.x * ab.x + ab.y * ab.y
        guard lengthSquared > 0 else { return distance(p, a) }
        var t = ((p.x - a.x) * ab.x + (p.y - a.y) * ab.y) / lengthSquared
        t = min(max(t, 0), 1)
        return distance(p, CGPoint(x: a.x + ab.x * t, y: a.y + ab.y * t))
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }
}
