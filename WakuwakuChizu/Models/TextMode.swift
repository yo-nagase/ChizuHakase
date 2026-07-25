import Foundation

/// Whether the interface writes for a child or for an adult.
///
/// The child mode is the product (CLAUDE.md §1: 「UI文言はすべてひらがな中心」),
/// so it is the default and stays the default — an adult reading over a
/// five-year-old's shoulder is the secondary audience, not the primary one.
/// Adult mode swaps in ordinary kanji-mixed Japanese, which is also what an
/// older sibling or a parent testing themselves would want.
///
/// This is a display concern only. It never changes what is asked, how it is
/// scored, or what is saved.
nonisolated enum TextMode: String, Codable, Sendable, CaseIterable {
    case kids
    case adult

    var isKids: Bool { self == .kids }

    /// Label for the setting itself — always shown in both scripts so whoever
    /// is holding the phone can find it.
    var settingLabel: String {
        switch self {
        case .kids: "こども (ひらがな)"
        case .adult: "おとな (漢字)"
        }
    }
}

// MARK: - Interface vocabulary
//
// Every user-facing string in one place. Keeping them together is what makes
// it possible to see at a glance that the child wording stays plain, short and
// affirmative (CLAUDE.md §12) while the adult wording is just ordinary
// Japanese — and it means a new screen cannot quietly ship in one script only.

nonisolated extension TextMode {

    // Title & navigation
    var appTitleTop: String { isKids ? "わくわく" : "わくわく" }
    var appTitleMain: String { isKids ? "ちずクイズ" : "地図クイズ" }
    var play: String { isKids ? "あそぶ" : "はじめる" }
    var myMap: String { isKids ? "マイマップ" : "マイマップ" }
    var cardBook: String { isKids ? "ずかん" : "図鑑" }
    var settings: String { isKids ? "せってい" : "設定" }
    var stages: String { isKids ? "ステージ" : "ステージ" }
    var close: String { isKids ? "とじる" : "閉じる" }
    var quit: String { isKids ? "やめる" : "やめる" }

    // Quiz
    var questionSuffix: String { isKids ? "は どこかな?" : "はどこ?" }
    var readAloud: String { isKids ? "もんだいを よむ" : "問題を読む" }
    var answerByVoice: String { isKids ? "こえで こたえる" : "音声で答える" }
    var listening: String { isKids ? "きいています" : "聞いています" }
    var hintNudge: String { isKids ? "ひかっている ところだよ" : "光っている場所です" }
    func questionCounter(_ current: Int, _ total: Int) -> String {
        isKids ? "\(total) もんちゅう \(current) もんめ" : "全\(total)問中 \(current)問目"
    }
    var combo: String { isKids ? "れんぞく!" : "連続!" }

    // Cards
    var cardWonNew: String { isKids ? "カードを もらったよ!" : "カードを獲得!" }
    var cardWonShiny: String { isKids ? "キラカードに なった!" : "キラカードになりました" }
    var cardWonDuplicate: String { isKids ? "もっている カードだね" : "所持済みのカードです" }
    var specialtyCards: String { isKids ? "とくさんひん カード" : "特産品カード" }
    var notCollectedYet: String { isKids ? "まだ もっていない カード" : "未取得のカード" }
    var allCategories: String { isKids ? "ぜんぶ" : "すべて" }

    // Result
    var points: String { isKids ? "てん" : "点" }
    var bestScore: String { isKids ? "さいこう" : "最高" }
    var playAgain: String { isKids ? "もういちど" : "もう一度" }
    var chooseStage: String { isKids ? "ステージを えらぶ" : "ステージを選ぶ" }
    var becameSparkling: String { isKids ? "✨ キラキラに なった けん!" : "✨ キラキラになった県" }
    func starCount(_ count: Int) -> String {
        isKids ? "ほし \(count) こ" : "星 \(count) 個"
    }

    // My map
    var sparklingCount: String { isKids ? "キラキラ" : "キラキラ" }
    var learnedCount: String { isKids ? "おぼえた" : "覚えた" }
    var stickerCount: String { isKids ? "シール" : "シール" }
    var resetZoom: String { isKids ? "もとの おおきさ" : "元の大きさ" }
    var eraseEverything: String { isKids ? "きろくを ぜんぶ けす" : "記録をすべて消去" }
    var eraseConfirm1: String { isKids ? "ほんとうに けしても いい?" : "本当に消去しますか?" }
    var eraseConfirm2: String { isKids ? "けすと もどせないよ。いい?" : "消去すると元に戻せません" }
    var eraseCancel: String { isKids ? "やめる" : "キャンセル" }
    var eraseNext: String { isKids ? "つぎへ" : "次へ" }
    var eraseConfirmAction: String { isKids ? "けす" : "消去する" }

    func masteryLabel(_ level: Int) -> String {
        switch (level, isKids) {
        case (..<1, true): "まだ"
        case (..<1, false): "未学習"
        case (1, true): "すこし おぼえた"
        case (1, false): "少し覚えた"
        case (2, true): "おぼえてきた"
        case (2, false): "覚えてきた"
        case (_, true): "キラキラ"
        case (_, false): "キラキラ"
        }
    }

    // Settings
    var soundSection: String { isKids ? "おと" : "音" }
    var soundEffects: String { isKids ? "こうかおん" : "効果音" }
    var speech: String { isKids ? "よみあげ" : "読み上げ" }
    var voiceSection: String { isKids ? "こえ" : "音声入力" }
    var voiceOnDeviceNote: String {
        isKids ? "こえは この iPhone の なかだけで しらべます。"
               : "音声はこの iPhone 内でのみ処理されます。"
    }
    var micDenied: String {
        isKids ? "マイクを つかえません。「せってい」から ゆるすと つかえます。"
               : "マイクを使用できません。iOS の設定から許可してください。"
    }
    var displaySection: String { isKids ? "もじ" : "文字表示" }
}

// MARK: - Data display

nonisolated extension Prefecture {
    /// Reading for children, kanji for adults. `spokenName` stays the reading
    /// either way — speech synthesis needs it to pronounce the name correctly.
    func displayName(_ mode: TextMode) -> String {
        mode.isKids ? kana : name
    }

    /// The smaller line underneath. Adults get the reading, children get the
    /// kanji they are gradually being exposed to.
    func secondaryName(_ mode: TextMode) -> String {
        mode.isKids ? name : kana
    }
}

nonisolated extension SpecialtyCard {
    func displayName(_ mode: TextMode) -> String {
        mode.isKids ? nameKana : nameKanji
    }
}

nonisolated extension SpecialtyCard.Category {
    func label(_ mode: TextMode) -> String {
        switch (self, mode.isKids) {
        case (.food, true): "たべもの"
        case (.food, false): "食べ物"
        case (.landmark, true): "めいしょ"
        case (.landmark, false): "名所"
        case (.nature, true): "しぜん"
        case (.nature, false): "自然"
        case (.craft, true): "つくるもの"
        case (.craft, false): "工芸"
        }
    }
}

nonisolated extension Stage {
    func displayName(_ mode: TextMode) -> String {
        mode.isKids ? name : kanjiName
    }
}
