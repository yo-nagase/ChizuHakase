import SwiftUI

/// The collection: all 141 cards, filterable by category, grouped by
/// prefecture. Unowned cards stay visible as silhouettes so there is something
/// to aim at.
struct CardBookView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.textMode) private var mode

    /// Which cards the book opens on. A caller that already knows what the
    /// child is looking for should not make them find it again.
    var initialFilter: CardFilter = .all

    @State private var filter: CardFilter?
    @State private var opened: SpecialtyCard?

    private var save: SaveData { app.save.data }
    private var active: CardFilter { filter ?? initialFilter }
    private var isOpeningOneCard: Bool {
        if case .card = active { true } else { false }
    }

    private var groups: [(prefecture: Prefecture, cards: [SpecialtyCard])] {
        app.mapData.prefectures.compactMap { pref in
            let cards = app.cards.cards(for: pref.code).filter { matches($0) }
            return cards.isEmpty ? nil : (pref, cards)
        }
    }

    private func matches(_ card: SpecialtyCard) -> Bool {
        switch active {
        case .all, .card: true
        case .category(let c): card.category == c
        case .shiny: save.isShiny(card.id)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(groups, id: \.prefecture.code) { group in
                        prefectureSection(group.prefecture, cards: group.cards)
                    }
                    emptyNote
                } header: {
                    filterBar
                }
            }
            .padding(16)
        }
        .background(AlbumPage())
        .navigationTitle(mode.cardBook)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if case .card(let id) = initialFilter { opened = app.cards[id] }
        }
        .fullScreenCover(item: $opened) { card in
            CardDetailView(card: card,
                           prefecture: app.mapData[card.prefectureCode],
                           ownedCount: save.ownedCount(of: card.id))
                .environment(\.textMode, mode)
                .presentationBackground(.clear)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Text("\(save.totalOwnedCards) / \(app.cards.count)")
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
                // Ahead of the categories: it is the one a child arrives here
                // looking for, and the one they will want to switch back to.
                chip(title: "✨ \(mode.sparklingCount)", isOn: active == .shiny) {
                    filter = active == .shiny ? .all : .shiny
                }
                ForEach(SpecialtyCard.Category.allCases, id: \.self) { c in
                    chip(title: "\(c.emoji) \(c.label(mode))",
                         isOn: active == .category(c)) {
                        filter = active == .category(c) ? .all : .category(c)
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .background(Palette.page)
    }

    /// Shown when a filter leaves nothing, so an empty book reads as "none yet"
    /// rather than as broken.
    @ViewBuilder private var emptyNote: some View {
        if groups.isEmpty {
            Text(mode.notCollectedYet)
                .font(AppFont.rounded(15, relativeTo: .body))
                .foregroundStyle(Palette.ink.opacity(0.55))
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        }
    }

    private func chip(title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(AppFont.rounded(14, relativeTo: .footnote))
                .foregroundStyle(isOn ? .white : Palette.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isOn ? Palette.orange : Color.white, in: Capsule())
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
                                 ownedCount: save.ownedCount(of: card.id),
                                 onOpen: { opened = card })
                }
            }
        }
    }
}


/// What the card book is showing.
nonisolated enum CardFilter: Hashable, Sendable {
    case all
    case category(SpecialtyCard.Category)
    /// The ones already turned キラ — the payoff, and what the title screen's
    /// ✨ count is counting.
    case shiny
    /// Everything, opened straight onto one card. Debug only, for looking at
    /// the detail view without tapping through the book to find it.
    case card(String)
}
