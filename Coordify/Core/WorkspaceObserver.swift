import AppKit

/// macOS のアクティブスペース変更を検知してスペース情報を最新に保つオブザーバー
/// 連続通知は畳み込み、ref 更新を 1 件 in-flight + 1 件 pending に制限する。
@MainActor
final class WorkspaceObserver {
    private let spaceManager: SpaceManager
    var onSpaceDidChange: (() -> Void)?
    var onSpaceDidChangeAfterRefresh: (() async -> Void)?

    private var isRefreshing = false
    private var hasPending = false

    nonisolated init(spaceManager: SpaceManager) {
        self.spaceManager = spaceManager
    }

    /// スペース切り替え通知の監視を開始する
    nonisolated func start() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(spaceDidChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
    }

    /// 通知の監視を停止する
    nonisolated func stop() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private nonisolated func spaceDidChange(_: Notification) {
        // NSWorkspace の通知配送は main 前提だが、明示的に MainActor に入る
        Task { @MainActor in self.scheduleRefresh() }
    }

    /// in-flight 中なら保留、そうでなければすぐ refresh。完了時に保留があればもう一度走らせる。
    private func scheduleRefresh() {
        if isRefreshing {
            hasPending = true
            return
        }
        isRefreshing = true
        Task { @MainActor in
            repeat {
                hasPending = false
                onSpaceDidChange?()
                await spaceManager.refresh()
                await onSpaceDidChangeAfterRefresh?()
            } while hasPending
            isRefreshing = false
        }
    }
}
