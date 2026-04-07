import Foundation

/// 論理ディスプレイの値表現
/// Coordify がスイッチャーのパネル単位として扱うディスプレイ。
/// 接続中でも切断中でも同じ型で扱えるため、UI 側は `physical` の有無だけを見れば
/// 「今つながっているディスプレイか、過去に繋いでいたディスプレイか」を判別できる。
struct LogicalDisplay: Identifiable {
    /// パネル表示順 (1 が現在アクティブな物理ディスプレイ、2 以降は追加・仮想)
    let id: LogicalDisplayID
    /// 永続識別子 (物理 UUID を論理として扱うための値型)
    let key: LogicalDisplayKey
    /// 表示名 (接続中は物理ディスプレイ名、切断中は保存された名前)
    let name: String
    /// 現在接続されている物理ディスプレイ情報。nil なら切断中
    let physical: PhysicalDisplay?
    /// この論理ディスプレイに属するスペース一覧
    let spaces: [SpaceInfo]

    var isConnected: Bool {
        physical != nil
    }
}
