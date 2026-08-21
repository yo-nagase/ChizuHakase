# P8: オリジナルカード(パイロット + 解放予告)実装計画

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (本セッションでは
> superpowers:subagent-driven-development)でタスク単位に実装する。

**Goal:** 世界アトラスの 2 段目 — オリジナルカード(`{code}-2`)を目録と抽選に
加え、国旗カードの「あと ◯かいで」をシルバー到達 = オリジナル解放の予告に変える。

**Architecture:** 抽選ゲート(`GameRules.DrawPolicy.flagFirstSilverGate`)と
目録契約(国が最初に載せる札 = 国旗)は P5–P7 で実装済み。P8 は (1) 生成器
`build_world_cards.py` に**明示テーブル**でオリジナル札を足し、(2) 文言は
`AtlasNoun` 経由で Atlas がビューに渡す(ビューは分岐しない)。全 167 カ国を
一度に書かず、**ひがしアジア 6 カ国のパイロット**で編集様式を確立してユーザー
サインオフを得る。

**Tech Stack:** Python(生成器)/ Swift 6 + Swift Testing(検証)

---

## 前提(実装者への注意)

- **並行セッションが同じツリーで作業中。** `git add -A` 禁止・pathspec 指定のみ。
  現在の他人の変更(コミット禁止): PrefectureMapView / CardBookView / QuizView /
  TitleView / SaveData / SaveStore / SaveStoreTests / **TextModeTests** /
  WorldQuizUITests / docs/app / docs/styles.css / project.yml ほか。
  TextModeTests.swift に触るタスクは **scratch-index 方式**(GIT_INDEX_FILE +
  `git update-index --cacheinfo`。前例 = P6 の p6t3-commit.sh)で自分のハンクだけ
  コミットし、コミット後に `git status --short` + per-file diff で他人のハンクが
  未コミットのまま残っていることを確認する
- **シミュレータ**: ユーザーの iPhone 15(86FE017B-…)には触れない。
  iPhone 15 Pro(89951824-E383-48B3-BAB0-8D7BD4200E48)+ scratchpad 配下の
  隔離 derivedDataPath を使う。xcodebuild は**フォアグラウンド実行**
  (ターン終了でバックグラウンド子プロセスは死ぬ)
- ユニットスイートは P7 終了時点で 442(共有ツリー)。減らさない

## 編集規範(札の題材と文言 — Task 1 と全バッチに適用)

- **題材**: その国の代表物 1 つ。カテゴリは food / landmark / nature / craft
  (flag は使わない)。政治・軍事・宗教対立・国境に触れない。ステレオタイプの
  揶揄にしない。**実在の事実であること**(覚えようとしている子どもに嘘を
  つかない)。手描きできる具体物であること(この題材がそのまま作画指示になる)
- **id**: `{ISO numeric}-2`(ゼロ埋めなし、国旗 `-1` と同じ流儀)。セーブキー
  なので公開後は変更不可。公開前は題材の書き換え可(日本版 §4 と同じ)
- **emoji**: 題材を表す 1 つ。国旗絵文字(地域指標記号)は使わない
- **nameKana**: ひらがな。**nameKanji**: 大人表記(漢字、無ければカタカナ)
- **description**: ひらがな + 語間スペース、〜だよ / 〜よ調、12〜20 文字程度、
  事実のみ(日本版「つめたい うみで そだつよ」準拠)。国名は言わない
  (札は国のマスに綴じられており、言うと冗長)
- **目録順の契約**: 各国の先頭は必ず国旗札(`CardCatalog` のコメントと
  `flagFirstSilverGate` が依存)。`-2` は `-1` の直後に置く

## 裁定(この計画で確定させる設計未決)

1. **絵より先に題材**: 設計 §5 の「オリジナルは手描きができてから足す」を改める。
   題材(emoji + 名前 + 説明)が作画指示そのものであり、`ART_FOR_CARD` の
   明示対応の流儀(CLAUDE.md §4)は題材が先に確定していることを要求する。
   日本版も絵文字のみで出荷し絵を後からバッチで足した前例に従い、
   **絵文字先行・絵は後続バッチ**とする
