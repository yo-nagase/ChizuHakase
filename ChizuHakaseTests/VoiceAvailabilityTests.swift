import AVFoundation
import Speech
import Testing

@testable import ChizuHakase

/// The launch-time derivation of voice availability (CLAUDE.md §7).
///
/// The mic button used to vanish on every cold start even though the mode was
/// on and both permissions were granted: availability only ever moved inside
/// requestAccess(), and nothing called that until the settings toggle was
/// flipped again. The rule is a pure function so these tests cannot depend on
/// what this machine's TCC database happens to say.
@MainActor
struct VoiceAvailabilityTests {
    typealias A = VoiceInputService.Availability

    /// The cold-start case the bug shipped: everything was granted in an
    /// earlier session, so a fresh launch must read as available without
    /// anyone re-asking.
    @Test func grantedPermissionsReadAsAvailableWithoutAsking() {
        #expect(A.derived(possibleOnDevice: true,
                          speech: .authorized,
                          microphone: .granted) == .available)
    }

    @Test func anUnsupportedDeviceHidesTheModeWhateverTCCSays() {
        for speech in [SFSpeechRecognizerAuthorizationStatus.authorized,
                       .denied, .notDetermined] {
            #expect(A.derived(possibleOnDevice: false,
                              speech: speech,
                              microphone: .granted) == .unsupported)
        }
    }

    @Test func aRefusalOnEitherPromptReadsAsDenied() {
        #expect(A.derived(possibleOnDevice: true,
                          speech: .denied, microphone: .granted) == .denied)
        #expect(A.derived(possibleOnDevice: true,
                          speech: .restricted, microphone: .granted) == .denied)
        #expect(A.derived(possibleOnDevice: true,
                          speech: .authorized, microphone: .denied) == .denied)
        // Half-answered still counts: a denied mic cannot listen no matter
        // what the unasked speech prompt might say later.
        #expect(A.derived(possibleOnDevice: true,
                          speech: .notDetermined, microphone: .denied) == .denied)
    }

    /// Never-asked is neither available nor denied: the mic button stays
    /// hidden, no 「つかえません」 hint appears, and the settings toggle keeps
    /// its right to put the question.
    @Test func unansweredPromptsAreNeitherAvailableNorDenied() {
        #expect(A.derived(possibleOnDevice: true,
                          speech: .notDetermined,
                          microphone: .undetermined) == .notDetermined)
        #expect(A.derived(possibleOnDevice: true,
                          speech: .authorized,
                          microphone: .undetermined) == .notDetermined)
        #expect(A.derived(possibleOnDevice: true,
                          speech: .notDetermined,
                          microphone: .granted) == .notDetermined)
    }
}
