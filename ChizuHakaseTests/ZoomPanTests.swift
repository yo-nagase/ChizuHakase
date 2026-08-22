import CoreGraphics
import SwiftUI
import Testing

@testable import ChizuHakase

/// Pinch-to-zoom limits on the my-map screen.
///
/// These are the states a child can actually get stuck in, so they are pinned
/// rather than trusted to the gesture: a map pinched away to nothing, or
/// dragged off the edge with no way back, ends the screen for someone who
/// cannot reason about what they just did.
struct ZoomPanTests {

    private let frame = CGSize(width: 300, height: 400)

    // MARK: - Scale

    @Test func scaleNeverGoesBelowWholeCountry() {
        #expect(ZoomPan.clamp(scale: 0.2) == 1)
        #expect(ZoomPan.clamp(scale: 0) == 1)
        #expect(ZoomPan.clamp(scale: -3) == 1)
    }

    @Test func scaleIsCappedAtTheTop() {
        #expect(ZoomPan.clamp(scale: 50) == ZoomPan.maxScale)
        #expect(ZoomPan.clamp(scale: .infinity) == ZoomPan.maxScale)
    }

    @Test(arguments: [1.0, 1.5, 2.0, 3.9, 4.0])
    func scalesInRangePassThrough(scale: CGFloat) {
        #expect(ZoomPan.clamp(scale: scale) == scale)
    }

    // MARK: - Offset

    /// At rest there is nothing to pan, so any stray translation collapses.
    @Test func offsetIsZeroWhenNotZoomed() {
        let dragged = CGSize(width: 120, height: -90)
        #expect(ZoomPan.clamp(offset: dragged, scale: 1, in: frame) == .zero)
        #expect(ZoomPan.clamp(offset: dragged, scale: 0.5, in: frame) == .zero)
    }

    /// The frame stays covered: half the overhang is the furthest a pan can go
    /// before a blank edge would show.
    @Test func offsetStopsWhereTheEdgeWouldShow() {
        let clamped = ZoomPan.clamp(offset: CGSize(width: 9_999, height: 9_999),
                                    scale: 2, in: frame)
        #expect(clamped.width == frame.width / 2)
        #expect(clamped.height == frame.height / 2)
    }

    @Test func offsetClampsInBothDirections() {
        let clamped = ZoomPan.clamp(offset: CGSize(width: -9_999, height: -9_999),
                                    scale: 3, in: frame)
        #expect(clamped.width == -frame.width)
        #expect(clamped.height == -frame.height)
    }

    @Test func offsetInsideTheLimitIsUntouched() {
        let small = CGSize(width: 10, height: -20)
        #expect(ZoomPan.clamp(offset: small, scale: 2, in: frame) == small)
    }

    /// Zooming back out has to pull the map home. An offset that was legal at
    /// 4x is off the screen at 1.2x, and without this the country drifts away
    /// as the child unpinches.
    @Test func zoomingOutPullsAPannedMapBack() {
        let far = ZoomPan.clamp(offset: CGSize(width: 9_999, height: 0),
                                scale: 4, in: frame)
        let afterZoomOut = ZoomPan.clamp(offset: far, scale: 1.2, in: frame)
        #expect(afterZoomOut.width < far.width)
        #expect(abs(afterZoomOut.width - frame.width * 0.1) < 0.001)
    }

    @Test func returningToOneRecentresCompletely() {
        let far = ZoomPan.clamp(offset: CGSize(width: 500, height: 500),
                                scale: 4, in: frame)
        #expect(ZoomPan.clamp(offset: far, scale: 1, in: frame) == .zero)
    }

    // MARK: - Anchoring

    /// Pinching about the centre is the case where nothing should move.
    @Test func centreAnchoredZoomLeavesTheOffsetAlone() {
        let held = ZoomPan.offset(.zero, keeping: .center, in: frame, from: 1, to: 3)
        #expect(held == .zero)
    }

