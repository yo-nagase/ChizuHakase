# ワールドマップ機能 実装計画 P6(世界をユーザーに開く)

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 世界アトラスをユーザーに見える形で開通させる — タイトル 2 ページ化、
世界ステージ選択、結果・マイマップ・ずかんのアトラス対応、描画仕上げ、
なまえをあてる対応。地球儀とワールドチャレンジ(P7)、オリジナルカード制作
(P8)は含まない。**大陸ステージだけで遊び切れる状態**がこの計画の出口。

**前提:** P1–P5 完了(`2026-08-19-world-atlas-implementation.md` の完了記録と
P6 引き継ぎメモ 8 項目)。設計は `2026-08-16-world-atlas-design.md` §2(分岐は
タイトル 1 カ所)と `2026-08-18-world-stages.md`(ステージ選択 UI 決定
2026-08-20: 大陸見出し付き 1 本スクロール)。

**ブランチ:** `feature/worldmap`(継続)。コミットは pathspec 指定のみ。

**不変条件(全タスク共通の合格条件):**
- 日本版の全テスト緑を維持(ユニット 323+、UI 38+)
- View に japan/world の分岐を書かない — 分岐は Atlas 値と atlasKey だけ
- CLAUDE.md §1 制約(SDK/通信/IDFA なし)に触れない

---

### Task 1: ステージ選択のアトラス対応(大陸見出し付き 1 本スクロール)

**Files:**
- Modify: `ChizuHakase/Features/StageSelect/StageSelectView.swift`
- Modify: `ChizuHakase/Features/Title/RootView.swift`(.stageSelect ルートに atlas を渡し、⚠️ 罠コメントを解消)
- Test: `ChizuHakaseUITests/`(世界ステージ選択の看板数・見出しのスモーク)

- `StageSelectView` は `Atlas` を受け取り `atlas.stages` を並べる(`Stage.all`
  直参照を外す)。記録・おぼえた数は `save.data.atlas(atlas.saveKey)` から
- 世界のとき大陸セクション見出しを出す。見出しは stage index 区間から機械的に
  (0–2 アメリカ / 3–6 ヨーロッパ / 7–11 アフリカ / 12–16 アジア / 17 オセアニア)。
  日本のときは見出しなし(今のまま)
- 看板の色(`StageCardBackground.tints` 7 色)と地標アイコン
  (`StageLandmark.assetNames` 7 個)は `% count` 循環で 18 枚に流用し、
  世界専用の地標アセットは P6 では作らない(コメントで明示)
- ナビタイトルは `mode.stages`(「ステージ」)のまま両方共通

### Task 2: タイトル 2 ページ化(にほん ⇄ せかいの ちずちょう)★分岐はここだけ

**Files:**
- Modify: `ChizuHakase/Features/Title/TitleView.swift` / `RootView.swift`
- Modify: `ChizuHakase/Models/SaveData.swift`(settings に lastAtlas を追加 — v7 の
  まま。Settings は decodeIfPresent 方式なのでバージョンを上げない)
- Modify: `ChizuHakase/App/AppState.swift`(必要なら)
- Test: ユニット(lastAtlas の保存)+ UI(ページ切替 → あそぶ → 世界ステージ選択)

- 設計 §2 のとおり: タイトルを 2 ページのアルバムにし、**ページ端の見えるボタン**
  (「せかいの ちずへ →」/「← にほんの ちずへ」)で切り替える。スワイプ併用可
- 世界ページ = 世界シルエットのミニ地図(習熟色。`TitleView.miniMap` の世界版)+
  タリー(おぼえた くに n/167、もっている カード n/カタログ数)。データ駆動なので
  オリジナルカードが増えれば分母は自動で追従
- 前回開いていたページを記憶(settings.lastAtlas)。起動時はそのページから
- **ページ切替時に必ずやること(引き継ぎ 4・5)**: `VoiceInputService.configure`
  を表示中アトラスの語彙で呼び直す/世界ページが見えるタイミングで `app.world`
  を先読みし、初回タップの同期ロードヒッチを隠す
- あそぶ・タリーのタップは atlasKey に従って各画面へ(以降の画面に分岐は無い)
- デバッグ引数 `-atlas world` は残す(スクショ・テスト用)

### Task 3: 結果・マイマップ・ずかん・タイトルタリーのアトラス貫通

