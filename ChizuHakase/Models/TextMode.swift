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

// MARK: - Atlas-carried nouns

/// A kids/adult word pair carried by an atlas (ちずちょう).
///
/// Born as "the noun the open book puts into otherwise shared sentences"
/// (けん ⇄ くに), the role has since widened to any word pair that rides the
/// `Atlas` value the way its draw policy and save key do: the card panel's
/// standalone title, and the region-zoom button labels — which are neither
/// slotted into a shared sentence nor a difference between the books (japan's
/// zooms simply *are* japanese geography). What stays constant is the
/// discipline: the view asks the value for the word and never asks which book
/// it is in.
nonisolated struct AtlasNoun: Sendable, Equatable {
    let kids: String
    let adult: String

    /// The script the current mode reads — same shape as `displayName(_:)`.
    func label(_ mode: TextMode) -> String { mode.isKids ? kids : adult }
}

nonisolated extension AtlasNoun {
    /// 日本: the thing a stage asks about. Only the standalone noun — a
    /// prefecture's own けん (「あいちけん」) is part of its name, not this.
    static let prefecture = AtlasNoun(kids: "けん", adult: "県")
    static let country = AtlasNoun(kids: "くに", adult: "国")
    /// 日本のカード欄の見出し。
    static let specialtyCards = AtlasNoun(kids: "とくさんひん カード",
                                          adult: "特産品カード")
    /// 世界のカード欄の見出し。「こっきカード」ではなく「せかいの カード」:
    /// P8 でオリジナル札が国旗の隣に並んでも(設計 §5)この見出しは嘘に
    /// ならない。札の種別名(国旗カード)は個々の札が言う。呼び名は設計文書が
    /// 先に選んだもの — 動機の表がずかんの空きマスを「せかいのカード」と
    /// 呼んでいる(docs/plans/2026-08-16-world-atlas-design.md:22)。
    static let worldCards = AtlasNoun(kids: "せかいの カード", adult: "世界のカード")
    /// 世界: 国旗がシルバーに達したとき解放される 2 枚目の札の呼称。
    /// `Atlas.unlockGoalNoun(for:)` が返し、「あと◯かいで」の silver 段の
    /// 名前に差し替わる — シルバー到達 = 解放が同じ出来事なので、予告は
    /// 段位ではなくもらえる物を名乗る。
    /// ★仮文言(ユーザーサインオフ待ち — 「おりじなるカード」等の代案あり)。
    /// カタカナは両表記共通: シルバー・ゴールドと同じ扱いで、札の種別名は
    /// 子どもがそのまま使う語。
    static let originalCard = AtlasNoun(kids: "オリジナルカード",
                                        adult: "オリジナルカード")

    /// The nationwide map's one-press zooms — the japan atlas carries these on
    /// its `RegionZoom`s. 「にほん」 spelt out rather than 「にし」「なか」
    /// 「ひがし」 alone: a five-year-old meets these words here first, and the
    /// regions should sound like parts of the country.
    static let eastJapan = AtlasNoun(kids: "ひがしにほん", adult: "東日本")
    static let middleJapan = AtlasNoun(kids: "なかにほん", adult: "中日本")
    static let westJapan = AtlasNoun(kids: "にしにほん", adult: "西日本")
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
    /// 「なまえを あてる」 asks about the region lit up on the map, so the
    /// question has no name in it to read out — only the atlas's noun.
    func nameItQuestion(_ region: AtlasNoun) -> String {
        isKids ? "この \(region.kids)は どこかな?" : "この\(region.adult)はどこ?"
    }
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
    // The card panel's title is the atlas's `cardNoun` (「とくさんひん カード」
    // ⇄ 「せかいの カード」), rendered through `AtlasNoun.label(_:)` above.
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
    ///
    /// `unlock` renames the *silver* rung only: on the world's flag cards,
    /// reaching silver and unlocking the country's second card are the same
    /// event (`GameRules.DrawPolicy.flagFirstSilverGate`), so the line promises
    /// the thing the child gets rather than the tier. Gold, streak and done are
    /// untouched — the unlock happens once, at silver, and there is nothing to
    /// promise above it. `NextGoal.fraction` stays as it is: the rung's end
    /// point is the same silver either way, only its name changes.
    func nextGoalLabel(_ goal: GameRules.NextGoal, unlock: AtlasNoun? = nil) -> String {
        switch goal {
        case .wins(let n, let tier):
            let name = tier == .gold ? "ゴールド" : unlock?.label(self) ?? "シルバー"
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
    /// The thing that was learned is the atlas's noun: けん on japan's result
    /// screen, くに on the world's.
    func becameSparkling(_ region: AtlasNoun) -> String {
        isKids ? "✨ おぼえた \(region.kids)!" : "✨ 覚えた\(region.adult)"
    }
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
    /// The learned tally, counted in whatever the open book asks about.
    /// Everything else about the two pages' tallies reads identically — same
    /// artwork, same bar — so this one noun is the whole difference the child
    /// sees between their numbers.
    func learnedTally(_ region: AtlasNoun) -> String {
        isKids ? "おぼえた \(region.kids)" : "覚えた\(region.adult)"
    }
    var ownedCards: String { isKids ? "もっている カード" : "持っているカード" }

    // Title pages. Each page-edge tab names where it leads, not where the
    // child is — a door is labelled by its far side (design doc §2: swipe
    // alone is undiscoverable at five, so these tabs are the visible way).
    var toWorldAtlas: String { isKids ? "せかいの ちずへ" : "世界の地図へ" }
    var toJapanAtlas: String { isKids ? "にほんの ちずへ" : "日本の地図へ" }
    var learnedCount: String { isKids ? "おぼえた" : "覚えた" }
    var resetZoom: String { isKids ? "もとの おおきさ" : "元の大きさ" }
    // 地球儀 ⇄ 平面のトグルチップ(地球儀データを運ぶ本のチャレンジだけに
    // 出る)。チップは行き先を名乗る — タイトルのページ端タブと同じ
    // 「扉は向こう側の名前」。
    // ★ユーザーサインオフ待ちの仮文言(計画 2026-08-20 P7)。
    var toGlobe: String { isKids ? "🌍 ちきゅうぎ" : "🌍 地球儀" }
    var toFlatMap: String { isKids ? "🗺️ ちず" : "🗺️ 地図" }
    /// VoiceOver だけが聞く調整つまみのラベル(GlobeMapView.rotateStepper)。
    /// ドラッグで回せない利用者が裏側の国へ届く唯一の口なので、
    /// 動詞で「何が起きるか」を名乗る。
    var rotateGlobe: String { isKids ? "ちきゅうぎを まわす" : "地球儀を回す" }
    /// How the one-finger zoom is discovered: press and hold, then slide up
    /// or down. Pinch works too, but nobody needs a label to find a pinch.
    var zoomHint: String { isKids ? "ながおしして うえしたで おおきく できるよ"
                                  : "長押しして上下で拡大縮小できます" }
    // The region zoom labels (にしにほん…) live on `AtlasNoun` above — they
    // are the japan atlas's words, carried by its `RegionZoom`s.
    var eraseEverything: String { isKids ? "きろくを ぜんぶ けす" : "記録をすべて消去" }
    var eraseConfirm1: String { isKids ? "ほんとうに けしても いい?" : "本当に消去しますか?" }
    /// The second confirmation names both books: the erase is whole-app, and
    /// a child on the world page must not think only that page's records go.
    /// 「にほん」「せかい」 are the words the title's page tabs already taught —
    /// not 「ちずちょう」, which never appears on the glass.
    var eraseConfirm2: String { isKids ? "にほんも せかいも けすと もどせないよ。いい?"
                                       : "日本も世界も消去すると元に戻せません" }
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
