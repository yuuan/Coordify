import AppKit

/// スペース上で動作しているアプリケーション1つ分を表すモデル
struct AppInfo: Identifiable {
    let id: Int
    let appName: String
    let bundleIdentifier: String
    let executableName: String
    let icon: NSImage
}