    /// Zooming in on the top-left has to push the content down and right, or
    /// the point under the fingers slides away toward the centre.
    @Test func zoomingOnACornerPushesTheContentTowardIt() {
        let held = ZoomPan.offset(.zero, keeping: .topLeading, in: frame, from: 1, to: 2)
        #expect(held.width > 0)
        #expect(held.height > 0)
        #expect(held.width == frame.width / 2)
        #expect(held.height == frame.height / 2)
    }

    @Test func zoomingOnTheOppositeCornerPushesTheOtherWay() {
        let held = ZoomPan.offset(.zero, keeping: .bottomTrailing, in: frame, from: 1, to: 2)
        #expect(held.width == -frame.width / 2)
        #expect(held.height == -frame.height / 2)
    }

    /// Zooming out about a point undoes zooming in about it, or a pinch in and
    /// back out would leave the map somewhere the child did not put it.
    @Test func anchoredZoomIsReversible() {
        let anchor = UnitPoint(x: 0.2, y: 0.8)
        let zoomedIn = ZoomPan.offset(.zero, keeping: anchor, in: frame, from: 1, to: 3)
        let backOut = ZoomPan.offset(zoomedIn, keeping: anchor, in: frame, from: 3, to: 1)
        #expect(abs(backOut.width) < 0.001)
        #expect(abs(backOut.height) < 0.001)
    }

    @Test func anchoringAddsToAnExistingOffset() {
        let start = CGSize(width: 40, height: -10)
        let held = ZoomPan.offset(start, keeping: .center, in: frame, from: 1, to: 2)
        #expect(held == start)
    }

    // MARK: - Zoomed state

    /// Drives whether the reset button shows and whether panning is live, so a
    /// rounding wobble at rest must not read as zoomed.
    @Test func restingScaleDoesNotCountAsZoomed() {
        #expect(!ZoomPan.isZoomed(1))
        #expect(!ZoomPan.isZoomed(1.001))
        #expect(ZoomPan.isZoomed(1.5))
        #expect(ZoomPan.isZoomed(ZoomPan.maxScale))
    }

    /// A degenerate frame must not produce NaN offsets before layout settles.
    @Test func zeroSizedFrameIsHarmless() {
        let clamped = ZoomPan.clamp(offset: CGSize(width: 50, height: 50),
                                    scale: 2, in: .zero)
        #expect(clamped == .zero)
    }

    // MARK: - Visibility

    /// At rest every point of the panel is its own screen point, so nothing
    /// legitimate is dropped.
    @Test func atRestTheWholePanelIsVisible() {
        #expect(ZoomPan.isVisible(.zero, scale: 1, offset: .zero, in: frame))
        #expect(ZoomPan.isVisible(CGPoint(x: 300, y: 400), scale: 1, offset: .zero, in: frame))
        #expect(!ZoomPan.isVisible(CGPoint(x: -1, y: 0), scale: 1, offset: .zero, in: frame))
        #expect(!ZoomPan.isVisible(CGPoint(x: 0, y: 401), scale: 1, offset: .zero, in: frame))
    }

    /// Zoomed about the centre, the middle stays on the glass and the corners
    /// scale off it — the region the clip hides but the touch geometry keeps,
    /// which is how a zoomed map used to swallow the back button.
    @Test func zoomingPushesTheCornersOffTheGlass() {
        #expect(ZoomPan.isVisible(CGPoint(x: 150, y: 200), scale: 4, offset: .zero, in: frame))
        #expect(!ZoomPan.isVisible(CGPoint(x: 10, y: 10), scale: 4, offset: .zero, in: frame))
    }

    /// Panning toward a hidden corner brings its taps back with its pixels —
    /// visibility has to follow the same mapping the drawing uses.
    @Test func panningBringsAHiddenCornerBack() {
        let corner = CGPoint(x: 10, y: 10)
        #expect(!ZoomPan.isVisible(corner, scale: 2, offset: .zero, in: frame))
        let toCorner = ZoomPan.clamp(offset: CGSize(width: 9_999, height: 9_999),
                                     scale: 2, in: frame)
        #expect(ZoomPan.isVisible(corner, scale: 2, offset: toCorner, in: frame))
    }