**Files:**
- Modify: `ChizuHakase/Features/Result/ResultView.swift`(⚠️ 罠コメントの解消)
- Modify: `ChizuHakase/Features/MyMap/MyMapView.swift`
- Modify: `ChizuHakase/Features/CardBook/CardBookView.swift`
- Test: ユニット(アトラス別タリー)+ UI(世界の結果画面まで通す — 引き継ぎ 6)

- ResultView に Atlas を通す: `app.cards`/`app.mapData`/`record`/`streak` を
  atlas 経由に。**カード ID の 7 件文字列衝突(引き継ぎ 2)がここで実害になる**ので、
  カード解決は必ず atlas.cards から
- MyMap: atlas の地図と習熟を表示。凡例・タリー・「きろくを ぜんぶ けす」は
  そのまま(**全削除は両方の本を消す仕様を維持** — 設計文書の推奨。文言に
  「ぜんぶの ちずちょう」の一言を足すかは実装時に判断)
- CardBook: atlas のカタログと所持で描く。国旗カードの札面は既存 CardFaceView が
  絵文字でそのまま描けるはず(確認)。フィルタチップは Task 8 で入れた
  dealtCategories 方式が世界で「こっき」だけになることを確認
- タイトルのタリーは Task 2 で atlas 別になっている前提の整合確認

### Task 4: 世界地図の描画仕上げ(背景・インセット・ロシア枠)

**Files:**
- Modify: `ChizuHakase/Components/PrefectureMapView.swift`(最小限)/ `Atlas.swift` /
  `WorldDataLoader.swift`(background/insets/europeBbox の配線)
- Test: ユニット(枠計算の純関数)+ スクショ確認

- **背景海岸線**: 収録外の国・属領(`background`)をグレーで描く(嘘の海岸線を
  作らない、の完成)。ステージ枠内に掛かるものだけで良い
- **インセット**: シンガポール・マルタ・モルディブ・フィジーを scale 2.5 の
  拡大枠で表示。沖縄インセットの描画(破線枠)を一般化する。配置は
  ステージ枠内の空き海域から機械的に選ぶ(沖縄方式の一般化。手置きしない)。
  タップ判定もインセット枠内で成立させる(沖縄と同じ仕組みの流用)
- **ひがしヨーロッパの枠**: ロシアは `europeBbox` を枠計算に使い、シベリアは
  枠外へはみ出す背景として描く(モルドバ 13pt 問題の解消)
- 必要なら**ステージ個別投影**(refLat をステージ中心緯度に)をここで入れる —
  きたヨーロッパの横伸びが視認で気になる場合のみ。入れる場合は純関数の
  テストを足す

### Task 5: なまえをあてる(世界)と音声

**Files:**
- Modify: `ChizuHakase/Services/VoiceInputService.swift`(語彙の差し替え口が
  Task 2 で済んでいる前提の確認)/ QuizViewModel(確認のみ)
- Test: ユニット(選択肢が同ステージ内から出る)+ UI(世界 nameIt 1 問)

- 4 択は既存ロジックがステージ内から選ぶので世界でもそのまま動くはず — 確認と
  テストが本体
- 音声入力: contextualStrings = 世界アトラスの語彙(かな 167 語 + 表記ゆれ)。
  「とうきょうと」相当のゆれ吸収(「あめりか」「あめりかがっしゅうこく」)は
  kana + nameJa 読みの 2 系で最小限に
- 読み上げ(findOnMap の自動読み)は kana がそのまま通る — 実機で発音確認

### Task 6: 仕上げ確認

- `-atlas world` デバッグ経路を通常導線(タイトル→ページ→あそぶ)に対して
  冗長になった範囲で整理(残す: スクショ・UI テストの直行入口)
- GameRules `drawCard` の `= .random` 既定引数を外す(引き継ぎ 7・Task 7 レビュー)
- Reduce Motion・Dynamic Type・iPad 4 方向を世界画面で一巡確認
- 履歴の tracked `tools/__pycache__/*.pyc` を `git rm --cached`(引き継ぎ 8)
- ストア文言・スクショは**含まない**(リリース準備は別作業)

---

## P7 以降(別計画)

- **P7: 地球儀モード + ワールドチャレンジ**(設計 §7・§8。正射図法 View、
  地球儀⇄平面切替、47 問抽選と askedInChallenge 消費、裏側ヒント救済、
  `isNationwide` の再定義)
- **P8: オリジナルカード 167 枚**(制作パイプライン + シルバー解放の文言
  「あと◯かいで オリジナルカード!」)
