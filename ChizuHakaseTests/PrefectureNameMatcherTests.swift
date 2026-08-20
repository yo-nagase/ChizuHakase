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

    // MARK: - 世界(P6 Task 5)

    // 世界の国は境界で Prefecture になる(Atlas)ので、照合器は同じ関数のまま
    // 国名も引き受ける。増えたのは州体サフィックス(共和国・連邦 …)の 1 族だけ。

    static let world = Result {
        try WorldDataLoader.load(contentsOf: TestResources.require("WorldShapes"))
    }

    private func countries() throws -> [Prefecture] {
        Atlas.world(from: try Self.world.get()).mapData.prefectures
    }

    private func country(_ code: Int) throws -> Prefecture {
        try #require(Atlas.world(from: try Self.world.get()).mapData[code])
    }

    /// 「とうきょう」「とうきょうと」相当のゆれ: よみ・正式表記・かな書きの
    /// 正式名のどれで届いても同じ国にあたる。
    @Test func acceptsACountryInEverySpellingTheRecogniserWrites() throws {
        let america = try country(840)
        #expect(PrefectureNameMatcher.matches("あめりか", prefecture: america))
        #expect(PrefectureNameMatcher.matches("アメリカ", prefecture: america))
        #expect(PrefectureNameMatcher.matches("アメリカ合衆国", prefecture: america))
        #expect(PrefectureNameMatcher.matches("あめりかがっしゅうこく", prefecture: america))
    }

    /// 認識器は子どもの「みなみあふりか」を「南アフリカ」と書く — nameJa
    /// (南アフリカ共和国)とも kana とも一致しない、州体ストリップだけが
    /// 届く表記。
    @Test func acceptsTheKanjiShortFormTheRecogniserWrites() throws {
        #expect(PrefectureNameMatcher.matches("南アフリカ", prefecture: try country(710)))
        #expect(PrefectureNameMatcher.matches("中央アフリカ", prefecture: try country(140)))
        #expect(PrefectureNameMatcher.matches("アラブ首長国", prefecture: try country(784)))
    }

    /// 裸の「こんご」はどちらのコンゴにもあたらない。kana が接尾辞を残して
    /// いるのは両国を分けるためで、機械ストリップがそれを覆すと、
    /// コンゴ民主共和国の問題で「こんご」と言った子がコンゴ共和国を
    /// 誤答したことにされる。
    @Test func anAmbiguousBareNameMatchesNeitherCongo() throws {
        let congo = try country(178)
        let drCongo = try country(180)
        #expect(!PrefectureNameMatcher.matches("こんご", prefecture: congo))
        #expect(!PrefectureNameMatcher.matches("こんご", prefecture: drCongo))
        #expect(PrefectureNameMatcher.matches("こんごきょうわこく", prefecture: congo))
        #expect(PrefectureNameMatcher.matches("こんごみんしゅきょうわこく", prefecture: drCongo))
        #expect(!PrefectureNameMatcher.matches("こんごきょうわこく", prefecture: drCongo))
    }

    /// なまえあての候補はステージの国々から出る(選択肢はその部分集合)。
    /// その中で、正解でない国のよみはその国自身に解決される — 正解に
    /// 吸われて誤爆しない。
    @Test func aNonAnswerKanaResolvesToItsOwnCountryAmongStageChoices() throws {
        let atlas = Atlas.world(from: try Self.world.get())
        let eastAsia = try #require(atlas.stage(at: 15))
        let candidates = atlas.mapData.prefectures(in: eastAsia.codes)
        #expect(PrefectureNameMatcher.match("にほん", among: candidates)?.code == 392)
        #expect(PrefectureNameMatcher.match("たいわん", among: candidates)?.code == 158)
        #expect(PrefectureNameMatcher.match("きたちょうせん", among: candidates)?.code == 408)
        #expect(PrefectureNameMatcher.match("ぱり", among: candidates) == nil)
    }

    /// 日本版と同じ大域条件: 167 カ国のどの 2 国も受理形を共有しない。
    /// これと「自分のよみ・表記を受理する」の 2 つで、`match` が候補の中で
    /// 一意に解決することが従う(全対全の match は回さない — 高くつくだけ)。
    @Test func noTwoCountriesShareAnAcceptedForm() throws {
        var seen: [String: String] = [:]
        for country in try countries() {
            let forms = PrefectureNameMatcher.acceptedForms(for: country)
            #expect(!forms.isEmpty)
            for form in forms {
                if let other = seen[form] {
                    Issue.record("\(form) is accepted by both \(other) and \(country.name)")
                }
                seen[form] = country.name
            }
            #expect(PrefectureNameMatcher.matches(country.kana, prefecture: country))
            #expect(PrefectureNameMatcher.matches(country.name, prefecture: country))
        }
    }
}
