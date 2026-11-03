import XCTest

import DoyahCore

/// `FR-STD-DB-META-006` · 「连不上的库」：**同一把刷新键的自动取数有上限**。
///
/// 由头（2026-11-03 人类主人真机点验）：「连一个连不上的地址（如 `127.0.0.1:1`）后，
/// 对象树不停地自己刷新，像在无限重试」。
///
/// 这一份判的是**策略**这一层（纯函数），视图那一层由
/// `TestsUISnapshot/ObjectTreeDeadConnectionProbeTests` 用真宿主 + 真死地址判。
final class ObjectTreeLoadRetryTests: XCTestCase {

    /// 同一条连接（键里的 `connectionID` 必须**稳定**：每次现取一个 `UUID()` 就是不同的键，
    /// 那会把「同一把键」的预算测成「换了键」—— 本条判据自己踩过这个坑）。
    private let connectionID = UUID()

    private func key(_ revision: Int = 0) -> ObjectTreeRefreshKey {
        ObjectTreeRefreshKey(connectionID: connectionID, revision: revision)
    }

    /// ① 首连照常发；一次失败之后**允许**再来一发（这就是"重试一次"的那一发）。
    func testFirstLoadAndOneRetryAreAllowed() {
        var retry = ObjectTreeLoadRetry()
        let k = key()
        XCTAssertTrue(retry.beginAutomatic(for: k), "首连被挡住了 —— 连不上也算一次正常尝试")
        XCTAssertEqual(retry.retryDelayAfterFailure(), .seconds(2), "失败之后应该排一次 2 秒后的自动重试")

        XCTAssertTrue(retry.beginAutomatic(for: k), "一次失败之后的这一发（自动重试）被挡住了")
        XCTAssertNil(retry.retryDelayAfterFailure(), "第二次失败之后还想再排 —— 那就是无限重试")
        XCTAssertTrue(retry.hasGivenUp, "预算用完之后应该登记成「已放弃」")
    }

    /// ② **无限自刷的直接反例**：放弃之后再叫 100 次（`.task(id:)` 在 `List` 里就会被这么叫），
    ///    一次都不许通过。
    func testGivenUpKeyNeverStartsAgain() {
        var retry = ObjectTreeLoadRetry()
        let k = key()
        for _ in 0..<ObjectTreeLoadRetry.automaticBudget {
            XCTAssertTrue(retry.beginAutomatic(for: k))
        }
        for attempt in 0..<100 {
            XCTAssertFalse(
                retry.beginAutomatic(for: k),
                "放弃之后第 \(attempt + 1) 次自动调用仍被放行 —— 这就是真机上那个「不停地自己刷新」"
            )
        }
        XCTAssertEqual(
            retry.usedAutomaticLoads, ObjectTreeLoadRetry.automaticBudget,
            "已经发出去的自动发数不该被反复重算（预算按发数，不按失败次数）"
        )
    }

    /// ③ 换键（换连接 / 元数据版本变了）⇒ 预算重来：那是另一件事，不该被上一把键的失败锁住。
    func testKeyChangeResetsBudget() {
        var retry = ObjectTreeLoadRetry()
        for _ in 0..<ObjectTreeLoadRetry.automaticBudget {
            _ = retry.beginAutomatic(for: key(0))
        }
        XCTAssertFalse(retry.beginAutomatic(for: key(0)))
        XCTAssertTrue(retry.beginAutomatic(for: key(1)), "换了元数据版本还沿用上一把键的「已放弃」")
        XCTAssertFalse(retry.hasGivenUp)
    }

    /// ④ 用户手点「重试」⇒ **恰好再发一发**（需求原文：「它停在那儿，我点重试它再试」）。
    ///
    /// 这一发之后自动路径仍然停在原地（不跟一串自动重试）；而**成功**会把预算复位。
    func testManualRetryFiresExactlyOnce() {
        var retry = ObjectTreeLoadRetry()
        let k = key()
        for _ in 0..<ObjectTreeLoadRetry.automaticBudget { _ = retry.beginAutomatic(for: k) }
        XCTAssertTrue(retry.hasGivenUp)

        retry.beginManual(for: k)
        XCTAssertNil(retry.retryDelayAfterFailure(), "手点之后又排自动重试 —— 用户点一下不该引发一串重试")
        XCTAssertFalse(retry.beginAutomatic(for: k), "手点那一发之后，自动路径还能再发一发 —— 上限没守住")

        // 手点那一发成功 ⇒ 预算复位，回到「首连 + 一次重试」的常态。
        retry.recordSuccess()
        XCTAssertTrue(retry.beginAutomatic(for: k), "成功之后自动路径应恢复正常")
        XCTAssertFalse(retry.hasGivenUp)
    }

    /// ⑤ 成功之后预算复位：下一次真失败仍然「首连 + 一次重试」，不是一次配额用一辈子。
    func testSuccessResetsBudget() {
        var retry = ObjectTreeLoadRetry()
        let k = key()
        _ = retry.beginAutomatic(for: k)
        XCTAssertEqual(retry.retryDelayAfterFailure(), .seconds(2))
        _ = retry.beginAutomatic(for: k)
        XCTAssertTrue(retry.hasGivenUp)

        retry.recordSuccess()
        XCTAssertFalse(retry.hasGivenUp)
        XCTAssertEqual(retry.usedAutomaticLoads, 0)
        XCTAssertTrue(retry.beginAutomatic(for: k), "成功之后同一个键再来一发被挡住了")
    }

    /// ⑥ 退避就那么长：**一次** 2 秒。三次 15 秒的退避对"连不上的地址"是让人盯着转圈，
    ///    而能连上的情况首连就已经连上了（见 `ObjectTreeLoadRetry` 文件头）。
    func testBackoffIsOneShortStep() {
        XCTAssertEqual(ObjectTreeLoadRetry.backoff, [.seconds(2)])
        XCTAssertEqual(ObjectTreeLoadRetry.automaticBudget, 2)
    }
}
