import SwiftUI

/// Pinch-to-zoom maths, kept as pure functions so the edges are testable.
///
/// The clamping matters more here than the gesture does: a child who pinches
/// the map into a corner and cannot find it again has lost the screen, and at
/// five years old the recovery move is to put the iPad down.
nonisolated enum ZoomPan {
    /// 1 is the whole country. Below that the map would shrink away inside its
    /// own frame; above 4 the shapes are bigger than the detail behind them.
    static let minScale: CGFloat = 1
    static let maxScale: CGFloat = 4

    static func clamp(scale: CGFloat) -> CGFloat {
        min(max(scale, minScale), maxScale)
    }

    /// Keeps the zoomed map covering its frame, so no pan can expose a blank
    /// edge or push the country out of sight.
    static func clamp(offset: CGSize, scale: CGFloat, in size: CGSize) -> CGSize {
        guard scale > minScale else { return .zero }
        let limitX = size.width * (scale - 1) / 2
        let limitY = size.height * (scale - 1) / 2
        return CGSize(width: min(max(offset.width, -limitX), limitX),
                      height: min(max(offset.height, -limitY), limitY))
    }

    static func isZoomed(_ scale: CGFloat) -> Bool { scale > minScale + 0.01 }

    /// How long a finger sits still before a slide means zoom rather than pan.
    ///
    /// A hold, not a double tap. The map answers the quiz on a tap, and a
    /// double tap would either submit its first tap as an answer or make every
    /// answer wait to see whether a second tap was coming — a wrong answer for
    /// trying to zoom, or a lag on all 47 (CLAUDE.md §12). A hold is
    /// distinguishable from a tap without either.
    static let liftHold: TimeInterval = 0.3

    /// How far the finger travels to double the map, in points.
    ///
    /// The whole 1×–4× range then fits in about 280pt — half a phone screen —
    /// so a child can reach full zoom without lifting off and starting again.
    static let liftDoubling: CGFloat = 140

    /// The scale after sliding `dy` points from where the finger pressed,
    /// positive upward.
    ///
    /// Exponential, so the same movement doubles the map wherever it starts. A
    /// linear ramp crawls near 1× and lurches near 4×, which reads as the map
    /// fighting the finger.
    static func scale(_ scale: CGFloat, liftedBy dy: CGFloat) -> CGFloat {
        clamp(scale: scale * pow(2, dy / liftDoubling))
    }

    /// The offset that holds `anchor` still while the scale changes.
    ///
    /// Without this the map zooms about the centre of its frame, so pinching
    /// on Kyushu walks Kyushu off the screen and the child chases the place
    /// they were trying to look at. Scaling about the point between the two
    /// fingers is what makes the gesture feel attached to them.
    ///
    /// Derivation: a point `p` is drawn at `C + (p - C) * scale + offset`, so
    /// holding the anchor's drawn position fixed across a scale change gives
    /// `offset' = offset + (A - C) * (old - new)`.
    static func offset(_ offset: CGSize,
                       keeping anchor: UnitPoint,
                       in size: CGSize,
                       from old: CGFloat,
                       to new: CGFloat) -> CGSize {
        let deltaX = (anchor.x - 0.5) * size.width * (old - new)
        let deltaY = (anchor.y - 0.5) * size.height * (old - new)
        return CGSize(width: offset.width + deltaX, height: offset.height + deltaY)
    }
}

/// Makes its content pinchable and, once pinched, draggable.
///
/// The drag is attached only while zoomed in. At rest the map sits in a
/// vertical ScrollView, and a drag gesture that is always live would eat the
/// scroll — the screen would stop scrolling for no visible reason. The caller
/// is expected to disable that ScrollView while `scale` is above 1, which is
/// the other half of the same trade.
struct ZoomPanModifier: ViewModifier {
    @Binding var scale: CGFloat
    @Binding var offset: CGSize
    /// Hold, then slide up to grow the map and down to shrink it — zooming with
    /// one hand, for a child who cannot yet pinch reliably.
    ///
    /// Off by default because a plain drag already means something elsewhere:
    /// the enlarged card turns under one, and a hold-then-turn has to stay a
    /// turn.
    var oneFingerZoom = false

    /// Magnification and the point it is happening around, updated together
    /// because the offset correction needs both.
    private struct Pinch: Equatable {
        var magnification: CGFloat = 1
        var anchor: UnitPoint = .center
    }

    /// A one-finger zoom in flight.
    private struct Lift: Equatable {
        var isActive = false
        /// Points travelled since the press, positive upward.
        var travel: CGFloat = 0
        var anchor: UnitPoint = .center
    }

    @State private var size: CGSize = .zero
    @GestureState private var pinch = Pinch()
    @GestureState private var drag: CGSize = .zero
    @GestureState private var lift = Lift()

