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

    /// 現在のスペース配置をディスプレイ UUID と紐づけて保存する
    /// - Parameter spaces: yabai から取得したスペース情報
    func saveCurrentMapping(spaces: [SpaceQueryResult]) async throws {
        let displays = try await yabai.queryDisplays()
        let indexToUUID = Dictionary(uniqueKeysWithValues: displays.map { ($0.index, $0.uuid) })

        var mapping = DisplayMapping()
        for space in spaces {
            if let displayUUID = indexToUUID[space.displayIndex] {
                mapping.spacesByUUID[space.uuid] = SpaceEntry(display: displayUUID, index: space.index)
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

    /// 現在のディスプレイ UUID を取得する
    /// - Returns: ディスプレイ UUID の配列
    func queryDisplayUUIDs() async throws -> [String] {
        let displays = try await yabai.queryDisplays()
        return displays.map(\.uuid)
    }

    /// NSScreen から ディスプレイ UUID → DisplayEntry の辞書を構築する
    @MainActor
    private static func buildDisplayEntries() -> [String: DisplayEntry] {
        var result: [String: DisplayEntry] = [:]
        for screen in NSScreen.screens {
            let key = NSDeviceDescriptionKey("NSScreenNumber")
            guard let screenNumber = screen.deviceDescription[key] as? CGDirectDisplayID else {
                continue
            }
            guard let cfUUID = CGDisplayCreateUUIDFromDisplayID(screenNumber)?.takeRetainedValue() else {
                continue
            }
            let uuid = CFUUIDCreateString(nil, cfUUID) as String
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

    /// スペースのディスプレイ割り当てを次のディスプレイに移動する
    /// - Parameters:
    ///   - spaceUUID: 移動するスペースの UUID
    ///   - displayUUIDs: 現在のパネル順に並んだディスプレイ UUID の配列
    func moveSpaceToNextDisplay(spaceUUID: String, displayUUIDs: [String]) throws {
        var mapping = (try? fileClient.load()) ?? DisplayMapping()
        let existing = mapping.spacesByUUID[spaceUUID]
        let currentDisplay = existing?.display ?? displayUUIDs.first ?? ""
        let index = existing?.index ?? 0
        if let idx = displayUUIDs.firstIndex(of: currentDisplay) {
            let nextDisplay = displayUUIDs[(idx + 1) % displayUUIDs.count]
            mapping.spacesByUUID[spaceUUID] = SpaceEntry(display: nextDisplay, index: index)
        } else {
            let target = displayUUIDs.count > 1 ? displayUUIDs[1] : displayUUIDs.first ?? ""
            mapping.spacesByUUID[spaceUUID] = SpaceEntry(display: target, index: index)
        }
        try fileClient.save(mapping)
    }
}
