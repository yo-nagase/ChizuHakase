import AVFoundation
import Foundation

/// Reads question text aloud (CLAUDE.md §7).
///
/// `AVSpeechSynthesizer` runs entirely on device, so this costs nothing and
/// sends nothing anywhere. It is a free feature and must stay one: a child who
/// cannot read hiragana yet has no way to play without it.
// Explicit @MainActor: inheriting NSObject would otherwise pull the class to
// its superclass's (non-)isolation instead of the project default.
@Observable
@MainActor
final class SpeechService: NSObject {
    static let shared = SpeechService()

    private let synthesizer = AVSpeechSynthesizer()

    /// Whether an announcement is still being spoken, mirrored into observable
    /// state. The quiz holds the microphone back until this goes false: armed
    /// any earlier, the recogniser hears the app say the answer's own name.
    private(set) var isSpeaking = false

    /// Resolved once, at first use. A voice downloaded while the app is running
    /// is picked up the next launch, which is soon enough for something nobody
    /// changes twice.
    private let voice: AVSpeechSynthesisVoice?

    private override init() {
        voice = SpeechService.bestJapaneseVoice()
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        speak([text])
    }

    /// Reads phrases with a beat between them.
    ///
    /// Run together in one utterance they arrive as one breath —
    /// 「どこかな?なまえを えらんでね」 — which is the difference between being asked
    /// a question and being talked at.
    func speak(_ phrases: [String]) {
        let phrases = phrases.filter { !$0.isEmpty }
        guard !phrases.isEmpty else { return }
        // Cut off whatever is still playing; the newest question is the one
        // that matters.
        synthesizer.stopSpeaking(at: .immediate)

        for (index, phrase) in phrases.enumerated() {
            let utterance = AVSpeechUtterance(string: phrase)
            utterance.voice = voice
            // Slower than default on purpose — at the default rate children in
            // the target age range cannot follow the prefecture names.
            utterance.rate = 0.42
            // The compact voice is thin, and lifting it slightly makes it
            // friendlier. An enhanced or premium voice is a recording of a
            // person: shifting its pitch puts a ring around it, so it is left
            // where it was recorded.
            utterance.pitchMultiplier = isCompact ? 1.05 : 1.0
            utterance.postUtteranceDelay = index == phrases.count - 1 ? 0 : 0.3
            synthesizer.speak(utterance)
        }
        isSpeaking = true
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    private var isCompact: Bool { (voice?.quality ?? .default) == .default }

    /// Re-reads the synthesizer rather than counting utterances down: a queued
    /// utterance that is cancelled without a callback would leave a counter
    /// stuck above zero, and the mirror would say "speaking" forever.
    private func refreshSpeaking() {
        isSpeaking = synthesizer.isSpeaking
    }
}

extension SpeechService: AVSpeechSynthesizerDelegate {
    // Delivered on the synthesizer's queue, so both are non-isolated and only
    // the main-actor hop touches state — same shape as the recognition
    // handler in VoiceInputService.
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.refreshSpeaking() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.refreshSpeaking() }
    }
}

// MARK: - Choosing the voice

extension SpeechService {
    /// One installed voice, reduced to the properties the choice depends on.
    ///
    /// Separated from `AVSpeechSynthesisVoice` so the rule can be tested: which
    /// voices exist depends on what the machine running the tests happens to
    /// have downloaded, and a test that asserts on that passes or fails by
    /// accident.
    nonisolated struct VoiceOption: Equatable {
        var identifier: String
        var language: String
        var quality: AVSpeechSynthesisVoiceQuality
        var isNovelty = false
        var isPersonal = false

        /// Eloquence voices are formant-synthesised screen-reader voices —
        /// the gravel-voiced Eddy, Grandpa and friends. They report the same
        /// default quality as the compact voice and carry no novelty trait,
        /// so the name prefix is the only thing that tells them apart. Left
        /// in, the identifier tie-break chose them *over* the compact voice
        /// (`eloquence` < `voice` alphabetically) on every device without a
        /// downloaded enhanced voice.
        var isEloquence: Bool { identifier.hasPrefix("com.apple.eloquence.") }
    }

    /// The best Japanese voice among `options`, or nil to let the system decide.
    ///
    /// Highest quality wins. Ties break on the identifier so a device reads in
    /// the same voice every launch rather than picking whatever the list handed
    /// back first. Novelty voices are jokes, a personal voice belongs to
    /// whoever recorded it, and an Eloquence voice is a screen reader's robot —
    /// none of them is what a five-year-old should be handed by a quiz about
    /// Aichi.
    nonisolated static func pick(from options: [VoiceOption]) -> VoiceOption? {
        options
            .filter {
                $0.language.hasPrefix("ja")
                    && !$0.isNovelty && !$0.isPersonal && !$0.isEloquence
            }
            .sorted {
                $0.quality.rawValue == $1.quality.rawValue
                    ? $0.identifier < $1.identifier
                    : $0.quality.rawValue > $1.quality.rawValue
            }
            .first
    }

    /// Why this exists at all: `AVSpeechSynthesisVoice(language: "ja-JP")` returns
    /// the system default, and on a device where nobody has been into
    /// 設定 → アクセシビリティ → 読み上げコンテンツ → 声 that is the *compact* Kyoko —
    /// a few megabytes of stitched samples, and it sounds like it. The enhanced
    /// and premium Japanese voices are ordinary free downloads that plenty of
    /// devices already have, so the only thing between this app and a much
    /// better reading was asking for them by name.
    static func bestJapaneseVoice() -> AVSpeechSynthesisVoice? {
        let installed = AVSpeechSynthesisVoice.speechVoices()
        let options = installed.map {
            VoiceOption(identifier: $0.identifier,
                        language: $0.language,
                        quality: $0.quality,
                        isNovelty: $0.voiceTraits.contains(.isNoveltyVoice),
                        isPersonal: $0.voiceTraits.contains(.isPersonalVoice))
        }
        guard let best = pick(from: options) else {
            return AVSpeechSynthesisVoice(language: "ja-JP")
        }
        return installed.first { $0.identifier == best.identifier }
    }
}
