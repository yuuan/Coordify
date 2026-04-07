// swiftlint:disable file_length
import AppKit
import os.log

private let logger = Logger(subsystem: "net.yuuan.Coordify", category: "app")

// MARK: - 用語定義

//
// 物理ディスプレイ (physical display)
//   実際に接続されているディスプレイ。yabai の `queryDisplays` や `NSScreen.screens` が返すもの。
//   `SpaceInfo.physicalDisplayIndex` は yabai が割り当てる 1-based の物理ディスプレイ番号。
//
// 論理ディスプレイ (logical display)
//   Coordify がスイッチャーのパネル単位として扱うディスプレイ。`LogicalDisplay` 値型で表現し、
//   接続中なら `physical != nil`、切断中なら nil。物理接続有無に関わらず同じ操作性を提供するのが目的。
//   論理ディスプレイの構築は `LogicalDisplayStore` が担う。

/// Coordify アプリケーションのエントリーポイント。依存関係の組み立てとライフサイクル管理を行う
@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController!
    private var hotkeyInterceptor: HotkeyInterceptor!
    private var workspaceObserver: WorkspaceObserver!
    private var switcherPanel: SwitcherPanel!

    /// 最後に取得した論理ディスプレイのスナップショット
    private var logicalDisplays: [LogicalDisplay] = []
    /// 現在パネルに表示している論理ディスプレイ ID
    private var activeLogicalDisplayID: LogicalDisplayID = .init(0)
    /// パネル表示完了前に pinned mode が要求された場合の遅延フラグ
    private var pendingPinnedMode = false

    private var spaceManager: SpaceManager!
    /// ユーザーが Option+Tab でスペースを移動したかどうか
    private var userDidNavigate = false

    // Adapters / Store
    private let spaceAdapter = SpaceAdapter()
    private let windowCaptureAdapter = WindowCaptureAdapter()
    private let wallpaperAdapter = WallpaperAdapter()
    private let configAdapter = ConfigAdapter()
    private let displayMappingAdapter = DisplayMappingAdapter()
    private let logicalDisplayStore = LogicalDisplayStore()

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
            await logicalDisplayStore.recordCurrentVisibleSpaces(spaceManager.spaces)

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
        workspaceObserver.onSpaceDidChangeAfterRefresh = { [weak self] in
            guard let self else { return }
            await logicalDisplayStore.recordCurrentVisibleSpaces(spaceManager.spaces)
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
        switcherPanel.onNextLogicalDisplayRequested = { [weak self] in
            self?.switchToNextLogicalDisplay()
        }
        switcherPanel.onPreviousLogicalDisplayRequested = { [weak self] in
            self?.switchToPreviousLogicalDisplay()
        }
        switcherPanel.onTabNavigate = { [weak self] delta in
            self?.handleTabNavigation(delta: delta)
        }
        switcherPanel.onSpaceRightClicked = { [weak self] spaceUUID in
            self?.moveSpaceToNextLogicalDisplay(spaceUUID: spaceUUID)
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
            guard !spaceManager.spaces.isEmpty else { return }

            logicalDisplays = await logicalDisplayStore.snapshot(allSpaces: spaceManager.spaces)
            guard !logicalDisplays.isEmpty else { return }

            // フォーカス中のスペースが属する論理ディスプレイを初期表示にする
            let focusedUUID = spaceManager.spaces.first(where: \.hasFocus)?.uuid
            let initialDisplay = logicalDisplays.first(where: { display in
                display.spaces.contains(where: { $0.uuid == focusedUUID })
            }) ?? logicalDisplays[0]
            activeLogicalDisplayID = initialDisplay.id

            showPanelForActiveLogicalDisplay()
            if pendingPinnedMode {
                pendingPinnedMode = false
                switcherPanel.startPinnedMode()
            }
            completion?()
        }
    }

    /// 現在アクティブな論理ディスプレイのスペースをパネルに表示する
    /// - Parameter forceSelectedIndex: 指定するとフォーカス位置ではなくこのインデックスを初期選択にする
    @MainActor private func showPanelForActiveLogicalDisplay(forceSelectedIndex: Int? = nil) {
        guard let display = logicalDisplays.first(where: { $0.id == activeLogicalDisplayID }) else { return }

        let selectedIndex = forceSelectedIndex
            ?? display.spaces.firstIndex(where: \.hasFocus)
            ?? logicalDisplayStore.lastActiveSpace(in: display)
            .flatMap { target in display.spaces.firstIndex(where: { $0.uuid == target.uuid }) }
            ?? 0

        let allSpaces = logicalDisplays.flatMap(\.spaces)
        // 論理ディスプレイごとに「今表示中のアクティブスペース」を渡してハイライトする。
        // 接続中なら visible な space、切断中なら履歴、どちらも無ければ先頭。
        let activeUUID = logicalDisplayStore.lastActiveSpace(in: display)?.uuid
        switcherPanel.show(
            spaces: display.spaces,
            allSpaces: allSpaces,
            selectedIndex: selectedIndex,
            displayName: display.name,
            displayDisconnected: !display.isConnected,
            activeSpaceUUID: activeUUID
        )
    }

    /// スペースを次の論理ディスプレイに移動する（右クリック時）
    @MainActor private func moveSpaceToNextLogicalDisplay(spaceUUID: String) {
        let keys = logicalDisplays.map(\.key)
        guard !keys.isEmpty else { return }
        try? displayMappingAdapter.moveSpaceToNextLogicalDisplay(
            spaceUUID: spaceUUID, logicalDisplayKeys: keys
        )
        // マッピング変更後にパネルを再表示
        showSwitcherPanel {
            self.switcherPanel.startPinnedMode()
        }
    }

    /// パネルの表示を次の論理ディスプレイに切り替える
    @MainActor func switchToNextLogicalDisplay() {
        switchLogicalDisplay(delta: 1)
    }

    /// パネルの表示を前の論理ディスプレイに切り替える
    @MainActor func switchToPreviousLogicalDisplay() {
        switchLogicalDisplay(delta: -1)
    }

    @MainActor private func switchLogicalDisplay(delta: Int) {
        guard logicalDisplays.count > 1,
              let currentIdx = logicalDisplays.firstIndex(where: { $0.id == activeLogicalDisplayID })
        else { return }
        let count = logicalDisplays.count
        activeLogicalDisplayID = logicalDisplays[((currentIdx + delta) % count + count) % count].id
        showPanelForActiveLogicalDisplay()
        switcherPanel.startPinnedMode()
    }

    /// Tab / Shift+Tab によるナビゲーション。
    /// 複数論理ディスプレイで現在選択が末端（右端/左端）なら反対側の論理ディスプレイへ跨いで切替、
    /// それ以外は現在の論理ディスプレイ内で選択移動（モジュロでラップ）。
    @MainActor private func handleTabNavigation(delta: Int) {
        let currentDisplay = logicalDisplays.first(where: { $0.id == activeLogicalDisplayID })
        let count = currentDisplay?.spaces.count ?? 0
        let idx = switcherPanel.selectedIndex
        let multiLogical = logicalDisplays.count > 1
        let atEnd = delta > 0 && idx == count - 1
        let atStart = delta < 0 && idx == 0

        if multiLogical, count > 0, atEnd || atStart {
            crossLogicalDisplayTabNavigate(delta: delta)
        } else {
            switcherPanel.updateSelection(to: idx + delta)
        }
    }

    /// 反対側の論理ディスプレイへパネルを切替え、方向に応じて左端（delta>0）または右端（delta<0）を初期選択にする。
    /// 呼び出し時にピン留め中ならピン留め状態を引き継ぐ。
    @MainActor private func crossLogicalDisplayTabNavigate(delta: Int) {
        guard logicalDisplays.count > 1,
              let currentIdx = logicalDisplays.firstIndex(where: { $0.id == activeLogicalDisplayID })
        else { return }
        let wasPinned = switcherPanel.isPinned
        let count = logicalDisplays.count
        let newDisplay = logicalDisplays[((currentIdx + delta) % count + count) % count]
        activeLogicalDisplayID = newDisplay.id
        let forceIndex = delta > 0 ? 0 : max(0, newDisplay.spaces.count - 1)
        showPanelForActiveLogicalDisplay(forceSelectedIndex: forceIndex)
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

    /// Ctrl+Cmd+←/→ による同一論理ディスプレイ内の隣接スペース切り替え。
    /// フォーカス中の物理ディスプレイに他の論理ディスプレイも紐づく場合 (1:N) は
    /// macOS ネイティブの Ctrl+← が論理境界を跨いでしまうため、Coordify 側で計算して切り替える。
    /// それ以外 (1:1) は macOS 標準ショートカットに委譲する。
    func hotkeyInterceptorDidRequestAdjacentSpace(_ direction: HotkeyInterceptor.Direction) {
        guard !switcherPanel.isVisible else { return }
        // hot path: キャッシュ参照のみ。refresh は WorkspaceObserver が非同期に追随する。
        let all = spaceManager.spaces
        guard let focused = all.first(where: \.hasFocus) else {
            // キャッシュ未準備時は native Ctrl+矢印にフォールバック（論理境界は 1:1 想定で近似）。
            KeyEventEmitter.shared.sendCtrlArrow(direction: direction)
            return
        }
        Task { @MainActor in
            let displays = await logicalDisplayStore.snapshot(allSpaces: all)
            switch Self.computeAdjacentTarget(in: displays, focused: focused, direction: direction) {
            case .native:
                KeyEventEmitter.shared.sendCtrlArrow(direction: direction)
            case let .explicit(target):
                await switcherPanel.performSwitch(to: target, allSpaces: all, previousApp: nil)
                // 連打対策: refresh が追いつく前に次のキーが来ても正しい起点から計算できるよう楽観更新
                spaceManager.markFocused(uuid: target.uuid)
            case .none:
                break
            }
        }
    }

    /// Ctrl+Cmd+↑/↓ による隣の論理ディスプレイ（パネル）のアクティブスペースへの切り替え。
    /// フォーカス中の物理ディスプレイに他の論理ディスプレイが紐づく 1:N の場合のみ動作する。
    /// 隣パネルの初期選択は、Option+Tab → ↑/↓ でパネルを跨いだときと同じロジック
    /// （`hasFocus` → `lastActiveSpace` → 先頭）で決定する。
    func hotkeyInterceptorDidRequestNeighborPanelActiveSpace(delta: Int) {
        guard !switcherPanel.isVisible else { return }
        // hot path: キャッシュ参照のみ。
        let all = spaceManager.spaces
        guard let focused = all.first(where: \.hasFocus) else { return }
        Task { @MainActor in
            let displays = await logicalDisplayStore.snapshot(allSpaces: all)
            let result = Self.computeNeighborPanelTarget(
                in: displays,
                focused: focused,
                delta: delta,
                resolveActiveSpace: { [logicalDisplayStore] display in
                    display.spaces.first(where: \.hasFocus)
                        ?? logicalDisplayStore.lastActiveSpace(in: display)
                        ?? display.spaces.first
                }
            )
            if case let .explicit(target) = result {
                await switcherPanel.performSwitch(to: target, allSpaces: all, previousApp: nil)
                spaceManager.markFocused(uuid: target.uuid)
            }
        }
    }

    /// 論理ディスプレイの `spaces` 内で `focused` の左右隣のスペースを返す。
    /// 境界 (先頭/末尾) なら nil。
    static func adjacentSpace(in spaces: [SpaceInfo],
                              from focused: SpaceInfo,
                              direction: HotkeyInterceptor.Direction) -> SpaceInfo?
    {
        guard let idx = spaces.firstIndex(where: { $0.uuid == focused.uuid }) else { return nil }
        let next = direction == .left ? idx - 1 : idx + 1
        guard spaces.indices.contains(next) else { return nil }
        return spaces[next]
    }

    /// Ctrl+Cmd+←/→ の決定ロジック。副作用を持たず、テストから駆動できる純粋関数。
    enum AdjacentTarget {
        /// 1:1 ケース — macOS 標準の Ctrl+矢印に委譲
        case native
        /// 1:N ケース — Coordify が明示的に切り替える
        case explicit(SpaceInfo)
        /// 論理境界に達した、または対象スペースが特定できない
        case none
    }

    static func computeAdjacentTarget(
        in displays: [LogicalDisplay],
        focused: SpaceInfo,
        direction: HotkeyInterceptor.Direction
    ) -> AdjacentTarget {
        if !focusedPhysicalHostsMultipleLogicals(displays: displays, focused: focused) {
            return .native
        }
        guard let focusedDisplay = displays.first(where: { display in
            display.spaces.contains(where: { $0.uuid == focused.uuid })
        }) else { return .none }
        guard let target = adjacentSpace(
            in: focusedDisplay.spaces, from: focused, direction: direction
        ) else { return .none }
        return .explicit(target)
    }

    /// Ctrl+Cmd+↑/↓ の決定ロジック。1:N のときだけ隣パネルのアクティブスペースを返す。
    /// `resolveActiveSpace` は `LogicalDisplay` から「その論理ディスプレイの active space」を取り出す戦略を注入する
    /// （本番では `hasFocus` → `lastActiveSpace` → 先頭、テストでは単純な先頭返しなど自由に差し替え可能）。
    enum NeighborPanelTarget {
        case explicit(SpaceInfo)
        case none
    }

    static func computeNeighborPanelTarget(
        in displays: [LogicalDisplay],
        focused: SpaceInfo,
        delta: Int,
        resolveActiveSpace: (LogicalDisplay) -> SpaceInfo?
    ) -> NeighborPanelTarget {
        guard displays.count > 1,
              let currentIdx = displays.firstIndex(where: { display in
                  display.spaces.contains(where: { $0.uuid == focused.uuid })
              }),
              focusedPhysicalHostsMultipleLogicals(displays: displays, focused: focused)
        else { return .none }

        let count = displays.count
        let neighbor = displays[((currentIdx + delta) % count + count) % count]
        guard let target = resolveActiveSpace(neighbor) else { return .none }
        return .explicit(target)
    }

    /// フォーカス中スペースが乗る物理ディスプレイに、所属論理以外の論理ディスプレイも
    /// 同じ `physicalDisplayIndex` のスペースを持っているか（= 1物理:N論理）を判定する。
    static func focusedPhysicalHostsMultipleLogicals(
        displays: [LogicalDisplay], focused: SpaceInfo
    ) -> Bool {
        let focusedDisplayID = displays.first { display in
            display.spaces.contains(where: { $0.uuid == focused.uuid })
        }?.id
        return displays.contains { other in
            other.id != focusedDisplayID
                && other.spaces.contains(where: {
                    $0.physicalDisplayIndex == focused.physicalDisplayIndex
                })
        }
    }

    /// 論理ディスプレイの「アクティブなスペース」を返す。
    /// `showPanelForActiveLogicalDisplay` と同じ優先順位
    /// （`hasFocus` → `lastActiveSpace` → 先頭）で決定する。
    private func activeSpace(in display: LogicalDisplay) -> SpaceInfo? {
        display.spaces.first(where: \.hasFocus)
            ?? logicalDisplayStore.lastActiveSpace(in: display)
            ?? display.spaces.first
    }
}
