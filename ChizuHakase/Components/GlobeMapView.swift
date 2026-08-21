import SwiftUI

/// 地球儀の回転状態: 正面に来る経度・緯度(度)。
///
/// `GlobeMapView` はこれを `@Binding` で受ける。内部 `@State` に隠すと、
/// この部品自身のヒント回転と、親が命じたい回転 — nameIt の出題前回転
/// (Task 6)、マイマップの初期位置(Task 7)— が同じ状態を触れない。
/// 回転は「親が命令でき、部品(ドラッグ)も動かせる」共有状態なので、
/// 小さな値型 + Binding だけが両方を満たす。
nonisolated struct GlobeCenter: Sendable, Equatable {
    var longitude: Double
    var latitude: Double

    init(longitude: Double = 0, latitude: Double = 0) {
        self.longitude = longitude
        self.latitude = latitude
    }

    /// この本の子の家 — 日本が正面に来る回転。クイズもマイマップも、地球儀は
    /// まずここから開く: 球上で 5 歳がすでに知っている唯一の場所から始まれば、
    /// 世界は大海原ではなく「どこか」から広がる。値は日本本土の中心あたり
    /// (138°E, 36°N)で、緯度を少し北に取るのは正射図法の正面が最も歪みなく
    /// 見える帯に日本列島全体を寝かせるため。
    static let home = GlobeCenter(longitude: 138, latitude: 36)

    /// `GlobeGeometry.centering` の到達値へ「最短の弧」で向かうための代入値。
    ///
    /// SwiftUI のアニメーションは数値を直線補間するので、170° → −170° を
    /// そのまま代入すると 340° 逆回りに一周近く回る。経度は目的地と等価な
    /// 値のうち現在地から ±180° 以内のものへ写す — 結果は ±180 を超えて
    /// よい(投影は wrap 無しでも等価で、次のドラッグが畳む)。緯度に
    /// wrap は無いのでクランプだけ(極の特異点回避を到達値でも守る)。
    func facing(_ target: (longitude: Double, latitude: Double)) -> GlobeCenter {
        GlobeCenter(
            longitude: longitude
                + GlobeProjection.wrappedLongitude(target.longitude - longitude),
            latitude: GlobeProjection.clampedLatitude(target.latitude))
    }
}

