import Foundation

/// A bonus card earned by completing a whole part of an atlas.
///
/// Phantom cards are deliberately not another `CardTier`: ordinary cards grow
/// plain → silver → gold → rainbow, while these are one-off rewards with no
/// stars and no place in the normal draw pool.
nonisolated struct PhantomCard: Identifiable, Sendable, Hashable {
    enum Motif: String, Sendable, Hashable {
        case sky, earth, sea
        case northAmerica, southAmerica, europe, africa, asia, oceania, antarctica
    }

    enum UnlockRule: Sendable, Hashable {
        /// Every ordinary card belonging to every listed region is owned.
        case collectedRegionCards(Set<Int>)
        /// Used by Antarctica, which has no ordinary country cards in the atlas.
        case phantomCards(Set<String>)
    }

    let id: String
    let nameKana: String
    let nameKanji: String
    let descriptionKana: String
    let descriptionKanji: String
    let motif: Motif
    let setIndex: Int
    let setCount: Int
    let unlockRule: UnlockRule

    func displayName(_ mode: TextMode) -> String { mode.isKids ? nameKana : nameKanji }

    func displayDescription(_ mode: TextMode) -> String {
        mode.isKids ? descriptionKana : descriptionKanji
    }

    /// The cards that belong to one atlas. World group membership is read from
    /// the atlas's stage codes so it stays in step with WorldShapes.json instead
    /// of duplicating 167 ISO codes here.
    static func catalog(for atlas: Atlas) -> [PhantomCard] {
        switch atlas.saveKey {
        case SaveData.japanAtlas:
            return japan
        case SaveData.worldAtlas:
            func codes(in indexes: Set<Int>) -> Set<Int> {
                Set(atlas.stages.filter { indexes.contains($0.index) }.flatMap(\.codes))
            }
            let inhabited = [
                PhantomCard(id: "phantom-world-north-america",
                            nameKana: "きたアメリカ", nameKanji: "北アメリカ",
                            descriptionKana: "こおりと もりの ひかり",
                            descriptionKanji: "氷と森を巡る光",
                            motif: .northAmerica, setIndex: 1, setCount: 7,
                            unlockRule: .collectedRegionCards(codes(in: [0, 1]))),
                PhantomCard(id: "phantom-world-south-america",
                            nameKana: "みなみアメリカ", nameKanji: "南アメリカ",
                            descriptionKana: "たいがを めぐる ひかり",
                            descriptionKanji: "大河を巡る光",
                            motif: .southAmerica, setIndex: 2, setCount: 7,
                            unlockRule: .collectedRegionCards(codes(in: [2]))),
                PhantomCard(id: "phantom-world-europe",
                            nameKana: "ヨーロッパ", nameKanji: "ヨーロッパ",
                            descriptionKana: "まちを つなぐ ひかり",
                            descriptionKanji: "街をつなぐ光",
                            motif: .europe, setIndex: 3, setCount: 7,
                            unlockRule: .collectedRegionCards(codes(in: Set(3...6)))),
                PhantomCard(id: "phantom-world-africa",
                            nameKana: "アフリカ", nameKanji: "アフリカ",
                            descriptionKana: "だいちを てらす ひかり",
                            descriptionKanji: "大地を照らす光",
                            motif: .africa, setIndex: 4, setCount: 7,
                            unlockRule: .collectedRegionCards(codes(in: Set(7...11)))),
                PhantomCard(id: "phantom-world-asia",
                            nameKana: "アジア", nameKanji: "アジア",
                            descriptionKana: "やまを こえる ひかり",
                            descriptionKanji: "山を越える光",
                            motif: .asia, setIndex: 5, setCount: 7,
                            unlockRule: .collectedRegionCards(codes(in: Set(12...16)))),
                PhantomCard(id: "phantom-world-oceania",
                            nameKana: "オセアニア", nameKanji: "オセアニア",
                            descriptionKana: "うみを わたる ひかり",
                            descriptionKanji: "海を渡る光",
                            motif: .oceania, setIndex: 6, setCount: 7,
                            unlockRule: .collectedRegionCards(codes(in: [17]))),
            ]
            let sixIDs = Set(inhabited.map(\.id))
            return inhabited + [
                PhantomCard(id: "phantom-world-antarctica",
                            nameKana: "なんきょく", nameKanji: "南極",
                            descriptionKana: "さいごに ひらく こおりの ひかり",
                            descriptionKanji: "最後に開く氷の光",
                            motif: .antarctica, setIndex: 7, setCount: 7,
                            unlockRule: .phantomCards(sixIDs)),
            ]
        default:
            return []
        }
    }

    /// Re-evaluates to a fixed point so the sixth continent and Antarctica can
    /// unlock in the same result without making the order of the catalog matter.
    static func newlyUnlocked(
        from candidates: [PhantomCard],
        ordinaryCatalog: CardCatalog,
        save: AtlasSave
    ) -> Set<String> {
        var owned = save.phantomCards
        var changed = true
        while changed {
            changed = false
            for card in candidates where !owned.contains(card.id) {
                let ready: Bool
                switch card.unlockRule {
                case .collectedRegionCards(let codes):
                    ready = !codes.isEmpty && codes.allSatisfy { code in
                        let cards = ordinaryCatalog.cards(for: code)
                        return !cards.isEmpty && cards.allSatisfy { save.owns($0.id) }
                    }
                case .phantomCards(let required):
                    ready = !required.isEmpty && owned.isSuperset(of: required)
                }
                if ready {
                    owned.insert(card.id)
                    changed = true
                }
            }
        }
        return owned.subtracting(save.phantomCards)
    }

    private static let japan: [PhantomCard] = [
        PhantomCard(id: "phantom-japan-sky",
                    nameKana: "てん", nameKanji: "天",
                    descriptionKana: "ひがしの そらに うかぶ にほん",
                    descriptionKanji: "東の空に浮かぶ日本",
                    motif: .sky, setIndex: 1, setCount: 3,
                    unlockRule: .collectedRegionCards(Set(1...14))),
        PhantomCard(id: "phantom-japan-earth",
                    nameKana: "ち", nameKanji: "地",
                    descriptionKana: "まんなかの だいちに ねむる にほん",
                    descriptionKanji: "中央の大地に眠る日本",
                    motif: .earth, setIndex: 2, setCount: 3,
                    unlockRule: .collectedRegionCards(Set(15...30))),
        PhantomCard(id: "phantom-japan-sea",
                    nameKana: "うみ", nameKanji: "海",
                    descriptionKana: "にしの うみに きらめく にほん",
                    descriptionKanji: "西の海にきらめく日本",
                    motif: .sea, setIndex: 3, setCount: 3,
                    unlockRule: .collectedRegionCards(Set(31...47))),
    ]
}
