import SwiftUI

/// The collection: all 141 cards, filterable by category, grouped by
/// prefecture. Unowned cards stay visible as silhouettes so there is something
/// to aim at.
struct CardBookView: View {
    @Environment(AppState.self) private var app

    @State private var category: SpecialtyCard.Category?

    private var save: SaveData { app.save.data }

    private var groups: [(prefecture: Prefecture, cards: [SpecialtyCard])] {
        app.mapData.prefectures.compactMap { pref in
            let cards = app.cards.cards(for: pref.code)
                .filter { category == nil || $0.category == category }
            return cards.isEmpty ? nil : (pref, cards)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(groups, id: \.prefecture.code) { group in
                        prefectureSection(group.prefecture, cards: group.cards)
                    }
                } header: {
                    filterBar
                }
            }
            .padding(16)
        }
        .background(AlbumPage())
        .navigationTitle("ずかん")
        .navigationBarTitleDisplayMode(.inline)
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
                chip(title: "ぜんぶ", isOn: category == nil) { category = nil }
                ForEach(SpecialtyCard.Category.allCases, id: \.self) { c in
                    chip(title: "\(c.emoji) \(c.kanaLabel)", isOn: category == c) {
                        category = category == c ? nil : c
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .background(Palette.page)
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
    }

    private func prefectureSection(_ pref: Prefecture, cards: [SpecialtyCard]) -> some View {
        let owned = cards.filter { save.owns($0.id) }.count
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(pref.kana)
                    .font(AppFont.rounded(18, relativeTo: .headline))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text("\(owned) / \(cards.count)")
                    .font(AppFont.rounded(12, relativeTo: .caption))
                    .foregroundStyle(Palette.ink.opacity(0.45))
                    .monospacedDigit()
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10),
                                     count: 3), spacing: 10) {
                ForEach(cards) { card in
                    CardChipView(card: card, ownedCount: save.ownedCount(of: card.id))
                }
            }
        }
    }
}
