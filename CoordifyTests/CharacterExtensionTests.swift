import XCTest
@testable import Coordify

final class CharacterExtensionTests: XCTestCase {
    // MARK: - toHalfwidthASCII

    func testHalfwidthLowercase() {
        XCTAssertEqual(Character("a").toHalfwidthASCII, "a")
        XCTAssertEqual(Character("z").toHalfwidthASCII, "z")
    }

    func testHalfwidthUppercase() {
        XCTAssertEqual(Character("A").toHalfwidthASCII, "A")
        XCTAssertEqual(Character("Z").toHalfwidthASCII, "Z")
    }

    func testFullwidthLowercase() {
        XCTAssertEqual(Character("ａ").toHalfwidthASCII, "a")
        XCTAssertEqual(Character("ｚ").toHalfwidthASCII, "z")
    }

    func testFullwidthUppercase() {
        XCTAssertEqual(Character("Ａ").toHalfwidthASCII, "A")
        XCTAssertEqual(Character("Ｚ").toHalfwidthASCII, "Z")
    }

    func testDigitsReturnNil() {
        XCTAssertNil(Character("0").toHalfwidthASCII)
        XCTAssertNil(Character("9").toHalfwidthASCII)
        XCTAssertNil(Character("０").toHalfwidthASCII) // fullwidth digit
    }

    func testSymbolsReturnNil() {
        XCTAssertNil(Character("!").toHalfwidthASCII)
        XCTAssertNil(Character("@").toHalfwidthASCII)
        XCTAssertNil(Character("-").toHalfwidthASCII)
    }

    func testJapaneseReturnsNil() {
        XCTAssertNil(Character("あ").toHalfwidthASCII)
        XCTAssertNil(Character("漢").toHalfwidthASCII)
    }

    func testSpaceReturnsNil() {
        XCTAssertNil(Character(" ").toHalfwidthASCII)
    }

    // MARK: - isASCIILetter

    func testIsASCIILetter() {
        XCTAssertTrue(Character("A").isASCIILetter)
        XCTAssertTrue(Character("z").isASCIILetter)
        XCTAssertTrue(Character("Ａ").isASCIILetter) // fullwidth
        XCTAssertFalse(Character("1").isASCIILetter)
        XCTAssertFalse(Character("あ").isASCIILetter)
    }
}
