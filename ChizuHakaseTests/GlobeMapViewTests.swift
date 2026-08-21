import CoreGraphics
import Foundation
import Testing

@testable import ChizuHakase

/// 地球儀 View の回転状態(P7 Task 3)。アニメーションの到達値を決める
/// 純ロジックだけをピンする — View に業務ロジックを書かない(CLAUDE.md §11)。
struct GlobeCenterTests {

    @Test func 経度は最短の弧で向かう() {
        // 170°E から −170°E へは +20°(日付変更線越え)が最短。素の代入だと
        // SwiftUI は数値を直線補間して 340° 逆回りに一周近く回る —
        // この関数の存在理由。
        let moved = GlobeCenter(longitude: 170, latitude: 0)
            .facing((longitude: -170, latitude: -17))
        #expect(abs(moved.longitude - 190) < 1e-9)
        #expect(moved.latitude == -17)
    }

    @Test func 逆向きも最短の弧() {
        let moved = GlobeCenter(longitude: -170, latitude: 0)
            .facing((longitude: 170, latitude: 0))
        #expect(abs(moved.longitude - (-190)) < 1e-9)
    }

    @Test func 半回転ちょうどは決定的に東回り() {
        // wrappedLongitude は (−180, 180] に畳む — ちょうど半回転は +180 に倒れ、
        // どちらへ回るかが実行ごとに揺れない。
        let moved = GlobeCenter().facing((longitude: 180, latitude: 0))
        #expect(moved.longitude == 180)
    }

    @Test func 到達値は目的地と等価な投影になる() {
        // 190° は wrap の外の値だが、三角関数上 −170° と等価なので
        // そのまま投影に食わせてよい(GlobeProjection の規約)。
        let moved = GlobeCenter(longitude: 170, latitude: 0)
            .facing((longitude: -170, latitude: 0))
        let projection = GlobeProjection(centerLongitude: moved.longitude,
                                         centerLatitude: moved.latitude,
                                         radius: 100,
                                         screenCenter: CGPoint(x: 200, y: 300))
        let point = projection.point(lon: -170, lat: 0)
        #expect(abs(point.x - 200) < 1e-9)
        #expect(abs(point.y - 300) < 1e-9)
    }

    @Test func 緯度はクランプされる() {
        // 極の特異点回避(GlobeProjection.centerLatitudeLimitDegrees)を
        // 到達値の側でも守る — アニメーションの終点が禁止域に入らない。
        let moved = GlobeCenter().facing((longitude: 0, latitude: 89))
        #expect(moved.latitude == GlobeProjection.centerLatitudeLimitDegrees)
    }
}

/// 地球儀 View から切り出した純関数(半径・ヒント回転・重なり順)。
struct GlobeMapViewLogicTests {

    // MARK: - 半径

    @Test func 半径は短辺と余白から決まる() {
        // 短辺 200 → 半径 200/2 − 6(mapPaddingPoints)= 94。
        let radius = GlobeMapView.radius(in: CGSize(width: 200, height: 300), zoom: 1)
        #expect(radius == 94)
    }

    @Test func ズームは1から4に畳まれる() {
        // ZoomPan.clamp と同じ意味論(計画 Task 3)。94 × 上限 4 = 376。
        let size = CGSize(width: 200, height: 300)
        #expect(GlobeMapView.radius(in: size, zoom: 9) == 376)
        #expect(GlobeMapView.radius(in: size, zoom: 0.1) == 94)
    }

    @Test func 潰れたフレームの半径はゼロ() {
        // 余白より小さいフレームで負の半径を作らない(レイアウト初回対策)。
        #expect(GlobeMapView.radius(in: CGSize(width: 8, height: 8), zoom: 2) == 0)
        #expect(GlobeMapView.radius(in: .zero, zoom: 1) == 0)
    }

    // MARK: - ヒント回転

    private func shape(code: Int, centroid: CGPoint) -> GlobeShape {
        // ヒント回転は重心しか見ないので、リングは空でよい。
        GlobeShape(code: code, rings: [], centroid: centroid)
    }

    @Test func 裏側のヒントは正面へ回す到達値を返す() {
        let hidden = shape(code: 5, centroid: CGPoint(x: 150, y: 10))
        let rotation = GlobeMapView.hintRotation(code: 5, shapes: [hidden],
                                                 from: GlobeCenter())
        #expect(rotation == GlobeCenter(longitude: 150, latitude: 10))
    }

