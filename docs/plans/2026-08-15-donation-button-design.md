# 設定画面の「寄付(応援)」ボタン — 規約確認と実装計画

日付: 2026-08-15
状態: **計画のみ(未実装)**。CLAUDE.md §1「課金なし」は絶対制約であり、
これを変更するのはオーナーの判断。実装着手前にこの文書の承認を得ること。

---

## 1. 結論: 条件付きで可能

Kids カテゴリのまま寄付ボタンを置くことは **App Store 規約上可能**。
ただし次の 3 条件をすべて満たす形に限る。

| # | 条件 | 根拠 |
| --- | --- | --- |
| 1 | **App 内課金(IAP)として実装する。** PayPal / Ko-fi / Stripe 等への外部リンクは不可 | Guideline 3.1.1: 開発者への「チップ」は IAP を使うと明記 |
| 2 | **ペアレンタルゲートの内側に置く** | Guideline 1.3: Kids カテゴリは「購入機会・外部リンク」をゲートの内側の専用領域に限る |
| 3 | **「慈善寄付」と呼ばない。**「開発者への応援(チップ)」として設計する | Guideline 3.2.2(vi): アプリ内で寄付金を集められるのは承認済み非営利団体のみ。それ以外は「アプリ外(Safari/SMS)でのみ」収集可 |

つまり日本語 UI では **「寄付」ではなく「開発を応援する」** という語を使う。
慈善・チャリティの体裁を取った瞬間に 3.2.2(vi) に抵触する。
承認済み非営利団体でない個人開発者が集められるのは「チップ」だけであり、
チップは IAP 必須・Kids ではゲート必須、という構造。

### 規約原文(2026-08 時点で確認)

- **1.3 Kids Category**: "These apps must not include links out of the app,
  purchasing opportunities, or other distractions to kids **unless reserved
  for a designated area behind a parental gate**."
- **3.1.1 In-App Purchase**: "Apps may use in-app purchase currencies to
  enable customers to **'tip' the developer** or digital content providers
  in the app."
- **3.2.2(vi) Unacceptable**: "Unless you are an approved nonprofit …
  collecting funds within the app for charities and fundraisers. Apps that
  seek to raise money for such causes must be free on the App Store and may
  only collect funds outside of the app, such as via Safari or SMS."

### 補足: 外部決済リンクについて

スマホソフトウェア競争促進法(2025-12 施行)により日本ストアフロントでは
外部決済への導線が制度上開きつつあるが、
①Kids カテゴリのゲート要件はそのまま、②本アプリの「アプリ外リンクを作らない」
原則(CLAUDE.md §1)に反する、③決済・税務の自前対応が増える、の 3 点から
**採用しない**。IAP 一択。

---

## 2. 設計方針

### 全体像

```
設定画面(⚙️)
└─ 「おうちの かたへ」セクション(漢字表記・大人向けトーン)
   └─ 「開発を応援する」ボタン
      └─ ペアレンタルゲート(掛け算 2 問など、大人向け漢字文)
         └─ 応援画面(SupportView)
            ├─ 説明: 機能は全部無料のまま。応援しても何も増えません
            ├─ チップ 3 段(例: ¥160 / ¥480 / ¥1,200 — 消耗型 IAP)
            └─ 購入後: ありがとう表示(その場限り。バッジ等の見返りなし)
```

### 守ること

- **子どもの動線に一切出さない。** タイトル・クイズ・結果・ずかんに導線を
  置かない。設定画面の大人向けセクションのみ。文言は漢字主体にして
  「子ども向けに書かれていない」ことを審査者にも子どもにも伝える
- **見返りを付けない。** チップで機能・カード・演出が増えると
  「課金で有利」になり §1 の思想が壊れる。買っても何も起きないのが正しい。
  ゆえに消耗型(consumable)・リストアボタン不要
- **ペアレンタルゲート**は Apple の推奨パターン(大人向けの文章指示+
  計算問題)。3 回失敗で静かに閉じる。ゲート自体を `Components/` に置き、
  将来の外部リンク(もし作るなら)と共用できる形にする
