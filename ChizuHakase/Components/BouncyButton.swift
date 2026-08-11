import SwiftUI

/// Pill button with a solid drop shadow that sinks on press (CLAUDE.md §9).
///
/// The travel is the whole affordance: at this age a button that visibly moves
/// reads as pressable in a way a colour change does not.
struct BouncyButtonStyle: ButtonStyle {
    var background: Color = Palette.orange
    var foreground: Color = .white
    var depth: CGFloat = 4
    var horizontalPadding: CGFloat = 26
    var verticalPadding: CGFloat = 14
    var fontSize: CGFloat = 20

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed && !reduceMotion
        return configuration.label
            .font(AppFont.rounded(fontSize, relativeTo: .body))
            .foregroundStyle(foreground)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(minHeight: 44)
            .background(background, in: Capsule())
            .overlay {
                if configuration.isPressed {
                    Capsule().fill(.black.opacity(0.08))
                }
            }
            .offset(y: pressed ? depth : 0)
            .background(alignment: .bottom) {
                // Darkened shelf under the pill. Composited rather than
                // Color.mix(with:by:), which needs iOS 18 and this app targets 17.
                Capsule()
                    .fill(background)
                    .overlay { Capsule().fill(.black.opacity(0.22)) }
                    .frame(height: 44 + depth)
                    .offset(y: depth)
            }
            .opacity(isEnabled ? 1 : 0.45)
            .animation(.spring(duration: 0.16), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == BouncyButtonStyle {
    static var bouncy: BouncyButtonStyle { BouncyButtonStyle() }

    static func bouncy(_ background: Color,
                       foreground: Color = .white,
                       fontSize: CGFloat = 20) -> BouncyButtonStyle {
        BouncyButtonStyle(background: background, foreground: foreground, fontSize: fontSize)
    }
}

/// Small round icon button (speech, back, settings).
struct CircleIconButtonStyle: ButtonStyle {
    var background: Color = .white
    var foreground: Color = Palette.ink
    var diameter: CGFloat = 48

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: diameter * 0.42))
            .foregroundStyle(foreground)
            .frame(width: diameter, height: diameter)
            .background(background, in: Circle())
            .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(duration: 0.16), value: configuration.isPressed)
    }
}

#Preview {
    VStack(spacing: 24) {
        Button("はじめる") {}.buttonStyle(.bouncy)
        Button("ずかんを みる") {}.buttonStyle(.bouncy(Palette.teal))
        Button("できない") {}.buttonStyle(.bouncy).disabled(true)
        Button("🔊") {}.buttonStyle(CircleIconButtonStyle())
    }
    .padding(40)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Palette.background)
}
