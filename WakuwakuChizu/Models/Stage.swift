import Foundation

/// A regional stage. `index` is the save key, so the order is fixed.
nonisolated struct Stage: Identifiable, Sendable, Equatable {
    let index: Int
    let name: String
    let codes: [Int]
    let isFree: Bool

    var id: Int { index }
    var questionCount: Int { codes.count }

    static let all: [Stage] = [
        Stage(index: 0, name: "ほっかいどう・とうほく", codes: Array(1...7), isFree: true),
        Stage(index: 1, name: "かんとう", codes: Array(8...14), isFree: true),
        Stage(index: 2, name: "ちゅうぶ", codes: Array(15...23), isFree: false),
        Stage(index: 3, name: "きんき", codes: Array(24...30), isFree: false),
        Stage(index: 4, name: "ちゅうごく・しこく", codes: Array(31...39), isFree: false),
        Stage(index: 5, name: "きゅうしゅう・おきなわ", codes: Array(40...47), isFree: false),
        Stage(index: 6, name: "ぜんこく チャレンジ", codes: Array(1...47), isFree: false),
    ]

    static func stage(at index: Int) -> Stage? {
        all.first { $0.index == index }
    }
}
