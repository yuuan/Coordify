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

    private func logicalKey(_ s: String) -> LogicalDisplayKey {
        LogicalDisplayKey.representing(PhysicalDisplayUUID(s))
    }

    // MARK: - moveSpaceToNextLogicalDisplay

    func testMoveSpace_cyclesToNextDisplay() throws {
        let displays = [logicalKey("uuid-A"), logicalKey("uuid-B"), logicalKey("uuid-C")]
        var mapping = DisplayMapping()
        mapping.spacesByUUID["space-1"] = SpaceEntry(display: logicalKey("uuid-A"), index: 1)
        fileClient.loadResult = .success(mapping)

        try adapter.moveSpaceToNextLogicalDisplay(spaceUUID: "space-1", logicalDisplayKeys: displays)

        XCTAssertEqual(fileClient.savedMapping?.spacesByUUID["space-1"]?.display, logicalKey("uuid-B"))
    }

    func testMoveSpace_wrapsAroundToFirstDisplay() throws {
        let displays = [logicalKey("uuid-A"), logicalKey("uuid-B"), logicalKey("uuid-C")]
        var mapping = DisplayMapping()
        mapping.spacesByUUID["space-1"] = SpaceEntry(display: logicalKey("uuid-C"), index: 1)
        fileClient.loadResult = .success(mapping)

        try adapter.moveSpaceToNextLogicalDisplay(spaceUUID: "space-1", logicalDisplayKeys: displays)

        XCTAssertEqual(fileClient.savedMapping?.spacesByUUID["space-1"]?.display, logicalKey("uuid-A"))
    }

    func testMoveSpace_newSpaceDefaultsToSecondDisplay() throws {
        let displays = [logicalKey("uuid-A"), logicalKey("uuid-B")]
        fileClient.loadResult = .success(DisplayMapping())

        try adapter.moveSpaceToNextLogicalDisplay(spaceUUID: "space-new", logicalDisplayKeys: displays)

        // 新規スペースは first がデフォルト → 次は second
        XCTAssertEqual(fileClient.savedMapping?.spacesByUUID["space-new"]?.display, logicalKey("uuid-B"))
    }

    func testMoveSpace_singleDisplay_staysOnSame() throws {
        let displays = [logicalKey("uuid-A")]
        var mapping = DisplayMapping()
        mapping.spacesByUUID["space-1"] = SpaceEntry(display: logicalKey("uuid-A"), index: 1)
        fileClient.loadResult = .success(mapping)

        try adapter.moveSpaceToNextLogicalDisplay(spaceUUID: "space-1", logicalDisplayKeys: displays)

        XCTAssertEqual(fileClient.savedMapping?.spacesByUUID["space-1"]?.display, logicalKey("uuid-A"))
    }

    func testMoveSpace_unknownDisplay_goesToSecond() throws {
        let displays = [logicalKey("uuid-A"), logicalKey("uuid-B")]
        var mapping = DisplayMapping()
        mapping.spacesByUUID["space-1"] = SpaceEntry(display: logicalKey("uuid-GONE"), index: 1)
        fileClient.loadResult = .success(mapping)

        try adapter.moveSpaceToNextLogicalDisplay(spaceUUID: "space-1", logicalDisplayKeys: displays)

        XCTAssertEqual(fileClient.savedMapping?.spacesByUUID["space-1"]?.display, logicalKey("uuid-B"))
    }

    func testMoveSpace_preservesIndex() throws {
        let displays = [logicalKey("uuid-A"), logicalKey("uuid-B")]
        var mapping = DisplayMapping()
        mapping.spacesByUUID["space-1"] = SpaceEntry(display: logicalKey("uuid-A"), index: 3)
        fileClient.loadResult = .success(mapping)

        try adapter.moveSpaceToNextLogicalDisplay(spaceUUID: "space-1", logicalDisplayKeys: displays)

        XCTAssertEqual(fileClient.savedMapping?.spacesByUUID["space-1"]?.index, 3)
    }

    func testMoveSpace_doesNotAffectOtherSpaces() throws {
        let displays = [logicalKey("uuid-A"), logicalKey("uuid-B")]
        var mapping = DisplayMapping()
        mapping.spacesByUUID["space-1"] = SpaceEntry(display: logicalKey("uuid-A"), index: 1)
        mapping.spacesByUUID["space-2"] = SpaceEntry(display: logicalKey("uuid-B"), index: 2)
        fileClient.loadResult = .success(mapping)

        try adapter.moveSpaceToNextLogicalDisplay(spaceUUID: "space-1", logicalDisplayKeys: displays)

        XCTAssertEqual(fileClient.savedMapping?.spacesByUUID["space-2"]?.display, logicalKey("uuid-B"))
    }

    // MARK: - loadMapping

    func testLoadMapping_returnsFromClient() throws {
        var mapping = DisplayMapping()
        mapping.spacesByUUID["s1"] = SpaceEntry(display: logicalKey("d1"), index: 1)
        fileClient.loadResult = .success(mapping)

        let loaded = try adapter.loadMapping()
        XCTAssertEqual(loaded.spacesByUUID["s1"]?.display, logicalKey("d1"))
    }

    // MARK: - queryDisplayUUIDs

    func testQueryDisplayUUIDs_returnsUUIDsInOrder() async throws {
        yabai.displayQueryResult = [
            YabaiDisplayResponse(id: 1, uuid: PhysicalDisplayUUID("uuid-A"), index: 1, spaces: [1, 2]),
            YabaiDisplayResponse(id: 2, uuid: PhysicalDisplayUUID("uuid-B"), index: 2, spaces: [3]),
        ]

        let uuids = try await adapter.queryDisplayUUIDs()
        XCTAssertEqual(uuids, [PhysicalDisplayUUID("uuid-A"), PhysicalDisplayUUID("uuid-B")])
    }

    func testQueryDisplayUUIDs_emptyDisplays() async throws {
        yabai.displayQueryResult = []

        let uuids = try await adapter.queryDisplayUUIDs()
        XCTAssertTrue(uuids.isEmpty)
    }
}
