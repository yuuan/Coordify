import Foundation

/// スペースの最終アクティブ状態を論理ディスプレイごとに永続化するアダプター。
/// 境界 (物理→論理の変換) は `LogicalDisplayStore` が担当し、本 Adapter は
/// すでに解決済みの `LogicalDisplayKey` を受け取って `space-history.json` に書くだけ。
final class SpaceHistoryAdapter {
    private let fileClient: SpaceHistoryFileClientProtocol
    private let mappingFileClient: DisplayMappingFileClientProtocol
    private var cached: SpaceHistory

    init(fileClient: SpaceHistoryFileClientProtocol = SpaceHistoryFileClient.shared,
         mappingFileClient: DisplayMappingFileClientProtocol = DisplayMappingFileClient.shared)
    {
        self.fileClient = fileClient
        self.mappingFileClient = mappingFileClient
        cached = (try? fileClient.load()) ?? SpaceHistory()
        pruneInconsistentEntries()
        seedFromDisplayMappingIfNeeded()
    }

    /// 論理ディスプレイ → 最後に visible だったスペース UUID の組を一括で記録する
    /// - Parameter pairs: (論理ディスプレイ, スペース UUID) の配列
    func recordLastActive(_ pairs: [(LogicalDisplayKey, String)]) {
        var changed = false
        for (key, spaceUUID) in pairs where cached.lastActiveSpaceByDisplay[key] != spaceUUID {
            cached.lastActiveSpaceByDisplay[key] = spaceUUID
            changed = true
        }
        guard changed else { return }
        cached.updatedAt = Self.iso8601Now()
        try? fileClient.save(cached)
    }

    /// 指定された論理ディスプレイで最後にアクティブだったスペースの UUID を返す
    func lookupLastActiveSpaceUUID(forLogicalDisplay key: LogicalDisplayKey) -> String? {
        cached.lastActiveSpaceByDisplay[key]
    }

    // MARK: - Migration / Seed

    /// 保存済み display-mapping と矛盾する (過去バグ由来の) エントリを除去する
    private func pruneInconsistentEntries() {
        guard let mapping = try? mappingFileClient.load() else { return }
        var changed = false
        for (displayKey, spaceUUID) in cached.lastActiveSpaceByDisplay {
            if let savedDisplay = mapping.spacesByUUID[spaceUUID]?.display,
               savedDisplay != displayKey
            {
                cached.lastActiveSpaceByDisplay.removeValue(forKey: displayKey)
                changed = true
            }
        }
        if changed {
            cached.updatedAt = Self.iso8601Now()
            try? fileClient.save(cached)
        }
    }

    /// 起動時に display-mapping.json から既知ディスプレイの初期値を埋める。
    /// 外部ディスプレイを切断中でも、過去に記録された空間配置からそれらしい最後のスペースを推定できるようにする
    private func seedFromDisplayMappingIfNeeded() {
        guard let mapping = try? mappingFileClient.load() else { return }
        var changed = false
        for physicalUUID in mapping.displaysByUUID.keys {
            let displayKey = LogicalDisplayKey.representing(physicalUUID)
            if cached.lastActiveSpaceByDisplay[displayKey] != nil { continue }
            let candidate = mapping.spacesByUUID
                .filter { $0.value.display == displayKey }
                .min(by: { $0.value.index < $1.value.index })
            guard let spaceUUID = candidate?.key else { continue }
            cached.lastActiveSpaceByDisplay[displayKey] = spaceUUID
            changed = true
        }
        guard changed else { return }
        cached.updatedAt = Self.iso8601Now()
        try? fileClient.save(cached)
    }

    private static func iso8601Now() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = .current
        return formatter.string(from: Date())
    }
}
