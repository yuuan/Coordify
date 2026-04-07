import Foundation

/// アプリ設定の JSON ファイルへの永続化を担うクライアント
final class ConfigFileClient: ConfigFileClientProtocol {
    static let shared = ConfigFileClient()

    private let fileURL: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Coordify", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("config.json")
    }

    /// 設定を JSON ファイルに保存する
    /// - Parameter config: 保存する設定
    func save(_ config: Config) throws {
        let data = try JSONEncoder().encode(config)
        try data.write(to: fileURL, options: .atomic)
    }

    /// JSON ファイルから設定を読み込む（ファイルが存在しない場合はデフォルト設定を返す）
    /// - Returns: 読み込まれた設定
    func load() throws -> Config {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return Config() }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(Config.self, from: data)
    }
}
