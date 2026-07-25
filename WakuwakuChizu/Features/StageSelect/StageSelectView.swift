import SwiftUI

/// Stage list with best records. Locked stages stay visible so the child can
/// see what exists, but the unlock prompt goes through a parental gate.
struct StageSelectView: View {
    @Environment(AppState.self) private var app

    var onPlay: (Stage) -> Void
    var onLocked: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(Stage.all) { stage in
                    StageRow(stage: stage,
                             record: app.save.data.record(forStage: stage.index),
                             isPlayable: app.isPlayable(stage)) {
                        app.isPlayable(stage) ? onPlay(stage) : onLocked()
                    }
                }
            }
            .padding(16)
        }
        .background(Palette.background)
        .navigationTitle("ステージ")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct StageRow: View {
    let stage: Stage
    let record: StageRecord?
    let isPlayable: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(stage.name)
                        .font(AppFont.rounded(19, relativeTo: .headline))
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.leading)
                    Text("\(stage.questionCount) もん")
                        .font(AppFont.rounded(12, relativeTo: .caption))
                        .foregroundStyle(Palette.ink.opacity(0.5))
                }
                Spacer(minLength: 8)

                if isPlayable {
                    VStack(alignment: .trailing, spacing: 3) {
                        HStack(spacing: 2) {
                            ForEach(1...3, id: \.self) { i in
                                Text(i <= (record?.stars ?? 0) ? "⭐️" : "☆")
                                    .font(.system(size: 15))
                            }
                        }
                        if let record, record.score > 0 {
                            Text("\(record.score)")
                                .font(AppFont.rounded(12, relativeTo: .caption))
                                .foregroundStyle(Palette.ink.opacity(0.5))
                                .monospacedDigit()
                        }
                    }
                } else {
                    Text("🔒")
                        .font(.system(size: 22))
                        .accessibilityLabel("まだ あそべない")
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(.white, in: RoundedRectangle(cornerRadius: 22))
            .opacity(isPlayable ? 1 : 0.55)
        }
        .buttonStyle(.plain)
    }
}
