import AppKit
import CoreGraphics
import Foundation

/// スペースとディスプレイの対応関係を管理するアダプター
final class DisplayMappingAdapter {
    private let yabai: YabaiClientProtocol
    private let fileClient: DisplayMappingFileClientProtocol

    init(yabai: YabaiClientProtocol = YabaiClient.shared,
         fileClient: DisplayMappingFileClientProtocol = DisplayMappingFileClient.shared)
    {
        self.yabai = yabai
        self.fileClient = fileClient
    }

    /// 現在のスペース配置を物理ディスプレイ UUID と紐づけて保存する
    /// - Parameter spaces: yabai から取得したスペース情報
    func saveCurrentMapping(spaces: [SpaceQueryResult]) async throws {
        let displays = try await yabai.queryDisplays()
        let indexToUUID = Dictionary(uniqueKeysWithValues:
            displays.map { (PhysicalDisplayIndex($0.index), $0.uuid) })

        var mapping = DisplayMapping()
        for space in spaces {
            if let displayUUID = indexToUUID[space.physicalDisplayIndex] {
                // 保存時点では物理ディスプレイが接続されているが、SpaceEntry は将来の切断後に
                // 論理ディスプレイ識別子として参照されるため LogicalDisplayKey で包む
                mapping.spacesByUUID[space.uuid] = SpaceEntry(
                    display: LogicalDisplayKey.representing(displayUUID),
                    index: space.index
                )
            }
        }
        mapping.displaysByUUID = await Self.buildDisplayEntries()
        mapping.recordedAt = Self.iso8601Now()
        try fileClient.save(mapping)
    }

    /// 保存済みのディスプレイマッピングを読み込む
    /// - Returns: 読み込まれたマッピング
    func loadMapping() throws -> DisplayMapping {
        try fileClient.load()
    }

    /// 現在接続されている物理ディスプレイ UUID を取得する
    func queryDisplayUUIDs() async throws -> [PhysicalDisplayUUID] {
        let displays = try await yabai.queryDisplays()
        return displays.map(\.uuid)
    }

    /// NSScreen から 物理ディスプレイ UUID → DisplayEntry の辞書を構築する
    @MainActor
    private static func buildDisplayEntries() -> [PhysicalDisplayUUID: DisplayEntry] {
        var result: [PhysicalDisplayUUID: DisplayEntry] = [:]
        for screen in NSScreen.screens {
            let key = NSDeviceDescriptionKey("NSScreenNumber")
            guard let screenNumber = screen.deviceDescription[key] as? CGDirectDisplayID else {
                continue
            }
            guard let cfUUID = CGDisplayCreateUUIDFromDisplayID(screenNumber)?.takeRetainedValue() else {
                continue
            }
            let uuid = PhysicalDisplayUUID(CFUUIDCreateString(nil, cfUUID) as String)
            let isBuiltIn = CGDisplayIsBuiltin(screenNumber) != 0
            result[uuid] = DisplayEntry(name: screen.localizedName, builtIn: isBuiltIn)
        }
        return result
    }

    private static func iso8601Now() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = .current
        return formatter.string(from: Date())
    }

    /// スペースの所属を次の論理ディスプレイに移動する
    /// - Parameters:
    ///   - spaceUUID: 移動するスペースの UUID
    ///   - logicalDisplayKeys: 現在のパネル順に並んだ論理ディスプレイ識別子の配列
    func moveSpaceToNextLogicalDisplay(spaceUUID: String,
                                       logicalDisplayKeys: [LogicalDisplayKey]) throws
    {
        var mapping = (try? fileClient.load()) ?? DisplayMapping()
        let existing = mapping.spacesByUUID[spaceUUID]
        guard let firstDisplay = logicalDisplayKeys.first else { return }
        let currentDisplay = existing?.display ?? firstDisplay
        let index = existing?.index ?? 0
        if let idx = logicalDisplayKeys.firstIndex(of: currentDisplay) {
            let nextDisplay = logicalDisplayKeys[(idx + 1) % logicalDisplayKeys.count]
            mapping.spacesByUUID[spaceUUID] = SpaceEntry(display: nextDisplay, index: index)
        } else {
            let target = logicalDisplayKeys.count > 1 ? logicalDisplayKeys[1] : firstDisplay
            mapping.spacesByUUID[spaceUUID] = SpaceEntry(display: target, index: index)
        }
        try fileClient.save(mapping)
    }
}
