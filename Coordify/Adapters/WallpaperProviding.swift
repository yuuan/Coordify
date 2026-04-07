import AppKit

/// スペースごとの壁紙画像の提供能力を表すインターフェース
protocol WallpaperLoadable {
    /// スペースUUIDをキーとした壁紙画像の辞書を取得する
    /// - Returns: スペースUUIDと壁紙画像のマッピング
    func loadWallpapers() -> [String: NSImage]
}
