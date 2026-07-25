import SwiftUI

/// How one prefecture is painted. The quiz and the my-map screen differ only
/// in the appearance they hand back, which is why this is a closure and not a
/// mode enum baked into the view.
nonisolated struct PrefectureAppearance: Equatable {
    var fill: Color
    var stroke: Color = .white
    var lineWidth: CGFloat = 1.2
    /// Gold outline used for mastery level 3.
    var isSparkling: Bool = false
    /// Specialty emoji floating above the shape after a correct answer.
    var badge: String?

    static let hidden = PrefectureAppearance(fill: .clear, stroke: .clear, lineWidth: 0)
}

/// A one-shot visual reaction targeted at a single prefecture.
/// `id` changes on every new event so repeats of the same kind still fire.
nonisolated struct MapEffect: Equatable {
    enum Kind: Equatable { case pop, shake }
    var code: Int
    var kind: Kind
    var id: Int
}

/// Draws a set of prefectures and resolves taps (CLAUDE.md §3).
///
/// Shared by the quiz and the my-map screen so the shape, the fit and the hit
/// test can never drift apart between them.
struct PrefectureMapView: View {
    let mapData: MapData
    /// Prefectures to draw, in stage order.
    let codes: [Int]
    var appearance: (Prefecture) -> PrefectureAppearance
    /// Prefectures a tap may resolve to. Usually the not-yet-answered ones.
    var interactiveCodes: Set<Int> = []
    /// The prefecture being asked about — the only one granted near-miss slack.
    var targetCode: Int?
    /// Blinks a red outline once the child has missed twice.
    var hintCode: Int?
    var effect: MapEffect?
    var showsOkinawaInset = true
    var onTap: ((Prefecture?) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var prefectures: [Prefecture] { mapData.prefectures(in: codes) }

    var body: some View {
        GeometryReader { geo in
            let transform = PrefectureGeometry.fitTransform(
                bounds: PrefectureGeometry.boundingBox(of: prefectures),
                into: geo.size)

            ZStack(alignment: .topLeading) {
                if showsOkinawaInset, codes.contains(47) {
                    OkinawaInsetFrame(rect: mapData.okinawaInset.applying(transform))
                }

                ForEach(prefectures) { prefecture in
                    PrefectureLayer(
                        prefecture: prefecture,
                        transform: transform,
                        canvasSize: geo.size,
                        appearance: appearance(prefecture),
                        isHinted: hintCode == prefecture.code,
                        effect: effect?.code == prefecture.code ? effect : nil,
                        reduceMotion: reduceMotion)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .onTapGesture { location in
                guard let onTap else { return }
                onTap(resolve(location, transform: transform))
            }
        }
    }

    /// Direct hit first, then the near-miss allowance for the asked prefecture.
    private func resolve(_ point: CGPoint, transform: CGAffineTransform) -> Prefecture? {
        let candidates = prefectures.filter { interactiveCodes.contains($0.code) }
        guard !candidates.isEmpty else { return nil }
        let target = targetCode.flatMap { mapData[$0] }
        return PrefectureGeometry.resolveTap(at: point, target: target,
                                             among: candidates, transform: transform)
    }
}

// MARK: - One prefecture

private struct PrefectureLayer: View {
    let prefecture: Prefecture
    let transform: CGAffineTransform
    let canvasSize: CGSize
    let appearance: PrefectureAppearance
    let isHinted: Bool
    let effect: MapEffect?
    let reduceMotion: Bool

    private var path: Path {
        PrefectureGeometry.path(for: prefecture, transform: transform)
    }

    private var screenCentroid: CGPoint {
        PrefectureGeometry.screenCentroid(of: prefecture, transform: transform)
    }

    /// scaleEffect anchors in unit space of the whole canvas, and the path
    /// carries absolute coordinates, so the anchor is the centroid as a
    /// fraction of the canvas.
    private var anchor: UnitPoint {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return .center }
        return UnitPoint(x: screenCentroid.x / canvasSize.width,
                         y: screenCentroid.y / canvasSize.height)
    }

    var body: some View {
        shape
            .modifier(PopEffect(trigger: triggerID(for: .pop), anchor: anchor,
                                enabled: !reduceMotion))
            .modifier(ShakeEffect(trigger: triggerID(for: .shake),
                                  enabled: !reduceMotion))
            .overlay(alignment: .topLeading) { badge }
            .accessibilityElement()
            .accessibilityLabel(prefecture.name)
            .accessibilityAddTraits(.isButton)
    }

    private var shape: some View {
        ZStack(alignment: .topLeading) {
            // Holes are handled by the fill rule rather than by subtracting
            // paths, which is why every ring can live in one Path.
            path.fill(appearance.fill, style: FillStyle(eoFill: true))
            path.stroke(appearance.stroke, lineWidth: appearance.lineWidth)

            if appearance.isSparkling {
                path.stroke(Palette.gold, lineWidth: 2.4)
                    .modifier(SlowGlow(enabled: !reduceMotion))
            }
            if isHinted {
                path.stroke(Palette.red, lineWidth: 3)
                    .modifier(HintBlink(enabled: !reduceMotion))
            }
        }
    }

    @ViewBuilder private var badge: some View {
        if let badge = appearance.badge {
            Text(badge)
                .font(.system(size: 26))
                .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                .modifier(RiseEffect(enabled: !reduceMotion))
                .position(x: screenCentroid.x, y: screenCentroid.y)
                .allowsHitTesting(false)
        }
    }

    /// Only the targeted prefecture sees a changing trigger, so the others
    /// stay still.
    private func triggerID(for kind: MapEffect.Kind) -> Int {
        guard let effect, effect.kind == kind else { return 0 }
        return effect.id
    }
}

// MARK: - Effects
//
// Every one of these is a no-op when Reduce Motion is on; the state change is
// still legible because colour carries it (CLAUDE.md §9).

private struct PopEffect: ViewModifier {
    let trigger: Int
    let anchor: UnitPoint
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.keyframeAnimator(initialValue: 1.0, trigger: trigger) { view, scale in
                view.scaleEffect(scale, anchor: anchor)
            } keyframes: { _ in
                // 1.0 -> 1.22 -> 0.95 -> 1.0 across 0.55s (CLAUDE.md §5).
                KeyframeTrack {
                    CubicKeyframe(1.22, duration: 0.18)
                    CubicKeyframe(0.95, duration: 0.19)
                    CubicKeyframe(1.00, duration: 0.18)
                }
            }
        } else {
            content
        }
    }
}