/// 地球儀を描き、回転・ズーム・タップを解決する(`PrefectureMapView` の球面版)。
///
/// 入力は平面版の部分集合と同型だが、identity は `Prefecture` ではなくコード:
/// この部品はデータ盲目で、`GlobeShape` が運ぶのは形とコードだけ。名前
/// (VoiceOver のかな)は `accessibilityName` で親が渡す。
///
/// 平面版との構造差はふたつ。**拡大は `scaleEffect` ではなく半径**に入る —
/// 線の太さ・タップ許容・スタンプはガラス座標のまま描かれるので、平面版に
/// 散っている `/ max(zoom, 1)` の補正はここには存在しない。そして
/// **回転ドラッグは highPriorityGesture** — どのズーム倍率でも、囲む
/// ScrollView や先祖のジェスチャに勝って縦横のドラッグを取り切る(平面版が
/// ズーム中だけスクロールを奪うのと違い、地球儀はいつでも回る物だから)。
/// ホストはページを送る余地をこのパネルの**外**に残すこと。タップだけは
/// 生き残る — ドラッグの minimumDistance 10pt が手を付けないので。
struct GlobeMapView: View {
    let globe: GlobeData
    /// コード → 塗り。`MasteryStyle.appearance` も `PrefectureAppearance` の
    /// ファクトリもコードだけで足りる(平面版が Prefecture を渡すのは
    /// 呼び手がすでに持っているからで、地球儀は持っていない)。
    var appearance: (Int) -> PrefectureAppearance
    /// タップが解決してよい国。可視性の選別は不要 — 裏側の国は
    /// `GlobeGeometry.resolveTap` が描かれないのと同じ理由で当たらない。
    var interactiveCodes: Set<Int> = []
    /// 出題中の国(タップ許容の下駄の相手)。
    var targetCode: Int?
    /// 3 ミス後に赤い輪郭を点滅させる国。裏側にいたら先に正面へ回す。
    var hintCode: Int?
    var effect: MapEffect?
    var comboBurst: ComboBurst?
    /// 正面に来る経度・緯度。ドラッグがこれを動かし、ヒントはこれを回す。
    /// 親から回すときの型(nameIt の出題前回転・マイマップの初期位置):
    /// `center = center.facing(GlobeGeometry.centering(on: shape))` を
    /// `withAnimation` で包む(Reduce Motion では素の代入でジャンプ)。
    @Binding var center: GlobeCenter
    /// 半径の倍率。`ZoomPan.clamp(scale:)` の既定範囲に畳む。Binding なのは
    /// リセットボタンを親が置くため(平面版の zoom と同じ役割分担)。
    /// パンは無い — 見たい場所へは回して寄る。
    @Binding var zoom: CGFloat
    /// 可視国の VoiceOver ラベル(かな名)。nil なら国ラベルだけでなく
    /// 回転つまみ(`rotateStepper`)も消える — 読み上げる名前の無い地球儀を
    /// 回せても、着いた先を伝えられない。
    var accessibilityName: ((Int) -> String)?
    /// 何に当たったか(海なら nil)と、指が落ちた点(この View の座標)。
    var onTap: ((Int?, CGPoint) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.textMode) private var textMode
    @GestureState private var pinch: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            GlobeSurface(
                longitude: center.longitude,
                latitude: center.latitude,
                radius: Self.radius(in: geo.size, zoom: zoom * pinch),
                canvasSize: geo.size,
                globe: globe,
                appearance: appearance,
                interactiveCodes: interactiveCodes,
                targetCode: targetCode,
                hintCode: hintCode,
                effect: effect,
                comboBurst: comboBurst,
                accessibilityName: accessibilityName,
                reduceMotion: reduceMotion,
                onRotate: { center = $0 },
                onTap: onTap)
                .simultaneousGesture(magnify)
                // ヒントが裏側の国を指したら、点滅の前に正面へ回す(設計 §7
                // 未決の解決)。平面 ⇄ 地球儀の切替でヒントが立ったまま
                // 現れることもあるので、onAppear でも同じ判定を通す。
                .onChange(of: hintCode) { _, code in rotate(toHint: code) }
                .onAppear { rotate(toHint: hintCode) }
                .overlay(alignment: .bottom) { rotateStepper }
        }
    }

    /// VoiceOver はドラッグで地球儀を回せない — そして裏側の国は読み上げ
    /// 一覧にも出ない(重心可視の選別)ので、回す口が無ければ永遠に届かない。
    /// この見えない調整要素(accessibilityAdjustableAction)が経度を
    /// `GameRules.globeRotateStepDegrees` ずつ回す: 上スワイプで東へ、
    /// 下スワイプで西へ。値は正面いちばん近くの国の読み — 一歩ごとに
    /// 「いまどこを見ているか」が聞こえる。Reduce Motion は見ない: 利用者
    /// 自身が起こした移動で、素の代入に切るべき補間がそもそも無い。
    @ViewBuilder private var rotateStepper: some View {
        if let accessibilityName {
            Color.clear
                .frame(width: 44, height: 44)
                .allowsHitTesting(false)
                .accessibilityElement()
                .accessibilityLabel(textMode.rotateGlobe)
                .accessibilityValue(
                    Self.frontmostCode(shapes: globe.shapes, center: center)
                        .map(accessibilityName) ?? "")
                .accessibilityAdjustableAction { direction in
                    center = Self.stepped(center, east: direction == .increment)
                }
        }
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .updating($pinch) { value, state, _ in state = value.magnification }
            .onEnded { value in zoom = ZoomPan.clamp(scale: zoom * value.magnification) }
    }

    private func rotate(toHint code: Int?) {
        guard let code,
              let destination = Self.hintRotation(code: code,
                                                  shapes: globe.shapes,
                                                  from: center)
        else { return }
        if reduceMotion {
            center = destination
        } else {
            withAnimation(.easeInOut(duration: GameRules.globeCenteringDuration)) {
                center = destination
            }
        }
    }

    // MARK: - 純ロジック(GlobeMapViewTests)

    /// 円盤の半径。フレームの短辺に収まる円からリムが縁に触れないぶんの
    /// 余白(`GameRules.mapPaddingPoints`)を引き、1...4 に畳んだズーム
    /// 倍率を掛ける。余白より小さいフレーム(レイアウト初回)は 0 —
    /// 負の半径の円盤を作らない。
    nonisolated static func radius(in size: CGSize, zoom: CGFloat) -> CGFloat {
        let base = min(size.width, size.height) / 2 - GameRules.mapPaddingPoints
        guard base > 0 else { return 0 }
        return base * ZoomPan.clamp(scale: zoom)
    }

    /// 回転救済の到達値 — 3 ミスのヒント点滅と、なまえを あてる の出題前
    /// 回転(Task 6)が同じ述語を使う。対象の重心が「快適に見える角距離」
    /// (`GameRules.globeHintComfortDegrees`)の内側なら nil: 見えている答えを
    /// 回すと、点滅を見つけかけた子から地図が逃げる。境界を正面半球(90°)に
    /// しないのは、80° 台の地平線際では前縮みで輪郭が数 pt に潰れ、「見えて
    /// いる」が嘘になるから。判定は角度だけで決まるので、投影の半径・
    /// スクリーンは仮値でよい。
    nonisolated static func hintRotation(code: Int,
                                         shapes: [GlobeShape],
                                         from current: GlobeCenter) -> GlobeCenter? {
        guard let shape = shapes.first(where: { $0.code == code }) else { return nil }
        let probe = GlobeProjection(centerLongitude: current.longitude,
                                    centerLatitude: current.latitude,
                                    radius: 1, screenCenter: .zero)
        let comfort = cos(GameRules.globeHintComfortDegrees * .pi / 180)
        guard probe.cosineOfAngularDistance(lon: Double(shape.centroid.x),
                                            lat: Double(shape.centroid.y)) < comfort
        else { return nil }
        return current.facing(GlobeGeometry.centering(on: shape))
    }

    /// VoiceOver の 1 ステップぶん回した到達値(`rotateStepper`)。緯度は
    /// 触らない — 収録国の重心は 39°S〜66°N に収まり、初期位置
    /// (`GlobeCenter.home`、36°N)からなら経度の一周だけで全国がいつか
    /// 正面半球に入る(実データのピン: GlobeMapViewTests)。ドラッグしない
    /// 利用者の緯度をよそで動かすのは、なまえを あてる の出題回転と、
    /// 両モードで発火する 3 ミスのヒント回転(`rotate(toHint:)`)。ヒントが
    /// 高緯度(アイスランド ~66°N)へ寄せた後は南端の国が全経度で 90° の
    /// 外に出るが、その国が答えになった回はまさに同じヒント回転が正面へ
    /// 連れて行く — 崩した張本人が救済を兼ねる。二軸のつまみは「いまどこか」
    /// を耳で追う相手には迷路になる。経度は wrap — 一周して同じ場所へ帰る、
    /// 球の事実そのまま。
    nonisolated static func stepped(_ center: GlobeCenter, east: Bool) -> GlobeCenter {
        let step = GameRules.globeRotateStepDegrees
        return GlobeCenter(
            longitude: GlobeProjection.wrappedLongitude(
                center.longitude + (east ? step : -step)),
            latitude: center.latitude)
    }

    /// 正面(中心)にいちばん近い重心の国 — `rotateStepper` の読み上げ値。
    /// 中心が大洋の真ん中でも「いちばん近い国」を返すのは意図: 何も言わない
    /// つまみは、回した結果が届いたのかどうかを聞き手に教えない。
    nonisolated static func frontmostCode(shapes: [GlobeShape],
                                          center: GlobeCenter) -> Int? {
        // 角距離の比較だけなので投影の半径・スクリーンは仮値でよい
        // (hintRotation と同じ理屈)。
        let probe = GlobeProjection(centerLongitude: center.longitude,
                                    centerLatitude: center.latitude,
                                    radius: 1, screenCenter: .zero)
        func closeness(_ shape: GlobeShape) -> Double {
            probe.cosineOfAngularDistance(lon: Double(shape.centroid.x),
                                          lat: Double(shape.centroid.y))
        }
        return shapes.max { closeness($0) < closeness($1) }?.code
    }

    /// 重なり順(平面版 `PrefectureMapView.zIndex` の球面鏡 — 理由も同じ:
    /// 動いている物が最上位、輪を着けた物がその下、他は平ら)。
    nonisolated static func zIndex(for code: Int, paint: PrefectureAppearance,
                                   effect: MapEffect?, hintCode: Int?) -> Double {
        if effect?.code == code { return 2 }
        if hintCode == code || paint.outline != nil { return 1 }
        return 0
    }
}

