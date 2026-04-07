import AppKit

/// macOS のアクティブスペース変更を検知してスペース情報を最新に保つオブザーバー
final class WorkspaceObserver {
    private let spaceManager: SpaceManager
    var onSpaceDidChange: (() -> Void)?

    init(spaceManager: SpaceManager) {
        self.spaceManager = spaceManager
    }

    /// スペース切り替え通知の監視を開始する
    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(spaceDidChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
    }

    /// 通知の監視を停止する
    func stop() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func spaceDidChange(_: Notification) {
        Task { @MainActor in
            onSpaceDidChange?()
            await spaceManager.refresh()
        }
    }
}
