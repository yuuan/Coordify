import CommonCrypto
import Foundation

/// ディスプレイマッピングの JSON ファイルへの永続化を担うクライアント
final class DisplayMappingFileClient: DisplayMappingFileClientProtocol {
    static let shared = DisplayMappingFileClient()

    let fileURL: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Coordify", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("display-mapping.json")
    }

    /// ディスプレイマッピングを JSON ファイルから読み込む（ファイルが存在しない場合は空のマッピングを返す）
    /// - Returns: 読み込まれたマッピング
    func load() throws -> DisplayMapping {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return DisplayMapping() }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(DisplayMapping.self, from: data)
    }

    /// ディスプレイマッピングを JSON ファイルに保存する
    /// - Parameter mapping: 保存するマッピング
    func save(_ mapping: DisplayMapping) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(mapping)
        try data.write(to: fileURL, options: .atomic)
        saveBackup(data: data, mapping: mapping)
    }

    /// 接続中ディスプレイの構成ごとに backups/ へ最新版を複製する
    private func saveBackup(data: Data, mapping: DisplayMapping) {
        let backupDir = fileURL.deletingLastPathComponent().appendingPathComponent("backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)

        // ディスプレイ UUID をソートして結合し、短いハッシュでファイル名にする
        let displayUUIDs = mapping.displaysByUUID.keys
            .map(\.rawValue)
            .sorted()
            .joined(separator: "+")
        let hash = sha256Prefix(displayUUIDs, length: 8)

        // ディスプレイ名をファイル名に含める（ファイル名に使えない文字を除去）
        let names = mapping.displaysByUUID.values.map(\.name).sorted()
        let sanitized = names.joined(separator: "_")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")

        let fileName = sanitized.isEmpty ? "displays-\(hash).json" : "\(sanitized)-\(hash).json"
        let backupURL = backupDir.appendingPathComponent(fileName)
        try? data.write(to: backupURL, options: .atomic)
    }

    private func sha256Prefix(_ string: String, length: Int) -> String {
        let data = Data(string.utf8)
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash) }
        return hash.prefix(length / 2 + 1).map { String(format: "%02x", $0) }.joined().prefix(length).description
    }
}