    /// Before layout settles the frame is zero; treating that as "nothing is
    /// visible" would swallow every tap, which is the worse failure.
    @Test func zeroSizedFrameKeepsTapsAlive() {
        #expect(ZoomPan.isVisible(CGPoint(x: 50, y: 50), scale: 1, offset: .zero, in: .zero))
    }

    // MARK: - Region framing

    /// The whole promise of the 「にしにほん」「ひがしにほん」 buttons: one press
    /// puts the half being asked about in the middle of the frame.
    @Test func framingCentresTheRegion() {
        let region = CGRect(x: 30, y: 40, width: 100, height: 100)
        let (scale, offset) = ZoomPan.framing(region, in: frame, margin: 0)
        // A point p is drawn at C + (p - C) * scale + offset.
        let drawnX = frame.width / 2 + (region.midX - frame.width / 2) * scale
            + offset.width
        let drawnY = frame.height / 2 + (region.midY - frame.height / 2) * scale
            + offset.height
        #expect(abs(drawnX - frame.width / 2) < 0.001)
        #expect(abs(drawnY - frame.height / 2) < 0.001)
    }

    /// The tighter axis decides, exactly like the map's own aspect fit — a
    /// region must never be stretched or overflow the frame.
    @Test func framingFillsTheFrameAlongTheTightAxis() {
        let region = CGRect(x: 50, y: 50, width: 150, height: 100)
        let (scale, _) = ZoomPan.framing(region, in: frame, margin: 0)
        #expect(abs(scale - 2) < 0.001)   // 300/150, not 400/100
    }

    /// Margin is breathing room: it grows the rect being fitted, so the
    /// coastline stops short of the frame's edge.
    @Test func framingMarginLeavesAir() {
        let region = CGRect(x: 100, y: 100, width: 100, height: 100)
        let (scale, _) = ZoomPan.framing(region, in: frame, margin: 0.25)
        #expect(abs(scale - 2) < 0.001)   // fits 150, not 100
    }

    /// A tiny region is not a licence to zoom past the pinch's own ceiling.
    @Test func framingObeysTheScaleCap() {
        let speck = CGRect(x: 140, y: 190, width: 10, height: 10)
        let (scale, _) = ZoomPan.framing(speck, in: frame, margin: 0)
        #expect(scale == ZoomPan.maxScale)
    }

    /// A region hugging a corner wants more offset than the clamp allows; the
    /// button must settle for the closest legal view, never a blank edge.
    @Test func framingNeverUncoversAnEdge() {
        let corner = CGRect(x: 0, y: 0, width: 50, height: 50)
        let (scale, offset) = ZoomPan.framing(corner, in: frame, margin: 0)
        #expect(scale == ZoomPan.maxScale)
        #expect(offset.width == frame.width * (scale - 1) / 2)
        #expect(offset.height == frame.height * (scale - 1) / 2)
    }

    /// Before layout settles the sizes are zero; the button must be inert
    /// rather than produce NaN.
    @Test func framingDegenerateInputsComeBackToRest() {
        let (s1, o1) = ZoomPan.framing(.zero, in: frame)
        #expect(s1 == ZoomPan.minScale)
        #expect(o1 == .zero)
        let (s2, o2) = ZoomPan.framing(CGRect(x: 0, y: 0, width: 10, height: 10),
                                       in: .zero)
        #expect(s2 == ZoomPan.minScale)
        #expect(o2 == .zero)
    }

    // MARK: - Hold and slide

    /// Up grows the map, down shrinks it — the direction a child expects from
    /// pulling something toward them.
    @Test func slidingUpZoomsInAndDownZoomsOut() {
        #expect(ZoomPan.scale(2, liftedBy: 70) > 2)
        #expect(ZoomPan.scale(2, liftedBy: -70) < 2)
        #expect(ZoomPan.scale(2, liftedBy: 0) == 2)
    }

    /// One doubling distance doubles it, wherever it started. The whole point
    /// of the exponent: 1×→2× and 2×→4× have to cost the same movement, or the
    /// map crawls at the bottom of the range and lurches at the top.
    @Test func oneDoublingDistanceDoublesTheMap() {
        #expect(abs(ZoomPan.scale(1, liftedBy: ZoomPan.liftDoubling) - 2) < 0.001)
        #expect(abs(ZoomPan.scale(2, liftedBy: ZoomPan.liftDoubling) - 4) < 0.001)
    }

