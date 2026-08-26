import Foundation
import Testing

@testable import ChizuHakase

@MainActor
struct PhantomCardTests {
    private var japanAtlas: Atlas {
        Atlas.japan(mapData: AtlasTests.japanMap, cards: AtlasTests.japanCards)
    }

    private func worldAtlas() throws -> Atlas {
        Atlas.world(from: try AtlasTests.world.get(), cards: AtlasTests.worldCards)
    }

    @Test func eachAtlasHasThePromisedNumberOfPhantomCards() throws {
        let japan = PhantomCard.catalog(for: japanAtlas)
        let world = PhantomCard.catalog(for: try worldAtlas())

        #expect(japan.count == 3)
        #expect(japan.map(\.setIndex) == [1, 2, 3])
        #expect(japan.allSatisfy { $0.setCount == 3 })
        #expect(world.count == 7)
        #expect(world.map(\.setIndex) == Array(1...7))
        #expect(world.allSatisfy { $0.setCount == 7 })
        #expect(Set((japan + world).map(\.id)).count == 10)
    }

    @Test func collectingEastJapanOrdinaryCardsUnlocksOnlySky() {
        let atlas = japanAtlas
        var save = AtlasSave()
        for code in 1...14 {
            for card in atlas.cards.cards(for: code) { save.cards[card.id] = 1 }
        }

        let unlocked = PhantomCard.newlyUnlocked(
            from: PhantomCard.catalog(for: atlas),
            ordinaryCatalog: atlas.cards, save: save)

        #expect(unlocked == ["phantom-japan-sky"])
    }

    @Test func oneMissingOrdinaryCardKeepsTheRewardHidden() {
        let atlas = japanAtlas
        var save = AtlasSave()
        let required = (1...14).flatMap { atlas.cards.cards(for: $0) }
        for card in required.dropLast() { save.cards[card.id] = 1 }

        let unlocked = PhantomCard.newlyUnlocked(
            from: PhantomCard.catalog(for: atlas),
            ordinaryCatalog: atlas.cards, save: save)

        #expect(unlocked.isEmpty)
    }

    @Test func allSixWorldRegionsUnlockAntarcticaInTheSamePass() throws {
        let atlas = try worldAtlas()
        var save = AtlasSave()
        for card in atlas.cards.all { save.cards[card.id] = 1 }

        let unlocked = PhantomCard.newlyUnlocked(
            from: PhantomCard.catalog(for: atlas),
            ordinaryCatalog: atlas.cards, save: save)

        #expect(unlocked.count == 7)
        #expect(unlocked.contains("phantom-world-antarctica"))
    }

    @Test func existingOwnershipIsNeverAnnouncedAgain() {
        let atlas = japanAtlas
        var save = AtlasSave()
        for code in 1...14 {
            for card in atlas.cards.cards(for: code) { save.cards[card.id] = 1 }
        }
        save.phantomCards.insert("phantom-japan-sky")

        let unlocked = PhantomCard.newlyUnlocked(
            from: PhantomCard.catalog(for: atlas),
            ordinaryCatalog: atlas.cards, save: save)

        #expect(unlocked.isEmpty)
    }

    @Test func versionEightSaveDefaultsPhantomOwnershipToEmpty() throws {
        let json = Data(#"{"version":8,"atlases":{"japan":{"cards":{"01-1":1}}}}"#.utf8)
        let data = try JSONDecoder().decode(SaveData.self, from: json)

        #expect(data.version == SaveData.currentVersion)
        #expect(data.atlas(SaveData.japanAtlas).phantomCards.isEmpty)
        #expect(data.atlas(SaveData.japanAtlas).cards["01-1"] == 1)
    }
}
