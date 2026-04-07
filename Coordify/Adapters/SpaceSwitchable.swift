import Foundation

/// スペース・ディスプレイへのフォーカス切り替え能力を表すインターフェース
protocol SpaceSwitchable {
    /// 指定されたデスクトップ番号のスペースにフォーカスを切り替える
    /// - Parameter desktopNumber: 切り替え先のデスクトップ番号
    func focusSpace(desktopNumber: Int) async throws

    /// フルスクリーンアプリをアクティブにする
    /// - Parameter bundleIdentifier: 対象アプリのバンドルID
    func focusFullscreenApp(bundleIdentifier: String)

    /// 指定されたディスプレイにフォーカスを移動する
    /// - Parameter displayIndex: yabai の displayIndex (1-based)
    func focusDisplay(displayIndex: Int) async
}
