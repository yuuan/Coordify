import Foundation

/// スペース切替履歴の JSON ファイルへの永続化を担うクライアント
final class SpaceHistoryFileClient: SpaceHistoryFileClientProtocol {
    static let shared = SpaceHistoryFileClient()

    let fileURL: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Coordify", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("space-history.json")
    }

    /// スペース履歴を JSON ファイルから読み込む（ファイルが存在しない場合は空の履歴を返す）
    func load() throws -> SpaceHistory {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return SpaceHistory() }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(SpaceHistory.self, from: data)
    }

    /// スペース履歴を JSON ファイルに保存する
    func save(_ history: SpaceHistory) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(history)
        try data.write(to: fileURL, options: .atomic)
    }
}
