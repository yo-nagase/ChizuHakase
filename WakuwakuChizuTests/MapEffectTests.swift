import Testing

@testable import WakuwakuChizu

/// What each prefecture does with the one effect the map broadcasts.
///
/// The map publishes a single `MapEffect` and every prefecture decides whether
/// it is the addressee. Getting that wrong is invisible in a screenshot and
/// obvious to a child: the country twitches in places nobody touched.
@MainActor
struct MapEffectTests {

    private func shake(_ id: Int) -> MapEffect { MapEffect(code: 5, kind: .shake, id: id) }
    private func pop(_ id: Int) -> MapEffect { MapEffect(code: 5, kind: .pop, id: id) }

    @Test func aMissFiresTheShakeOnce() {
        var triggers = EffectTriggers()
        #expect(triggers.shake == 0)
        triggers.apply(shake(1))
        #expect(triggers.shake != 0, "a miss on this prefecture did not fire its shake")
    }

    /// The bug this type exists for.
    ///
    /// Missing a second prefecture hands the first one `nil`, and the trigger
    /// used to be derived straight from the current effect — so it fell back to
    /// the sentinel, which is a change, which replays the animation. A child who
    /// missed 青森 and then missed 岩手 watched 青森 shake at them again.
    @Test func anEffectAimedElsewhereLeavesThisPrefectureAlone() {
        var triggers = EffectTriggers()
        triggers.apply(shake(1))
        let afterTheMiss = triggers.shake

        triggers.apply(nil)
        #expect(triggers.shake == afterTheMiss,
                "a prefecture shook again because a different one was tapped")
    }

    /// `advance()` clears the effect between questions, which is the same nil.
    @Test func clearingTheEffectBetweenQuestionsIsNotAnEvent() {
        var triggers = EffectTriggers()
        triggers.apply(pop(1))
        let afterThePop = triggers.pop

        triggers.apply(nil)
        #expect(triggers.pop == afterThePop,
                "the correct prefecture popped a second time as the next question arrived")
    }

    /// The two kinds share a prefecture but not a trigger. Popping used to reset
    /// the shake to the sentinel, so a prefecture that had been missed shook
    /// again at the moment it was finally got right.
    @Test func aPopDoesNotReplayAnEarlierShake() {
        var triggers = EffectTriggers()
        triggers.apply(shake(1))
        let afterTheMiss = triggers.shake

        triggers.apply(pop(2))
        #expect(triggers.shake == afterTheMiss, "getting it right replayed the miss")
        #expect(triggers.pop != 0, "the pop did not fire")
    }

    /// Repeats still have to fire: two misses on the same prefecture are two
    /// events, and a shake that plays only the first time reads as a dropped
    /// tap.
    @Test func eachMissOnTheSamePrefectureFiresAgain() {
        var triggers = EffectTriggers()
        triggers.apply(shake(1))
        let first = triggers.shake
        triggers.apply(shake(2))
        #expect(triggers.shake != first, "the second miss on the same prefecture was silent")
    }

    /// The layers stack in `codes` order, so an animating prefecture used to
    /// slide *under* every neighbour drawn after it — the pop, the floating
    /// specialty emoji and all, half-swallowed by the next shape over. The
    /// addressee of the live effect must ride above its siblings, and the
    /// blinking answer above the crowd, or a neighbour's die-cut carves into
    /// its outline.
    @Test func theAnimatingPrefectureRisesAboveItsNeighbours() {
        let view = PrefectureMapView(
            mapData: MapDataTests.map,
            codes: Array(1...47),
            appearance: { PrefectureAppearance.slot(for: $0.code) },
            hintCode: 13,
            effect: MapEffect(code: 5, kind: .pop, id: 1))
        #expect(view.zIndex(for: 5) > view.zIndex(for: 6),
                "the popping prefecture is not lifted above its neighbours")
        #expect(view.zIndex(for: 13) > view.zIndex(for: 6),
                "the hinted answer's outline can be cut by a later neighbour")
        #expect(view.zIndex(for: 5) > view.zIndex(for: 13),
                "the thing moving right now outranks the thing blinking")
        #expect(view.zIndex(for: 6) == view.zIndex(for: 7),
                "everyone else stays flat")
    }
}