    @Test func 正面のヒントは回さない() {
        // 見えている答えを回すと、点滅を見つけかけた子から地図が逃げる。
        let front = shape(code: 5, centroid: CGPoint(x: 10, y: 10))
        #expect(GlobeMapView.hintRotation(code: 5, shapes: [front],
                                          from: GlobeCenter()) == nil)
    }

    @Test func 快適域の内側は回さない() {
        // 40° は cos40° ≈ 0.77 — まだ形が形に見える距離。
        let comfortable = shape(code: 5, centroid: CGPoint(x: 40, y: 0))
        #expect(GlobeMapView.hintRotation(code: 5, shapes: [comfortable],
                                          from: GlobeCenter()) == nil)
    }

    @Test func 前面半球でも快適域の外なら回す() {
        // 80° は前面半球(可視)だが、前縮み cos80° ≈ 0.17 で輪郭は潰れて
        // いる。境界が「重心が見えるか」だった頃はここで据え置かれ、
        // 3 ミスの点滅が地平線際で空振りしていた(Task 3 レビューの指摘)。
        let edge = shape(code: 5, centroid: CGPoint(x: 80, y: 0))
        let rotation = GlobeMapView.hintRotation(code: 5, shapes: [edge],
                                                 from: GlobeCenter())
        #expect(rotation == GlobeCenter(longitude: 80, latitude: 0))
    }

    @Test func ちょうど90度の重心も回す() {
        // エッジオン(見かけの幅ゼロ)。浮動小数で cos(π/2) が正に化けても
        // 快適閾値 cos65° を上回ることはなく、境界の点が据え置かれない。
        let edgeOn = shape(code: 5, centroid: CGPoint(x: 90, y: 0))
        let rotation = GlobeMapView.hintRotation(code: 5, shapes: [edgeOn],
                                                 from: GlobeCenter())
        #expect(rotation == GlobeCenter(longitude: 90, latitude: 0))
    }

    @Test func 知らないコードは回さない() {
        #expect(GlobeMapView.hintRotation(code: 99, shapes: [],
                                          from: GlobeCenter()) == nil)
    }

    // MARK: - VoiceOver の調整つまみ(P7 Task 8)

    @Test func つまみは経度だけを一歩ぶん回す() {
        // wrap の掛からない出発点で素の一歩を見る(wrap は次のテスト)。
        let start = GlobeCenter(longitude: 10, latitude: 36)
        let east = GlobeMapView.stepped(start, east: true)
        #expect(east.longitude == 10 + GameRules.globeRotateStepDegrees)
        #expect(east.latitude == 36, "経度のつまみが緯度を動かしている")
        let west = GlobeMapView.stepped(start, east: false)
        #expect(west.longitude == 10 - GameRules.globeRotateStepDegrees)
    }

    @Test func つまみの経度は日付変更線で畳まれる() {
        // 170° + 45° = 215° → (−180, 180] へ wrap して −145°。畳まないと
        // スワイプを重ねた値が際限なく育つ(GlobeProjection.wrappedLongitude
        // の註)。
        let moved = GlobeMapView.stepped(
            GlobeCenter(longitude: 170, latitude: 20), east: true)
        #expect(moved.longitude == -145)
        #expect(moved.latitude == 20)
    }

    @Test func つまみを一周ぶん回すと同じ場所へ帰る() {
        // 45° × 8 歩 = 360°。球の上で迷子にならないことの保証そのもの。
        var center = GlobeCenter.home
        for _ in 0..<8 { center = GlobeMapView.stepped(center, east: true) }
        #expect(center == GlobeCenter.home)
    }

    /// つまみの一軸設計の前提を実データで釘に: どの収録国も、home の緯度の
    /// まま経度を一歩ずつ回すだけで(一周 = 8 歩)いつか正面半球に入る。
    /// P8 のデータ更新・home の移動・歩幅の変更がこの前提を破った瞬間に落ちる
    /// (stepped の doc コメント「39°S〜66°N」を主張から不変条件へ)。
    @Test func つまみの一周でどの国も正面半球に入る() throws {
        let world = try WorldDataLoader.load(
            contentsOf: TestResources.require("WorldShapes"))
        let steps = Int((360 / GameRules.globeRotateStepDegrees).rounded(.up))
        for shape in world.globe.shapes {
            var center = GlobeCenter.home
            var reachable = false
            for _ in 0..<steps where !reachable {
                let probe = GlobeProjection(centerLongitude: center.longitude,
                                            centerLatitude: center.latitude,
                                            radius: 1, screenCenter: .zero)
                reachable = probe.cosineOfAngularDistance(
                    lon: Double(shape.centroid.x),
                    lat: Double(shape.centroid.y)) > 0
                center = GlobeMapView.stepped(center, east: true)
            }
            #expect(reachable,
                    "code \(shape.code) はつまみの一周で正面半球に入らない")
        }
    }

    @Test func 読み上げ値は正面いちばん近くの国() {
        let near = shape(code: 1, centroid: CGPoint(x: 10, y: 5))
        let far = shape(code: 2, centroid: CGPoint(x: 120, y: 0))
        #expect(GlobeMapView.frontmostCode(shapes: [far, near],
                                           center: GlobeCenter()) == 1)
        // 回した先では顔ぶれが入れ替わる — 一歩ごとの聞こえ方の根拠。
        #expect(GlobeMapView.frontmostCode(
            shapes: [far, near],
            center: GlobeCenter(longitude: 130, latitude: 0)) == 2)
        #expect(GlobeMapView.frontmostCode(shapes: [], center: GlobeCenter()) == nil)
    }

    @Test func ヒント回転も最短の弧を通る() {
        // 現在 170°・答えの重心 −80°(角距離 110° — 裏側)。等価な経度の
        // うち現在地に近い 280° へ向かうこと(−80° へ直行すると 250° 逆回り)。
        let hidden = shape(code: 7, centroid: CGPoint(x: -80, y: 0))
        let rotation = GlobeMapView.hintRotation(code: 7, shapes: [hidden],
                                                 from: GlobeCenter(longitude: 170, latitude: 0))
        #expect(rotation == GlobeCenter(longitude: 280, latitude: 0))
    }

    // MARK: - 重なり順(平面版 MapEffectTests の球面鏡)

    @Test func 動いている国が点滅する国より上に来る() {
        let effect = MapEffect(code: 5, kind: .pop, id: 1)
        let slot = PrefectureAppearance.slot(for: 6)
        #expect(GlobeMapView.zIndex(for: 5, paint: slot, effect: effect, hintCode: 13) >
                GlobeMapView.zIndex(for: 6, paint: slot, effect: effect, hintCode: 13),
                "動いている国が隣の国の下に潜る")
        #expect(GlobeMapView.zIndex(for: 13, paint: slot, effect: effect, hintCode: 13) >
                GlobeMapView.zIndex(for: 6, paint: slot, effect: effect, hintCode: 13),
                "点滅する答えの輪郭があとから描かれる隣に削られる")
        #expect(GlobeMapView.zIndex(for: 5, paint: slot, effect: effect, hintCode: 13) >
                GlobeMapView.zIndex(for: 13, paint: slot, effect: effect, hintCode: 13),
                "いま動いている物が点滅している物より下になる")
        #expect(GlobeMapView.zIndex(for: 6, paint: slot, effect: effect, hintCode: 13) ==
                GlobeMapView.zIndex(for: 7, paint: slot, effect: effect, hintCode: 13),
                "その他の国は平らなまま")
        #expect(GlobeMapView.zIndex(for: 6, paint: .asked(for: 6), effect: effect, hintCode: 13) >
                GlobeMapView.zIndex(for: 7, paint: slot, effect: effect, hintCode: 13),
                "出題中の赤わくが隣に削られる")
    }
}

