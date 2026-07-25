import AVFoundation
import Foundation

/// Reads question text aloud (CLAUDE.md §7).
///
/// `AVSpeechSynthesizer` runs entirely on device, so this costs nothing and
/// sends nothing anywhere. It is a free feature and must stay one: a child who
/// cannot read hiragana yet has no way to play without it.
@Observable
final class SpeechService {
    static let shared = SpeechService()

    private let synthesizer = AVSpeechSynthesizer()

    private init() {}

    func speak(_ text: String) {
        guard !text.isEmpty else { return }
        // Cut off whatever is still playing; the newest question is the one
        // that matters.
        synthesizer.stopSpeaking(at: .immediate)

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP")
        // Slower than default on purpose — at the default rate children in the
        // target age range cannot follow the prefecture names.
        utterance.rate = 0.42
        utterance.pitchMultiplier = 1.05
        utterance.postUtteranceDelay = 0
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}
