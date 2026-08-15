import Foundation
import Testing

@testable import ChizuHakase

/// The title theme (docs/plans/2026-08-15-title-theme-song.md). The song is a
/// bundled file, so the failure worth guarding against is the quiet one: a
/// missing or renamed resource makes a silent title screen, not a crash.
@MainActor
struct MusicServiceTests {

    /// Catches the resource drifting out of the bundle — the app keeps
    /// running either way, so nothing else would notice.
    @Test func themeSongIsBundled() {
        #expect(MusicService.themeURL != nil,
                "theme-song.m4a is not in Resources; the title plays silence")
    }

    @Test func playsAndStops() {
        let service = MusicService()
        service.playTitleTheme()
        #expect(service.isPlaying)

        service.stop(fadeOut: 0)
        #expect(!service.isPlaying)
    }

    /// Called from every path back to the title, so arriving twice must not
    /// restart the song or stack players.
    @Test func playingTwiceIsHarmless() {
        let service = MusicService()
        service.playTitleTheme()
        service.playTitleTheme()
        #expect(service.isPlaying)
        service.stop(fadeOut: 0)
    }

    @Test func stoppingWhenNothingPlaysIsHarmless() {
        let service = MusicService()
        service.stop(fadeOut: 0)
        #expect(!service.isPlaying)
    }

    /// Popping back to the title mid-fade: the return must win, or the fade
    /// that was scheduled on the way out kills the music that just restarted.
    @Test func aFadingStopIsCancelledByPlay() async throws {
        let service = MusicService()
        service.playTitleTheme()
        service.stop(fadeOut: 0.2)
        service.playTitleTheme()

        try await Task.sleep(for: .seconds(0.4))
        #expect(service.isPlaying, "the cancelled fade still silenced the theme")
        service.stop(fadeOut: 0)
    }
}
