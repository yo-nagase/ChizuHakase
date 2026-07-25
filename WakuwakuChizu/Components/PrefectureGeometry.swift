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

    /// Width/height of a stage once padded. Callers hand this to
    /// `.aspectRatio` so the sea panel hugs the map instead of leaving a tall
    /// empty box around it — the fit is uniform either way, this just stops the
    /// letterboxing from being visible.
    static func aspectRatio(of prefectures: [Prefecture]) -> CGFloat {
        let bounds = boundingBox(of: prefectures)
        guard bounds.width > 0, bounds.height > 0 else { return 1 }
        return bounds.width / bounds.height
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

    /// Distance from a point to the nearest edge of a prefecture, 0 if inside.
    ///
    /// Measured against the outline rather than the centroid: a centroid is a
    /// terrible proxy for a long prefecture like Nagano, where one end sits far
    /// from the middle.
    static func distanceToOutline(
        _ point: CGPoint,
        of prefecture: Prefecture,
        transform: CGAffineTransform
    ) -> CGFloat {
        if contains(point, prefecture: prefecture, transform: transform) { return 0 }
        var best = CGFloat.greatestFiniteMagnitude
        for ring in prefecture.rings {
            guard ring.count >= 2 else { continue }
            var previous = ring[0].applying(transform)
            for raw in ring.dropFirst() {
                let current = raw.applying(transform)
                best = min(best, distanceToSegment(point, previous, current))
                previous = current
            }
        }
        return best
    }

    private static func distanceToSegment(_ p: CGPoint,
                                          _ a: CGPoint,
                                          _ b: CGPoint) -> CGFloat {
        let ab = b - a
        let lengthSquared = ab.x * ab.x + ab.y * ab.y
        guard lengthSquared > 0 else { return distance(p, a) }
        var t = ((p.x - a.x) * ab.x + (p.y - a.y) * ab.y) / lengthSquared
        t = min(max(t, 0), 1)
        return distance(p, CGPoint(x: a.x + ab.x * t, y: a.y + ab.y * t))
    }

    /// Resolves a tap to a prefecture (CLAUDE.md §3).
    ///
    /// Direct hit wins. Otherwise the nearest outline within `tolerance` wins,
    /// with the prefecture being asked about credited a `targetBias` head start.
    ///
    /// Nearest-outline rather than a plain radius around the target's centroid,
    /// because a radius cannot work at both ends of the scale: on the all-Japan
    /// stage Kagawa is about 6pt across and Tokyo and Kanagawa sit ~5pt apart,
    /// so any radius wide enough to make Kagawa reachable also hands Tokyo taps
    /// that landed on Kanagawa. Nearest-wins is self-limiting — it cannot
    /// misattribute a tap that is plainly closer to a neighbour — and the bias
    /// still gives the asked prefecture the benefit of the doubt when the child
    /// aimed at the right place and missed by a finger-width.
    static func resolveTap(
        at point: CGPoint,
        target: Prefecture?,
        among prefectures: [Prefecture],
        transform: CGAffineTransform,
        tolerance: CGFloat = GameRules.tapTolerancePoints,
        targetBias: CGFloat = GameRules.tapTargetBiasPoints
    ) -> Prefecture? {
        if let hit = directHit(at: point, among: prefectures, transform: transform) {
            return hit
        }
        var best: (prefecture: Prefecture, score: CGFloat)?
        for prefecture in prefectures {
            let raw = distanceToOutline(point, of: prefecture, transform: transform)
            let score = prefecture.code == target?.code ? raw - targetBias : raw
            guard raw <= tolerance else { continue }
            if best == nil || score < best!.score {
                best = (prefecture, score)
            }
        }
        return best?.prefecture
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
