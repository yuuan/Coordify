import AppKit

/// スペースごとの壁紙画像を提供するアダプター
final class WallpaperAdapter: WallpaperLoadable {
    private let plistClient: WallpaperPlistClientProtocol

    init(plistClient: WallpaperPlistClientProtocol = WallpaperPlistClient.shared) {
        self.plistClient = plistClient
    }

    /// スペースUUIDをキーとした壁紙画像の辞書を取得する
    /// - Returns: スペースUUIDと壁紙画像のマッピング
    func loadWallpapers() -> [String: NSImage] {
        plistClient.loadWallpapers()
    }
}
