import XCTest
@testable import DoyahRetroCore

// `FR-RTR-MKT-FEED-002` 幂等落库的机械证据
// （执行契约 §16.4：幂等键四要素 · 同键覆盖不追加 · 单标事务不落半截行 · 缺量不填 0）。
//
// 纪律：断言的是**行数与内容**，不是「没崩」；同键重跑后行数不增长是这条判据的正面证据。

final class IdempotentBarStoreTests: XCTestCase {

    private func row(_ symbol: String = "600000", day: String = "2026-03-09",
                     adjustment: String = "不复权", close: Decimal = 10, volume: Decimal? = 1000,
                     source: String = "src-a") -> BarRow {
        BarRow(
            key: BarKey(symbol: symbol, period: "1d", tradingDay: day, adjustment: adjustment),
            open: close, high: close, low: close, close: close, volume: volume, source: source
        )
    }

    /// 同键重跑 ⇒ 覆盖不追加（行数恒为 1，值取最后一次）。
    func testSameKeyOverwritesInsteadOfAppending() {
        var store = IdempotentBarStore()
        store.upsert(row(close: 10))
        store.upsert(row(close: 12))
        XCTAssertEqual(store.count, 1, "同键重跑不许追加第二行")
        XCTAssertEqual(store.rows(symbol: "600000").map(\.close), [12])
    }

    /// 复权方式是键的一部分：同日同标的不同复权 ⇒ 两行（互不覆盖）。
    func testAdjustmentIsPartOfTheKey() {
        var store = IdempotentBarStore()
        store.upsert(row(adjustment: "不复权"))
        store.upsert(row(adjustment: "前复权"))
        XCTAssertEqual(store.count, 2)
    }

    /// 单标事务：commit 之前读方看不见暂存行。
    func testStagedRowsInvisibleBeforeCommit() {
        var store = IdempotentBarStore()
        store.stage(row(day: "2026-03-09"))
        store.stage(row(day: "2026-03-10"))
        XCTAssertEqual(store.count, 0, "commit 前不可见")
        XCTAssertTrue(store.rows(symbol: "600000").isEmpty)
        store.commit(symbol: "600000")
        XCTAssertEqual(store.count, 2)
    }

    /// 失败不落半截行：整标回滚后一行都不留（半个标的比没有更坏）。
    func testRollbackLeavesNoHalfWrittenSymbol() {
        var store = IdempotentBarStore()
        store.stage(row(day: "2026-03-09"))
        store.stage(row(day: "2026-03-10"))
        store.rollback(symbol: "600000")
        XCTAssertEqual(store.count, 0)
        XCTAssertTrue(store.rows(symbol: "600000").isEmpty)
    }

    /// 一个标的失败不牵连另一个标的（事务边界按标的）。
    func testCommitIsPerSymbol() {
        var store = IdempotentBarStore()
        store.stage(row("600000", day: "2026-03-09"))
        store.stage(row("000001", day: "2026-03-09"))
        store.commit(symbol: "600000")
        XCTAssertEqual(store.count, 1)
        store.rollback(symbol: "000001")
        XCTAssertEqual(store.count, 1)
        XCTAssertTrue(store.rows(symbol: "000001").isEmpty)
    }

    /// 成交量缺列 = 缺失（nil），不许被填成 0（公共口径 D）。
    func testMissingVolumeStaysMissing() {
        var store = IdempotentBarStore()
        store.upsert(row(volume: nil))
        XCTAssertNil(store.rows(symbol: "600000").first?.volume, "缺失不等于 0")
        store.upsert(row(volume: 0))
        XCTAssertEqual(store.rows(symbol: "600000").first?.volume, 0, "真实零要能存")
    }

    /// 读出的行是全序（交易日升序），不依赖字典遍历顺序。
    func testRowsAreFullyOrdered() {
        var store = IdempotentBarStore()
        for day in ["2026-03-11", "2026-03-09", "2026-03-10"] { store.upsert(row(day: day)) }
        XCTAssertEqual(store.rows(symbol: "600000").map(\.key.tradingDay),
                       ["2026-03-09", "2026-03-10", "2026-03-11"])
    }
}
