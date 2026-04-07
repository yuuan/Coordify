import Foundation

/// スペース一覧の取得能力を表すインターフェース
protocol SpaceQueryable {
    var isAvailable: Bool { get }
    /// 全スペースの情報を問い合わせる
    /// - Returns: スペース情報の配列
    func querySpaces() async throws -> [SpaceQueryResult]
}

/// スペース問い合わせの結果を保持する構造体
struct SpaceQueryResult {
    let id: Int
    let uuid: String
    let index: Int
    let label: String
    let physicalDisplayIndex: PhysicalDisplayIndex
    let isVisible: Bool
    let hasFocus: Bool
    let isNativeFullscreen: Bool
    let windowIDs: [Int]
}
