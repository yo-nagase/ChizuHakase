# ワールドマップ機能 実装計画 P7(地球儀とワールドチャレンジ)

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> to implement this plan task-by-task.

**Goal:** 世界アトラスに総合ステージ「ワールドチャレンジ」を開き、その本体である
地球儀モード(正射図法)を実装する。世界マイマップも地球儀にする。
オリジナルカード制作(P8)は含まない。

**Architecture:** 正射図法は純関数(`GlobeProjection`)+ 平面版と同型の
ヒットテスト(`GlobeGeometry`)+ 専用 View(`GlobeMapView`)の 3 層。
SceneKit/RealityKit は使わない(新規依存ゼロ、CLAUDE.md §1)。
lon/lat は現在ロード時に投影されて消えるため、`WorldDataLoader` が度数リングを
`Atlas.globe` として別に保持する(日本は nil — View は「地球儀データの有無」で
振る舞いが変わるだけで、japan/world では分岐しない。インセット判定と同じ規律)。
ワールドチャレンジは毎回 47 問・未出題優先抽選(設計 §8)で、履歴は
`AtlasSave.askedInChallenge`(v7 で予約済み・現在未使用)に持つ。

**Tech Stack:** Swift 6 / SwiftUI / Swift Testing。データ変更なし
(WorldShapes.json は lon/lat のまま — パイプライン変更不要)。

**前提:** P6 完了(`2026-08-20-world-ui-plan.md` 最終レビュー READY)。
設計は `2026-08-16-world-atlas-design.md` §7(地球儀)・§8(ワールドチャレンジ)。

**ブランチ:** `feature/worldmap`(継続)。コミットは pathspec 指定のみ
(並行セッションの hunk に注意 — 対象外ファイルは §不変条件参照)。

**不変条件(全タスク共通の合格条件):**

- 日本版の挙動・文言・テストを一切変えない(ユニット 352+ 緑維持。
  特に `allJapanStageRunsAll47` と日本の `askedInChallenge` が空のままであること)
- View に japan/world の分岐を書かない — 分岐はデータの有無(`atlas.globe`、
  `stage.isChallenge`、`atlas.regionZooms`)だけ
- CLAUDE.md §1(SDK/通信/IDFA なし)・§11(print/強制アンラップなし、
  マジックナンバーは GameRules へ)・§9(Reduce Motion 尊重)

---

### Task 1: GlobeProjection + GlobeGeometry(純関数・TDD)

**Files:**

- Create: `ChizuHakase/Components/GlobeProjection.swift`
- Create: `ChizuHakase/Components/GlobeGeometry.swift`
- Test: `ChizuHakaseTests/GlobeProjectionTests.swift`

**GlobeProjection(正射図法)** — 値型。中心 `(lon0, lat0)`(度)、半径 R(pt)、
スクリーン中心 C を持つ。

- 前方投影: `x = R·cos(lat)·sin(lon−lon0)`,
  `y′ = R·(cos(lat0)·sin(lat) − sin(lat0)·cos(lat)·cos(lon−lon0))`,
  スクリーンは `(C.x + x, C.y − y′)`(y 反転)
- 可視判定: `cosC = sin(lat0)·sin(lat) + cos(lat0)·cos(lat)·cos(lon−lon0) > 0`
- **地平線クランプ**: `cosC ≤ 0` の点は `(x, y′)` を正規化して半径 R の縁
  (リム)へ写す。ポリゴンを閉じたまま保つための標準手法で、
  リング全点が不可視の国は描かない(設計 §7「90° 超の国は描かない」)
- 経度は sin/cos に食わせるだけなので **+360 正規化済みの値がそのまま通る**
  (フィジー 189.75°E も三角関数上は等価。球には日付変更線問題が無い)
- 回転: ドラッグ delta(pt)→ 中心の移動量(度)。`Δlon = −Δx / R · (180/π)
  / max(cos(lat0), ε)` は高緯度で暴れるので **`Δlon = −Δx / R · (180/π)` の
  単純形で良い**(地球儀の掴み心地は厳密性より安定を優先)。
  lat0 は ±85° にクランプ(極の特異点回避)、lon0 は wrap

**GlobeGeometry** — `PrefectureGeometry` と同じ意味論の球面版。
`CGAffineTransform` の代わりに `GlobeProjection` を取る:

- `path(rings:projection:)` — 点ごとに投影 + リムクランプ、even-odd
- `contains(_:point:projection:)` — CGPath even-odd(平面版 :39-50 と同じ理由)
- `resolveTap(at:target:among:projection:tolerance:targetBias:)` —
  直接ヒット優先 → 輪郭距離 22pt 許容 + 正解バイアス 10pt。定数は
  `GameRules.tapTolerancePoints` / `tapTargetBiasPoints` を共用
- `visibleCodes(among:projection:)` — 重心が可視の国(描画・VoiceOver 用)
- `centering(on:)` — 指定国の重心を正面に回す中心座標(ヒント・nameIt 用)

