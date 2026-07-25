import Foundation
import Observation

/// Root state: the loaded resources and the save store.
/// Created once at launch and passed down through the environment.
@Observable
final class AppState {
    let mapData: MapData
    let cards: CardCatalog
    let save: SaveStore
    let voice: VoiceInputService

    init(mapData: MapData? = nil,
         cards: CardCatalog? = nil,
         save: SaveStore? = nil,
         voice: VoiceInputService? = nil) {
        self.mapData = mapData ?? MapDataLoader.loadMapData()
        self.cards = cards ?? MapDataLoader.loadCards()
        self.save = save ?? SaveStore()
        self.voice = voice ?? VoiceInputService()
        self.voice.configure(vocabulary: self.mapData.prefectures.flatMap { [$0.kana, $0.name] })
    }

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
}
