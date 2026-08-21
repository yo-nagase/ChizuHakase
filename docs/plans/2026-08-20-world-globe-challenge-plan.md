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
  (フィジー 180.18°E・ロシア 189.76°E も三角関数上は等価。
  球には日付変更線問題が無い)
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

> **Task 4 レビューからの ride-along(2026-08-20・最初のコミットでやる):**
> - QuizViewModel の `repeats:` 行に道標コメント(challengeQuestionCount を
>   超える challenge は challengeSelection で抽選するまで存在してはならない)+
>   両アトラス全ステージで `QuizViewModel.questionCount == stage.questionCount`
>   の突き合わせテスト(未配線の >47 チャレンジが VM に届いた瞬間に落ちる。
>   逆方向 — 19 面目が isChallenge:false で通る 334/334 自己整合 — は
>   捕まえないとテストコメントに明記し、Task 5 本体のピンで塞ぐ)
> - RegionZoom.id = label.kids の一意性をピンか一行コメントで
> - QuizView:245-252/276-282 の「全国チャレンジ」コメント 2 件を isChallenge
>   世代に言い直す(ZoomHintChip が世界チャレンジ平面に出るのは意図どおり —
>   そう書く)
> - AtlasNoun の型ドキュメントに「アトラスが運ぶ こども/おとな 語彙対」への
>   役割拡大を一句(地域ラベルは共有文への差し込みでも本の間の差でもない)
> - Stage.questionCount の `* 2` を `asksEachTwice` 経由に戻すか相互参照を明記

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

> **Task 3 レビューからの ride-along(2026-08-20):**
> - **冒頭でやる**: ヒント回転の閾値を「重心が前面半球」から「快適に見える角距離」
>   へ(`GameRules.globeHintComfortDegrees` ≈ 60–70°、`GlobeProjection` に
>   角距離の口を追加)。nameIt の事前回転も同じ述語を使う — 88° の縁で
>   つぶれた輪郭が点滅しても 3 回ミスした子は見つけられない
> - GlobeSurface のドラッグ基準点を startLocation キーに(GlobeMapView:188/281 —
>   システムキャンセルで lastDrag が残ると次ドラッグの初回デルタが跳ぶ。
>   直すと 10pt スロップぶんの初回ジャンプも同時に消える。@GestureState は
>   updating/onChanged の順序が未定義なので使わない)
> - 赤リング幅 3.5 の 2 ファイル重複を共有定数へ(GlobeMapView:404 /
>   PrefectureMapView:397 — コメントで結ばれた越境不変条件)
> - 任意: hairlineWidth をトップレベル関数から名前空間 enum の static へ/
>   リムのコメント「インセット枠と同じ」の言い過ぎ修正(0.22/1.5 vs 0.35/1.6)/
>   ちょうど 90° の重心でヒント回転が起きるピン

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

> **裁定(2026-08-21)**: タイトルのミニ地球儀は**見送り** — 並行セッションが
> TitleView.swift + TitleLogoWorld.imageset を編集中(未コミット)で、
> 同ファイルへの合流は巻き込み事故(da0cd8b の前例)のリスクが利益を上回る。
> ツリーが落ち着いてから小タスクとして単独で判断する。Task 7 は MyMapView 限定。
>
> **Task 6 レビューからの ride-along:**
> - QuizView:394 の `codes:` 三項演算子 — 地方側がなぜ quiz.order のままかを
>   一句(または stage.codes に統一して削除。集合としては同値、変わるのは
>   地方の描画/a11y 反復順のみ)
> - `interactiveCodes: quiz.mode == .nameIt ? [] : quiz.interactiveCodes` の
>   verbatim 重複(QuizView:397/427)を computed ヘルパーに
> - `GlobeCenter(138, 36)` のマジックナンバーを `GlobeCenter.home` 等の
>   名前付き定数へ(§11)
> - mapView コメントに平面世界チャレンジ = 167 PrefectureLayer の負荷プロファイル
>   注記(旧 47。古い機種でカクつくならここ)

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
- **Task 7 レビューからの ride-along**:
  - GlobeMapView のヘッダに回転ドラッグの highPriority 契約を 1 文
    (「平面版との構造差はひとつ」は今や過少申告 — 将来のホスト作者が読む場所に)
  - ドラッグ UI テストに端末形状依存の一言(0.88/0.06 は CI iPhone 調整値。
    iPad の pageColumn 余白では 0.88 が盤外)
  - RootView:284 の -learnFirstStage コメントに「-resetSave 併用時」の限定を
  - MyMapView の accessibilityZoomAction 重複 2 カ所を共有ヘルパーか
    コメント引き継ぎで
  - **VoiceOver は地球儀を回せない** — マイマップの裏側の国の詳細に届かない。
    accessibilityAdjustableAction(経度ステップ)等が安ければ入れる、
    高ければ申し送りに記録(クイズ側は平面トグルが代替経路)
