import CoreGraphics
import Foundation
import SwiftUI
import Testing

@testable import ChizuHakase

/// CLAUDE.md §10 phase 1: every prefecture must produce a non-empty Path, and
/// `contains` must be true at its centroid.
@MainActor
struct MapDataTests {

    static let map = MapDataLoader.loadMapData(contentsOf: TestResources.require("PrefectureShapes"))
    static let catalog = MapDataLoader.loadCards(contentsOf: TestResources.require("SpecialtyCards"))

    private var map: MapData { Self.map }

    @Test func loadsAll47Prefectures() {
        #expect(map.prefectures.count == 47)
        #expect(map.prefectures.map(\.code) == Array(1...47))
    }

    @Test func mapHasUsableDimensions() {
        #expect(map.width == 1000)
        #expect(map.height > 0)
        #expect(map.okinawaInset.width > 0)
        #expect(map.okinawaInset.height > 0)
    }

    @Test func everyPrefectureHasMetadata() throws {
        for pref in map.prefectures {
            #expect(!pref.name.isEmpty, "code \(pref.code) has no name")
            #expect(!pref.kana.isEmpty, "code \(pref.code) has no kana")
            #expect(pref.bbox.width > 0 && pref.bbox.height > 0,
                    "\(pref.name) has an empty bbox")
        }
    }

    @Test func everyPrefectureProducesANonEmptyPath() {
        for pref in map.prefectures {
            let path = PrefectureGeometry.path(for: pref, transform: .identity)
            #expect(!path.isEmpty, "\(pref.name) produced an empty Path")
            #expect(!path.boundingRect.isNull, "\(pref.name) has a null bounding rect")
        }
    }

    /// The centroid anchors labels, the correct-answer pop and the tap
    /// tolerance, so it has to be inside the shape — not merely near it.
    @Test func centroidIsInsideTheShape() {
        for pref in map.prefectures {
            #expect(PrefectureGeometry.contains(pref.centroid, prefecture: pref,
                                                transform: .identity),
                    "\(pref.name) centroid \(pref.centroid) is outside its own shape")
        }
    }

    /// Guards the reason `PrefectureGeometry` hit-tests through CGPath.
    ///
    /// SwiftUI's `Path.contains(_:eoFill:)` reports these three centroids as
    /// outside shapes it fills solidly with the same rule. If this test ever
    /// starts failing, SwiftUI has been fixed and the CGPath detour could be
    /// revisited — but do not swap it back on the assumption alone.
    @Test func swiftUIPathContainsIsUnreliableHenceTheCGPathDetour() {
        var disagreements: [String] = []
        for pref in map.prefectures {
            let swiftUI = PrefectureGeometry.path(for: pref, transform: .identity)
                .contains(pref.centroid, eoFill: true)
            let coreGraphics = PrefectureGeometry.contains(pref.centroid, prefecture: pref,
                                                           transform: .identity)
            if swiftUI != coreGraphics { disagreements.append(pref.name) }
        }
        // CGPath is the one that matches the rendering, so it is the reference.
        #expect(!disagreements.isEmpty,
                "SwiftUI now agrees everywhere — the CGPath detour may be revisited")
    }

    @Test func centroidLiesWithinItsOwnBoundingBox() {
        for pref in map.prefectures {
            #expect(pref.bbox.contains(pref.centroid),
                    "\(pref.name) centroid escapes its bbox")
        }
    }

    /// A centroid landing inside a neighbour would make hints and the
    /// tap-tolerance fallback point at the wrong prefecture.
    @Test func centroidNeverFallsInsideAnotherPrefecture() {
        for pref in map.prefectures {
            for other in map.prefectures where other.code != pref.code {
                guard other.bbox.contains(pref.centroid) else { continue }
                let path = PrefectureGeometry.path(for: other, transform: .identity)
                #expect(!path.contains(pref.centroid, eoFill: true),
                        "\(pref.name) centroid is inside \(other.name)")
            }
        }
    }

    @Test func ringsAreClosedAndSubstantial() {
        for pref in map.prefectures {
            #expect(!pref.rings.isEmpty, "\(pref.name) has no rings")
            for ring in pref.rings {
                #expect(ring.count >= 3, "\(pref.name) has a degenerate ring")
            }
            // Largest ring first — the app labels and anchors off rings[0].
            let areas = pref.rings.map { PrefectureGeometry.absoluteArea(of: $0) }
            #expect(areas.first == areas.max(),
                    "\(pref.name) rings are not sorted largest-first")
        }
    }

    @Test func allShapesFitInsideTheDeclaredCanvas() {
        for pref in map.prefectures {
            for ring in pref.rings {
                for p in ring {
                    #expect(p.x >= -0.5 && p.x <= map.width + 0.5,
                            "\(pref.name) x=\(p.x) outside canvas")
                    #expect(p.y >= -0.5 && p.y <= map.height + 0.5,
                            "\(pref.name) y=\(p.y) outside canvas")
                }
            }
        }
    }

    @Test func okinawaSitsInsideItsInsetFrame() throws {
        let okinawa = try #require(map[47])
        #expect(map.okinawaInset.insetBy(dx: -0.5, dy: -0.5).contains(okinawa.bbox),
                "Okinawa \(okinawa.bbox) escapes its inset \(map.okinawaInset)")
    }

    @Test func stageLookupResolvesEveryStage() {
        for stage in Stage.all {
            let prefs = map.prefectures(in: stage.codes)
            #expect(prefs.count == stage.codes.count,
                    "stage \(stage.name) is missing shapes")
        }
    }

    @Test func missingResourceFallsBackToEmptyRatherThanCrashing() {
        let missing = URL(fileURLWithPath: "/nonexistent/PrefectureShapes.json")
        #expect(MapDataLoader.loadMapData(contentsOf: missing).prefectures.isEmpty)
        #expect(MapDataLoader.loadCards(contentsOf: missing).all.isEmpty)
    }

    @Test func corruptResourceFallsBackToEmpty() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("corrupt-\(UUID().uuidString).json")
        try Data("{ this is not json".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(MapDataLoader.loadMapData(contentsOf: url).prefectures.isEmpty)
        #expect(MapDataLoader.loadCards(contentsOf: url).all.isEmpty)
    }
}

