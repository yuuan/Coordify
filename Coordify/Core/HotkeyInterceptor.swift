import AppKit
import Carbon.HIToolbox
import os.log

private let logger = Logger(subsystem: "net.yuuan.Coordify", category: "hotkey")

/// ホットキー操作に応じたスイッチャーの制御を受け取るデリゲート
@MainActor
protocol HotkeyInterceptorDelegate: AnyObject {
    /// スイッチャーの表示がトリガーされた
    func hotkeyInterceptorDidTriggerOpen()
    /// 次のスペースが選択された
    func hotkeyInterceptorDidSelectNext()
    /// 前のスペースが選択された
    func hotkeyInterceptorDidSelectPrevious()
    /// 選択が確定された
    func hotkeyInterceptorDidConfirm()
    /// 選択がキャンセルされた
    func hotkeyInterceptorDidCancel()
    /// 方向キーによるスペース選択
    /// - Parameter direction: 選択方向
    func hotkeyInterceptorDidSelectDirection(_ direction: HotkeyInterceptor.Direction)
}

/// Option+Tab をはじめとするグローバルホットキーを検知してデリゲートに通知するインターセプター
final class HotkeyInterceptor {
    /// スペース選択の方向
    enum Direction {
        case left, right
    }

    weak var delegate: HotkeyInterceptorDelegate?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private(set) var isOptionDown = false
    private(set) var isSwitcherActive = false

    /// 外部からスイッチャー状態をリセットする（スペース切り替え後の dismiss 用）
    /// isOptionDown は物理キー状態を追跡するため、ここではリセットしない
    func resetState() {
        isSwitcherActive = false
    }

    /// CGEventTap を作成してホットキーの監視を開始する
    func start() {
        let eventMask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: hotkeyCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("HotkeyInterceptor: CGEventTap の作成に失敗しました。Accessibility 権限を確認してください。")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        logger.warning("CGEventTap started successfully")
    }

    /// ホットキーの監視を停止し、リソースを解放する
    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
        }
        eventTap = nil
        runLoopSource = nil
        isOptionDown = false
        isSwitcherActive = false
    }

    /// Called from the C callback
    fileprivate func handleEvent(_: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Re-enable tap if it gets disabled by the system
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if type == .flagsChanged {
            return handleFlagsChanged(event)
        }

        if type == .keyDown {
            return handleKeyDown(event)
        }

        return Unmanaged.passUnretained(event)
    }

    private func handleFlagsChanged(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let flags = event.flags
        let optionDown = flags.contains(.maskAlternate)

        if optionDown, !isOptionDown {
            // Option pressed
            isOptionDown = true
            logger.warning("Option DOWN")
        } else if !optionDown, isOptionDown {
            // Option released
            isOptionDown = false
            if isSwitcherActive {
                isSwitcherActive = false
                let delegate = delegate
                Task { @MainActor in
                    delegate?.hotkeyInterceptorDidConfirm()
                }
                return nil // consume the event
            }
        }

        return Unmanaged.passUnretained(event)
    }

    private func handleKeyDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard isOptionDown else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))

        switch keyCode {
        case kVK_Tab:
            return handleTab(event)
        case kVK_Escape:
            return handleEscape()
        case kVK_LeftArrow:
            return handleArrow(.left)
        case kVK_RightArrow:
            return handleArrow(.right)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleTab(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let shiftDown = event.flags.contains(.maskShift)
        let delegate = delegate
        if !isSwitcherActive {
            isSwitcherActive = true
            Task { @MainActor in delegate?.hotkeyInterceptorDidTriggerOpen() }
        } else {
            Task { @MainActor in
                if shiftDown {
                    delegate?.hotkeyInterceptorDidSelectPrevious()
                } else {
                    delegate?.hotkeyInterceptorDidSelectNext()
                }
            }
        }
        return nil
    }

    private func handleEscape() -> Unmanaged<CGEvent>? {
        guard isSwitcherActive else { return Unmanaged.passUnretained(CGEvent(source: nil)!) }
        isSwitcherActive = false
        let delegate = delegate
        Task { @MainActor in delegate?.hotkeyInterceptorDidCancel() }
        return nil
    }

    private func handleArrow(_ direction: Direction) -> Unmanaged<CGEvent>? {
        guard isSwitcherActive else { return Unmanaged.passUnretained(CGEvent(source: nil)!) }
        let delegate = delegate
        Task { @MainActor in delegate?.hotkeyInterceptorDidSelectDirection(direction) }
        return nil
    }
}

/// C-function callback for CGEventTap
private func hotkeyCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let interceptor = Unmanaged<HotkeyInterceptor>.fromOpaque(userInfo).takeUnretainedValue()
    return interceptor.handleEvent(proxy, type: type, event: event)
}
