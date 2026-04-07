import Foundation

/// 物理ディスプレイ (現在接続されているもの) の値表現
struct PhysicalDisplay: Equatable {
    /// yabai の 1-based 物理ディスプレイ番号
    let index: PhysicalDisplayIndex
    /// CGDisplay 由来の UUID
    let uuid: PhysicalDisplayUUID
    /// 表示名 (NSScreen.localizedName)
    let name: String
    /// MacBook 本体内蔵ディスプレイかどうか
    let isBuiltIn: Bool
}
