import Foundation
import Testing

@testable import ChizuHakase

/// CLAUDE.md §7: voice answers must survive the ways a child and a recogniser
/// will actually spell a prefecture.
@MainActor
struct PrefectureNameMatcherTests {

    private var map: MapData { MapDataTests.map }

    @Test func acceptsKanaWithAndWithoutTheSuffix() throws {
        let tokyo = try #require(map[13])
        #expect(PrefectureNameMatcher.matches("とうきょうと", prefecture: tokyo))
        #expect(PrefectureNameMatcher.matches("とうきょう", prefecture: tokyo))
    }

    @Test func acceptsKanjiInBothForms() throws {
        let tokyo = try #require(map[13])
        #expect(PrefectureNameMatcher.matches("東京都", prefecture: tokyo))
        #expect(PrefectureNameMatcher.matches("東京", prefecture: tokyo))
    }

    @Test func acceptsKatakanaFromTheRecogniser() throws {
        let tokyo = try #require(map[13])
        #expect(PrefectureNameMatcher.matches("トウキョウ", prefecture: tokyo))
    }

    @Test func ignoresSurroundingWhitespaceAndPunctuation() throws {
        let osaka = try #require(map[27])
        #expect(PrefectureNameMatcher.matches("  おおさか 、", prefecture: osaka))
        #expect(PrefectureNameMatcher.matches("おおさか　ふ", prefecture: osaka))
    }

    /// -ken, -to, -fu and -do all have to come off.
    @Test func handlesEverySuffixKind() throws {
        #expect(PrefectureNameMatcher.matches("ほっかいどう", prefecture: try #require(map[1])))
        #expect(PrefectureNameMatcher.matches("きょうと", prefecture: try #require(map[26])))
        #expect(PrefectureNameMatcher.matches("おおさかふ", prefecture: try #require(map[27])))
        #expect(PrefectureNameMatcher.matches("あおもりけん", prefecture: try #require(map[2])))
    }

    @Test func rejectsADifferentPrefecture() throws {
        let tokyo = try #require(map[13])
        #expect(!PrefectureNameMatcher.matches("おおさか", prefecture: tokyo))
        #expect(!PrefectureNameMatcher.matches("", prefecture: tokyo))
    }

    /// Kyoto is the trap: 「きょうとふ」minus its suffix is 「きょうと」, which
    /// itself ends in a suffix character. Accepting forms rather than reducing
    /// to a single key is what keeps that working.
    @Test func kyotoSurvivesSuffixHandling() throws {
        let kyoto = try #require(map[26])
        #expect(PrefectureNameMatcher.matches("きょうとふ", prefecture: kyoto))
        #expect(PrefectureNameMatcher.matches("きょうと", prefecture: kyoto))
        #expect(PrefectureNameMatcher.matches("京都", prefecture: kyoto))
        #expect(!PrefectureNameMatcher.matches("きょう", prefecture: kyoto))
    }

    /// No two prefectures may accept the same spoken string, or a voice answer
    /// would be ambiguous and silently dropped.
    @Test func noTwoPrefecturesShareAnAcceptedForm() {
        var seen: [String: String] = [:]
        for pref in map.prefectures {
            for form in PrefectureNameMatcher.acceptedForms(for: pref) {
                if let other = seen[form] {
                    Issue.record("\(form) is accepted by both \(other) and \(pref.name)")
                }
                seen[form] = pref.name
            }
        }
        for pref in map.prefectures {
            #expect(!PrefectureNameMatcher.acceptedForms(for: pref).isEmpty)
        }
    }

    @Test func everyPrefectureMatchesItselfAndNothingElse() {
        for pref in map.prefectures {
            let hit = PrefectureNameMatcher.match(pref.kana, among: map.prefectures)
            #expect(hit?.code == pref.code,
                    "\(pref.kana) resolved to \(hit?.kana ?? "nothing")")
            let byKanji = PrefectureNameMatcher.match(pref.name, among: map.prefectures)
            #expect(byKanji?.code == pref.code,
                    "\(pref.name) resolved to \(byKanji?.name ?? "nothing")")
        }
    }

    @Test func unrecognisedSpeechMatchesNothing() {
        #expect(PrefectureNameMatcher.match("こんにちは", among: map.prefectures) == nil)
        #expect(PrefectureNameMatcher.match("", among: map.prefectures) == nil)
    }
}
