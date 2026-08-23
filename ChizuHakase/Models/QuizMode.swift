import Foundation

/// Which direction the question runs.
///
/// The two are different skills. Recognising a shape you are given the name of
/// is not the same as recalling the name of a shape you are shown, and a child
/// who can do one often cannot yet do the other. They share everything else —
/// the same stages, the same scoring, the same mastery ramp — so learning does
/// not get split into two ledgers a five-year-old has to reconcile.
nonisolated enum QuizMode: String, Codable, Sendable, CaseIterable, Identifiable {
    /// 「あいちけんは どこかな?」 — given the name, find it on the map.
    case findOnMap
    /// The map rings one prefecture in red — say which one it is.
    case nameIt

    var id: String { rawValue }
}

nonisolated extension QuizMode {
    func title(_ text: TextMode) -> String {
        switch (self, text.isKids) {
        case (.findOnMap, true): "ちずで さがす"
        case (.findOnMap, false): "地図で探す"
        case (.nameIt, true): "なまえを あてる"
        case (.nameIt, false): "名前を当てる"
        }
    }

    /// One line on the mode switch, so the difference is legible before the
    /// first question rather than after it. The thing in the red ring is
    /// named by the atlas (けん ⇄ くに) — the stage picker serves both books.
    func blurb(_ text: TextMode, region: AtlasNoun) -> String {
        switch (self, text.isKids) {
        case (.findOnMap, true): "なまえを きいて タップ"
        case (.findOnMap, false): "名前を聞いてタップ"
        case (.nameIt, true): "あかい わくの \(region.kids)を こたえる"
        case (.nameIt, false): "赤い枠の\(region.adult)を答える"
        }
    }

    var symbol: String {
        switch self {
        case .findOnMap: "👆"
        case .nameIt: "💡"
        }
    }
}
