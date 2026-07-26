import AVFoundation
import Testing

@testable import WakuwakuChizu

/// Who owns the audio session, and who has to give it back.
///
/// Read-aloud is the accessibility floor for a child who cannot read hiragana
/// yet (CLAUDE.md §7), and it plays through whatever category was configured
/// last. Listening puts the session in `.record`, where a synthesizer is
/// inaudible — so the invariant worth pinning is that nothing leaves it there.
@MainActor
struct AudioSessionTests {

    @Test func playbackConfigurationIsAmbientAndMixes() {
        AudioSession.configureForPlayback()
        #expect(AudioSession.category == .ambient)
        #expect(AVAudioSession.sharedInstance().categoryOptions.contains(.mixWithOthers),
                "the app must not stop a family's music")
    }

    /// The regression this exists for: one use of the microphone used to leave
    /// the session in `.record` for good, and the question could no longer be
    /// read to a child who could not read it themselves.
    @Test func stoppingListeningLeavesTheSessionAbleToSpeak() throws {
        try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement)
        #expect(AudioSession.category == .record)

        VoiceInputService().stop()

        #expect(AudioSession.category == .ambient,
                "listening did not hand the session back")
    }

    /// Called on every sound effect and on every stop; it has to be safe to
    /// call over and over.
    @Test func configuringRepeatedlyIsHarmless() {
        for _ in 0..<5 { AudioSession.configureForPlayback() }
        #expect(AudioSession.category == .ambient)
    }
}
