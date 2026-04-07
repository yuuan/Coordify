import AppKit
import ServiceManagement

/// メニューバー上の Coordify アイコンとメニューを提供するコントローラー
@MainActor
final class MenuBarController {
    private var statusItem: NSStatusItem?
    private let spaceManager: SpaceManager
    private var yabaiWarning: Bool

    init(spaceManager: SpaceManager, yabaiAvailable: Bool) {
        self.spaceManager = spaceManager
        yabaiWarning = !yabaiAvailable
        setupStatusItem()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "Coordify")
            button.image?.isTemplate = true
        }

        updateMenu()
    }

    /// メニューの内容を現在のスペース情報で更新する
    func updateMenu() {
        let menu = NSMenu()

        // Title
        let titleItem = NSMenuItem(title: "Coordify", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(.separator())

        // Current space
        let currentSpace = spaceManager.spaces.first(where: { $0.hasFocus })
        let spaceName = currentSpace.map { $0.label.isEmpty ? "Desktop \($0.index)" : $0.label } ?? "不明"
        let spaceItem = NSMenuItem(title: "現在の Space: \(spaceName)", action: nil, keyEquivalent: "")
        spaceItem.isEnabled = false
        menu.addItem(spaceItem)

        menu.addItem(.separator())

        // yabai warning
        if yabaiWarning {
            let warningItem = NSMenuItem(title: "⚠ yabai が見つかりません", action: nil, keyEquivalent: "")
            warningItem.isEnabled = false
            menu.addItem(warningItem)
            menu.addItem(.separator())
        }

        // Display mapping
        let mappingItem = NSMenuItem(
            title: "マッピングを編集...",
            action: #selector(openDisplayMapping),
            keyEquivalent: ","
        )
        mappingItem.keyEquivalentModifierMask = .command
        mappingItem.target = self
        menu.addItem(mappingItem)

        menu.addItem(.separator())

        // Launch at Login
        let launchAtLoginItem = NSMenuItem(
            title: "ログイン時に起動",
            action: #selector(toggleLaunchAtLogin(_:)),
            keyEquivalent: ""
        )
        launchAtLoginItem.target = self
        launchAtLoginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(launchAtLoginItem)

        menu.addItem(.separator())

        // Accessibility
        let accessibilityItem = NSMenuItem(
            title: "アクセシビリティ権限を開く...",
            action: #selector(openAccessibilityPreferences),
            keyEquivalent: ""
        )
        accessibilityItem.target = self
        menu.addItem(accessibilityItem)

        menu.addItem(.separator())

        // Quit
        let quitItem = NSMenuItem(title: "終了", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        if SMAppService.mainApp.status == .enabled {
            try? SMAppService.mainApp.unregister()
        } else {
            try? SMAppService.mainApp.register()
        }
        sender.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func openDisplayMapping() {
        NSWorkspace.shared.open(DisplayMappingFileClient.shared.fileURL)
    }

    @objc private func openAccessibilityPreferences() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
