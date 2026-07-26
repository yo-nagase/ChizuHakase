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
    @State private var appeared = false

    private var isShiny: Bool { ownedCount >= GameRules.maxCardCopies }

    /// How far the card will lean. Enough to catch the light, not so far that
    /// the face starts to distort and stops reading as a card.
    private static let maxTilt: CGFloat = 14

    var body: some View {
        ZStack {
            // Tapping the backdrop closes: a child who does not find the button
            // will try tapping away from the thing, and should be right.
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 18) {
                cardFace
                    .frame(maxWidth: 300)
                    .rotation3DEffect(.degrees(tilt.height), axis: (x: 1, y: 0, z: 0),
                                      perspective: 0.6)
                    .rotation3DEffect(.degrees(tilt.width), axis: (x: 0, y: 1, z: 0),
                                      perspective: 0.6)
                    .scaleEffect(appeared ? 1 : 0.86)
                    .opacity(appeared ? 1 : 0)
                    .gesture(tiltGesture)

                Button(mode.close) { dismiss() }
                    .buttonStyle(.bouncy(Palette.teal, fontSize: 17))
            }
            .padding(24)
        }
        .onAppear {
            if reduceMotion { appeared = true }
            else { withAnimation(.spring(duration: 0.35)) { appeared = true } }
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

    // MARK: - The card itself

    private var cardFace: some View {
        VStack(spacing: 0) {
            header
            art
            caption
        }
        .background(Palette.page)
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(isShiny ? Palette.gold : Palette.dieCut, lineWidth: 5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 18, y: 10)
    }

    /// Ink on the prefecture's own colour. White was unreadable: the palette is
    /// eight pastels, and white text on a pastel is white text on white.
    private var header: some View {
        Text(prefecture?.displayName(mode) ?? "")
            .font(AppFont.rounded(16, relativeTo: .headline))
            .foregroundStyle(Palette.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Palette.fill(for: card.prefectureCode))
    }

    /// Square, so the card sizes itself around the picture instead of forcing
    /// a portrait ratio the illustrations then float inside.
    @ViewBuilder private var art: some View {
        ZStack {
            Palette.fill(for: card.prefectureCode, strength: 0.16)
            if let art = card.art {
                Image(art)
                    .resizable()
                    .scaledToFit()
                    .padding(6)
            } else {
                Text(card.emoji)
                    .font(.system(size: 96))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        // The shine belongs to the picture, which is where foil would be. Over
        // the caption it tinted the words and cost more legibility than it was
        // ever going to buy in sparkle.
        .overlay { sheen }
        .clipped()
    }

    private var caption: some View {
        VStack(spacing: 4) {
            // The reading, always: an illustrated card titles itself in kanji,
            // which the child this app is for cannot read.
            Text(card.nameKana)
                .font(AppFont.rounded(22, relativeTo: .title3))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(card.description)
                .font(AppFont.rounded(13, relativeTo: .caption))
                .foregroundStyle(Palette.ink.opacity(0.65))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 10)
        .padding(.vertical, 14)
        .background(.white)
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
        .opacity(isShiny ? 0.34 : 0.18)
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }
}
