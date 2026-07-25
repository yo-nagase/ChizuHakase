import SwiftUI

/// Sound, speech and the voice-answer mode.
///
/// Speech sits here as a plain toggle with no gate and no price attached: it is
/// the accessibility floor for children who cannot read hiragana yet
/// (CLAUDE.md §7).
struct SettingsView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var showsUnlock = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: setting(\.soundEnabled)) {
                        label("こうかおん")
                    }
                    Toggle(isOn: setting(\.speechEnabled)) {
                        label("よみあげ")
                    }
                } header: {
                    Text("おと").font(AppFont.rounded(12, relativeTo: .caption))
                }

                if app.canOfferVoiceMode {
                    Section {
                        Toggle(isOn: setting(\.voiceInputEnabled)) {
                            label("こえで こたえる")
                        }
                        if app.voice.availability == .denied {
                            // Stated once, never re-prompted — a permission loop
                            // is worse than losing the feature (CLAUDE.md §7).
                            Text("マイクを つかえません。「せってい」から ゆるすと つかえます。")
                                .font(AppFont.rounded(12, relativeTo: .caption))
                                .foregroundStyle(Palette.ink.opacity(0.55))
                        }
                    } header: {
                        Text("こえ").font(AppFont.rounded(12, relativeTo: .caption))
                    } footer: {
                        Text("こえは この iPhone の なかだけで しらべます。")
                            .font(AppFont.rounded(11, relativeTo: .caption2))
                    }
                }

                Section {
                    if app.isUnlocked {
                        Label("ぜんぶ あそべます", systemImage: "checkmark.circle.fill")
                            .font(AppFont.rounded(15, relativeTo: .body))
                            .foregroundStyle(Palette.teal)
                    } else {
                        Button("ぜんぶ あそべるようにする") { showsUnlock = true }
                            .font(AppFont.rounded(15, relativeTo: .body))
                    }
                } header: {
                    Text("おうちのかたへ").font(AppFont.rounded(12, relativeTo: .caption))
                }
            }
            .tint(Palette.teal)
            .navigationTitle("せってい")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("とじる") { dismiss() }
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
    private func setting(_ keyPath: WritableKeyPath<Settings, Bool>) -> Binding<Bool> {
        Binding(
            get: { app.save.data.settings[keyPath: keyPath] },
            set: { newValue in app.save.updateSettings { $0[keyPath: keyPath] = newValue } })
    }
}
