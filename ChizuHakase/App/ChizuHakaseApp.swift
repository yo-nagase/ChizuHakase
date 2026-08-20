import SwiftUI

@main
struct ChizuHakaseApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            // The title opens on the page that was open last time (design doc
            // §2). Handed in at init so the very first frame is already the
            // right page — restoring it after the fact would flash japan.
            RootView(initialAtlasKey: appState.save.data.settings.lastAtlas)
                .environment(appState)
        }
    }
}
