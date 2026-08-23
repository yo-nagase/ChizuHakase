import Testing

@testable import ChizuHakase

/// P8 Task 2: 「あと◯」の解放予告 — silver 段の名前だけを unlock の名詞に
/// 差し替える。gold・streak・done は unlock があっても不変: 世界の解放は
/// シルバー到達の一度きりで、それより上の段に予告する物が無い。
///
/// TextModeTests ではなく別ファイルなのは並行セッションの都合(同ファイルに
/// 他人の未コミットハンクがあるため)— 検証対象は同じ `TextMode.nextGoalLabel`。
struct NextGoalWordingTests {
    private let kids = TextMode.kids
    private let adult = TextMode.adult

    @Test func シルバー段はunlockの名詞に差し替わる() {
        #expect(kids.nextGoalLabel(.wins(3, to: .silver), unlock: .originalCard)
                == "あと 3かいで オリジナルカード!")
        #expect(adult.nextGoalLabel(.wins(3, to: .silver), unlock: .originalCard)
                == "あと3回でオリジナルカード")
    }

    /// unlock 省略は従来の文そのまま — 既存の呼び出し側(日本の全札)は
    /// 1 文字も変わらない。
    @Test func unlockが無ければ従来どおりシルバー() {
        #expect(kids.nextGoalLabel(.wins(2, to: .silver)) == "あと 2かいで シルバー!")
        #expect(adult.nextGoalLabel(.wins(2, to: .silver)) == "あと2回でシルバー")
    }

    @Test func ゴールド段はunlockがあっても変わらない() {
        #expect(kids.nextGoalLabel(.wins(4, to: .gold), unlock: .originalCard)
                == "あと 4かいで ゴールド!")
        #expect(adult.nextGoalLabel(.wins(4, to: .gold), unlock: .originalCard)
                == "あと4回でゴールド")
    }

    @Test func れんぞくと最上段はunlockがあっても変わらない() {
        #expect(kids.nextGoalLabel(.streak(5), unlock: .originalCard)
                == "あと 5れんぞくで にじいろ!")
        #expect(adult.nextGoalLabel(.streak(5), unlock: .originalCard)
                == "あと5連続でにじいろ")
        #expect(kids.nextGoalLabel(.done, unlock: .originalCard) == "さいこうの カード!")
        #expect(adult.nextGoalLabel(.done, unlock: .originalCard) == "最高のカード")
    }
}
