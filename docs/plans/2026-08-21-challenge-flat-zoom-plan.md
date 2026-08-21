# P9: 世界チャレンジ平面地図のズーム上限拡大 実装計画

> **For Claude:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development。

**Goal:** ワールドチャレンジの平面地図で、どの収録国も「その国が属する
地方ステージの地図と同じ大きさ」まで拡大できるようにする(ユーザー要望
2026-08-21「平面地図の方の拡大率をもう少し拡大できるようにしたい」)。

**Architecture:** `ZoomPan.maxScale = 4` は全画面共有の既定のまま残し、
上限を**呼び出しごとの引数**にする。世界チャレンジだけが大きい上限を渡し、
その値はステージ枠と各地方ステージ枠の比から**データで導出**する
(沖縄インセットの空き海域走査と同じ「手置きしない」流儀)。

**関連ユーザー要望(このプランには含めない):**
「ワールド編のずかんを国別グルーピングでなく所持カードの取得順一覧に」は
**並行セッションが実装中**(CardBookView / SaveData / SaveStore の未コミット
diff に `ownedCardsInAcquisitionOrder` と世界の本のグリッド化が既に載っている
のを 2026-08-21 に確認)。このセッションでは触らない — 二重実装は先方の
作業を破壊する。

---

## 上限値の導出(実装の根拠)

WorldShapes.json の各国 bbox から、チャレンジ枠(全収録国の bbox 連結)と
ステージ枠の比 `max(challengeW/stageW, challengeH/stageH)` を全 18 ステージで
とると最大 **16.9**(stage 11 みなみアフリカ。次点 stage 4 にしヨーロッパ 16.4、
stage 1 カリブかい 14.9)。この形はフレーム縦横比に依らない上界
(`min(W/w,H/h) / min(W/cw,H/ch) ≤ max(cw/w, ch/h)` が常に成り立つ)なので、
**この最大比を上限にすれば、どの端末でもどの国もステージ地図と同じ以上の
大きさまで寄れる**。タップ許容(スクリーン 22pt)はズームと独立に効くため、
寄れること自体が小国のタップ成立を回復する。

- 日本(全国チャレンジ含む)と世界の地方ステージは **4 のまま**。
  4 を超えると「形が背後のディテールより大きくなる」という既定の美観判断
  (ZoomPan.swift のコメント)は変えない — 世界チャレンジだけ、成立性が
  美観に優先する
- 導出はコードで行い(データが変われば追従)、テストで現在値 ≈ 17 を釘打つ

## 前提(実装者への注意)

- 並行セッションと同一ツリー。`git add -A` 禁止・pathspec のみ。
  **QuizView.swift は他人の未コミットハンクを含む** — 変更は 1 行(zoomPan
  呼び出しへの引数追加)に留め、コミットは scratch-index 方式で自分のハンク
  だけを綴じる(前例 P6 p6t3-commit.sh)。他のファイル(ZoomPan / GameRules /
  Atlas / Stage / テスト)はクリーン
- シミュレータ: ユーザーの iPhone 15(86FE017B-…)不可。iPhone 15 Pro
  (89951824-…)+ scratchpad 隔離 derivedDataPath。xcodebuild は
  フォアグラウンドのみ
- ビューは japan/world で分岐しない。上限は Stage(または Atlas)が値として
  運び、QuizView は運ばれた値を渡すだけにする

## Task 1: 上限の引数化と世界チャレンジへの配線

**Files:**
- Modify: `ChizuHakase/Components/ZoomPan.swift`(clamp / scale / Modifier に
  max 引数、既定は maxScale)
- Modify: `ChizuHakase/Models/GameRules.swift`(導出の純関数)
- Modify: `ChizuHakase/Models/Stage.swift` + `ChizuHakase/Models/Atlas.swift`
  (ステージが flat ズーム上限を値として運ぶ。既定 = ZoomPan.maxScale 相当、
  世界チャレンジだけ導出値)
- Modify: `ChizuHakase/Features/Quiz/QuizView.swift`(zoomPan 呼び出しに
  上限を渡す 1 行。scratch-index)
- Test: `ChizuHakaseTests/ZoomPanTests.swift`(max 引数の clamp 境界)、
  `ChizuHakaseTests/GameRulesTests.swift` or `AtlasTests.swift`
  (実データで導出値 ≈ 17 と「全ステージ比の最大値以上」を釘打つ。
  日本側・世界地方ステージが 4 のままであることも)

**Steps(TDD):** 失敗するテスト → 実装 → 全スイート緑(453 から純増)→
scratch-index コミット → 他人のハンク無傷確認。

実装後の目視: 世界チャレンジ → トグルで平面 → 上限まで寄って小国(カリブ等)
がステージ並みの大きさになること。日本の全国チャレンジが 4 のままなこと。
