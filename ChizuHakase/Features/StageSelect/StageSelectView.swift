import SwiftUI

/// A shelf of regional signboards on a softly painted map page.
/// The region silhouette remains useful: it uses the same geometry and
/// mastery data as the quiz, while the surrounding treatment makes choosing a
/// stage feel like choosing the next stop on a journey.
struct StageSelectView: View {
    @Environment(AppState.self) private var app
    @Environment(\.textMode) private var mode
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The book this shelf pages through. Stages, map, records and mastery all
    /// come off this one value, so the view never asks which book it is in —
    /// japan and world differ only in the data handed here (design doc §3).
    let atlas: Atlas
    @Binding var quizMode: QuizMode
    var onPlay: (Stage) -> Void

    /// The played book's slice of the save. Every read below goes through this
    /// slice: a world signboard showing japan's records would be a lie twice
    /// over (wrong stars, and stage index 3 means a different place per book).
    private var save: AtlasSave { app.save.data.atlas(atlas.saveKey) }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                modeSwitch

                ForEach(atlas.stageShelves) { shelf in
                    if let title = shelf.title {
                        sectionHeader(title)
                    }

                    ForEach(shelf.stages) { stage in
                        StageSignboard(
                            stage: stage,
                            mapData: atlas.mapData,
                            record: save.record(forStage: stage.index,
                                                mode: quizMode),
                            save: save
                        ) {
                            SoundService.shared.play(
                                .decide, enabled: app.save.data.settings.soundEnabled)
                            onPlay(stage)
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 30)
            .pageColumn()
        }
        .background(StageAtlasBackground())
        .navigationTitle(mode.stages)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 36, height: 36)
                        .background(.white.opacity(0.82), in: Circle())
                        .overlay(Circle().strokeBorder(Color(hex: 0xD9B56B).opacity(0.6)))
                        .shadow(color: Palette.stickerShadow, radius: 3, y: 2)
                }
                .accessibilityLabel("もどる")
            }
        }
    }

    /// A continent label between shelf groups — rendered only when the atlas
    /// carries sections (the world; japan's shelf stays one unbroken run).
    /// Quiet on purpose: the signboards are the content, this is a finger
    /// between the pages, so it takes the same small-caption treatment as the
    /// my-map legend labels rather than any new asset.
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(AppFont.rounded(13, relativeTo: .caption))
            .foregroundStyle(Palette.ink.opacity(0.6))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.top, 14)
            .padding(.bottom, 2)
            .accessibilityAddTraits(.isHeader)
    }

    /// The question direction is part of the stage choice: records and stars
    /// below change with it, so it remains immediately above the signboards.
    private var modeSwitch: some View {
        GeometryReader { proxy in
            let segmentWidth = proxy.size.width / 2

            ZStack(alignment: .leading) {
                Image("stage-tab-rail")
                    .resizable()
                    .frame(width: proxy.size.width, height: 72)

                Image("stage-tab-selected")
                    .resizable()
                    .frame(width: segmentWidth + 5, height: 70)
                    .offset(x: quizMode == .findOnMap ? -2 : segmentWidth - 3)
                    .shadow(color: Palette.stickerShadow.opacity(0.45), radius: 3, y: 2)
                    .animation(reduceMotion ? nil : .spring(duration: 0.28), value: quizMode)

                HStack(spacing: 0) {
                    ForEach(QuizMode.allCases) { candidate in
                        Button {
                            quizMode = candidate
                        } label: {
                            VStack(spacing: 2) {
                                HStack(spacing: 5) {
                                    Image(candidate.stageTabIcon)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 21, height: 21)

                                    Text(candidate.title(mode))
                                        .font(AppFont.rounded(14, relativeTo: .subheadline))
                                        .foregroundStyle(Palette.ink)
                                }

                                Text(candidate.blurb(mode, region: atlas.regionNoun))
                                    .font(AppFont.rounded(9, relativeTo: .caption2))
                                    .foregroundStyle(Palette.ink.opacity(0.58))
                            }
                            .lineLimit(2)
                            .minimumScaleFactor(0.68)
                            .multilineTextAlignment(.center)
                            .frame(width: segmentWidth, height: 66)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(quizMode == candidate ? [.isSelected] : [])
                    }
                }
            }
        }
        .frame(height: 72)
    }
}

