import AudioToolbox
import AVFoundation
import Foundation

/// Short feedback sounds.
///
/// The quiz cues are synthesised in-process rather than shipped as audio
/// files: that set is four short tones, and generating them keeps the bundle
/// free of binary assets that would need licence tracking for a
/// Kids-category release. The navigation taps are the exception — supplied
/// recordings whose shapes a tone pair does not reproduce, bundled as
/// {name}.caf and baked to 44.1 kHz mono.
final class SoundService {
    static let shared = SoundService()

    enum Cue: Hashable {
        /// Played from decide.caf / cancel.caf rather than from notes.
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
            case .decide: "decide"
            case .cancel: "cancel"
            default: nil
            }
        }
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

    func play(_ cue: Cue, enabled: Bool) {
        guard enabled else { return }
        guard let buffer = makeBuffer(for: cue) else { return }
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

    /// Recorded cues, decoded once and kept.
    private var recordedBuffers: [Cue: AVAudioPCMBuffer] = [:]

    /// The files are baked to 44.1 kHz mono so their processing format is
    /// exactly the format the player node was connected with. The guard
    /// re-checks that rather than trusting the asset: scheduling a mismatched
    /// buffer raises an exception, which would turn a re-exported file into a
    /// crash on the first tap.
    private func recordedBuffer(for cue: Cue) -> AVAudioPCMBuffer? {
        if let cached = recordedBuffers[cue] { return cached }
        guard let name = cue.fileName,
              let url = Bundle.main.url(forResource: name, withExtension: "caf"),
              let file = try? AVAudioFile(forReading: url),
              file.processingFormat == format,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: AVAudioFrameCount(file.length))
        else { return nil }
        do { try file.read(into: buffer) } catch { return nil }
        recordedBuffers[cue] = buffer
        return buffer
    }

    private func makeBuffer(for cue: Cue) -> AVAudioPCMBuffer? {
        guard let (frequencies, noteDuration) = cue.notes else {
            return recordedBuffer(for: cue)
        }
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
