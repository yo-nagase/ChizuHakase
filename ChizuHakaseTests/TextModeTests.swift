import Foundation
import Testing

@testable import ChizuHakase

/// Child mode is the product (CLAUDE.md §1); adult mode is an accommodation on
/// top of it. These pin that the default never drifts and that neither mode
/// leaks the other's script.
@MainActor
struct TextModeTests {

    private var map: MapData { MapDataTests.map }
    private var catalog: CardCatalog { MapDataTests.catalog }

    // MARK: - Default

    @Test func freshSettingsAreChildMode() {
        #expect(Settings().textMode == .kids)
        #expect(SaveData().settings.textMode == .kids)
    }

    /// A save written before this setting existed belongs to a child.
    @Test func saveWithoutTheSettingDefaultsToChildMode() throws {
        let json = #"{"version":1,"settings":{"soundEnabled":true}}"#
        let decoded = try JSONDecoder().decode(SaveData.self, from: Data(json.utf8))
        #expect(decoded.settings.textMode == .kids)
    }

    @Test func modeRoundTripsThroughDisk() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("textmode-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        SaveStore(directory: dir).updateSettings { $0.textMode = .adult }
        #expect(SaveStore(directory: dir).data.settings.textMode == .adult)
    }

    // MARK: - Data display

    @Test func prefectureNamesFollowTheMode() throws {
        let tokyo = try #require(map[13])
        #expect(tokyo.displayName(.kids) == "とうきょうと")
        #expect(tokyo.displayName(.adult) == "東京都")
        // The secondary line shows the other script, so both are always present.
        #expect(tokyo.secondaryName(.kids) == "東京都")
        #expect(tokyo.secondaryName(.adult) == "とうきょうと")
    }

