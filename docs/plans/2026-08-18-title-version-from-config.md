# タイトルのバージョン表記を project.yml に追従させる

日付: 2026-08-18
状態: **実装済み(2026-08-19)**。project.yml を 1.7 に更新し、タイトルの
v1.7 表示をシミュレータで確認済み。調査時の前提が 1 つ訂正されている:
`ChizuHakase.xcodeproj` は git 管理外の生成物だった(コミット対象は
project.yml のみ)。`CURRENT_PROJECT_VERSION` は 1 のまま — ビルド番号は
同一バージョン内で一意ならよく、1.7 は未アップロードのため。
アップロード時に App Store Connect が衝突を報告したら project.yml で上げる。

## 要望

タイトル画面のバージョン番号(フッターの `v1.0` 表記)を、
**設定ファイル(`project.yml`)のバージョンを反映した値**にしたい。

## 現状調査(2026-08-18 時点)

- 表示側の仕組みは**すでに正しい**。`TitleView.swift:19-20` が
  `CFBundleShortVersionString` をバンドルから読み、`:120` で
  `v\(version)` を表示している。Swift 側の変更は不要の見込み
- 問題は値の供給側。`project.yml:44-45` が
  `MARKETING_VERSION: "1.0"` / `CURRENT_PROJECT_VERSION: "1"` のまま
  置き去りで、`ChizuHakase.xcodeproj/project.pbxproj` も同値(1.0 / 1)。
  そのためビルドしたアプリのタイトルは **v1.0** と出る
- 一方、ストアで公開中の版は **1.7 系**(branch `feature/v1-7`、
  `292801b` "Write the v1.7 What's New for the store")。リリース版数は
  リポジトリ外(アーカイブ時の手動設定と思われる)で付いており、
  リポジトリ内のどこにも 1.7 は無い(xcconfig も無し)

つまり「設定ファイルを直せば画面に出る」構造は既にあり、
**project.yml を版数の単一の真実にして値を現実に合わせる**のがこのタスク。

## 実装手順

1. `project.yml` の `MARKETING_VERSION` を現行リリース(例: `"1.7"`)へ、
   `CURRENT_PROJECT_VERSION` をビルド番号の実態に合わせて更新する。
   **現行の正確な版数・ビルド番号はユーザーに確認する**
   (App Store Connect の値と一致させる必要がある。App ID 6800378835)
2. `xcodegen generate` で `ChizuHakase.xcodeproj` を再生成し、
   pbxproj に反映する(このリポジトリは project.yml → xcodegen 運用。
   再生成の差分が版数以外に及んでいないか `git diff` で確認)
3. シミュレータでビルドし、タイトル画面のフッターが `v1.7` に
   なることを目視確認(起動はそのままタイトルが出る。
   スクショは `xcrun simctl io <UDID> screenshot`)
4. 以後の運用をこの文書か README に一行残す:
   **リリース時の版数バンプは project.yml だけを編集 → xcodegen**。
   Xcode の GUI で直接変えると project.yml と再び乖離する

## 注意

- 並行セッション(Claude / Codex)が同一ツリーで作業している。
  コミットは pathspec 指定(`git commit -- project.yml ChizuHakase.xcodeproj`)、
  index を信用しない(メモリ `parallel-session-git` 参照)
- pbxproj の再生成は Xcode を閉じた状態で行うほうが安全
- `TitleView` は version が nil のとき表記ごと隠すので、
  Info.plist 生成が壊れてもクラッシュはしない(が、消えたら気づくこと)