- Reduce Motion / Dynamic Type / iPad 4 方向を地球儀画面で一巡
- 全ユニット + 全 UI スイート通し。日本フロー不変の最終確認
- 完了記録をこの文書に追記

---

## 完了記録

| Task | コミット | レビュー |
| --- | --- | --- |
| 1 投影純関数 | `a21a6b4` `b44bd29` | 仕様✅(数学を独立再導出)/ 品質✅(ユニット 382 緑。screenCentroid 継ぎ目と可視式の緯度項ピンを追補 — 後者はミューテーションで有効性実証) |
| 2 度数リング保持 | `9f32e46` | 仕様✅(平面側の bit 同一性を文字単位確認)/ 品質✅(ユニット 390 緑。実データ計測: 国 5,721 点+背景 645 点 — 地球儀の毎フレーム再投影は余裕、間引き基盤は作らない) |
| 3 GlobeMapView | `ca5b953` | 仕様✅(平面側 stampAnchor 切り出しが verbatim)/ 品質✅(ユニット 406 緑。Binding+Animatable 構成・ズームは半径に入れて補正ゼロ。持ち越しは Task 6 ride-along に記載) |
| 4 旗の再定義 | `2a7ab43` | 仕様✅(日本の文言・コード・ゲートをバイト単位確認、UI テスト再実行)/ 品質✅(ユニット 410 緑。前方ガードは Task 5 冒頭の ride-along に記載) |
| 5 せかいチャレンジ | `1f4f61d` `5d7f26f` `0594c4d` | 仕様✅(§8 の抽選・一巡リセットを手検証)/ 品質✅(ユニット 427 緑。asked は既定値なしの必須引数、一巡分母は目録由来で専用テストにピン。UI スモークの隣国直撃 4 カ国フレークを実測から修正) |
| 6 クイズ統合 | `256fa4b` `da0cd8b` `f9fbea2` | 仕様✅ / 品質✅(ユニット 434 緑単体検証。世界チャレンジは地球儀で開き、トグルは表示のみ。道中で Task 5 の取りこぼし — 平面チャレンジが抽選 47 カ国しか描かない — を修正。da0cd8b が並行セッションのずかんテスト hunk を巻き込み → f9fbea2 で外科的に未コミットへ返した) |
| 7 マイマップ地球儀 | `6ef336a` `42ef574` | 仕様✅(単体 434 緑・UI 単体ビルド緑)/ 品質✅(回転ドラッグは highPriorityGesture — 意味論として正の判定。タイトルミニ地球儀は衝突回避で見送り。ドキュメント修正 3 件は Task 8 送り) |
| 8 仕上げ | `56bec75` `bd8b52e` | 仕様✅(単体再検証)/ 品質✅(共有ツリー 442 緑・UI 全クラス緑・単体 439 緑。drawPolicy 既定削除、VoiceOver 回転つまみ(±45°・正面国を読み上げ)、RM 穴なし、DT/iPad 4 方向実タップ確認。全国到達の不変条件を実データでピン) |

**最終レビュー(2026-08-21): READY** — 出口(そうごう棚 → 地球儀チャレンジ →
トグル → 結果 → マイマップ地球儀)を単体ツリーで踏破。地球儀と平面のタップは
ルールコードの手前で合流(セーブ効果は構造的に同一)、center への 3 書き手は
自己修復、§8 ライフサイクルは中断時無書き込み、§1 制約・日本フロー不変を
全レンジで確認(単体 439 緑)。指摘は Minor のみ・対応済みまたは申し送り済み。

## ユーザーサインオフ待ち(実装は仮文言で進める)

- ステージ名「せかい チャレンジ」/ 棚見出し「そうごう」
- トグルチップの文言(仮: 「ちきゅうぎ」⇄「ちず」)
- P6 から持ち越し: カード欄見出し「せかいの カード」

## P8(別計画)

- オリジナルカード 167 枚(制作パイプライン + シルバー解放文言)
- リリース前: Natural Earth 出典表記、実機発音確認、中国/韓国別名(P6 申し送り)、
  **VoiceOver 実機確認**(地球儀の回転つまみ — 値の読み・increment の向き・
  要素の発見性。XCUITest では adjustable action を駆動できないため実機のみ)

## ツリーが静かになったらやる小タスク(並行セッションとの衝突回避で見送った分)

- タイトル世界ページのミニ地球儀(Task 7 裁定で見送り。TitleView が空いたら)
- `MasteryStyle` を TitleView.swift から `Components/`(Palette/StickerStyle の隣)へ
  移設(3 機能が使う共有品になった。Task 7 時点では TitleView が並行編集中で不可)
