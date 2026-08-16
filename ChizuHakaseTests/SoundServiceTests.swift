import Testing

@testable import ChizuHakase

/// The correct-answer cue rises with a combo (CLAUDE.md §5's combo, §12's
/// "never shrill"): one major scale, held at the octave.
struct SoundServiceTests {

    /// A single correct answer is not a run yet, and neither is the answer
    /// that follows a fumble (the combo is 0 there) — both get the base cue.
    @Test func baseNoteBeforeARun() {
        #expect(SoundService.semitoneRise(forCombo: 0) == 0)
        #expect(SoundService.semitoneRise(forCombo: 1) == 0)
    }

    /// Do-re-mi, one step per clean answer: the whole point is that a run
    /// sounds like a melody being climbed, not a random pitch wobble.
    @Test func climbsAMajorScale() {
        let rises = (2...8).map { SoundService.semitoneRise(forCombo: $0) }
        #expect(rises == [2, 4, 5, 7, 9, 11, 12])
    }

    /// Past the octave the cue holds instead of climbing on into a whistle.
    @Test func holdsTheOctave() {
        #expect(SoundService.semitoneRise(forCombo: 9) == 12)
        #expect(SoundService.semitoneRise(forCombo: 47) == 12)
    }

    /// Garbage in, base note out — a negative combo must not index below the
    /// scale.
    @Test func negativeComboIsTheBaseNote() {
        #expect(SoundService.semitoneRise(forCombo: -3) == 0)
    }
}
