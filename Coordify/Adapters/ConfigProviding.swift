import Foundation

/// アプリ設定の読み書き能力を表すインターフェース
protocol ConfigLoadable {
    /// 永続化された設定を読み込む
    /// - Returns: 読み込まれた設定
    func load() throws -> Config

    /// 設定を永続化する
    /// - Parameter config: 保存する設定
    func save(_ config: Config) throws
}