// MARK: - 描画面

/// 実際に描く面。`Animatable` なのはヒント・出題の回転を SwiftUI に補間
/// させるため — `withAnimation { center = … }` のトランザクションがここの
/// `animatableData` に届き、フレームごとに補間された中心で再投影される。
/// ジェスチャもここに付く: タップとドラッグは「いま描かれている」投影で
/// 解決されるべきで、アニメーション中の到達値で解決すると、子どもが見て
/// いる場所と当たる場所が食い違う(GlobeGeometry.cgPath の註と同じ理由)。
private struct GlobeSurface: View, Animatable {
    var longitude: Double
    var latitude: Double
    var radius: CGFloat
    let canvasSize: CGSize
    let globe: GlobeData
    let appearance: (Int) -> PrefectureAppearance
    let interactiveCodes: Set<Int>
    let targetCode: Int?
    let hintCode: Int?
    let effect: MapEffect?
    let comboBurst: ComboBurst?
    let accessibilityName: ((Int) -> String)?
    let reduceMotion: Bool
    let onRotate: ((GlobeCenter) -> Void)?
    let onTap: ((Int?, CGPoint) -> Void)?

    /// ドラッグの基準: このドラッグの startLocation と前回 translation。
    /// 差分だけを `dragged(by:)` に食わせる — 累積を毎回適用し直す形だと、
    /// 緯度クランプで捨てた分が指を返した瞬間にまとめて戻ってくる。
    /// startLocation をキーにするのは、システムに取り上げられたドラッグ
    /// (通知シェード・システムジェスチャ)が onEnded を呼ばずに消えるから:
    /// 残った translation を次のドラッグが引き継ぐと初回デルタが跳ぶ。
    /// 見知らぬ startLocation の最初のイベントは基準の取り直しに使い、
    /// デルタを適用しない — minimumDistance 10pt のスロップが初回に
    /// まとめて届くジャンプも、これで一緒に消える。(@GestureState は
    /// updating と onChanged の実行順が未定義なので使わない)
    @State private var dragBaseline: (start: CGPoint, translation: CGSize)?

