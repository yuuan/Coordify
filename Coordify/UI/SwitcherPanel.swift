// swiftlint:disable file_length
@preconcurrency import AppKit
import Carbon.HIToolbox
import os.log

private let logger = Logger(subsystem: "net.yuuan.Coordify", category: "panel")

/// スペースの一覧表示と選択操作を提供するフローティングパネル
@MainActor
// swiftlint:disable:next type_body_length
final class SwitcherPanel {
    private var panel: NSPanel?
    private var cardViews: [SpaceCardView] = []
    private var overlayCard: SpaceCardView?
    private var shadowView: NSView?
    private var spaces: [SpaceInfo] = []
    private var allSpaces: [SpaceInfo] = []
    private var shortcutKeys: [String?] = []
    /// 現在表示中の論理ディスプレイの「アクティブスペース」の UUID。
    /// 背景ハイライト判定に使う（グローバルフォーカスでなくても論理ディスプレイごとにハイライトする）。
    private var activeSpaceUUID: String?
    private(set) var selectedIndex: Int = 0
    private var clickMonitor: Any?
    private var keyMonitor: Any?
    private var scrollMonitor: Any?
    private var scrollAccumY: CGFloat = 0
    private var scrollArmed: Bool = true
    private var previousApp: NSRunningApplication?
    private var clockTimer: Timer?
    private var clockLabel: NSTextField?
    var isVisible: Bool {
        panel != nil
    }

    /// 次のディスプレイパネルへの切り替え要求コールバック
    var onNextLogicalDisplayRequested: (() -> Void)?

    /// 前のディスプレイパネルへの切り替え要求コールバック
    var onPreviousLogicalDisplayRequested: (() -> Void)?

    /// Tab/Shift+Tab が押されたときのコールバック（delta = +1 or -1）
    /// 設定されていればこちらが優先され、設定されていなければ同ディスプレイ内で updateSelection
    var onTabNavigate: ((Int) -> Void)?

    /// スペースカードが右クリックされたときのコールバック（スペースUUIDを渡す）
    var onSpaceRightClicked: ((String) -> Void)?

    /// ⌘, が押されたときのコールバック（マッピング編集用）
    var onEditMappingRequested: (() -> Void)?

    private(set) var isPinned = false
    private let spaceSwitcher: SpaceSwitchable

    init(spaceSwitcher: SpaceSwitchable) {
        self.spaceSwitcher = spaceSwitcher
    }