/// コンボスタンプの配置(平面版 comboPoint から切り出した純関数)。
/// 平面と地球儀が同じ式で置くことをここで固定する。
@MainActor
struct ComboStampPlacementTests {

    @Test func バッジが無ければスタンプはタップ位置に戻る() {
        // -34pt 持ち上げて描き +34pt 戻すので、余裕があれば元の点のまま。
        let anchor = ComboBurstLabel.stampAnchor(
            tap: CGPoint(x: 200, y: 300), radius: 48,
            badgeOrigin: nil, canvasSize: CGSize(width: 400, height: 600))
        #expect(anchor == CGPoint(x: 200, y: 300))
    }

    @Test func バッジと近すぎるスタンプは広い側へ避ける() {
        // clearance = 48 + 42 = 90。左の余地 62 < 右の余地 162 なので右へ。
        let anchor = ComboBurstLabel.stampAnchor(
            tap: CGPoint(x: 200, y: 300), radius: 48,
            badgeOrigin: CGPoint(x: 200, y: 300),
            canvasSize: CGSize(width: 500, height: 600))
        #expect(anchor == CGPoint(x: 290, y: 300))
    }

    @Test func スタンプは紙の中に畳まれる() {
        // 端へのタップでも箔の光条ごとパネルに収まる。
        let anchor = ComboBurstLabel.stampAnchor(
            tap: CGPoint(x: 5, y: 10), radius: 48,
            badgeOrigin: nil, canvasSize: CGSize(width: 400, height: 600))
        #expect(anchor == CGPoint(x: 48, y: 82))
    }
}
