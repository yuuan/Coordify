import AppKit
import XCTest
@testable import Coordify

final class ShortcutKeyTests: XCTestCase {
    // MARK: - Helpers

    private func makeSpace(
        index: Int = 1,
        isNativeFullscreen: Bool = false,
        apps: [AppInfo] = []
    ) -> SpaceInfo {
        SpaceInfo(
            id: index,
            uuid: "uuid-\(index)",
            index: index,
            label: "",
            physicalDisplayIndex: PhysicalDisplayIndex(1),
            isVisible: true,
            hasFocus: false,
            isNativeFullscreen: isNativeFullscreen,
            windowIDs: [],
            apps: apps
        )
    }

    private func makeApp(name: String, executableName: String = "") -> AppInfo {
        AppInfo(id: 1, appName: name, bundleIdentifier: "com.example", executableName: executableName, icon: NSImage())
    }

    // MARK: - 通常スペース

    func testRegularSpaceReturnsIndex() {
        let space = makeSpace(index: 3)
        let key = ShortcutKeyRule.shortcutKey(for: space, spaceName: "Desktop 3")
        XCTAssertEqual(key, "3")
    }

    func testDesktop10ReturnsZero() {
        let space = makeSpace(index: 10)
        let key = ShortcutKeyRule.shortcutKey(for: space, spaceName: "Desktop 10")
        XCTAssertEqual(key, "0")
    }

    func testDesktop11ReturnsNil() {
        let space = makeSpace(index: 11)
        let key = ShortcutKeyRule.shortcutKey(for: space, spaceName: "Desktop 11")
        XCTAssertNil(key)
    }

    // MARK: - フルスクリーン: 半角英字

    func testFullscreenASCIIName() {
        let space = makeSpace(isNativeFullscreen: true, apps: [makeApp(name: "Xcode")])
        let key = ShortcutKeyRule.shortcutKey(for: space, spaceName: "Xcode")
        XCTAssertEqual(key, "X")
    }

    func testFullscreenLowercaseASCII() {
        let space = makeSpace(isNativeFullscreen: true, apps: [makeApp(name: "safari")])
        let key = ShortcutKeyRule.shortcutKey(for: space, spaceName: "safari")
        XCTAssertEqual(key, "S")
    }

    // MARK: - フルスクリーン: 全角英字

    func testFullscreenFullwidthAlphabet() {
        let space = makeSpace(isNativeFullscreen: true, apps: [makeApp(name: "Ａｐｐ")])
        let key = ShortcutKeyRule.shortcutKey(for: space, spaceName: "Ａｐｐ")
        XCTAssertEqual(key, "A")
    }

    // MARK: - フルスクリーン: 日本語名（英字なし）

    func testFullscreenJapaneseOnlyReturnsNil() {
        let space = makeSpace(isNativeFullscreen: true, apps: [makeApp(name: "写真")])
        let key = ShortcutKeyRule.shortcutKey(for: space, spaceName: "写真")
        XCTAssertNil(key)
    }

    // MARK: - フルスクリーン: 日本語名の中に英字

    func testFullscreenJapaneseWithASCII() {
        let space = makeSpace(isNativeFullscreen: true, apps: [makeApp(name: "日本語App")])
        let key = ShortcutKeyRule.shortcutKey(for: space, spaceName: "日本語App")
        XCTAssertEqual(key, "A")
    }

    // MARK: - フルスクリーン: 数字で始まる名前

    func testFullscreenStartsWithDigit() {
        let space = makeSpace(isNativeFullscreen: true, apps: [makeApp(name: "1Password")])
        let key = ShortcutKeyRule.shortcutKey(for: space, spaceName: "1Password")
        XCTAssertEqual(key, "P")
    }

    // MARK: - フルスクリーン: 数字のみ（実行ファイル名フォールバックなし）

    func testFullscreenDigitsOnlyNoExecReturnsNil() {
        let space = makeSpace(isNativeFullscreen: true, apps: [makeApp(name: "123")])
        let key = ShortcutKeyRule.shortcutKey(for: space, spaceName: "123")
        XCTAssertNil(key)
    }

    // MARK: - フルスクリーン: 実行ファイル名フォールバック

    func testFullscreenFallbackToExecutableName() {
        let space = makeSpace(isNativeFullscreen: true, apps: [makeApp(name: "写真", executableName: "Photos")])
        let key = ShortcutKeyRule.shortcutKey(for: space, spaceName: "写真")
        XCTAssertEqual(key, "P")
    }

