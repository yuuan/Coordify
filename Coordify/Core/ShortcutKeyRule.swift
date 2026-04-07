import Foundation

/// スペースごとのショートカットキー割り当てルール
enum ShortcutKeyRule {
    /// デスクトップ番号に対応する表示文字とキーコードの組
    struct DesktopShortcut {
        let display: String
        let keyCode: Int
    }

    /// デスクトップ番号(1-based) → ショートカット定義。Ctrl+1〜9, Ctrl+0(=10) に対応。
    static let desktopShortcuts: [Int: DesktopShortcut] = [
        1: DesktopShortcut(display: "1", keyCode: 0x12),
        2: DesktopShortcut(display: "2", keyCode: 0x13),
        3: DesktopShortcut(display: "3", keyCode: 0x14),
        4: DesktopShortcut(display: "4", keyCode: 0x15),
        5: DesktopShortcut(display: "5", keyCode: 0x17),
        6: DesktopShortcut(display: "6", keyCode: 0x16),
        7: DesktopShortcut(display: "7", keyCode: 0x1A),
        8: DesktopShortcut(display: "8", keyCode: 0x1C),
        9: DesktopShortcut(display: "9", keyCode: 0x19),
        10: DesktopShortcut(display: "0", keyCode: 0x1D),
    ]

    /// 全スペースのショートカットキーを一括で割り当てる
    /// 配列のインデックスがスペースのインデックスに対応する
    static func assignShortcutKeys(spaces: [SpaceInfo], spaceNames: [String]) -> [String?] {
        var usedKeys = Set<String>()
        var result = [String?](repeating: nil, count: spaces.count)

        for idx in spaces.indices {
            let space = spaces[idx]
            if !space.isNativeFullscreen {
                result[idx] = desktopShortcuts[space.index]?.display
                // 数字キーは英字と重複しないので usedKeys に入れない
            } else {
                let key = firstUnusedASCIILetter(
                    in: spaceNames[idx],
                    fallback: space.apps.first?.executableName,
                    usedKeys: usedKeys
                )
                result[idx] = key
                if let key { usedKeys.insert(key) }
            }
        }

        return result
    }

    /// 単一スペースのショートカットキー（テスト用・重複なし前提）
    static func shortcutKey(for space: SpaceInfo, spaceName: String) -> String? {
        assignShortcutKeys(spaces: [space], spaceNames: [spaceName])[0]
    }

    /// 文字列中の ASCII 英字を順に試し、usedKeys に含まれない最初の1文字を返す
    /// primary で見つからなければ fallback も試す
    private static func firstUnusedASCIILetter(
        in primary: String,
        fallback: String?,
        usedKeys: Set<String>
    ) -> String? {
        for char in primary {
            guard let half = char.toHalfwidthASCII else { continue }
            let key = String(half).uppercased()
            if !usedKeys.contains(key) { return key }
        }
        if let fallback {
            for char in fallback {
                guard let half = char.toHalfwidthASCII else { continue }
                let key = String(half).uppercased()
                if !usedKeys.contains(key) { return key }
            }
        }
        return nil
    }
}

// MARK: - Character Extension

extension Character {
    /// 半角・全角の英字（[a-zA-Z] および [Ａ-Ｚａ-ｚ]）
    var isASCIILetter: Bool {
        toHalfwidthASCII != nil
    }

    /// 全角英字を半角に変換して返す。半角英字はそのまま返す。それ以外は nil。
    var toHalfwidthASCII: Character? {
        let str = String(self)
        let converted = str.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? str
        guard let char = converted.first, ("a" ... "z").contains(char) || ("A" ... "Z").contains(char) else {
            return nil
        }
        return char
    }
}
