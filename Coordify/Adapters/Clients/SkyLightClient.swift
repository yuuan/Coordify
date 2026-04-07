import CoreGraphics

/// SkyLight プライベート API を利用したウィンドウ単体のスクリーンショット取得クライアント
final class SkyLightClient: SkyLightClientProtocol, WindowCapturable {
    static let shared = SkyLightClient()

    private lazy var cgsConnection: CGSConnectionID = CGSMainConnectionID()

    /// SkyLight プライベート API を使用してウィンドウをキャプチャする
    /// - Parameter windowID: キャプチャ対象のウィンドウID
    /// - Returns: キャプチャされた画像。失敗時は nil
    func captureWindow(_ windowID: CGWindowID) -> CGImage? {
        var wid = windowID
        let result = CGSHWCaptureWindowList(
            cgsConnection,
            &wid,
            1,
            [.ignoreGlobalClipShape, .bestResolution]
        )
        let images = result.takeRetainedValue() as? [CGImage]
        return images?.first
    }
}
