import AVFoundation
import Foundation
import OSLog
import Speech

/// "Answer by voice" mode (CLAUDE.md §7).
///
/// On-device recognition only. `requiresOnDeviceRecognition` is set before the
/// request is ever started, so audio never leaves the device — which is what
/// keeps the privacy label at "no data collected". If a device cannot do
/// on-device Japanese, the mode is hidden rather than silently downgraded to a
/// server round trip.
@Observable
final class VoiceInputService {

    private static let log = Logger(subsystem: "com.wakuwaku.chizu", category: "VoiceInput")

    enum Availability: Equatable {
        case available
        /// Recogniser missing, or the device cannot do it on-device.
        case unsupported
        /// Permission refused. We fall back to tapping and never ask again.
        case denied
    }

    private(set) var availability: Availability = .unsupported
    private(set) var isListening = false
    private(set) var transcript = ""

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    /// Held here rather than captured by the recognition handler, which has to
    /// stay non-isolated and so cannot carry a main-actor closure across.
    private var onResult: ((String) -> Void)?

    /// Contextual vocabulary: the answer is always one of 47 fixed words.
    private var vocabulary: [String] = []

    func configure(vocabulary: [String]) {
        self.vocabulary = vocabulary
    }

    // MARK: - Availability

    /// Cheap check that does not prompt. Used to decide whether to *show* the
    /// mode at all.
    var isPossibleOnThisDevice: Bool {
        guard let recognizer, recognizer.isAvailable else { return false }
        return recognizer.supportsOnDeviceRecognition
    }

    /// Asks for the two permissions the mode needs, in order.
    ///
    /// Every handler here is `@Sendable` on purpose. This type is MainActor
    /// isolated, and the project compiles with MainActor-by-default, so a bare
    /// closure literal inherits that isolation — but TCC calls these back on its
    /// own queue, and Swift 6 checks the executor before running the body. The
    /// result was a hard crash in `dispatch_assert_queue` the first time a child
    /// switched the mode on. `@Sendable` makes the closure non-isolated, which
    /// is the truth: it runs wherever the system calls it.
    func requestAccess() async {
        guard isPossibleOnThisDevice else {
            availability = .unsupported
            return
        }
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { @Sendable status in
                continuation.resume(returning: status)
            }
        }
        guard speech == .authorized else {
            availability = .denied
            return
        }
        let mic = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { @Sendable granted in
                continuation.resume(returning: granted)
            }
        }
        availability = mic ? .available : .denied
    }

    // MARK: - Listening

    func start(onResult: @escaping (String) -> Void) {
        guard availability == .available, !isListening, let recognizer else { return }
        stop()

        let request = SFSpeechAudioBufferRecognitionRequest()
        // Both of these are load-bearing for the privacy promise.
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.contextualStrings = vocabulary
        self.request = request
        self.onResult = onResult

        do {
            try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement,
                                                            options: .duckOthers)
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)

            let input = engine.inputNode
            input.removeTap(onBus: 0)
            // The tap runs on the audio render thread, which is the one place
            // that must never wait for the main actor. Handing the buffer
            // straight to the request is what the API is designed for; the
            // unsafe annotation is the acknowledgement that this reference
            // crosses threads deliberately.
            nonisolated(unsafe) let sink = request
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) {
                @Sendable buffer, _ in
                sink.append(buffer)
            }
            engine.prepare()
            try engine.start()
            isListening = true

            task = recognizer.recognitionTask(with: request) { @Sendable [weak self] result, error in
                // Called on Speech's own queue. Nothing here may touch self
                // directly — only Sendable values cross, and the state change
                // hops back to the main actor.
                let heard = result?.bestTranscription.formattedString
                let finished = error != nil || result?.isFinal == true
                Task { @MainActor in
                    self?.receive(heard: heard, finished: finished)
                }
            }
        } catch {
            Self.log.error("could not start listening: \(error.localizedDescription, privacy: .public)")
            stop()
        }
    }

    /// Main-actor landing point for whatever the recogniser heard.
    private func receive(heard: String?, finished: Bool) {
        if let heard {
            transcript = heard
            onResult?(heard)
        }
        if finished { stop() }
    }

    func stop() {
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        onResult = nil
        isListening = false
        // Hand the session back. Listening puts it in .record, and leaving it
        // there silently killed the read-aloud for the rest of the session —
        // one use of the microphone and a child who cannot read hiragana had no
        // way left to hear the question.
        AudioSession.configureForPlayback()
    }
}

/// Matches what was heard against a prefecture name.
///
/// Recognition returns kanji as often as kana, and children drop the
/// 県/都/府 suffix constantly, so both spellings and both forms have to be
/// accepted (CLAUDE.md §7).
nonisolated enum PrefectureNameMatcher {

    /// Administrative suffixes that carry no information for the quiz.
    private static let suffixes = ["けん", "県", "ふ", "府", "どう", "道", "と", "都"]

    /// Whitespace, punctuation and katakana folded away. Deliberately does
    /// *not* touch suffixes — see `strippingSuffix`.
    static func normalize(_ input: String) -> String {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        for junk in [" ", "　", "、", "。", "！", "?", "？"] {
            text = text.replacingOccurrences(of: junk, with: "")
        }
        // Katakana -> hiragana so「トウキョウ」and「とうきょう」agree.
        if let folded = text.applyingTransform(.hiraganaToKatakana, reverse: true) {
            text = folded
        }
        return text
    }

    /// The name with its administrative suffix removed, or nil if it has none.
    ///
    /// Only ever applied to build the *accepted* forms — never used as the sole
    /// comparison key. Doing that would break Kyoto: 「きょうとふ」minus 「ふ」is
    /// 「きょうと」, but naively stripping 「と」 from a child saying 「きょうと」
    /// leaves 「きょう」 and the two would never meet.
    static func strippingSuffix(_ normalized: String) -> String? {
        for suffix in suffixes where normalized.hasSuffix(suffix) {
            let stripped = String(normalized.dropLast(suffix.count))
            if !stripped.isEmpty { return stripped }
        }
        return nil
    }

    /// Every spelling that should be accepted for one prefecture.
    static func acceptedForms(for prefecture: Prefecture) -> Set<String> {
        var forms: Set<String> = []
        for base in [prefecture.kana, prefecture.name] {
            let normalized = normalize(base)
            guard !normalized.isEmpty else { continue }
            forms.insert(normalized)
            if let stripped = strippingSuffix(normalized) { forms.insert(stripped) }
        }
        return forms
    }

    /// True when `heard` names `prefecture`, in kana or kanji, with or without
    /// the administrative suffix.
    static func matches(_ heard: String, prefecture: Prefecture) -> Bool {
        let spoken = normalize(heard)
        guard !spoken.isEmpty else { return false }
        let forms = acceptedForms(for: prefecture)
        if forms.contains(spoken) { return true }
        // Also try the spoken form without its suffix, for a child who adds one
        // the official name does not have (「ほっかいどうけん」).
        if let stripped = strippingSuffix(spoken), forms.contains(stripped) { return true }
        return false
    }

    /// The prefecture named by `heard`, if exactly one matches.
    static func match(_ heard: String, among prefectures: [Prefecture]) -> Prefecture? {
        let hits = prefectures.filter { matches(heard, prefecture: $0) }
        return hits.count == 1 ? hits[0] : nil
    }
}
