import XCTest
@testable import Coordify

// MARK: - Mock

final class MockSkyLightClient: SkyLightClientProtocol {
    var capturedWindowID: CGWindowID?
    var captureResult: CGImage?

    func captureWindow(_ windowID: CGWindowID) -> CGImage? {
        capturedWindowID = windowID
        return captureResult
    }
}

// MARK: - Tests

final class WindowCaptureAdapterTests: XCTestCase {
    private var skyLight: MockSkyLightClient!
    private var adapter: WindowCaptureAdapter!

    override func setUp() {
        skyLight = MockSkyLightClient()
        adapter = WindowCaptureAdapter(skyLight: skyLight)
    }

    func testCaptureWindow_delegatesToSkyLight() {
        let testImage = createTestImage()
        skyLight.captureResult = testImage

        let result = adapter.captureWindow(42)

        XCTAssertEqual(skyLight.capturedWindowID, 42)
        XCTAssertNotNil(result)
    }

    func testCaptureWindow_returnsNilWhenSkyLightFails() {
        skyLight.captureResult = nil

        let result = adapter.captureWindow(99)

        XCTAssertEqual(skyLight.capturedWindowID, 99)
        XCTAssertNil(result)
    }

    private func createTestImage() -> CGImage {
        let context = CGContext(
            data: nil, width: 1, height: 1,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        )!
        return context.makeImage()!
    }
}
