import XCTest
@testable import DoyahRetroCore

// `FR-RTR-RSR-SCENARIO-001` / `FR-RTR-RSR-BACKTEST-001` 未来函数判据的机械证据
// （执行契约 §16.12 ① / §16.13 ①；概要设计 §3.5.12 ①、§3.5.13 ①）。
//
// 纪律：
//   ① **负例必须失败**：构造依赖未来的用例 → 必须抛 `futureData`，不许「返回空也算过」；
//   ② 边界要钉住：`dataDate == cursor` 是**合法**的（游标日是可见的）；
//   ③ 「隐藏后续」是**真取不到**：裁剪后的数组里根本没有未来行，而不是标记为不可见。

final class CursorGuardTests: XCTestCase {

    /// 负例：数据日晚于游标 ⇒ 必抛（零容忍，哪怕只多一天）。
    func testFutureDataThrows() {
        XCTAssertThrowsError(
            try CursorGuard.assertReadable(dataDates: ["2026-03-06", "2026-03-09", "2026-03-10"], cursor: "2026-03-09")
        ) { error in
            XCTAssertEqual(error as? CursorViolation, .futureData(dataDate: "2026-03-10", cursor: "2026-03-09"))
        }
    }

    /// 负例的最小形式：只有一天且就是未来那一天。
    func testSingleFutureRowThrows() {
        XCTAssertThrowsError(try CursorGuard.assertReadable(dataDates: ["2026-03-10"], cursor: "2026-03-09"))
    }

    /// 边界：数据日 == 游标日 ⇒ 合法（契约让游标日当天可见）。
    func testBoundaryEqualsCursorPasses() throws {
        XCTAssertNoThrow(try CursorGuard.assertReadable(dataDates: ["2026-03-09"], cursor: "2026-03-09"))
    }

    /// 空集合 = 无数据，不是未来数据 ⇒ 不抛（「无数据」与「数据日为 0」是两件事）。
    func testEmptyIsNoDataNotViolation() throws {
        XCTAssertNil(CursorGuard.maxDataDate([String]()))
        XCTAssertNoThrow(try CursorGuard.assertReadable(dataDates: [String](), cursor: "2026-03-09"))
    }

    /// 最大数据日是读数来源，取的是最大而不是最后一个（输入顺序无关）。
    func testMaxDataDateIgnoresInputOrder() {
        XCTAssertEqual(CursorGuard.maxDataDate(["2026-03-05", "2026-03-10", "2026-03-07"]), "2026-03-10")
    }

    /// 「真取不到」：裁剪后数组里没有未来行，且保持输入顺序。
    func testReadableDropsFutureRows() {
        struct Row { let day: String; let close: Int }
        let rows = [
            Row(day: "2026-03-05", close: 10),
            Row(day: "2026-03-09", close: 11),
            Row(day: "2026-03-10", close: 99),
        ]
        let kept = CursorGuard.readable(rows, cursor: "2026-03-09", dataDate: \.day)
        XCTAssertEqual(kept.map(\.day), ["2026-03-05", "2026-03-09"])
        XCTAssertFalse(kept.contains { $0.day > "2026-03-09" }, "未来行必须取不到，不是被遮住")
    }

    /// 回退再推进回同一日：同一游标两次裁剪，结果逐值一致（含中间序列）。
    func testRewindThenAdvanceReproducesSameSequence() {
        struct Row { let day: String; let close: Int }
        let rows = (1...20).map { Row(day: String(format: "2026-03-%02d", $0), close: $0) }
        let first = CursorGuard.readable(rows, cursor: "2026-03-10", dataDate: \.day).map(\.close)
        _ = CursorGuard.readable(rows, cursor: "2026-03-15", dataDate: \.day)   // 推进
        _ = CursorGuard.readable(rows, cursor: "2026-03-03", dataDate: \.day)   // 回退
        let second = CursorGuard.readable(rows, cursor: "2026-03-10", dataDate: \.day).map(\.close)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first, Array(1...10))
    }
}
