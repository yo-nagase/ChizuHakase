import Testing
import UIKit

@testable import ChizuHakase

/// Stage-selection landmark assets (GitHub Issue #10).
///
/// The names are code, while the painted PNGs are an asset catalog: without a
/// bundle-resolution test those two sources can drift into blank signboards.
@MainActor
struct StageLandmarkArtTests {

    @Test func japanKeepsItsOriginalSevenLandmarks() {
        #expect(Stage.landmarkAssetNames == [
            "stage-icon-balloon", "stage-icon-tower", "stage-icon-fuji",
            "stage-icon-castle", "stage-icon-yuzu", "stage-icon-hibiscus",
            "stage-icon-globe",
        ])

        let atlas = Atlas.japan(mapData: .empty, cards: .empty)
        #expect(atlas.stages.map { atlas.stageLandmarkAssetName(for: $0) }
                == Stage.landmarkAssetNames.map(Optional.some))
    }

    @Test func worldCarriesOneUniqueLandmarkPerStage() throws {
        let data = try WorldDataLoader.load(
            contentsOf: TestResources.require("WorldShapes"))
        let atlas = Atlas.world(from: data)

        #expect(WorldStage.landmarkAssetNames.count == 19)
        #expect(Set(WorldStage.landmarkAssetNames).count == 19)
        #expect(WorldStage.landmarkAssetNames.last == "stage-icon-world-challenge")
        #expect(atlas.stages.map { atlas.stageLandmarkAssetName(for: $0) }
                == WorldStage.landmarkAssetNames.map(Optional.some))
    }

    @Test func everyLandmarkResolvesToA384PixelBundledImage() throws {
        for name in Stage.landmarkAssetNames + WorldStage.landmarkAssetNames {
            let image = try #require(UIImage(named: name), "missing asset \(name)")
            let pixels = try #require(image.cgImage)
            #expect(pixels.width == 384, "\(name) width is \(pixels.width)")
            #expect(pixels.height == 384, "\(name) height is \(pixels.height)")
        }
    }

    @Test func anUnknownStageDoesNotBorrowAnotherRegionsLandmark() {
        let atlas = Atlas.japan(mapData: .empty, cards: .empty)
        let unknown = Stage(index: 99, name: "", kanjiName: "", codes: [])
        #expect(atlas.stageLandmarkAssetName(for: unknown) == nil)
    }
}
