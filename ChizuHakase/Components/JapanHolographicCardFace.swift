import SwiftUI

/// A blank base for redesigning the nationwide challenge reward.
struct JapanHolographicCardFace: View {
    let card: PhantomCard
    let metrics: PhantomCardFaceView.Metrics
    var tilt: CGSize
    @Environment(\.textMode) private var mode

    var body: some View {
        RoundedRectangle(cornerRadius: metrics.radius, style: .continuous)
            .fill(.white)
            .overlay {
                RoundedRectangle(cornerRadius: metrics.radius, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.12), lineWidth: 1)
            }
            .aspectRatio(CardFaceView.aspectRatio, contentMode: .fit)
            .shadow(color: .black.opacity(0.16), radius: metrics.shadowRadius, y: metrics.shadowY)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(card.displayName(mode))。\(mode.phantomCard)")
    }
}
