import CoreGraphics
import Foundation
import OSLog

/// Decodes the two generated resources (CLAUDE.md §3, §4).
///
/// Both loads are failable-by-design: a corrupt or missing resource returns an
/// empty catalogue and is logged, never trapped. A child seeing a blank map is
/// bad; a crash on launch is worse.
nonisolated enum MapDataLoader {

    private static let log = Logger(subsystem: "com.wakuwaku.chizuhakase", category: "MapDataLoader")

    // MARK: - Wire format

    private struct MapFile: Decodable {
        struct Pref: Decodable {
            let code: Int
            let name: String
            let kana: String
            let bbox: [CGFloat]
            let centroid: [CGFloat]
            let rings: [[[CGFloat]]]
        }
        let mapWidth: CGFloat
        let mapHeight: CGFloat
        let okinawaInset: [CGFloat]
        let prefectures: [Pref]
    }

    private struct CardFile: Decodable {
        let cards: [SpecialtyCard]
    }

    // MARK: - Loading

    static func loadMapData(bundle: Bundle = .main) -> MapData {
        guard let url = bundle.url(forResource: "PrefectureShapes", withExtension: "json") else {
            log.error("PrefectureShapes.json missing from bundle")
            return .empty
        }
        return loadMapData(contentsOf: url)
    }

    static func loadMapData(contentsOf url: URL) -> MapData {
        do {
            let file = try JSONDecoder().decode(MapFile.self, from: Data(contentsOf: url))
            let prefectures = file.prefectures.compactMap(makePrefecture)
            guard !prefectures.isEmpty else {
                log.error("map data decoded but contained no usable prefectures")
                return .empty
            }
            return MapData(width: file.mapWidth,
                           height: file.mapHeight,
                           okinawaInset: rect(from: file.okinawaInset) ?? .zero,
                           prefectures: prefectures.sorted { $0.code < $1.code })
        } catch {
            log.error("map data load failed: \(error.localizedDescription, privacy: .public)")
            return .empty
        }
    }

    static func loadCards(bundle: Bundle = .main) -> CardCatalog {
        guard let url = bundle.url(forResource: "SpecialtyCards", withExtension: "json") else {
            log.error("SpecialtyCards.json missing from bundle")
            return .empty
        }
        return loadCards(contentsOf: url)
    }

    static func loadCards(contentsOf url: URL) -> CardCatalog {
        do {
            let file = try JSONDecoder().decode(CardFile.self, from: Data(contentsOf: url))
            return CardCatalog(cards: file.cards)
        } catch {
            log.error("card data load failed: \(error.localizedDescription, privacy: .public)")
            return .empty
        }
    }

    // MARK: - Mapping

    private static func makePrefecture(_ p: MapFile.Pref) -> Prefecture? {
        // A prefecture with no drawable ring would be an invisible, untappable
        // question. Drop it rather than ship a dead question.
        let rings = p.rings.compactMap { ring -> [CGPoint]? in
            let points = ring.compactMap { pair -> CGPoint? in
                pair.count >= 2 ? CGPoint(x: pair[0], y: pair[1]) : nil
            }
            return points.count >= 3 ? points : nil
        }
        guard !rings.isEmpty,
              let bbox = rect(from: p.bbox),
              p.centroid.count >= 2,
              (1...47).contains(p.code)
        else {
            log.error("skipping malformed prefecture entry code=\(p.code, privacy: .public)")
            return nil
        }
        return Prefecture(code: p.code,
                          name: p.name,
                          kana: p.kana,
                          bbox: bbox,
                          centroid: CGPoint(x: p.centroid[0], y: p.centroid[1]),
                          rings: rings)
    }

    /// `[x0, y0, x1, y1]` -> CGRect.
    private static func rect(from values: [CGFloat]) -> CGRect? {
        guard values.count >= 4 else { return nil }
        return CGRect(x: values[0],
                      y: values[1],
                      width: values[2] - values[0],
                      height: values[3] - values[1])
    }
}
