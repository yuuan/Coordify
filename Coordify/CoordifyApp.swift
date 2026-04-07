// swiftlint:disable file_length
import AppKit
import os.log

private let logger = Logger(subsystem: "net.yuuan.Coordify", category: "app")

/// Coordify アプリケーションのエントリーポイント。依存関係の組み立てとライフサイクル管理を行う
@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController!
    private var hotkeyInterceptor: HotkeyInterceptor!
    private var workspaceObserver: WorkspaceObserver!
    private var switcherPanel: SwitcherPanel!

    /// スイッチャー表示時のディスプレイ・スペース状態
    private struct DisplayState {
        /// 全ディスプレイの全スペース
        var allSpaces: [SpaceInfo] = []
        /// 仮想キー → そのディスプレイのスペース一覧
        var spacesByKey: [Int: [SpaceInfo]] = [:]
        /// 表示順の仮想キー一覧
        var sortedKeys: [Int] = []
        /// 現在パネルに表示しているディスプレイの仮想キー
        var activeKey: Int = 0
        /// 仮想キー順に並んだディスプレイ UUID（単一ディスプレイ時のみ使用）
        var uuidOrder: [String] = []
        /// 仮想キー → ディスプレイ名
        var nameByKey: [Int: String] = [:]

        var isMultiDisplay: Bool {
            Set(allSpaces.map(\.displayIndex)).count >= 2
        }
    }

    private var displayState = DisplayState()
    /// パネル表示完了前に pinned mode が要求された場合の遅延フラグ
    private var pendingPinnedMode = false

    private var spaceManager: SpaceManager!
    /// ユーザーが Option+Tab でスペースを移動したかどうか
    private var userDidNavigate = false

    // Adapters
    private let spaceAdapter = SpaceAdapter()
    private let windowCaptureAdapter = WindowCaptureAdapter()
    private let wallpaperAdapter = WallpaperAdapter()
    private let configAdapter = ConfigAdapter()
    private let displayMappingAdapter = DisplayMappingAdapter()

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_: Notification) {
        logger.warning("applicationDidFinishLaunching called")
        // 1. Accessibility permission check
        if !checkAccessibilityPermission() {
            showAccessibilityAlert()
        }

        // 2. Screen Recording permission check (non-blocking)
        Task {
            await ThumbnailCache.shared.captureCurrentSpace(spaceUUID: "permission-check")
            ThumbnailCache.shared.evict(spaceUUID: "permission-check")
        }

        // 3. Compose dependencies
        spaceManager = SpaceManager(spaceQuery: spaceAdapter, windowCapturer: windowCaptureAdapter)
        switcherPanel = SwitcherPanel(spaceSwitcher: spaceAdapter)
        setupSwitcherCallbacks()

        // 4. yabai availability check
        let yabaiAvailable = spaceAdapter.isAvailable
        if !yabaiAvailable {
            NSLog("Coordify: yabai が見つかりません。Space 切替機能は無効です。")
        }

        // 3.5. Mission Control shortcut check
        if !Self.missionControlShortcutsEnabled() {
            showMissionControlAlert()
        }

        // 4. Load config
        _ = try? configAdapter.load()

        // 6. Load wallpapers and refresh space list
        spaceManager.loadWallpapers(provider: wallpaperAdapter)
        Task { @MainActor in
            await spaceManager.refresh()

            // Capture initial thumbnail
            if !spaceManager.currentSpaceUUID.isEmpty {
                await ThumbnailCache.shared.captureCurrentSpace(spaceUUID: spaceManager.currentSpaceUUID)
            }

            // Update menu after initial refresh
            menuBarController.updateMenu()
        }

        // 6. Setup workspace observer
        workspaceObserver = WorkspaceObserver(spaceManager: spaceManager)
        workspaceObserver.onSpaceDidChange = { [weak self] in
            guard let self else { return }
            switcherPanel.dismiss()
            hotkeyInterceptor.resetState()
        }
        workspaceObserver.start()

        // 8. Setup hotkey interceptor
        hotkeyInterceptor = HotkeyInterceptor()
        hotkeyInterceptor.delegate = self
        hotkeyInterceptor.start()

        // 8. Setup menu bar
        menuBarController = MenuBarController(spaceManager: spaceManager, yabaiAvailable: yabaiAvailable)
    }

    @MainActor private func setupSwitcherCallbacks() {
        switcherPanel.onSpaceBarPressed = { [weak self] in
            self?.switchToNextDisplay()
        }
        switcherPanel.onPreviousDisplayRequested = { [weak self] in
            self?.switchToPreviousDisplay()
        }
        switcherPanel.onTabNavigate = { [weak self] delta in
            self?.handleTabNavigation(delta: delta)
        }
        switcherPanel.onSpaceRightClicked = { [weak self] spaceUUID in
            self?.moveSpaceToNextDisplay(spaceUUID: spaceUUID)
        }
        switcherPanel.onEditMappingRequested = {
            NSWorkspace.shared.open(DisplayMappingFileClient.shared.fileURL)
        }
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        showSwitcherPanel {
            self.switcherPanel.startPinnedMode()
        }
        return false
    }

    func applicationWillTerminate(_: Notification) {
        hotkeyInterceptor?.stop()
        workspaceObserver?.stop()
    }

    // MARK: - Permission Checks

    private func checkAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "アクセシビリティ権限が必要です"
        alert.informativeText = "Coordify がホットキーを検知するには、アクセシビリティ権限が必要です。\nシステム設定 > プライバシーとセキュリティ > アクセシビリティ で許可してください。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "設定を開く")
        alert.addButton(withTitle: "後で")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            NSWorkspace.shared.open(url)
        }
    }

    /// Mission Control の「デスクトップ N への切り替え」ショートカットが有効か確認
    /// キー 118〜127 が Desktop 1〜10 に対応
    /// spaceCount を指定するとその数分チェックし、省略時は yabai のスペース数を使う
    private static func missionControlShortcutsEnabled() -> Bool {
        var spaceCount = 2 // デフォルト: 最低2つ
        if SpaceAdapter().isAvailable,
           let spaces = try? syncQuerySpaces()
        {
            spaceCount = spaces.filter { !$0.isNativeFullscreen }.count
        }
        return shortcutsEnabled(forSpaceCount: min(spaceCount, 10))
    }

    private static func shortcutsEnabled(forSpaceCount count: Int) -> Bool {
        guard count > 0 else { return true }
        guard let hotkeys = UserDefaults(suiteName: "com.apple.symbolichotkeys")?
            .dictionary(forKey: "AppleSymbolicHotKeys")
        else {
            return false
        }
        // キー 118 = Desktop 1, 119 = Desktop 2, ... 127 = Desktop 10
        for index in 0 ..< count {
            let key = "\(118 + index)"
            guard let entry = hotkeys[key] as? [String: Any],
                  let enabled = entry["enabled"] as? Bool,
                  enabled
            else {
                return false
            }
        }
        return true
    }

    private static func syncQuerySpaces() throws -> [SpaceQueryResult] {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<[SpaceQueryResult], Error>?
        Task {
            do {
                let spaces = try await SpaceAdapter().querySpaces()
                result = .success(spaces)
            } catch {
                result = .failure(error)
            }
            semaphore.signal()
        }
        semaphore.wait()
        return try result!.get()
    }

    private var guidePanel: NSPanel?

    private func showMissionControlAlert() {
        let alert = NSAlert()
        alert.messageText = "キーボードショートカットが無効です"
        alert.informativeText = "Coordify でスペースを切り替えるには、Mission Control のキーボードショートカットを有効にする必要があります。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "設定を開いて案内を表示")
        alert.addButton(withTitle: "後で")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            showGuidePanel()
            let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Shortcuts")!
            NSWorkspace.shared.open(url)
        }
    }

    private func showGuidePanel() {
        let width: CGFloat = 440
        let height: CGFloat = 260

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Coordify セットアップガイド"
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.isMovableByWindowBackground = true

        setupGuidePanelContent(panel)

        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let originX = screenFrame.maxX - width - 20
            let originY = screenFrame.maxY - height - 20
            panel.setFrameOrigin(NSPoint(x: originX, y: originY))
        }

        panel.orderFrontRegardless()
        guidePanel = panel
    }

    private func setupGuidePanelContent(_ panel: NSPanel) {
        let textView = NSTextField(wrappingLabelWithString: """
        以下の手順でショートカットを有効にしてください:

        1. 左から「Mission Control」を選択
        2. 右側の「Mission Control」のツリーを開く
        3. 「デスクトップ 1 への切り替え」〜 使用するデスクトップの数だけチェックを入れる
        4. 「完了」を押して閉じる
        """)
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = .white
        textView.translatesAutoresizingMaskIntoConstraints = false

        // Mac の慣例: キャンセルが左、アクション（設定した）が右
        let cancelButton = NSButton(title: "キャンセル", target: self, action: #selector(guideCancelClicked))
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}" // Esc

        let doneButton = NSButton(title: "設定した", target: self, action: #selector(guideDoneClicked))
        doneButton.bezelStyle = .rounded
        doneButton.keyEquivalent = "\r" // Enter

        let buttonStack = NSStackView(views: [cancelButton, doneButton])
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 8
        buttonStack.translatesAutoresizingMaskIntoConstraints = false

        panel.contentView?.addSubview(textView)
        panel.contentView?.addSubview(buttonStack)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: panel.contentView!.topAnchor, constant: 16),
            textView.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor, constant: 16),
            textView.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor, constant: -16),

            buttonStack.topAnchor.constraint(greaterThanOrEqualTo: textView.bottomAnchor, constant: 16),
            buttonStack.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor, constant: -16),
            buttonStack.bottomAnchor.constraint(equalTo: panel.contentView!.bottomAnchor, constant: -16),
        ])
    }

    @objc private func guideCancelClicked() {
        guidePanel?.orderOut(nil)
        guidePanel = nil
    }

    @objc private func guideDoneClicked() {
        guidePanel?.orderOut(nil)
        guidePanel = nil

        if !Self.missionControlShortcutsEnabled() {
            showMissionControlAlert()
        }
    }
}

