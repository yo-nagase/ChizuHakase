import SwiftUI

/// How one prefecture is painted. The quiz and the my-map screen differ only
/// in the appearance they hand back, which is why this is a closure and not a
/// mode enum baked into the view.
nonisolated struct PrefectureAppearance: Equatable {
    var fill: Color
    var stroke: Color = Palette.dieCut
    /// キラ: gold edge plus the holographic sheen (CLAUDE.md §5, level 3).
    var isSparkling: Bool = false
    /// A stuck sticker gets the white die-cut edge and lifts off the page.
    /// False is the album's faintly pre-printed slot — visible, so the map is
    /// never a grey blank, but obviously not yet earned.
    var isStuck: Bool = true
    /// Specialty emoji floating up from a prefecture just won.
    var badge: String?

    /// The pre-printed slot: the prefecture's own colour, washed out.
    static func slot(for code: Int) -> PrefectureAppearance {
        PrefectureAppearance(fill: Palette.fill(for: code, strength: 0.22),
                             stroke: Palette.boundary,
                             isStuck: false)
    }

    /// A sticker pressed onto the page.
    static func stuck(for code: Int, strength: Double = 1, sparkling: Bool = false,
                      badge: String? = nil) -> PrefectureAppearance {
        PrefectureAppearance(fill: Palette.fill(for: code, strength: strength),
                             isSparkling: sparkling,
                             isStuck: true,
                             badge: badge)
    }
}

/// A streak called out where the finger landed.
///
/// Anchored to the tap rather than to the prefecture's centre: the child is
/// already looking at their fingertip, and on 全国チャレンジ a centred label can
/// land on a different island from the one they just touched.
nonisolated struct ComboBurst: Equatable {
    /// Where to put it. A spoken answer has no fingertip, so it falls back to
    /// the prefecture itself rather than dropping the celebration.
    enum Anchor: Equatable {
        /// In the map's own coordinates, as handed back by `onTap`.
        case point(CGPoint)
        case prefecture(Int)
    }

    var text: String
    var anchor: Anchor
    /// 1...3, louder as the run grows (`GameRules.comboTier`).
    var tier: Int
    /// Changes per burst so two streaks in a row both animate.
    var id: Int
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
    /// How much the caller has magnified this view.
    ///
    /// Outlines are drawn before `scaleEffect` is applied, so at 4x a 1.5pt
    /// border lands as 6pt and swallows the small prefectures whole. Dividing
    /// by the zoom keeps every line the same width on the glass no matter how
    /// far in the child has pinched.
    var zoom: CGFloat = 1
    var comboBurst: ComboBurst?
    /// Hands back what was hit and where the finger actually landed, in this
    /// view's own coordinates.
    var onTap: ((Prefecture?, CGPoint) -> Void)?

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

                // One shadow for the whole sheet of stuck stickers rather than
                // 47 individual ones: a single draw, and it reads correctly
                // because adjacent prefectures form one contiguous cut-out.
                stuckSilhouette(transform: transform)
                    .fill(Palette.stickerShadow)
                    .offset(y: min(max(geo.size.width * 0.008, 1), Sticker.lift))
                    .blur(radius: min(max(geo.size.width * 0.007, 0.8), 2.5))
                    .allowsHitTesting(false)

                ForEach(prefectures) { prefecture in
                    PrefectureLayer(
                        prefecture: prefecture,
                        transform: transform,
                        canvasSize: geo.size,
                        zoom: zoom,
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
                onTap(resolve(location, transform: transform), location)
            }
            .overlay(alignment: .topLeading) { comboLabel(transform: transform) }
        }
    }

    /// The streak call-out, at the tap.
    ///
    /// Counter-scaled by the zoom for the same reason the outlines are divided
    /// by it: this sits inside the magnified content, and at 4x an unscaled
    /// label would cover half the country.
    @ViewBuilder private func comboLabel(transform: CGAffineTransform) -> some View {
        if let comboBurst, let point = burstPoint(comboBurst.anchor, transform: transform) {
            ComboBurstLabel(burst: comboBurst, reduceMotion: reduceMotion)
                .scaleEffect(1 / max(zoom, 1))
                .position(point)
                .allowsHitTesting(false)
                // Keyed on the burst so a second streak restarts the animation
                // instead of inheriting the finished state of the first.
                .id(comboBurst.id)
        }
    }

    private func burstPoint(_ anchor: ComboBurst.Anchor,
                            transform: CGAffineTransform) -> CGPoint? {
        switch anchor {
        case .point(let point):
            point
        case .prefecture(let code):
            mapData[code].map {
                PrefectureGeometry.screenCentroid(of: $0, transform: transform)
            }
        }
    }

    /// Combined outline of everything currently stuck down.
    private func stuckSilhouette(transform: CGAffineTransform) -> Path {
        var path = Path()
        for prefecture in prefectures where appearance(prefecture).isStuck {
            path.addPath(PrefectureGeometry.path(for: prefecture, transform: transform))
        }
        return path
    }

    /// Direct hit first, then the near-miss allowance for the asked prefecture.
    ///
    /// The allowance shrinks with the zoom for the same reason the outlines do:
    /// taps arrive in this view's own coordinates, so a fixed 22 units becomes
    /// 22 x zoom on the glass. Left alone, a pinched-in map would hand the
    /// answer to a tap most of a thumb away from the prefecture.
    private func resolve(_ point: CGPoint, transform: CGAffineTransform) -> Prefecture? {
        let candidates = prefectures.filter { interactiveCodes.contains($0.code) }
        guard !candidates.isEmpty else { return nil }
        let target = targetCode.flatMap { mapData[$0] }
        let magnification = max(zoom, 1)
        return PrefectureGeometry.resolveTap(
            at: point, target: target, among: candidates, transform: transform,
            tolerance: GameRules.tapTolerancePoints / magnification,
            targetBias: GameRules.tapTargetBiasPoints / magnification)
    }
}

