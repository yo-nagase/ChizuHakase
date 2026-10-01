import SwiftUI

/// Illustrated expedition cards. Artwork carries each card's identity; foil,
/// typography and collection numbering tie the Japanese and world sets together.
struct PhantomCardFaceView: View {
    let card: PhantomCard
    let isOwned: Bool
    var metrics: Metrics = .full
    var tilt: CGSize = .zero

    @Environment(\.textMode) private var mode

    struct Metrics {
        let radius: CGFloat
        let showsDetails: Bool
        let shadowRadius: CGFloat
        let shadowY: CGFloat

        static let full = Metrics(radius: 18, showsDetails: true,
                                  shadowRadius: 20, shadowY: 12)
        static let chip = Metrics(radius: 10, showsDetails: false,
                                  shadowRadius: 0, shadowY: 2)
    }

    private let ink = Color(red: 0.035, green: 0.065, blue: 0.10)
    private let gold = Color(red: 0.89, green: 0.73, blue: 0.43)
    private let ivory = Color(red: 1, green: 0.96, blue: 0.83)

    var body: some View {
        if isOwned && card.motif == .japan {
            JapanHolographicCardFace(card: card, metrics: metrics, tilt: tilt)
        } else if isOwned && card.motif == .sky {
            SkyHolographicCardFace(card: card, metrics: metrics, tilt: tilt)
        } else if isOwned && card.motif == .earth {
            EarthHolographicCardFace(card: card, metrics: metrics, tilt: tilt)
        } else {
            illustratedBody
        }
    }