// MARK: - HotkeyInterceptorDelegate

extension AppDelegate: HotkeyInterceptorDelegate {
    func hotkeyInterceptorDidTriggerOpen() {
        // pinned 状態なら選択を移動するだけ（決定しない）
        if switcherPanel.isPinned {
            let shiftDown = NSEvent.modifierFlags.contains(.shift)
            let delta = shiftDown ? -1 : 1
            handleTabNavigation(delta: delta)
            return
        }

        userDidNavigate = false
        showSwitcherPanel()
    }

    private func showSwitcherPanel(then completion: (@MainActor () -> Void)? = nil) {
        Task { @MainActor in
            await spaceManager.refresh()

            displayState.allSpaces = spaceManager.spaces
            guard !displayState.allSpaces.isEmpty else { return }

            if displayState.isMultiDisplay {
                try? await displayMappingAdapter.saveCurrentMapping(spaces: spaceManager.lastQueryResults)
                displayState.spacesByKey = Dictionary(grouping: displayState.allSpaces, by: \.displayIndex)
                displayState.nameByKey = resolveScreenNames()
            } else {
                displayState.spacesByKey = await partitionByDisplayMapping()
            }
            displayState.sortedKeys = displayState.spacesByKey.keys.sorted()
            // フォーカス中のスペースが属する仮想キーを初期表示にする
            let focusedUUID = displayState.allSpaces.first(where: \.hasFocus)?.uuid
            displayState.activeKey = displayState.spacesByKey.first(where: { _, spaces in
                spaces.contains(where: { $0.uuid == focusedUUID })
            })?.key ?? displayState.sortedKeys.first ?? 0

            showPanelForCurrentDisplay()
            if pendingPinnedMode {
                pendingPinnedMode = false
                switcherPanel.startPinnedMode()
            }
            completion?()
        }
    }

