import SwiftUI

/// Sound, speech and the voice-answer mode.
///
/// Speech sits here as a plain toggle with no gate and no price attached: it is
/// the accessibility floor for children who cannot read hiragana yet
/// (CLAUDE.md §7).
struct SettingsView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.textMode) private var mode

    @State private var showsUnlock = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    // Both labels are always shown so whoever picks up the
                    // phone can switch, including a child who cannot yet read
                    // the kanji one.
                    Picker(selection: setting(\.textMode)) {
                        ForEach(TextMode.allCases, id: \.self) { candidate in
                            Text(candidate.settingLabel).tag(candidate)
                        }
                    } label: {
                        label(mode.displaySection)
                    }
                    .pickerStyle(.inline)
                } header: {
                    Text(mode.displaySection)
                        .font(AppFont.rounded(12, relativeTo: .caption))
                }

                Section {
                    Toggle(isOn: setting(\.soundEnabled)) {
                        label(mode.soundEffects)
                    }
                    Toggle(isOn: setting(\.speechEnabled)) {
                        label(mode.speech)
                    }
                } header: {
                    Text(mode.soundSection).font(AppFont.rounded(12, relativeTo: .caption))
                }

                if app.canOfferVoiceMode {
                    Section {
                        Toggle(isOn: setting(\.voiceInputEnabled)) {
                            label(mode.answerByVoice)
                        }
                        if app.voice.availability == .denied {
                            // Stated once, never re-prompted — a permission loop
                            // is worse than losing the feature (CLAUDE.md §7).
                            Text(mode.micDenied)
                                .font(AppFont.rounded(12, relativeTo: .caption))
                                .foregroundStyle(Palette.ink.opacity(0.55))
                        }
                    } header: {
                        Text(mode.voiceSection).font(AppFont.rounded(12, relativeTo: .caption))
                    } footer: {
                        Text(mode.voiceOnDeviceNote)
                            .font(AppFont.rounded(11, relativeTo: .caption2))
                    }
                }

                Section {
                    if app.isUnlocked {
                        Label(mode.unlockedAlready, systemImage: "checkmark.circle.fill")
                            .font(AppFont.rounded(15, relativeTo: .body))
                            .foregroundStyle(Palette.teal)
                    } else {
                        Button(mode.unlockCTA) { showsUnlock = true }
                            .font(AppFont.rounded(15, relativeTo: .body))
                    }
                } header: {
                    Text(mode.forGrownUps).font(AppFont.rounded(12, relativeTo: .caption))
                }
            }
            .tint(Palette.teal)
            .navigationTitle(mode.settings)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(mode.close) { dismiss() }
                }
            }
            .sheet(isPresented: $showsUnlock) { UnlockView() }
            // Permission is requested only when the mode is switched on, and
            // only once — never on every appearance.
            .onChange(of: app.save.data.settings.voiceInputEnabled) { _, enabled in
                if enabled { Task { await app.voice.requestAccess() } }
            }
        }
    }

    private func label(_ title: String) -> some View {
        Text(title).font(AppFont.rounded(16, relativeTo: .body))
    }

    /// Writes straight through to the save store, which persists immediately.
    private func setting<Value>(_ keyPath: WritableKeyPath<Settings, Value>) -> Binding<Value> {
        Binding(
            get: { app.save.data.settings[keyPath: keyPath] },
            set: { newValue in app.save.updateSettings { $0[keyPath: keyPath] = newValue } })
    }
}
