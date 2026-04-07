import AppKit

/// macOS の壁紙設定ファイル（Index.plist）からスペースごとの壁紙を提供するクライアント
final class WallpaperPlistClient: WallpaperPlistClientProtocol, WallpaperLoadable {
    static let shared = WallpaperPlistClient()

    /// Index.plist から壁紙パスを読み取り、画像として読み込む
    /// - Returns: スペースUUIDと壁紙画像のマッピング
    func loadWallpapers() -> [String: NSImage] {
        var result: [String: NSImage] = [:]

        let map = wallpaperPathsByUUID()
        for (uuid, path) in map {
            if let image = NSImage(contentsOfFile: path) {
                result[uuid] = image
            }
        }

        return result
    }

    // MARK: - Private

    private func wallpaperPathsByUUID() -> [String: String] {
        let plistPath = NSHomeDirectory() + "/Library/Application Support/com.apple.wallpaper/Store/Index.plist"
        guard let plistData = FileManager.default.contents(atPath: plistPath),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
              let spaces = plist["Spaces"] as? [String: Any]
        else {
            return [:]
        }

        var map: [String: String] = [:]
        for (uuid, value) in spaces {
            guard let spaceDict = value as? [String: Any] else { continue }
            if let path = extractWallpaperPath(from: spaceDict) {
                map[uuid] = path
            }
        }
        return map
    }

    private func extractWallpaperPath(from spaceDict: [String: Any]) -> String? {
        guard let defaultDict = spaceDict["Default"] as? [String: Any],
              let desktop = defaultDict["Desktop"] as? [String: Any],
              let content = desktop["Content"] as? [String: Any],
              let choices = content["Choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let configData = firstChoice["Configuration"] as? Data,
              let config = try? PropertyListSerialization.propertyList(from: configData, format: nil) as? [String: Any],
              let urlDict = config["url"] as? [String: Any],
              let relative = urlDict["relative"] as? String,
              let url = URL(string: relative)
        else {
            return nil
        }
        return url.path
    }
}
