import Foundation
import Observation

/// Root state: the loaded resources plus the save store. Created once at
/// launch and passed down through the environment.
@Observable
final class AppState {
    let mapData: MapData
    let cards: CardCatalog
    let save: SaveStore

    /// True once a purchase unlocks the paid stages. Wired to StoreKit in a
    /// later phase; free stages must work without it.
    var isUnlocked = false

    init(mapData: MapData? = nil, cards: CardCatalog? = nil, save: SaveStore? = nil) {
        self.mapData = mapData ?? MapDataLoader.loadMapData()
        self.cards = cards ?? MapDataLoader.loadCards()
        self.save = save ?? SaveStore()
    }

    func isPlayable(_ stage: Stage) -> Bool { stage.isFree || isUnlocked }

    /// Stage list with the shapes each one needs, in display order.
    var stages: [Stage] { Stage.all }
}
