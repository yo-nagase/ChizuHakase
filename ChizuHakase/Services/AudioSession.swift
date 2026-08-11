import AVFoundation
import OSLog

/// The one place the shared audio session is configured.
///
/// Both the sound effects and the read-aloud play through it, and the voice
/// input mode takes it over while listening. Whoever grabs it last decides
/// whether speech can be heard at all, which is why putting it back is not
/// optional — read-aloud is the accessibility floor for a child who cannot read
/// hiragana yet (CLAUDE.md §7).
nonisolated enum AudioSession {

    private static let log = Logger(subsystem: "com.wakuwaku.chizuhakase", category: "Audio")

    /// Ambient and mixing: the app is a toy, so it plays alongside whatever
    /// else is going on and stays quiet when the ring switch says quiet.
    static func configureForPlayback() {
        do {
            try AVAudioSession.sharedInstance()
                .setCategory(.ambient, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // Losing audio is a degraded experience, never a reason to stop.
            log.error("could not configure audio: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Current category, for tests and for diagnosing a silent app.
    static var category: AVAudioSession.Category {
        AVAudioSession.sharedInstance().category
    }
}
