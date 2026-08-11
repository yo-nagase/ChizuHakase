import AVFoundation
import Testing

@testable import ChizuHakase

/// Which voice reads the questions (CLAUDE.md §7).
///
/// The rule is tested rather than the outcome: what is installed differs from
/// device to device, so an assertion about the voice actually chosen here would
/// pass or fail by accident.
struct SpeechVoiceTests {
    private typealias Option = SpeechService.VoiceOption

    private let compact = Option(identifier: "ja.compact.Kyoko", language: "ja-JP",
                                 quality: .default)
    private let enhanced = Option(identifier: "ja.enhanced.Kyoko", language: "ja-JP",
                                  quality: .enhanced)
    private let premium = Option(identifier: "ja.premium.Kyoko", language: "ja-JP",
                                 quality: .premium)

    /// The whole point: the system default for a language is the compact voice,
    /// and it is the one nobody would choose on purpose.
    @Test func theBestInstalledQualityWins() {
        #expect(SpeechService.pick(from: [compact, enhanced, premium]) == premium)
        #expect(SpeechService.pick(from: [compact, enhanced]) == enhanced)
        #expect(SpeechService.pick(from: [compact]) == compact)
    }

    @Test func orderOfTheInstalledListDoesNotMatter() {
        #expect(SpeechService.pick(from: [premium, compact, enhanced]) == premium)
        #expect(SpeechService.pick(from: [enhanced, premium, compact]) == premium)
    }

    /// A device reads in the same voice every launch. `speechVoices()` is not
    /// promised in any order, so equal candidates are settled by identifier.
    @Test func tiesAreBrokenTheSameWayEveryTime() {
        let a = Option(identifier: "ja.enhanced.Hattori", language: "ja-JP",
                       quality: .enhanced)
        #expect(SpeechService.pick(from: [enhanced, a]) == a)
        #expect(SpeechService.pick(from: [a, enhanced]) == a)
    }

    @Test func otherLanguagesAreNotCandidates() {
        let english = Option(identifier: "en.premium.Ava", language: "en-US",
                             quality: .premium)
        #expect(SpeechService.pick(from: [english, compact]) == compact)
        #expect(SpeechService.pick(from: [english]) == nil)
    }

    /// Novelty voices are jokes and a personal voice belongs to whoever recorded
    /// it. Neither should read a question to a five-year-old, however high the
    /// quality flag on it is.
    @Test func noveltyAndPersonalVoicesAreSkipped() {
        let novelty = Option(identifier: "ja.novelty.Bahh", language: "ja-JP",
                             quality: .premium, isNovelty: true)
        let personal = Option(identifier: "ja.personal.Someone", language: "ja-JP",
                              quality: .premium, isPersonal: true)
        #expect(SpeechService.pick(from: [novelty, personal, compact]) == compact)
        #expect(SpeechService.pick(from: [novelty, personal]) == nil)
    }

    /// The regression that shipped a robot. Eloquence voices (Eddy, Grandpa, …)
    /// are formant-synthesised screen-reader voices: they report the same
    /// default quality as the compact voice, carry no novelty trait, and their
    /// identifiers sort ahead of `com.apple.voice.…` — so on any device without
    /// a downloaded enhanced voice, the tie-break read every question in Eddy.
    /// Real identifiers on purpose: the only way to tell them apart is by name.
    @Test func eloquenceVoicesAreNeverPicked() {
        let eddy = Option(identifier: "com.apple.eloquence.ja-JP.Eddy",
                          language: "ja-JP", quality: .default)
        let kyoko = Option(identifier: "com.apple.voice.super-compact.ja-JP.Kyoko",
                           language: "ja-JP", quality: .default)
        #expect(SpeechService.pick(from: [eddy, kyoko]) == kyoko)
        #expect(SpeechService.pick(from: [eddy]) == nil,
                "with only Eloquence installed, the system default is still the better reader")
    }

    /// Nil means "no opinion", which leaves `AVSpeechSynthesisVoice(language:)`
    /// to answer. Reading in the system default is far better than not reading.
    @Test func noJapaneseVoiceLeavesTheChoiceToTheSystem() {
        #expect(SpeechService.pick(from: []) == nil)
    }
}
