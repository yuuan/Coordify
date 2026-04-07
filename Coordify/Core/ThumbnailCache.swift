import AppKit
import ScreenCaptureKit

/// スペースごとのサムネイル画像を提供するキャッシュ
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private var thumbnailsBySpaceUUID: [String: CGImage] = [:]
    private let lock = NSLock()

    /// バックグラウンドのサムネ再撮影ジョブ。in-flight + 1 件 pending の coalesce。
    private let refreshQueue = DispatchQueue(
        label: "net.yuuan.Coordify.thumbnail-refresh",
        qos: .utility
    )
    /// pending request があれば保持、なければ nil。refreshQueue 上でのみ読み書き。
    private var pendingRefresh: BackgroundRefreshRequest?
    /// 実行中フラグ。refreshQueue 上でのみ読み書き。
    private var isRefreshing = false

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

    // MARK: - Background refresh

    /// SpaceManager.refresh のクリティカルパスから外して、全スペースのサムネを非同期に取り直す。
    /// in-flight 中に呼ばれても 1 件だけ保留し、古い保留は新しい要求で上書きする。
    func scheduleBackgroundRefresh(
        spaces: [SpaceInfo],
        stickyWindows: Set<Int>,
        windowBounds: [Int: CGRect],
        capturer: WindowCapturable
    ) {
        let request = BackgroundRefreshRequest(
            spaces: spaces,
            stickyWindows: stickyWindows,
            windowBounds: windowBounds,
            capturer: capturer
        )
        refreshQueue.async { [weak self] in
            guard let self else { return }
            if isRefreshing {
                pendingRefresh = request
                return
            }
            executeRefresh(request)
        }
    }

    private func executeRefresh(_ request: BackgroundRefreshRequest) {
        isRefreshing = true
        refreshQueue.async { [weak self] in
            guard let self else { return }
            for space in request.spaces {
                let captureTarget = space.windowIDs.first { wid in
                    !request.stickyWindows.contains(wid)
                }
                guard let firstWindowID = captureTarget else { continue }
                let scale = Self.thumbnailScale(
                    bounds: request.windowBounds[firstWindowID],
                    physicalDisplayIndex: space.physicalDisplayIndex
                )
                captureWindow(
                    CGWindowID(firstWindowID),
                    capturer: request.capturer,
                    wallpaper: space.wallpaper,
                    spaceUUID: space.uuid,
                    fullscreen: space.isNativeFullscreen,
                    windowScale: scale
                )
            }
            let next = pendingRefresh
            pendingRefresh = nil
            isRefreshing = false
            if let next {
                executeRefresh(next)
            }
        }
    }

    /// ウィンドウがディスプレイ可視領域にどれだけ占めるかからサムネ表示倍率を決める。
    /// `visibleFrame` は NSScreen プロパティなので main 外から触らないために nonisolated な経路では
    /// フォールバック（全スクリーンの画面サイズ平均）を使う。ここでは簡易に main の NSScreen を参照するが、
    /// 背景キューから呼ばれるので MainActor 境界では `NSScreen.screens` を直接使うに留め、副作用を避ける。
    nonisolated static func thumbnailScale(
        bounds: CGRect?,
        physicalDisplayIndex: PhysicalDisplayIndex
    ) -> CGFloat {
        guard let bounds else { return 0.6 }
        let screens = NSScreen.screens
        let idx = physicalDisplayIndex.rawValue - 1
        let screen = (idx >= 0 && idx < screens.count) ? screens[idx] : NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return 0.6 }
        let coverage = (bounds.width * bounds.height) / (visibleFrame.width * visibleFrame.height)
        return coverage >= 0.85 ? 0.9 : 0.6
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

// MARK: - Background refresh request

/// ThumbnailCache.scheduleBackgroundRefresh に渡すパラメータの入れ物。
/// 背景キューに載せるため Sendable 相当（NSImage / プロトコル型を含むので @unchecked）。
private struct BackgroundRefreshRequest: @unchecked Sendable {
    let spaces: [SpaceInfo]
    let stickyWindows: Set<Int>
    let windowBounds: [Int: CGRect]
    let capturer: WindowCapturable
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
