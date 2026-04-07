import CoreGraphics

// MARK: - SkyLight Private API Declarations

/// CoreGraphics サーバー接続IDの型エイリアス
typealias CGSConnectionID = UInt32

/// CoreGraphics スペースIDの型エイリアス
typealias CGSSpaceID = UInt64

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> CGSConnectionID

/// ウィンドウキャプチャ時のオプションフラグ
struct CGSWindowCaptureOptions: OptionSet {
    let rawValue: UInt32
    static let ignoreGlobalClipShape = CGSWindowCaptureOptions(rawValue: 1 << 11)
    static let bestResolution = CGSWindowCaptureOptions(rawValue: 1 << 8)
    static let fullSize = CGSWindowCaptureOptions(rawValue: 1 << 19)
}

@_silgen_name("CGSHWCaptureWindowList")
func CGSHWCaptureWindowList(
    _ cid: CGSConnectionID,
    _ windowList: UnsafeMutablePointer<CGWindowID>,
    _ windowCount: UInt32,
    _ options: CGSWindowCaptureOptions
) -> Unmanaged<CFArray>