    /// スイッチャーパネルを表示する
    /// - Parameter activeSpaceUUID: 現在表示中の論理ディスプレイの「アクティブ」スペース UUID。
    ///   背景ハイライト対象。グローバルフォーカス外の論理ディスプレイでもハイライトされる。
    func show(spaces: [SpaceInfo], allSpaces: [SpaceInfo], selectedIndex: Int,
              displayName: String = "", displayDisconnected: Bool = false,
              activeSpaceUUID: String? = nil, on screen: NSScreen? = nil)
    {
        self.spaces = spaces
        self.allSpaces = allSpaces
        self.selectedIndex = selectedIndex
        self.activeSpaceUUID = activeSpaceUUID
        close()

        guard !spaces.isEmpty else { return }

        // 初期選択が選択不可なら次の選択可能なスペースに移動
        if !isSelectable(at: selectedIndex) {
            var found = false
            for offset in 1 ..< spaces.count {
                let candidate = (selectedIndex + offset) % spaces.count
                if isSelectable(at: candidate) {
                    self.selectedIndex = candidate
                    found = true
                    break
                }
            }
            if !found { self.selectedIndex = -1 }
        }

        // ショートカットキーを一括計算
        let spaceNames = spaces.map(Self.spaceName)
        shortcutKeys = ShortcutKeyRule.assignShortcutKeys(spaces: spaces, spaceNames: spaceNames)

        let panel = createPanel(for: spaces)
        let stackView = createCardGrid(spaces: spaces)

        // contentView から window の root まで全てのクリッピングを無効化
        var ancestor: NSView? = panel.contentView
        while let view = ancestor {
            view.wantsLayer = true
            view.layer?.masksToBounds = false
            ancestor = view.superview
        }
        // 背景ビューの参照（グリッドとフッターの配置基準に使う）
        let bgView = panel.contentView!.subviews.last!

        panel.contentView?.addSubview(stackView)
        let footer = createFooter(
            displayName: displayName, displayDisconnected: displayDisconnected, width: panel.frame.width
        )
        panel.contentView?.addSubview(footer)
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: bgView.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: bgView.centerYAnchor,
                                               constant: -Self.footerHeight / 2),
            footer.leadingAnchor.constraint(equalTo: bgView.leadingAnchor, constant: Self.padding),
            footer.trailingAnchor.constraint(equalTo: bgView.trailingAnchor, constant: -Self.padding),
            footer.bottomAnchor.constraint(equalTo: bgView.bottomAnchor),
        ])

        centerOnScreen(panel, on: screen)
        panel.orderFrontRegardless()
        self.panel = panel
        updateOverlayCard()
    }

    /// 選択中のスペースを変更する（循環選択対応、選択不可スペースをスキップ）
    /// - Parameter index: 新しい選択インデックス
    func updateSelection(to index: Int) {
        guard !spaces.isEmpty, selectedIndex >= 0 else { return }
        let direction = index >= selectedIndex ? 1 : -1
        var newIndex = ((index % spaces.count) + spaces.count) % spaces.count

        // 選択不可スペースをスキップ（最大1周まで）
        for _ in 0 ..< spaces.count {
            if isSelectable(at: newIndex) { break }
            newIndex = ((newIndex + direction) % spaces.count + spaces.count) % spaces.count
        }

        selectedIndex = newIndex
        updateOverlayCard()
    }

    /// そのスペースが選択可能かどうか
    /// 別の物理ディスプレイにあるアプリなしスペースは選択不可
    private func isSelectable(at index: Int) -> Bool {
        let space = spaces[index]
        let focusedDisplay = allSpaces.first(where: \.hasFocus)?.physicalDisplayIndex
        if space.physicalDisplayIndex != focusedDisplay, space.apps.isEmpty {
            return false
        }
        return true
    }

    /// 選択中のスペースに切り替えてパネルを閉じる
    func commitAndClose() async {
        guard !spaces.isEmpty, selectedIndex < spaces.count else {
            let empty = spaces.isEmpty
            let idx = selectedIndex
            let cnt = spaces.count
            logger.warning("commitAndClose skipped (empty=\(empty), index=\(idx), count=\(cnt))")
            close()
            return
        }

        let targetSpace = spaces[selectedIndex]
        let appToRestore = previousApp
        logger.warning("switching to space index=\(targetSpace.index), uuid=\(targetSpace.uuid)")
        close()
        await performSwitch(to: targetSpace, allSpaces: allSpaces, previousApp: appToRestore)
    }

    /// パネルを介さずに、指定スペースへ切り替える純粋スイッチ処理。
    /// commitAndClose とロジックを共有するため、グローバルホットキー経由でも呼び出せる。
    func performSwitch(to targetSpace: SpaceInfo,
                       allSpaces: [SpaceInfo],
                       previousApp: NSRunningApplication?) async
    {
        if targetSpace.hasFocus {
            previousApp?.activate()
            return
        }

        // 移動先スペースにアプリがあればそのアプリを activate して完了
        if let app = targetSpace.apps.first {
            spaceSwitcher.focusFullscreenApp(bundleIdentifier: app.bundleIdentifier)
            logger.warning("activated app: \(app.appName) on space \(targetSpace.index)")
            return
        }

        // アプリがないスペースの場合: 対象の物理ディスプレイにフォーカスしてから Ctrl+数字
        let focusedPhysical = allSpaces.first(where: \.hasFocus)?.physicalDisplayIndex
        if focusedPhysical != targetSpace.physicalDisplayIndex {
            await spaceSwitcher.focusDisplay(physicalIndex: targetSpace.physicalDisplayIndex)
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2秒待機
        }

        // per-display: 同じ物理ディスプレイの通常スペースの中で何番目か
        let targetDisplay = targetSpace.physicalDisplayIndex
        let desktopNumber = allSpaces
            .filter {
                !$0.isNativeFullscreen
                    && $0.physicalDisplayIndex == targetDisplay
                    && $0.index <= targetSpace.index
            }
            .count

        do {
            try await spaceSwitcher.focusSpace(desktopNumber: desktopNumber)
            logger.warning("focusSpace succeeded (desktopNumber=\(desktopNumber))")
        } catch {
            logger.warning("Space 切替失敗: \(String(describing: error), privacy: .public)")
        }
    }

    /// 選択をキャンセルしてパネルを閉じ、元のアプリに戻る
    func cancelAndClose() {
        let appToRestore = previousApp
        close()
        appToRestore?.activate()
    }

    /// パネルを閉じるだけ（アプリ復元なし、外部からのスペース切替時用）
    func dismiss() {
        close()
    }

    /// ピン留めモードを開始し、パネルがキー入力を受け付ける状態にする
    func startPinnedMode() {
        stopPinnedMode()
        logger.warning("startPinnedMode called, panel=\(self.panel == nil ? "nil" : "exists")")
        guard let panel else { return }
        isPinned = true

        // 現在フォーカス中のアプリを記憶
        previousApp = NSWorkspace.shared.frontmostApplication

        // パネルがキー入力を受けられるようにする
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.cancelAndClose()
            }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event -> NSEvent? in
            guard let self else { return event }
            let keyCode = event.keyCode
            let modifiers = event.modifierFlags
            let handled: Bool = MainActor.assumeIsolated {
                self.handlePinnedKeyDown(keyCode: keyCode, modifiers: modifiers)
            }
            return handled ? nil : event
        }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event -> NSEvent? in
            guard let self else { return event }
            let deltaY = event.scrollingDeltaY
            let phase = event.phase
            let momentumPhase = event.momentumPhase
            MainActor.assumeIsolated {
                self.handleScroll(deltaY: deltaY, phase: phase, momentumPhase: momentumPhase)
            }
            return nil
        }
    }

    /// 縦スクロールを ↑/↓ 矢印キー押下相当のナビゲーションに変換する。
    /// トラックパッドは 1 ジェスチャー 1 段（慣性スクロールは無視）、
    /// マウスホイールは 1 ティック 1 段になるよう量子化する。
    private func handleScroll(deltaY: CGFloat, phase: NSEvent.Phase, momentumPhase: NSEvent.Phase) {
        // 慣性フェーズは完全に無視（物理スワイプのみに反応）
        guard momentumPhase.isEmpty else { return }

        // phase 空 = 旧来のマウスホイールティック。1 イベント 1 段
        if phase.isEmpty {
            if deltaY > 0 {
                moveSelectionVertically(-1)
            } else if deltaY < 0 {
                moveSelectionVertically(1)
            }
            return
        }

        // トラックパッドのジェスチャー
        if phase.contains(.began) {
            scrollArmed = true
            scrollAccumY = 0
        }
        if phase.contains(.ended) || phase.contains(.cancelled) {
            scrollAccumY = 0
            scrollArmed = true
            return
        }

        scrollAccumY += deltaY
        let threshold: CGFloat = 20
        if scrollArmed, abs(scrollAccumY) >= threshold {
            let direction = scrollAccumY > 0 ? -1 : 1
            moveSelectionVertically(direction)
            scrollArmed = false
        }
    }

    /// kVK_ANSI_1 ~ kVK_ANSI_0 のキーコード → スペースインデックス(0-based)
    /// keyCode → spaceIndex(0-based) のマップ。ShortcutKeyRule.desktopShortcuts から導出。
    private static let numberKeyMap: [Int: Int] = {
        var map: [Int: Int] = [:]
        for (spaceIndex, shortcut) in ShortcutKeyRule.desktopShortcuts {
            map[shortcut.keyCode] = spaceIndex - 1
        }
        return map
    }()

    private func handlePinnedKeyDown(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        let code = Int(keyCode)

        switch code {
        case 123: // left arrow
            updateSelection(to: selectedIndex - 1)
            return true
        case 124: // right arrow
            updateSelection(to: selectedIndex + 1)
            return true
        case 125: // down arrow
            moveSelectionVertically(1)
            return true
        case 126: // up arrow
            moveSelectionVertically(-1)
            return true
        case 48: // tab
            handleTabKey(shift: modifiers.contains(.shift))
            return true
        case 36: // return
            Task { await commitAndClose() }
            return true
        case 53: // escape
            cancelAndClose()
            return true
        case 49: // space bar
            onNextLogicalDisplayRequested?()
            return true
        case 43 where modifiers.contains(.command): // ⌘,
            dismiss()
            onEditMappingRequested?()
            return true
        default:
            return handleDirectSelection(code: code, keyCode: keyCode)
        }
    }

    private func handleTabKey(shift: Bool) {
        let delta = shift ? -1 : 1
        if let handler = onTabNavigate {
            handler(delta)
        } else {
            updateSelection(to: selectedIndex + delta)
        }
    }

    private func handleDirectSelection(code: Int, keyCode: UInt16) -> Bool {
        if let spaceIndex = Self.numberKeyMap[code], spaceIndex < spaces.count, isSelectable(at: spaceIndex) {
            updateSelection(to: spaceIndex)
            Task { await commitAndClose() }
            return true
        }
        if let index = fullscreenIndexForKey(keyCode: keyCode), isSelectable(at: index) {
            updateSelection(to: index)
            Task { await commitAndClose() }
            return true
        }
        return false
    }

    private func moveSelectionVertically(_ direction: Int) {
        guard !spaces.isEmpty else { return }
        let cols = Self.maxColumns
        let currentRow = selectedIndex / cols
        let rows = Self.rowCount(for: spaces.count)

        // 最下段で下 → 次のディスプレイ、最上段で上 → 前のディスプレイ
        if direction > 0, currentRow == rows - 1 {
            onNextLogicalDisplayRequested?()
            return
        }
        if direction < 0, currentRow == 0 {
            onPreviousLogicalDisplayRequested?()
            return
        }

        let currentCol = selectedIndex % cols
        let targetRow = ((currentRow + direction) % rows + rows) % rows
        let targetIndex = targetRow * cols + currentCol
        if targetIndex < spaces.count {
            updateSelection(to: targetIndex)
        } else {
            updateSelection(to: spaces.count - 1)
        }
    }

    private func stopPinnedMode() {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
            scrollMonitor = nil
        }
        scrollAccumY = 0
        scrollArmed = true
    }

    private func close() {
        clockTimer?.invalidate()
        clockTimer = nil
        clockLabel = nil
        stopPinnedMode()
        isPinned = false
        panel?.collectionBehavior = []
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        cardViews = []
        shadowView?.removeFromSuperview()
        shadowView = nil
        overlayCard?.removeFromSuperview()
        overlayCard = nil
        previousApp = nil
    }

    private func updateOverlayCard() {
        shadowView?.removeFromSuperview()
        shadowView = nil
        overlayCard?.removeFromSuperview()
        overlayCard = nil

        guard selectedIndex < spaces.count else { return }
        guard let contentView = panel?.contentView else { return }
        guard selectedIndex < cardViews.count else { return }

        let space = spaces[selectedIndex]
        let originalCard = cardViews[selectedIndex]
        let isLastRow = selectedIndex / Self.maxColumns == Self.rowCount(for: spaces.count) - 1

        let shadow = createShadowView(isLastRow: isLastRow)
        contentView.addSubview(shadow)

        let overlay = createOverlayCard(for: space)
        contentView.addSubview(overlay)

        overlay.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: originalCard.topAnchor),
            overlay.leadingAnchor.constraint(equalTo: originalCard.leadingAnchor),
            overlay.widthAnchor.constraint(equalTo: originalCard.widthAnchor),
            overlay.heightAnchor.constraint(greaterThanOrEqualToConstant: Self.cardHeight(for: spaces)),

            isLastRow
                ? shadow.topAnchor.constraint(equalTo: overlay.topAnchor, constant: -12)
                : shadow.topAnchor.constraint(equalTo: overlay.bottomAnchor, constant: -6),
            shadow.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: isLastRow ? -10 : 0),
            shadow.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: isLastRow ? 10 : 0),
            shadow.bottomAnchor.constraint(equalTo: overlay.bottomAnchor, constant: isLastRow ? 12 : 16),
        ])

        shadowView = shadow
        overlayCard = overlay
    }

    private func createShadowView(isLastRow: Bool) -> NSView {
        let shadow = NSView()
        shadow.wantsLayer = true
        shadow.translatesAutoresizingMaskIntoConstraints = false

        if isLastRow {
            shadow.layer?.backgroundColor = NSColor(white: 0.05, alpha: 1.0).cgColor
            shadow.layer?.cornerRadius = 16
        } else {
            let gradient = CAGradientLayer()
            gradient.colors = [NSColor(white: 0, alpha: 0).cgColor, NSColor(white: 0, alpha: 1.0).cgColor]
            gradient.startPoint = CGPoint(x: 0.5, y: 0)
            gradient.endPoint = CGPoint(x: 0.5, y: 1)
            shadow.layer = gradient
        }
        return shadow
    }

    private func createOverlayCard(for space: SpaceInfo) -> SpaceCardView {
        let overlay = SpaceCardView()
        overlay.configure(with: makeViewModel(for: space, at: selectedIndex, isSelected: true))
        overlay.onClick = { [weak self] in
            guard let self else { return }
            Task { await self.commitAndClose() }
        }
        overlay.onRightClick = { [weak self] in
            self?.onSpaceRightClicked?(space.uuid)
        }
        return overlay
    }

    // MARK: - Helpers

    private static let maxColumns = 6
    private static let cardWidth: CGFloat = SpaceCardView.cardWidth
    private static let spacing: CGFloat = 16
    private static let rowSpacing: CGFloat = 16
    private static let padding: CGFloat = 16
    private static let footerHeight: CGFloat = 72
    private static let thumbnailHeight: CGFloat = SpaceCardView.thumbnailHeight
    private static let nameLabelHeight: CGFloat = 18
    private static let separatorHeight: CGFloat = 1
    private static let nameLabelSpacing: CGFloat = 8 // nameLabel の上下
    private static let appListSpacing: CGFloat = 14 // appList の上
    private static let cardFixedHeight: CGFloat =
        thumbnailHeight + nameLabelSpacing + nameLabelHeight + nameLabelSpacing + separatorHeight + appListSpacing
    private static let appRowHeight: CGFloat = 23

    private static func cardHeight(for spaces: [SpaceInfo]) -> CGFloat {
        let limit = SpaceCardView.maxApps
        let maxDisplayApps = spaces.map { min($0.apps.count, limit) }.max() ?? 0
        let hasMoreLabel = spaces.contains { $0.apps.count > limit }
        let rowCount = maxDisplayApps + (hasMoreLabel ? 1 : 0)
        let appsHeight = CGFloat(max(rowCount, 1)) * appRowHeight
        return cardFixedHeight + appsHeight + padding
    }

    private static func rowCount(for spaceCount: Int) -> Int {
        max(1, Int(ceil(Double(spaceCount) / Double(maxColumns))))
    }

    private static func columnsInRow(for spaceCount: Int) -> Int {
        min(spaceCount, maxColumns)
    }

    private func createFooter(displayName: String, displayDisconnected: Bool = false, width _: CGFloat) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let nameLabel = NSTextField(labelWithString: "")
        let nameColor = NSColor(red: 0.35, green: 0.45, blue: 0.55, alpha: 1.0)
        let nameFont = NSFont.systemFont(ofSize: 16, weight: .light)
        if displayDisconnected, !displayName.isEmpty {
            let attributed = NSMutableAttributedString(
                string: displayName,
                attributes: [.foregroundColor: nameColor, .font: nameFont]
            )
            let suffix = NSAttributedString(
                string: " (disconnected)",
                attributes: [.foregroundColor: NSColor(white: 0.25, alpha: 1.0), .font: nameFont]
            )
            attributed.append(suffix)
            nameLabel.attributedStringValue = attributed
        } else {
            nameLabel.stringValue = displayName
            nameLabel.font = nameFont
            nameLabel.textColor = nameColor
        }
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        let timeLabel = NSTextField(labelWithString: "")
        timeLabel.attributedStringValue = Self.formattedNowAttributed()
        timeLabel.alignment = .right
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        clockLabel = timeLabel

        container.addSubview(nameLabel)
        container.addSubview(timeLabel)
        NSLayoutConstraint.activate([
            nameLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            nameLabel.lastBaselineAnchor.constraint(equalTo: timeLabel.lastBaselineAnchor),
            timeLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            timeLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            container.heightAnchor.constraint(equalToConstant: Self.footerHeight),
        ])

        startClock()
        return container
    }

    private func startClock() {
        clockTimer?.invalidate()
        clockTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.clockLabel?.attributedStringValue = Self.formattedNowAttributed()
            }
        }
    }

    private static let clockColor = NSColor(
        red: 0x45 / 255.0, green: 0x85 / 255.0, blue: 0x88 / 255.0, alpha: 1.0
    )
    private static let dateFont: NSFont = .systemFont(ofSize: 16)
    private static let timeFont: NSFont = .init(name: "SF Mono", size: 32)
        ?? .monospacedSystemFont(ofSize: 32, weight: .regular)

    private static func formattedNowAttributed() -> NSAttributedString {
        let now = Date()
        let dateFmt = DateFormatter()
        dateFmt.locale = Locale(identifier: "ja_JP")
        dateFmt.dateFormat = "M/d(EEE)"
        let timeFmt = DateFormatter()
        timeFmt.locale = Locale(identifier: "ja_JP")
        timeFmt.dateFormat = "HH:mm:ss"

        let result = NSMutableAttributedString()
        result.append(NSAttributedString(
            string: dateFmt.string(from: now),
            attributes: [.font: dateFont, .foregroundColor: clockColor, .kern: 2]
        ))
        result.append(NSAttributedString(
            string: " ",
            attributes: [.font: dateFont, .kern: 4]
        ))
        result.append(NSAttributedString(
            string: timeFmt.string(from: now),
            attributes: [.font: timeFont, .foregroundColor: clockColor]
        ))
        return result
    }

    /// オーバーレイカードが下方向にはみ出す分のマージン
    private static let overflowMargin: CGFloat = 300

    private func createPanel(for spaces: [SpaceInfo]) -> NSPanel {
        let cols = Self.columnsInRow(for: spaces.count)
        let rows = Self.rowCount(for: spaces.count)
        let colsF = CGFloat(cols)
        let rowsF = CGFloat(rows)
        let totalWidth = Self.padding * 2 + colsF * Self.cardWidth + (colsF - 1) * Self.spacing
        let cardHeight = Self.cardHeight(for: spaces)
        let visibleHeight = Self.padding * 2 + rowsF * cardHeight + (rowsF - 1) * Self.rowSpacing + Self.footerHeight
        let panelHeight = visibleHeight + Self.overflowMargin

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: totalWidth, height: panelHeight),
            styleMask: [.nonactivatingPanel, .borderless, .hudWindow],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.appearance = NSAppearance(named: .darkAqua)

        addBackgroundViews(to: panel, visibleHeight: visibleHeight)
        return panel
    }

    /// 背景ビューを上寄せで固定サイズに配置する（パネル下部の透明領域にははみ出さない）
    private func addBackgroundViews(to panel: NSPanel, visibleHeight: CGFloat) {
        let contentView = panel.contentView!

        let blurView = NSVisualEffectView()
        blurView.translatesAutoresizingMaskIntoConstraints = false
        blurView.material = .hudWindow
        blurView.state = .active
        blurView.blendingMode = .behindWindow
        blurView.wantsLayer = true
        blurView.layer?.cornerRadius = 12
        blurView.layer?.masksToBounds = true
        contentView.addSubview(blurView)

        let tintView = NSView()
        tintView.translatesAutoresizingMaskIntoConstraints = false
        tintView.wantsLayer = true
        tintView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.85).cgColor
        tintView.layer?.cornerRadius = 12
        tintView.layer?.masksToBounds = true
        contentView.addSubview(tintView)

        // 上端に揃えて visibleHeight 分だけ確保（下側は透明の余白）
        for view in [blurView, tintView] {
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: contentView.topAnchor),
                view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                view.heightAnchor.constraint(equalToConstant: visibleHeight),
            ])
        }
    }

    private func createCardGrid(spaces: [SpaceInfo]) -> NSStackView {
        let cardHeight = Self.cardHeight(for: spaces)
        cardViews = []

        let gridStack = NSStackView()
        gridStack.orientation = .vertical
        gridStack.spacing = Self.rowSpacing
        gridStack.alignment = .leading
        gridStack.translatesAutoresizingMaskIntoConstraints = false

        let rows = spaces.chunked(by: Self.maxColumns)
        for row in rows {
            let rowStack = NSStackView()
            rowStack.orientation = .horizontal
            rowStack.spacing = Self.spacing

            for space in row {
                let cardIndex = spaces.firstIndex(where: { $0.id == space.id })!
                let card = SpaceCardView()
                card.configure(with: makeViewModel(for: space, at: cardIndex, isSelected: false))
                card.onClick = { [weak self] in
                    guard let self, isSelectable(at: cardIndex) else { return }
                    updateSelection(to: cardIndex)
                    Task { await self.commitAndClose() }
                }
                card.onRightClick = { [weak self] in
                    self?.onSpaceRightClicked?(space.uuid)
                }
                card.translatesAutoresizingMaskIntoConstraints = false
                card.widthAnchor.constraint(equalToConstant: Self.cardWidth).isActive = true
                card.heightAnchor.constraint(equalToConstant: cardHeight).isActive = true
                rowStack.addArrangedSubview(card)
                cardViews.append(card)
            }

            gridStack.addArrangedSubview(rowStack)
        }

        return gridStack
    }

    private static func spaceName(for space: SpaceInfo) -> String {
        if space.isNativeFullscreen, let app = space.apps.first {
            app.appName
        } else if !space.label.isEmpty {
            space.label
        } else {
            "Desktop \(space.index)"
        }
    }

    private func makeViewModel(for space: SpaceInfo, at index: Int, isSelected: Bool) -> SpaceCardViewModel {
        let displayApps = Array(space.apps.prefix(SpaceCardView.maxApps))
        let extra = max(0, space.apps.count - SpaceCardView.maxApps)
        let spaceName = Self.spaceName(for: space)
        let shortcutKey = space.hasFocus ? "ESC" : (index < shortcutKeys.count ? shortcutKeys[index] : nil)
        // 背景ハイライトは「この論理ディスプレイのアクティブスペース」基準。
        // グローバルフォーカスが他論理にある場合も、今見ている論理のアクティブスペースをハイライトする。
        let isCurrent = activeSpaceUUID.map { space.uuid == $0 } ?? space.hasFocus

        return SpaceCardViewModel(
            spaceIndex: space.index,
            spaceName: spaceName,
            shortcutKey: shortcutKey,
            isCurrent: isCurrent,
            isSelected: isSelected,
            isFullscreen: space.isNativeFullscreen,
            thumbnail: space.thumbnail,
            wallpaper: space.wallpaper,
            apps: displayApps,
            allApps: space.apps,
            extraAppCount: extra,
            isSelectable: isSelectable(at: index)
        )
    }

    private func fullscreenIndexForKey(keyCode: UInt16) -> Int? {
        let keyChar = Self.keyCodeToChar(keyCode)
        guard let keyChar else { return nil }
        let keyStr = String(keyChar)
        for index in spaces.indices where shortcutKeys[index] == keyStr {
            return index
        }
        return nil
    }

    private static func keyCodeToChar(_ keyCode: UInt16) -> Character? {
        // 日本語IME等ではレイアウトデータがないため、ASCII capable な入力ソースにフォールバック
        let layoutData: UnsafeMutableRawPointer? = {
            let src = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
            if let data = TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData) {
                return data
            }
            let asciiSrc = TISCopyCurrentASCIICapableKeyboardLayoutInputSource().takeRetainedValue()
            return TISGetInputSourceProperty(asciiSrc, kTISPropertyUnicodeKeyLayoutData)
        }()
        guard let layoutData else { return nil }
        let data = unsafeBitCast(layoutData, to: CFData.self) as Data
        return data.withUnsafeBytes { rawBuf -> Character? in
            guard let ptr = rawBuf.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return nil
            }
            var deadKeyState: UInt32 = 0
            var length = 0
            var chars = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(
                ptr, keyCode, UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
                UInt32(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, chars.count, &length, &chars
            )
            guard status == noErr, length > 0 else { return nil }
            return Character(String(utf16CodeUnits: chars, count: length).uppercased())
        }
    }

    private func centerOnScreen(_ panel: NSPanel, on target: NSScreen? = nil) {
        guard let screen = target ?? NSScreen.main else { return }
        let screenFrame = screen.frame
        let panelFrame = panel.frame
        // 背景部分（overflowMargin を除いた上部）を画面中央に配置する
        let visibleHeight = panelFrame.height - Self.overflowMargin
        let originX = screenFrame.midX - panelFrame.width / 2
        let originY = screenFrame.midY - visibleHeight / 2 - Self.overflowMargin
        panel.setFrameOrigin(NSPoint(x: originX, y: originY))
    }
}

// MARK: - Array Extension

private extension Array {
    func chunked(by size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