private struct ShakeEffect: ViewModifier {
    let trigger: Int
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, dx in
                view.offset(x: dx)
            } keyframes: { _ in
                // Sideways wobble, 0.45s. Never a red flash or an X: a wrong
                // answer should read as "not that one", not as a scolding.
                KeyframeTrack {
                    CubicKeyframe(-7, duration: 0.09)
                    CubicKeyframe(7, duration: 0.09)
                    CubicKeyframe(-4, duration: 0.09)
                    CubicKeyframe(4, duration: 0.09)
                    CubicKeyframe(0, duration: 0.09)
                }
            }
        } else {
            content
        }
    }
}

private struct HintBlink: ViewModifier {
    let enabled: Bool
    @State private var on = false

    func body(content: Content) -> some View {
        if enabled {
            content
                .opacity(on ? 1 : 0.15)
                .animation(.easeInOut(duration: GameRules.hintBlinkPeriod / 2)
                    .repeatForever(autoreverses: true), value: on)
                .onAppear { on = true }
        } else {
            content.opacity(1)
        }
    }
}

private struct SlowGlow: ViewModifier {
    let enabled: Bool
    @State private var on = false

    func body(content: Content) -> some View {
        if enabled {
            content
                .opacity(on ? 1 : 0.5)
                .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true),
                           value: on)
                .onAppear { on = true }
        } else {
            content
        }
    }
}

private struct RiseEffect: ViewModifier {
    let enabled: Bool
    @State private var lifted = false

    func body(content: Content) -> some View {
        if enabled {
            content
                .offset(y: lifted ? -26 : 0)
                .opacity(lifted ? 0 : 1)
                .scaleEffect(lifted ? 1.3 : 0.7)
                .animation(.easeOut(duration: 0.9), value: lifted)
                .onAppear { lifted = true }
        } else {
            content
        }
    }
}

// MARK: - Okinawa inset

/// Dashed box around the relocated Okinawa so it reads as a separate frame
/// rather than Okinawa's real position (CLAUDE.md §3).
private struct OkinawaInsetFrame: View {
    let rect: CGRect

    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .strokeBorder(Palette.ink.opacity(0.35),
                          style: StrokeStyle(lineWidth: 1.6, dash: [6, 5]))
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
    }
}

#Preview("ぜんこく") {
    let app = AppState()
    return PrefectureMapView(
        mapData: app.mapData,
        codes: Stage.all[6].codes,
        appearance: { PrefectureAppearance(fill: Palette.fill(for: $0.code)) },
        interactiveCodes: Set(1...47))
    .padding()
    .background(Palette.seaGradient)
}

#Preview("きんき") {
    let app = AppState()
    return PrefectureMapView(
        mapData: app.mapData,
        codes: Stage.all[3].codes,
        appearance: { PrefectureAppearance(fill: Palette.fill(for: $0.code)) },
        interactiveCodes: Set(24...30))
    .padding()
    .background(Palette.seaGradient)
}
