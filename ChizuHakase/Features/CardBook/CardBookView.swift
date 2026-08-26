import SwiftUI

/// The collection: Japan's catalog stays grouped by prefecture with unowned
/// silhouettes to aim at. The world book is the child's travel stack instead:
/// only cards already won, in the order they were first obtained.
struct CardBookView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.textMode) private var mode

    /// The book on display. Catalog, region names and the owned stars all come
    /// off this one value and its save slice — card IDs collide as strings
    /// across books (world "12-1" is アルジェリア's flag, japan's is 千葉の
    /// らっかせい), so a lookup outside the atlas shows the wrong card.
    let atlas: Atlas

    /// Which cards the book opens on. A caller that already knows what the
    /// child is looking for should not make them find it again.
    var initialFilter: CardFilter = .all

    @State private var filter: CardFilter?
    @State private var opened: SpecialtyCard?
    @State private var openedPhantom: PhantomCard?

    private var save: AtlasSave { app.save.data.atlas(atlas.saveKey) }
    private var active: CardFilter { filter ?? initialFilter }
    private var isOpeningOneCard: Bool {
        if case .card = active { true } else { false }
    }

    /// The categories with at least one card in this book's catalog.
    private var dealtCategories: Set<SpecialtyCard.Category> {
        Set(atlas.cards.all.map(\.category))
    }

    private var groups: [(prefecture: Prefecture, cards: [SpecialtyCard])] {
        atlas.mapData.prefectures.compactMap { pref in
            let cards = atlas.cards.cards(for: pref.code).filter { matches($0) }
            return cards.isEmpty ? nil : (pref, cards)
        }
    }

    private var worldCards: [SpecialtyCard] {
        save.ownedCardsInAcquisitionOrder(from: atlas.cards).filter { matches($0) }
    }

    private var isWorldBook: Bool { atlas.saveKey == SaveData.worldAtlas }
    private var phantomCards: [PhantomCard] { PhantomCard.catalog(for: atlas) }
    private var isShowingPhantom: Bool { active == .phantom }

    /// Opens with the cover's own slide suppressed.
    ///
    /// A full-screen cover comes up from the bottom edge, which is the gesture
    /// for a sheet of paper being pushed onto a desk. A card is picked up — it
    /// should arrive from depth, which is what CardDetailView animates once the
    /// system is not also sliding the whole thing.
    private func open(_ card: SpecialtyCard) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { opened = card }
    }

    private func matches(_ card: SpecialtyCard) -> Bool {
        switch active {
        case .all, .card: true
        case .phantom: false
        case .category(let c): card.category == c
        // The exact rung, the way `cardCount(ofTier:)` counts: a rainbow card
        // under the gold filter would put one card behind two chips, and a
        // child hunting their rainbows deserves a filter with only rainbows
        // in it.
        case .tier(let t): save.tier(of: card.id) == t
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16, pinnedViews: [.sectionHeaders]) {
                Section {
                    if isShowingPhantom {
                        phantomCardGrid
                    } else if isWorldBook {
                        worldCardGrid
                    } else {
                        ForEach(groups, id: \.prefecture.code) { group in
                            prefectureSection(group.prefecture, cards: group.cards)
                        }
                    }
                    emptyNote
                } header: {
                    filterBar
                }
            }
            .padding(16)
            .pageColumn()
        }
        .background(CardBookParchmentBackground())
        .navigationTitle(mode.cardBook)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            app.save.reconcilePhantomCards(catalog: atlas.cards,
                                           phantomCards: phantomCards,
                                           atlas: atlas.saveKey)
            if case .card(let id) = initialFilter, let card = atlas.cards[id] { open(card) }
        }
        .fullScreenCover(item: $opened) { card in
            CardDetailView(card: card,
                           prefecture: atlas.mapData[card.prefectureCode],
                           stars: save.stars(of: card.id),
                           rainbow: save.isRainbow(card.id),
                           streak: save.streak(of: card.prefectureCode),
                           unlock: atlas.unlockGoalNoun(for: card))
                .environment(\.textMode, mode)
                .presentationBackground(.clear)
        }
        .fullScreenCover(item: $openedPhantom) { card in
            PhantomCardDetailView(card: card)
                .environment(\.textMode, mode)
                .presentationBackground(.clear)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Text(isShowingPhantom
                     ? "\(save.phantomCards.intersection(Set(phantomCards.map(\.id))).count) / \(phantomCards.count)"
                     : "\(save.totalOwnedCards) / \(atlas.cards.count)")
                    .font(AppFont.rounded(14, relativeTo: .footnote))
                    .foregroundStyle(Palette.ink.opacity(0.6))
                    .monospacedDigit()
            }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: mode.allCategories,
                     isOn: active == .all || isOpeningOneCard) { filter = .all }
                chip(title: mode.phantomCards,
                     isOn: isShowingPhantom,
                     onFill: AnyShapeStyle(LinearGradient(
                        colors: [.indigo, .purple, .cyan],
                        startPoint: .topLeading, endPoint: .bottomTrailing))) {
                    filter = isShowingPhantom ? .all : .phantom
                }
                // Ahead of the categories: the payoff is what a child arrives
                // here looking for. One chip per tier rather than a single
                // キラカード bundle — a child asking "where are my golds?" was
                // being answered with silvers mixed in.
                ForEach([CardTier.silver, .gold, .rainbow], id: \.self) { tier in
                    tierChip(tier)
                }
                // Only the categories this book actually deals: `flag` exists
                // for the world atlas, and a chip whose filter can never show
                // a card is a button that teaches "buttons do nothing".
                ForEach(SpecialtyCard.Category.allCases.filter(dealtCategories.contains),
                        id: \.self) { c in
                    chip(title: "\(c.emoji) \(c.label(mode))",
                         isOn: active == .category(c)) {
                        filter = active == .category(c) ? .all : .category(c)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    /// A tier's filter chip, lit in the tier's own colour when selected — the
    /// same rule the card faces and the win banner follow, so "the silver one"
    /// means the same thing everywhere.
    @ViewBuilder private func tierChip(_ tier: CardTier) -> some View {
        if let name = mode.tierFilterName(tier) {
            chip(title: name,
                 isOn: active == .tier(tier),
                 onFill: tierFill(tier),
                 // The rainbow wash is pastel; white on it disappears.
                 onInk: tier == .rainbow ? Palette.ink : .white) {
                filter = active == .tier(tier) ? .all : .tier(tier)
            }
        }
    }

    private func tierFill(_ tier: CardTier) -> AnyShapeStyle {
        switch tier {
        case .silver: AnyShapeStyle(Palette.silverMark)
        case .gold: AnyShapeStyle(Palette.gold)
        case .rainbow: AnyShapeStyle(LinearGradient(stops: Palette.rainbowRamp,
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing))
        default: AnyShapeStyle(Palette.orange)
        }
    }

    /// Shown when a filter leaves nothing, so an empty book reads as "none yet"
    /// rather than as broken.
    @ViewBuilder private var emptyNote: some View {
        if !isShowingPhantom && (isWorldBook ? worldCards.isEmpty : groups.isEmpty) {
            Text(mode.notCollectedYet)
                .font(AppFont.rounded(15, relativeTo: .body))
                .foregroundStyle(Palette.ink.opacity(0.55))
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        }
    }

    private var worldCardGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10),
                                 count: typeSize.cardColumns), spacing: 10) {
            ForEach(worldCards) { card in
                CardChipView(card: card,
                             prefecture: atlas.mapData[card.prefectureCode],
                             stars: save.stars(of: card.id),
                             rainbow: save.isRainbow(card.id),
                             onOpen: { open(card) })
            }
        }
    }

    private var phantomCardGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10),
                                 count: typeSize.cardColumns), spacing: 10) {
            ForEach(phantomCards) { card in
                let owned = save.phantomCards.contains(card.id)
                VStack(spacing: 5) {
                    PhantomCardFaceView(card: card, isOwned: owned, metrics: .chip)
                    Text(owned ? card.displayName(mode) : "???")
                        .font(AppFont.heading(14, relativeTo: .caption))
                        .foregroundStyle(Palette.ink.opacity(owned ? 0.86 : 0.42))
                        .lineLimit(1)
                }
                    .contentShape(Rectangle())
                    .onTapGesture { if owned { openedPhantom = card } }
                    .accessibilityAddTraits(owned ? .isButton : [])
            }
        }
    }

    private func chip(title: String, isOn: Bool,
                      onFill: AnyShapeStyle = AnyShapeStyle(Palette.orange),
                      onInk: Color = .white,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(AppFont.rounded(14, relativeTo: .footnote))
                .foregroundStyle(isOn ? onInk : Palette.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isOn ? onFill : AnyShapeStyle(Color.white), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    private func prefectureSection(_ pref: Prefecture, cards: [SpecialtyCard]) -> some View {
        let owned = cards.filter { save.owns($0.id) }.count
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(pref.displayName(mode))
                    .font(AppFont.rounded(18, relativeTo: .headline))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text("\(owned) / \(cards.count)")
                    .font(AppFont.rounded(12, relativeTo: .caption))
                    .foregroundStyle(Palette.ink.opacity(0.45))
                    .monospacedDigit()
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10),
                                     count: typeSize.cardColumns), spacing: 10) {
                ForEach(cards) { card in
                    CardChipView(card: card,
                                 stars: save.stars(of: card.id),
                                 rainbow: save.isRainbow(card.id),
                                 onOpen: { open(card) })
                }
            }
        }
    }
}

/// A quiet centre keeps the cards and labels readable while the painted map
/// details around the edge make the collection feel like an explorer's atlas.
private struct CardBookParchmentBackground: View {
    var body: some View {
        Image("card-book-parchment-background")
            .resizable()
            .scaledToFill()
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

/// What the card book is showing.
nonisolated enum CardFilter: Hashable, Sendable {
    case all
    case phantom
    case category(SpecialtyCard.Category)
    /// One exact rung of the ladder — silver, gold or rainbow. This replaced
    /// a single "silver and up" キラカード filter, which answered "where are my
    /// golds?" with silvers mixed in.
    case tier(CardTier)
    /// Everything, opened straight onto one card. Debug only, for looking at
    /// the detail view without tapping through the book to find it.
    case card(String)
}
