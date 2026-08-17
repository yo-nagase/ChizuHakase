import AVFoundation
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

    /// Do-re-mi, one step per clean answer, for two whole octaves: the whole
    /// point is that a run sounds like a melody being climbed, not a random
    /// pitch wobble — and a long run keeps climbing instead of flattening
    /// out after seven answers.
    @Test func climbsAMajorScale() {
        let rises = (2...15).map { SoundService.semitoneRise(forCombo: $0) }
        #expect(rises == [2, 4, 5, 7, 9, 11, 12, 14, 16, 17, 19, 21, 23, 24])
    }

    /// Past the second octave the cue holds instead of climbing on into a
    /// whistle.
    @Test func holdsTheSecondOctave() {
        #expect(SoundService.semitoneRise(forCombo: 16) == 24)
        #expect(SoundService.semitoneRise(forCombo: 47) == 24)
    }

    /// Garbage in, base note out — a negative combo must not index below the
    /// scale.
    @Test func negativeComboIsTheBaseNote() {
        #expect(SoundService.semitoneRise(forCombo: -3) == 0)
    }

    // MARK: - Navigation taps

    /// Going forward slides up, going back slides down: the direction is
    /// audible before a child can read any label, and neither end is a
    /// buzzer. Both are synthesised sweeps like every other cue — no bundled
    /// recording left to licence-track.
    @Test func navigationCuesAreDirectionalSweeps() throws {
        let decide = try #require(SoundService.Cue.decide.sweep)
        let cancel = try #require(SoundService.Cue.cancel.sweep)
        #expect(decide.to > decide.from, "forward should rise")
        #expect(cancel.to < cancel.from, "back should fall")
        #expect(SoundService.Cue.correct.sweep == nil,
                "the quiz cues keep their note pairs")
    }

    /// Bubble pops, not whistles: both sweeps stay inside a register that is
    /// bright without being shrill, and short enough to never delay the next
    /// tap.
    @Test func sweepsStayGentleAndShort() throws {
        for cue in [SoundService.Cue.decide, .cancel] {
            let sweep = try #require(cue.sweep)
            #expect(min(sweep.from, sweep.to) >= 200)
            #expect(max(sweep.from, sweep.to) <= 1500)
            #expect(sweep.duration <= 0.2)
        }
    }

    /// The sweeps must actually render: a non-empty buffer whose peak sits at
    /// the same comfortable level as the synthesised quiz cues.
    @Test func sweepsRenderQuietBuffers() throws {
        for cue in [SoundService.Cue.decide, .cancel] {
            let buffer = try #require(SoundService.shared.makeBuffer(for: cue))
            #expect(buffer.frameLength > 0)
            let channel = try #require(buffer.floatChannelData?[0])
            let peak = (0..<Int(buffer.frameLength))
                .map { abs(channel[$0]) }.max() ?? 0
            #expect(peak > 0, "a silent cue is a broken cue")
            #expect(peak <= 0.3, "a tap must never startle")
        }
    }
}
