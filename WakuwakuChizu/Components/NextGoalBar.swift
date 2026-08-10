import SwiftUI

/// The little bar under a 「あと◯」 line: the current rung, filling toward the
/// next tier (CLAUDE.md §5).
///
/// The fill is coloured as the thing being worked toward — silver, gold, or
/// the rainbow — so the bar answers "toward what?" at a glance, before the
/// label is read or can be read at all.
///
/// Decorative on purpose: the label already carries the number, so the bar is
/// hidden from VoiceOver rather than read out as a second, vaguer copy of it.
struct NextGoalBar: View {
    let goal: GameRules.NextGoal
    /// The groove the fill sits in. Ink-tinted for paper; the enlarged card
    /// passes a lighter one to stay visible on its dark backdrop.
    var track: Color = Palette.ink.opacity(0.12)

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                // A fresh rung draws no fill at all. An empty groove says
                // "everything still to come" better than a sliver that looks
                // like a rendering mistake.
                if goal.fraction > 0 {
                    Capsule().fill(fill)
                        .frame(width: geo.size.width * goal.fraction)
                }
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }

    private var fill: AnyShapeStyle {
        switch goal {
        case .wins(_, let tier) where tier == .gold:
            AnyShapeStyle(Palette.gold)
        case .wins:
            AnyShapeStyle(Palette.silverMark)
        // Toward — or at — the rainbow, the fill is the §9 prefecture palette,
        // same as every other holographic surface in the app.
        case .streak, .done:
            AnyShapeStyle(LinearGradient(colors: Palette.prefectureFills,
                                         startPoint: .leading, endPoint: .trailing))
        }
    }
}

#Preview {
    VStack(spacing: 14) {
        NextGoalBar(goal: .wins(2, to: .silver))
        NextGoalBar(goal: .wins(3, to: .gold))
        NextGoalBar(goal: .streak(4))
        NextGoalBar(goal: .streak(GameRules.rainbowStreak))
        NextGoalBar(goal: .done)
    }
    .frame(width: 150)
    .padding()
    .background(Palette.background)
}
