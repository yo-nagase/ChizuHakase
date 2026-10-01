import SwiftUI

/// The approved dragon artwork already contains its title and metal border.
/// Moving foil is composited separately so it responds to the actual card tilt.
struct SkyHolographicCardFace: View, Animatable {
    let card: PhantomCard
    let metrics: PhantomCardFaceView.Metrics
    var tilt: CGSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.textMode) private var mode

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(tilt.width, tilt.height) }
        set { tilt = CGSize(width: newValue.first, height: newValue.second) }
    }

    private var movement: CGSize { reduceMotion ? .zero : tilt }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let x = movement.width / CardFaceView.maxTilt
            let y = movement.height / CardFaceView.maxTilt
            ZStack {
                Image("phantom-art-sky")
                    .resizable()
                    .scaledToFit()
                LinearGradient(
                    colors: [.clear, .cyan.opacity(0.18), .purple.opacity(0.16),
                             .pink.opacity(0.12), .yellow.opacity(0.18), .clear],
                    startPoint: UnitPoint(x: -0.4 + x * 0.7, y: y * 0.4),
                    endPoint: UnitPoint(x: 1.1 + x * 0.7, y: 1 + y * 0.4)
                )
                .blendMode(.colorDodge)
                .opacity(reduceMotion ? 0 : 0.65 + abs(x) * 0.25)
                // A narrow reflection travels across the lacquer rather than
                // washing out the dragon's white face with a full-card glow.
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .clear, location: 0.43),
                    .init(color: .white.opacity(0.22), location: 0.5),
                    .init(color: .clear, location: 0.57),
                    .init(color: .clear, location: 1)
                ], startPoint: UnitPoint(x: -0.7 + x, y: y * 0.3),
                   endPoint: UnitPoint(x: 1.3 + x, y: 1 + y * 0.3))
                .blendMode(.screen)
                .opacity(reduceMotion ? 0 : 1)
                RoundedRectangle(cornerRadius: metrics.radius)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.6), .clear,
                                                          .cyan.opacity(0.35), .white.opacity(0.5)],
                                                 startPoint: UnitPoint(x: 0.2 + x * 0.4, y: 0),
                                                 endPoint: .bottomTrailing), lineWidth: 1)
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: metrics.radius))
        }
        .aspectRatio(2.0 / 3.0, contentMode: .fit)
        .background {
            RoundedRectangle(cornerRadius: metrics.radius)
                .fill(Color(white: 0.12))
                .offset(x: -movement.width * 0.08, y: 2 + abs(movement.height) * 0.06)
        }
        .shadow(color: .black.opacity(0.45), radius: metrics.shadowRadius,
                x: -movement.width * 0.3, y: metrics.shadowY)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(card.displayName(mode))。\(mode.phantomCard)")
    }
}
