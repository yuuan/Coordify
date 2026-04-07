import XCTest
@testable import Coordify

// MARK: - Mock

final class MockDisplayMappingFileClient: DisplayMappingFileClientProtocol {
    var savedMapping: DisplayMapping?
    var loadResult: Result<DisplayMapping, Error> = .success(DisplayMapping())

    func load() throws -> DisplayMapping {
        try loadResult.get()
    }

    func save(_ mapping: DisplayMapping) throws {
        savedMapping = mapping
    }
}

// MARK: - Tests

final class DisplayMappingAdapterTests: XCTestCase {
    private var fileClient: MockDisplayMappingFileClient!
    private var yabai: MockYabaiClient!
    private var adapter: DisplayMappingAdapter!

    override func setUp() {
        fileClient = MockDisplayMappingFileClient()
        yabai = MockYabaiClient()
        adapter = DisplayMappingAdapter(yabai: yabai, fileClient: fileClient)
    }

    // MARK: - moveSpaceToNextDisplay

    func testMoveSpace_cyclesToNextDisplay() throws {
        let displays = ["uuid-A", "uuid-B", "uuid-C"]
        var mapping = DisplayMapping()
        mapping.spacesByUUID["space-1"] = SpaceEntry(display: "uuid-A", index: 1)
        fileClient.loadResult = .success(mapping)

        try adapter.moveSpaceToNextDisplay(spaceUUID: "space-1", displayUUIDs: displays)

        XCTAssertEqual(fileClient.savedMapping?.spacesByUUID["space-1"]?.display, "uuid-B")
    }

    func testMoveSpace_wrapsAroundToFirstDisplay() throws {
        let displays = ["uuid-A", "uuid-B", "uuid-C"]
        var mapping = DisplayMapping()
        mapping.spacesByUUID["space-1"] = SpaceEntry(display: "uuid-C", index: 1)
        fileClient.loadResult = .success(mapping)

        try adapter.moveSpaceToNextDisplay(spaceUUID: "space-1", displayUUIDs: displays)

        XCTAssertEqual(fileClient.savedMapping?.spacesByUUID["space-1"]?.display, "uuid-A")
    }

    func testMoveSpace_newSpaceDefaultsToSecondDisplay() throws {
        let displays = ["uuid-A", "uuid-B"]
        fileClient.loadResult = .success(DisplayMapping())

        try adapter.moveSpaceToNextDisplay(spaceUUID: "space-new", displayUUIDs: displays)

        // 新規スペースは first がデフォルト → 次は second
        XCTAssertEqual(fileClient.savedMapping?.spacesByUUID["space-new"]?.display, "uuid-B")
    }

    func testMoveSpace_singleDisplay_staysOnSame() throws {
        let displays = ["uuid-A"]
        var mapping = DisplayMapping()
        mapping.spacesByUUID["space-1"] = SpaceEntry(display: "uuid-A", index: 1)
        fileClient.loadResult = .success(mapping)

        try adapter.moveSpaceToNextDisplay(spaceUUID: "space-1", displayUUIDs: displays)

        XCTAssertEqual(fileClient.savedMapping?.spacesByUUID["space-1"]?.display, "uuid-A")
    }

    func testMoveSpace_unknownDisplay_goesToSecond() throws {
        let displays = ["uuid-A", "uuid-B"]
        var mapping = DisplayMapping()
        mapping.spacesByUUID["space-1"] = SpaceEntry(display: "uuid-GONE", index: 1)
        fileClient.loadResult = .success(mapping)

        try adapter.moveSpaceToNextDisplay(spaceUUID: "space-1", displayUUIDs: displays)

        XCTAssertEqual(fileClient.savedMapping?.spacesByUUID["space-1"]?.display, "uuid-B")
    }

    func testMoveSpace_preservesIndex() throws {
        let displays = ["uuid-A", "uuid-B"]
        var mapping = DisplayMapping()
        mapping.spacesByUUID["space-1"] = SpaceEntry(display: "uuid-A", index: 3)
        fileClient.loadResult = .success(mapping)

        try adapter.moveSpaceToNextDisplay(spaceUUID: "space-1", displayUUIDs: displays)

        XCTAssertEqual(fileClient.savedMapping?.spacesByUUID["space-1"]?.index, 3)
    }

    func testMoveSpace_doesNotAffectOtherSpaces() throws {
        let displays = ["uuid-A", "uuid-B"]
        var mapping = DisplayMapping()
        mapping.spacesByUUID["space-1"] = SpaceEntry(display: "uuid-A", index: 1)
        mapping.spacesByUUID["space-2"] = SpaceEntry(display: "uuid-B", index: 2)
        fileClient.loadResult = .success(mapping)

        try adapter.moveSpaceToNextDisplay(spaceUUID: "space-1", displayUUIDs: displays)

        XCTAssertEqual(fileClient.savedMapping?.spacesByUUID["space-2"]?.display, "uuid-B")
    }

    // MARK: - loadMapping

    func testLoadMapping_returnsFromClient() throws {
        var mapping = DisplayMapping()
        mapping.spacesByUUID["s1"] = SpaceEntry(display: "d1", index: 1)
        fileClient.loadResult = .success(mapping)

        let loaded = try adapter.loadMapping()
        XCTAssertEqual(loaded.spacesByUUID["s1"]?.display, "d1")
    }

    // MARK: - queryDisplayUUIDs

    func testQueryDisplayUUIDs_returnsUUIDsInOrder() async throws {
        yabai.displayQueryResult = [
            YabaiDisplayResponse(id: 1, uuid: "uuid-A", index: 1, spaces: [1, 2]),
            YabaiDisplayResponse(id: 2, uuid: "uuid-B", index: 2, spaces: [3]),
        ]

        let uuids = try await adapter.queryDisplayUUIDs()
        XCTAssertEqual(uuids, ["uuid-A", "uuid-B"])
    }

    func testQueryDisplayUUIDs_emptyDisplays() async throws {
        yabai.displayQueryResult = []

        let uuids = try await adapter.queryDisplayUUIDs()
        XCTAssertTrue(uuids.isEmpty)
    }
}
