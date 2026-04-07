import AppKit
import XCTest
@testable import Coordify

final class AdjacentSpaceTests: XCTestCase {
    private func makeSpace(index: Int, physical: Int = 1) -> SpaceInfo {
        SpaceInfo(
            id: index,
            uuid: "uuid-\(index)",
            index: index,
            label: "",
            physicalDisplayIndex: PhysicalDisplayIndex(physical),
            isVisible: true,
            hasFocus: false,
            isNativeFullscreen: false,
            windowIDs: [],
            apps: []
        )
    }

    func testLeftAtHeadReturnsNil() {
        let spaces = [makeSpace(index: 1), makeSpace(index: 2), makeSpace(index: 3)]
        XCTAssertNil(AppDelegate.adjacentSpace(in: spaces, from: spaces[0], direction: .left))
    }

    func testRightAtTailReturnsNil() {
        let spaces = [makeSpace(index: 1), makeSpace(index: 2), makeSpace(index: 3)]
        XCTAssertNil(AppDelegate.adjacentSpace(in: spaces, from: spaces[2], direction: .right))
    }

    func testLeftFromMiddleReturnsPrevious() {
        let spaces = [makeSpace(index: 1), makeSpace(index: 2), makeSpace(index: 3)]
        let result = AppDelegate.adjacentSpace(in: spaces, from: spaces[1], direction: .left)
        XCTAssertEqual(result?.uuid, "uuid-1")
    }

    func testRightFromMiddleReturnsNext() {
        let spaces = [makeSpace(index: 1), makeSpace(index: 2), makeSpace(index: 3)]
        let result = AppDelegate.adjacentSpace(in: spaces, from: spaces[1], direction: .right)
        XCTAssertEqual(result?.uuid, "uuid-3")
    }

    func testFocusedNotFoundReturnsNil() {
        let spaces = [makeSpace(index: 1), makeSpace(index: 2)]
        let orphan = makeSpace(index: 99)
        XCTAssertNil(AppDelegate.adjacentSpace(in: spaces, from: orphan, direction: .right))
    }

    /// 論理ディスプレイ内で物理インデックスが混在していても、順序どおり隣を返す
    /// (論理境界の判定は呼び出し側で行うため、この関数自体は物理を区別しない)
    func testMixedPhysicalIndicesDoesNotFilter() {
        let spaces = [
            makeSpace(index: 1, physical: 1),
            makeSpace(index: 2, physical: 2),
            makeSpace(index: 3, physical: 1),
        ]
        let result = AppDelegate.adjacentSpace(in: spaces, from: spaces[0], direction: .right)
        XCTAssertEqual(result?.uuid, "uuid-2")
    }

    // MARK: - focusedPhysicalHostsMultipleLogicals

    private func makeDisplay(id: Int, spaces: [SpaceInfo]) -> LogicalDisplay {
        LogicalDisplay(
            id: LogicalDisplayID(id),
            key: LogicalDisplayKey.representing(PhysicalDisplayUUID("uuid-\(id)")),
            name: "Display \(id)",
            physical: nil,
            spaces: spaces
        )
    }

    func test1to1_returnsFalse() {
        let focused = makeSpace(index: 1, physical: 1)
        let other = makeSpace(index: 2, physical: 2)
        let displays = [makeDisplay(id: 1, spaces: [focused]), makeDisplay(id: 2, spaces: [other])]
        XCTAssertFalse(AppDelegate.focusedPhysicalHostsMultipleLogicals(displays: displays, focused: focused))
    }

    func testSingleLogical_returnsFalse() {
        let focused = makeSpace(index: 1, physical: 1)
        let displays = [makeDisplay(id: 1, spaces: [focused, makeSpace(index: 2, physical: 1)])]
        XCTAssertFalse(AppDelegate.focusedPhysicalHostsMultipleLogicals(displays: displays, focused: focused))
    }

    /// フォーカス中物理 (1) に別の論理ディスプレイのスペースも乗っている (1:N)
    func test1toN_returnsTrue() {
        let focused = makeSpace(index: 1, physical: 1)
        let orphan = makeSpace(index: 5, physical: 1)
        let displays = [makeDisplay(id: 1, spaces: [focused]), makeDisplay(id: 2, spaces: [orphan])]
        XCTAssertTrue(AppDelegate.focusedPhysicalHostsMultipleLogicals(displays: displays, focused: focused))
    }

