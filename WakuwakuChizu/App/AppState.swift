import Foundation
import Observation

/// Root state: the loaded resources, the save store and the purchase store.
/// Created once at launch and passed down through the environment.
@Observable
final class AppState {
    let mapData: MapData
    let cards: CardCatalog
    let save: SaveStore
    let purchases: PurchaseStore
    let voice: VoiceInputService

    init(mapData: MapData? = nil,
         cards: CardCatalog? = nil,
         save: SaveStore? = nil,
         purchases: PurchaseStore? = nil,
         voice: VoiceInputService? = nil) {
        self.mapData = mapData ?? MapDataLoader.loadMapData()
        self.cards = cards ?? MapDataLoader.loadCards()
        self.save = save ?? SaveStore()
        self.purchases = purchases ?? PurchaseStore()
        self.voice = voice ?? VoiceInputService()
        self.voice.configure(vocabulary: self.mapData.prefectures.flatMap { [$0.kana, $0.name] })
    }

    var isUnlocked: Bool { purchases.isUnlocked }

    func isPlayable(_ stage: Stage) -> Bool { stage.isFree || isUnlocked }

    var stages: [Stage] { Stage.all }

    /// True only when the device can recognise Japanese on-device *and* the
    /// child's guardian has turned the mode on. Anything less and the feature
    /// stays hidden rather than half-present (CLAUDE.md §7).
    var isVoiceModeAvailable: Bool {
        save.data.settings.voiceInputEnabled
            && voice.isPossibleOnThisDevice
            && voice.availability == .available
    }

    var canOfferVoiceMode: Bool { voice.isPossibleOnThisDevice }

    /// Re-verify entitlements at launch and on foreground (CLAUDE.md §8).
    func refreshOnForeground() async {
        await purchases.refreshEntitlements()
    }
}