    private var liveScale: CGFloat {
        let pinched = ZoomPan.clamp(scale: scale * pinch.magnification)
        guard lift.isActive else { return pinched }
        return ZoomPan.scale(pinched, liftedBy: lift.travel)
    }

    private var liveOffset: CGSize {
        let anchored = ZoomPan.offset(offset, keeping: lift.isActive ? lift.anchor : pinch.anchor,
                                      in: size, from: scale, to: liveScale)
        // The pan translation is dropped while holding: one finger is driving
        // both, and adding them would slide the map sideways as it grows.
        let panned = lift.isActive
            ? anchored
            : CGSize(width: anchored.width + drag.width,
                     height: anchored.height + drag.height)
        return ZoomPan.clamp(offset: panned, scale: liveScale, in: size)
    }

    func body(content: Content) -> some View {
        content
            .scaleEffect(liveScale)
            .offset(liveOffset)
            // Simultaneous so a pinch and a drag can run together: fingers
            // rarely zoom without also sliding, and making them take turns is
            // what reads as the map sticking.
            .simultaneousGesture(magnify)
            .simultaneousGesture(oneFinger)
            .background {
                GeometryReader { geo in
                    Color.clear
                        .onAppear { size = geo.size }
                        .onChange(of: geo.size) { _, new in size = new }
                }
            }
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .updating($pinch) { value, state, _ in
                state = Pinch(magnification: value.magnification, anchor: value.startAnchor)
            }
            .onEnded { value in
                let ended = ZoomPan.clamp(scale: scale * value.magnification)
                let anchored = ZoomPan.offset(offset, keeping: value.startAnchor, in: size,
                                              from: scale, to: ended)
                scale = ended
                // Re-clamp on release: zooming back out can leave an offset
                // that was legal at the larger scale and is not any more.
                offset = ZoomPan.clamp(offset: anchored, scale: ended, in: size)
            }
    }

    private var pan: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($drag) { value, state, _ in state = value.translation }
            .onEnded { value in
                offset = ZoomPan.clamp(
                    offset: CGSize(width: offset.width + value.translation.width,
                                   height: offset.height + value.translation.height),
                    scale: scale, in: size)
            }
    }

    /// Whatever one finger is allowed to do here.
    ///
    /// The hold takes precedence over the pan rather than running alongside it:
    /// a zero-distance drag recognises the instant the finger moves and would
    /// always win the race, so `exclusively` is what gives the hold its 0.3s.
    /// Move straight away and you pan; wait first and you zoom.
    ///
    /// Nothing at all at rest, which is load-bearing: the maps sit in vertical
    /// ScrollViews, and a live zero-distance drag there eats the scroll. The
    /// hold is safe on its own — a scroll starts by moving immediately, so the
    /// press never completes and the ScrollView keeps the gesture.
    private var oneFinger: AnyGesture<Void>? {
        switch (oneFingerZoom, ZoomPan.isZoomed(scale)) {
        case (true, true): AnyGesture(holdZoom.exclusively(before: pan).map { _ in () })
        case (true, false): AnyGesture(holdZoom.map { _ in () })
        case (false, true): AnyGesture(pan.map { _ in () })
        case (false, false): nil
        }
    }

    private var holdZoom: some Gesture {
        LongPressGesture(minimumDuration: ZoomPan.liftHold, maximumDistance: 10)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .updating($lift) { value, state, _ in
                guard case .second(true, let slide) = value else { return }
                guard let slide else {
                    // Held, not yet moved. Marked active so the pan stays out
                    // of the way from the moment the hold lands.
                    state = Lift(isActive: true)
                    return
                }
                state = Lift(isActive: true,
                             travel: -slide.translation.height,
                             anchor: unitPoint(slide.startLocation))
            }
            .onEnded { value in
                guard case .second(true, let slide?) = value else { return }
                let ended = ZoomPan.scale(scale, liftedBy: -slide.translation.height)
                let anchored = ZoomPan.offset(offset, keeping: unitPoint(slide.startLocation),
                                              in: size, from: scale, to: ended)
                scale = ended
                offset = ZoomPan.clamp(offset: anchored, scale: ended, in: size)
            }
    }

    /// Where the finger pressed, as a fraction of the frame — the form
    /// `ZoomPan.offset(_:keeping:in:from:to:)` anchors on, so the map grows
    /// around the spot being looked at instead of around its own middle.
    private func unitPoint(_ point: CGPoint) -> UnitPoint {
        guard size.width > 0, size.height > 0 else { return .center }
        return UnitPoint(x: point.x / size.width, y: point.y / size.height)
    }
}

extension View {
    func zoomPan(scale: Binding<CGFloat>, offset: Binding<CGSize>,
                 oneFingerZoom: Bool = false) -> some View {
        modifier(ZoomPanModifier(scale: scale, offset: offset,
                                 oneFingerZoom: oneFingerZoom))
    }
}
