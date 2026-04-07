import CoreGraphics

/// 個別ウィンドウのスクリーンショット取得能力を表すインターフェース
protocol WindowCapturable {
    /// 指定されたウィンドウIDのスクリーンショットを取得する
    /// - Parameter windowID: キャプチャ対象のウィンドウID
    /// - Returns: キャプチャされた画像。失敗時は nil
    func captureWindow(_ windowID: CGWindowID) -> CGImage?
}
