import Foundation

// MARK: - 概要

//
// ディスプレイ識別子の型。
// 物理 (physical) と論理 (logical) の取り違えをコンパイル時に防ぐため、
// いずれも newtype の struct として分離する。raw の Int や String を露出するのは
// yabai / NSScreen / JSON などの境界のみに限定する。
//
// レイヤ分離:
//   - 物理のみを扱うコード: PhysicalDisplayIndex / PhysicalDisplayUUID だけを使う
//   - 論理のみを扱うコード: LogicalDisplayID / LogicalDisplayKey だけを使う
//   - 両方を扱う (境界) コード: `LogicalDisplayKey.representing(_:)` と
//     `LogicalDisplayKey.asPhysicalDisplayUUID` を介してだけ変換する (grep-able な唯一の窓口)

// MARK: - Physical

/// yabai / NSScreen が扱う 1-based の物理ディスプレイ番号
struct PhysicalDisplayIndex: Hashable, Codable, ExpressibleByIntegerLiteral, CustomStringConvertible {
    let rawValue: Int

    init(_ rawValue: Int) {
        self.rawValue = rawValue
    }

    init(integerLiteral value: Int) {
        rawValue = value
    }

    init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(Int.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var description: String {
        "\(rawValue)"
    }
}

/// CGDisplay / yabai が扱う物理ディスプレイ UUID
/// 論理ディスプレイ識別子として扱いたいときは `LogicalDisplayKey.representing(_:)` を介して変換する
struct PhysicalDisplayUUID: Hashable, Codable, CodingKeyRepresentable, CustomStringConvertible {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    init?(codingKey: some CodingKey) {
        rawValue = codingKey.stringValue
    }

    var codingKey: CodingKey {
        StringCodingKey(rawValue)
    }

    var description: String {
        rawValue
    }
}

// MARK: - Logical

/// 論理ディスプレイの識別子
/// 論理ディスプレイは「現在または過去に接続されていた物理ディスプレイ」を指すため、
/// 識別子としては物理 UUID を流用する。ただし PhysicalDisplayUUID とは敢えて別型にして、
/// 「今接続されている物理ディスプレイを参照する」のか「論理ディスプレイを参照する」のかを
/// 呼び出し側で明示させる。
///
/// **変換はこの型が提供する 2 つの窓口のみを通す**:
///   - `LogicalDisplayKey.representing(_:)` — 物理 UUID を論理識別子として扱う
///   - `LogicalDisplayKey.asPhysicalDisplayUUID` — 論理識別子から物理 UUID を取り出す
/// `physicalUUID` ストレージと `init(_:)` は fileprivate で、この窓口以外からの変換を禁止する。
struct LogicalDisplayKey: Hashable, Codable, CodingKeyRepresentable, CustomStringConvertible {
    fileprivate let physicalUUID: PhysicalDisplayUUID

    fileprivate init(_ physicalUUID: PhysicalDisplayUUID) {
        self.physicalUUID = physicalUUID
    }

    /// 物理ディスプレイ UUID を論理ディスプレイ識別子として扱う (境界での明示的な変換)
    static func representing(_ physicalUUID: PhysicalDisplayUUID) -> LogicalDisplayKey {
        LogicalDisplayKey(physicalUUID)
    }

    /// この論理ディスプレイが流用している物理 UUID を取り出す (境界での明示的な変換)
    /// 現在接続されている物理ディスプレイとの突き合わせなどに使う
    var asPhysicalDisplayUUID: PhysicalDisplayUUID {
        physicalUUID
    }

    init(from decoder: Decoder) throws {
        physicalUUID = try decoder.singleValueContainer().decode(PhysicalDisplayUUID.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(physicalUUID)
    }

    init?(codingKey: some CodingKey) {
        physicalUUID = PhysicalDisplayUUID(codingKey.stringValue)
    }

    var codingKey: CodingKey {
        physicalUUID.codingKey
    }

    var description: String {
        physicalUUID.description
    }
}

/// Coordify 内部でスイッチャーのパネル単位を識別するための ID
/// 1 は現在アクティブな物理ディスプレイ、2 以降は追加の論理ディスプレイ (切断中の仮想ディスプレイを含む)
struct LogicalDisplayID: Hashable, Codable, Comparable, ExpressibleByIntegerLiteral, CustomStringConvertible {
    let rawValue: Int

    init(_ rawValue: Int) {
        self.rawValue = rawValue
    }

    init(integerLiteral value: Int) {
        rawValue = value
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(Int.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var description: String {
        "\(rawValue)"
    }
}

// MARK: - CodingKey helper

/// Dictionary<T, V> を JSON オブジェクトとしてエンコードするために CodingKeyRepresentable から返す汎用キー
private struct StringCodingKey: CodingKey {
    let stringValue: String
    var intValue: Int? {
        nil
    }

    init(_ string: String) {
        stringValue = string
    }

    init(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue _: Int) {
        nil
    }
}
