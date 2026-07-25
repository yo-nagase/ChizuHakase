import AudioToolbox
import AVFoundation
import Foundation

/// Short feedback sounds.
///
/// Synthesised in-process rather than shipped as audio files: the whole set is
/// four short tones, and generating them keeps the bundle free of binary
/// assets that would need licence tracking for a Kids-category release.
final class SoundService {
    static let shared = SoundService()

    enum Cue {
        case correct, wrong, star, cardWin

        /// (frequencies in Hz, seconds per note)
        var notes: ([Double], Double) {
            switch self {
            // Rising major third: unambiguously "yes" without being shrill.
            case .correct: ([660, 880], 0.09)
            // Gentle low blip. Deliberately not a buzzer — a wrong tap should
            // read as "not that one", never as a scolding (CLAUDE.md §12).
            case .wrong: ([300, 260], 0.07)
            case .star: ([784, 988, 1175], 0.10)
            case .cardWin: ([523, 659, 784, 1047], 0.08)
            }
        }
    }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var started = false

    private init() {}

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
        // .ambient + mixWithOthers: the app should never stop a family's music.
        try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try AVAudioSession.sharedInstance().setActive(true)

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        try engine.start()
        started = true
    }

    private let sampleRate: Double = 44_100
    private var format: AVAudioFormat? {
        AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
    }

    private func makeBuffer(for cue: Cue) -> AVAudioPCMBuffer? {
        let (frequencies, noteDuration) = cue.notes
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
