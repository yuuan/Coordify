import AppKit
import Combine

/// 全スペースの状態（アプリ・サムネイル・壁紙）を集約するコアモデル
@MainActor
final class SpaceManager: ObservableObject {
    @Published var spaces: [SpaceInfo] = []
    @Published var currentSpaceUUID: String = ""
    private(set) var lastQueryResults: [SpaceQueryResult] = []

    private let spaceQuery: SpaceQueryable
    private let windowCapturer: WindowCapturable
    private var wallpaperCache: [String: NSImage] = [:]

    var isAvailable: Bool {
        spaceQuery.isAvailable
    }

    init(spaceQuery: SpaceQueryable, windowCapturer: WindowCapturable) {
        self.spaceQuery = spaceQuery
        self.windowCapturer = windowCapturer
    }

    /// 壁紙プロバイダーから壁紙を読み込み、キャッシュに保存する
    /// - Parameter provider: 壁紙提供プロバイダー
    func loadWallpapers(provider: WallpaperLoadable) {
        wallpaperCache = provider.loadWallpapers()
        for screen in NSScreen.screens {
            if let url = NSWorkspace.shared.desktopImageURL(for: screen),
               let image = NSImage(contentsOf: url)
            {
                let key = "display-\(NSScreen.screens.firstIndex(of: screen) ?? 0)"
                wallpaperCache[key] = image
            }
        }
    }

    /// スペース一覧を再取得し、アプリ情報とサムネイルを更新する
    func refresh() async {
        guard spaceQuery.isAvailable else { return }

        do {
            let responses = try await spaceQuery.querySpaces()
            lastQueryResults = responses
            var newSpaces = responses.map { response in
                SpaceInfo(
                    id: response.id,
                    uuid: response.uuid,
                    index: response.index,
                    label: response.label,
                    displayIndex: response.displayIndex,
                    isVisible: response.isVisible,
                    hasFocus: response.hasFocus,
                    isNativeFullscreen: response.isNativeFullscreen,
                    windowIDs: response.windowIDs,
                    apps: [],
                    thumbnail: ThumbnailCache.shared.thumbnail(for: response.uuid),
                    wallpaper: cachedWallpaper(for: response.uuid, displayIndex: response.displayIndex)
                )
            }

            let (stickyWindows, windowMap) = resolveApps(for: &newSpaces)

            for spaceIndex in newSpaces.indices {
                let space = newSpaces[spaceIndex]
                // sticky・補助ウィンドウを除外した最初のウィンドウをスクリーンショット対象にする
                let captureTarget = space.windowIDs.first { wid in
                    !stickyWindows.contains(wid)
                        && windowMap[wid].map { !isAuxiliaryWindow($0) } ?? false
                }
                guard let firstWindowID = captureTarget else { continue }
                let windowScale = thumbnailScale(
                    for: windowMap[firstWindowID],
                    displayIndex: space.displayIndex
                )
                ThumbnailCache.shared.captureWindow(
                    CGWindowID(firstWindowID),
                    capturer: windowCapturer,
                    wallpaper: space.wallpaper,
                    spaceUUID: space.uuid,
                    fullscreen: space.isNativeFullscreen,
                    windowScale: windowScale
                )
                newSpaces[spaceIndex].thumbnail = ThumbnailCache.shared.thumbnail(for: space.uuid)
            }

            spaces = newSpaces
            if let focused = newSpaces.first(where: { $0.hasFocus }) {
                currentSpaceUUID = focused.uuid
            }
        } catch {
            NSLog("SpaceManager refresh failed: %@", error.localizedDescription)
        }
    }

    // MARK: - App Resolution

    /// アプリ情報を解決し、sticky ウィンドウの ID セットとウィンドウ情報マップを返す
    @discardableResult
    private func resolveApps(for spaces: inout [SpaceInfo]) -> (Set<Int>, [Int: [String: Any]]) {
        guard let windowList = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
            return ([], [:])
        }

        let windowMap = buildWindowMap(from: windowList)
        let appByPID = buildAppByPID()
        let stickyWindows = detectStickyWindows(in: spaces)

