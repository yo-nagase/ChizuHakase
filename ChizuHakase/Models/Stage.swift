import Foundation

/// A regional stage. `index` is the save key, so the order is fixed.
///
/// Every stage is playable from the first launch. There is deliberately no
/// per-stage gate: a child who opens the app should be able to reach any part
/// of the country without finding a grown-up first.
nonisolated struct Stage: Identifiable, Sendable, Equatable {
    let index: Int
    /// Reading, shown in child mode.
    let name: String
    /// Ordinary written form, shown in adult mode.
    let kanjiName: String
    let codes: [Int]

    var id: Int { index }

    /// Regional stages ask each prefecture twice.
    ///
    /// Once is a coin-flip a child can pass by luck, and with the answered
    /// prefectures no longer changing colour there is no elimination shortcut
    /// to shorten the second pass either. 全国チャレンジ is exempt: 47 questions
    /// is already a long sitting, and 94 would be a different activity.
    var asksEachTwice: Bool { codes.count < 47 }

    var questionCount: Int { codes.count * (asksEachTwice ? 2 : 1) }

    static let all: [Stage] = [
        Stage(index: 0, name: "ほっかいどう・とうほく", kanjiName: "北海道・東北",
              codes: Array(1...7)),
        Stage(index: 1, name: "かんとう", kanjiName: "関東",
              codes: Array(8...14)),
        Stage(index: 2, name: "ちゅうぶ", kanjiName: "中部",
              codes: Array(15...23)),
        Stage(index: 3, name: "きんき", kanjiName: "近畿",
              codes: Array(24...30)),
        Stage(index: 4, name: "ちゅうごく・しこく", kanjiName: "中国・四国",
              codes: Array(31...39)),
        Stage(index: 5, name: "きゅうしゅう・おきなわ", kanjiName: "九州・沖縄",
              codes: Array(40...47)),
        Stage(index: 6, name: "ぜんこく チャレンジ", kanjiName: "全国チャレンジ",
              codes: Array(1...47)),
    ]

    static func stage(at index: Int) -> Stage? {
        all.first { $0.index == index }
    }
}
