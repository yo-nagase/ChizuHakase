import SwiftUI

/// Stage picker, built as a shelf of sticker sheets.
///
/// The old version was a settings list: white rows, tiny star glyphs, a padlock
/// emoji. It told the child nothing about where they were going. Each card now
/// shows the region's **actual silhouette**, drawn from the same map data the
/// quiz uses, so the shape of Kanto or Kyushu is familiar before the first
/// question is asked — and the sticker count says what there is to collect.
struct StageSelectView: View {
    @Environment(AppState.self) private var app
    @Environment(\.textMode) private var mode

    var onPlay: (Stage) -> Void
    var onLocked: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(Stage.all) { stage in
                    StageSheet(stage: stage,
                               mapData: app.mapData,
                               record: app.save.data.record(forStage: stage.index),
                               stuckCount: stuckCount(stage),
                               isPlayable: app.isPlayable(stage)) {
                        app.isPlayable(stage) ? onPlay(stage) : onLocked()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
        }
        .background(AlbumPage())
        .navigationTitle(mode.stages)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// How many of this stage's prefectures the child has stuck down at all.
    private func stuckCount(_ stage: Stage) -> Int {
        stage.codes.filter { app.save.data.masteryLevel(of: $0) > 0 }.count
    }
}

private struct StageSheet: View {
    @Environment(\.textMode) private var mode
    let stage: Stage
    let mapData: MapData
    let record: StageRecord?
    let stuckCount: Int
    let isPlayable: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                silhouette
                    .frame(width: 76, height: 76)

                VStack(alignment: .leading, spacing: 6) {
                    Text(stage.displayName(mode))
                        .font(AppFont.rounded(19, relativeTo: .headline))
                        .foregroundStyle(Palette.ink)
                        // Wraps rather than truncating: 「ちゅうごく…」 tells a
                        // child nothing about where they are going.
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                        .fixedSize(horizontal: false, vertical: true)

                    if isPlayable {
                        HStack(spacing: 3) {
                            ForEach(1...3, id: \.self) { i in
                                StarBadge(filled: i <= (record?.stars ?? 0), size: 19)
                            }
                            if let record, record.score > 0 {
                                Text(verbatim: "\(record.score)")
                                    .font(AppFont.rounded(13, relativeTo: .caption))
                                    .foregroundStyle(Palette.ink.opacity(0.5))
                                    .monospacedDigit()
                                    .padding(.leading, 4)
                            }
                        }
                        Text("\(mode.stickerCount) \(stuckCount) / \(stage.questionCount)")
                            .font(AppFont.rounded(12, relativeTo: .caption))
                            .foregroundStyle(Palette.ink.opacity(0.5))
                            .monospacedDigit()
                    } else {
                        Text(mode.lockedHint)
                            .font(AppFont.rounded(12, relativeTo: .caption))
                            .foregroundStyle(Palette.ink.opacity(0.5))
                    }
                }

                Spacer(minLength: 4)

                if !isPlayable {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(Palette.ink.opacity(0.28))
                        .accessibilityLabel(mode.lockedLabel)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            // Locked stages stay fully legible — they are something to look
            // forward to, not something to be hidden from (CLAUDE.md §12).
            .stickerCard(fill: isPlayable
                         ? Palette.fill(for: stage.codes.first ?? 0, strength: 0.30)
                         : Color(hex: 0xEDE7DA))
        }
        .buttonStyle(SheetPressStyle())
        .accessibilityLabel(accessibilityText)
    }

    /// The region, drawn as the sticker it will become.
    private var silhouette: some View {
        PrefectureMapView(
            mapData: mapData,
            codes: stage.codes,
            appearance: { PrefectureAppearance.stuck(for: $0.code) },
            showsOkinawaInset: false)
        .allowsHitTesting(false)
    }

    private var accessibilityText: String {
        let name = stage.displayName(mode)
        guard isPlayable else { return "\(name)。\(mode.lockedLabel)" }
        return "\(name)。\(stage.questionCount) もん。\(mode.starCount(record?.stars ?? 0))"
    }
}

/// Drawn rather than the ⭐️/☆ emoji pair, which render at different optical
/// sizes and made the old rows look accidental.
struct StarBadge: View {
    var filled: Bool
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: filled ? "star.fill" : "star")
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(filled ? Palette.gold : Palette.emptySlot)
            .shadow(color: filled ? Palette.gold.opacity(0.55) : .clear, radius: 3)
    }
}

/// Presses the whole sheet into the page instead of dimming it.
private struct SheetPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(.spring(duration: 0.18), value: configuration.isPressed)
    }
}
