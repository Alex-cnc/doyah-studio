import XCTest
@testable import DoyahCore

/// 断点账本（`FR-STD-WS-TOOL-003` 界面半的判定层）。
final class DebugBreakpointsTests: XCTestCase {

    private let a = "/tmp/demo/main.c"
    private let b = "/tmp/demo/util.c"

    func testToggleAddsAndRemoves() {
        var set = DebugBreakpointSet()
        XCTAssertTrue(set.toggle(path: a, line: 5), "第一次点 = 加上")
        XCTAssertTrue(set.contains(path: a, line: 5))
        XCTAssertFalse(set.toggle(path: a, line: 5), "再点一次 = 去掉")
        XCTAssertFalse(set.contains(path: a, line: 5))
        XCTAssertTrue(set.isEmpty, "去掉最后一条之后账本要回到空（不是留一个空集合）")
    }

    func testLineZeroIsRefused() {
        var set = DebugBreakpointSet()
        XCTAssertFalse(set.toggle(path: a, line: 0), "行号 1 起；0 是点歪了，不许落成断点")
        XCTAssertFalse(set.toggle(path: a, line: -3))
        XCTAssertTrue(set.isEmpty)
    }

    func testEmptyPathIsRefused() {
        var set = DebugBreakpointSet()
        XCTAssertFalse(set.toggle(path: "   ", line: 3))
        XCTAssertTrue(set.isEmpty)
    }

    func testLinesAreSortedAndScopedPerFile() {
        var set = DebugBreakpointSet()
        set.toggle(path: a, line: 9)
        set.toggle(path: a, line: 2)
        set.toggle(path: b, line: 7)
        XCTAssertEqual(set.lines(for: a), [2, 9], "同一文件的断点按行号升序")
        XCTAssertEqual(set.lines(for: b), [7])
        XCTAssertEqual(set.count, 3)
    }

    func testDapMapIsSortedAndSkipsFilesWithoutBreakpoints() {
        var set = DebugBreakpointSet()
        set.toggle(path: a, line: 30)
        set.toggle(path: a, line: 4)
        set.toggle(path: b, line: 1)
        set.clear(path: b)
        let map = set.dapMap()
        XCTAssertEqual(map, [a: [4, 30]], "发给适配器的是升序行号，空文件不进 map")
    }

    func testPathNormalizationSqueezesSlashesAndTrims() {
        var set = DebugBreakpointSet()
        set.toggle(path: "  /tmp/demo//main.c  ", line: 5)
        XCTAssertTrue(set.contains(path: "/tmp/demo/main.c", line: 5),
                      "同一文件写成带空白的/带双斜杠的，也该是同一份断点")
        XCTAssertEqual(set.listing.count, 1, "归一之后不许出现两条同名文件")
    }

    func testListingIsStable() {
        var set = DebugBreakpointSet()
        set.toggle(path: b, line: 8)
        set.toggle(path: a, line: 3)
        set.toggle(path: a, line: 1)
        XCTAssertEqual(set.listing.map(\.path), [a, b], "清单按路径字典序，行号升序（面板行序不能抖）")
        XCTAssertEqual(set.listing.first?.lines, [1, 3])
    }

    func testClearAndRemoveAll() {
        var set = DebugBreakpointSet()
        set.toggle(path: a, line: 1)
        set.toggle(path: b, line: 2)
        set.clear(path: a)
        XCTAssertEqual(set.count, 1)
        set.removeAll()
        XCTAssertTrue(set.isEmpty)
        XCTAssertEqual(set.dapMap(), [:])
    }
}
