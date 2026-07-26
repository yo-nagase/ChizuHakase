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
                    .aspectRatio(0.72, contentMode: .fit)
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

    /// A 掛け紙 rather than a trading-card template.
    ///
    /// The previous face was the dictionary definition of a card — coloured
    /// border, title bar, matted window, name plate, star rating, numbered
    /// footer — every element a centred box stacked on the last. It also said
    /// everything twice: the painting already prints 「宮城県 ずんだ餅」 inside its
    /// own frame, and the card repeated both around it.
    ///
    /// This is the printed paper the subject actually comes wrapped in: a
    /// vertical title strip, the picture running to the edges, a seal, and a
    /// double rule. The frame now supplies only what the painting lacks — the
    /// *reading*, in kana, for a child who cannot read the kanji in the art.
    private var cardFace: some View {
        HStack(spacing: 0) {
            titleStrip
            VStack(alignment: .leading, spacing: 0) {
                picture
                nameBlock
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.page)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay { doubleRule }
        .shadow(color: .black.opacity(0.3), radius: 14, y: 8)
    }

    /// The prefecture, set vertically down the spine.
    ///
    /// In kana on purpose: the painting says 宮城県 in kanji, so this adds the
    /// reading instead of repeating the word. Vertical because that is how a
    /// label on Japanese packaging runs, and because it puts the one piece of
    /// text a child scans for on an axis nothing else uses.
    private var titleStrip: some View {
        VStack(spacing: 2) {
            ForEach(Array((prefecture?.kana ?? "").enumerated()), id: \.offset) { _, ch in
                Text(String(ch))
                    .font(AppFont.heading(15, relativeTo: .subheadline))
                    // Ink, not white: the palette is eight pastels and white on
                    // a pastel is white on white.
                    .foregroundStyle(Palette.ink)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 16)
        .padding(.horizontal, 7)
        .frame(maxHeight: .infinity)
        .background(Palette.fill(for: card.prefectureCode))
    }

    /// Runs to the top and right edges. A picture inset evenly on all four
    /// sides is a thumbnail; one that reaches the edge is the face of the thing.
    @ViewBuilder private var picture: some View {
        ZStack {
            Palette.fill(for: card.prefectureCode, strength: 0.12)
            if let art = card.art {
                Image(art).resizable().scaledToFit()
            } else {
                // Bigger than the painted cards need, because an emoji has
                // no frame of its own to fill the window with.
                Text(card.emoji).font(.system(size: 128))
            }
        }
        // Takes whatever height is left rather than a fixed square. The square
        // version left a band of blank paper at the foot of every card; here
        // the tint above and below the painting reads as the mat it is.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .overlay { sheen }
    }

    /// Left-aligned, hanging off the strip. Centred text under a centred
    /// picture inside a centred border was most of what made the old face read
    /// as a template.
    /// Caption and seal side by side rather than stacked with a gap between
    /// them. Stacking left a band of empty paper in the middle of the card,
    /// which is the layout admitting it had run out of things to say.
    private var nameBlock: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(card.nameKana)
                    .font(AppFont.heading(24, relativeTo: .title2))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(card.description)
                    .font(AppFont.rounded(12, relativeTo: .caption))
                    .foregroundStyle(Palette.ink.opacity(0.62))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            seal
        }
        // Sized to its content, not flexible: with both this and the picture
        // asking for the leftover height they split it, and the caption's half
        // came out as a band of blank paper under two lines of text.
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
    }

    /// A seal, where a stamped mark of provenance goes. It replaces the star
    /// rating, which was the generic videogame signifier for the same idea, and
    /// it carries the card's number so the footer can go away entirely.
    private var seal: some View {
        VStack(spacing: 0) {
            Text(card.category.label(mode))
                .font(AppFont.heading(11, relativeTo: .caption2))
            Text(verbatim: card.id)
                .font(AppFont.heading(10, relativeTo: .caption2))
                .monospacedDigit()
        }
        .foregroundStyle(isShiny ? Palette.ink : .white)
        .frame(width: 52, height: 52)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isShiny ? foilFill : AnyShapeStyle(Palette.seal))
        }
        .rotationEffect(.degrees(-6))
    }

    /// Foil, not rainbow. Stamped gold shifts with the angle and stays one
    /// colour; a spectrum smeared across the face is the literal reading of
    /// "holo" and looks it.
    private var foilFill: AnyShapeStyle {
        let shift = tilt.width / Self.maxTilt
        return AnyShapeStyle(LinearGradient(
            colors: [Palette.gold, .white, Palette.gold],
            startPoint: UnitPoint(x: 0.5 - shift, y: 0),
            endPoint: UnitPoint(x: 1.5 - shift, y: 1)))
    }

    /// Thick-then-thin, inset from the trim. A printing convention, and the
    /// thing a plain rounded border was standing in for.
    private var doubleRule: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Palette.ink, lineWidth: 3.5)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(Palette.ink.opacity(0.8), lineWidth: 1)
                .padding(6)
        }
        .allowsHitTesting(false)
    }

    /// The shine, and the reason tilting is worth doing at all.
    ///
    /// It slides across as the card turns, so the highlight belongs to the
    /// angle rather than being a decal printed on the face. Plain cards get a
    /// faint white version of the same thing — glass catches light too.
    @ViewBuilder private var sheen: some View {
        let shift = tilt.width / Self.maxTilt
        LinearGradient(colors: [.clear, .white, .clear],
                       startPoint: UnitPoint(x: 0.0 + shift, y: 0),
                       endPoint: UnitPoint(x: 1.0 + shift, y: 1))
            // A moving highlight, not a tint. The old rainbow wash turned the
            // watercolours yellow whether or not anyone was tilting the card.
            .opacity(isShiny ? 0.22 : 0.08)
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
    }
}
