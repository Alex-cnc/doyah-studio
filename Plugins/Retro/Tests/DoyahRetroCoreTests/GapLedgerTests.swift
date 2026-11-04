import XCTest
@testable import DoyahRetroCore

// `FR-RTR-MKT-HEALTH-001` 缺口四处同源的机械证据
// （执行契约 §16.6 ⑤：图断点 / 表空槽 + 原因 / 导出空单元格 / 统计剔除报 n/N，四处同一份清单）。
//
// 纪律：
//   ① 缺口**不改写成连续**：不插值、不前值填充，表里没有「补出来的行」；
//   ② 豁免只标记不删：停牌日是条目但不算真缺口；
//   ③ 四处投影的缺口集合必须**相同**（少一处即判红）。

final class GapLedgerTests: XCTestCase {

    private let calendar = ["2026-03-05", "2026-03-06", "2026-03-09", "2026-03-10", "2026-03-11"]

    private func ledger(actual: [String] = ["2026-03-05", "2026-03-06", "2026-03-10"],
                        exemptions: [String: GapEntry.Reason] = [:]) -> GapLedger {
        GapLedger(expectedDays: calendar, actualDays: actual, exemptions: exemptions)
    }

    /// 相对交易日历缺行 ⇒ 真缺口，且按交易日升序全序。
    func testMissingDaysAreRealGaps() {
        let l = ledger()
        XCTAssertEqual(l.realGapDays, ["2026-03-09", "2026-03-11"])
        XCTAssertEqual(l.entries.count, 2)
    }

    /// 停牌是豁免：条目在，但不算真缺口（只标记不删数据）。
    func testSuspensionIsExemptionNotGap() {
        let l = ledger(exemptions: ["2026-03-09": .suspended])
        XCTAssertEqual(l.entries.count, 2, "豁免条目仍要留痕")
        XCTAssertEqual(l.realGapDays, ["2026-03-11"], "豁免不进真缺口")
    }

    /// 四处投影同源：集合相等，图表段数 = 缺口数 + 1。
    func testFourProjectionsAgree() {
        let l = ledger()
        XCTAssertTrue(l.projectionsAgree(expectedDays: calendar))
        let chart = l.chartProjection(points: calendar)
        XCTAssertEqual(chart.gapCount, 2)
        XCTAssertEqual(chart.drawableSegments, 3, "两个缺口把序列切成三段")
    }

    /// 统计报 n/N：分母剔除真缺口。
    func testStatsReportsAvailableOverTotal() {
        let stats = ledger().statsProjection(expectedDays: calendar)
        XCTAssertEqual(stats.available, 3)
        XCTAssertEqual(stats.total, 5)
    }

    /// 表格 / 导出：空单元格 + 原因，且**不出现补出来的行**（行数 == 缺口数）。
    func testTableGivesBlankCellWithReasonAndNoFilledRows() {
        let table = ledger().tableProjection()
        XCTAssertEqual(table.count, 2, "不许插值出额外行")
        XCTAssertTrue(table.allSatisfy { $0.cell.isEmpty }, "空单元格，不填 0、不前值填充")
        XCTAssertTrue(table.allSatisfy { $0.reason == "缺行情" })
        XCTAssertEqual(table.map(\.tradingDay), ["2026-03-09", "2026-03-11"])
    }

    /// 豁免不进分母：停牌日在口径上就不该有行情，留在分母里等于把「本来就不该有」记成「缺了」。
    func testExemptionsAreExcludedFromDenominator() {
        let l = ledger(exemptions: ["2026-03-09": .suspended, "2026-03-11": .delisted])
        XCTAssertTrue(l.realGapDays.isEmpty)
        let stats = l.statsProjection(expectedDays: calendar)
        XCTAssertEqual(stats.total, 3, "分母 = 应有 5 − 豁免 2")
        XCTAssertEqual(stats.available, 3, "可用 = 分母 − 真缺口 0")
    }

    /// 两次构造逐行一致（同输入同输出，含顺序）。
    func testSameInputSameLedger() {
        let a = ledger()
        let b = ledger()
        XCTAssertEqual(a.entries, b.entries)
    }
}
