import AppKit

/// macOS のスペース（仮想デスクトップ）1つ分を表すモデル
struct SpaceInfo: Identifiable {
    let id: Int
    let uuid: String
    let index: Int
    let label: String
    let displayIndex: Int
    let isVisible: Bool
    let hasFocus: Bool
    let isNativeFullscreen: Bool
    let windowIDs: [Int]
    var apps: [AppInfo]
    var thumbnail: CGImage?
    var wallpaper: NSImage?
}