// MARK: - Cards

@MainActor
struct CardCatalogTests {

    private var catalog: CardCatalog { MapDataTests.catalog }

    @Test func loadsAll141Cards() {
        #expect(catalog.count == 141)
    }

    @Test func everyPrefectureHasExactlyThreeCards() {
        for code in 1...47 {
            #expect(catalog.cards(for: code).count == 3,
                    "code \(code) has \(catalog.cards(for: code).count) cards")
        }
    }

    @Test func cardIDsAreUniqueAndWellFormed() {
        var seen = Set<String>()
        for card in catalog.all {
            #expect(seen.insert(card.id).inserted, "duplicate card id \(card.id)")
            #expect(card.id == String(format: "%02d-", card.prefectureCode) + card.id.suffix(1),
                    "malformed id \(card.id)")
            #expect(catalog[card.id] == card, "id lookup failed for \(card.id)")
        }
    }

    @Test func cardContentIsChildReadable() {
        for card in catalog.all {
            #expect(!card.emoji.isEmpty, "\(card.id) has no emoji")
            #expect(!card.nameKana.isEmpty, "\(card.id) has no kana name")
            #expect(!card.nameKanji.isEmpty, "\(card.id) has no written name")
            #expect(!card.description.isEmpty, "\(card.id) has no description")
            // Pre-readers are the target audience; descriptions must not
            // require kanji (CLAUDE.md §1, §12).
            let hasKanji = card.description.unicodeScalars.contains {
                (0x4E00...0x9FFF).contains(Int($0.value))
            }
            #expect(!hasKanji, "\(card.id) description contains kanji: \(card.description)")
        }
    }

    /// Every category except `flag`, which belongs to the world atlas —
    /// asserting its absence here is what keeps the japan book free of a
    /// flag filter chip that could never show a card.
    @Test func everyCategoryIsRepresented() {
        let used = Set(catalog.all.map(\.category))
        #expect(used == Set(SpecialtyCard.Category.allCases).subtracting([.flag]))
    }
}

/// Anchor for locating the test bundle's copy of the resources.
final class BundleToken {}

/// The generated JSON ships in the app bundle, but which bundle is "main"
/// depends on whether the suite runs hosted or standalone. Search both rather
/// than guess, and fail loudly if the resource is genuinely absent — a silent
/// empty map would make every assertion below vacuously pass.
enum TestResources {
    static func require(_ name: String) -> URL {
        var candidates = [Bundle(for: BundleToken.self), Bundle.main]
        candidates.append(contentsOf: Bundle.allBundles)
        for bundle in candidates {
            if let url = bundle.url(forResource: name, withExtension: "json") {
                return url
            }
        }
        fatalError("\(name).json not found in any loaded bundle")
    }
}
