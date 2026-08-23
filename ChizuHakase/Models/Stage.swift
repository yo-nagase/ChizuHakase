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
    /// The one stage per atlas that draws the whole book in a single frame —
    /// 全国チャレンジ today, the world's challenge stage next (P7).
    ///
    /// Stored, not derived: this used to be `codes.count == 47`, which was
    /// really "is this japan's biggest stage" wearing a general name. The
    /// world's challenge spans 167 countries, and 47 of its ISO codes belong
    /// to other countries entirely — no count can tell a challenge apart.
    let isChallenge: Bool
    /// How far this stage's flat map may be pinched. Almost every stage keeps
    /// `GameRules.mapMaxZoom`: a regional map already draws its region as big
    /// as the frame allows, so 4× is where shapes outgrow the detail behind
    /// them. The world challenge is the exception — its frame spans the whole
    /// globe, and at 4× the small countries stay untappable — so its atlas
    /// derives a wider ceiling from the stage frames
    /// (`GameRules.challengeFlatMaxZoom`) and carries it here as a value, keeping
    /// the view free of any japan/world branch.
    let flatMaxZoom: CGFloat
    /// How far this stage's flat map may be pinched *out*, below the at-rest
    /// fit. Almost every stage keeps 1: japan's regional maps draw no
    /// neighbouring scenery, so shrinking them would only reveal false sea,
    /// and a challenge frame already holds its whole book. The world's
    /// regional stages are the exception — where the region sits on the globe
    /// is part of what they teach — so their atlas derives a floor from the
    /// data (`GameRules.regionalFlatMinZoom`) that lets a pinch shrink the
    /// region until the whole world is in the frame, and carries it here the
    /// same way `flatMaxZoom` carries the ceiling: as a value, never a branch.
    let flatMinZoom: CGFloat

    init(index: Int, name: String, kanjiName: String, codes: [Int],
         isChallenge: Bool = false, flatMaxZoom: CGFloat = GameRules.mapMaxZoom,
         flatMinZoom: CGFloat = 1) {
        self.index = index
        self.name = name
        self.kanjiName = kanjiName
        self.codes = codes
        self.isChallenge = isChallenge
        self.flatMaxZoom = flatMaxZoom
        self.flatMinZoom = flatMinZoom
    }

    var id: Int { index }

    /// Regional stages ask each prefecture twice.
    ///
    /// Once is a coin-flip a child can pass by luck, and with the answered
    /// prefectures no longer changing colour there is no elimination shortcut
    /// to shorten the second pass either. The challenge stage is exempt: 47
    /// questions is already a long sitting, and 94 would be a different
    /// activity.
    var asksEachTwice: Bool { !isChallenge }

    /// A challenge session is capped at `GameRules.challengeQuestionCount`.
    /// Japan's 47 codes pass through the `min` untouched — the stage is
    /// exactly as long as it has always been — and the world's 167 become one
    /// 47-question sitting (which countries fill it is the draw's job, not
    /// this count's).
    ///
    /// The regional arm's `* 2` is `asksEachTwice` in number form — the two
    /// express one rule, so change them together. `QuizViewModel` builds the
    /// actual order from `asksEachTwice`, and the VM/stage cross-check test
    /// (QuizViewModelTests) falls if the two drift apart.
    var questionCount: Int {
        isChallenge ? min(codes.count, GameRules.challengeQuestionCount)
                    : codes.count * 2
    }

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
              codes: Array(1...47), isChallenge: true),
    ]

    /// 日本編 7 面の看板スタンプ。index と同じ固定順。北海道・東北だけは
    /// 地域性の無かった気球から、承認済みの雪上のキタキツネへ差し替えた
    /// (Issue #11)。View はこの配列を知らず、Atlas が運んだ値だけを描く。
    static let landmarkAssetNames = [
        "stage-icon-ezo-red-fox", "stage-icon-tower", "stage-icon-fuji",
        "stage-icon-castle", "stage-icon-yuzu", "stage-icon-hibiscus",
        "stage-icon-globe",
    ]

    static func stage(at index: Int) -> Stage? {
        all.first { $0.index == index }
    }
}
