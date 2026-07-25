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

    /// Magnification and the point it is happening around, updated together
    /// because the offset correction needs both.
    private struct Pinch: Equatable {
        var magnification: CGFloat = 1
        var anchor: UnitPoint = .center
    }

    @State private var size: CGSize = .zero
    @GestureState private var pinch = Pinch()
    @GestureState private var drag: CGSize = .zero

    private var liveScale: CGFloat { ZoomPan.clamp(scale: scale * pinch.magnification) }

    private var liveOffset: CGSize {
        let anchored = ZoomPan.offset(offset, keeping: pinch.anchor, in: size,
                                      from: scale, to: liveScale)
        return ZoomPan.clamp(
            offset: CGSize(width: anchored.width + drag.width,
                           height: anchored.height + drag.height),
            scale: liveScale, in: size)
    }

    func body(content: Content) -> some View {
        content
            .scaleEffect(liveScale)
            .offset(liveOffset)
            // Simultaneous so a pinch and a drag can run together: fingers
            // rarely zoom without also sliding, and making them take turns is
            // what reads as the map sticking.
            .simultaneousGesture(magnify)
            .simultaneousGesture(ZoomPan.isZoomed(scale) ? pan : nil)
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
}

extension View {
    func zoomPan(scale: Binding<CGFloat>, offset: Binding<CGSize>) -> some View {
        modifier(ZoomPanModifier(scale: scale, offset: offset))
    }
}
