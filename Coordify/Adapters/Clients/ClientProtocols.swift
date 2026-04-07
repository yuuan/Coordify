import AppKit

/// yabai との通信を抽象化するインターフェース
protocol YabaiClientProtocol {
    /// yabai が利用可能かどうか
    var isAvailable: Bool { get }

    /// 全スペースの情報を問い合わせる
    /// - Returns: yabai から取得したスペース情報の配列
    func querySpaces() async throws -> [YabaiSpaceResponse]

    /// 指定されたインデックスのスペースにフォーカスを切り替える
    /// - Parameter index: 切り替え先のスペースインデックス
    func focusSpace(index: Int) async throws

    /// 指定されたディスプレイにフォーカスを切り替える
    /// - Parameter index: 切り替え先のディスプレイインデックス (1-based)
    func focusDisplay(index: Int) async throws

    /// 全ディスプレイの情報を問い合わせる
    /// - Returns: yabai から取得したディスプレイ情報の配列
    func queryDisplays() async throws -> [YabaiDisplayResponse]
}

/// キーボードイベントの合成・送信を抽象化するインターフェース
protocol KeyEventEmitterProtocol {
    /// Ctrl+数字キーのイベントを送信する
    /// - Parameter number: 送信する数字（1〜10）
    func sendCtrlNumber(_ number: Int)
}

/// プライベート API によるウィンドウキャプチャを抽象化するインターフェース
protocol SkyLightClientProtocol {
    /// 指定されたウィンドウのスクリーンショットを取得する
    /// - Parameter windowID: キャプチャ対象のウィンドウID
    /// - Returns: キャプチャされた画像。失敗時は nil
    func captureWindow(_ windowID: CGWindowID) -> CGImage?
}

/// macOS の壁紙情報へのアクセスを抽象化するインターフェース
protocol WallpaperPlistClientProtocol {
    /// スペースUUIDをキーとした壁紙画像の辞書を取得する
    /// - Returns: スペースUUIDと壁紙画像のマッピング
    func loadWallpapers() -> [String: NSImage]
}

/// ディスプレイマッピングの永続化を抽象化するインターフェース
protocol DisplayMappingFileClientProtocol {
    /// ディスプレイマッピングを読み込む
    /// - Returns: 読み込まれたマッピング
    func load() throws -> DisplayMapping

    /// ディスプレイマッピングを保存する
    /// - Parameter mapping: 保存するマッピング
    func save(_ mapping: DisplayMapping) throws
}

/// アプリ設定の永続化を抽象化するインターフェース
protocol ConfigFileClientProtocol {
    /// 設定ファイルから設定を読み込む
    /// - Returns: 読み込まれた設定
    func load() throws -> Config

    /// 設定ファイルに設定を保存する
    /// - Parameter config: 保存する設定
    func save(_ config: Config) throws
}
