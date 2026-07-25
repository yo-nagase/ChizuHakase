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

    var id: Int { code }

    /// Reading used for the question text and speech: 「ほっかいどう」.
    var spokenName: String { kana }
}

/// The whole map resource: `PrefectureShapes.json` decoded.
nonisolated struct MapData: Sendable {
    let width: CGFloat
    let height: CGFloat
    /// Frame of the Okinawa inset, drawn dashed so children can see it is a
    /// separate box rather than Okinawa's real position.
    let okinawaInset: CGRect
    let prefectures: [Prefecture]

    private let byCode: [Int: Prefecture]

    init(width: CGFloat, height: CGFloat, okinawaInset: CGRect, prefectures: [Prefecture]) {
        self.width = width
        self.height = height
        self.okinawaInset = okinawaInset
        self.prefectures = prefectures
        self.byCode = Dictionary(uniqueKeysWithValues: prefectures.map { ($0.code, $0) })
    }

    subscript(code: Int) -> Prefecture? { byCode[code] }

    func prefectures(in codes: [Int]) -> [Prefecture] {
        codes.compactMap { byCode[$0] }
    }

    var size: CGSize { CGSize(width: width, height: height) }

    static let empty = MapData(width: 1, height: 1, okinawaInset: .zero, prefectures: [])
}
