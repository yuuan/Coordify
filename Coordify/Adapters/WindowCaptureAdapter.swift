import CoreGraphics

/// 個別ウィンドウのスクリーンショット取得を提供するアダプター
final class WindowCaptureAdapter: WindowCapturable {
    private let skyLight: SkyLightClientProtocol

    init(skyLight: SkyLightClientProtocol = SkyLightClient.shared) {
        self.skyLight = skyLight
    }

    /// 指定されたウィンドウのスクリーンショットを取得する
    /// - Parameter windowID: キャプチャ対象のウィンドウID
    /// - Returns: キャプチャされた画像。失敗時は nil
    func captureWindow(_ windowID: CGWindowID) -> CGImage? {
        skyLight.captureWindow(windowID)
    }
}
