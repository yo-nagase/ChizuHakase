import CoreGraphics
import Foundation
import SwiftUI
import Testing

@testable import WakuwakuChizu

/// CLAUDE.md §3: fitting and tap resolution.
@MainActor
struct PrefectureGeometryTests {

    private var map: MapData { MapDataTests.map }

    private func stagePrefectures(_ index: Int) -> [Prefecture] {
        map.prefectures(in: Stage.all[index].codes)
    }

    // MARK: - Fitting

    @Test func fitKeepsAspectRatioRatherThanStretching() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 50)
        let t = PrefectureGeometry.fitTransform(bounds: bounds,
                                                into: CGSize(width: 400, height: 400))
        #expect(abs(t.a - t.d) < 1e-9, "x and y scale must match; \(t.a) vs \(t.d)")
    }

    @Test func fittedContentStaysInsideTheCanvas() {
        let size = CGSize(width: 390, height: 600)
        for stage in Stage.all {
            let prefs = map.prefectures(in: stage.codes)
            let t = PrefectureGeometry.fitTransform(
                bounds: PrefectureGeometry.boundingBox(of: prefs), into: size)
            for pref in prefs {
                let box = PrefectureGeometry.bbox(of: pref, transform: t)
                #expect(box.minX >= -0.5 && box.maxX <= size.width + 0.5,
                        "\(stage.name)/\(pref.name) overflows horizontally: \(box)")
                #expect(box.minY >= -0.5 && box.maxY <= size.height + 0.5,
                        "\(stage.name)/\(pref.name) overflows vertically: \(box)")
            }
        }
    }

    /// A stage covering fewer prefectures must zoom in, otherwise small
    /// prefectures stay unhittable on the regional stages.
    @Test func regionalStagesZoomInMoreThanTheAllJapanStage() {
        let size = CGSize(width: 390, height: 600)
        func scale(_ stageIndex: Int) -> CGFloat {
            PrefectureGeometry.fitTransform(
                bounds: PrefectureGeometry.boundingBox(of: stagePrefectures(stageIndex)),
                into: size).a
        }
        #expect(scale(1) > scale(6), "Kanto should be drawn larger than all-Japan")
        #expect(scale(3) > scale(6), "Kinki should be drawn larger than all-Japan")
    }

    @Test func degenerateInputsFallBackToIdentityInsteadOfNaN() {
        let t = PrefectureGeometry.fitTransform(bounds: .zero,
                                                into: CGSize(width: 100, height: 100))
        #expect(t == .identity)
        let t2 = PrefectureGeometry.fitTransform(bounds: CGRect(x: 0, y: 0, width: 10, height: 10),
                                                 into: .zero)
        #expect(t2 == .identity)
    }

    // MARK: - Direct hits

    @Test func tappingACentroidSelectsThatPrefecture() {
        let size = CGSize(width: 390, height: 600)
        for stage in Stage.all {
            let prefs = map.prefectures(in: stage.codes)
            let t = PrefectureGeometry.fitTransform(
                bounds: PrefectureGeometry.boundingBox(of: prefs), into: size)
            for pref in prefs {
                let point = PrefectureGeometry.screenCentroid(of: pref, transform: t)
                let hit = PrefectureGeometry.directHit(at: point, among: prefs, transform: t)
                #expect(hit?.code == pref.code,
                        "\(stage.name): tapping \(pref.name)'s centroid hit \(hit?.name ?? "sea")")
            }
        }
    }

    @Test func tappingOpenSeaHitsNothing() {
        let prefs = stagePrefectures(1)
        let t = PrefectureGeometry.fitTransform(
            bounds: PrefectureGeometry.boundingBox(of: prefs),
            into: CGSize(width: 390, height: 600))
        // Top-left corner is padding, never land.
        #expect(PrefectureGeometry.directHit(at: CGPoint(x: 1, y: 1),
                                             among: prefs, transform: t) == nil)
    }

    // MARK: - Near-miss resolution

    @Test func aNearMissOnTheAskedPrefectureCounts() throws {
        let prefs = stagePrefectures(4)   // Chugoku/Shikoku, includes tiny Kagawa
        let t = PrefectureGeometry.fitTransform(
            bounds: PrefectureGeometry.boundingBox(of: prefs),
            into: CGSize(width: 390, height: 600))
        let kagawa = try #require(map[37])
        let centre = PrefectureGeometry.screenCentroid(of: kagawa, transform: t)
        // Walk north out of Kagawa into the Inland Sea until we leave the shape.
        var point = centre
        while PrefectureGeometry.distanceToOutline(point, of: kagawa, transform: t) == 0 {
            point.y -= 1
        }
        point.y -= 4   // a few points out to sea

        let resolved = PrefectureGeometry.resolveTap(at: point, target: kagawa,
                                                     among: prefs, transform: t)
        #expect(resolved?.code == kagawa.code,
                "a tap just off Kagawa should still reach it, got \(resolved?.name ?? "sea")")
    }

    @Test func aFarMissResolvesToNothing() throws {
        let prefs = stagePrefectures(4)
        let t = PrefectureGeometry.fitTransform(
            bounds: PrefectureGeometry.boundingBox(of: prefs),
            into: CGSize(width: 390, height: 600))
        let kagawa = try #require(map[37])
        let centre = PrefectureGeometry.screenCentroid(of: kagawa, transform: t)
        let far = CGPoint(x: centre.x + 400, y: centre.y + 400)
        #expect(PrefectureGeometry.resolveTap(at: far, target: kagawa,
                                              among: prefs, transform: t) == nil)
    }

    // MARK: - Tap allowance while zoomed
    //
    // Taps arrive in the map's own coordinates, so PrefectureMapView divides
    // the allowance by the zoom to keep the slack a constant width on the
    // glass. These pin both halves of that: a magnified map must still accept
    // a tap on the prefecture, and must stop accepting one from far away.

    @Test func everyPrefectureIsStillReachableAtTheTightestAllowance() throws {
        let prefs = stagePrefectures(6)
        let t = PrefectureGeometry.fitTransform(
            bounds: PrefectureGeometry.boundingBox(of: prefs),
            into: CGSize(width: 358, height: 500))
        let zoomed = GameRules.tapTolerancePoints / ZoomPan.maxScale
        for pref in prefs {
            let point = PrefectureGeometry.screenCentroid(of: pref, transform: t)
            let resolved = PrefectureGeometry.resolveTap(
                at: point, target: pref, among: prefs, transform: t,
                tolerance: zoomed, targetBias: GameRules.tapTargetBiasPoints / ZoomPan.maxScale)
            #expect(resolved?.code == pref.code,
                    "\(pref.name) unreachable at 4x: got \(resolved?.name ?? "sea")")
        }
    }

    /// The reason the allowance shrinks at all. At 4x an unscaled 22-unit slack
    /// would be 88pt on the glass, so a tap the width of a hand away from
    /// Kagawa would still be scored as Kagawa.
    @Test func aMissThatWouldCountUnzoomedIsRejectedWhenMagnified() throws {
        let prefs = stagePrefectures(4)
        let t = PrefectureGeometry.fitTransform(
            bounds: PrefectureGeometry.boundingBox(of: prefs),
            into: CGSize(width: 390, height: 600))
        let kagawa = try #require(map[37])
        var point = PrefectureGeometry.screenCentroid(of: kagawa, transform: t)
        while PrefectureGeometry.distanceToOutline(point, of: kagawa, transform: t) == 0 {
            point.y -= 1
        }
        point.y -= 12   // well outside, but inside the resting allowance

        #expect(PrefectureGeometry.resolveTap(at: point, target: kagawa,
                                              among: prefs, transform: t)?.code == kagawa.code,
                "this miss is meant to be forgiven at rest")
        #expect(PrefectureGeometry.resolveTap(
            at: point, target: kagawa, among: prefs, transform: t,
            tolerance: GameRules.tapTolerancePoints / 4,
            targetBias: GameRules.tapTargetBiasPoints / 4)?.code != kagawa.code,
                "the same miss is a whole thumb away once the map is at 4x")
    }

    @Test func distanceToOutlineIsZeroInsideAndGrowsOutside() throws {
        let prefs = stagePrefectures(1)
        let t = PrefectureGeometry.fitTransform(
            bounds: PrefectureGeometry.boundingBox(of: prefs),
            into: CGSize(width: 390, height: 600))
        for pref in prefs {
            let centre = PrefectureGeometry.screenCentroid(of: pref, transform: t)
            #expect(PrefectureGeometry.distanceToOutline(centre, of: pref, transform: t) == 0,
                    "\(pref.name) centroid should read as inside")
            let far = CGPoint(x: centre.x + 1000, y: centre.y)
            #expect(PrefectureGeometry.distanceToOutline(far, of: pref, transform: t) > 100)
        }
    }

    /// The reason resolution is nearest-outline rather than a radius around the
    /// asked prefecture's centroid: on the all-Japan stage Kagawa is ~6pt across
    /// and Tokyo/Kanagawa sit a few points apart, so any radius wide enough for
    /// Kagawa would also swallow its neighbours.
    @Test func everyPrefectureIsReachableEvenOnTheAllJapanStage() {
        let prefs = stagePrefectures(6)
        let t = PrefectureGeometry.fitTransform(
            bounds: PrefectureGeometry.boundingBox(of: prefs),
            into: CGSize(width: 358, height: 500))
        for pref in prefs {
            let point = PrefectureGeometry.screenCentroid(of: pref, transform: t)
            let resolved = PrefectureGeometry.resolveTap(at: point, target: pref,
                                                         among: prefs, transform: t)
            #expect(resolved?.code == pref.code,
                    "\(pref.name) unreachable on the all-Japan stage: got \(resolved?.name ?? "sea")")
        }
    }

    /// A tap that lands squarely on the wrong prefecture stays wrong — the
    /// allowance is for misses, not for redirecting real hits.
    @Test func aDirectHitOnTheWrongPrefectureIsNotRescued() throws {
        let prefs = stagePrefectures(1)
        let t = PrefectureGeometry.fitTransform(
            bounds: PrefectureGeometry.boundingBox(of: prefs),
            into: CGSize(width: 390, height: 600))
        let tokyo = try #require(map[13])
        let chiba = try #require(map[12])
        let onChiba = PrefectureGeometry.screenCentroid(of: chiba, transform: t)

        let resolved = PrefectureGeometry.resolveTap(at: onChiba, target: tokyo,
                                                     among: prefs, transform: t)
        #expect(resolved?.code == chiba.code)
    }

    /// The target bias may break a tie, but must not overturn a tap that is
    /// clearly nearer a neighbour.
    @Test func targetBiasCannotOverturnAClearlyCloserNeighbour() throws {
        let prefs = stagePrefectures(1)
        let t = PrefectureGeometry.fitTransform(
            bounds: PrefectureGeometry.boundingBox(of: prefs),
            into: CGSize(width: 390, height: 600))
        let tokyo = try #require(map[13])
        let chiba = try #require(map[12])
        let centre = PrefectureGeometry.screenCentroid(of: chiba, transform: t)

        // Just outside Chiba, still far from Tokyo.
        var point = centre
        while PrefectureGeometry.distanceToOutline(point, of: chiba, transform: t) == 0 {
            point.x += 1
        }
        point.x += 3
        let toChiba = PrefectureGeometry.distanceToOutline(point, of: chiba, transform: t)
        let toTokyo = PrefectureGeometry.distanceToOutline(point, of: tokyo, transform: t)
        try #require(toTokyo > toChiba + GameRules.tapTargetBiasPoints)

        let resolved = PrefectureGeometry.resolveTap(at: point, target: tokyo,
                                                     among: prefs, transform: t)
        #expect(resolved?.code == chiba.code)
    }

    @Test func resolveTapPrefersTheDirectHit() {
        let prefs = stagePrefectures(0)
        let t = PrefectureGeometry.fitTransform(
            bounds: PrefectureGeometry.boundingBox(of: prefs),
            into: CGSize(width: 390, height: 600))
        for pref in prefs {
            let point = PrefectureGeometry.screenCentroid(of: pref, transform: t)
            let resolved = PrefectureGeometry.resolveTap(at: point, target: pref,
                                                         among: prefs, transform: t)
            #expect(resolved?.code == pref.code)
        }
    }

    @Test func aTapInOpenSeaFarFromLandResolvesToNothing() {
        let prefs = stagePrefectures(1)
        let t = PrefectureGeometry.fitTransform(
            bounds: PrefectureGeometry.boundingBox(of: prefs),
            into: CGSize(width: 390, height: 600))
        #expect(PrefectureGeometry.resolveTap(at: CGPoint(x: 1, y: 1), target: nil,
                                              among: prefs, transform: t) == nil)
    }

    // MARK: - Paths

    @Test func pathAndCGPathDescribeTheSameGeometry() {
        let t = CGAffineTransform(scaleX: 0.4, y: 0.4)
        for pref in map.prefectures {
            let swiftUI = PrefectureGeometry.path(for: pref, transform: t)
            let core = PrefectureGeometry.cgPath(rings: pref.rings, transform: t)
            #expect(swiftUI.boundingRect.equalTo(core.boundingBox)
                    || abs(swiftUI.boundingRect.width - core.boundingBox.width) < 0.01,
                    "\(pref.name) bounds differ: \(swiftUI.boundingRect) vs \(core.boundingBox)")
        }
    }
}