    @Test func everyStageHasBothNames() {
        for stage in Stage.all {
            #expect(!stage.displayName(.kids).isEmpty)
            #expect(!stage.displayName(.adult).isEmpty)
            #expect(stage.displayName(.kids) != stage.displayName(.adult),
                    "\(stage.name) has the same name in both modes")
        }
    }

    @Test func cardNamesFollowTheMode() throws {
        let crab = try #require(catalog["01-1"])
        #expect(crab.displayName(.kids) == crab.nameKana)
        #expect(crab.displayName(.adult) == crab.nameKanji)
    }

    // MARK: - Script hygiene

    private func containsKanji(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x4E00...0x9FFF).contains(Int($0.value)) }
    }

    /// The whole point of child mode: no kanji anywhere a child reads.
    /// Katakana is fine — 「ステージ」and 「カード」are how these things are
    /// written for children too.
    @Test func childModeInterfaceTextHasNoKanji() {
        for text in TextMode.kids.allInterfaceStrings {
            #expect(!containsKanji(text), "child-mode string contains kanji: \(text)")
        }
    }

    /// Adult mode must actually differ — otherwise the setting does nothing.
    @Test func adultModeDiffersWhereItShould() {
        let kids = TextMode.kids.allInterfaceStrings
        let adults = TextMode.adult.allInterfaceStrings
        #expect(kids.count == adults.count)
        let changed = zip(kids, adults).filter { $0 != $1 }.count
        #expect(changed >= kids.count / 3,
                "only \(changed) of \(kids.count) strings change; the mode is barely doing anything")
    }

    @Test func everyChildFacingStringIsNonEmpty() {
        for mode in TextMode.allCases {
            for text in mode.allInterfaceStrings {
                #expect(!text.isEmpty, "\(mode) has an empty interface string")
            }
        }
    }

    @Test func masteryLabelsCoverEveryLevel() {
        for mode in TextMode.allCases {
            for level in 0...GameRules.maxMastery {
                #expect(!mode.masteryLabel(level).isEmpty)
            }
            #expect(mode.masteryLabel(0) != mode.masteryLabel(3))
        }
    }

    /// ✨ marks two different things — a fully-learned prefecture and a
    /// silver-or-up card — and the title screen shows the card count next to a
    /// prefecture count. The words have to carry the difference, because the
    /// emoji cannot.
    @Test func theTwoSparklingCountsAreNamedApart() {
        for mode in TextMode.allCases {
            #expect(mode.learnedCount != mode.sparklingCards,
                    "prefectures and cards are both called 「\(mode.learnedCount)」")
        }
    }

    /// The mastery ladder ends on the word it climbs toward: まだ → すこし
    /// おぼえた → おぼえてきた → おぼえた. The top used to be 「キラキラ」, which
    /// broke the word family — and made the title's 「おぼえた けん」 read as a
    /// different measurement from the map's gold.
    @Test func theMasteryLadderEndsOnLearned() {
        #expect(TextMode.kids.masteryLabel(GameRules.maxMastery) == "おぼえた")
        #expect(TextMode.adult.masteryLabel(GameRules.maxMastery) == "覚えた")
        #expect(TextMode.kids.becameSparkling == "✨ おぼえた けん!")
        #expect(!TextMode.adult.becameSparkling.contains("キラキラ"))
    }

    @Test func categoryLabelsExistInBothModes() {
        for category in SpecialtyCard.Category.allCases {
            #expect(!category.label(.kids).isEmpty)
            #expect(!category.label(.adult).isEmpty)
            #expect(!containsKanji(category.label(.kids)),
                    "child category label has kanji: \(category.label(.kids))")
        }
    }

    /// The 「あと◯」 line counts toward what comes next and never mentions what
    /// broke — the streak resetting is not something the interface says.
    @Test func theNextGoalLineCountsUpTheLadder() {
        let kids = TextMode.kids
        #expect(kids.nextGoalLabel(.wins(3, to: .silver)) == "あと 3かいで シルバー!")
        #expect(kids.nextGoalLabel(.wins(10, to: .gold)) == "あと 10かいで ゴールド!")
        #expect(kids.nextGoalLabel(.streak(5)) == "あと 5れんぞくで にじいろ!")
        #expect(kids.nextGoalLabel(.done) == "さいこうの カード!")

        let adult = TextMode.adult
        #expect(adult.nextGoalLabel(.wins(3, to: .silver)) == "あと3回でシルバー")
        #expect(adult.nextGoalLabel(.wins(1, to: .gold)) == "あと1回でゴールド")
        #expect(adult.nextGoalLabel(.streak(5)) == "あと5連続でにじいろ")
        #expect(adult.nextGoalLabel(.done) == "最高のカード")
    }

    /// Speech must keep using the reading regardless of mode, or adult mode
    /// would make the app mispronounce prefecture names.
    @Test func spokenNameIsAlwaysTheReading() {
        for pref in map.prefectures {
            #expect(pref.spokenName == pref.kana)
            #expect(!containsKanji(pref.spokenName))
        }
    }
}

/// Every user-facing string, so the hygiene tests above cannot silently miss a
/// newly added one.
extension TextMode {
    var allInterfaceStrings: [String] {
        [appTitleTop, appTitleMain, play, myMap, cardBook, viewCards,
         settings, stages, close, quit,
         questionSuffix, readAloud, answerByVoice, listening, hintNudge, combo,
         questionCounter(1, 7),
         cardWonNew, cardWonStar, cardWonSilver, cardWonGold, cardWonDuplicate,
         specialtyCards, notCollectedYet,
         allCategories,
         points, bestScore, playAgain, chooseStage, becameSparkling, becameRainbow,
         starCount(3),
         sparklingCards, learnedPrefectures, ownedCards,
         learnedCount, stickerCount, resetZoom,
         eraseEverything, eraseConfirm1, eraseConfirm2, eraseCancel, eraseNext,
         eraseConfirmAction,
         soundSection, soundEffects, speech, voiceSection, voiceOnDeviceNote, micDenied,
         displaySection,
         masteryLabel(0), masteryLabel(1), masteryLabel(2), masteryLabel(3),
         masteryLabel(4), masteryLabel(5),
         cardTierName(.silver) ?? "", cardTierName(.gold) ?? "",
         cardTierName(.rainbow) ?? "",
         nextGoalLabel(.wins(3, to: .silver)), nextGoalLabel(.wins(10, to: .gold)),
         nextGoalLabel(.streak(5)), nextGoalLabel(.done)]
    }
}
