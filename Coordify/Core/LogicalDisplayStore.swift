import AppKit
import CoreGraphics
import Foundation

/// 論理ディスプレイのスナップショット構築を担うコア。
/// yabai が返す物理構成と `display-mapping.json` の保存情報を統合して
/// `[LogicalDisplay]` を組み立てる。
/// **状態変化の監視は行わない** — 呼ばれたタイミングの情報を返すだけ。
final class LogicalDisplayStore {
    private let yabai: YabaiClientProtocol
    private let mappingAdapter: DisplayMappingAdapter
    private let historyAdapter: SpaceHistoryAdapter

    init(yabai: YabaiClientProtocol = YabaiClient.shared,
         mappingAdapter: DisplayMappingAdapter = DisplayMappingAdapter(),
         historyAdapter: SpaceHistoryAdapter = SpaceHistoryAdapter())
    {
        self.yabai = yabai
        self.mappingAdapter = mappingAdapter
        self.historyAdapter = historyAdapter
    }

    // MARK: - Snapshot

    /// 現時点の論理ディスプレイ構成のスナップショットを構築する。
    /// - Parameter allSpaces: SpaceManager から取得したスペース一覧
    /// 複数物理ディスプレイ接続時は mapping.json にも保存する (将来切断されたときのために)。
    func snapshot(allSpaces: [SpaceInfo]) async -> [LogicalDisplay] {
        guard !allSpaces.isEmpty else { return [] }

        let physicalDisplays = await buildPhysicalDisplays()
        let hasMultiplePhysical = Set(allSpaces.map(\.physicalDisplayIndex)).count >= 2

        // 現在接続されているディスプレイ構成を記録 (切断時に参照できるように)
        if hasMultiplePhysical {
            let queryResults = allSpaces.map(spaceQueryResultFromInfo)
            try? await mappingAdapter.saveCurrentMapping(spaces: queryResults)
        }

        let savedMapping = (try? mappingAdapter.loadMapping()) ?? DisplayMapping()
        let physicalByKey = Dictionary(uniqueKeysWithValues:
            physicalDisplays.map { (LogicalDisplayKey.representing($0.uuid), $0) })

        if hasMultiplePhysical {
            return buildForMultiplePhysical(
                allSpaces: allSpaces,
                physicalByKey: physicalByKey,
                savedMapping: savedMapping
            )
        } else {
            return buildForSinglePhysical(
                allSpaces: allSpaces,
                physicalByKey: physicalByKey,
                savedMapping: savedMapping
            )
        }
    }

    // MARK: - 履歴記録

    /// 現在 visible なスペースを論理ディスプレイごとに記録する。
    /// 境界変換 (物理→論理 キー) を Store 内で完結させることで、Adapter は純粋な永続化責務に留まる。
    func recordCurrentVisibleSpaces(_ allSpaces: [SpaceInfo]) async {
        let visibleSpaces = allSpaces.filter(\.isVisible)
        guard !visibleSpaces.isEmpty else { return }

        let savedMapping = (try? mappingAdapter.loadMapping()) ?? DisplayMapping()
        let physicalDisplays = await buildPhysicalDisplays()
        let physicalByIndex = Dictionary(uniqueKeysWithValues: physicalDisplays.map { ($0.index, $0) })

        var updates: [(LogicalDisplayKey, String)] = []
        for space in visibleSpaces {
            let key: LogicalDisplayKey
            if let saved = savedMapping.spacesByUUID[space.uuid]?.display {
                key = saved
            } else if let phys = physicalByIndex[space.physicalDisplayIndex] {
                key = LogicalDisplayKey.representing(phys.uuid)
            } else {
                continue
            }
            updates.append((key, space.uuid))
        }
        historyAdapter.recordLastActive(updates)
    }

    /// 論理ディスプレイ内の「最後に active だった」スペースを返す。
    /// 接続中なら isVisible、切断中なら履歴から。見つからなければ先頭。
    func lastActiveSpace(in display: LogicalDisplay) -> SpaceInfo? {
        if display.isConnected, let visible = display.spaces.first(where: \.isVisible) {
            return visible
        }
        if let uuid = historyAdapter.lookupLastActiveSpaceUUID(forLogicalDisplay: display.key),
           let space = display.spaces.first(where: { $0.uuid == uuid })
        {
            return space
        }
        return display.spaces.first
    }

    // MARK: - Private helpers

    /// yabai の物理ディスプレイ情報 + NSScreen の名前/builtIn を統合する
    private func buildPhysicalDisplays() async -> [PhysicalDisplay] {
        guard let yabaiDisplays = try? await yabai.queryDisplays() else { return [] }
        let yabaiIndexByUUID = Dictionary(uniqueKeysWithValues:
            yabaiDisplays.map { ($0.uuid, PhysicalDisplayIndex($0.index)) })

        var result: [PhysicalDisplay] = []
        for screen in NSScreen.screens {
            guard let physical = physicalDisplay(from: screen, yabaiIndexByUUID: yabaiIndexByUUID) else {
                continue
            }
            result.append(physical)
        }
        return result
    }

