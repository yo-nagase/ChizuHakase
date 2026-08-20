import CoreGraphics
import Foundation

// 地球儀モード(設計 2026-08-16 §7 / 計画 2026-08-20 Task 1)。
// SceneKit は使わない — 正射図法の純関数で「球を横から見た円盤」を作り、
// 描画は既存の Path + even-odd に流す(新規依存ゼロ、CLAUDE.md §1)。

/// 地球儀に描く 1 形状。
///
/// **座標は度数**: `rings`・`centroid` は x = 経度、y = 緯度で、
/// **y は北向き(上向き)** — 投影済みの平面データ(y 下向き)と正反対。
/// 混ぜると世界が逆さまになるので、この型に入れてよいのは
/// 投影前の実位置・実縮尺の座標だけ(インセットの拡大・移設は平面専用)。
///
/// - リング末尾の閉環重複点は `WorldCountry.flatRings` と同じく保持する
///   (落とすと 2 つの地図でデータ規約が割れる)。
/// - 経度は日付変更線またぎを +360 正規化した値(フィジー 189.75 など)を
///   そのまま持ってよい。三角関数上は等価で、球には日付変更線問題が無い。
/// - 置き場所(Components)は仮 — Atlas 側の置き場が定まったら移す
///   (WorldDataLoader の値型と同じ「一時的な同居」の規律)。
nonisolated struct GlobeShape: Identifiable, Sendable, Equatable {
    /// ISO 3166-1 numeric(`WorldCountry.code` と同じ)。
    let code: Int
    /// 外周と穴(度数)。even-odd で塗り・判定する。
    let rings: [[CGPoint]]
    /// pole of inaccessibility(度数)。可視判定と `centering` の錨。
    let centroid: CGPoint

    var id: Int { code }
}