- **オフライン時は静かに無効化。** ボタンは出すが押すと「インターネットに
  つないでください」。完全オフラインアプリの唯一の通信機能になることを
  CLAUDE.md に明記する(通信相手は Apple の StoreKit のみ)
- **プライバシーラベルは「データを収集しません」を維持できる。**
  決済は Apple が処理し、アプリ側は購入履歴を保存も送信もしない
  (サーバーを持たない)。サードパーティ SDK は増えない

### 文言案

| 場所 | 文言 |
| --- | --- |
| 設定内ボタン | 「開発を応援する」(漢字。ふりがな無し) |
| ゲート | 「保護者の方に確認します。次の計算に答えてください」 |
| 応援画面の説明 | 「このアプリはすべての機能を無料で提供しています。応援していただいても、機能やカードが増えることはありません。いただいた応援は今後の開発に使わせていただきます」 |
| 購入後 | 「ありがとうございます! 開発の励みになります」 |

---

## 3. 実装ステップ(コード側)

動く状態で区切る。§10 の流儀に合わせて各フェーズ後にテストを通す。

1. **ParentalGate コンポーネント** — `Components/ParentalGate.swift`。
   純粋関数(問題生成・判定)を切り出してユニットテスト。
   Reduce Motion / VoiceOver 対応(§9)
2. **TipStore(StoreKit 2)** — `Services/TipStore.swift`。`@Observable`。
   `Product.products(for:)` で 3 商品を取得、`purchase()`、
   `Transaction.finish()`。ネットワーク不可・商品取得失敗は
   「今はつながりません」表示に握る(クラッシュ・リトライループ禁止)。
   ロジックは `.storekit` 構成ファイルでローカルテスト
3. **SupportView** — `Features/Settings/` 配下。設定画面に
   「おうちの かたへ」セクションを追加し、ゲート → SupportView をシートで
4. **UI テスト** — ゲートを通らないと購入画面に到達できないこと、
   誤答で開かないことを検証
5. **文書更新** — CLAUDE.md: §1(制約の但し書き)、§8(課金セクションの
   全面書き換え: 「収益より優先」の思想は残したまま、ゲート内チップのみ
   例外とする)、README の「全機能無料」表現の調整

## 4. App Store Connect 側の作業(オーナーのみ実施可能)

1. **Paid Applications 契約**への署名 + 銀行口座・税務情報(W-8BEN 等)の登録
   — これが無いと IAP はテストすら動かない
2. IAP 商品 3 つを作成(消耗型、価格 Tier 選択、審査用スクリーンショット)
3. ストア掲載情報の更新:
   - 「App 内課金あり」バッジが自動で付く
   - `design/app-store/metadata.md` の「App 内課金 | なし」
     「アプリ内課金はありません」→「開発者への応援(任意)のみ。
     機能はすべて無料です」に差し替え
4. 審査ノートに「チップはペアレンタルゲート内・機能への影響なし」と明記

## 5. リスクと代替案

- **審査リスク: 中。** Kids カテゴリの購入機能は人間の審査官が厳しめに見る。
  ゲートの強度不足(単純タップ・ホールドのみ等)での差し戻しが典型。
  計算問題+漢字文で回避する
- **手数料**: Apple が 30%(Small Business Program 申請済みなら 15%)
- **コスト対効果**: 契約・税務・審査対応という固定コストが乗る。
  額が見込めないなら、**アプリには手を入れず GitHub の Sponsor /
  ストア外のウェブページで受ける**のが最小コスト案(アプリは今のまま、
  規約リスクもゼロ)。ストアページの説明文やサポート URL からの導線は
  アプリ外なので Kids 制約の対象外

## 参考

- [App Review Guidelines(Apple)](https://developer.apple.com/app-store/review/guidelines/)
- [Kids カテゴリのアップデートについて(Apple Developer News)](https://developer.apple.com/news/?id=091202019a)
