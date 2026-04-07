import Foundation

/// Coordify のユーザー設定を表すモデル
struct Config: Codable {
    var spaceLabels: [String: String] = [:]
    var appAssignments: [AppAssignment] = []
    var displayLayouts: [DisplayLayout] = []
}

/// アプリケーションをスペースに割り当てるための設定
struct AppAssignment: Codable {
    let bundleIdentifier: String
    let spaceLabel: String
}

/// ディスプレイごとのスペース配置レイアウト
struct DisplayLayout: Codable {
    let displayCount: Int
    let spaceArrangement: [String]
}
