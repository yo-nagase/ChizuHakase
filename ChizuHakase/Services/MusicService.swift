import AVFoundation
import Observation
import OSLog

/// The title theme (docs/plans/2026-08-15-title-theme-song.md).
///
/// One song, one place it plays: the title screen. Navigation away fades it
/// out, every path back to the title starts it again, and the mute button on
/// the title writes through `Settings.musicEnabled` so the choice survives a
/// relaunch. It plays through the shared ambient session, so the ring switch
/// silences it and it never stops a family's own music (CLAUDE.md §7).
@Observable
final class MusicService {

    /// Where the bundled song is, or nil if it drifted out of the bundle.
    /// A missing resource is a silent title screen, not a crash — this URL is
    /// what the test suite watches so the drift is caught before a release.
    static var themeURL: URL? {
        Bundle.main.url(forResource: "theme-song", withExtension: "m4a")
    }

    /// Below full scale (about −3 dB): the bundled track is mastered loud,
    /// and the theme is the title's furniture — it should sit under the tap
    /// sounds and the read-aloud voice, not compete with them.
    static let themeVolume: Float = 0.7

    private let log = Logger(subsystem: "com.wakuwaku.chizuhakase", category: "Music")

    private var player: AVAudioPlayer?
    /// The tail end of a fade-out. Kept so that coming back to the title
    /// mid-fade can cancel it — otherwise the stop scheduled on the way out
    /// lands after the song has restarted and kills it.
    private var pendingStop: Task<Void, Never>?

    var isPlaying: Bool { player?.isPlaying ?? false }

    /// Idempotent: arriving at the title twice must not restart the song or
    /// stack a second player under the first.
    func playTitleTheme() {
        pendingStop?.cancel()
        pendingStop = nil

        if let player {
            // Mid-fade return: take the volume back, keep the song where it is.
            player.setVolume(Self.themeVolume, fadeDuration: 0)
            if !player.isPlaying { player.play() }
            return
        }

        guard let url = Self.themeURL else {
            log.error("theme-song.m4a is not in the bundle; the title stays quiet")
            return
        }
        do {
            AudioSession.configureForPlayback()
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = Self.themeVolume
            player.play()
            self.player = player
        } catch {
            // Music is a nicety; failing to play it must never interrupt play.
            log.error("could not play the theme: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Stop now (`fadeOut: 0`) or fade to silence and then release the player.
    func stop(fadeOut: TimeInterval) {
        pendingStop?.cancel()
        pendingStop = nil

        guard let player else { return }
        guard fadeOut > 0, player.isPlaying else {
            player.stop()
            self.player = nil
            return
        }

        player.setVolume(0, fadeDuration: fadeOut)
        pendingStop = Task { [weak self] in
            try? await Task.sleep(for: .seconds(fadeOut))
            guard !Task.isCancelled else { return }
            self?.player?.stop()
            self?.player = nil
            self?.pendingStop = nil
        }
    }
}
