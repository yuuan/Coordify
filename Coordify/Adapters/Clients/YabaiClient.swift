import Foundation

/// yabai CLI を介してスペースやディスプレイの情報取得・操作を行うクライアント
final class YabaiClient: YabaiClientProtocol {
    static let shared = YabaiClient()

    private var yabaiPath: String?

    private init() {
        yabaiPath = Self.resolveYabaiPath()
    }

    var isAvailable: Bool {
        yabaiPath != nil
    }

    // MARK: - yabai Commands

    /// yabai の query --spaces コマンドで全スペース情報を取得する
    /// - Returns: yabai から取得したスペース情報の配列
    func querySpaces() async throws -> [YabaiSpaceResponse] {
        let output = try await run(["-m", "query", "--spaces"])
        let data = Data(output.utf8)
        return try JSONDecoder().decode([YabaiSpaceResponse].self, from: data)
    }

    /// yabai の query --displays コマンドで全ディスプレイ情報を取得する
    /// - Returns: yabai から取得したディスプレイ情報の配列
    func queryDisplays() async throws -> [YabaiDisplayResponse] {
        let output = try await run(["-m", "query", "--displays"])
        let data = Data(output.utf8)
        return try JSONDecoder().decode([YabaiDisplayResponse].self, from: data)
    }

    /// 指定されたインデックスのスペースにフォーカスを切り替える
    /// - Parameter index: 切り替え先のスペースインデックス
    func focusSpace(index: Int) async throws {
        _ = try await run(["-m", "space", "--focus", "\(index)"])
    }

    /// 指定されたディスプレイにフォーカスを切り替える
    func focusDisplay(index: Int) async throws {
        _ = try await run(["-m", "display", "--focus", "\(index)"])
    }

    /// 指定されたスペースにラベルを設定する
    /// - Parameters:
    ///   - index: 対象のスペースインデックス
    ///   - label: 設定するラベル名
    func labelSpace(index: Int, label: String) async throws {
        _ = try await run(["-m", "space", "\(index)", "--label", label])
    }

    /// 指定されたウィンドウを別のスペースに移動する
    /// - Parameters:
    ///   - windowID: 移動対象のウィンドウID
    ///   - spaceIndex: 移動先のスペースインデックス
    func moveWindow(windowID: Int, toSpace spaceIndex: Int) async throws {
        _ = try await run(["-m", "window", "\(windowID)", "--space", "\(spaceIndex)"])
    }

    // MARK: - Process Execution

    private func run(_ arguments: [String]) async throws -> String {
        guard let path = yabaiPath else {
            throw YabaiClientError.notInstalled
        }

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: YabaiClientError.executionFailed(error.localizedDescription))
                return
            }

            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            if process.terminationStatus != 0 {
                let message = output.trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(throwing: YabaiClientError.commandFailed(message))
            } else {
                continuation.resume(returning: output)
            }
        }
    }

    private static func resolveYabaiPath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/yabai",
            "/usr/local/bin/yabai",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["yabai"]
        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        } catch {}
        return nil
    }
}

// MARK: - Response Types

/// yabai が返すディスプレイ情報の JSON 表現
struct YabaiDisplayResponse: Decodable {
    let id: Int
    let uuid: String
    let index: Int
    let spaces: [Int]
}

/// yabai が返すスペース情報の JSON 表現
struct YabaiSpaceResponse: Decodable {
    let id: Int
    let uuid: String
    let index: Int
    let label: String
    let type: String
    let display: Int
    let windows: [Int]
    let isVisible: Bool
    let isNativeFullscreen: Bool
    let hasFocus: Bool

    enum CodingKeys: String, CodingKey {
        case id, uuid, index, label, type, display, windows
        case isVisible = "is-visible"
        case isNativeFullscreen = "is-native-fullscreen"
        case hasFocus = "has-focus"
    }
}

/// yabai の実行に関するエラー種別
enum YabaiClientError: LocalizedError {
    case notInstalled
    case executionFailed(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            "yabai がインストールされていません"
        case let .executionFailed(message):
            "yabai の実行に失敗しました: \(message)"
        case let .commandFailed(message):
            "yabai コマンドエラー: \(message)"
        }
    }
}
