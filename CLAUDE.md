# わくわく ちずクイズ (wakuwaku-chizu)

子ども向けの都道府県学習アプリ。日本地図をタップして県を当てるクイズを軸に、
「全国マイマップ」と「とくさんひんカード」で継続動機をつくる。

---

## 1. プロダクト前提

| 項目 | 内容 |
| --- | --- |
| プラットフォーム | iOS 17.0+ / iPadOS 17.0+ |
| 言語・UI | Swift 6, SwiftUI |
| 主対象 | 5〜9歳(ひらがなが読めるかどうか怪しい層を含む) |
| 課金 | 買い切り 1 本(StoreKit 2)。広告なし |
| 通信 | **なし**。完全オフライン動作 |
| 表示言語 | 日本語のみ(UI文言はすべてひらがな中心) |

### 絶対に守る制約

これらは App Store Kids カテゴリ(Guideline 1.3 / 5.1.4)への適合条件であり、
実装判断で覆さないこと。迷ったら実装せずに確認を求める。

- **広告 SDK を入れない。** AdMob 等の依存を追加しない
- **サードパーティ分析 SDK を入れない。** Firebase Analytics, Amplitude 等すべて不可
- **IDFA / AdSupport.framework を参照しない。** `ASIdentifierManager` を binary に含めない
- **端末外へデータを送信しない。** ユーザー生成データはすべてローカル保存
- **アプリ外リンク・購入導線はペアレンタルゲートの内側**に置く
- プライバシーラベルは「データを収集しません」を維持する

### やらないこと (Non-goals)

- アカウント登録・ログイン・クラウド同期
- ランキング・他ユーザーとの比較・SNS 共有
- 連続ログイン日数(ストリーク)とその喪失演出
- ライフ/ハート制、全問共通の制限時間
- ガチャ課金、消費型アイテム

---

## 2. ディレクトリ構成

```
wakuwaku-chizu/
├── CLAUDE.md
├── tools/
│   └── build_map_data.py          # GeoJSON → PrefectureShapes.json
├── WakuwakuChizu/
│   ├── App/
│   │   ├── WakuwakuChizuApp.swift
│   │   └── AppState.swift          # @Observable ルート状態
│   ├── Models/
│   │   ├── Prefecture.swift        # 県マスタ(形状 + メタ)
│   │   ├── SpecialtyCard.swift     # カードマスタ
│   │   ├── Stage.swift             # 地方ステージ定義
│   │   └── SaveData.swift          # セーブ用 Codable
│   ├── Store/
│   │   ├── SaveStore.swift         # 読み書き + マイグレーション
│   │   ├── MapDataLoader.swift     # JSON → [Prefecture]
│   │   └── PurchaseStore.swift     # StoreKit 2
│   ├── Features/
│   │   ├── Title/
│   │   ├── StageSelect/
│   │   ├── Quiz/                   # QuizViewModel, QuizView, MapView
│   │   ├── Result/
│   │   ├── MyMap/
│   │   └── CardBook/
│   ├── Components/
│   │   ├── PrefectureMapView.swift # 地図描画 + タップ判定(再利用)
│   │   ├── CardChipView.swift
│   │   ├── BouncyButton.swift
│   │   └── ParentalGateView.swift
│   ├── Services/
│   │   ├── SpeechService.swift     # 読み上げ
│   │   ├── VoiceInputService.swift # 音声入力
│   │   └── SoundService.swift      # 効果音
│   └── Resources/
│       ├── PrefectureShapes.json   # 生成物(コミットする)
│       ├── SpecialtyCards.json     # 生成物(コミットする)
│       └── Assets.xcassets
└── WakuwakuChizuTests/
```

---

## 3. 地図データ

### 生成パイプライン

`Resources/PrefectureShapes.json` は生成物だが **リポジトリにコミットする**
(ビルド時に再生成しない)。更新が必要なときだけ以下を実行する。

