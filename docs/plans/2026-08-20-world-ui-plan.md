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
- 看板の色(`StageCardBackground.tints` 7 色)は `% count` 循環で流用する。
  地標アイコンは当初 P6 の範囲外として日本編 7 個を循環させていたが、
  **Issue #10 で解消済み**: 世界編 18 地方 + 世界チャレンジに固有の 19 個を追加し、
  `Atlas.stageLandmarkAssetNames` から値として運ぶ。View に japan/world 分岐は置かない
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

> **Task 3 レビューからの ride-along(2026-08-20):**
> - `PrefectureMapView` の沖縄インセット判定 `codes.contains(47)` を廃し、
>   データ駆動(`okinawaInset != .zero` を `MapData.hasInset` 等へ集約)にする。
>   世界で 47 が発火しないのは ISO の偶然に依っている。MyMapView:63 /
>   TitleView:371 の重複式もここで畳む
> - `SaveStore.applyStageResult` の `atlas key: String = SaveData.japanAtlas`
>   既定引数を外す(読み側で葬った「黙って日本」の書き込み側の双子。
>   DEBUG 4 呼び出しに明示引数を足すだけ)
> - RootView の `-learnFirstStage` は japan 固定のまま `-atlas` パースの後に
>   居る — atlas 対応にするか japan 専用と一言コメントするか、どちらかに倒す
> - WorldQuizUITests のずかんテストに「カタログ順で 12-1 が先頭」前提の
>   一言コメントを足す

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
- **実装時の裁定(2026-08-20)**: インセット倍率は固定 ×2.5 をやめ、
  10–22pt 帯(香川 band)に届く倍率を国ごとに**機械的に導出**する(×2.5 を
  下限とし、手置きしない)。固定 ×2.5 ではマルタ 9.0pt・シンガポール 6.3pt と
  ステージ文書自身の 10pt 基準を割ったため。**ステージ個別投影は P7 送り**
  (きたヨーロッパは 60°N で横 +73% — 見て分かるが判別は可能。配置・枠計算に
  波及するので地球儀と同時に判断する)

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
- **申し送り(2026-08-20)**: 認識器が「中国」「韓国」と短い漢字名で書く場合、
  nameJa(中華人民共和国/大韓民国)から機械導出できず照合に失敗する。
  実機で contextualStrings がかな出力へ誘導しきれないと分かったら、
  パイプラインに別名フィールド(KANA_OVERRIDES と同じ規律)を足す —
  Swift 側に国別の表を書かない。実機発音確認(あぜるばいじゃん等)も未実施

### Task 6: 仕上げ確認

- **世界画面の日本語彙を直す(Task 3 レビューで顕在化)**: 世界の結果画面に
  「✨ おぼえた けん!」「とくさんひん カード」が出る。名詞を Atlas に持たせて
  差し替える(タイトルのタリーは既に「おぼえた くに」なので「くに」は確定。
  カード欄の見出しは世界のカード名詞を設計 §5 と突き合わせて決める)
- CLAUDE.md §3 の JSON スキーマ例 `mapHeight 997.9` が現物(1066.7)と
  ずれている — 数値を現物に合わせる(Task 3 レビューで発見の既存ずれ)
- `-atlas world` デバッグ経路を通常導線(タイトル→ページ→あそぶ)に対して
  冗長になった範囲で整理(残す: スクショ・UI テストの直行入口)
- GameRules `drawCard` の `= .random` 既定引数を外す(引き継ぎ 7・Task 7 レビュー)
- Reduce Motion・Dynamic Type・iPad 4 方向を世界画面で一巡確認
- 履歴の tracked `tools/__pycache__/*.pyc` を `git rm --cached`(引き継ぎ 8)
- ストア文言・スクショは**含まない**(リリース準備は別作業)

---

## 完了記録

| Task | コミット | レビュー |
| --- | --- | --- |
| 1 ステージ選択 | `b23236b` | 仕様✅ / 品質✅ |
| 2 タイトル 2 ページ | `6e6f381` | 仕様✅ / 品質✅(-resetSave の atlasKey 再同期を修正) |
| 3 画面貫通 | `850dab4` | 仕様✅ / 品質✅(ユニット 333・UI 48 緑。持ち越しは Task 4/6 の ride-along に記載) |
| 4 描画仕上げ | `117673c` `71cc346` `3c72767` | 仕様✅ / 品質✅(ユニット 342 緑。モルドバ 24.8pt。倍率は機械導出 ×3.97/×2.77/×2.5/×2.5。枠のはみ出し余白と横長前提をバリデータの契約に格上げ。投影は P7 送り) |
| 5 なまえあて・音声 | `9ffa1fd` `f2df462` | 仕様✅ / 品質✅(ユニット 349 緑。接尾辞族の機械規則のみ・国別表なし。話し手側の一意性も 167 実データで固定。中国/韓国別名と実機発音は申し送り) |
| 6 仕上げ | `eaea109` `0c477b9` `d0e2517` | 仕様✅ / 品質✅(ユニット 352・UI 17 緑。名詞は Atlas 積み — 世界のカード欄「せかいの カード」は**ユーザー確認待ち**。デバッグ経路は削除ゼロが正。RM/DT/iPad 4 方向一巡) |

UI テストの数字は各タスクが回した範囲(関連スイートのみ)で、全 UI スイートの
通し数ではない。ユニットは常に全数。

**最終レビュー(2026-08-20): READY** — 出口条件(大陸ステージだけで遊び切れる)
をコードパスで踏破、§1 制約・View 無分岐・日本版不変をレンジ全域で確認、
タスク間の継ぎ目(セーブ名前空間・語彙同期・移設後タップ判定)もピン留め済み。
引き継ぎメモ 8 項目は全消化(7 の isNationwide のみ P7 送りの道標付き)。

## P7 以降(別計画)

- **P7: 地球儀モード + ワールドチャレンジ**(設計 §7・§8。正射図法 View、
  地球儀⇄平面切替、47 問抽選と askedInChallenge 消費、裏側ヒント救済、
  `isNationwide` の再定義)
- **P7 冒頭でやること(最終レビュー 2026-08-20 の申し送り)**:
  - `isNationwide` の再定義は罠 2 つを同時に外す — 問題数(167×2)と
    QuizView の地域ズームボタン(`Stage.eastJapanCodes` が県コード直持ち。
    道標は `Atlas.swift` の isNationwide コメント)
  - ワールドチャレンジの棚は leftovers 分岐に流さず `sections` の明示エントリで
    (`Atlas.swift:85-88` に理由)
  - `QuizViewModel.init` の `drawPolicy = .random` 既定引数を外す(drawCard と
    同じ「黙って日本」型。生産呼び出しは明示済み、テストだけ直す)
  - ステージ個別投影(きたヨーロッパ +73%)は地球儀と結合したまま判断する
- **リリース前(P6/P7 のコードには含まない)**:
  - Natural Earth 出典表記(TitleView フッターの TODO。日本の国土地理院表記と並べる)
  - 「せかいの カード」の文言サインオフ(結果画面・ずかんに出る)
  - 実機での発音確認と、必要なら 中国/韓国 の別名フィールド(Task 5 申し送り)
- **P8: オリジナルカード 167 枚**(制作パイプライン + シルバー解放の文言
  「あと◯かいで オリジナルカード!」)