    /// Sliding back down the same distance lands where it started, so an
    /// abandoned zoom leaves nothing behind.
    @Test func slidingBackReturnsToWhereItStarted() {
        let out = ZoomPan.scale(2, liftedBy: 90)
        #expect(abs(ZoomPan.scale(out, liftedBy: -90) - 2) < 0.001)
    }

    /// The same floor and ceiling as the pinch. A child who keeps sliding must
    /// not be able to push the country out of its own frame.
    @Test func slidingIsHeldToTheSameRangeAsPinching() {
        #expect(ZoomPan.scale(1, liftedBy: -2000) == ZoomPan.minScale)
        #expect(ZoomPan.scale(1, liftedBy: 2000) == ZoomPan.maxScale)
    }

    /// Long enough that answering never trips it, short enough not to read as
    /// the map ignoring the finger.
    @Test func theHoldIsShortButNotTapLength() {
        #expect(ZoomPan.liftHold >= 0.25)
        #expect(ZoomPan.liftHold <= 0.5)
    }

    // MARK: - Per-map ceiling

    /// The world challenge's flat map passes a wider ceiling so its smallest
    /// countries can be pinched up to a regional stage's size; every other map
    /// omits the argument and must keep the shared default.
    @Test func aWiderCeilingLetsThePinchPastTheDefault() {
        #expect(ZoomPan.clamp(scale: 10, max: 17) == 10)
    }

    @Test func theWiderCeilingStillCaps() {
        #expect(ZoomPan.clamp(scale: 50, max: 17) == 17)
        #expect(ZoomPan.clamp(scale: .infinity, max: 17) == 17)
    }

    /// The floor is about never losing the map inside its own frame, not about
    /// detail — no ceiling argument may open it.
    @Test func theFloorIgnoresTheCeiling() {
        #expect(ZoomPan.clamp(scale: 0.2, max: 17) == ZoomPan.minScale)
    }

    /// The hold-and-slide zoom stops where the pinch stops — one finger and
    /// two must share the same per-map ceiling, or the map's limit depends on
    /// which hand the child had free.
    @Test func slidingObeysTheWiderCeiling() {
        #expect(ZoomPan.scale(1, liftedBy: 5_000, max: 17) == 17)
        #expect(ZoomPan.scale(1, liftedBy: 5_000) == ZoomPan.maxScale)
    }

    // MARK: - Per-map floor

    /// A world regional stage passes a floor below 1 (`Stage.flatMinZoom`) so
    /// the same pinch that magnifies the region can also shrink it until the
    /// whole world is in the frame; every other map omits the argument and
    /// keeps the default floor — nothing there may move by a pixel.
    @Test func aLowerFloorLetsThePinchBelowTheFit() {
        #expect(ZoomPan.clamp(scale: 0.3, min: 0.2) == 0.3)
        #expect(ZoomPan.clamp(scale: 0.1, min: 0.2) == 0.2)
        #expect(ZoomPan.clamp(scale: 0.3) == ZoomPan.minScale)
    }

    /// One finger and two share the floor the way they share the ceiling.
    @Test func slidingObeysTheLowerFloor() {
        #expect(abs(ZoomPan.scale(1, liftedBy: -5_000, min: 0.2) - 0.2) < 0.001)
        #expect(ZoomPan.scale(1, liftedBy: -5_000) == ZoomPan.minScale)
    }

    /// Zoomed out is its own state: not zoomed (there is nothing to pan — the
    /// offset clamp keeps the shrunken map centred), but not at rest either
    /// (the reset chip must show the way home).
    @Test func belowTheFitCountsAsZoomedOutNotZoomed() {
        #expect(ZoomPan.isZoomedOut(0.5))
        #expect(!ZoomPan.isZoomed(0.5))
        #expect(!ZoomPan.isZoomedOut(1))
        #expect(!ZoomPan.isZoomedOut(0.999))
        #expect(!ZoomPan.isZoomedOut(2))
    }
}
