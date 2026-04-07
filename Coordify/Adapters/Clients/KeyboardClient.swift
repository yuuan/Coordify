import CoreGraphics

/// Mission Control ショートカット（Ctrl+数字）のキーイベントを合成して送信するエミッター
final class KeyEventEmitter: KeyEventEmitterProtocol {
    static let shared = KeyEventEmitter()

    /// Ctrl+数字キーを送信する
    func sendCtrlNumber(_ number: Int) {
        guard let keyCode = ShortcutKeyRule.desktopShortcuts[number].map({ UInt16($0.keyCode) }) else { return }

        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyDown?.flags = .maskControl
        keyUp?.flags = .maskControl
        keyDown?.post(tap: CGEventTapLocation.cgSessionEventTap)
        keyUp?.post(tap: CGEventTapLocation.cgSessionEventTap)
    }
}
