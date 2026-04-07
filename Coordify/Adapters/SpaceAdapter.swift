import AppKit

/// スペースの情報取得と切り替えを統合的に提供するアダプター
final class SpaceAdapter: SpaceQueryable, SpaceSwitchable {
    private let yabai: YabaiClientProtocol
    private let keyboard: KeyEventEmitterProtocol

    init(yabai: YabaiClientProtocol = YabaiClient.shared, keyboard: KeyEventEmitterProtocol = KeyEventEmitter.shared) {
        self.yabai = yabai
        self.keyboard = keyboard
    }

    // MARK: - SpaceQueryable

    var isAvailable: Bool {
        yabai.isAvailable
    }

    /// yabai からスペース一覧を取得し、SpaceQueryResult に変換する
    /// - Returns: スペース情報の配列
    func querySpaces() async throws -> [SpaceQueryResult] {
        let responses = try await yabai.querySpaces()
        return responses.map { res in
            SpaceQueryResult(
                id: res.id,
                uuid: res.uuid,
                index: res.index,
                label: res.label,
                physicalDisplayIndex: PhysicalDisplayIndex(res.display),
                isVisible: res.isVisible,
                hasFocus: res.hasFocus,
                isNativeFullscreen: res.isNativeFullscreen,
                windowIDs: res.windows
            )
        }
    }

    // MARK: - SpaceSwitchable

    /// 指定されたデスクトップ番号にフォーカスを切り替える（yabai 失敗時は Ctrl+数字キーで代替）
    /// - Parameter desktopNumber: 切り替え先のデスクトップ番号
    func focusSpace(desktopNumber: Int) async throws {
        do {
            try await yabai.focusSpace(index: desktopNumber)
        } catch {
            keyboard.sendCtrlNumber(desktopNumber)
        }
    }

    /// フルスクリーンアプリをアクティブにする
    /// - Parameter bundleIdentifier: 対象アプリのバンドルID
    func focusFullscreenApp(bundleIdentifier: String) {
        let runningApps = NSWorkspace.shared.runningApplications
        if let app = runningApps.first(where: { $0.bundleIdentifier == bundleIdentifier }) {
            app.activate()
        }
    }

    /// 指定された物理ディスプレイにフォーカスを移動する（yabai display --focus）
    func focusDisplay(physicalIndex: PhysicalDisplayIndex) async {
        try? await yabai.focusDisplay(index: physicalIndex.rawValue)
    }
}