        for spaceIndex in spaces.indices {
            spaces[spaceIndex].apps = resolveAppsForSpace(
                spaces[spaceIndex], windowMap: windowMap, appByPID: appByPID, stickyWindows: stickyWindows
            )
        }
        return (stickyWindows, windowMap)
    }

    private func buildWindowMap(from windowList: [[String: Any]]) -> [Int: [String: Any]] {
        var map: [Int: [String: Any]] = [:]
        for entry in windowList {
            if let wid = entry[kCGWindowNumber as String] as? Int {
                map[wid] = entry
            }
        }
        return map
    }

    private func buildAppByPID() -> [pid_t: NSRunningApplication] {
        var map: [pid_t: NSRunningApplication] = [:]
        for app in NSWorkspace.shared.runningApplications {
            map[app.processIdentifier] = app
        }
        return map
    }

    /// 全スペースに出現するウィンドウ（sticky）を検出する
    private func detectStickyWindows(in spaces: [SpaceInfo]) -> Set<Int> {
        var windowSpaceCount: [Int: Int] = [:]
        for space in spaces {
            for wid in space.windowIDs {
                windowSpaceCount[wid, default: 0] += 1
            }
        }
        return Set(windowSpaceCount.filter { $0.value == spaces.count }.map(\.key))
    }

    private func resolveAppsForSpace(
        _ space: SpaceInfo,
        windowMap: [Int: [String: Any]],
        appByPID: [pid_t: NSRunningApplication],
        stickyWindows: Set<Int>
    ) -> [AppInfo] {
        var apps: [AppInfo] = []
        var seenBundleIDs: Set<String> = []

        for wid in space.windowIDs {
            guard !stickyWindows.contains(wid),
                  let info = windowMap[wid],
                  !isAuxiliaryWindow(info),
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let runningApp = appByPID[pid],
                  let bundleID = runningApp.bundleIdentifier,
                  !seenBundleIDs.contains(bundleID)
            else { continue }

            seenBundleIDs.insert(bundleID)
            apps.append(AppInfo(
                id: wid,
                appName: runningApp.localizedName ?? bundleID,
                bundleIdentifier: bundleID,
                executableName: runningApp.executableURL?.lastPathComponent ?? "",
                icon: runningApp.icon ?? NSImage(named: NSImage.applicationIconName)!
            ))
        }
        return apps
    }

    /// 通常のアプリウィンドウではない補助的なウィンドウ（通知、ツールチップ等）を判定する
    ///
    /// 以下のいずれかに該当するウィンドウを除外対象とする:
    /// - `kCGWindowLayer` が 0 以外（オーバーレイ、ツールチップ等の手前レイヤー）
    /// - `kCGWindowName` が空（タイトルのないサブウィンドウ）
    private func isAuxiliaryWindow(_ info: [String: Any]) -> Bool {
        if let layer = info[kCGWindowLayer as String] as? Int, layer != 0 {
            return true
        }
        let title = info[kCGWindowName as String] as? String ?? ""
        return title.isEmpty
    }

    // MARK: - Thumbnail scale

    /// ウィンドウがディスプレイの可視領域に対してどれだけ占めているかでサムネ表示倍率を決める
    /// 最大化判定（visibleFrame の85%以上を覆う）なら 0.9、それ以外は 0.6
    private func thumbnailScale(for windowInfo: [String: Any]?, displayIndex: Int) -> CGFloat {
        guard let info = windowInfo,
              let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsDict)
        else { return 0.6 }

        let screens = NSScreen.screens
        let idx = displayIndex - 1
        let screen = (idx >= 0 && idx < screens.count) ? screens[idx] : NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return 0.6 }

        let coverage = (bounds.width * bounds.height) / (visibleFrame.width * visibleFrame.height)
        return coverage >= 0.85 ? 0.9 : 0.6
    }

    // MARK: - Wallpaper

    private func cachedWallpaper(for spaceUUID: String, displayIndex: Int) -> NSImage? {
        if let image = wallpaperCache[spaceUUID] {
            return image
        }
        let displayKey = "display-\(displayIndex - 1)"
        return wallpaperCache[displayKey]
    }
}
