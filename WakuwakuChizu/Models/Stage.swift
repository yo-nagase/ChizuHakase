import Foundation

/// A regional stage. `index` is the save key, so the order is fixed.
nonisolated struct Stage: Identifiable, Sendable, Equatable {
    let index: Int
    /// Reading, shown in child mode.
    let name: String
    /// Ordinary written form, shown in adult mode.
    let kanjiName: String
    let codes: [Int]
    let isFree: Bool

    var id: Int { index }
    var questionCount: Int { codes.count }

    static let all: [Stage] = [
        Stage(index: 0, name: "ほっかいどう・とうほく", kanjiName: "北海道・東北",
              codes: Array(1...7), isFree: true),
        Stage(index: 1, name: "かんとう", kanjiName: "関東",
              codes: Array(8...14), isFree: true),
        Stage(index: 2, name: "ちゅうぶ", kanjiName: "中部",
              codes: Array(15...23), isFree: false),
        Stage(index: 3, name: "きんき", kanjiName: "近畿",
              codes: Array(24...30), isFree: false),
        Stage(index: 4, name: "ちゅうごく・しこく", kanjiName: "中国・四国",
              codes: Array(31...39), isFree: false),
        Stage(index: 5, name: "きゅうしゅう・おきなわ", kanjiName: "九州・沖縄",
              codes: Array(40...47), isFree: false),
        Stage(index: 6, name: "ぜんこく チャレンジ", kanjiName: "全国チャレンジ",
              codes: Array(1...47), isFree: false),
    ]

    static func stage(at index: Int) -> Stage? {
        all.first { $0.index == index }
    }
}
