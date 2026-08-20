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
    /// A steady ring drawn around the shape, over everything else.
    var outline: Color?
    /// Specialty emoji floating up from a prefecture just won.
    var badge: String?

    /// The pre-printed slot: the prefecture's own colour, washed out.
    static func slot(for code: Int) -> PrefectureAppearance {
        PrefectureAppearance(fill: Palette.fill(for: code, strength: 0.22),
                             stroke: Palette.boundary,
                             isStuck: false)
    }

    /// The one being asked about in 「なまえを あてる」.
    ///
    /// A red ring around an otherwise ordinary slot. It used to be the shape
    /// at full colour against neighbours washed to 22% — the widest contrast
    /// the palette has — but "the saturated one" is a comparison, and a
    /// comparison takes a second look. A ring is a mark: nothing else on the
    /// map wears one, so there is nothing to compare against. Steady rather
    /// than blinking, because this is the question, not a rescue.
    static func asked(for code: Int) -> PrefectureAppearance {
        var appearance = slot(for: code)
        appearance.outline = Palette.red
        return appearance
    }

    /// A sticker pressed onto the page. The edge defaults to the white
    /// die-cut; the quiz's correct-answer celebration passes gold, so that
    /// moment reads as a small reward rather than as one more sticker on
    /// the sheet.
    static func stuck(for code: Int, strength: Double = 1, sparkling: Bool = false,
                      stroke: Color = Palette.dieCut,
                      badge: String? = nil) -> PrefectureAppearance {
        PrefectureAppearance(fill: Palette.fill(for: code, strength: strength),
                             stroke: stroke,
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

/// The animation triggers one prefecture is carrying.
///
/// `keyframeAnimator` replays whenever its trigger changes — in either
/// direction, and it cannot know which way is meaningful. Deriving the trigger
/// straight from the current effect therefore fired twice: once when the effect
/// arrived, and again when it moved on and the value fell back to the sentinel.
/// Missing 青森 and then missing 岩手 shook 青森 a second time, and the map
/// twitched in places nobody had touched.
///
/// So the triggers are remembered rather than derived. An effect aimed at
/// another prefecture is not news here and leaves them alone; only one aimed at
/// this one advances anything. The values are opaque — all that matters is that
/// they change exactly once per event.
nonisolated struct EffectTriggers: Equatable {
    private(set) var pop = 0
    private(set) var shake = 0

    /// - Parameter effect: the effect aimed at *this* prefecture, or nil when
    ///   the live one is aimed elsewhere or there is none.
    mutating func apply(_ effect: MapEffect?) {
        guard let effect else { return }
        switch effect.kind {
        // Counted rather than copied from `effect.id`: the ids restart with each
        // quiz, and a remembered id colliding with a fresh one would swallow an
        // animation.
        case .pop: pop += 1
        case .shake: shake += 1
        }
    }
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
    /// The dashed boxes around relocated shapes (Okinawa, the world's inset
    /// countries). Data-driven — a frame is drawn wherever `mapData.insets`
    /// declares one for a shape on screen; this flag only lets the stage-select
    /// thumbnails drop the furniture at sticker size.
    var showsInsetFrames = true
    /// Unrecorded coastlines (`mapData.background`), grey and untappable.
    /// Off for the same thumbnails: at 84pt the scenery would drown the stage.
    var showsBackground = true
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
                // Scenery first, under everything: it must never cover a
                // question, a sticker or a celebration.
                if showsBackground {
                    backgroundLayer(transform: transform, canvasSize: geo.size)
                }

                if showsInsetFrames {
                    ForEach(mapData.insets, id: \.code) { inset in
                        if codes.contains(inset.code) {
                            InsetFrame(rect: inset.frame.applying(transform))
                        }
                    }
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
                    let paint = appearance(prefecture)
                    PrefectureLayer(
                        prefecture: prefecture,
                        transform: transform,
                        canvasSize: geo.size,
                        zoom: zoom,
                        appearance: paint,
                        isHinted: hintCode == prefecture.code,
                        effect: effect?.code == prefecture.code ? effect : nil,
                        reduceMotion: reduceMotion)
                        .zIndex(zIndex(for: prefecture.code, paint: paint))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            // Siberia and the background coastlines deliberately overflow the
            // stage frame (frame calculation and drawn extent are separate
            // things — Prefecture.frameBbox). Cut the overflow at the map's
            // own edge; nothing on the japan map reaches it, so nothing there
            // changes. Overlays below (the combo stamp) attach after the clip
            // and keep their own inside-the-canvas clamping.
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture { location in
                guard let onTap else { return }
                onTap(resolve(location, transform: transform), location)
            }
            .overlay(alignment: .topLeading) {
                comboLabel(transform: transform, canvasSize: geo.size)
            }
        }
    }

    /// The unrecorded coastlines that fall inside the visible canvas, as one
    /// quiet grey landmass (CLAUDE.md §3 — leaving them out draws false sea).
    /// One combined path, filled once: it is scenery, so adjacent shapes may
    /// fuse — separate them and they start to look like more questions.
    /// Not tappable and hidden from VoiceOver for the same reason.
    @ViewBuilder private func backgroundLayer(transform: CGAffineTransform,
                                              canvasSize: CGSize) -> some View {
        let canvasRect = CGRect(origin: .zero, size: canvasSize)
        let path = mapData.background.reduce(into: Path()) { path, shape in
            // The world's background covers the globe; a stage sees a corner.
            guard shape.bbox.applying(transform).intersects(canvasRect) else { return }
            path.addPath(PrefectureGeometry.path(rings: shape.rings,
                                                 transform: transform))
        }
        if !path.isEmpty {
            ZStack(alignment: .topLeading) {
                path.fill(Palette.backgroundLand, style: FillStyle(eoFill: true))
                // A shoreline hairline, or the grey mass reads as a stain on
                // the sea rather than as land.
                path.stroke(Palette.backgroundShore,
                            lineWidth: hairlineWidth(canvasWidth: canvasSize.width,
                                                     zoom: zoom))
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// The streak call-out, at the tap.
    ///
    /// Counter-scaled by the zoom for the same reason the outlines are divided
    /// by it: this sits inside the magnified content, and at 4x an unscaled
    /// label would cover half the country.
    @ViewBuilder private func comboLabel(transform: CGAffineTransform,
                                         canvasSize: CGSize) -> some View {
        if let comboBurst, let point = burstPoint(comboBurst.anchor, transform: transform) {
            let radius = ComboBurstLabel.visualRadius(for: comboBurst.tier)
            let safePoint = comboPoint(point, radius: radius,
                                       transform: transform, canvasSize: canvasSize)
            ComboBurstLabel(burst: comboBurst, reduceMotion: reduceMotion)
                .scaleEffect(1 / max(zoom, 1))
                .position(safePoint)
                .allowsHitTesting(false)
                // Keyed on the burst so a second streak restarts the animation
                // instead of inheriting the finished state of the first.
                .id(comboBurst.id)
        }
    }

    /// Places the stamp clear of the specialty emoji rising from the rewarded
    /// prefecture. Both effects used to travel upward from virtually the same
    /// point, leaving the emoji hidden behind the much larger stamp.
    /// This resolves the map-specific part — where the badge is — and hands the
    /// placement itself to `ComboBurstLabel.stampAnchor`, which the globe shares.
    private func comboPoint(_ point: CGPoint, radius: CGFloat,
                            transform: CGAffineTransform,
                            canvasSize: CGSize) -> CGPoint {
        var badgeOrigin: CGPoint?
        if let effect,
           let prefecture = mapData[effect.code],
           appearance(prefecture).badge != nil {
            badgeOrigin = PrefectureGeometry.screenCentroid(
                of: prefecture, transform: transform)
        }
        return ComboBurstLabel.stampAnchor(tap: point, radius: radius,
                                           badgeOrigin: badgeOrigin,
                                           canvasSize: canvasSize)
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

    /// Stacking order. The layers draw in `codes` order, so without this a
    /// prefecture mid-pop slid *under* every neighbour drawn after it — the
    /// celebration, the floating specialty emoji and all. The addressee of the
    /// live effect rides on top; anything wearing a ring (the blinking answer,
    /// the asked-about prefecture) sits above the crowd too, or a later
    /// neighbour's die-cut carves into its outline. The effect outranks the
    /// rings because it is the one actually moving, and the two can point at
    /// different prefectures — a wrong tap shakes one while the answer blinks
    /// elsewhere.
    func zIndex(for code: Int, paint: PrefectureAppearance) -> Double {
        if effect?.code == code { return 2 }
        if hintCode == code || paint.outline != nil { return 1 }
        return 0
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

/// The map's one hairline weight, shared by the printed prefecture boundary
/// and the background shoreline. Deliberately hair-thin: at 47 shapes it is a
/// grid of borders, and anything heavier reads as the lines being the subject
/// rather than the country. One formula so no line ever outweighs a real
/// border — the two call sites used to duplicate it and merely promise to
/// match. Divided by the zoom because the stroke is drawn inside the magnified
/// content (see `PrefectureMapView.zoom`).
/// Internal, not private: `GlobeMapView` draws the same hairline (at zoom 1 —
/// its magnification is in the radius, not in a scaleEffect).
func hairlineWidth(canvasWidth: CGFloat, zoom: CGFloat) -> CGFloat {
    min(max(canvasWidth * 0.0019, 0.3), 0.7) / max(zoom, 1)
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

    /// Survives every effect aimed at another prefecture, which is the whole
    /// point — see `EffectTriggers`.
    @State private var triggers = EffectTriggers()

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

    /// The prefecture boundary itself (see `hairlineWidth`).
    private var boundaryWidth: CGFloat {
        hairlineWidth(canvasWidth: canvasSize.width, zoom: zoom)
    }

    /// One width for every red ring — the asked-about prefecture and the
    /// blinking hint — so "a red line" always weighs the same thing.
    private var ringWidth: CGFloat { 3.5 / max(zoom, 1) }

    private var anchor: UnitPoint {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return .center }
        return UnitPoint(x: screenCentroid.x / canvasSize.width,
                         y: screenCentroid.y / canvasSize.height)
    }

    var body: some View {
        shape
            .modifier(PopEffect(trigger: triggers.pop, anchor: anchor,
                                enabled: !reduceMotion))
            .modifier(ShakeEffect(trigger: triggers.shake,
                                  enabled: !reduceMotion))
            // The effect is already filtered to this prefecture upstream, so nil
            // means "not mine" — and not-mine must not move anything.
            .onChange(of: effect) { _, new in triggers.apply(new) }
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

            // A correct answer earns a brief foil trace around the prefecture.
            // This ties the celebration to the map itself before the stamp at
            // the fingertip appears; a floating badge on its own could belong
            // to any quiz. The live effect id recreates the trace for repeated
            // answers to the same prefecture.
            if appearance.isStuck, case .pop? = effect?.kind {
                CorrectFoilTrace(path: path,
                                 lineWidth: max(dieCutWidth * 0.8, 1 / max(zoom, 1)),
                                 reduceMotion: reduceMotion)
                    .id(effect?.id)
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

            if let outline = appearance.outline {
                path.stroke(outline, lineWidth: ringWidth)
            }

            if isHinted {
                path.stroke(Palette.red, lineWidth: ringWidth)
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

}

// MARK: - Effects
//
// Every one of these is a no-op when Reduce Motion is on; the state change is
// still legible because colour carries it (CLAUDE.md §9).
//
// Internal, not private: `GlobeMapView` replays the same celebrations on the
// globe. One implementation per animation, or the two maps drift apart in
// exactly the moments a child watches most closely (minimal visibility hoist —
// only `StampRays` and `InsetFrame` stay file-private).

struct PopEffect: ViewModifier {
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

struct ShakeEffect: ViewModifier {
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

struct HintBlink: ViewModifier {
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

struct SlowGlow: ViewModifier {
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

struct RiseEffect: ViewModifier {
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

/// A travel stamp pressed where the answer landed.
///
/// The old white capsule and emoji sparkles looked like a generic toast laid
/// over the map. This uses the album's paper, ink and foil instead: the count is
/// printed inside a round souvenir stamp and restrained rays make longer runs
/// feel rarer without throwing confetti over the question.
struct ComboBurstLabel: View {
    let burst: ComboBurst
    let reduceMotion: Bool

    @State private var shown = false

    private var tier: Int { min(max(burst.tier, 1), 3) }
    private var diameter: CGFloat { [72, 84, 98][tier - 1] }
    private var countSize: CGFloat { [28, 34, 40][tier - 1] }
    private var labelSize: CGFloat { [11, 12, 13][tier - 1] }
    private var ink: Color { tier == 1 ? Palette.orange : Palette.ink }

    static func visualRadius(for tier: Int) -> CGFloat {
        let index = min(max(tier, 1), 3) - 1
        let diameters: [CGFloat] = [72, 84, 98]
        let rayLengths: [CGFloat] = [7, 10, 13]
        return diameters[index] / 2 + 5 + rayLengths[index]
    }

    /// Where the stamp's position anchor should land, given where the finger
    /// tapped and (when a specialty emoji is rising) where it rises from.
    /// Pure and shared by both maps — the flat map and the globe resolve the
    /// badge's screen position their own way, but the stamp must dodge and
    /// clamp by the same rules on either one.
    nonisolated static func stampAnchor(tap point: CGPoint, radius: CGFloat,
                                        badgeOrigin: CGPoint?,
                                        canvasSize: CGSize) -> CGPoint {
        // The label finishes 34pt above its position anchor.
        var stampCenter = CGPoint(x: point.x, y: point.y - 34)

        if let badgeOrigin {
            // The emoji rises 26pt. Its swept area is represented by the
            // midpoint of that short path plus enough room for the 26pt glyph.
            let badgePathCenter = CGPoint(x: badgeOrigin.x, y: badgeOrigin.y - 13)
            let dx = stampCenter.x - badgePathCenter.x
            let dy = stampCenter.y - badgePathCenter.y
            // Extra clearance also covers the stamp's brief 1.34x arrival,
            // not just its resting circle.
            let clearance = radius + 42

            if hypot(dx, dy) < clearance {
                let left = badgeOrigin.x - clearance
                let right = badgeOrigin.x + clearance
                let leftRoom = left - radius
                let rightRoom = canvasSize.width - (right + radius)

                // Prefer the side with enough paper; when both fit, use the
                // roomier side so coastal prefectures naturally move inward.
                stampCenter.x = rightRoom > leftRoom ? right : left
            }
        }

        // Keep the full foil rays inside the clipped map panel. Return the
        // anchor rather than the visual centre, restoring the label's -34pt
        // resting offset.
        stampCenter.x = min(max(stampCenter.x, radius),
                            max(radius, canvasSize.width - radius))
        stampCenter.y = min(max(stampCenter.y, radius),
                            max(radius, canvasSize.height - radius))
        return CGPoint(x: stampCenter.x, y: stampCenter.y + 34)
    }

    private var parts: (count: String, label: String) {
        let pieces = burst.text.split(separator: " ", maxSplits: 1)
        return (pieces.first.map(String.init) ?? burst.text,
                pieces.count > 1 ? String(pieces[1]) : "")
    }

    private var foilColors: [Color] {
        guard tier >= 3 else {
            return [Palette.orange, Palette.gold, .white, Palette.gold, Palette.orange]
        }
        // The top tier borrows the card book's holographic promise, but only
        // on the foil edge. The paper centre keeps the number easy to read.
        return [Palette.red, Palette.gold, Palette.teal,
                Color(hex: 0x81D4FA), Color(hex: 0xCE93D8), Palette.red]
    }

    var body: some View {
        ZStack {
            StampRays(diameter: diameter, tier: tier, colors: foilColors)
                .scaleEffect(reduceMotion ? 1 : (shown ? 1 : 0.62))
                .rotationEffect(.degrees(reduceMotion ? 0 : (shown ? 0 : -16)))
                .opacity(tier == 1 ? 0.55 : 0.82)

            Circle()
                .fill(Palette.page.opacity(0.98))
                .shadow(color: Palette.stickerShadow, radius: 0, y: 3)
                .shadow(color: Palette.gold.opacity(0.32), radius: tier >= 2 ? 9 : 4)

            Circle()
                .stroke(
                    AngularGradient(colors: foilColors, center: .center),
                    style: StrokeStyle(lineWidth: tier == 1 ? 3 : 4.5,
                                       lineCap: .round))
                .padding(2)

            // Slightly broken ink inside the foil rim makes this read as a
            // physical stamp rather than another polished app badge.
            Circle()
                .stroke(ink.opacity(0.46),
                        style: StrokeStyle(lineWidth: 1.5, dash: [2.5, 3.5]))
                .padding(9)

            (Text(parts.count)
                .font(AppFont.heading(countSize, relativeTo: .title))
             + Text("\n")
             + Text(parts.label)
                .font(AppFont.rounded(labelSize, relativeTo: .caption)))
                .foregroundStyle(ink)
                .multilineTextAlignment(.center)
                .lineSpacing(-3)
                .monospacedDigit()
                // Keep the exact existing UI-test and VoiceOver label even
                // though the visual treatment now uses two lines.
                .accessibilityLabel(burst.text)
        }
        .frame(width: diameter, height: diameter)
        .fixedSize()
        // A stamp arrives from just above the paper, lands with a short spring,
        // then lifts enough to uncover the prefecture beneath it.
        .rotationEffect(.degrees(reduceMotion ? -2 : (shown ? -2 : -9)))
        .offset(y: reduceMotion ? -30 : (shown ? -34 : -12))
        .scaleEffect(reduceMotion ? 1 : (shown ? 1 : 1.34))
        .opacity(reduceMotion ? 1 : (shown ? 1 : 0))
        .animation(reduceMotion ? nil : .spring(duration: 0.52, bounce: 0.32),
                   value: shown)
        .onAppear { shown = true }
    }
}

/// The glints behind the stamp are foil rays, not particles: they stay attached
/// to the award and disappear with it, so even the top tier never becomes a
/// screen-filling confetti effect.
private struct StampRays: View {
    let diameter: CGFloat
    let tier: Int
    let colors: [Color]

    private var count: Int { [6, 9, 12][min(max(tier, 1), 3) - 1] }
    private var length: CGFloat { [7, 10, 13][min(max(tier, 1), 3) - 1] }

    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(AngularGradient(colors: colors, center: .center))
                    .frame(width: tier >= 3 ? 3 : 2.5, height: length)
                    .offset(y: -(diameter / 2 + 5 + length / 2))
                    .rotationEffect(.degrees(Double(index) * 360 / Double(count)))
            }
        }
    }
}

/// A bright segment runs once around the rewarded prefecture. With Reduce
/// Motion the existing steady gold edge carries the same meaning on its own.
struct CorrectFoilTrace: View {
    let path: Path
    let lineWidth: CGFloat
    let reduceMotion: Bool

    @State private var progress: CGFloat = 0

    var body: some View {
        if !reduceMotion {
            path
                .trim(from: max(0, progress - 0.34), to: progress)
                .stroke(
                    LinearGradient(colors: [Palette.orange, .white, Palette.gold],
                                   startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: lineWidth,
                                       lineCap: .round, lineJoin: .round))
                .shadow(color: Palette.gold.opacity(0.75), radius: 4)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.62)) { progress = 1 }
                }
        }
    }
}

// MARK: - Inset frame

/// Dashed box around a relocated, enlarged shape — Okinawa on the japan map,
/// the Singapore-class countries on the world map — so it reads as a separate
/// frame rather than the shape's real position (CLAUDE.md §3).
private struct InsetFrame: View {
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
