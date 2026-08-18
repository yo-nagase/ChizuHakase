import AudioToolbox
import AVFoundation
import Foundation

/// Short feedback sounds.
///
/// Every cue is synthesised in-process rather than shipped as an audio file:
/// the whole set is a handful of short tones, and generating them keeps the
/// bundle free of binary assets that would need licence tracking for a
/// Kids-category release. The navigation taps used to be the exception — a
/// bundled tap recording — but a dry click is office furniture in a toy, so
/// they are now the bubble pops below.
final class SoundService {
    static let shared = SoundService()

    enum Cue: Hashable {
        /// The navigation taps: pitch sweeps, not note pairs.
        case decide, cancel
        case correct, wrong, star, cardWin

        /// (frequencies in Hz, seconds per note); nil for the swept cues.
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

        /// (start Hz, end Hz, seconds); nil for cues built from notes.
        ///
        /// The navigation taps are little bubble pops: going forward slides
        /// up an octave, going back slides the same distance down, so which
        /// way the app just moved is audible before a child can read any
        /// label. A glide with a percussive envelope reads as a water plip —
        /// toy-box material — where a flat tone pair read as a beep and the
        /// old tap recording read as a grown-up's keyboard.
        var sweep: (from: Double, to: Double, duration: Double)? {
            switch self {
            case .decide: (520, 1040, 0.11)
            case .cancel: (740, 370, 0.13)
            default: nil
            }
        }
    }

    /// How far the correct cue rises for a running combo, in semitones.
    ///
    /// Two major scales, do to do to do: each clean answer climbs a step, so
    /// a run *sounds* like it is going somewhere before the child can read
    /// the combo badge. One octave used to be the lot, but it flattened out
    /// on the seventh answer — right when a run starts feeling special — so
    /// the ladder now spans two octaves (the top lands at four times the
    /// base frequency) and the longest runs keep audibly climbing. From the
    /// second octave on it holds: the cue has to keep reading as "yes", and
    /// climbing forever turns yes into a whistle.
    /// Combo 0 and 1 are the base note: one correct answer is not yet a
    /// run, and an answer after a fumble starts over where the scale does.
    static func semitoneRise(forCombo combo: Int) -> Int {
        let scale = [0, 2, 4, 5, 7, 9, 11, 12,
                     14, 16, 17, 19, 21, 23, 24]
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

    /// Builds the engine before the first tap needs it. That otherwise
    /// happens synchronously inside the first button action, and starting an
    /// AVAudioEngine takes long enough there to read as input lag. Runs
    /// regardless of the sound setting: the toggle can flip at any moment,
    /// and an idle engine on the ambient session just renders silence.
    func warmUp() {
        try? start()
    }

    /// `semitonesUp` transposes the note-based cues; the swept taps play as
    /// they are — navigation has no combo to climb.
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

    func makeBuffer(for cue: Cue, semitonesUp: Int = 0) -> AVAudioPCMBuffer? {
        guard let (baseFrequencies, noteDuration) = cue.notes else {
            return cue.sweep.flatMap(makeSweepBuffer)
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

    /// One sine whose pitch glides between the sweep's ends — the bubble pop.
    ///
    /// The phase is accumulated sample by sample: with a moving frequency,
    /// sin(2πf(t)·t) re-derives the whole waveform from t = 0 every sample
    /// and warbles. The envelope is a near-instant attack with a long soft
    /// fall, which is what separates a pop from a beep.
    private func makeSweepBuffer(
        _ sweep: (from: Double, to: Double, duration: Double)
    ) -> AVAudioPCMBuffer? {
        guard let format else { return nil }
        let frames = AVAudioFrameCount(sampleRate * sweep.duration)
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames

        // Exponential glide: equal time per octave, which is how pitch is
        // heard — a linear glide spends most of its run near the high end.
        let ratio = sweep.to / sweep.from
        var phase = 0.0
        for i in 0..<Int(frames) {
            let progress = Double(i) / Double(frames)
            let frequency = sweep.from * pow(ratio, progress)
            phase += 2 * .pi * frequency / sampleRate
            let envelope = min(1, progress * 30) * pow(1 - progress, 1.6)
            channel[i] = Float(sin(phase) * envelope * 0.26)
        }
        return buffer
    }
}
