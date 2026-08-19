# ワールドマップ機能 実装計画(基盤フェーズ)

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 世界アトラスの基盤(データパイプライン → Swift データ層 → セーブ移行 → デバッグ起動でクイズ疎通)を、日本版を一切壊さずに積む。

**Architecture:** 設計は `2026-08-16-world-atlas-design.md`(§3, §5–8)と
`2026-08-18-world-stages.md`(ステージ表・裁定結果)で確定済み。
世界データは緯度経度で持ち、投影はロード時(§7)。View は Atlas 非依存を保ち、
分岐はデータ(`Atlas`)に閉じ込める(§3)。セーブは v7 でアトラス名前空間化。

**Tech Stack:** Python3(パイプライン、依存追加なし)、mapshaper(npx、日本版と同じ)、Swift 6 / SwiftUI(依存追加なし)

**ブランチ:** `feature/worldmap`(メインツリー。worktree は使わない — ユーザーが本ツリーをこのブランチへ切替済み)

**コミット規律:** 並行セッションがいるため、コミットは必ず pathspec 指定
(`git commit -- <paths>`)。`git add -A` 禁止(メモリ `parallel-session-git`)。

---

## フェーズ構成(各フェーズ末で動く状態)

- **P1 データ**: 収録国マスタ + WorldShapes.json + WorldCards.json(国旗のみ)生成
- **P2 Swift データ層**: Atlas 抽象 + ローダ + 投影。日本版の全テスト緑を維持
- **P3 セーブ**: SaveData v7(アトラス名前空間 + askedInChallenge)移行
- **P4 規則**: 世界版カード抽選(国旗先行・シルバー解放ゲート)
- **P5 疎通**: デバッグ起動引数で世界ステージのクイズが遊べる(シミュレータ確認)
- **P6 以降(別計画)**: タイトル 2 ページ化、世界ステージ選択 UI、地球儀、
  ワールドチャレンジ、なまえをあてる語彙・音声、カード絵コンテンツ

---

### Task 1: 収録国マスタ(config)

**Files:**
- Create: `tools/world_countries.py`

ステージ表(`2026-08-18-world-stages.md`)と裁定結果をコードにする。
Natural Earth の `ISO_N3` を国コード(Int)として使う。

```python
# tools/world_countries.py
# 収録国マスタ。2026-08-18-world-stages.md の表と裁定結果(2026-08-19)が唯一の出典。
# ここを変えたら build_world_map_data.py を再実行する。

# stage index -> (ステージ名かな, ステージ名漢字)
STAGES = [
    ("きた・ちゅうおうアメリカ", "北・中央アメリカ"),   # 0
    ("カリブかい", "カリブ海"),                        # 1
    ("みなみアメリカ", "南アメリカ"),                  # 2
    ("きたヨーロッパ", "北ヨーロッパ"),                # 3
    ("にしヨーロッパ", "西ヨーロッパ"),                # 4
    ("ひがしヨーロッパ", "東ヨーロッパ"),              # 5
    ("みなみヨーロッパ", "南ヨーロッパ"),              # 6
    ("きたアフリカ", "北アフリカ"),                    # 7
    ("にしアフリカ", "西アフリカ"),                    # 8
    ("ちゅうおうアフリカ", "中央アフリカ"),            # 9
    ("ひがしアフリカ", "東アフリカ"),                  # 10
    ("みなみアフリカ", "南アフリカ"),                  # 11
    ("にしアジア", "西アジア"),                        # 12
    ("ちゅうおうアジア", "中央アジア"),                # 13
    ("みなみアジア", "南アジア"),                      # 14
    ("ひがしアジア", "東アジア"),                      # 15
    ("とうなんアジア", "東南アジア"),                  # 16
    ("オセアニア", "オセアニア"),                      # 17
]

# ISO_N3 -> stage index。ここに載っている国だけが「収録」(出題・カード対象)。
# 台湾(158)は裁定により収録。バーレーン・コソボ・パレスチナは載せない(背景描画)。
STAGE_OF_COUNTRY = {
    # きた・ちゅうおうアメリカ: 米・加・墨・グアテマラ・ベリーズ・ホンジュラス・
    # エルサルバドル・ニカラグア・コスタリカ・パナマ
    840: 0, 124: 0, 484: 0, 320: 0, 84: 0, 340: 0, 222: 0, 558: 0, 188: 0, 591: 0,
    # カリブかい: キューバ・ハイチ・ドミニカ共和国・ジャマイカ・バハマ・トリニダード
    192: 1, 332: 1, 214: 1, 388: 1, 44: 1, 780: 1,
    # …(以下、ステージ表の全収録国。実装時に Natural Earth の ISO_N3 で埋める。
    #    総数はステージ表の「収録」列の合計と一致させること)
}

# インセット拡大する国(裁定 2026-08-19): シンガポール・マルタ・モルディブ・フィジー
INSET_COUNTRIES = {702, 470, 462, 242}

# ひらがな表記のオーバーライド(機械変換で不自然になる国だけ書く)。
# 既定は NAME_JA のカタカナ→ひらがな機械変換 + 「〜共和国」等の接尾辞除去。
KANA_OVERRIDES = {
    840: "あめりか",       # アメリカ合衆国 → あめりか
    826: "いぎりす",       # 英国 → いぎりす
    410: "かんこく",       # 大韓民国 → かんこく
    408: "きたちょうせん",  # 朝鮮民主主義人民共和国
    # …実装時に全収録国を目視して追加
}
```