**Steps(TDD):** 手計算値でテストを先に書く
(例: lat0=0,lon0=0 で (0,0)→中心、(90,0)→右端 x=R、(0,90)→上端、
裏側 (180,0) は不可視でリムへ、緯度 60° の 1° 経度幅は赤道の半分)。
回転・クランプ・wrap もピン留め。実装 → 緑 → コミット。

### Task 2: 度数リングの保持(Atlas.globe)

**Files:**

- Modify: `ChizuHakase/Store/WorldDataLoader.swift`(WorldFile 消費時に
  度数リングを `GlobeShape` として併産。**flat 側は一切変えない**)
- Modify: `ChizuHakase/Models/Atlas.swift`(`globe: GlobeData?` を追加。
  japan は nil。空フォールバックも nil)
- Test: `ChizuHakaseTests/WorldDataTests.swift` 追記

- `GlobeShape` = code + 度数リング + 度数重心。**真の位置・真の縮尺**
  (インセットの拡大・移設は平面専用 — 地球儀は実位置で描く。
  `WorldInset` doc :50-61 が予告済み)。背景 77 形状も度数のまま持つ
  (地球儀の裏側にも大陸の嘘が無いように)
- メモリは JSON 141KB 相当 — 保持で問題ない。日本の `MapDataLoader` は触らない
- テスト: 167 形状、シンガポールの globe 重心 ≈ (103.8E, 1.35N)(flat の
  移設先と違うこと)、ロシアの度数 bbox が europeBbox でなく全土であること

### Task 3: GlobeMapView(描画・回転・ズーム)

**Files:**

- Create: `ChizuHakase/Components/GlobeMapView.swift`
- Test: ユニット(回転状態の純ロジックがあれば)+ Preview スクショ

- 入力は `PrefectureMapView` の部分集合と同型: `globe: GlobeData`,
  `appearance: (code) -> PrefectureAppearance`(MasteryStyle をそのまま流用),
  `interactiveCodes`, `targetCode`, `hintCode`, `effect`, `onTap`
- 海 = 円盤(`Palette.sea` グラデーション)+ 薄いリム。背景形状はグレー
  (平面と同じ `Palette.backgroundLand`)。塗りは even-odd
- ドラッグ = 回転(Task 1 の式)。ピンチ = `ZoomPan.clamp(scale:)` を流用した
  半径スケール(offset は使わない — 地球儀はパンしない)
- 正解 pop・絵文字浮上・コンボは投影後の重心にアンカー(既存 Effect View 流用)。
  **Reduce Motion**: 既存ゲートと同じ(自動回転は作らないので止める物は
  ドラッグ慣性くらい — 慣性を付けるなら RM で切る)
- ヒント(3 ミス)発火時: 正解国が裏側なら `GlobeGeometry.centering` へ
  アニメーション(RM 時はジャンプ)してから輪郭点滅 — 設計 §7 未決の解決
- VoiceOver: 可視国のみ `accessibilityLabel(かな名)`
- Preview で日本無し(world globe のみ)を確認 — このコンポーネントは
  GlobeData 必須なので japan では存在しない

### Task 4: isNationwide の再定義と地域ズームの Atlas 積み

**Files:**

- Modify: `ChizuHakase/Models/Stage.swift` / `Atlas.swift` /
  `ChizuHakase/Features/Quiz/QuizView.swift` / `QuizViewModel.swift`
- Test: 既存テスト維持 + 新ピン

**Atlas.swift:175-182 の道標に従い、罠 2 つを同時に外す:**

- `Stage.isNationwide`(`codes.count == 47`、Stage.swift:19)を**廃止**し、
  stored `let isChallenge: Bool`(default false)に置換。日本ステージ 6 と
  世界のワールドチャレンジ(Task 5)だけ true。使用 6 カ所
  (Stage.swift:19,27 / QuizView.swift:253,284,303,359)を移行
- `asksEachTwice = !isChallenge`。`questionCount` は
  `isChallenge ? min(codes.count, GameRules.challengeQuestionCount) :
  codes.count * 2`(challengeQuestionCount = 47 を GameRules 定数に。
  日本の challenge は codes 47 なので min で従来どおり 47 — 挙動不変)
- **地域ズームは Atlas へ**: `Atlas.regionZooms: [RegionZoom]`
  (label は TextMode 経由・codes)。japan = 従来 3 つ
  (QuizView.swift:361-363 / Stage.swift:64-66 から移設)、world = **空**
  (世界チャレンジの平面は地球儀が主役 — ボタンは足さない。YAGNI)。
  QuizView は `stage.isChallenge && !atlas.regionZooms.isEmpty` で出す
- テスト: 日本ステージ 6 の isChallenge/questionCount 不変、
  世界 18 ステージ全部 false、japan regionZooms 3 件・world 0 件

### Task 5: ワールドチャレンジ(47 問・未出題優先・askedInChallenge)

**Files:**

- Modify: `ChizuHakase/Models/WorldStage.swift`(19 面目 + 専用 AtlasSection)/
  `Atlas.swift` / `GameRules.swift` / `QuizViewModel.swift` /
  `SaveStore.swift`(askedInChallenge 更新)/ `RootView.swift`(配線確認)
