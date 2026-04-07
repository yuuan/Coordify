import XCTest
@testable import Coordify

// MARK: - Mock

final class MockConfigFileClient: ConfigFileClientProtocol {
    var savedConfig: Config?
    var loadResult: Result<Config, Error> = .success(Config())

    func load() throws -> Config {
        try loadResult.get()
    }

    func save(_ config: Config) throws {
        savedConfig = config
    }
}

// MARK: - Tests

final class ConfigAdapterTests: XCTestCase {
    private var client: MockConfigFileClient!
    private var adapter: ConfigAdapter!

    override func setUp() {
        client = MockConfigFileClient()
        adapter = ConfigAdapter(client: client)
    }

    func testLoad_returnsConfigFromClient() throws {
        var config = Config()
        config.spaceLabels = ["uuid1": "Work"]
        client.loadResult = .success(config)

        let loaded = try adapter.load()
        XCTAssertEqual(loaded.spaceLabels["uuid1"], "Work")
    }

    func testLoad_propagatesError() {
        client.loadResult = .failure(NSError(domain: "test", code: 1))

        XCTAssertThrowsError(try adapter.load())
    }

    func testSave_passesConfigToClient() throws {
        var config = Config()
        config.spaceLabels = ["uuid2": "Personal"]

        try adapter.save(config)
        XCTAssertEqual(client.savedConfig?.spaceLabels["uuid2"], "Personal")
    }
}
