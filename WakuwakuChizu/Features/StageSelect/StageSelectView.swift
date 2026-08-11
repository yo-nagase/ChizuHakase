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

    @Binding var quizMode: QuizMode
    var onPlay: (Stage) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                modeSwitch
                ForEach(Stage.all) { stage in
                    StageSheet(stage: stage,
                               mapData: app.mapData,
                               record: app.save.data.record(forStage: stage.index,
                                                            mode: quizMode),
                               stuckCount: stuckCount(stage),
                               sparklingCount: sparklingCount(stage)) {
                        onPlay(stage)
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

    /// Which way the questions run.
    ///
    /// Sits above the shelf rather than in settings: it changes what the next
    /// tap does, and the stars underneath are per mode, so the two have to be
    /// visible together or the records look like they reset themselves.
    private var modeSwitch: some View {
        HStack(spacing: 10) {
            ForEach(QuizMode.allCases) { candidate in
                Button {
                    quizMode = candidate
                } label: {
                    VStack(spacing: 3) {
                        Text("\(candidate.symbol) \(candidate.title(mode))")
                            .font(AppFont.rounded(15, relativeTo: .subheadline))
                            .foregroundStyle(Palette.ink)
                        Text(candidate.blurb(mode))
                            .font(AppFont.rounded(10, relativeTo: .caption2))
                            .foregroundStyle(Palette.ink.opacity(0.5))
                    }
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(quizMode == candidate ? .white : Color(hex: 0xF3EDE0))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(quizMode == candidate ? Palette.orange : .clear,
                                          lineWidth: 2.5)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(quizMode == candidate ? [.isSelected] : [])
            }
        }
    }

    /// How many of this stage's prefectures the child has stuck down at all.
    private func stuckCount(_ stage: Stage) -> Int {
        stage.codes.filter { app.save.data.masteryLevel(of: $0) > 0 }.count
    }

    /// How many have reached the top of the mastery ladder — 「おぼえた」
    /// (CLAUDE.md §5).
    private func sparklingCount(_ stage: Stage) -> Int {
        stage.codes.filter { app.save.data.masteryLevel(of: $0) >= GameRules.maxMastery }.count
    }
}

private struct StageSheet: View {
    @Environment(\.textMode) private var mode
    let stage: Stage
    let mapData: MapData
    let record: StageRecord?
    let stuckCount: Int
    let sparklingCount: Int
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

                    HStack(spacing: 3) {
                        ForEach(1...3, id: \.self) { i in
                            StarBadge(filled: i <= (record?.stars ?? 0), size: 19)
                        }
                        if let record, record.score > 0 {
                            // With its unit, and dark enough to read on every
                            // stock — a bare pale number floating by the stars
                            // read as debug output.
                            Text(verbatim: "\(record.score) \(mode.points)")
                                .font(AppFont.rounded(13, relativeTo: .caption))
                                .foregroundStyle(Palette.ink.opacity(0.62))
                                .monospacedDigit()
                                .padding(.leading, 4)
                        }
                    }
                    HStack(spacing: 8) {
                        // Out of the stage's *prefectures*, which is what
                        // `stuckCount` counts. Against `questionCount` a
                        // regional stage could never pass half — every one of
                        // them asks each prefecture twice — so a child who had
                        // covered all of Kanto was shown 「7 / 14」 and told
                        // they were halfway (CLAUDE.md §12).
                        countChip("\(mode.stickerCount) \(stuckCount) / \(stage.codes.count)",
                                  tint: Palette.ink.opacity(0.75),
                                  border: Palette.ink.opacity(0.10))

                        // Only once there is one to show. A 「✨ 0 / 9」 on every
                        // untouched stage would read as something missing
                        // rather than as something still to find.
                        if sparklingCount > 0 {
                            countChip("✨ \(mode.learnedCount) \(sparklingCount)",
                                      tint: Palette.goldInk,
                                      border: Palette.gold.opacity(0.65))
                        }
                    }
                    .padding(.top, 2)
                }

                Spacer(minLength: 4)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            // Keyed on the stage, not on its first prefecture code: by code,
            // 関東・近畿・九州 all land on the same pink and 中部・中国 on the
            // same teal, so the shelf reads as three repeated cards. Seven
            // stages into an eight-colour palette gives each its own.
            .stickerCard(fill: Palette.fill(for: stage.index, strength: 0.30))
        }
        .buttonStyle(SheetPressStyle())
        .accessibilityLabel(accessibilityText)
    }

    /// A count on its own small white label, stuck to the sheet.
    ///
    /// The sheets come in seven pastels and the counts used to sit straight on
    /// them — gold lettering on the pale-yellow 中部 sheet was invisible. A
    /// white base under the text makes the contrast independent of whichever
    /// stock is behind it, and a little white label on a coloured sheet is
    /// already this app's visual language.
    private func countChip(_ text: String, tint: Color, border: Color) -> some View {
        Text(text)
            .font(AppFont.rounded(13, relativeTo: .caption))
            .foregroundStyle(tint)
            .monospacedDigit()
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(.white, in: Capsule())
            .overlay(Capsule().strokeBorder(border, lineWidth: 1))
            .shadow(color: Palette.stickerShadow, radius: 0, y: 1)
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
        var text = "\(stage.displayName(mode))。\(stage.questionCount) もん。"
            + "\(mode.starCount(record?.stars ?? 0))。"
            + "\(mode.stickerCount) \(stuckCount)"
        if sparklingCount > 0 { text += "。\(mode.learnedCount) \(sparklingCount)" }
        return text
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