    private var illustratedBody: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let width = size.width
            ZStack {
                ink
                if isOwned {
                    Image(artworkName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: width, height: size.height)
                        .clipped()
                    LinearGradient(stops: [
                        .init(color: ink.opacity(0.65), location: 0),
                        .init(color: .clear, location: 0.24),
                        .init(color: .clear, location: 0.57),
                        .init(color: ink.opacity(0.65), location: 0.77),
                        .init(color: ink.opacity(0.98), location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                    foilDust(in: size)
                } else {
                    hiddenArtwork(in: size)
                }
                lettering(in: size)
                frame(in: size)
            }
            .frame(width: width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: metrics.radius, style: .continuous))
        }
        .aspectRatio(CardFaceView.aspectRatio, contentMode: .fit)
        .background {
            RoundedRectangle(cornerRadius: metrics.radius, style: .continuous)
                .fill(ink).offset(y: metrics.showsDetails ? 3 : 1)
        }
        .shadow(color: .black.opacity(0.35), radius: metrics.shadowRadius, y: metrics.shadowY)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isOwned
                            ? "\(card.displayName(mode))。\(mode.phantomCard)"
                            : mode.notCollectedYet)
    }

    private func lettering(in size: CGSize) -> some View {
        let width = size.width
        return VStack(spacing: 0) {
            if metrics.showsDetails {
            HStack(alignment: .center) {
                Text(mode.phantomCard)
                    .font(AppFont.heading(width * 0.035, relativeTo: .caption))
                    .tracking(width * 0.008)
                Spacer()
                Text(String(format: "%02d / %02d", card.setIndex, card.setCount))
                    .font(.system(size: width * 0.035, weight: .medium, design: .monospaced))
                    .tracking(width * 0.003)
            }
            .foregroundStyle(ivory.opacity(0.9))
            }
            Spacer()
            HStack(spacing: width * 0.025) {
                Rectangle().fill(gold.opacity(0.7)).frame(height: 0.6)
                Image(systemName: card.motif == .japan ? "crown.fill" : "sparkle")
                    .font(.system(size: width * 0.045, weight: .regular))
                    .foregroundStyle(gold)
                Rectangle().fill(gold.opacity(0.7)).frame(height: 0.6)
            }
            .padding(.horizontal, width * 0.15)
            .padding(.bottom, width * 0.035)
            Text(isOwned ? card.displayName(mode) : "???")
                .font(AppFont.heading(width * 0.115, relativeTo: .title2))
                .foregroundStyle(ivory)
                .tracking(width * 0.008)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .shadow(color: ink, radius: 3, y: 1)
            HStack(spacing: width * 0.014) {
                ForEach(1...card.setCount, id: \.self) { index in
                    Circle()
                        .fill(index == card.setIndex ? gold : gold.opacity(0.23))
                        .frame(width: width * 0.012, height: width * 0.012)
                }
            }
            .padding(.top, width * 0.035)
        }
        .padding(.horizontal, width * 0.085)
        .padding(.top, width * 0.09)
        .padding(.bottom, width * 0.09)
    }

    private func frame(in size: CGSize) -> some View {
        let width = size.width
        let foil = LinearGradient(colors: [ivory, gold, Color(red: 0.45, green: 0.29, blue: 0.12),
                                           ivory, gold],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        return ZStack {
            RoundedRectangle(cornerRadius: metrics.radius, style: .continuous)
                .strokeBorder(foil, lineWidth: width * 0.014)
            RoundedRectangle(cornerRadius: max(2, metrics.radius - width * 0.025))
                .strokeBorder(gold.opacity(0.6), lineWidth: 0.6)
                .padding(width * 0.026)
            // Small engraved corners leave the illustration open and readable.
            Canvas { context, canvas in
                let inset = width * 0.047
                let length = width * 0.065
                for origin in [CGPoint(x: inset, y: inset),
                               CGPoint(x: canvas.width - inset, y: inset),
                               CGPoint(x: inset, y: canvas.height - inset),
                               CGPoint(x: canvas.width - inset, y: canvas.height - inset)] {
                    let dx: CGFloat = origin.x < canvas.width / 2 ? 1 : -1
                    let dy: CGFloat = origin.y < canvas.height / 2 ? 1 : -1
                    var corner = Path()
                    corner.move(to: CGPoint(x: origin.x, y: origin.y + length * dy))
                    corner.addLine(to: origin)
                    corner.addLine(to: CGPoint(x: origin.x + length * dx, y: origin.y))
                    context.stroke(corner, with: .color(gold), lineWidth: width * 0.004)
                }
            }
        }
        .frame(width: width, height: size.height)
        .allowsHitTesting(false)
    }

    private func foilDust(in size: CGSize) -> some View {
        Canvas { context, canvas in
            for index in 0..<18 {
                let x = CGFloat((index * 73 + 17) % 101) / 101 * canvas.width
                let y = CGFloat((index * 41 + 13) % 97) / 97 * canvas.height * 0.78
                let radius = canvas.width * (index.isMultiple(of: 4) ? 0.0028 : 0.0014)
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: radius * 2, height: radius * 2)),
                             with: .color(ivory.opacity(index.isMultiple(of: 4) ? 0.8 : 0.4)))
            }
        }
        .frame(width: size.width, height: size.height)
        .offset(x: tilt.width * 0.10, y: tilt.height * 0.08)
        .allowsHitTesting(false)
    }

    private func hiddenArtwork(in size: CGSize) -> some View {
        ZStack {
            RadialGradient(colors: [Color(red: 0.12, green: 0.19, blue: 0.23), ink],
                           center: .center, startRadius: 0, endRadius: size.width * 0.8)
            Canvas { context, canvas in
                let center = CGPoint(x: canvas.width / 2, y: canvas.height * 0.44)
                let radius = canvas.width * 0.27
                for index in 0..<24 {
                    let angle = Double(index) * .pi / 12
                    var ray = Path()
                    ray.move(to: CGPoint(x: center.x + cos(angle) * radius,
                                         y: center.y + sin(angle) * radius))
                    let outer = radius + canvas.width * (index.isMultiple(of: 3) ? 0.045 : 0.015)
                    ray.addLine(to: CGPoint(x: center.x + cos(angle) * outer,
                                            y: center.y + sin(angle) * outer))
                    context.stroke(ray, with: .color(gold.opacity(0.4)), lineWidth: 0.7)
                }
            }
            Image(systemName: "lock.fill")
                .font(.system(size: size.width * 0.13, weight: .light))
                .foregroundStyle(gold.opacity(0.65))
                .offset(y: -size.height * 0.06)
        }
    }

    private var artworkName: String {
        let suffix: String
        switch card.motif {
        case .sky: suffix = "sky"
        case .earth: suffix = "earth"
        case .sea: suffix = "sea"
        case .japan: suffix = "japan"
        case .northAmerica: suffix = "north-america"
        case .southAmerica: suffix = "south-america"
        case .europe: suffix = "europe"
        case .africa: suffix = "africa"
        case .asia: suffix = "asia"
        case .oceania: suffix = "oceania"
        case .antarctica: suffix = "antarctica"
        }
        return "phantom-art-\(suffix)"
    }
}
