import AudioToolbox
import AVFoundation
import Foundation

/// Short feedback sounds.
///
/// The quiz cues are synthesised in-process rather than shipped as audio
/// files: that set is four short tones, and generating them keeps the bundle
/// free of binary assets that would need licence tracking for a
/// Kids-category release. The navigation taps are the exception — a supplied
/// recording whose shape a tone pair does not reproduce, bundled as tap.caf
/// and baked to 44.1 kHz mono. Forward and back currently share the one
/// recording; the two cue names survive so they can diverge again without
/// touching the call sites.
final class SoundService {
    static let shared = SoundService()

    enum Cue: Hashable {
        /// Played from a bundled recording rather than from notes.
        case decide, cancel
        case correct, wrong, star, cardWin

        /// (frequencies in Hz, seconds per note); nil for recorded cues.
        var notes: ([Double], Double)? {
            switch self {
            case .decide, .cancel: nil
            // Rising major third: unambiguously "yes" without being shrill.
            case .correct: ([660, 880], 0.09)
            // Gentle low blip. Deliberately not a buzzer — a wrong tap should
            // read as "not that one", never as a scolding (CLAUDE.md §12).
            case .wrong: ([300, 260], 0.07)
            case .star: ([784, 988, 1175], 0.10)
            case .cardWin: ([523, 659, 784, 1047], 0.08)
            }
        }

        /// Bundled file name for the recorded cues.
        var fileName: String? {
            switch self {
            case .decide, .cancel: "tap"
            default: nil
            }
        }
    }

    /// How far the correct cue rises for a running combo, in semitones.
    ///
    /// One major scale, do to do: each clean answer climbs a step, so a run
    /// *sounds* like it is going somewhere before the child can read the
    /// combo badge. From the octave on it holds — the cue has to keep
    /// reading as "yes", and climbing forever turns yes into a whistle.
    /// Combo 0 and 1 are the base note: one correct answer is not yet a
    /// run, and an answer after a fumble starts over where the scale does.
    static func semitoneRise(forCombo combo: Int) -> Int {
        let scale = [0, 2, 4, 5, 7, 9, 11, 12]
        return scale[min(max(combo - 1, 0), scale.count - 1)]
    }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var started = false

    private init() {
        // The voice input mode flips the audio session to .record and back,
        // which invalidates a running engine — afterwards it either reports
        // stopped or keeps "running" with no output, and the correct-answer
        // sound goes silently missing. Tear it down on the system's
        // notification so the next play() rebuilds under the session as it
        // is by then.
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { @Sendable [weak self] _ in
            Task { @MainActor in self?.reset() }
        }
    }

    private func reset() {
        engine.stop()
        started = false
    }

    /// Builds the engine and decodes the tap recording before the first tap
    /// needs them. Both otherwise happen synchronously inside the first
    /// button action, and starting an AVAudioEngine takes long enough there
    /// to read as input lag. Runs regardless of the sound setting: the
    /// toggle can flip at any moment, and an idle engine on the ambient
    /// session just renders silence.
    func warmUp() {
        _ = recordedBuffer(for: .decide)
        try? start()
    }

    /// `semitonesUp` transposes the synthesised cues; recorded cues play as
    /// recorded — resampling a real tap would just make it chipmunked.
    func play(_ cue: Cue, enabled: Bool, semitonesUp: Int = 0) {
        guard enabled else { return }
        guard let buffer = makeBuffer(for: cue, semitonesUp: semitonesUp) else { return }
        do {
            try start()
            player.scheduleBuffer(buffer, at: nil, options: .interrupts)
            player.play()
        } catch {
            // Sound is a nicety; failing to produce it must never interrupt play.
        }
    }

    private func start() throws {
        guard !started else {
            if !engine.isRunning { try engine.start() }
            return
        }
        // The app should never stop a family's music.
        AudioSession.configureForPlayback()

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        try engine.start()
        started = true
    }

    private let sampleRate: Double = 44_100
    private var format: AVAudioFormat? {
        AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
    }

    /// Recorded cues, decoded once and kept. Keyed by file name, not by cue,
    /// so cues that share a recording share the one decoded buffer.
    private var recordedBuffers: [String: AVAudioPCMBuffer] = [:]

    /// The files are baked to 44.1 kHz mono so their processing format is
    /// exactly the format the player node was connected with. The guard
    /// re-checks that rather than trusting the asset: scheduling a mismatched
    /// buffer raises an exception, which would turn a re-exported file into a
    /// crash on the first tap.
    private func recordedBuffer(for cue: Cue) -> AVAudioPCMBuffer? {
        guard let name = cue.fileName else { return nil }
        if let cached = recordedBuffers[name] { return cached }
        guard let url = Bundle.main.url(forResource: name, withExtension: "caf"),
              let file = try? AVAudioFile(forReading: url),
              file.processingFormat == format,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: AVAudioFrameCount(file.length))
        else { return nil }
        do { try file.read(into: buffer) } catch { return nil }
        recordedBuffers[name] = buffer
        return buffer
    }

    private func makeBuffer(for cue: Cue, semitonesUp: Int = 0) -> AVAudioPCMBuffer? {
        guard let (baseFrequencies, noteDuration) = cue.notes else {
            return recordedBuffer(for: cue)
        }
        // Equal-temperament transpose: the cue keeps its own interval and
        // length, only its register moves.
        let factor = pow(2, Double(semitonesUp) / 12)
        let frequencies = baseFrequencies.map { $0 * factor }
        guard let format else { return nil }
        let framesPerNote = AVAudioFrameCount(sampleRate * noteDuration)
        let total = framesPerNote * AVAudioFrameCount(frequencies.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: total),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = total

        var frame = 0
        for frequency in frequencies {
            for i in 0..<Int(framesPerNote) {
                let t = Double(i) / sampleRate
                // Short attack/release envelope so the note does not click.
                let progress = Double(i) / Double(framesPerNote)
                let envelope = min(1, progress * 12) * min(1, (1 - progress) * 6)
                channel[frame] = Float(sin(2 * .pi * frequency * t) * envelope * 0.22)
                frame += 1
            }
        }
        return buffer
    }
}