```bash
cd tools
curl -sL -o japan.geojson \
  https://raw.githubusercontent.com/dataofjapan/land/master/japan.geojson
npx mapshaper japan.geojson \
  -simplify visvalingam 5% keep-shapes -clean \
  -o japan_simplified.geojson format=geojson
python3 build_map_data.py
mv PrefectureShapes.json ../WakuwakuChizu/Resources/
```

出典表記が必要。タイトル画面フッターに以下を残すこと。

> ちずデータ: Global Map Japan (国土地理院) をもとに簡略化

### JSON スキーマ

```jsonc
{
  "mapWidth": 1000.0,
  "mapHeight": 997.9,
  "okinawaInset": [0.0, 832.5, 56.7, 915.9],  // 沖縄インセットの枠 [x0,y0,x1,y1]
  "prefectures": [
    {
      "code": 1,                      // 全国地方公共団体コードの都道府県部分 (1-47)
      "name": "北海道",
      "kana": "ほっかいどう",
      "bbox": [x0, y0, x1, y1],
      "centroid": [cx, cy],           // ラベル/エフェクトの表示位置
      "rings": [ [[x,y], ...], ... ]  // 先頭が外周、以降は穴
    }
  ]
}
```

座標系は **左上原点・y 下向き**(SwiftUI と同じ)、幅 1000 に正規化済み。
全 47 県 4,087 点、約 62 KB。

### 描画とタップ判定

```swift
// rings → Path
func makePath(rings: [[CGPoint]], transform: CGAffineTransform) -> Path {
    var path = Path()
    for ring in rings {
        guard let first = ring.first else { continue }
        path.move(to: first.applying(transform))
        for point in ring.dropFirst() { path.addLine(to: point.applying(transform)) }
        path.closeSubpath()
    }
    return path
}
```

- 穴(湖など)があるため塗りは **even-odd**。`path.fill(color, style: FillStyle(eoFill: true))`
- ヒットテストも `path.contains(point, eoFill: true)`
- 表示範囲はステージごとに可変。`bbox` の和集合に 9% + 8pt のパディングを足して
  `GeometryReader` のサイズへ **等比(aspect fit)** で収める。潰さないこと
- **タップ許容**: 直接ヒットが無い場合、対象県の重心から一定距離内なら正解扱いにする。
  香川・大阪・沖縄など小さい県を子どもが指でタップできないと成立しない。
  スクリーン座標で 22pt 以内を目安に調整すること
- 沖縄は九州西方へ 1.6 倍に拡大して移動済み。`okinawaInset` の枠を破線で描き、
  「別枠である」ことを視覚的に示す

---

## 4. カードデータ

`Resources/SpecialtyCards.json`。47 県 × 3 枚 = **141 枚**。
生成手順は別途 Codex 用プロンプトを参照(このリポジトリでは生成物のみ管理)。

```jsonc
{
  "cards": [
    {
      "id": "01-1",              // "{県コード2桁}-{連番}"
      "prefectureCode": 1,
      "emoji": "🦀",
      "nameKana": "かに",
      "nameKanji": "蟹",
      "category": "food",        // food | landmark | nature | craft
      "description": "つめたい うみで そだつよ"
    }
  ]
}
```

起動時に読み込み、`prefectureCode` で辞書化する。
`id` はセーブデータのキーになるので **一度公開したら変更しない**。

---

## 5. ゲームロジック

### ステージ

| # | 名前 | 県コード | 無料 |
| --- | --- | --- | --- |
| 0 | ほっかいどう・とうほく | 1–7 | ○ |
| 1 | かんとう | 8–14 | ○ |
| 2 | ちゅうぶ | 15–23 | 課金 |
| 3 | きんき | 24–30 | 課金 |
| 4 | ちゅうごく・しこく | 31–39 | 課金 |
| 5 | きゅうしゅう・おきなわ | 40–47 | 課金 |
| 6 | ぜんこく チャレンジ | 1–47 | 課金 |

### 1 問の流れ

1. 出題順はステージ内でシャッフル
2. 問題文は **ひらがな**を主・漢字を副で表示。🔊 ボタンで読み上げ
3. 未回答かつステージ内の県のみタップ可能
4. **正解**: 県が pop(1.0 → 1.22 → 0.95 → 1.0 / 0.55s)して着色、
   特産品絵文字が浮上、カードを 1 枚獲得、1.15s 後に次の問題へ
