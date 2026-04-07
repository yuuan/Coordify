import Foundation

/// 論理ディスプレイごとに最後に表示していたスペースを記録するモデル
struct SpaceHistory: Codable {
    /// 論理ディスプレイ → 最後に visible だったスペース UUID
    var lastActiveSpaceByDisplay: [LogicalDisplayKey: String] = [:]
    /// 記録日時 (ISO 8601)
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case lastActiveSpaceByDisplay = "lastActive"
        case updatedAt
    }
}