    /// 保存済みマッピングを使って単一ディスプレイ上のスペースをディスプレイ UUID ごとに分割する
    /// アクティブディスプレイ=キー1、それ以外は出現順にキー2, 3, ... を割り当てる
    private func partitionByDisplayMapping() async -> [Int: [SpaceInfo]] {
        let mapping = (try? displayMappingAdapter.loadMapping()) ?? DisplayMapping()
        let currentDisplayUUID = await (try? displayMappingAdapter.queryDisplayUUIDs())?.first

        // ディスプレイ UUID → 仮想キーのマッピングを構築
        var uuidToKey: [String: Int] = [:]
        if let current = currentDisplayUUID {
            uuidToKey[current] = 1
        }
        var nextKey = 2

        var result: [Int: [SpaceInfo]] = [:]
        for space in displayState.allSpaces {
            let key: Int
            if let saved = mapping.spacesByUUID[space.uuid]?.display, saved != currentDisplayUUID {
                if let existing = uuidToKey[saved] {
                    key = existing
                } else {
                    uuidToKey[saved] = nextKey
                    key = nextKey
                    nextKey += 1
                }
            } else {
                key = 1
            }
            result[key, default: []].append(space)
        }

        // 仮想キー順にディスプレイ UUID を記録
        let sorted = uuidToKey.sorted(by: { $0.value < $1.value })
        displayState.uuidOrder = sorted.map(\.key)

        // ディスプレイ名を記録
        displayState.nameByKey = [:]
        for (uuid, key) in sorted {
            displayState.nameByKey[key] = mapping.displaysByUUID[uuid]?.name
        }
        return result
    }

