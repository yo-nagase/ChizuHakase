import CoreGraphics
import Foundation

/// One prefecture's shape and metadata, in map space
/// (top-left origin, y down, width normalised to `MapData.width`).
nonisolated struct Prefecture: Identifiable, Sendable, Equatable {
    /// 全国地方公共団体コード, 1...47. Stable across releases; used as a save key.
    let code: Int
    let name: String
    let kana: String
    let bbox: CGRect
    /// Guaranteed to lie inside `rings` — it is a pole of inaccessibility, not
    /// an area centroid, so it is safe to anchor labels and the tap-tolerance
    /// test to it. See tools/build_map_data.py.
    let centroid: CGPoint
    /// Outer boundaries and holes together. Drawn and hit-tested with even-odd,
    /// which makes the distinction unnecessary at render time.
    let rings: [[CGPoint]]
    /// The part of the shape a stage frame should honour; nil means the whole
    /// `bbox`. Only Russia carries one (its European part): fitting the full
    /// territory stretches ひがしヨーロッパ to the Bering Strait and crushes
    /// Moldova to a few points, so the frame stops at the Urals and Siberia
    /// overflows it as scenery (docs/plans/2026-08-18-world-stages.md).
    /// Hit-testing and VoiceOver keep the true `bbox` — a tap on visible
    /// Siberia is a tap on Russia.
    let frameBbox: CGRect?

    init(code: Int, name: String, kana: String, bbox: CGRect,
         centroid: CGPoint, rings: [[CGPoint]], frameBbox: CGRect? = nil) {
        self.code = code
        self.name = name
        self.kana = kana
        self.bbox = bbox
        self.centroid = centroid
        self.rings = rings
        self.frameBbox = frameBbox
    }

    var id: Int { code }

    /// Reading used for the question text and speech: 「ほっかいどう」.
    var spokenName: String { kana }
}

/// A shape drawn enlarged inside a separate dashed box — Okinawa on the japan
/// map, Singapore-class countries on the world map. The box is dashed so
/// children can see it is a frame, not the shape's real position (CLAUDE.md
/// §3). Placement comes from the data pipeline, which scans for empty sea —
/// never hand-placed.
nonisolated struct MapInset: Sendable, Equatable {
    /// The relocated shape's code. The frame is only drawn when that shape is
    /// part of what is on screen.
    let code: Int
    /// The dashed box, in map space.
    let frame: CGRect
}

/// A coastline that is drawn but never asked about — dependencies and
/// unrecorded countries on the world map. Leaving them out would draw false
/// sea where land exists (2026-08-18-world-stages.md 技術ノート). Carries no
/// code and no name: it is scenery.
nonisolated struct MapBackgroundShape: Sendable, Equatable {
    let rings: [[CGPoint]]
    /// Cheap cull: only shapes whose box touches the visible canvas are drawn.
    /// The world's background covers the whole globe; a stage sees a corner.
    let bbox: CGRect
}

/// The whole map resource: `PrefectureShapes.json` decoded.
nonisolated struct MapData: Sendable {
    let width: CGFloat
    let height: CGFloat
    /// Dashed inset boxes. Japan has one (Okinawa), the world four, an empty
    /// list means no frames — presence is data, never a japan/world branch.
    let insets: [MapInset]
    /// Unrecorded coastlines (world only; japan's list is empty).
    let background: [MapBackgroundShape]
    let prefectures: [Prefecture]

    private let byCode: [Int: Prefecture]

    init(width: CGFloat, height: CGFloat, insets: [MapInset] = [],
         background: [MapBackgroundShape] = [], prefectures: [Prefecture]) {
        self.width = width
        self.height = height
        self.insets = insets
        self.background = background
        self.prefectures = prefectures
        self.byCode = Dictionary(uniqueKeysWithValues: prefectures.map { ($0.code, $0) })
    }

    subscript(code: Int) -> Prefecture? { byCode[code] }

    /// Deduplicated: a regional stage lists every prefecture twice in its
    /// question order, and handing that straight to the map drew — and made an
    /// accessibility element for — each shape twice.
    func prefectures(in codes: [Int]) -> [Prefecture] {
        var seen: Set<Int> = []
        return codes.compactMap { seen.insert($0).inserted ? byCode[$0] : nil }
    }

    var size: CGSize { CGSize(width: width, height: height) }

    static let empty = MapData(width: 1, height: 1, prefectures: [])
}
