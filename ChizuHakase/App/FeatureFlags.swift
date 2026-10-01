/// Build-time switches for features that are still in development.
nonisolated enum FeatureFlags {
    /// レア（まぼろし）カードの獲得と表示。
    /// 本番公開時は Release 側（#else）を true に変更する。
    #if DEBUG
    static let phantomCardsEnabled = true
    #else
    static let phantomCardsEnabled = false
    #endif
}
