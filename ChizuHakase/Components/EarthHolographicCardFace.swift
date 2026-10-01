import SwiftUI

/// Separate clean background and alpha foreground allow real relative motion
/// without leaving a second fox behind when the card is tilted.
struct EarthHolographicCardFace: View, Animatable {
    let card: PhantomCard
    let metrics: PhantomCardFaceView.Metrics
    var tilt: CGSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.textMode) private var mode

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(tilt.width, tilt.height) }
        set { tilt = CGSize(width: newValue.first, height: newValue.second) }
    }

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let x = reduceMotion ? 0 : tilt.width / CardFaceView.maxTilt
            let y = reduceMotion ? 0 : -tilt.height / CardFaceView.maxTilt
            ZStack {
                Image("phantom-earth-forest")
                    .resizable().scaledToFill()
                    .frame(width: w, height: h)
                    .scaleEffect(1.1)
                    .offset(x: -x * w * 0.025, y: -y * h * 0.018)
                Color.black.opacity(0.10)
                backgroundGlitter(width: w, x: x, y: y)
                    .offset(x: -x * w * 0.018, y: -y * h * 0.012)
                Image("phantom-earth-fox")
                    .resizable().scaledToFit()
                    .frame(width: w, height: h)
                    .scaleEffect(0.92)
                    .shadow(color: .black.opacity(0.28), radius: w * 0.025,
                            x: -x * w * 0.02, y: w * 0.025)
                    .offset(x: x * w * 0.035, y: y * h * 0.022)
                LinearGradient(colors: [.clear, .cyan.opacity(0.16), .pink.opacity(0.13),
                                        .yellow.opacity(0.18), .clear],
                               startPoint: UnitPoint(x: -0.5 + x * 0.8, y: y * 0.3),
                               endPoint: UnitPoint(x: 1.2 + x * 0.8, y: 1 + y * 0.3))
                    .blendMode(.colorDodge)
                    .opacity(reduceMotion ? 0 : 0.8)
                // Sparkles sit in front of both art layers.
                Canvas { context, size in
                    for i in 0..<22 {
                        let px = CGFloat((i * 37 + 11) % 101) / 101 * size.width
                        let py = CGFloat((i * 61 + 7) % 103) / 103 * size.height
                        let r = w * (i.isMultiple(of: 4) ? 0.004 : 0.002)
                        context.fill(Path(ellipseIn: CGRect(x: px, y: py, width: r * 2, height: r * 2)),
                                     with: .color(.yellow.opacity(0.65)))
                    }
                }
                .offset(x: x * w * 0.055, y: y * h * 0.035)
                VStack {
                    Text("地")
                        .font(.system(size: w * 0.17, weight: .semibold, design: .serif))
                        .foregroundStyle(LinearGradient(colors: [.white, Color(red: 1, green: 0.83, blue: 0.42), .white],
                                                        startPoint: .topLeading, endPoint: .bottomTrailing))
                        .shadow(color: .black.opacity(0.85), radius: 3, y: 2)
                    Spacer()
                }
                .padding(.top, w * 0.055)
                RoundedRectangle(cornerRadius: metrics.radius)
                    .strokeBorder(LinearGradient(colors: [Color(white: 0.7), Color(white: 0.12),
                                                          Color(white: 0.4), Color(white: 0.1), Color(white: 0.7)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: w * 0.021)
                RoundedRectangle(cornerRadius: max(2, metrics.radius - w * 0.025))
                    .strokeBorder(LinearGradient(colors: [.white, .yellow.opacity(0.7), .brown, .yellow.opacity(0.7)],
                                                 startPoint: UnitPoint(x: 0.2 + x * 0.5, y: 0),
                                                 endPoint: .bottomTrailing), lineWidth: w * 0.004)
                    .padding(w * 0.025)
            }
            .frame(width: w, height: h)
            .clipShape(RoundedRectangle(cornerRadius: metrics.radius))
        }
        .aspectRatio(2.0 / 3.0, contentMode: .fit)
        .background {
            RoundedRectangle(cornerRadius: metrics.radius)
                .fill(Color(white: 0.12)).offset(y: metrics.showsDetails ? 3 : 1)
        }
        .shadow(color: .black.opacity(0.4), radius: metrics.shadowRadius, y: metrics.shadowY)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(card.displayName(mode))。\(mode.phantomCard)")
    }

    /// Foil flecks live behind the fox, so even the brightest glints do not
    /// obscure its face. Fixed seeds keep the pattern stable while dragging.
    private func backgroundGlitter(width: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        Canvas { context, size in
            let colors: [Color] = [Color(red: 1, green: 0.86, blue: 0.38),
                                   .white, .mint, Color(red: 0.78, green: 0.68, blue: 1)]
            for i in 0..<190 {
                let px = CGFloat((i * 73 + 19) % 251) / 251 * size.width
                let py = CGFloat((i * 137 + 43) % 257) / 257 * size.height
                let phase = Double(i) * 1.71 + Double(x) * 5 + Double(y) * 3
                let brightness = 0.45 + 0.55 * pow((sin(phase) + 1) / 2, 3)
                let star = i.isMultiple(of: 9)
                let radius = width * (star ? 0.014 : 0.0025)
                let center = CGPoint(x: px, y: py)
                let color = colors[i % colors.count]
                if star {
                    let halo = CGRect(x: px - radius * 3, y: py - radius * 3,
                                      width: radius * 6, height: radius * 6)
                    context.fill(Path(ellipseIn: halo), with: .radialGradient(
                        Gradient(colors: [color.opacity(brightness * 0.55), .clear]),
                        center: center, startRadius: 0, endRadius: radius * 3))
                    var sparkle = Path()
                    sparkle.move(to: CGPoint(x: px, y: py - radius * 1.7))
                    sparkle.addLine(to: CGPoint(x: px + radius * 0.24, y: py - radius * 0.24))
                    sparkle.addLine(to: CGPoint(x: px + radius, y: py))
                    sparkle.addLine(to: CGPoint(x: px + radius * 0.24, y: py + radius * 0.24))
                    sparkle.addLine(to: CGPoint(x: px, y: py + radius * 1.7))
                    sparkle.addLine(to: CGPoint(x: px - radius * 0.24, y: py + radius * 0.24))
                    sparkle.addLine(to: CGPoint(x: px - radius, y: py))
                    sparkle.addLine(to: CGPoint(x: px - radius * 0.24, y: py - radius * 0.24))
                    sparkle.closeSubpath()
                    context.fill(sparkle, with: .color(.white.opacity(brightness)))
                } else {
                    context.fill(Path(ellipseIn: CGRect(x: px, y: py, width: radius * 2, height: radius * 2)),
                                 with: .color(color.opacity(brightness)))
                }
            }
        }
        .blendMode(.screen)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