5. **不正解**: 誤タップした県が横に振動(0.45s)、コンボ 0、ミス記録
6. **2 回間違えた**時点で正解県の輪郭を赤で点滅(0.9s ループ)させる

### スコア

- 1 回目で正解: `100 + (コンボ − 1) × 20`
- 2 回目以降で正解: `50`
- コンボは 1 回目正解でのみ加算、不正解でリセット

### 星評価(ステージ単位)

ミスした **県の数**(誤タップ回数ではない)で決める。

- 0 → ★★★
- `ceil(問題数 / 4)` 以下 → ★★
- それ以外 → ★

### 習熟レベル(全国マイマップ)

県ごとに 0–3。**1 回目で正解したときだけ +1**、上限 3。
**間違えても減らさない。** 子どもから積み上げを奪わないための設計判断であり、
「復習のために減衰させる」提案は採用しない。

| Lv | 表示 |
| --- | --- |
| 0 | グレー `#E7ECEF` |
| 1 | 県色 33% 透過 |
| 2 | 県色 73% 透過 |
| 3 | 県色ベタ + 金枠 `#FFC53D` + ゆっくり明滅 |

Lv3 到達時は結果画面で「✨ キラキラに なった けん!」として個別に祝う。

### カード獲得

正解するたびに、その県のカードを 1 枚獲得する。

```
未所持のカードがあれば、その中からランダムに 1 枚
すべて所持済みならランダムに 1 枚 → 「キラカード」に昇格(所持数 2 で打ち止め)
```

未所持を優先することでコレクションが早く埋まり、
埋まった後はキラ狙いでクリア済みステージを再プレイする動機が残る。

---

## 6. セーブデータ

`FileManager` の Application Support に JSON で保存。SwiftData は使わない
(構造が単純で、マイグレーションを自前で握れるほうが安全)。

```swift
struct SaveData: Codable {
    var version: Int = 1
    var mastery: [Int: Int] = [:]        // 県コード → 0...3
    var cards: [String: Int] = [:]       // カードID → 所持数 (0...2)
    var stages: [Int: StageRecord] = [:] // ステージ# → ベスト記録
    var settings: Settings = .init()
}

struct StageRecord: Codable { var stars: Int; var score: Int }
struct Settings: Codable {
    var soundEnabled = true
    var speechEnabled = true
    var voiceInputEnabled = false
}
```

- 書き込みは **ステージ終了時のみ**。1 問ごとに書かない
- 保存は atomic write。読み込み失敗時は初期値にフォールバックしてクラッシュさせない
- `version` を見て将来のマイグレーションを分岐する
- 記録の全削除はマイマップ画面から。必ず 2 段階確認を挟む

---

## 7. 音声

### 読み上げ (`SpeechService`)

`AVSpeechSynthesizer`。オンデバイスで完結し課金対象外。

```swift
let utterance = AVSpeechUtterance(string: "とうきょうとは、どこかな?")
utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP")
utterance.rate = 0.42   // 既定より遅め。子どもは既定速度だと聞き取れない
```

読み上げは **無料機能**。課金や広告の後ろに置かない。ひらがなが読めない層にとって
これが無いとアプリが成立しないため。

### 音声入力 (`VoiceInputService`)

`SFSpeechRecognizer` を **オンデバイス限定**で使う。

```swift
request.requiresOnDeviceRecognition = true   // 必須。音声を外部送信しない
request.contextualStrings = allPrefectureKanaNames  // 47 語の固定語彙
```

- 「こえで こたえるモード」として地図タップと並列の選択肢にする
- 判定は正規化した読みの一致 + 表記ゆれ吸収
  (「とうきょう」「とうきょうと」「東京」をすべて可)
- マイク権限が拒否された場合は静かにタップモードへフォールバック。
  権限を再要求してループさせない
- **オンデバイス認識が使えない端末では機能自体を隠す**