2. **図鑑の未解放オリジナル枠は「❓」のまま**(設計 §5 未決の解消)。
   空きマスがすでに「もらえる物がある」ことを語っており(CLAUDE.md §5 の
   未所持札の扱いと同じ理由)、「どうすれば」は国旗札の
   「あと ◯かいで オリジナルカード!」が言う。CardBookView への変更は**ゼロ**
   (並行セッションが同ファイルを編集中でもあり、衝突しない)
3. **予告は嘘をつかない**: `-2` 札がまだ目録に無い国では従来どおり
   「あと ◯かいで シルバー!」のまま。オリジナルを約束できるのは目録に
   2 枚目が実在する国だけ。判定はデータ(`catalog.cards(for:)`)から引く
4. **国旗ライセンス表記は不要**(設計 §5 未決の解消): 国旗は地域指標記号
   (絵文字)で端末フォントが描くため、画像素材が存在しない

---

## Task 1: パイロット 6 カ国のオリジナル札(生成器 + データ + 目録契約テスト)

**Files:**
- Modify: `tools/build_world_cards.py`(ORIGINALS 明示テーブル + `-2` 出力)
- Regenerate: `ChizuHakase/Resources/WorldCards.json`(167 → 173 枚)
- Test: `ChizuHakaseTests/AtlasTests.swift` または `WorldDataTests.swift`
  (どちらもクリーン。世界目録のテストが既にある方に足す)

**Step 1: 失敗するテストを書く。** 世界目録の契約テストを追加:
- 各国の先頭札は id が `-1` で終わり category == .flag
- `-2` 札は category != .flag、id は `{code}-2`、その国の 2 枚目に位置する
- パイロット 6 カ国(156, 158, 392, 408, 410, 496)は 2 枚持つ
- 全札の description はひらがな・カタカナ・スペース・長音のみ(漢字なし)
- **既存の「目録の持ち主は収録国と過不足なく一致する」(AtlasTests)を
  弱めない** — ラップリセットの分母が依存している。`-2` 追加で持ち主集合は
  変わらないので、このテストは無修正で通り続けるはず(通らなければ実装が誤り)

**Step 2: テスト実行 → 新規分が FAIL することを確認**(`-2` 札がまだ無い)

**Step 3: 生成器にテーブルを足す。** `build_world_cards.py` に
`ORIGINALS: dict[int, dict]`(code → emoji/nameKana/nameKanji/category/
description)を**明示的に**書く(ファイル名や属性からの推測をしない —
ART_FOR_CARD と同じ流儀)。出力は各国 `-1` の直後に `-2`。テーブルに無い国は
国旗のみ(従来どおり)。決定性(同じ入力 → 同じバイト列)を保つ。

パイロット題材(編集規範に従う。実装者は事実確認をすること):
| code | 国 | 題材案 | カテゴリ |
| --- | --- | --- | --- |
| 156 | ちゅうごく | 万里の長城(ばんりのちょうじょう) | landmark |
| 158 | たいわん | タピオカミルクティー or 小籠包 | food |
| 392 | にほん | 富士山(ふじさん) | nature |
| 408 | きたちょうせん | 白頭山(はくとうさん)or 冷麺 | nature/food |
| 410 | かんこく | キムチ | food |
| 496 | もんごる | ゲル(移動式の家) | craft |

**Step 4: 生成を実行し JSON を再生成**
```bash
cd tools && python3 build_world_cards.py
```
173 枚(国旗 167 + オリジナル 6)になること、既存 167 枚のバイト列が
不変であることを diff で確認。

**Step 5: テスト実行 → 全 PASS**(既存スイートも減っていないこと)

**Step 6: コミット**(pathspec: `tools/build_world_cards.py`
`ChizuHakase/Resources/WorldCards.json` + テストファイルのみ)