- Test: ユニット(抽選の純関数を TDD)+ UI(世界チャレンジ 1 問スモーク)

- ステージ名は **「せかい チャレンジ」**(ぜんこく チャレンジと同型。
  ★ユーザーサインオフ対象 — 設計文書はワールドチャレンジ表記)、index 18、
  codes = 全 167、`isChallenge: true`。**棚は leftovers 枝に流さず**
  `WorldStage.sections` に専用区間 `18..<19` を明示追加
  (Atlas.swift:85-88 の規律。見出し文言も★サインオフ — 仮「そうごう」)
- **抽選の純関数(TDD)**: `GameRules.challengeSelection(codes:asked:count:using:)`
  — 未出題を優先で count 件(シャッフル)、不足分は出題済みから補充。
  ピン: 未出題 < 47 のとき全未出題が必ず入る/未出題 ≥ 47 のとき出題済みが
  入らない/選択は count 件・重複なし
- QuizViewModel: `stage.isChallenge && codes.count > challengeQuestionCount`
  のときだけ抽選(それ以外は従来の questionOrder — **日本は抽選経路に
  乗らないので askedInChallenge を書かない**。ピン必須)。1 国 1 回
- `StageResult` に `askedCodes: Set<Int>`(default 空)を追加。
  `SaveStore.applyStageResult` は challenge 結果のとき
  `askedInChallenge[mode] ∪= askedCodes`、全収録国を覆ったら空にリセット
  (§8 の 2 周目)。ピン: 4 プレイ相当で一巡 → リセット
- 記録(星・スコア)は mode → stageIndex 18 の従来 records に載る — 毎回
  47 問なのでベスト比較が成立(§8)

### Task 6: クイズ統合 — 地球儀 ⇄ 平面トグル

**Files:**

- Modify: `ChizuHakase/Features/Quiz/QuizView.swift`
- Test: UI(世界チャレンジを平面で 1 問 + 地球儀表示のスモーク)+ スクショ

- 世界チャレンジ(`stage.isChallenge && atlas.globe != nil`)は
  **地球儀モードで開く**。トグルチップ(🌍 ⇄ 🗺 相当。文言は TextMode に、
  ズームリセットと同じ帯 QuizView.swift:275-291)で平面へ切替。
  **表示モードであり出題状態を変えない**(問題・スコア・れんぞく持ち越し —
  設計 §7。quiz VM は一切知らない)
- タップは `GlobeGeometry.resolveTap`(許容・バイアス同値)。
  可視ゲートは「重心可視」で `ZoomPan.isVisible` 相当を置換
- nameIt: 出題時に対象国を正面へ回してから赤わく(設計 §7 未決の解決)。
  findOnMap のヒント回転は Task 3 実装を配線
- 平面モードは従来の PrefectureMapView(167 国 + 全インセット + 背景)。
  ズーム最大 4 のままで小国が苦しいのは地球儀が答え — 変更しない
- スクショ: `world-challenge-globe.png` / `world-challenge-flat.png` /
  `world-challenge-nameit.png`

### Task 7: 世界マイマップの地球儀 + タイトルのミニ地球儀

**Files:**

- Modify: `ChizuHakase/Features/MyMap/MyMapView.swift` /
  `ChizuHakase/Features/Title/TitleView.swift`
- Test: UI スモーク + スクショ

- 世界マイマップ(`atlas.globe != nil`)は地図パネルを地球儀に
  (回して緑を探す — 設計 §7 表)。タップで従来の詳細シート。
  凡例・タリー・全削除は不変。日本は従来の平面のまま(データの有無で決まる)
- タイトル世界ページのミニ地図もミニ地球儀(非対話・`allowsHitTesting(false)`
  のまま、TitleView.swift:345-391 の PrefectureMapView 差し替え)。
  **重くなるなら平面のまま残して良い**(ページめくりの 60fps が優先 —
  実測で判断し、見送るなら理由をここに書き足す)
- スクショ: `world-mymap-globe.png` / `world-title-globe.png`

### Task 8: 仕上げ

- `QuizViewModel.init` の `drawPolicy: = .random` 既定引数を外す
  (P6 最終レビュー指摘。生産は明示済み・テストだけ直す)
- Reduce Motion / Dynamic Type / iPad 4 方向を地球儀画面で一巡
- 全ユニット + 全 UI スイート通し。日本フロー不変の最終確認
- 完了記録をこの文書に追記

---

## ユーザーサインオフ待ち(実装は仮文言で進める)

- ステージ名「せかい チャレンジ」/ 棚見出し「そうごう」
- トグルチップの文言(仮: 「ちきゅうぎ」⇄「ちず」)
- P6 から持ち越し: カード欄見出し「せかいの カード」

## P8(別計画)

- オリジナルカード 167 枚(制作パイプライン + シルバー解放文言)
- リリース前: Natural Earth 出典表記、実機発音確認、中国/韓国別名(P6 申し送り)