**Step 1:** 上記の骨組みで作成し、`STAGE_OF_COUNTRY` をステージ表どおり全収録国分埋める(Natural Earth の GeoJSON から `NAME`/`ISO_N3` を突き合わせるスクリプトを使ってよい)
**Step 2:** 検証: `python3 -c "import world_countries as w; print(len(w.STAGE_OF_COUNTRY))"` が収録合計(≈170)と一致
**Step 3:** Commit: `git commit -m "世界の収録国マスタを起こす" -- tools/world_countries.py`

---

### Task 2: WorldShapes.json 生成パイプライン

**Files:**
- Create: `tools/build_world_map_data.py`
- Create: `ChizuHakase/Resources/WorldShapes.json`(生成物。コミットする)

日本版 `build_map_data.py` と同じ流儀(取得 → mapshaper 簡略化 → 変換)。

```bash
cd tools
curl -sL -o ne_50m_countries.geojson \
  https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_50m_admin_0_countries.geojson
npx mapshaper ne_50m_countries.geojson -simplify visvalingam 4% keep-shapes -clean \
  -o ne_50m_simplified.geojson format=geojson
python3 build_world_map_data.py
mv WorldShapes.json ../ChizuHakase/Resources/
```

**出力スキーマ(緯度経度のまま。§7 の決定):**

```jsonc
{
  "countries": [
    {
      "code": 840,                    // ISO 3166-1 numeric
      "nameJa": "アメリカ合衆国",       // NAME_JA そのまま(おとな表記)
      "kana": "あめりか",              // KANA_OVERRIDES または機械変換
      "stage": 0,                     // 収録国のみ持つ。背景国は無し
      "rings": [ [[lon,lat], ...], ...],  // 主リング群(遠隔領土は除去済み)
      "centroid": [lon, lat],
      "bbox": [lon0, lat0, lon1, lat1]
    }
  ],
  "background": [ { "rings": [...] } ],   // 属領・収録外国(コード無しの海岸線)
  "insets": [ { "code": 702, "scale": 2.5 } ]
}
```

**実装で守ること(ステージ表の技術ノート):**
- 日付変更線: リングの経度スパンが 180° を超えたら +360 正規化(ロシア東端・フィジー)
- 遠隔領土の除去: 主リング(最大面積)から一定距離を超える離島リングを落とす
  (フランス→仏領ギアナ除去、アメリカ→アラスカ・ハワイは**残す**の例外表を持つ)
- ロシア: 全リングを保持しつつ `europeBbox` を別途出力(枠計算用。§P2)
- 収録外の国・属領は `background` へ(海にしない)

**Step 1:** スクリプト作成 → 実行 → JSON 生成
**Step 2:** 検証スクリプト(次 Task)が通ること
**Step 3:** Commit(pathspec: `tools/build_world_map_data.py`、`ChizuHakase/Resources/WorldShapes.json`)

---

### Task 3: パイプライン出力の検証

**Files:**
- Create: `tools/validate_world_data.py`

```python
# 生成のたびに実行する軽い健全性チェック。落ちたらコミットしない。
import json, world_countries as w
d = json.load(open('../ChizuHakase/Resources/WorldShapes.json'))
recorded = [c for c in d['countries'] if 'stage' in c]
assert len(recorded) == len(w.STAGE_OF_COUNTRY), (len(recorded), len(w.STAGE_OF_COUNTRY))
for c in recorded:
    assert c['rings'] and all(len(r) >= 4 for r in c['rings']), c['code']
    x0, y0, x1, y1 = c['bbox']
    assert x1 - x0 < 360 and x1 - x0 > 0, (c['code'], '日付変更線の正規化漏れ')
codes = {c['code'] for c in recorded}
assert w.INSET_COUNTRIES <= codes, 'インセット対象が収録に無い'
assert 392 in codes, '日本が世界地図にいない'
assert 158 in codes, '台湾の裁定が反映されていない'
assert 48 not in codes, 'バーレーンは収録外の裁定'
print(f'OK: {len(recorded)} countries recorded')
```

**Step 1:** 書く → 実行 → `OK: 17x countries recorded`
**Step 2:** ファイルサイズ確認(目安 400KB 以下 — build_world_map_data.py の
WARNING と同じ値。超えたら黙って簡略化率を上げず、報告して判断を仰ぐ)
**Step 3:** Commit

---

### Task 4: Swift — WorldMapData ローダと投影(TDD)

**Files:**
- Create: `ChizuHakase/Store/WorldDataLoader.swift`
- Create: `ChizuHakase/Models/WorldStage.swift`
- Test: `ChizuHakaseTests/WorldDataTests.swift`

緯度経度 → 平面(等積横メルカトルではなく単純な cos 補正エクイレクタングラー)
への投影は純関数。`PrefectureGeometry` は触らない(flat な rings を食わせる)。

