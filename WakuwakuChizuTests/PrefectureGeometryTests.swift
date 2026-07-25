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

    // MARK: - Near-miss tolerance

    @Test func aNearMissOnTheAskedPrefectureCounts() throws {
        let prefs = stagePrefectures(4)   // Chugoku/Shikoku, includes tiny Kagawa
        let t = PrefectureGeometry.fitTransform(
            bounds: PrefectureGeometry.boundingBox(of: prefs),
            into: CGSize(width: 390, height: 600))
        let kagawa = try #require(map[37])
        let centre = PrefectureGeometry.screenCentroid(of: kagawa, transform: t)
        let tolerance = PrefectureGeometry.effectiveTolerance(for: kagawa, among: prefs,
                                                              transform: t)
        // Just inside the allowance, in a direction that leaves the shape.
        let near = CGPoint(x: centre.x, y: centre.y - tolerance * 0.9)
        #expect(PrefectureGeometry.isNearMiss(near, of: kagawa, among: prefs, transform: t))
    }

    @Test func aFarMissDoesNotCount() throws {
        let prefs = stagePrefectures(4)
        let t = PrefectureGeometry.fitTransform(
            bounds: PrefectureGeometry.boundingBox(of: prefs),
            into: CGSize(width: 390, height: 600))
        let kagawa = try #require(map[37])
        let centre = PrefectureGeometry.screenCentroid(of: kagawa, transform: t)
        let far = CGPoint(x: centre.x + 200, y: centre.y + 200)
        #expect(!PrefectureGeometry.isNearMiss(far, of: kagawa, among: prefs, transform: t))
    }

    /// The reason the tolerance is clamped rather than a flat 22pt: on the
    /// all-Japan stage Tokyo and Kanagawa sit 17.5 map units apart, so a fixed
    /// allowance would hand Tokyo a tap that is sitting on Kanagawa.
    @Test func toleranceShrinksWhereNeighboursAreTight() throws {
        let prefs = stagePrefectures(6)
        let t = PrefectureGeometry.fitTransform(
            bounds: PrefectureGeometry.boundingBox(of: prefs),
            into: CGSize(width: 390, height: 600))
        let tokyo = try #require(map[13])
        let tolerance = PrefectureGeometry.effectiveTolerance(for: tokyo, among: prefs,
                                                              transform: t)
        #expect(tolerance < GameRules.tapTolerancePoints,
                "crowded Kanto should not get the full allowance")
        #expect(tolerance > 0)
    }

    @Test func toleranceNeverReachesAcrossToANeighboursCentroid() {
        let size = CGSize(width: 390, height: 600)
        for stage in Stage.all {
            let prefs = map.prefectures(in: stage.codes)
            let t = PrefectureGeometry.fitTransform(
                bounds: PrefectureGeometry.boundingBox(of: prefs), into: size)
            for pref in prefs {
                let tolerance = PrefectureGeometry.effectiveTolerance(for: pref, among: prefs,
                                                                      transform: t)
                for other in prefs where other.code != pref.code {
                    let d = PrefectureGeometry.distance(
                        PrefectureGeometry.screenCentroid(of: pref, transform: t),
                        PrefectureGeometry.screenCentroid(of: other, transform: t))
                    #expect(tolerance <= d / 2 + 1e-9,
                            "\(stage.name): \(pref.name) tolerance \(tolerance) reaches \(other.name) at \(d)")
                }
            }
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
