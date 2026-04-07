import AppKit
import XCTest
@testable import Coordify

private final class MockWindowCapturer: WindowCapturable {
    var captureResult: CGImage?

    func captureWindow(_: CGWindowID) -> CGImage? {
        captureResult
    }
}

final class ThumbnailCacheTests: XCTestCase {
    // MARK: - Helpers

    private func createTestImage(width: Int, height: Int) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        )!
        context.setFillColor(NSColor.red.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    // MARK: - captureWindow + thumbnail

    func testCaptureWindow_cachesImage() {
        let cache = ThumbnailCache.shared
        let mockCapturer = MockWindowCapturer()
        mockCapturer.captureResult = createTestImage(width: 100, height: 100)

        cache.captureWindow(1, capturer: mockCapturer, wallpaper: nil, spaceUUID: "test-cache")
        XCTAssertNotNil(cache.thumbnail(for: "test-cache"))

        cache.evict(spaceUUID: "test-cache")
    }

    func testCaptureWindow_nilWhenCaptureFails() {
        let cache = ThumbnailCache.shared
        let mockCapturer = MockWindowCapturer()
        mockCapturer.captureResult = nil

        cache.captureWindow(1, capturer: mockCapturer, wallpaper: nil, spaceUUID: "test-nil")
        XCTAssertNil(cache.thumbnail(for: "test-nil"))
    }

    func testEvict_removesCachedImage() {
        let cache = ThumbnailCache.shared
        let mockCapturer = MockWindowCapturer()
        mockCapturer.captureResult = createTestImage(width: 100, height: 100)

        cache.captureWindow(1, capturer: mockCapturer, wallpaper: nil, spaceUUID: "test-evict")
        XCTAssertNotNil(cache.thumbnail(for: "test-evict"))

        cache.evict(spaceUUID: "test-evict")
        XCTAssertNil(cache.thumbnail(for: "test-evict"))
    }

    // MARK: - Compositing output size

    func testCaptureWindow_producesCorrectSize() {
        let cache = ThumbnailCache.shared
        let mockCapturer = MockWindowCapturer()
        mockCapturer.captureResult = createTestImage(width: 800, height: 600)

        let wallpaper = NSImage(size: NSSize(width: 1920, height: 1080))

        cache.captureWindow(1, capturer: mockCapturer, wallpaper: wallpaper, spaceUUID: "test-size")
        let result = cache.thumbnail(for: "test-size")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.width, 400)
        XCTAssertEqual(result?.height, 250)

        cache.evict(spaceUUID: "test-size")
    }

    func testCaptureWindow_fullscreenSkipsCompositing() {
        let cache = ThumbnailCache.shared
        let mockCapturer = MockWindowCapturer()
        let originalImage = createTestImage(width: 200, height: 150)
        mockCapturer.captureResult = originalImage

        cache.captureWindow(1, capturer: mockCapturer, wallpaper: nil, spaceUUID: "test-fs", fullscreen: true)
        let result = cache.thumbnail(for: "test-fs")

        // フルスクリーンはそのまま保存されるため元サイズ
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.width, 200)
        XCTAssertEqual(result?.height, 150)

        cache.evict(spaceUUID: "test-fs")
    }

    func testCaptureWindow_noWallpaperUsesGrayBackground() {
        let cache = ThumbnailCache.shared
        let mockCapturer = MockWindowCapturer()
        mockCapturer.captureResult = createTestImage(width: 100, height: 100)

        cache.captureWindow(1, capturer: mockCapturer, wallpaper: nil, spaceUUID: "test-no-wp")
        let result = cache.thumbnail(for: "test-no-wp")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.width, 400)
        XCTAssertEqual(result?.height, 250)

        cache.evict(spaceUUID: "test-no-wp")
    }
}