    /// NSScreen から displayIndex → 画面名の辞書を構築する
    @MainActor private func resolveScreenNames() -> [Int: String] {
        var names: [Int: String] = [:]
        for (index, screen) in NSScreen.screens.enumerated() {
            names[index + 1] = screen.localizedName
        }
        return names
    }

    /// 現在選択中のディスプレイのスペースをパネルに表示する
    /// - Parameter forceSelectedIndex: 指定するとフォーカス位置ではなくこのインデックスを初期選択にする
    @MainActor private func showPanelForCurrentDisplay(forceSelectedIndex: Int? = nil) {
        guard let spaces = displayState.spacesByKey[displayState.activeKey] else { return }
        let selectedIndex = forceSelectedIndex ?? (spaces.firstIndex(where: \.hasFocus) ?? 0)
        let name = displayState.nameByKey[displayState.activeKey] ?? ""
        let disconnected = !displayState.isMultiDisplay
            && !displayState.uuidOrder.isEmpty && displayState.activeKey != 1
        switcherPanel.show(spaces: spaces, allSpaces: displayState.allSpaces, selectedIndex: selectedIndex,
                           displayName: name, displayDisconnected: disconnected)
    }

    /// スペースを次のディスプレイパネルに移動する（右クリック時）
    @MainActor private func moveSpaceToNextDisplay(spaceUUID: String) {
        guard !displayState.uuidOrder.isEmpty else { return }
        try? displayMappingAdapter.moveSpaceToNextDisplay(
            spaceUUID: spaceUUID, displayUUIDs: displayState.uuidOrder
        )
        // マッピング変更後にパネルを再表示
        showSwitcherPanel {
            self.switcherPanel.startPinnedMode()
        }
    }

    /// パネルの表示を次のディスプレイに切り替える
    @MainActor func switchToNextDisplay() {
        switchDisplay(delta: 1)
    }