    /// 別物理に他論理があっても、フォーカス中物理は 1:1 なので false
    func testOtherPhysicalHas1toN_returnsFalse() {
        let focused = makeSpace(index: 1, physical: 1)
        let a = makeSpace(index: 2, physical: 2)
        let b = makeSpace(index: 3, physical: 2)
        let displays = [
            makeDisplay(id: 1, spaces: [focused]),
            makeDisplay(id: 2, spaces: [a]),
            makeDisplay(id: 3, spaces: [b]),
        ]
        XCTAssertFalse(AppDelegate.focusedPhysicalHostsMultipleLogicals(displays: displays, focused: focused))
    }

    // MARK: - computeAdjacentTarget

    func testAdjacentTarget_1to1_returnsNative() {
        let focused = makeSpace(index: 1, physical: 1)
        let other = makeSpace(index: 2, physical: 2)
        let displays = [makeDisplay(id: 1, spaces: [focused]), makeDisplay(id: 2, spaces: [other])]
        let result = AppDelegate.computeAdjacentTarget(in: displays, focused: focused, direction: .right)
        guard case .native = result else {
            return XCTFail("Expected .native in 1:1 case, got \(result)")
        }
    }

    func testAdjacentTarget_1toN_middleReturnsExplicit() {
        let a1 = makeSpace(index: 1, physical: 1)
        let a2 = makeSpace(index: 3, physical: 1)
        let a3 = makeSpace(index: 5, physical: 1)
        let b = makeSpace(index: 2, physical: 1) // 別論理だが同じ物理
        let displays = [
            makeDisplay(id: 1, spaces: [a1, a2, a3]),
            makeDisplay(id: 2, spaces: [b]),
        ]
        let result = AppDelegate.computeAdjacentTarget(in: displays, focused: a2, direction: .right)
        guard case let .explicit(target) = result else {
            return XCTFail("Expected .explicit, got \(result)")
        }
        XCTAssertEqual(target.uuid, a3.uuid)
    }

    func testAdjacentTarget_1toN_atBoundaryReturnsNone() {
        let a1 = makeSpace(index: 1, physical: 1)
        let a2 = makeSpace(index: 3, physical: 1)
        let b = makeSpace(index: 2, physical: 1)
        let displays = [
            makeDisplay(id: 1, spaces: [a1, a2]),
            makeDisplay(id: 2, spaces: [b]),
        ]
        let result = AppDelegate.computeAdjacentTarget(in: displays, focused: a2, direction: .right)
        guard case .none = result else {
            return XCTFail("Expected .none at boundary, got \(result)")
        }
    }

    // MARK: - computeNeighborPanelTarget

    func testNeighborPanel_1to1_returnsNone() {
        let focused = makeSpace(index: 1, physical: 1)
        let other = makeSpace(index: 2, physical: 2)
        let displays = [makeDisplay(id: 1, spaces: [focused]), makeDisplay(id: 2, spaces: [other])]
        let result = AppDelegate.computeNeighborPanelTarget(
            in: displays, focused: focused, delta: 1, resolveActiveSpace: { $0.spaces.first }
        )
        guard case .none = result else {
            return XCTFail("Expected .none in 1:1 case")
        }
    }

    func testNeighborPanel_singleDisplay_returnsNone() {
        let focused = makeSpace(index: 1, physical: 1)
        let displays = [makeDisplay(id: 1, spaces: [focused])]
        let result = AppDelegate.computeNeighborPanelTarget(
            in: displays, focused: focused, delta: 1, resolveActiveSpace: { $0.spaces.first }
        )
        guard case .none = result else {
            return XCTFail("Expected .none with single display")
        }
    }

    func testNeighborPanel_1toN_deltaPositive_returnsNeighborActive() {
        let focused = makeSpace(index: 1, physical: 1)
        let neighborActive = makeSpace(index: 2, physical: 1)
        let displays = [
            makeDisplay(id: 1, spaces: [focused]),
            makeDisplay(id: 2, spaces: [neighborActive, makeSpace(index: 3, physical: 1)]),
        ]
        let result = AppDelegate.computeNeighborPanelTarget(
            in: displays, focused: focused, delta: 1, resolveActiveSpace: { $0.spaces.first }
        )
        guard case let .explicit(target) = result else {
            return XCTFail("Expected .explicit")
        }
        XCTAssertEqual(target.uuid, neighborActive.uuid)
    }

