import XCTest
@testable import Coordify

// MARK: - Mocks

final class MockYabaiClient: YabaiClientProtocol {
    var isAvailable = true
    var spacesResult: Result<[YabaiSpaceResponse], Error> = .success([])
    var focusSpaceCallCount = 0
    var focusSpaceLastIndex: Int?
    var focusSpaceError: Error?
    var displayQueryResult: [YabaiDisplayResponse] = []

    func querySpaces() async throws -> [YabaiSpaceResponse] {
        try spacesResult.get()
    }

    func focusSpace(index: Int) async throws {
        focusSpaceCallCount += 1
        focusSpaceLastIndex = index
        if let error = focusSpaceError {
            throw error
        }
    }

    func focusDisplay(index: Int) async throws {}

    func queryDisplays() async throws -> [YabaiDisplayResponse] {
        displayQueryResult
    }
}

final class MockKeyboardClient: KeyEventEmitterProtocol {
    var sendCtrlNumberCallCount = 0
    var sendCtrlNumberLastNumber: Int?

    func sendCtrlNumber(_ number: Int) {
        sendCtrlNumberCallCount += 1
        sendCtrlNumberLastNumber = number
    }
}

// MARK: - Tests

final class SpaceAdapterTests: XCTestCase {
    private var yabai: MockYabaiClient!
    private var keyboard: MockKeyboardClient!
    private var adapter: SpaceAdapter!

    override func setUp() {
        yabai = MockYabaiClient()
        keyboard = MockKeyboardClient()
        adapter = SpaceAdapter(yabai: yabai, keyboard: keyboard)
    }

    // MARK: - isAvailable

    func testIsAvailable_delegatesToYabai() {
        yabai.isAvailable = true
        XCTAssertTrue(adapter.isAvailable)

        yabai.isAvailable = false
        XCTAssertFalse(adapter.isAvailable)
    }

    // MARK: - querySpaces

    func testQuerySpaces_mapsYabaiResponseToSpaceQueryResult() async throws {
        yabai.spacesResult = .success([
            YabaiSpaceResponse(
                id: 1, uuid: "AAA", index: 1, label: "Work",
                type: "bsp", display: 1, windows: [100, 200],
                isVisible: true, isNativeFullscreen: false, hasFocus: true
            ),
            YabaiSpaceResponse(
                id: 2, uuid: "BBB", index: 2, label: "",
                type: "bsp", display: 1, windows: [],
                isVisible: false, isNativeFullscreen: false, hasFocus: false
            ),
        ])

        let results = try await adapter.querySpaces()
        XCTAssertEqual(results.count, 2)

        XCTAssertEqual(results[0].uuid, "AAA")
        XCTAssertEqual(results[0].label, "Work")
        XCTAssertEqual(results[0].physicalDisplayIndex, PhysicalDisplayIndex(1))
        XCTAssertTrue(results[0].hasFocus)
        XCTAssertEqual(results[0].windowIDs, [100, 200])

        XCTAssertEqual(results[1].uuid, "BBB")
        XCTAssertFalse(results[1].hasFocus)
    }

    func testQuerySpaces_propagatesError() async {
        yabai.spacesResult = .failure(YabaiClientError.notInstalled)

        do {
            _ = try await adapter.querySpaces()
            XCTFail("Expected error")
        } catch {
            XCTAssertTrue(error is YabaiClientError)
        }
    }

    // MARK: - focusSpace

    func testFocusSpace_usesYabaiWhenSuccessful() async throws {
        try await adapter.focusSpace(desktopNumber: 3)

        XCTAssertEqual(yabai.focusSpaceCallCount, 1)
        XCTAssertEqual(yabai.focusSpaceLastIndex, 3)
        XCTAssertEqual(keyboard.sendCtrlNumberCallCount, 0)
    }

    func testFocusSpace_fallsBackToKeyboardOnYabaiError() async throws {
        yabai.focusSpaceError = YabaiClientError.commandFailed("scripting-addition error")

        try await adapter.focusSpace(desktopNumber: 5)

        XCTAssertEqual(yabai.focusSpaceCallCount, 1)
        XCTAssertEqual(keyboard.sendCtrlNumberCallCount, 1)
        XCTAssertEqual(keyboard.sendCtrlNumberLastNumber, 5)
    }
}
