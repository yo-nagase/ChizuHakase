import SwiftUI

/// Gate in front of anything that costs money or leaves the app
/// (CLAUDE.md §8).
///
/// A multiplication question a 5–9 year old cannot do, entered on a keypad.
/// Never spoken aloud, and a wrong answer is answered with a new question
/// rather than a telling-off.
struct ParentalGateView: View {
    @Environment(\.dismiss) private var dismiss

    var onPassed: () -> Void = {}

    @State private var left = Int.random(in: 3...9)
    @State private var right = Int.random(in: 3...9)
    @State private var entry = ""
    @State private var shake = 0

    private var answer: Int { left * right }

    var body: some View {
        VStack(spacing: 20) {
            Text("おうちのひとに きいてね")
                .font(AppFont.rounded(15, relativeTo: .subheadline))
                .foregroundStyle(Palette.ink.opacity(0.6))

            Text("\(left) × \(right) = ?")
                .font(AppFont.rounded(38, relativeTo: .largeTitle))
                .foregroundStyle(Palette.ink)
                // Speaking this would hand the answer to the child.
                .accessibilityLabel("ペアレンタルゲート")

            Text(entry.isEmpty ? " " : entry)
                .font(AppFont.rounded(30, relativeTo: .title))
                .foregroundStyle(Palette.ink)
                .frame(minWidth: 130, minHeight: 54)
                .background(.white, in: RoundedRectangle(cornerRadius: 16))
                .modifier(GateShake(trigger: shake))

            keypad

            Button("とじる") { dismiss() }
                .font(AppFont.rounded(15, relativeTo: .footnote))
                .foregroundStyle(Palette.ink.opacity(0.5))
                .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background)
        .presentationDetents([.medium])
    }

    private var keypad: some View {
        let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "←", "0", "OK"]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10),
                                        count: 3), spacing: 10) {
            ForEach(keys, id: \.self) { key in
                Button { tap(key) } label: {
                    Text(key)
                        .font(AppFont.rounded(22, relativeTo: .title3))
                        .foregroundStyle(key == "OK" ? .white : Palette.ink)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(key == "OK" ? Palette.orange : Color.white,
                                    in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: 280)
    }

    private func tap(_ key: String) {
        switch key {
        case "←":
            if !entry.isEmpty { entry.removeLast() }
        case "OK":
            if Int(entry) == answer {
                onPassed()
                dismiss()
            } else {
                // New question, no reprimand.
                shake += 1
                entry = ""
                left = Int.random(in: 3...9)
                right = Int.random(in: 3...9)
            }
        default:
            if entry.count < 3 { entry.append(key) }
        }
    }
}

private struct GateShake: ViewModifier {
    let trigger: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, dx in
                view.offset(x: dx)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(-8, duration: 0.08)
                    CubicKeyframe(8, duration: 0.08)
                    CubicKeyframe(0, duration: 0.08)
                }
            }
        }
    }
}

#Preview {
    ParentalGateView()
}
