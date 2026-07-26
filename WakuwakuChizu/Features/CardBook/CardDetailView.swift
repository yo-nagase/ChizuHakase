import SwiftUI

/// One card, held up and turned in the light.
///
/// The book shows 141 chips, which is a catalogue. This is the other half of
/// owning something: a single card big enough to look at, that tilts under a
/// finger the way a real one does when you angle it to catch the shine.
struct CardDetailView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.textMode) private var mode
    @Environment(\.dismiss) private var dismiss

    let card: SpecialtyCard
    let prefecture: Prefecture?
    let ownedCount: Int

    /// Live tilt, in degrees. x is pitch, y is yaw.
    @State private var tilt: CGSize = .zero
    /// Pinch magnification, 1...3.
    @State private var zoom: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1
    @State private var appeared = false

    private static let maxZoom: CGFloat = 3
    private var liveZoom: CGFloat { min(max(zoom * pinch, 1), Self.maxZoom) }

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

    private var isShiny: Bool { ownedCount >= GameRules.maxCardCopies }

    /// How far the card will lean. Enough to catch the light, not so far that
    /// the face starts to distort and stops reading as a card.
    private static let maxTilt: CGFloat = 14

    var body: some View {
        ZStack {
            // Tapping the backdrop closes: a child who does not find the button
            // will try tapping away from the thing, and should be right.
            Color.black.opacity(appeared ? 0.45 : 0)
                .ignoresSafeArea()
                .onTapGesture { close() }

            VStack(spacing: 18) {
                cardFace
                    .frame(maxWidth: 300)
                    .scaleEffect(liveZoom)
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
                    .gesture(magnifyGesture)
                    .simultaneousGesture(tiltGesture)

                Button(mode.close) { close() }
                    .buttonStyle(.bouncy(Palette.teal, fontSize: 17))
                    .opacity(appeared ? 1 : 0)
            }
            .padding(24)
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
                    width: clamp(value.translation.width / 8),
                    // Dragging down should lean the top away, like pushing the
                    // far edge of a card flat on a table.
                    height: clamp(-value.translation.height / 8))
            }
            .onEnded { _ in
                guard !reduceMotion else { return }
                withAnimation(.spring(duration: 0.5, bounce: 0.35)) { tilt = .zero }
            }
    }

    private func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, -Self.maxTilt), Self.maxTilt)
    }

    /// Pinch to look closer. The magnification is kept rather than sprung back:
    /// this is a viewer, and something zoomed into on purpose should stay that
    /// way until it is put down.
    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .updating($pinch) { value, state, _ in state = value.magnification }
            .onEnded { value in zoom = min(max(zoom * value.magnification, 1), Self.maxZoom) }
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

    // MARK: - The card itself

    /// Built the way a printed card is: coloured stock, an inset panel, a matted
    /// window for the picture, a name plate under it, and a number in the
    /// corner. The chips in the book are tiles — this is the object they stand
    /// for, so it is worth the layers.
    private var cardFace: some View {
        ZStack {
            stock
            VStack(spacing: 8) {
                topRow
                artWindow
                namePlate
                Text(card.description)
                    .font(AppFont.rounded(13, relativeTo: .caption))
                    .foregroundStyle(Palette.ink.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity)
                footer
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Palette.page)
            )
            // The inset is what turns the outer colour into a border rather
            // than a background.
            .padding(11)
        }
        .aspectRatio(0.7, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 20, y: 12)
    }

    /// The card stock. Gold for キラ, the prefecture's colour otherwise, darker
    /// toward the bottom so the border reads as a printed edge and not a flat
    /// rectangle behind the panel.
    private var stock: some View {
        let base = isShiny ? Palette.gold : Palette.fill(for: card.prefectureCode)
        return LinearGradient(colors: [base, base.opacity(0.72)],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(alignment: .topLeading) {
                // A gloss on the corner, as printed card stock has.
                RadialGradient(colors: [.white.opacity(0.55), .clear],
                               center: .topLeading, startRadius: 0, endRadius: 190)
            }
    }

    private var topRow: some View {
        HStack(spacing: 6) {
            Text(card.category.emoji)
                .font(.system(size: 15))
            Text(prefecture?.displayName(mode) ?? "")
                .font(AppFont.heading(16, relativeTo: .subheadline))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .tracking(0.5)
            Spacer(minLength: 0)
            // Rarity, in the corner where a card keeps it.
            Text(isShiny ? "★★" : "★")
                .font(AppFont.rounded(13, relativeTo: .caption))
                .foregroundStyle(isShiny ? Palette.gold : Palette.ink.opacity(0.28))
        }
    }

    /// The picture, matted and ruled like a window cut in the card.
    private var artWindow: some View {
        ZStack {
            Palette.fill(for: card.prefectureCode, strength: 0.14)
            if let art = card.art {
                Image(art).resizable().scaledToFit().padding(4)
            } else {
                Text(card.emoji).font(.system(size: 88))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay { sheen }
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(Palette.ink.opacity(0.18), lineWidth: 1)
        }
        .padding(.horizontal, 2)
    }

    /// The name, on a plate rather than loose on the panel — it is the card's
    /// title, and a title on a card sits on something.
    private var namePlate: some View {
        Text(card.nameKana)
            .font(AppFont.rounded(21, relativeTo: .title3))
            .foregroundStyle(Palette.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Palette.fill(for: card.prefectureCode, strength: 0.34))
            )
    }

    private var footer: some View {
        HStack {
            Text(card.category.label(mode))
                .font(AppFont.rounded(10, relativeTo: .caption2))
                .foregroundStyle(Palette.ink.opacity(0.45))
            Spacer(minLength: 0)
            // A collector number. It means nothing mechanically and that is
            // fine — it is one of the things that makes a card feel like a card.
            Text(verbatim: "No.\(card.id)")
                .font(AppFont.rounded(10, relativeTo: .caption2))
                .foregroundStyle(Palette.ink.opacity(0.35))
                .monospacedDigit()
        }
    }

    /// The shine, and the reason tilting is worth doing at all.
    ///
    /// It slides across as the card turns, so the highlight belongs to the
    /// angle rather than being a decal printed on the face. Plain cards get a
    /// faint white version of the same thing — glass catches light too.
    @ViewBuilder private var sheen: some View {
        let shift = tilt.width / Self.maxTilt
        LinearGradient(
            colors: isShiny ? Palette.holographicBand : [.white.opacity(0.35), .clear],
            startPoint: UnitPoint(x: 0.1 + shift * 0.5, y: 0),
            endPoint: UnitPoint(x: 0.9 + shift * 0.5, y: 1))
        // Enough to read as foil while it slides, not so much that the
        // illustration underneath changes colour at rest.
        .opacity(isShiny ? 0.24 : 0.14)
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }
}
