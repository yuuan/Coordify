import AppKit
import ScreenCaptureKit

/// スペースごとのサムネイル画像を提供するキャッシュ
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private var thumbnailsBySpaceUUID: [String: CGImage] = [:]
    private let lock = NSLock()

    private init() {}

    // MARK: - Public API

    /// WindowCapturable を使ってウィンドウのスクショを取得し、壁紙と合成してキャッシュ
    func captureWindow(
        _ windowID: CGWindowID,
        capturer: WindowCapturable,
        wallpaper: NSImage?,
        spaceUUID: String,
        fullscreen: Bool = false,
        windowScale: CGFloat = 0.6
    ) {
        guard let windowImage = capturer.captureWindow(windowID) else { return }
        let image = fullscreen
            ? windowImage
            : compositeOnWallpaper(windowImage: windowImage, wallpaper: wallpaper, scale: windowScale)
        lock.lock()
        thumbnailsBySpaceUUID[spaceUUID] = image
        lock.unlock()
    }

    /// ScreenCaptureKit で現在のディスプレイ全体をキャプチャ（フォールバック用）
    func captureCurrentSpace(spaceUUID: String) async {
        guard await hasScreenRecordingPermission() else { return }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else { return }

            let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
            let config = SCStreamConfiguration()
            config.width = 400
            config.height = 250
            config.showsCursor = false

            if #available(macOS 14.0, *) {
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                lock.withLock { thumbnailsBySpaceUUID[spaceUUID] = image }
            } else {
                let image = try await captureViaStream(filter: filter, config: config)
                if let image {
                    lock.withLock { thumbnailsBySpaceUUID[spaceUUID] = image }
                }
            }
        } catch {
            NSLog("ThumbnailCache capture failed: %@", error.localizedDescription)
        }
    }

    /// キャッシュからサムネイル画像を取得する
    /// - Parameter spaceUUID: 対象スペースのUUID
    /// - Returns: キャッシュされたサムネイル画像。未キャッシュの場合は nil
    func thumbnail(for spaceUUID: String) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        return thumbnailsBySpaceUUID[spaceUUID]
    }

    /// 指定されたスペースのサムネイルをキャッシュから削除する
    /// - Parameter spaceUUID: 削除対象のスペースUUID
    func evict(spaceUUID: String) {
        lock.lock()
        thumbnailsBySpaceUUID.removeValue(forKey: spaceUUID)
        lock.unlock()
    }

    // MARK: - Wallpaper Compositing

    private static let thumbWidth = 400
    private static let thumbHeight = 250

    /// ウィンドウのスクショを壁紙の中央に合成
    private func compositeOnWallpaper(windowImage: CGImage, wallpaper: NSImage?, scale: CGFloat) -> CGImage {
        let context = CGContext(
            data: nil,
            width: Self.thumbWidth,
            height: Self.thumbHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        )!
        let fullRect = CGRect(x: 0, y: 0, width: Self.thumbWidth, height: Self.thumbHeight)

        drawWallpaperBackground(context: context, wallpaper: wallpaper, rect: fullRect)
        drawWindowImage(context: context, windowImage: windowImage, canvasSize: fullRect.size, scale: scale)

        return context.makeImage()!
    }

    private func drawWallpaperBackground(context: CGContext, wallpaper: NSImage?, rect: CGRect) {
        if let wallpaper, let wallpaperCG = wallpaper.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            context.draw(wallpaperCG, in: rect)
        } else {
            context.setFillColor(NSColor.darkGray.cgColor)
            context.fill(rect)
        }
        context.setFillColor(CGColor(gray: 0, alpha: 0.3))
        context.fill(rect)
    }

    private func drawWindowImage(context: CGContext, windowImage: CGImage, canvasSize: CGSize, scale: CGFloat) {
        let maxWidth = canvasSize.width * scale
        let maxHeight = canvasSize.height * scale
        let aspect = CGFloat(windowImage.width) / CGFloat(windowImage.height)

        var drawWidth = maxWidth
        var drawHeight = drawWidth / aspect
        if drawHeight > maxHeight {
            drawHeight = maxHeight
            drawWidth = drawHeight * aspect
        }

        let windowRect = CGRect(
            x: (canvasSize.width - drawWidth) / 2,
            y: (canvasSize.height - drawHeight) / 2,
            width: drawWidth,
            height: drawHeight
        )
        context.setShadow(offset: CGSize(width: 0, height: -2), blur: 8, color: CGColor(gray: 0, alpha: 0.5))
        context.draw(windowImage, in: windowRect)
    }

    // MARK: - Stream-based capture for macOS 13

    private func captureViaStream(filter: SCContentFilter, config: SCStreamConfiguration) async throws -> CGImage? {
        let streamDelegate = ScreenCaptureStreamDelegate()
        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(streamDelegate, type: .screen, sampleHandlerQueue: .global())
        try await stream.startCapture()
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
        try await stream.stopCapture()
        return streamDelegate.capturedImage
    }

    // MARK: - Permission Check

    static var screenRecordingPermitted: Bool?

    private func hasScreenRecordingPermission() async -> Bool {
        if let cached = Self.screenRecordingPermitted {
            return cached
        }
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            Self.screenRecordingPermitted = true
            return true
        } catch {
            Self.screenRecordingPermitted = false
            return false
        }
    }
}

// MARK: - SCStreamOutput for macOS 13 fallback

/// macOS 13 向けに SCStream からフレームを受け取る SCStreamOutput 実装
private final class ScreenCaptureStreamDelegate: NSObject, SCStreamOutput {
    var capturedImage: CGImage?

    func stream(_: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard capturedImage == nil, type == .screen else { return }
        guard let imageBuffer = sampleBuffer.imageBuffer else { return }
        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        let context = CIContext()
        let width = CVPixelBufferGetWidth(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        capturedImage = context.createCGImage(ciImage, from: rect)
    }
}
