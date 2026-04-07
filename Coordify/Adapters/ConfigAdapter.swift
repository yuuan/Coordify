import Foundation

/// アプリ設定の読み書きを提供するアダプター
final class ConfigAdapter: ConfigLoadable {
    private let client: ConfigFileClientProtocol

    init(client: ConfigFileClientProtocol = ConfigFileClient.shared) {
        self.client = client
    }

    /// 永続化された設定を読み込む
    /// - Returns: 読み込まれた設定
    func load() throws -> Config {
        try client.load()
    }

    /// 設定を永続化する
    /// - Parameter config: 保存する設定
    func save(_ config: Config) throws {
        try client.save(config)
    }
}
