import AppKit

/// macOS のスペース（仮想デスクトップ）1つ分を表すモデル
struct SpaceInfo: Identifiable {
    let id: Int
    let uuid: String
    let index: Int
    let label: String
    let physicalDisplayIndex: PhysicalDisplayIndex
    let isVisible: Bool
    /// フォーカス中スペースかどうか。`refresh` で確定値が入るが、ホットキーの連打対策で
    /// 楽観的に `SpaceManager.markFocused(uuid:)` から更新されることがある。
    var hasFocus: Bool
    let isNativeFullscreen: Bool
    let windowIDs: [Int]
    var apps: [AppInfo]
    var thumbnail: CGImage?
    var wallpaper: NSImage?
}