    private func physicalDisplay(
        from screen: NSScreen,
        yabaiIndexByUUID: [PhysicalDisplayUUID: PhysicalDisplayIndex]
    ) -> PhysicalDisplay? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let screenNumber = screen.deviceDescription[key] as? CGDirectDisplayID,
              let cfUUID = CGDisplayCreateUUIDFromDisplayID(screenNumber)?.takeRetainedValue()
        else { return nil }
        let uuid = PhysicalDisplayUUID(CFUUIDCreateString(nil, cfUUID) as String)
        guard let index = yabaiIndexByUUID[uuid] else { return nil }
        return PhysicalDisplay(
            index: index,
            uuid: uuid,
            name: screen.localizedName,
            isBuiltIn: CGDisplayIsBuiltin(screenNumber) != 0
        )
    }

    /// 物理ディスプレイが複数接続されているとき。論理 ID は物理 index をそのまま流用する。
    private func buildForMultiplePhysical(
        allSpaces: [SpaceInfo],
        physicalByKey: [LogicalDisplayKey: PhysicalDisplay],
        savedMapping: DisplayMapping
    ) -> [LogicalDisplay] {
        let grouped = Dictionary(grouping: allSpaces, by: \.physicalDisplayIndex)
        return grouped
            .map { index, spaces in
                let logicalID = LogicalDisplayID(index.rawValue)
                let physical = physicalByKey.first(where: { $0.value.index == index })?.value
                let key = physical.map { LogicalDisplayKey.representing($0.uuid) }
                    ?? LogicalDisplayKey.representing(PhysicalDisplayUUID("")) // 接続中なら必ず見つかる想定
                let name = physical?.name
                    ?? savedMapping.displaysByUUID[key.asPhysicalDisplayUUID]?.name
                    ?? ""
                return LogicalDisplay(
                    id: logicalID, key: key, name: name, physical: physical, spaces: spaces
                )
            }
            .sorted(by: { $0.id < $1.id })
    }

    /// 物理ディスプレイが 1 つだけのとき。現在のディスプレイ + 保存済みマッピングの仮想ディスプレイを組み立てる。
    private func buildForSinglePhysical(
        allSpaces: [SpaceInfo],
        physicalByKey: [LogicalDisplayKey: PhysicalDisplay],
        savedMapping: DisplayMapping
    ) -> [LogicalDisplay] {
        // 現在接続されているキー (yabai + NSScreen から)。yabai 不通等で不明な場合は後段で fallback。
        let currentKey = physicalByKey.keys.first

        // 論理キー → 所属スペース の振り分け
        var keyOrder: [LogicalDisplayKey] = []
        var spacesByKey: [LogicalDisplayKey: [SpaceInfo]] = [:]
        if let current = currentKey {
            keyOrder.append(current)
            spacesByKey[current] = []
        }
        for space in allSpaces {
            let key: LogicalDisplayKey
            if let saved = savedMapping.spacesByUUID[space.uuid]?.display, saved != currentKey {
                key = saved
                if spacesByKey[key] == nil {
                    keyOrder.append(key)
                    spacesByKey[key] = []
                }
            } else if let current = currentKey {
                key = current
            } else if let fallback = keyOrder.first {
                key = fallback // currentKey 無 + saved 無 → 既出キーに寄せる
            } else {
                // 完全に未知: sentinel として便宜的なキーに集約
                let sentinel = LogicalDisplayKey.representing(PhysicalDisplayUUID(""))
                keyOrder.append(sentinel)
                spacesByKey[sentinel] = []
                key = sentinel
            }
            spacesByKey[key, default: []].append(space)
        }

        return keyOrder.enumerated().map { offset, key in
            let physical = physicalByKey[key]
            let name = physical?.name
                ?? savedMapping.displaysByUUID[key.asPhysicalDisplayUUID]?.name
                ?? ""
            return LogicalDisplay(
                id: LogicalDisplayID(offset + 1),
                key: key,
                name: name,
                physical: physical,
                spaces: spacesByKey[key] ?? []
            )
        }
    }

    /// SpaceInfo から SpaceQueryResult へ復元する (mappingAdapter.saveCurrentMapping が要求するため)
    /// SpaceInfo は SpaceQueryResult のスーパーセットなので情報的には問題ない。
    private func spaceQueryResultFromInfo(_ info: SpaceInfo) -> SpaceQueryResult {
        SpaceQueryResult(
            id: info.id,
            uuid: info.uuid,
            index: info.index,
            label: info.label,
            physicalDisplayIndex: info.physicalDisplayIndex,
            isVisible: info.isVisible,
            hasFocus: info.hasFocus,
            isNativeFullscreen: info.isNativeFullscreen,
            windowIDs: info.windowIDs
        )
    }
}
