import SwiftUI

/// One card, held up and turned in the light.
///
/// The book shows its atlas's cards as chips. This is the other half of owning
/// something: one card big enough to look at, that tilts under a finger the way
/// a real one does when you angle it to catch the shine. The face is
/// `CardFaceView` at full density — this file is the backdrop, the gestures and
/// the way the card arrives and leaves.
struct CardDetailView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.textMode) private var mode
    @Environment(\.dismiss) private var dismiss

    let card: SpecialtyCard
    let prefecture: Prefecture?
    let stars: Int
    /// From the save's rainbow latch — see `CardFaceView.rainbow`.
    var rainbow: Bool = false
    /// The prefecture's current streak, for the 「あと◯れんぞく」 line under a
    /// gold card. Zero is a fine default for callers that predate streaks.
    var streak: Int = 0
    /// What reaching silver unlocks, named — the world's flag cards promise
    /// 「オリジナルカード」 instead of the tier (P8). The parent reads it off
    /// its atlas (`Atlas.unlockGoalNoun(for:)`) and this view passes it on
    /// unopened: which book the card came from is never decided here. Nil
    /// keeps the plain 「シルバー」 wording, which is right for every japan
    /// card and fine for callers that predate the unlock line.
    var unlock: AtlasNoun? = nil

    /// Live tilt, in degrees. x is pitch, y is yaw.
    @State private var tilt: CGSize = .zero
    /// Pinch zoom and where the zoomed card has been dragged to, driven by the
    /// same `ZoomPan` the map uses.
    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var appeared = false

    /// Debug builds can start the card already leaning, so the tilted state can
    /// be looked at in a screenshot. A gesture-driven pose is otherwise
    /// impossible to capture without a finger on the glass.
    private static var debugTilt: CGSize? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-tiltCard"),
              index + 1 < arguments.count else { return nil }
        let parts = arguments[index + 1].split(separator: ",").compactMap { Double($0) }
        guard parts.count == 2 else { return nil }
        return CGSize(width: parts[0], height: parts[1])
        #else
        return nil
        #endif
    }

    var body: some View {
        ZStack {
            // Tapping the backdrop closes: a child who does not find the button
            // will try tapping away from the thing, and should be right.
            Color.black.opacity(appeared ? 0.45 : 0)
                .ignoresSafeArea()
                .onTapGesture { close() }

            // The card floats in the space above the button rather than the two
            // sitting together in the middle: 「とじる」 belongs where a thumb
            // already is, and a card being looked at should not have a button
            // parked against its bottom edge.
            VStack(spacing: 0) {
                Spacer(minLength: 8)

                CardFaceView(card: card, prefecture: prefecture,
                             stars: stars, rainbow: rainbow, tilt: tilt)
                    .frame(maxWidth: 300)
                    // Pinch to look closer and drag to choose what you are
                    // looking closer at, on the same terms as the map: the zoom
                    // holds the point between the fingers, and the pan cannot
                    // push the card out of its own frame.
                    .zoomPan(scale: $zoom, offset: $pan)
                    .rotation3DEffect(.degrees(tilt.height), axis: (x: 1, y: 0, z: 0),
                                      perspective: 0.6)
                    .rotation3DEffect(.degrees(tilt.width), axis: (x: 0, y: 1, z: 0),
                                      perspective: 0.6)
                    // Out of the depth of the screen rather than up from the
                    // bottom edge: small, soft and transparent, coming forward
                    // into focus. A card is picked up, not slid onto the desk.
                    .scaleEffect(appeared ? 1 : 0.62)
                    .blur(radius: appeared ? 0 : 14)
                    .opacity(appeared ? 1 : 0)
                    // Turning and panning are both one-finger drags, so only one
                    // of them can be live. Zoomed in, the drag moves the card:
                    // having asked to look closer at something, the child's next
                    // move is to say at what — and a card leaning at 26° while
                    // magnified three times is not a view of anything.
                    .simultaneousGesture(ZoomPan.isZoomed(zoom) ? nil : tiltGesture)

                // What this card becomes next, right under the thing it is
                // about. The one place the ladder is spelled out (CLAUDE.md §5).
                if let goal = GameRules.nextGoal(stars: stars, streak: streak,
                                                 isRainbow: rainbow) {
                    VStack(spacing: 7) {
                        Text(mode.nextGoalLabel(goal, unlock: unlock))
                            .font(AppFont.rounded(16, relativeTo: .subheadline))
                            .foregroundStyle(.white.opacity(0.92))
                        NextGoalBar(goal: goal, track: .white.opacity(0.25))
                            .frame(width: 150)
                    }
                    .padding(.top, 16)
                    .opacity(appeared ? 1 : 0)
                }

                Spacer(minLength: 18)

                Button(mode.close) { close() }
                    .buttonStyle(.bouncy(Palette.teal, fontSize: 17))
                    .opacity(appeared ? 1 : 0)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            // Low, but not against the home indicator — the bouncy style draws
            // its shadow below the pill and sinks into it when pressed.
            .padding(.bottom, 18)
        }
        .onAppear {
            if let debugTilt = Self.debugTilt { tilt = debugTilt }
            if reduceMotion { appeared = true }
            else { withAnimation(.spring(duration: 0.42, bounce: 0.22)) { appeared = true } }
        }
    }

    /// Turning the card. Reduce Motion opts out entirely: this is parallax, and
    /// parallax is the motion that makes people ill (CLAUDE.md §9). The card is
    /// still shown large, which is the part that carries the information.
    private var tiltGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !reduceMotion else { return }
                tilt = CGSize(
                    // /6 rather than /8: the limit went up to 26°, and at the
                    // old rate reaching it took most of the screen width.
                    width: clamp(value.translation.width / 6),
                    // Dragging down should lean the top away, like pushing the
                    // far edge of a card flat on a table.
                    height: clamp(-value.translation.height / 6))
            }
            .onEnded { _ in
                guard !reduceMotion else { return }
                withAnimation(.spring(duration: 0.5, bounce: 0.35)) { tilt = .zero }
            }
    }

    /// Enough to catch the light, not so far that the face starts to distort and
    /// stops reading as a card. The limit belongs to the face, which positions
    /// its highlight as a fraction of it.
    private func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, -CardFaceView.maxTilt), CardFaceView.maxTilt)
    }

    /// Reverses the arrival, then dismisses. Without it the card vanishes on
    /// the frame the button is pressed, which is not how anything is put down.
    private func close() {
        guard !reduceMotion else { return dismiss() }
        withAnimation(.easeIn(duration: 0.2)) { appeared = false }
        Task {
            try? await Task.sleep(for: .seconds(0.2))
            dismiss()
        }
    }
}
