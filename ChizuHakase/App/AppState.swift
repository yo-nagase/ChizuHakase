import Foundation
import Observation

/// Root state: the loaded resources and the save store.
/// Created once at launch and passed down through the environment.
@Observable
final class AppState {
    /// 日本アトラス。従来どおり起動時に読む — タイトルの直後に必ず使う。
    let japan: Atlas
    /// 世界アトラス。初アクセスまで読まない: まだどの画面からも到達できず
    /// (Route の分岐は後続タスク)、WorldShapes.json は日本の 2 倍強を
    /// デコード + 投影するので、日本だけ遊ぶ子の起動に載せる理由がない。
    /// 読み込み失敗は `Atlas.loadWorld` が空アトラスへ倒す(クラッシュしない)。
    /// 不変データなので観測は不要(@ObservationIgnored は lazy の要件でもある)。
    @ObservationIgnored private(set) lazy var world: Atlas = .loadWorld()
    let save: SaveStore
    let voice: VoiceInputService
    /// The title theme. Owned here so returning to the title finds the same
    /// player it left, not a second one layered under the first.
    let music = MusicService()

    init(mapData: MapData? = nil,
         cards: CardCatalog? = nil,
         save: SaveStore? = nil,
         voice: VoiceInputService? = nil) {
        self.japan = .japan(mapData: mapData ?? MapDataLoader.loadMapData(),
                            cards: cards ?? MapDataLoader.loadCards())
        self.save = save ?? SaveStore()
        self.voice = voice ?? VoiceInputService()
        self.voice.configure(vocabulary: japan.voiceVocabulary)
    }

    // 既存の呼び出し側はすべて日本アトラスを見る。アトラスの選択を画面へ
    // 通すのは後続タスクで、ここは薄い転送に留めて呼び出し側を変えない。
    var mapData: MapData { japan.mapData }
    var cards: CardCatalog { japan.cards }
    var stages: [Stage] { japan.stages }

    /// True only when the device can recognise Japanese on-device *and* the
    /// child's guardian has turned the mode on. Anything less and the feature
    /// stays hidden rather than half-present (CLAUDE.md §7).
    var isVoiceModeAvailable: Bool {
        save.data.settings.voiceInputEnabled
            && voice.isPossibleOnThisDevice
            && voice.availability == .available
    }

    var canOfferVoiceMode: Bool { voice.isPossibleOnThisDevice }
}
