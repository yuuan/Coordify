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

    /// ホットキーの連打でキャッシュが古くなる前に、切替先スペースを即座に `hasFocus` として反映する。
    /// 非同期 refresh が追いつくまでの繋ぎとして、次のキー押下が正しい起点から計算されるようにする。
    func markFocused(uuid: String) {
        for idx in spaces.indices {
            spaces[idx].hasFocus = (spaces[idx].uuid == uuid)
        }
        currentSpaceUUID = uuid
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

    /// スペース一覧を再取得し、アプリ情報を更新する。
    /// サムネイル生成は main を掴むクリティカルパスから外し、バックグラウンドに投げる。
    func refresh() async {
        guard spaceQuery.isAvailable else { return }

        do {
            // Phase A: yabai クエリ（YabaiClient のノンブロッキング化により main を握らない）
            let responses = try await spaceQuery.querySpaces()
            lastQueryResults = responses

            // Phase B: ウィンドウ列挙を main 外で実行
            let rawWindows = await Task.detached(priority: .userInitiated) {
                RawWindowSnapshot.capture()
            }.value

            var newSpaces = responses.map { response in
                SpaceInfo(
                    id: response.id,
                    uuid: response.uuid,
                    index: response.index,
                    label: response.label,
                    physicalDisplayIndex: response.physicalDisplayIndex,
                    isVisible: response.isVisible,
                    hasFocus: response.hasFocus,
                    isNativeFullscreen: response.isNativeFullscreen,
                    windowIDs: response.windowIDs,
                    apps: [],
                    thumbnail: ThumbnailCache.shared.thumbnail(for: response.uuid),
                    wallpaper: cachedWallpaper(for: response.uuid, physicalDisplayIndex: response.physicalDisplayIndex)
                )
            }

            // Phase C: NSRunningApplication 解決は main 前提
            let (stickyWindows, windowBounds) = resolveApps(for: &newSpaces, rawWindows: rawWindows)

            // Phase D: state 反映（パネル表示に必要な最短経路はここで終わり）
            spaces = newSpaces
            if let focused = newSpaces.first(where: { $0.hasFocus }) {
                currentSpaceUUID = focused.uuid
            }

            // Phase E: サムネ撮影は fire-and-forget で main 外
            ThumbnailCache.shared.scheduleBackgroundRefresh(
                spaces: newSpaces,
                stickyWindows: stickyWindows,
                windowBounds: windowBounds,
                capturer: windowCapturer
            )
        } catch {
            NSLog("SpaceManager refresh failed: %@", error.localizedDescription)
        }
    }

    // MARK: - App Resolution

    /// アプリ情報を解決し、sticky ウィンドウ ID とウィンドウ bounds マップを返す。
    /// windowMap の列挙 (`CGWindowListCopyWindowInfo`) は main 外で済ませた `RawWindowSnapshot` を受け取る。
    private func resolveApps(
        for spaces: inout [SpaceInfo],
        rawWindows: RawWindowSnapshot
    ) -> (Set<Int>, [Int: CGRect]) {
        let appByPID = buildAppByPID()
        let stickyWindows = detectStickyWindows(in: spaces)

        for spaceIndex in spaces.indices {
            spaces[spaceIndex].apps = resolveAppsForSpace(
                spaces[spaceIndex], rawWindows: rawWindows, appByPID: appByPID, stickyWindows: stickyWindows
            )
        }
        return (stickyWindows, rawWindows.bounds)
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
        rawWindows: RawWindowSnapshot,
        appByPID: [pid_t: NSRunningApplication],
        stickyWindows: Set<Int>
    ) -> [AppInfo] {
        var apps: [AppInfo] = []
        var seenBundleIDs: Set<String> = []

        for wid in space.windowIDs {
            guard !stickyWindows.contains(wid),
                  let entry = rawWindows.entriesByID[wid],
                  !entry.isAuxiliary,
                  let runningApp = appByPID[entry.pid],
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

    // MARK: - Wallpaper

    private func cachedWallpaper(for spaceUUID: String, physicalDisplayIndex: PhysicalDisplayIndex) -> NSImage? {
        if let image = wallpaperCache[spaceUUID] {
            return image
        }
        let displayKey = "display-\(physicalDisplayIndex.rawValue - 1)"
        return wallpaperCache[displayKey]
    }
}

// MARK: - RawWindowSnapshot

/// `CGWindowListCopyWindowInfo` の結果から必要なフィールドだけを抜き出した Sendable スナップショット。
/// main スレッド外でも扱えるように値型だけで構成する。
struct RawWindowSnapshot {
    struct Entry {
        let windowID: Int
        let pid: pid_t
        let isAuxiliary: Bool
        let bounds: CGRect?
    }

    let entriesByID: [Int: Entry]
    let bounds: [Int: CGRect]

    static func capture() -> RawWindowSnapshot {
        guard let windowList = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
            return RawWindowSnapshot(entriesByID: [:], bounds: [:])
        }
        var entries: [Int: Entry] = [:]
        var bounds: [Int: CGRect] = [:]
        for dict in windowList {
            guard let wid = dict[kCGWindowNumber as String] as? Int,
                  let pid = dict[kCGWindowOwnerPID as String] as? pid_t
            else { continue }
            let layer = dict[kCGWindowLayer as String] as? Int ?? 0
            let title = dict[kCGWindowName as String] as? String ?? ""
            let isAuxiliary = layer != 0 || title.isEmpty
            var rect: CGRect?
            if let boundsDict = dict[kCGWindowBounds as String] as? NSDictionary,
               let parsed = CGRect(dictionaryRepresentation: boundsDict)
            {
                rect = parsed
                bounds[wid] = parsed
            }
            entries[wid] = Entry(windowID: wid, pid: pid, isAuxiliary: isAuxiliary, bounds: rect)
        }
        return RawWindowSnapshot(entriesByID: entries, bounds: bounds)
    }
}
