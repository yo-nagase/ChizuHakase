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
    var appTitleTop: String { isKids ? "めざせ!" : "めざせ!" }
    var appTitleMain: String { isKids ? "ちずはかせ" : "地図博士" }
    var play: String { isKids ? "あそぶ" : "はじめる" }
    var myMap: String { isKids ? "マイマップ" : "マイマップ" }
    /// The screen's own name, for its title bar.
    var cardBook: String { isKids ? "ずかん" : "図鑑" }
    /// The way in, for the button that opens it. A title bar names a place, but
    /// a button is easier to press when it says what pressing it does — and
    /// 「ずかん」 asks a five-year-old to already know that the cards live there.
    var viewCards: String { isKids ? "カードを みる" : "カードを見る" }
    var settings: String { isKids ? "せってい" : "設定" }
    var stages: String { isKids ? "ステージ" : "ステージ" }
    var close: String { isKids ? "とじる" : "閉じる" }
    var quit: String { isKids ? "やめる" : "やめる" }

    // Quiz
    var questionSuffix: String { isKids ? "は どこかな?" : "はどこ?" }
    /// 「なまえを あてる」 asks about the prefecture lit up on the map, so the
    /// question has no name in it to read out.
    var nameItQuestion: String { isKids ? "この けんは どこかな?" : "この県はどこ?" }
    var nameItPrompt: String { isKids ? "なまえを えらんでね" : "名前を選んでください" }
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
    /// A star that did not cross a tier. Said plainly — the card went up, and
    /// the stars on it are where a child reads how far.
    var cardWonStar: String { isKids ? "ほしが ふえた!" : "星が増えました" }
    var cardWonSilver: String { isKids ? "シルバーカードに なった!" : "シルバーカードになりました" }
    var cardWonGold: String { isKids ? "ゴールドカードに なった!" : "ゴールドカードになりました" }
    var cardWonDuplicate: String { isKids ? "もっている カードだね" : "所持済みのカードです" }
    var specialtyCards: String { isKids ? "とくさんひん カード" : "特産品カード" }
    /// Nil for a card with nothing to say about its tier yet. Katakana in both
    /// modes: シルバー and ゴールド are the words a six-year-old already has for
    /// second and first place.
    func cardTierName(_ tier: CardTier) -> String? {
        switch tier {
        case .none, .plain: nil
        case .silver: "シルバーカード"
        case .gold: "ゴールドカード"
        // Hiragana, not 虹: the tier names are the words the child uses for
        // them, and this one they can already read.
        case .rainbow: "にじいろカード"
        }
    }
    /// The book's tier filter chips. Shorter than `cardTierName` — on a chip
    /// the word カード is the whole bar repeating itself — and fronted by a
    /// medal the way the category chips front their emoji. The medals lean on
    /// the same knowledge the katakana does: second and first place are
    /// pictures a six-year-old already reads.
    func tierFilterName(_ tier: CardTier) -> String? {
        switch tier {
        case .none, .plain: nil
        case .silver: "🥈 シルバー"
        case .gold: "🥇 ゴールド"
        case .rainbow: "🌈 にじいろ"
        }
    }
    /// The 「あと◯」 line under a card (CLAUDE.md §5). It only ever counts
    /// toward the next thing — a streak that broke is not mentioned, because
    /// naming the loss is the loss (CLAUDE.md §12).
    func nextGoalLabel(_ goal: GameRules.NextGoal) -> String {
        switch goal {
        case .wins(let n, let tier):
            let name = tier == .gold ? "ゴールド" : "シルバー"
            return isKids ? "あと \(n)かいで \(name)!" : "あと\(n)回で\(name)"
        case .streak(let n):
            return isKids ? "あと \(n)れんぞくで にじいろ!" : "あと\(n)連続でにじいろ"
        case .done:
            return isKids ? "さいこうの カード!" : "最高のカード"
        }
    }
    var notCollectedYet: String { isKids ? "まだ もっていない カード" : "未取得のカード" }
    var allCategories: String { isKids ? "ぜんぶ" : "すべて" }

    // Result
    var points: String { isKids ? "てん" : "点" }
    var bestScore: String { isKids ? "さいこう" : "最高" }
    var playAgain: String { isKids ? "もういちど" : "もう一度" }
    var chooseStage: String { isKids ? "ステージを えらぶ" : "ステージを選ぶ" }
    /// The top of the mastery ladder is called 「おぼえた」, so reaching it is
    /// announced in the same word — a celebration named 「キラキラ」 over a
    /// legend that says 「おぼえた」 reads as two different achievements.
    var becameSparkling: String { isKids ? "✨ おぼえた けん!" : "✨ 覚えた県" }
    /// The rarest thing in the game, and the only one a child can reach without
    /// drawing anything — so it has to be said out loud here or it happens in
    /// silence.
    var becameRainbow: String { isKids ? "🌈 にじいろに なった カード!" : "🌈 にじいろになったカード" }
    func starCount(_ count: Int) -> String {
        isKids ? "ほし \(count) こ" : "星 \(count) 個"
    }

    // My map
    /// Silver and up, counted in cards. Katakana in both modes, like the tier
    /// names it is summarising. 「キラ」 is a card word only now — the fully
    /// learned *prefecture* is called 「おぼえた」 (`learnedCount`), so ✨ next
    /// to either count still reads unambiguously.
    var sparklingCards: String { isKids ? "キラカード" : "キラカード" }

    // Title tallies. Verbs, not bare nouns: 「けん」 and 「カード」 name the things
    // rather than what the number says about them, and the title screen is
    // where a child has the least context to guess from.
    var learnedPrefectures: String { isKids ? "おぼえた けん" : "覚えた県" }
    var ownedCards: String { isKids ? "もっている カード" : "持っているカード" }
    var learnedCount: String { isKids ? "おぼえた" : "覚えた" }
    var resetZoom: String { isKids ? "もとの おおきさ" : "元の大きさ" }
    /// How the one-finger zoom is discovered: press and hold, then slide up
    /// or down. Pinch works too, but nobody needs a label to find a pinch.
    var zoomHint: String { isKids ? "ながおしして うえしたで おおきく できるよ"
                                  : "長押しして上下で拡大縮小できます" }
    /// The nationwide map's one-press zooms. 「にほん」 spelt out rather than
    /// 「にし」「なか」「ひがし」 alone: a five-year-old meets these words here
    /// first, and the regions should sound like parts of the country.
    var westJapan: String { isKids ? "にしにほん" : "西日本" }
    var middleJapan: String { isKids ? "なかにほん" : "中日本" }
    var eastJapan: String { isKids ? "ひがしにほん" : "東日本" }
    var eraseEverything: String { isKids ? "きろくを ぜんぶ けす" : "記録をすべて消去" }
    var eraseConfirm1: String { isKids ? "ほんとうに けしても いい?" : "本当に消去しますか?" }
    var eraseConfirm2: String { isKids ? "けすと もどせないよ。いい?" : "消去すると元に戻せません" }
    var eraseCancel: String { isKids ? "やめる" : "キャンセル" }
    var eraseNext: String { isKids ? "つぎへ" : "次へ" }
    var eraseConfirmAction: String { isKids ? "けす" : "消去する" }

    /// Grouped the way the map colours are: the ladder has five levels but
    /// four visual states, and the words follow the states. The ladder ends on
    /// the word it climbs toward — まだ → すこし おぼえた → おぼえてきた →
    /// おぼえた. The gold still shimmers; it just is not *named* by its shimmer.
    func masteryLabel(_ level: Int) -> String {
        switch (level, isKids) {
        case (..<1, true): "まだ"
        case (..<1, false): "未学習"
        case (1...2, true): "すこし おぼえた"
        case (1...2, false): "少し覚えた"
        case (3...4, true): "おぼえてきた"
        case (3...4, false): "覚えてきた"
        case (_, true): "おぼえた"
        case (_, false): "覚えた"
        }
    }

    // Settings
    var soundSection: String { isKids ? "おと" : "音" }
    var music: String { isKids ? "おんがく" : "音楽" }
    /// The title-screen mute names the action a press performs, and the two
    /// states must not share a wording — to VoiceOver an identical label makes
    /// muting and unmuting the same button.
    var musicStop: String { isKids ? "おんがくを とめる" : "音楽を止める" }
    var musicPlay: String { isKids ? "おんがくを ならす" : "音楽を鳴らす" }
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
        case (.flag, true): "こっき"
        case (.flag, false): "国旗"
        }
    }
}

nonisolated extension Stage {
    func displayName(_ mode: TextMode) -> String {
        mode.isKids ? name : kanjiName
    }
}