    func testNeighborPanel_1toN_wrapsAround() {
        let focused = makeSpace(index: 1, physical: 1)
        let other = makeSpace(index: 2, physical: 1)
        let displays = [makeDisplay(id: 1, spaces: [focused]), makeDisplay(id: 2, spaces: [other])]
        // delta=-1 で index 0 → wrap して 1 (= other の panel) に行く
        let result = AppDelegate.computeNeighborPanelTarget(
            in: displays, focused: focused, delta: -1, resolveActiveSpace: { $0.spaces.first }
        )
        guard case let .explicit(target) = result else {
            return XCTFail("Expected .explicit with wrap")
        }
        XCTAssertEqual(target.uuid, other.uuid)
    }

    // MARK: - 連打シナリオ (regression)

    /// 1:N で Ctrl+Cmd+→ を連打したとき、キャッシュを楽観更新 (markFocused 相当) し続ければ
    /// 期待通り 1 歩ずつ進む。これは `SpaceManager.markFocused` + `computeAdjacentTarget` の
    /// 組み合わせで成り立つ不変条件。
    func testRapidAdjacent_withMarkFocused_advancesOneStepEachPress() {
        let a1 = makeSpace(index: 1, physical: 1)
        let a2 = makeSpace(index: 3, physical: 1)
        let a3 = makeSpace(index: 5, physical: 1)
        let b = makeSpace(index: 2, physical: 1)
        let spaces = [a1, a2, a3]
        let displays = [
            makeDisplay(id: 1, spaces: spaces),
            makeDisplay(id: 2, spaces: [b]),
        ]
        let allByUUID = Dictionary(uniqueKeysWithValues: (spaces + [b]).map { ($0.uuid, $0) })

        var focused = a1
        var moves: [String] = []
        for _ in 0 ..< 5 {
            let result = AppDelegate.computeAdjacentTarget(
                in: displays, focused: focused, direction: .right
            )
            switch result {
            case let .explicit(target):
                moves.append(target.uuid)
                // markFocused による楽観更新をシミュレート（次の press は target を起点に計算）
                guard let next = allByUUID[target.uuid] else { return XCTFail() }
                focused = next
            case .native, .none:
                return // 境界到達で終了
            }
        }
        XCTAssertEqual(moves, [a2.uuid, a3.uuid])
    }

    /// 楽観更新が無ければ、連打は同じ target を返し続ける（= 体感「進まない / おかしい」のバグ再現）。
    /// このテストが pass することで、`markFocused` が無いと不変条件が破れることを明文化する。
    func testRapidAdjacent_withoutMarkFocused_returnsSameTargetRepeatedly() {
        let a1 = makeSpace(index: 1, physical: 1)
        let a2 = makeSpace(index: 3, physical: 1)
        let a3 = makeSpace(index: 5, physical: 1)
        let b = makeSpace(index: 2, physical: 1)
        let displays = [
            makeDisplay(id: 1, spaces: [a1, a2, a3]),
            makeDisplay(id: 2, spaces: [b]),
        ]

        let focused = a1 // 更新しない = キャッシュが古いままの状態をシミュレート
        var moves: [String] = []
        for _ in 0 ..< 3 {
            let result = AppDelegate.computeAdjacentTarget(
                in: displays, focused: focused, direction: .right
            )
            if case let .explicit(target) = result {
                moves.append(target.uuid)
            }
        }
        XCTAssertEqual(moves, [a2.uuid, a2.uuid, a2.uuid])
    }

    /// Ctrl+Cmd+↑/↓ の連打で全パネルを 1 ステップずつ巡回できること。
    func testRapidNeighborPanel_cyclesThroughDisplays() {
        let a = makeSpace(index: 1, physical: 1)
        let b = makeSpace(index: 2, physical: 1)
        let c = makeSpace(index: 3, physical: 1)
        let displays = [
            makeDisplay(id: 1, spaces: [a]),
            makeDisplay(id: 2, spaces: [b]),
            makeDisplay(id: 3, spaces: [c]),
        ]
        let allByUUID = Dictionary(uniqueKeysWithValues: [a, b, c].map { ($0.uuid, $0) })
        let resolver: (LogicalDisplay) -> SpaceInfo? = { $0.spaces.first }

        var focused = a
        var visited: [String] = []
        for _ in 0 ..< 4 {
            let result = AppDelegate.computeNeighborPanelTarget(
                in: displays, focused: focused, delta: 1, resolveActiveSpace: resolver
            )
            guard case let .explicit(target) = result else { return XCTFail() }
            visited.append(target.uuid)
            guard let next = allByUUID[target.uuid] else { return XCTFail() }
            focused = next
        }
        XCTAssertEqual(visited, [b.uuid, c.uuid, a.uuid, b.uuid])
    }
}
