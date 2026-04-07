import Foundation

/// スペースとディスプレイの対応関係を永続化するためのモデル
struct DisplayMapping: Codable {
    /// スペース UUID → スペース情報
    var spacesByUUID: [String: SpaceEntry] = [:]
    /// 物理ディスプレイ UUID → ディスプレイ情報
    var displaysByUUID: [PhysicalDisplayUUID: DisplayEntry] = [:]
    /// 記録日時
    var recordedAt: String?

    enum CodingKeys: String, CodingKey {
        case spacesByUUID = "spaces"
        case displaysByUUID = "displays"
        case recordedAt
    }
}

/// スペースごとの保存情報
struct SpaceEntry: Codable {
    /// そのスペースが所属する論理ディスプレイ
    var display: LogicalDisplayKey
    /// そのディスプレイ内での位置
    var index: Int
}

/// ディスプレイごとの保存情報
struct DisplayEntry: Codable {
    var name: String
    var builtIn: Bool
}
