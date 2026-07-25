import SwiftUI
import Testing

@testable import WakuwakuChizu

/// The my-map colour ramp (CLAUDE.md §5).
///
/// The legend used to be drawn from one hue while the map tinted each
/// prefecture with its own, so the four swatches promised colours the country
/// never showed. Everything now comes from `MasteryStyle.fill(level:)`, and
/// these pin the properties that made the mismatch possible.
@MainActor
struct MasteryStyleTests {

    private func rgba(_ color: Color) -> [CGFloat] {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return [r, g, b, a]
    }

    /// The whole point: one level, one colour, whoever is asking.
    @Test func aLevelHasExactlyOneColour() {
        for level in 0...GameRules.maxMastery {
            #expect(rgba(MasteryStyle.fill(level: level))
                    == rgba(MasteryStyle.fill(level: level)))
        }
    }

    /// The map reads its fill through `appearance`, the legend calls `fill`
    /// directly. If those ever disagree the legend is lying again.
    @Test func theMapAndTheLegendAgreeAtEveryLevel() {
        for level in 0...GameRules.maxMastery {
            var save = SaveData()
            save.mastery[1] = level
            let onTheMap = MasteryStyle.appearance(for: 1, save: save).fill
            #expect(rgba(onTheMap) == rgba(MasteryStyle.fill(level: level)),
                    "level \(level) differs between the map and the legend")
        }
    }

    /// Mastery is the only thing colour encodes here, so two prefectures at the
    /// same level must look identical — this is what stopped being true when
    /// the fill was keyed on the prefecture code.
    @Test func twoPrefecturesAtTheSameLevelLookTheSame() {
        var save = SaveData()
        save.mastery[1] = 2      // 1 % 8 and 13 % 8 differ, which used to matter
        save.mastery[13] = 2
        #expect(rgba(MasteryStyle.appearance(for: 1, save: save).fill)
                == rgba(MasteryStyle.appearance(for: 13, save: save).fill))
    }

    @Test func everyStepIsDistinct() {
        let colours = (0...GameRules.maxMastery).map { rgba(MasteryStyle.fill(level: $0)) }
        for (i, a) in colours.enumerated() {
            for (j, b) in colours.enumerated() where j > i {
                #expect(a != b, "levels \(i) and \(j) are the same colour")
            }
        }
    }

    /// キラキラ is flat gold, the same gold the legend chip uses.
    @Test func topLevelIsTheGoldToken() {
        #expect(rgba(MasteryStyle.fill(level: GameRules.maxMastery)) == rgba(Palette.gold))
    }

    /// Sparkling drives the sheen. It must be on at the top and nowhere else,
    /// or a half-learned prefecture would shimmer as if it were finished.
    @Test func onlyTheTopLevelSparkles() {
        for level in 0...GameRules.maxMastery {
            var save = SaveData()
            save.mastery[1] = level
            #expect(MasteryStyle.appearance(for: 1, save: save).isSparkling
                    == (level >= GameRules.maxMastery))
        }
    }

    /// Nothing on this screen is a stuck sticker any more; the outline stays
    /// the same printed edge at every level so the country reads as one map.
    @Test func noLevelGetsTheDieCutEdge() {
        for level in 0...GameRules.maxMastery {
            var save = SaveData()
            save.mastery[1] = level
            #expect(!MasteryStyle.appearance(for: 1, save: save).isStuck)
        }
    }

    @Test func unansweredIsTheGreyTokenNotAColour() {
        #expect(rgba(MasteryStyle.fill(level: 0)) == rgba(Palette.unlearned))
    }
}
