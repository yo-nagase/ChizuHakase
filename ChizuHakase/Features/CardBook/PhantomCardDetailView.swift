import SwiftUI

/// A phantom card held up in the same physical space as an ordinary card, but
/// rendered by its own full-bleed face.
struct PhantomCardDetailView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @Environment(\.textMode) private var mode

    let card: PhantomCard

    @State private var tilt: CGSize = .zero
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.opacity(appeared ? 0.68 : 0)
                .ignoresSafeArea()
                .onTapGesture { close() }
            VStack {
                Spacer(minLength: 12)
                PhantomCardFaceView(card: card, isOwned: true, tilt: tilt)
                    .frame(maxWidth: 300)
                    .rotation3DEffect(.degrees(tilt.height), axis: (x: 1, y: 0, z: 0),
                                      perspective: 0.6)
                    .rotation3DEffect(.degrees(tilt.width), axis: (x: 0, y: 1, z: 0),
                                      perspective: 0.6)
                    .scaleEffect(appeared ? 1 : 0.62)
                    .blur(radius: appeared ? 0 : 14)
                    .opacity(appeared ? 1 : 0)
                    .gesture(tiltGesture)
                VStack(spacing: 5) {
                    Text(card.displayName(mode))
                        .font(AppFont.heading(28, relativeTo: .title2))
                    Text(card.displayDescription(mode))
                        .font(AppFont.rounded(14, relativeTo: .body))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.white)
                .opacity(appeared ? 1 : 0)
                Spacer(minLength: 20)
                Button(mode.close) { close() }
                    .buttonStyle(.bouncy(Palette.teal, fontSize: 17))
                    .opacity(appeared ? 1 : 0)
            }
            .padding(24)
        }
        .onAppear {
            if reduceMotion { appeared = true }
            else { withAnimation(.spring(duration: 0.48, bounce: 0.2)) { appeared = true } }
        }
    }

    private var tiltGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !reduceMotion else { return }
                tilt = CGSize(width: clamp(value.translation.width / 6),
                              height: clamp(-value.translation.height / 6))
            }
            .onEnded { _ in
                guard !reduceMotion else { return }
                withAnimation(.spring(duration: 0.5, bounce: 0.35)) { tilt = .zero }
            }
    }

    private func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, -CardFaceView.maxTilt), CardFaceView.maxTilt)
    }

    private func close() {
        guard !reduceMotion else { return dismiss() }
        withAnimation(.easeIn(duration: 0.2)) { appeared = false }
        Task {
            try? await Task.sleep(for: .seconds(0.2))
            dismiss()
        }
    }
}
