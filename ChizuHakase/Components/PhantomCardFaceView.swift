import SwiftUI

/// The one-off completion reward. Its silhouette stays card-shaped so it fits
/// the book, but everything inside that silhouette rejects the printed-card
/// grammar used by `CardFaceView`: no paper panel, photo window, star row or
/// name plate — one deep glass portal from edge to edge.
struct PhantomCardFaceView: View {
    let card: PhantomCard
    let isOwned: Bool
    var metrics: Metrics = .full
    var tilt: CGSize = .zero

    @Environment(\.textMode) private var mode

    struct Metrics {
        let radius: CGFloat
        let titleSize: CGFloat
        let symbolSize: CGFloat
        let showsDetails: Bool
        let shadowRadius: CGFloat
        let shadowY: CGFloat

        static let full = Metrics(radius: 18, titleSize: 31,
                                  symbolSize: 86, showsDetails: true,
                                  shadowRadius: 24, shadowY: 13)
        static let chip = Metrics(radius: 10, titleSize: 14,
                                  symbolSize: 39, showsDetails: false,
                                  shadowRadius: 0, shadowY: 2)
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                obsidian
                interference(in: size)
                portal(in: size)
                if isOwned { identity(in: size) }
                else { hiddenIdentity }
                spectralGlint(in: size)
                crystalFrame
            }
        }
        .aspectRatio(CardFaceView.aspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: metrics.radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: metrics.radius, style: .continuous)
                .strokeBorder(.white.opacity(0.65), lineWidth: 0.8)
        }
        .background {
            RoundedRectangle(cornerRadius: metrics.radius, style: .continuous)
                .fill(Color(red: 0.02, green: 0.025, blue: 0.07))
                .offset(y: metrics.showsDetails ? 3 : 1.5)
        }
        .shadow(color: .black.opacity(metrics.showsDetails ? 0.48 : 0.28),
                radius: metrics.shadowRadius, y: metrics.shadowY)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var obsidian: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.005, green: 0.015, blue: 0.05),
                                    Color(red: 0.025, green: 0.025, blue: 0.11),
                                    Color(red: 0.04, green: 0.012, blue: 0.09)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [accent.opacity(0.23), .clear],
                           center: .center, startRadius: 0, endRadius: 240)
        }
    }

    private func interference(in size: CGSize) -> some View {
        ZStack {
            ForEach(0..<9, id: \.self) { index in
                Ellipse()
                    .stroke(AngularGradient(colors: [.clear, accent.opacity(0.3),
                                                     .clear, .white.opacity(0.15), .clear],
                                            center: .center),
                            lineWidth: metrics.showsDetails ? 0.8 : 0.45)
                    .frame(width: size.width * (0.42 + CGFloat(index) * 0.10),
                           height: size.height * (0.20 + CGFloat(index) * 0.065))
                    .rotationEffect(.degrees(Double(index) * 11 - 34))
                    .offset(x: tilt.width * CGFloat(index + 1) / 45,
                            y: tilt.height * CGFloat(index + 1) / 65)
            }
        }
        .opacity(isOwned ? 1 : 0.32)
        .allowsHitTesting(false)
    }

    private func portal(in size: CGSize) -> some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [.white.opacity(0.08), accent.opacity(0.24),
                                              Color.black.opacity(0.15), .clear],
                                     center: .center, startRadius: 1,
                                     endRadius: size.width * 0.42))
            Circle()
                .stroke(AngularGradient(colors: [.cyan, .purple, .pink, .yellow,
                                                 .cyan], center: .center),
                        lineWidth: metrics.showsDetails ? 2.2 : 1.1)
                .blur(radius: metrics.showsDetails ? 0.4 : 0)
                .opacity(isOwned ? 0.8 : 0.24)
            Circle()
                .stroke(.white.opacity(isOwned ? 0.32 : 0.1), lineWidth: 0.7)
                .padding(metrics.showsDetails ? 9 : 4)
        }
        .frame(width: size.width * 0.78, height: size.width * 0.78)
        .offset(x: tilt.width * 0.14, y: -size.height * 0.035 + tilt.height * 0.10)
        .shadow(color: accent.opacity(isOwned ? 0.75 : 0.18),
                radius: metrics.showsDetails ? 24 : 8)
    }

    private func identity(in size: CGSize) -> some View {
        Image(systemName: symbolName)
            .font(.system(size: metrics.symbolSize, weight: .ultraLight))
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, accent)
            .shadow(color: accent, radius: metrics.showsDetails ? 16 : 6)
            .offset(x: tilt.width * 0.24, y: tilt.height * 0.16)
        .frame(width: size.width, height: size.height)
    }

    private var hiddenIdentity: some View {
        VStack(spacing: metrics.showsDetails ? 13 : 5) {
            Image(systemName: "lock.fill")
                .font(.system(size: metrics.symbolSize * 0.55, weight: .thin))
                .foregroundStyle(.white.opacity(0.38))
            Text("???")
                .font(AppFont.heading(metrics.titleSize, relativeTo: .title2))
                .foregroundStyle(.white.opacity(0.42))
                .tracking(3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var setSeal: some View {
        HStack(spacing: metrics.showsDetails ? 5 : 2) {
            ForEach(1...card.setCount, id: \.self) { index in
                Rectangle()
                    .fill(index == card.setIndex ? AnyShapeStyle(.white)
                                                : AnyShapeStyle(.white.opacity(0.25)))
                    .frame(width: metrics.showsDetails ? 8 : 3.5,
                           height: metrics.showsDetails ? 8 : 3.5)
                    .rotationEffect(.degrees(45))
            }
        }
        .padding(.top, metrics.showsDetails ? 3 : 1)
        .accessibilityHidden(true)
    }

    private func spectralGlint(in size: CGSize) -> some View {
        LinearGradient(colors: [.clear, .cyan.opacity(0.05), .white.opacity(0.54),
                                .pink.opacity(0.13), .clear],
                       startPoint: .leading, endPoint: .trailing)
            .frame(width: size.width * 0.22, height: size.height * 1.4)
            .rotationEffect(.degrees(28))
            .offset(x: tilt.width / CardFaceView.maxTilt * size.width * 0.62,
                    y: -size.height * 0.04)
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
    }

    private var crystalFrame: some View {
        ZStack {
            RoundedRectangle(cornerRadius: metrics.radius, style: .continuous)
                .strokeBorder(AngularGradient(colors: [.cyan, .indigo, .pink, .yellow,
                                                       .mint, .purple, .cyan],
                                              center: .center),
                              lineWidth: metrics.showsDetails ? 10 : 5)
            RoundedRectangle(cornerRadius: metrics.radius - 4, style: .continuous)
                .strokeBorder(.white.opacity(0.42), lineWidth: 1)
                .padding(metrics.showsDetails ? 8 : 4)
            VStack {
                HStack { facet; Spacer(); facet.rotationEffect(.degrees(90)) }
                Spacer()
                HStack { facet.rotationEffect(.degrees(-90)); Spacer(); facet }
            }
            .padding(metrics.showsDetails ? 13 : 6)
            VStack {
                Spacer()
                setSeal
            }
            .padding(.bottom, metrics.showsDetails ? 15 : 7)
        }
        .allowsHitTesting(false)
    }

    private var facet: some View {
        Rectangle()
            .fill(LinearGradient(colors: [.white.opacity(0.9), accent.opacity(0.55),
                                          .clear], startPoint: .topLeading,
                                 endPoint: .bottomTrailing))
            .frame(width: metrics.showsDetails ? 25 : 11,
                   height: metrics.showsDetails ? 25 : 11)
            .rotationEffect(.degrees(45))
    }

    private var accent: Color {
        switch card.motif {
        case .sky: .pink
        case .earth: .yellow
        case .sea: .cyan
        case .northAmerica: .mint
        case .southAmerica: .orange
        case .europe: .purple
        case .africa: .yellow
        case .asia: .pink
        case .oceania: .cyan
        case .antarctica: .white
        }
    }

    private var symbolName: String {
        switch card.motif {
        case .sky: "sun.horizon.fill"
        case .earth: "mountain.2.fill"
        case .sea: "water.waves"
        case .northAmerica, .southAmerica: "globe.americas.fill"
        case .europe, .africa: "globe.europe.africa.fill"
        case .asia, .oceania: "globe.asia.australia.fill"
        case .antarctica: "snowflake"
        }
    }

    private var accessibilityText: String {
        guard isOwned else { return mode.notCollectedYet }
        return "\(card.displayName(mode))。\(mode.phantomCard)"
    }
}