    nonisolated var animatableData: AnimatablePair<AnimatablePair<Double, Double>, CGFloat> {
        get { AnimatablePair(AnimatablePair(longitude, latitude), radius) }
        set {
            longitude = newValue.first.first
            latitude = newValue.first.second
            radius = newValue.second
        }
    }

    private var projection: GlobeProjection {
        GlobeProjection(centerLongitude: longitude,
                        centerLatitude: latitude,
                        radius: radius,
                        screenCenter: CGPoint(x: canvasSize.width / 2,
                                              y: canvasSize.height / 2))
    }

    var body: some View {
        let projection = self.projection
        // 重心が正面半球の国だけがラベルを持つ(GlobeGeometry.visibleCodes の
        // 註 — 読み上げても押せない国を VoiceOver に並べない)。
        let labeled = accessibilityName == nil
            ? []
            : GlobeGeometry.visibleCodes(among: globe.shapes, projection: projection)

        ZStack(alignment: .topLeading) {
            seaDisk

            backgroundLayer(projection: projection)

            // 貼られたシールの影は平面版と同じく 1 枚(通常の塗りでは
            // isStuck が無いので空 — クイズの正解演出のときだけ現れる)。
            stuckSilhouette(projection: projection)
                .fill(Palette.stickerShadow)
                .offset(y: min(max(canvasSize.width * 0.008, 1), Sticker.lift))
                .blur(radius: min(max(canvasSize.width * 0.007, 0.8), 2.5))
                .allowsHitTesting(false)

            ForEach(globe.shapes) { shape in
                let paint = appearance(shape.code)
                GlobeCountryLayer(
                    shape: shape,
                    projection: projection,
                    canvasSize: canvasSize,
                    appearance: paint,
                    isHinted: hintCode == shape.code,
                    effect: effect?.code == shape.code ? effect : nil,
                    accessibilityLabel: labeled.contains(shape.code)
                        ? accessibilityName?(shape.code) : nil,
                    reduceMotion: reduceMotion)
                    .zIndex(GlobeMapView.zIndex(for: shape.code, paint: paint,
                                                effect: effect, hintCode: hintCode))
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        // ズームした円盤はフレームからあふれる。平面版と同じく自分の縁で切る。
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture { location in
            guard let onTap else { return }
            // 平面版と同じ「interactiveCodes で絞るだけ」。許容 22pt は
            // ガラス座標のままでよい — 拡大は半径に入っていて、タップも
            // 輪郭も同じガラスの上にある。
            let candidates = globe.shapes.filter { interactiveCodes.contains($0.code) }
            let target = targetCode.flatMap { code in
                globe.shapes.first { $0.code == code }
            }
            let hit = GlobeGeometry.resolveTap(at: location, target: target,
                                               among: candidates, projection: projection)
            onTap(hit?.code, location)
        }
        // High priority so the drag beats an enclosing ScrollView (the
        // my-map column). The flat map only steals scrolling while zoomed;
        // the globe rotates at *every* zoom, so a vertical drag that
        // scrolled the page instead would make latitude unreachable. The
        // page still scrolls from anywhere off the panel, and taps survive:
        // the drag's 10pt minimum distance leaves them unclaimed.
        .highPriorityGesture(rotation(projection: projection))
        .overlay(alignment: .topLeading) { comboLabel(projection: projection) }
    }

    // MARK: - 回転ドラッグ

    /// ドラッグ = 回転(`GlobeProjection.dragged(by:)`)。慣性は付けない:
    /// 回した分だけ回る方が 5 歳に予測可能で、Reduce Motion で切るべき
    /// 演出も増えない(計画 Task 3 の明示判断)。minimumDistance は既定の
    /// 10pt — それ未満はタップのまま。
    private func rotation(projection: GlobeProjection) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard let baseline = dragBaseline,
                      baseline.start == value.startLocation else {
                    // 新しいドラッグの最初のイベント: 基準を取り直すだけで
                    // 回さない(dragBaseline の註)。
                    dragBaseline = (value.startLocation, value.translation)
                    return
                }
                let delta = CGSize(
                    width: value.translation.width - baseline.translation.width,
                    height: value.translation.height - baseline.translation.height)
                dragBaseline = (value.startLocation, value.translation)
                let next = projection.dragged(by: delta)
                onRotate?(GlobeCenter(longitude: next.centerLongitude,
                                      latitude: next.centerLatitude))
            }
            .onEnded { _ in dragBaseline = nil }
    }

