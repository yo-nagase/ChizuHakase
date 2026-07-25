import CoreGraphics
import SwiftUI

/// Path building, fitting and hit testing for prefecture shapes (CLAUDE.md §3).
///
/// Pure functions on purpose: the same code decides what is drawn and what a
/// tap resolves to, so the two can never disagree.
nonisolated enum PrefectureGeometry {

    // MARK: - Paths

    /// Rings -> Path. Outer boundaries and holes go in the same path; even-odd
    /// filling sorts them out at draw and hit-test time.
    static func path(rings: [[CGPoint]], transform: CGAffineTransform) -> Path {
        var path = Path()
        for ring in rings {
            guard let first = ring.first else { continue }
            path.move(to: first.applying(transform))
            for point in ring.dropFirst() {
                path.addLine(to: point.applying(transform))
            }
            path.closeSubpath()
        }
        return path
    }

    static func path(for prefecture: Prefecture, transform: CGAffineTransform) -> Path {
        path(rings: prefecture.rings, transform: transform)
    }

    /// Same geometry as `path(rings:transform:)`, as a CGPath.
    ///
    /// Hit testing deliberately does **not** use SwiftUI's
    /// `Path.contains(_:eoFill:)`. On this data that call disagrees with what
    /// SwiftUI itself draws: for Kanagawa, Gifu and Shizuoka it reports the
    /// centroid as outside a shape it fills solidly (~7% of those bounding
    /// boxes disagree). CGPath's even-odd test matches the rendering, so taps
    /// land where the child can see colour. Verified by `MapDataTests`.
    static func cgPath(rings: [[CGPoint]], transform: CGAffineTransform) -> CGPath {
        let path = CGMutablePath()
        for ring in rings {
            guard let first = ring.first else { continue }
            path.move(to: first.applying(transform))
            for point in ring.dropFirst() {
                path.addLine(to: point.applying(transform))
            }
            path.closeSubpath()
        }
        return path
    }

    /// Even-odd containment, agreeing with what gets drawn.
    static func contains(_ point: CGPoint,
                         rings: [[CGPoint]],
                         transform: CGAffineTransform) -> Bool {
        cgPath(rings: rings, transform: transform).contains(point, using: .evenOdd)
    }

    static func contains(_ point: CGPoint,
                         prefecture: Prefecture,
                         transform: CGAffineTransform) -> Bool {
        contains(point, rings: prefecture.rings, transform: transform)
    }

    /// Unsigned shoelace area, used to order rings largest-first.
    static func absoluteArea(of ring: [CGPoint]) -> CGFloat {
        guard ring.count >= 3 else { return 0 }
        var sum: CGFloat = 0
        for i in 0..<ring.count {
            let a = ring[i]
            let b = ring[(i + 1) % ring.count]
            sum += a.x * b.y - b.x * a.y
        }
        return abs(sum) / 2
    }

    // MARK: - Fitting

    static func boundingBox(of prefectures: [Prefecture]) -> CGRect {
        prefectures.dropFirst().reduce(prefectures.first?.bbox ?? .zero) {
            $0.union($1.bbox)
        }
    }

    /// Aspect-fit `bounds` into `size`, padded. Uniform scale on both axes —
    /// stretching would distort shapes children are learning to recognise.
    static func fitTransform(
        bounds: CGRect,
        into size: CGSize,
        paddingRatio: CGFloat = GameRules.mapPaddingRatio,
        paddingPoints: CGFloat = GameRules.mapPaddingPoints
    ) -> CGAffineTransform {
        guard bounds.width > 0, bounds.height > 0, size.width > 0, size.height > 0 else {
            return .identity
        }
        let padded = bounds.insetBy(dx: -bounds.width * paddingRatio,
                                    dy: -bounds.height * paddingRatio)
        let available = CGSize(width: max(1, size.width - paddingPoints * 2),
                               height: max(1, size.height - paddingPoints * 2))
        let scale = min(available.width / padded.width, available.height / padded.height)

        // Centre the fitted content in the leftover space.
        let dx = (size.width - padded.width * scale) / 2 - padded.minX * scale
        let dy = (size.height - padded.height * scale) / 2 - padded.minY * scale
        return CGAffineTransform(translationX: dx, y: dy).scaledBy(x: scale, y: scale)
    }

    // MARK: - Hit testing

    /// The prefecture actually under the finger, or nil for open sea.
    static func directHit(
        at point: CGPoint,
        among prefectures: [Prefecture],
        transform: CGAffineTransform
    ) -> Prefecture? {
        for prefecture in prefectures {
            // bbox first: cheap reject before the crossing test
            guard bbox(of: prefecture, transform: transform).contains(point) else { continue }
            if contains(point, prefecture: prefecture, transform: transform) {
                return prefecture
            }
        }
        return nil
    }

    static func bbox(of prefecture: Prefecture, transform: CGAffineTransform) -> CGRect {
        prefecture.bbox.applying(transform)
    }

    static func screenCentroid(of prefecture: Prefecture,
                               transform: CGAffineTransform) -> CGPoint {
        prefecture.centroid.applying(transform)
    }

    /// How much slack a near-miss on `target` gets, in screen points.
    ///
    /// The nominal 22pt exists so Kagawa, Osaka and Okinawa stay reachable with
    /// a child's finger. But centroids get close on the all-Japan stage — Tokyo
    /// and Kanagawa are only 17.5 map units apart — so a flat 22pt would happily
    /// accept a tap sitting on top of the neighbour. Clamping to half the
    /// distance to the nearest other candidate keeps the generosity where
    /// there is room for it and withdraws it where there is not.
    static func effectiveTolerance(
        for target: Prefecture,
        among prefectures: [Prefecture],
        transform: CGAffineTransform,
        base: CGFloat = GameRules.tapTolerancePoints
    ) -> CGFloat {
        let centre = screenCentroid(of: target, transform: transform)
        let nearest = prefectures
            .filter { $0.code != target.code }
            .map { distance(centre, screenCentroid(of: $0, transform: transform)) }
            .min()
        guard let nearest else { return base }
        return min(base, nearest / 2)
    }

    /// Spec rule (CLAUDE.md §3): when a tap hits no prefecture at all, still
    /// count it if it lands near the prefecture being asked about.
    static func isNearMiss(
        _ point: CGPoint,
        of target: Prefecture,
        among prefectures: [Prefecture],
        transform: CGAffineTransform,
        base: CGFloat = GameRules.tapTolerancePoints
    ) -> Bool {
        let tolerance = effectiveTolerance(for: target, among: prefectures,
                                           transform: transform, base: base)
        guard tolerance > 0 else { return false }
        let centre = screenCentroid(of: target, transform: transform)
        if distance(point, centre) <= tolerance { return true }
        // Long, thin prefectures put their centroid far from the tapped end, so
        // also accept a tap just outside the outline itself.
        let grown = bbox(of: target, transform: transform).insetBy(dx: -tolerance, dy: -tolerance)
        return grown.contains(point)
            && contains(nudge(point, toward: centre, by: tolerance),
                        prefecture: target, transform: transform)
    }

    /// Resolves a tap to a prefecture: direct hit first, then the near-miss
    /// allowance for the prefecture being asked about.
    static func resolveTap(
        at point: CGPoint,
        target: Prefecture,
        among prefectures: [Prefecture],
        transform: CGAffineTransform,
        base: CGFloat = GameRules.tapTolerancePoints
    ) -> Prefecture? {
        if let hit = directHit(at: point, among: prefectures, transform: transform) {
            return hit
        }
        if isNearMiss(point, of: target, among: prefectures,
                      transform: transform, base: base) {
            return target
        }
        return nil
    }

    // MARK: - Small helpers

    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        (a - b).length
    }

    private static func nudge(_ point: CGPoint, toward target: CGPoint,
                              by amount: CGFloat) -> CGPoint {
        let delta = target - point
        let length = delta.length
        guard length > 0 else { return point }
        let step = min(amount, length)
        return CGPoint(x: point.x + delta.x / length * step,
                       y: point.y + delta.y / length * step)
    }
}

nonisolated private extension CGPoint {
    static func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }
    var length: CGFloat { (x * x + y * y).squareRoot() }
}