private extension QuizMode {
    var stageTabIcon: String {
        switch self {
        case .findOnMap: "stage-tab-icon-map"
        case .nameIt: "stage-tab-icon-name"
        }
    }
}

// MARK: - Signboard

private struct StageSignboard: View {
    @Environment(\.textMode) private var mode
    let stage: Stage
    let mapData: MapData
    let record: StageRecord?
    /// One atlas's slice, not the whole save: the board can only ever read the
    /// book it belongs to, so a world signboard cannot show japan's mastery.
    let save: AtlasSave
    var action: () -> Void

    private var learnedCount: Int {
        stage.codes.filter { save.masteryLevel(of: $0) >= GameRules.maxMastery }.count
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                StageCardBackground(stageIndex: stage.index)

                HStack(spacing: 8) {
                    silhouette
                        .frame(width: 72, height: 68)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(stage.displayName(mode))
                            .font(AppFont.heading(17, relativeTo: .headline))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.58)

                        HStack(spacing: 3) {
                            ForEach(1...3, id: \.self) { i in
                                StarBadge(filled: i <= (record?.stars ?? 0), size: 17)
                            }

                            scoreLabel
                                .padding(.leading, 5)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // Keep this third row in the layout even before a
                        // region is learned. Otherwise cards with a chip push
                        // their title upward while untouched cards centre the
                        // same title, and the shelf's baselines visibly jump.
                        countChip("✨ \(mode.learnedCount) \(learnedCount)")
                            .opacity(learnedCount > 0 ? 1 : 0)
                            .accessibilityHidden(learnedCount == 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    StageLandmark(stageIndex: stage.index)
                        .frame(width: 42, height: 54)
                        .padding(.leading, 1)
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 6)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 84)
            .contentShape(Rectangle())
        }
        .buttonStyle(SignPressStyle())
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var scoreLabel: some View {
        if let record, record.score > 0 {
            Text(verbatim: "\(record.score) \(mode.points)")
                .font(AppFont.rounded(13, relativeTo: .caption))
                .foregroundStyle(Palette.ink.opacity(0.66))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }

    private func countChip(_ text: String) -> some View {
        Text(text)
            .font(AppFont.rounded(12, relativeTo: .caption))
            .foregroundStyle(Palette.goldInk)
            .monospacedDigit()
            .padding(.horizontal, 10)
            .padding(.vertical, 1)
            .background(Color.white.opacity(0.86), in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.gold.opacity(0.65), lineWidth: 1.2))
            .shadow(color: Palette.stickerShadow.opacity(0.7), radius: 0, y: 1)
    }

    private var silhouette: some View {
        PrefectureMapView(
            mapData: mapData,
            codes: stage.codes,
            appearance: { MasteryStyle.appearance(for: $0.code, save: save) },
            // Sticker-sized: at 84pt the dashed frame is noise and the grey
            // scenery would drown the stage's own shapes.
            showsInsetFrames: false,
            showsBackground: false)
        .allowsHitTesting(false)
        .shadow(color: Palette.ink.opacity(0.12), radius: 0, y: 1)
    }

    private var accessibilityText: String {
        var text = "\(stage.displayName(mode))。\(stage.questionCount) もん。"
            + mode.starCount(record?.stars ?? 0)
        if learnedCount > 0 { text += "。\(mode.learnedCount) \(learnedCount)" }
        return text
    }
}

/// The reference uses a paper-thin watercolor sign, not an app-style rounded
/// card. One neutral generated board is tinted here so every region keeps the
/// same delicate edge, seams and sparse grain.
private struct StageCardBackground: View {
    let stageIndex: Int