// MARK: - One prefecture

private struct PrefectureLayer: View {
    let prefecture: Prefecture
    let transform: CGAffineTransform
    let canvasSize: CGSize
    let zoom: CGFloat
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
    /// The white die-cut has to scale with the render, or an 84pt stage
    /// thumbnail is drawn almost entirely in border and the colour disappears.
    private var dieCutWidth: CGFloat {
        min(max(canvasSize.width * 0.009, 0.5), 3) / max(zoom, 1)
    }

    /// The prefecture boundary itself. Deliberately hair-thin: at 47 shapes it
    /// is a grid of borders, and anything heavier reads as the lines being the
    /// subject rather than the country.
    private var boundaryWidth: CGFloat {
        min(max(canvasSize.width * 0.0019, 0.3), 0.7) / max(zoom, 1)
    }

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
            // The drawing itself is decorative; the labelled element is the
            // proxy below, which is the only one with a meaningful frame.
            .accessibilityHidden(true)
            .overlay(alignment: .topLeading) { accessibilityProxy }
    }

    /// A correctly-placed, correctly-sized element for each prefecture.
    ///
    /// A `Path` view expands to fill whatever it is offered, so putting the
    /// accessibility element on the drawn shape gave all 47 prefectures a frame
    /// covering the entire map — VoiceOver saw 47 identical stacked rectangles
    /// and direct-touch exploration was useless. This sits on the centroid at
    /// no less than the 44pt CLAUDE.md §9 asks for.
    ///
    /// Not hit-testable: the map has a single tap gesture that resolves the
    /// location itself, and a second responder here would swallow taps.
    private var accessibilityProxy: some View {
        let box = PrefectureGeometry.bbox(of: prefecture, transform: transform)
        return Color.clear
            .frame(width: max(box.width, 44), height: max(box.height, 44))
            .position(screenCentroid)
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityLabel(prefecture.name)
            .accessibilityAddTraits(.isButton)
    }

    private var shape: some View {
        ZStack(alignment: .topLeading) {
            // Holes are handled by the fill rule rather than by subtracting
            // paths, which is why every ring can live in one Path.
            path.fill(appearance.fill, style: FillStyle(eoFill: true))

            if appearance.isStuck {
                path.stroke(appearance.stroke, lineWidth: dieCutWidth)
            } else {
                // A thin printed edge, no white die-cut. Solid rather than
                // dashed — at 47 prefectures a dashed edge reads as scribble,
                // and the fresh-save map is the first thing seen.
                path.stroke(appearance.stroke, lineWidth: boundaryWidth)
            }

            if appearance.isSparkling {
                // No gold rim: the fill is already gold, so an outline drew a
                // line around a colour the shape had anyway, and at map scale
                // that line was most of Kagawa. What is left of §5's 明滅 is a
                // sheen breathing across the shape, masked inside so it can
                // never thicken the boundary.
                //
                // Only the sheen pulses, never the gold under it — a prefecture
                // that faded in and out would read as unfinished rather than as
                // finished and celebrated.
                //
                // Kept faint on purpose: the legend promises one gold, and a
                // heavier veil would make the map's キラキラ visibly paler than
                // the swatch standing for it.
                path.fill(.white.opacity(0.14), style: FillStyle(eoFill: true))
                    .modifier(SlowGlow(enabled: !reduceMotion))
            }

            if isHinted {
                path.stroke(Palette.red, lineWidth: 3.5 / max(zoom, 1))
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

/// 「3 れんぞく!」 rising off the tap, louder the longer the run.
///
/// Every tier changes size *and* colour *and* how much sparkle it carries. One
/// axis alone is too easy to miss at a glance, and the whole point is that the
/// fourth in a row should feel different from the second.
private struct ComboBurstLabel: View {
    let burst: ComboBurst
    let reduceMotion: Bool

    @State private var shown = false

    private var size: CGFloat { [18, 23, 29][min(max(burst.tier, 1), 3) - 1] }
    private var tint: Color { burst.tier >= 3 ? Palette.gold : Palette.orange }
    private var sparkles: String { String(repeating: "✨", count: max(burst.tier - 1, 0)) }

    var body: some View {
        Text(sparkles.isEmpty ? burst.text : "\(sparkles)\(burst.text)")
            .font(AppFont.rounded(size, relativeTo: .title3))
            .foregroundStyle(tint)
            .monospacedDigit()
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(.white.opacity(0.94)))
            .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 1.5))
            .shadow(color: Palette.ink.opacity(0.16), radius: 4, y: 2)
            .fixedSize()
            // Reduce Motion keeps the call-out — it just stops travelling. The
            // information is the streak, not the movement (CLAUDE.md §9).
            .offset(y: reduceMotion ? -26 : (shown ? -34 : 0))
            .scaleEffect(reduceMotion ? 1 : (shown ? 1 : 0.5))
            .opacity(reduceMotion ? 1 : (shown ? 1 : 0))
            .animation(reduceMotion ? nil : .spring(duration: 0.45), value: shown)
            .onAppear { shown = true }
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