/// 正射図法(orthographic)。中心 `(lon0, lat0)` を正面に置いた球を、
/// スクリーン中心 C・半径 R(pt)の円盤へ写す純関数。
///
/// 前方投影(度→ラジアン変換後):
/// `x = R·cos(lat)·sin(lon−lon0)`
/// `y′ = R·(cos(lat0)·sin(lat) − sin(lat0)·cos(lat)·cos(lon−lon0))`
/// スクリーンは `(C.x + x, C.y − y′)` — y′ は北向きなので反転する。
nonisolated struct GlobeProjection: Sendable, Equatable {
    /// 正面に来る経度(度)。wrap は `dragged(by:)` / `centering` が行うので、
    /// ここは任意の値を保持できる(三角関数は wrap 無しでも等価)。
    var centerLongitude: Double
    /// 正面に来る緯度(度)。
    var centerLatitude: Double
    /// 円盤の半径(pt)。
    var radius: CGFloat
    /// 円盤の中心(スクリーン座標)。
    var screenCenter: CGPoint

    /// 中心緯度の上限。±90° に近づくと cos(lat0) → 0 の特異点で回転が
    /// 暴れるため手前で止める。実データの最北の重心(グリーンランド
    /// ~74°N)でも余裕がある。
    static let centerLatitudeLimitDegrees: Double = 85

    /// 可視判定のしきい値。数学上の地平線は cosC = 0 だが、浮動小数では
    /// ちょうど 90° 離れた点が cos(π/2) ≈ 6e-17 > 0 に化ける。エッジオン
    /// (見かけの幅ゼロ)の点は不可視側に倒すのが正しいので、丸め誤差を
    /// 吸収する幅だけ内側で切る(角度にして 90° ± 6e-11° — 知覚不能)。
    private static let horizonCosine: Double = 1e-12

    private static let degreesPerRadian = 180.0 / Double.pi
    private static let radiansPerDegree = Double.pi / 180.0

    // MARK: - 前方投影

    /// 投影の本体。スクリーン点と可視かどうかを一度の三角関数で返す —
    /// 描画とヒットテストが同じ数字を見るための単一の入口。
    ///
    /// 不可視(地平線とその向こう)の点は `(x, y′)` を長さ R に正規化して
    /// 縁(リム)へ写す。地平線をまたぐポリゴンを閉じたまま保つための
    /// 標準手法で、全点が不可視のリングを描かない選別は `GlobeGeometry` の側。
    ///
    /// 性能の註(Task 3 の描画へ): sin/cos(lat0) は点ごとに再計算される —
    /// libm 呼び出しはコンパイラが共通化しない。ドラッグ 1 フレームで
    /// 数千点を写して足りなくなったら、lat0 の三角関数を事前計算した
    /// プロジェクタへ持ち上げること(プロファイルが求めるまではしない)。
    func project(lon: Double, lat: Double) -> (point: CGPoint, isVisible: Bool) {
        let lambda = (lon - centerLongitude) * Self.radiansPerDegree
        let phi = lat * Self.radiansPerDegree
        let phi0 = centerLatitude * Self.radiansPerDegree
        let cosC = sin(phi0) * sin(phi) + cos(phi0) * cos(phi) * cos(lambda)
        let visible = cosC > Self.horizonCosine

        let r = Double(radius)
        var x = r * cos(phi) * sin(lambda)
        var yUp = r * (cos(phi0) * sin(phi) - sin(phi0) * cos(phi) * cos(lambda))
        if !visible {
            let length = (x * x + yUp * yUp).squareRoot()
            if length > 0 {
                x = x / length * r
                yUp = yUp / length * r
            } else {
                // 真裏(対蹠点)は (0, 0) に写り、正規化の向きが定まらない。
                // どこへ置いても等しく間違いなので、決定的に右端へ置く。
                x = r
                yUp = 0
            }
        }
        return (CGPoint(x: screenCenter.x + x, y: screenCenter.y - yUp), visible)
    }

    func point(lon: Double, lat: Double) -> CGPoint {
        project(lon: lon, lat: lat).point
    }

    /// 正面半球(cosC > 0)にあるか。地平線ちょうどはエッジオンなので不可視。
    func isVisible(lon: Double, lat: Double) -> Bool {
        project(lon: lon, lat: lat).isVisible
    }

    // MARK: - ドラッグ回転

    /// ドラッグ delta(pt)を適用した新しい投影。
    ///
    /// `Δlon = −Δx/R·(180/π)`、`Δlat = +Δy/R·(180/π)`。符号は前方投影から
    /// 導ける: lon0 を減らすと正面の内容は右へ動くので、右ドラッグ
    /// (Δx > 0)は lon0 を減らす(西が正面に来る)。lat0 を増やすと内容は
    /// 下へ動くので、下ドラッグ(Δy > 0)は lat0 を増やす(北が正面に来る)。
    ///
    /// 経度側を cos(lat0) で割る厳密形は使わない — 高緯度で 1pt が数十度に
    /// 化けて地球儀が吹き飛ぶ。掴み心地は厳密性より安定を優先する
    /// (計画 Task 1 の明示判断)。
    func dragged(by delta: CGSize) -> GlobeProjection {
        // レイアウト初回のサイズ 0 の瞬間にドラッグが届くと、ゼロ除算の
        // NaN が状態を恒久的に汚す。素通しで守る。
        guard radius > 0 else { return self }
        let degreesPerPoint = Self.degreesPerRadian / Double(radius)
        var next = self
        next.centerLongitude = Self.wrappedLongitude(
            centerLongitude - Double(delta.width) * degreesPerPoint)
        next.centerLatitude = Self.clampedLatitude(
            centerLatitude + Double(delta.height) * degreesPerPoint)
        return next
    }

    /// (−180, 180] へ畳む。三角関数は wrap 無しでも等価だが、ドラッグを
    /// 重ねた値が際限なく育つと Double の分解能が落ちるので畳んでおく。
    static func wrappedLongitude(_ longitude: Double) -> Double {
        var wrapped = longitude.truncatingRemainder(dividingBy: 360)
        if wrapped > 180 { wrapped -= 360 }
        if wrapped <= -180 { wrapped += 360 }
        return wrapped
    }

    /// 極の特異点(`centerLatitudeLimitDegrees` の註)を避けるクランプ。
    static func clampedLatitude(_ latitude: Double) -> Double {
        min(max(latitude, -centerLatitudeLimitDegrees), centerLatitudeLimitDegrees)
    }
}
