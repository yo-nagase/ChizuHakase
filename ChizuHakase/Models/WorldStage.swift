import Foundation

/// 世界版の地方ステージ。日本版の `Stage` と同じく `index` がセーブキーなので、
/// 並びは固定(変えると既存の記録が別ステージに付く)。
///
/// `codes` は WorldShapes.json の各国が持つ stage 番号から組み立てる
/// (`WorldDataLoader`)。名前だけは JSON に入っていないので、ここに写しを持つ。
nonisolated struct WorldStage: Identifiable, Sendable, Equatable {
    let index: Int
    /// よみ(こども表記)。
    let name: String
    /// ふつうの書きかた(おとな表記)。
    let kanjiName: String
    /// ISO 3166-1 numeric。ステージ内はコード昇順(出題順とは無関係)。
    let codes: [Int]

    var id: Int { index }

    /// ステージ名の正本は tools/world_countries.py の STAGES。
    /// パイプラインとここの二重管理になるが、JSON に名前を運ばせると
    /// 「データの語彙」と「表示の語彙」が同じファイルで混ざるので、
    /// 日本版 `Stage.all` と同じくアプリ側に定数で持つ。
    /// 変更するときは必ず両方を同時に触ること。
    static let names: [(name: String, kanjiName: String)] = [
        ("きた・ちゅうおうアメリカ", "北・中央アメリカ"),   // 0
        ("カリブかい", "カリブ海"),                        // 1
        ("みなみアメリカ", "南アメリカ"),                  // 2
        ("きたヨーロッパ", "北ヨーロッパ"),                // 3
        ("にしヨーロッパ", "西ヨーロッパ"),                // 4
        ("ひがしヨーロッパ", "東ヨーロッパ"),              // 5
        ("みなみヨーロッパ", "南ヨーロッパ"),              // 6
        ("きたアフリカ", "北アフリカ"),                    // 7
        ("にしアフリカ", "西アフリカ"),                    // 8
        ("ちゅうおうアフリカ", "中央アフリカ"),            // 9
        ("ひがしアフリカ", "東アフリカ"),                  // 10
        ("みなみアフリカ", "南アフリカ"),                  // 11
        ("にしアジア", "西アジア"),                        // 12
        ("ちゅうおうアジア", "中央アジア"),                // 13
        ("みなみアジア", "南アジア"),                      // 14
        ("ひがしアジア", "東アジア"),                      // 15
        ("とうなんアジア", "東南アジア"),                  // 16
        ("オセアニア", "オセアニア"),                      // 17
    ]

    /// 総合ステージ「せかい チャレンジ」(ワールドチャレンジ、設計 §8)。
    /// JSON の stage 番号は 0–17 の地方ステージしか知らないので、19 面目は
    /// `Atlas.world(from:)` が全収録国を束ねて組み立てる — 名前と index の
    /// 正本だけをここに置く(`names` と同じ「表示の語彙はアプリ側」の判断)。
    /// index はセーブキー(records[mode][18])なので固定。
    /// ★文言は仮 — 「ぜんこく チャレンジ」と同型の名乗りだが、ユーザーの
    /// サインオフ待ち(docs/plans/2026-08-20-world-globe-challenge-plan.md)。
    static let challengeIndex = 18
    static let challengeName = "せかい チャレンジ"
    static let challengeKanjiName = "世界チャレンジ"

    /// 世界編 18 地方 + 世界チャレンジの看板スタンプ。`names` と同じく
    /// stage index 順で、19 面目だけはチャレンジの値。地域の意味は View の
    /// `% count` から推測せず、Atlas がこの値をそのまま運ぶ(Issue #10)。
    static let landmarkAssetNames = [
        "stage-icon-world-north-central-america", // 0 オオカバマダラ
        "stage-icon-world-caribbean",             // 1 ヤシの木と波
        "stage-icon-world-south-america",         // 2 リャマ
        "stage-icon-world-north-europe",          // 3 オーロラ
        "stage-icon-world-west-europe",           // 4 木組みの家
        "stage-icon-world-east-europe",           // 5 コウノトリ
        "stage-icon-world-south-europe",          // 6 オリーブ
        "stage-icon-world-north-africa",          // 7 オアシス
        "stage-icon-world-west-africa",           // 8 バオバブ
        "stage-icon-world-central-africa",        // 9 オカピ
        "stage-icon-world-east-africa",           // 10 アカシアとキリン
        "stage-icon-world-south-africa",          // 11 ゲムズボック
        "stage-icon-world-west-asia",             // 12 アラビアオリックス
        "stage-icon-world-central-asia",          // 13 ユルト
        "stage-icon-world-south-asia",            // 14 インドゾウ
        "stage-icon-world-east-asia",             // 15 タンチョウ
        "stage-icon-world-southeast-asia",        // 16 サイチョウ
        "stage-icon-world-oceania",               // 17 アウトリガーカヌー
        "stage-icon-world-challenge",             // 18 全大陸の地球儀
    ]

    /// ステージ選択の棚を区切る大陸見出し(UI 決定 2026-08-20 —
    /// docs/plans/2026-08-18-world-stages.md「ステージ選択 UI」)。
    /// 上の `names` はすでに大陸ごとに連続して並んでいるので、見出しは
    /// index 区間から機械的に引ける。`names` の並びを変えるなら
    /// (index はセーブキーなので変えないが)ここも必ず一緒に動かすこと。
    ///
    /// 総合ステージは専用の区間で立てる: `Atlas.stageShelves` の「余り」枝は
    /// データ食い違いの診断用で、正規のステージを日常的に流すと検出器で
    /// なくなる(Atlas.swift の規律)。★見出し「そうごう」も仮文言
    /// (サインオフ待ち。1 語・ひらがな)。
    static let sections: [AtlasSection] = [
        AtlasSection(title: "アメリカ", stageIndexes: 0..<3),
        AtlasSection(title: "ヨーロッパ", stageIndexes: 3..<7),
        AtlasSection(title: "アフリカ", stageIndexes: 7..<12),
        AtlasSection(title: "アジア", stageIndexes: 12..<17),
        AtlasSection(title: "オセアニア", stageIndexes: 17..<18),
        AtlasSection(title: "そうごう",
                     stageIndexes: challengeIndex..<(challengeIndex + 1)),
    ]
}