    private var tint: Color { Self.tints[stageIndex % Self.tints.count] }

    var body: some View {
        GeometryReader { proxy in
            Image("stage-sign-plank")
                .resizable()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .saturation(0.78)
                .colorMultiply(tint)
                .shadow(color: Color(hex: 0x806C52).opacity(0.20), radius: 2, y: 2)
        }
    }

    /// Sampled from the supplied screenshot's signboard washes. The seventh
    /// stage continues the sequence with quiet mint.
    ///
    /// The world's 18 signboards reuse these seven by the same `% count`
    /// cycle: neighbouring boards never share a wash, and a repeat only comes
    /// back seven rows later — further apart than one screen shows at once.
    private static let tints: [Color] = [
        Color(hex: 0xFFDCDA), Color(hex: 0xFFEFD8), Color(hex: 0xFFFBD6),
        Color(hex: 0xE4F2E3), Color(hex: 0xDAF2FE), Color(hex: 0xF0DFF2),
        Color(hex: 0xDDF1ED),
    ]
}

// MARK: - Regional landmarks

private struct StageLandmark: View {
    let stageIndex: Int

    var body: some View {
        Image(Self.assetNames[stageIndex % Self.assetNames.count])
            .resizable()
            .scaledToFit()
        .shadow(color: Palette.ink.opacity(0.16), radius: 0, y: 1)
        .accessibilityHidden(true)
    }

    /// Seven stamps for japan's seven stages. The world's 18 boards cycle
    /// through the same seven (`% count` above) — 富士山 on みなみアメリカ is
    /// admittedly a postcard from the wrong continent, but a decorative stamp,
    /// not a fact the quiz teaches. World-specific landmark art is deliberately
    /// deferred out of P6 (plan Task 1); drawing 18 honest landmarks is its
    /// own art task.
    private static let assetNames = [
        "stage-icon-balloon", "stage-icon-tower", "stage-icon-fuji",
        "stage-icon-castle", "stage-icon-yuzu", "stage-icon-hibiscus",
        "stage-icon-globe",
    ]
}

// MARK: - Page

struct StageAtlasBackground: View {
    var body: some View {
        // Sized from Color.clear, not the image: scaledToFill reports the
        // *covering* size, so a bare Image used as a ZStack child (the quiz
        // screen) widens the whole stack past the screen and pushes the
        // header and map off its edges. Color.clear keeps the layout size at
        // exactly what was proposed wherever this page is placed.
        Color.clear
            .overlay {
                Image("stage-atlas-background")
                    .resizable()
                    .scaledToFill()
            }
            .clipped()
            .ignoresSafeArea()
    }
}

/// Drawn rather than the ⭐️/☆ emoji pair, which render at different optical
/// sizes and make rows feel uneven.
struct StarBadge: View {
    var filled: Bool
    var size: CGFloat = 22

    var body: some View {
        StarShape()
            .fill(filled ? Palette.gold : Palette.emptySlot)
            .overlay {
                StarShape()
                    .stroke(filled ? Palette.goldInk.opacity(0.72)
                                   : Palette.ink.opacity(0.30),
                            lineWidth: max(1, size * 0.08))
            }
            .frame(width: size, height: size)
            .shadow(color: filled ? Palette.gold.opacity(0.55) : .clear, radius: 3)
    }
}

private struct StarShape: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = outerRadius * 0.45
        var path = Path()

        for point in 0..<10 {
            let radius = point.isMultiple(of: 2) ? outerRadius : innerRadius
            let angle = -CGFloat.pi / 2 + CGFloat(point) * CGFloat.pi / 5
            let position = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius)

            if point == 0 {
                path.move(to: position)
            } else {
                path.addLine(to: position)
            }
        }

        path.closeSubpath()
        return path
    }
}

private struct SignPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
            .offset(y: configuration.isPressed && !reduceMotion ? 2 : 0)
            .animation(.spring(duration: 0.18), value: configuration.isPressed)
    }
}