    // MARK: - 海と背景

    /// 海 = 円盤。光を上左に寄せたラジアルグラデーションが球に見せる —
    /// 平面の海と同じ 2 色(§9 に無い色を持ち込まない)。リムは惑星の
    /// 輪郭線 — インセット枠と同じ薄めたインクの系だが、あちら(0.35/1.6 の
    /// 破線)より軽い 0.22/1.5 の実線: 枠は目印、こちらはただの縁。
    private var seaDisk: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: Palette.sea,
                                     center: UnitPoint(x: 0.42, y: 0.36),
                                     startRadius: 0,
                                     endRadius: radius * 1.4))
            Circle()
                .strokeBorder(Palette.ink.opacity(0.22), lineWidth: 1.5)
        }
        .frame(width: radius * 2, height: radius * 2)
        .position(x: canvasSize.width / 2, y: canvasSize.height / 2)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// 収録外の海岸線。平面版は 1 本の Path に束ねて 1 回で塗るが、地球儀
    /// では束ねない: リムへクランプされた形どうしは縁で重なり合い、形の
    /// **間**に even-odd が効くと重なりが海色に抜ける。WorldDataLoader が
    /// 保った形状単位の入れ子(穴の even-odd)のまま、形ごとに塗る。
    private func backgroundLayer(projection: GlobeProjection) -> some View {
        ForEach(globe.backgroundRings.indices, id: \.self) { index in
            let path = GlobeGeometry.path(rings: globe.backgroundRings[index],
                                          projection: projection)
            if !path.isEmpty {
                ZStack(alignment: .topLeading) {
                    path.fill(Palette.backgroundLand, style: FillStyle(eoFill: true))
                    path.stroke(Palette.backgroundShore,
                                lineWidth: MapStroke.hairlineWidth(
                                    canvasWidth: canvasSize.width, zoom: 1))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func stuckSilhouette(projection: GlobeProjection) -> Path {
        var path = Path()
        for shape in globe.shapes where appearance(shape.code).isStuck {
            path.addPath(GlobeGeometry.path(for: shape, projection: projection))
        }
        return path
    }

    // MARK: - コンボスタンプ

    @ViewBuilder private func comboLabel(projection: GlobeProjection) -> some View {
        if let comboBurst,
           let point = burstPoint(comboBurst.anchor, projection: projection) {
            let radius = ComboBurstLabel.visualRadius(for: comboBurst.tier)
            ComboBurstLabel(burst: comboBurst, reduceMotion: reduceMotion)
                .position(stampPoint(point, radius: radius, projection: projection))
                .allowsHitTesting(false)
                .id(comboBurst.id)
        }
    }

    private func burstPoint(_ anchor: ComboBurst.Anchor,
                            projection: GlobeProjection) -> CGPoint? {
        switch anchor {
        case .point(let point):
            point
        case .prefecture(let code):
            // 名は「県」でも運ぶのはコード — この本では国を指す。
            globe.shapes.first { $0.code == code }.map {
                GlobeGeometry.screenCentroid(of: $0, projection: projection)
            }
        }
    }

    /// バッジ(浮上する絵文字)の位置だけ球面で解き、配置そのものは
    /// 平面版と同じ式(`ComboBurstLabel.stampAnchor`)に任せる。
    private func stampPoint(_ point: CGPoint, radius: CGFloat,
                            projection: GlobeProjection) -> CGPoint {
        var badgeOrigin: CGPoint?
        if let effect,
           let shape = globe.shapes.first(where: { $0.code == effect.code }),
           appearance(effect.code).badge != nil {
            badgeOrigin = GlobeGeometry.screenCentroid(of: shape, projection: projection)
        }
        return ComboBurstLabel.stampAnchor(tap: point, radius: radius,
                                           badgeOrigin: badgeOrigin,
                                           canvasSize: canvasSize)
    }
}

// MARK: - 1 国ぶん

/// `PrefectureLayer` の球面鏡。演出はすべて共有の Effect View(平面版の
/// ファイルから最小限の可視性で持ち上げたもの)で、違いは座標変換だけ。
private struct GlobeCountryLayer: View {
    let shape: GlobeShape
    let projection: GlobeProjection
    let canvasSize: CGSize
    let appearance: PrefectureAppearance
    let isHinted: Bool
    let effect: MapEffect?
    /// nil はラベル無し(重心が裏側、または親が名前を渡していない)。
    let accessibilityLabel: String?
    let reduceMotion: Bool

    /// よその国宛てのエフェクトを生き延びる(`EffectTriggers` の註)。
    @State private var triggers = EffectTriggers()

    /// 拡大は半径に入っているので、平面版と違いどの幅も zoom で割らない。
    private var dieCutWidth: CGFloat {
        min(max(canvasSize.width * 0.009, 0.5), 3)
    }

    private var boundaryWidth: CGFloat {
        MapStroke.hairlineWidth(canvasWidth: canvasSize.width, zoom: 1)
    }

    /// 赤い輪(出題・ヒント)— 平面版と同じ重さ(`MapStroke.ringWidth`)。
    /// 拡大は半径に入っているので zoom では割らない。
    private let ringWidth: CGFloat = MapStroke.ringWidth

    var body: some View {
        // 1 回の body 評価につき投影は 1 回。塗り・縁・輪が同じ Path を見る。
        let path = GlobeGeometry.path(for: shape, projection: projection)
        let centroid = GlobeGeometry.screenCentroid(of: shape, projection: projection)

        layers(path: path)
            .modifier(PopEffect(trigger: triggers.pop,
                                anchor: anchor(for: centroid),
                                enabled: !reduceMotion))
            .modifier(ShakeEffect(trigger: triggers.shake,
                                  enabled: !reduceMotion))
            // nil は「自分宛てではない」— 何も動かしてはいけない(平面版と同じ)。
            .onChange(of: effect) { _, new in triggers.apply(new) }
            .overlay(alignment: .topLeading) {
                // 全点が裏側なら国は存在しないのと同じ — バッジも出さない。
                if !path.isEmpty { badge(at: centroid) }
            }
            .accessibilityHidden(true)
            .overlay(alignment: .topLeading) {
                accessibilityProxy(path: path, centroid: centroid)
            }
    }

    private func layers(path: Path) -> some View {
        ZStack(alignment: .topLeading) {
            path.fill(appearance.fill, style: FillStyle(eoFill: true))

            if appearance.isStuck {
                path.stroke(appearance.stroke, lineWidth: dieCutWidth)
            } else {
                path.stroke(appearance.stroke, lineWidth: boundaryWidth)
            }

            if appearance.isStuck, case .pop? = effect?.kind {
                CorrectFoilTrace(path: path,
                                 lineWidth: max(dieCutWidth * 0.8, 1),
                                 reduceMotion: reduceMotion)
                    .id(effect?.id)
            }

            if appearance.isSparkling {
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

    /// scaleEffect の錨はキャンバス全体の単位空間(平面版と同じ理由)。
    private func anchor(for centroid: CGPoint) -> UnitPoint {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return .center }
        return UnitPoint(x: centroid.x / canvasSize.width,
                         y: centroid.y / canvasSize.height)
    }

    @ViewBuilder private func badge(at centroid: CGPoint) -> some View {
        if let badge = appearance.badge {
            Text(badge)
                .font(.system(size: 26))
                .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                .modifier(RiseEffect(enabled: !reduceMotion))
                .position(x: centroid.x, y: centroid.y)
                .allowsHitTesting(false)
        }
    }

    /// 平面版 `accessibilityProxy` と同じ理屈の代理要素。枠は投影済み
    /// Path の boundingRect から取る(リムへクランプされた点も含む —
    /// 見えている広がりそのもの)ので、44pt の下限ごと平面版と同じ形。
    @ViewBuilder private func accessibilityProxy(path: Path,
                                                 centroid: CGPoint) -> some View {
        if let accessibilityLabel {
            let box = path.boundingRect
            Color.clear
                .frame(width: max(box.width, 44), height: max(box.height, 44))
                .position(centroid)
                .allowsHitTesting(false)
                .accessibilityElement()
                .accessibilityLabel(accessibilityLabel)
                .accessibilityAddTraits(.isButton)
        }
    }
}

// MARK: - Preview

/// 実データ(WorldShapes.json)で地球儀を回すハーネス。マイマップ相当の
/// 習熟見本をコードで散らし、ドラッグ・ピンチ・タップを手で確かめられる。
private struct GlobeMapPreview: View {
    @State private var center: GlobeCenter
    @State private var zoom: CGFloat
    private let atlas = Atlas.loadWorld()

    init(center: GlobeCenter = .home,
         zoom: CGFloat = 1) {
        _center = State(initialValue: center)
        _zoom = State(initialValue: zoom)
    }

    var body: some View {
        if let globe = atlas.globe {
            GlobeMapView(
                globe: globe,
                appearance: { code in
                    PrefectureAppearance(
                        fill: MasteryStyle.fill(level: code % 6),
                        stroke: Palette.boundary,
                        isSparkling: code % 6 >= GameRules.maxMastery,
                        isStuck: false)
                },
                interactiveCodes: Set(globe.shapes.map(\.code)),
                center: $center,
                zoom: $zoom,
                accessibilityName: { code in atlas.mapData[code]?.kana ?? "" },
                onTap: { _, _ in })
                .padding()
                .background(Palette.background)
        } else {
            Text("WorldShapes.json が よみこめない")
        }
    }
}

#Preview("せかい ちきゅうぎ") {
    GlobeMapPreview()
}

#Preview("かいてん・ズーム") {
    GlobeMapPreview(center: GlobeCenter(longitude: -60, latitude: -15), zoom: 2)
}