## Task 2: 解放予告 — 「あと ◯かいで オリジナルカード!」

**Files:**
- Modify: `ChizuHakase/Models/TextMode.swift`(AtlasNoun.originalCard +
  `nextGoalLabel` の引数拡張)
- Modify: `ChizuHakase/Models/Atlas.swift`(札 → 解放予告名詞を引く純関数)
- Modify: `ChizuHakase/Features/Result/ResultView.swift`,
  `ChizuHakase/Features/CardBook/CardDetailView.swift`(配線。どちらもクリーン)
- Test: `ChizuHakaseTests/TextModeTests.swift`(**他人のハンクあり —
  scratch-index コミット必須**)+ `AtlasTests.swift`

**Step 1: 失敗するテストを書く。**
- `Atlas`(world): 国旗札(2 枚目が実在する国)→ 解放名詞 = オリジナルカード。
  2 枚目が無い国の国旗札 → nil。`-2` 札自体 → nil。japan の札 → 常に nil
  (drawPolicy .random)
- `TextMode.nextGoalLabel(.wins(n, to: .silver), unlock: .originalCard)`
  → こども「あと ◯かいで オリジナルカード!」/ おとな「あと◯回で
  オリジナルカード」。unlock nil → 従来どおり「シルバー」。
  **gold の段は unlock があっても変えない**(解放はシルバー到達の一度きり)

**Step 2: FAIL 確認**

**Step 3: 実装。**
- `AtlasNoun.originalCard`(kids/adult とも「オリジナルカード」。★仮文言 —
  ユーザーサインオフ待ちに追加)
- `Atlas` にインスタンスメソッド(例 `unlockGoalNoun(for card:) -> AtlasNoun?`):
  drawPolicy が flagFirstSilverGate かつ card がその国の先頭札かつ
  `cards(for:).count > 1` のときだけ名詞を返す。ビューは受け取った名詞を
  そのまま渡すだけで分岐しない(CLAUDE.md 世界設計の不変条件)
- `nextGoalLabel(_ goal:, unlock: AtlasNoun? = nil)`: silver 段の名前だけ
  差し替え。`NextGoal.fraction`(バー)は無変更 — 段の到達点は同じ
- ResultView / CardDetailView の呼び出しに atlas から引いた名詞を配線

**Step 4: 全テスト PASS + iPhone 15 Pro で目視**(世界クイズで国旗を獲得 →
結果画面の獲得カード欄とずかんの拡大表示に予告が出る。日本側が不変なことも見る)

**Step 5: コミット**(TextModeTests は scratch-index。コミット後に他人の
ハンクが未コミットで残ることを確認)

## Task 3: 残り 161 カ国の段取りと記録

**Files:**
- Modify: `docs/plans/2026-08-16-world-atlas-design.md`(§5 未決の解消を追記)
- Modify: この計画書(完了記録・サインオフ待ち・バッチ一覧)

**Step 1:** 設計文書 §5 の未決 2 件(国旗ライセンス / 図鑑の見せ方)に
裁定結果を追記(裁定 2・4 を転記、日付入り)

**Step 2:** 残り 161 カ国の題材バッチ計画を本計画書に綴じる:
大陸ごと(ステージ区分と同じ 0–17)のバッチ、各バッチ = 題材表を編集規範で
起草 → 事実確認レビュー → 生成器テーブル追記 → 再生成 → 目録テスト。
**パイロットのユーザーサインオフ(題材の選び方・文言の調子)を得てから着手**

**Step 3:** コミット(docs のみ、pathspec 指定)

---

## ユーザーサインオフ待ち(仮のまま進めた物)

- 札種の呼称「オリジナルカード」(AtlasNoun.originalCard、★仮 —
  ひらがな表記「おりじなるカード」等の代案もあり得る)
- パイロット 6 題材(とくに 158 台湾・408 北朝鮮は題材選定が編集判断)
- 残り 161 カ国のバッチ着手可否