---

## 8. 課金 (StoreKit 2)

- Non-Consumable 1 種のみ: `com.wakuwaku.chizu.full`(¥490 想定)
- 解放内容: 全ステージ + 全 141 枚のカード + 今後追加される世界編
- 購入・復元ボタンは必ず **ペアレンタルゲート**の内側
- ゲートは掛け算(例: 「7 × 8 は?」を数字キーパッドで入力)。
  読み上げ対象にしない。失敗しても子どもを責める文言を出さない
- `Transaction.currentEntitlements` を起動時とフォアグラウンド復帰時に検証
- 未購入時の導線は結果画面と ステージ選択の 2 か所まで。連打で出さない

---

## 9. デザイン

### トークン

```swift
enum Palette {
    static let background = Color(hex: 0xFFF7E8)
    static let ink        = Color(hex: 0x3D3A4B)
    static let orange     = Color(hex: 0xFF9F1C)   // 主 CTA
    static let teal       = Color(hex: 0x2EC4B6)   // 副次アクション
    static let red        = Color(hex: 0xFF5D5D)   // 正解演出・ヒント
    static let gold       = Color(hex: 0xFFC53D)   // キラキラ / キラカード
    static let sea        = [Color(hex: 0xCDEFFB), Color(hex: 0xA9DFF2)]
}
```

県の塗り分けは 8 色パレットを `県コード % 8` で循環させる。
`#FF8A80 #FFCC80 #FFF176 #A5D6A7 #81D4FA #CE93D8 #F48FB1 #80CBC4`

### 書体・形状

- 丸ゴシック(ヒラギノ丸ゴ ProN)。UI 文言は基本 Bold 以上
- ボタンは角丸 999(ピル型)+ 下方向のソリッドシャドウ。押下で 3–4pt 沈む
- カード・パネルは角丸 18–24

### アクセシビリティ

- `@Environment(\.accessibilityReduceMotion)` を尊重。true のときは
  pop / 振動 / 紙吹雪 / 明滅をすべて無効化し、状態変化は色のみで表現する
- 各県の `Path` に `.accessibilityLabel(県名)` を付ける
- タップターゲットは実質 44pt 以上を確保(§3 のタップ許容で担保)
- Dynamic Type は問題文と結果画面で追従させる。地図内ラベルは固定でよい

---

## 10. 実装順序

各フェーズが動く状態で区切ること。まとめて書かない。

1. **データ層** — `MapDataLoader` + `SaveStore` + ユニットテスト。
   47 県すべての `Path` が空でないこと、`contains` が重心で true を返すことを検証
2. **地図コンポーネント** — `PrefectureMapView` 単体。
   Preview でステージ切り替えとタップ判定を確認
3. **クイズ 1 ステージ** — 出題・正誤・スコア・コンボ・ヒント
4. **結果 + セーブ** — 星評価、習熟レベル、カード獲得、永続化
5. **マイマップ / ずかん**
6. **読み上げ・効果音**
7. **課金 + ペアレンタルゲート**
8. **音声入力モード**
9. 仕上げ(Reduce Motion、アイコン、スクリーンショット)

---

## 11. コーディング規約

- 状態は `@Observable`(Observation フレームワーク)。`ObservableObject` は使わない
- View に業務ロジックを書かない。判定・スコア計算は ViewModel か純関数へ
- スコア・星・習熟・カード抽選は **純粋関数**として切り出し、テストを書く
- `print` デバッグを残さない。必要なら `OSLog`
- 強制アンラップ `!` と `try!` を使わない。データ読み込み失敗は握って初期状態へ
- マジックナンバーは §5 の定数として `GameRules` にまとめる
- コメントは「なぜそうしたか」を書く。「何をしているか」はコードで示す

## 12. 迷ったら

- **子どもが不安になる方向には倒さない。** 失うもの・急かすもの・叱るものは作らない
- 仕様に無い機能を推測で追加しない。特に §1 の制約に触れる依存追加は必ず確認する
- 文言に迷ったら短く・ひらがなで・肯定形で
