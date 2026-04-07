import Carbon.HIToolbox
import CoreGraphics

/// Mission Control ショートカット（Ctrl+数字）のキーイベントを合成して送信するエミッター
final class KeyEventEmitter: KeyEventEmitterProtocol {
    static let shared = KeyEventEmitter()

    /// Ctrl+数字キーを送信する
    func sendCtrlNumber(_ number: Int) {
        guard let keyCode = ShortcutKeyRule.desktopShortcuts[number].map({ UInt16($0.keyCode) }) else { return }
        postCtrlKey(keyCode: keyCode)
    }

    /// Ctrl+←/→ を送信する（macOS 標準「前/次のスペースへ移動」）
    func sendCtrlArrow(direction: HotkeyInterceptor.Direction) {
        let keyCode: UInt16 = direction == .left ? UInt16(kVK_LeftArrow) : UInt16(kVK_RightArrow)
        postCtrlKey(keyCode: keyCode)
    }

    private func postCtrlKey(keyCode: UInt16) {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyDown?.flags = .maskControl
        keyUp?.flags = .maskControl
        keyDown?.post(tap: CGEventTapLocation.cgSessionEventTap)
        keyUp?.post(tap: CGEventTapLocation.cgSessionEventTap)
    }
}