    /// パネルの表示を前のディスプレイに切り替える
    @MainActor func switchToPreviousDisplay() {
        switchDisplay(delta: -1)
    }

    @MainActor private func switchDisplay(delta: Int) {
        guard displayState.sortedKeys.count > 1 else { return }
        guard let idx = displayState.sortedKeys.firstIndex(of: displayState.activeKey) else { return }
        let count = displayState.sortedKeys.count
        displayState.activeKey = displayState.sortedKeys[((idx + delta) % count + count) % count]
        showPanelForCurrentDisplay()
        switcherPanel.startPinnedMode()
    }

    /// Tab / Shift+Tab によるナビゲーション。
    /// 複数ディスプレイで現在選択が末端（右端/左端）なら反対側のディスプレイへ跨いで切替、
    /// それ以外は現在のディスプレイ内で選択移動（モジュロでラップ）。
    @MainActor private func handleTabNavigation(delta: Int) {
        let currentSpaces = displayState.spacesByKey[displayState.activeKey] ?? []
        let count = currentSpaces.count
        let idx = switcherPanel.selectedIndex
        let multiDisplay = displayState.sortedKeys.count > 1
        let atEnd = delta > 0 && idx == count - 1
        let atStart = delta < 0 && idx == 0

        if multiDisplay, count > 0, atEnd || atStart {
            crossDisplayTabNavigate(delta: delta)
        } else {
            switcherPanel.updateSelection(to: idx + delta)
        }
    }

    /// 反対側ディスプレイへパネルを切替え、方向に応じて左端（delta>0）または右端（delta<0）を初期選択にする。
    /// 呼び出し時にピン留め中ならピン留め状態を引き継ぐ。
    @MainActor private func crossDisplayTabNavigate(delta: Int) {
        guard displayState.sortedKeys.count > 1 else { return }
        guard let currentIdx = displayState.sortedKeys.firstIndex(of: displayState.activeKey) else { return }
        let wasPinned = switcherPanel.isPinned
        let keyCount = displayState.sortedKeys.count
        let newKey = displayState.sortedKeys[((currentIdx + delta) % keyCount + keyCount) % keyCount]
        displayState.activeKey = newKey
        let targetSpaces = displayState.spacesByKey[newKey] ?? []
        let forceIndex = delta > 0 ? 0 : max(0, targetSpaces.count - 1)
        showPanelForCurrentDisplay(forceSelectedIndex: forceIndex)
        if wasPinned {
            switcherPanel.startPinnedMode()
        }
    }

    func hotkeyInterceptorDidSelectNext() {
        if !switcherPanel.isPinned {
            userDidNavigate = true
        }
        handleTabNavigation(delta: 1)
    }

    func hotkeyInterceptorDidSelectPrevious() {
        if !switcherPanel.isPinned {
            userDidNavigate = true
        }
        handleTabNavigation(delta: -1)
    }

    func hotkeyInterceptorDidConfirm() {
        // pinned 状態なら Alt 離しは無視
        if switcherPanel.isPinned {
            return
        }
        // swiftformat:disable:next redundantSelf
        logger.warning("hotkeyInterceptorDidConfirm userDidNavigate=\(self.userDidNavigate)")
        if !userDidNavigate {
            if switcherPanel.isVisible {
                switcherPanel.startPinnedMode()
            } else {
                pendingPinnedMode = true
            }
            return
        }
        Task { @MainActor in
            await switcherPanel.commitAndClose()
            menuBarController.updateMenu()
        }
    }

    func hotkeyInterceptorDidCancel() {
        switcherPanel.cancelAndClose()
    }

    func hotkeyInterceptorDidSelectDirection(_ direction: HotkeyInterceptor.Direction) {
        userDidNavigate = true
        switch direction {
        case .right:
            switcherPanel.updateSelection(to: switcherPanel.selectedIndex + 1)
        case .left:
            switcherPanel.updateSelection(to: switcherPanel.selectedIndex - 1)
        }
    }
}