    func testFullscreenFallbackToExecutableNameFullwidth() {
        let space = makeSpace(isNativeFullscreen: true, apps: [makeApp(name: "写真", executableName: "Ｐｈｏｔｏｓ")])
        let key = ShortcutKeyRule.shortcutKey(for: space, spaceName: "写真")
        XCTAssertEqual(key, "P")
    }

    func testFullscreenNoAlphabetAnywhere() {
        let space = makeSpace(isNativeFullscreen: true, apps: [makeApp(name: "写真", executableName: "123")])
        let key = ShortcutKeyRule.shortcutKey(for: space, spaceName: "写真")
        XCTAssertNil(key)
    }

    func testFullscreenAppNameTakesPriorityOverExec() {
        let space = makeSpace(isNativeFullscreen: true, apps: [makeApp(name: "Safari", executableName: "XSafari")])
        let key = ShortcutKeyRule.shortcutKey(for: space, spaceName: "Safari")
        XCTAssertEqual(key, "S")
    }

    // MARK: - 重複回避

    func testDuplicateLetterUsesNextInAppName() {
        // Safari(S) → Slack は S が使われているので L になる
        let spaces = [
            makeSpace(index: 1, isNativeFullscreen: true, apps: [makeApp(name: "Safari")]),
            makeSpace(index: 2, isNativeFullscreen: true, apps: [makeApp(name: "Slack")]),
        ]
        let names = ["Safari", "Slack"]
        let keys = ShortcutKeyRule.assignShortcutKeys(spaces: spaces, spaceNames: names)
        XCTAssertEqual(keys[0], "S")
        XCTAssertEqual(keys[1], "L")
    }

    func testDuplicateLetterFallsBackToExec() {
        // 写真(nil) → アプリ名に英字なし、exec=Photos → P
        // ページ(nil) → アプリ名に英字なし、exec=Pages → P は使用済み → A
        let spaces = [
            makeSpace(index: 1, isNativeFullscreen: true, apps: [makeApp(name: "写真", executableName: "Photos")]),
            makeSpace(index: 2, isNativeFullscreen: true, apps: [makeApp(name: "ページ", executableName: "Pages")]),
        ]
        let names = ["写真", "ページ"]
        let keys = ShortcutKeyRule.assignShortcutKeys(spaces: spaces, spaceNames: names)
        XCTAssertEqual(keys[0], "P")
        XCTAssertEqual(keys[1], "A")
    }

    func testTripleDuplicate() {
        // Safari(S) → Slack(L) → Spotify(P) — S,L が使用済みなので P
        let spaces = [
            makeSpace(index: 1, isNativeFullscreen: true, apps: [makeApp(name: "Safari")]),
            makeSpace(index: 2, isNativeFullscreen: true, apps: [makeApp(name: "Slack")]),
            makeSpace(index: 3, isNativeFullscreen: true, apps: [makeApp(name: "Spotify")]),
        ]
        let names = ["Safari", "Slack", "Spotify"]
        let keys = ShortcutKeyRule.assignShortcutKeys(spaces: spaces, spaceNames: names)
        XCTAssertEqual(keys[0], "S")
        XCTAssertEqual(keys[1], "L")
        XCTAssertEqual(keys[2], "P")
    }

    func testAllLettersExhausted() {
        // アプリ名の全文字が使い尽くされたら nil
        let spaces = [
            makeSpace(index: 1, isNativeFullscreen: true, apps: [makeApp(name: "AB")]),
            makeSpace(index: 2, isNativeFullscreen: true, apps: [makeApp(name: "BA")]),
            makeSpace(index: 3, isNativeFullscreen: true, apps: [makeApp(name: "AB", executableName: "AB")]),
        ]
        let names = ["AB", "BA", "AB"]
        let keys = ShortcutKeyRule.assignShortcutKeys(spaces: spaces, spaceNames: names)
        XCTAssertEqual(keys[0], "A")
        XCTAssertEqual(keys[1], "B")
        XCTAssertNil(keys[2])
    }

    func testRegularSpacesDoNotConflictWithFullscreen() {
        // 通常スペース(数字)とフルスクリーン(英字)は重複しない
        let spaces = [
            makeSpace(index: 1, isNativeFullscreen: false),
            makeSpace(index: 2, isNativeFullscreen: true, apps: [makeApp(name: "Safari")]),
        ]
        let names = ["Desktop 1", "Safari"]
        let keys = ShortcutKeyRule.assignShortcutKeys(spaces: spaces, spaceNames: names)
        XCTAssertEqual(keys[0], "1")
        XCTAssertEqual(keys[1], "S")
    }
}