**Step 1: 失敗するテストを書く**

```swift
import Testing
@testable import ChizuHakase

struct WorldDataTests {
    @Test func 全収録国のパスが空でない() throws {
        let world = try WorldDataLoader.load()
        #expect(world.recordedCountries.count >= 165)
        for country in world.recordedCountries {
            #expect(!country.rings.isEmpty, "\(country.code)")
        }
    }
    @Test func 重心が自国に含まれる() throws {
        let world = try WorldDataLoader.load()
        // 島嶼国など凹形状は重心が外れることがある。日本版と同じく
        // 「重心 or bbox 中心のどちらかが contains」で判定
        for country in world.recordedCountries {
            let path = PrefectureGeometry.path(for: country.flatRings)
            #expect(path.contains(country.flatCentroid, eoFill: true)
                 || country.isInset, "\(country.code)")
        }
    }
    @Test func ステージの国数が設計と一致する() throws {
        let world = try WorldDataLoader.load()
        #expect(world.stages.count == 18)
        #expect(world.stages.flatMap(\.codes).count == world.recordedCountries.count)
    }
}
```

**Step 2:** 実行して FAIL を確認(`xcodebuild test -only-testing:ChizuHakaseTests/WorldDataTests`)
**Step 3:** 最小実装(デコード + 投影 + WorldStage 定義)
**Step 4:** テスト緑 + **既存全テストも緑**(日本版回帰ゼロの確認)
**Step 5:** Commit

---

### Task 5: Atlas 抽象と AppState

**Files:**
- Create: `ChizuHakase/Models/Atlas.swift`(mapData + stages + cards + 語彙の束。§3)
- Modify: `ChizuHakase/App/AppState.swift`(japan / world の 2 Atlas を保持。
  既存プロパティは japan への薄い転送にして呼び出し側の変更を最小に)
- Test: `ChizuHakaseTests/AtlasTests.swift`

テスト: japan Atlas が現行データと同一内容を返す(回帰)、world Atlas がロードできる。
**既存テストが全緑のままであることがこの Task の合格条件。**

---

### Task 6: SaveData v7 — アトラス名前空間化

**Files:**
- Modify: `ChizuHakase/Models/SaveData.swift`
- Test: `ChizuHakaseTests/SaveMigrationTests.swift`(既存の移行テスト群に追加)

§3 の決定どおり: `mastery/cards/rainbow/streaks/records` を `atlases["japan"]` へ。
world 側は空で初期化 + `askedInChallenge: [String: Set<Int>]`(モード→国コード。§8)。
`settings` は全体共有のまま。移行方針は v1→v6 と同じ「デコードが常に現行形を返す」。

テスト(最低限):
- v6 の実ファイル断片をデコード → japan 名前空間に全値が移り、値が不変
- v7 を書いて読み直すと同一
- 未来バージョン(v99)は番号を下げず内容を触らない(既存規則の踏襲)

---

### Task 7: GameRules — 世界版カード抽選(国旗先行・シルバー解放ゲート)

**Files:**
- Modify: `ChizuHakase/Models/GameRules.swift`(抽選関数に `drawOrder` 方針を追加。
  view には出さない。§5「規則の差分」)
- Test: `ChizuHakaseTests/GameRulesTests.swift` に追加

```swift
@Test func 世界版は国旗が先でシルバーまでオリジナルが出ない() {
    // 所持なし → {code}-1(国旗)
    // 国旗★4 → まだ国旗に星が付く(オリジナルは抽選対象外)
    // 国旗★5 → 次の正解で {code}-2(オリジナル)★1
    // 両方所持 → ★10 未満からランダム(日本版と同じ)
}
@Test func 日本版の抽選は従来どおり() { /* 既存挙動の回帰 */ }
```

---

### Task 8: WorldCards.json(国旗カードのみ)と疎通

**Files:**
- Create: `tools/build_world_cards.py`(収録国 → `{code}-1` 国旗カード。
  emoji は ISO alpha-2 由来の国旗絵文字。ライセンス問題なし)
- Create: `ChizuHakase/Resources/WorldCards.json`(生成物)
- Modify: `ChizuHakase/Features/Title/RootView.swift`(デバッグ起動引数
  `-atlas world` + `-startAt quiz:N` で世界ステージの findOnMap を起動)

**合格条件(P5 完了):** シミュレータで
`xcrun simctl launch <SIM> com.wakuwaku.chizuhakase -atlas world -startAt quiz:15`
が「ひがしアジア」ステージのクイズとして遊べる(にほんをタップして正解できる)。
スクリーンショットで確認し、既存 UI テストも全緑。

---

## この計画に含めないもの(P6 の別計画で)

タイトルの 2 ページ化(にほん/せかいの ちずちょう)、世界ステージ選択 UI
(19 枚看板 + 大陸グループ化)、地球儀モード、ワールドチャレンジ、
なまえをあてる 4 択・音声語彙、オリジナルカード(手描き 170 枚)の制作と組み込み、
国名ひらがなの編集校閲。基盤が緑になった時点で計画を継ぎ足す。
