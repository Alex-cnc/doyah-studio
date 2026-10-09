import XCTest
@testable import DoyahCore

/// 同步内核的**脱网单测**（契约 `Docs/需求规范书.md` §6.4.2 的 `IR-15` / `IR-16` / `IR-17` / `IR-21`
/// 里「不接网络也能判」的那一半）。
///
/// 这里刻意**一行网络调用都没有**：三态回执、墓碑、增量游标、队列与退避全是纯逻辑，
/// 判据是它们自己的返回值（不是「跑通了就算」）。网络接线由共享逻辑层的同步模块另片落，
/// 判据也在那片。
final class NoteSyncTests: XCTestCase {

    /// 可注入时钟：退避序列靠它断言，**不依赖真实等待**。
    private final class TestClock: @unchecked Sendable {
        var now: Date
        init(_ now: Date) { self.now = now }
        func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
    }

    private func stamp(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    private func record(
        uid: String = "note-1",
        rev: Int,
        updatedAt: TimeInterval,
        deletedAt: TimeInterval? = nil,
        payload: String = ""
    ) -> SyncRecord {
        SyncRecord(
            uid: uid,
            rev: rev,
            updatedAt: stamp(updatedAt),
            deletedAt: deletedAt.map(stamp),
            deviceId: "mac-a",
            payload: payload
        )
    }

    // MARK: - 三态 ① 已接收（`IR-16`）

    /// `rev` 更大 ⇒ 已接收 · **本地覆盖**。
    func testNewerRevisionIsAcceptedAndOverwritesLocal() {
        var ledger = SyncLedger()
        ledger.apply(record(rev: 1, updatedAt: 100, payload: "v1"))

        let merge = ledger.apply(record(rev: 2, updatedAt: 200, payload: "v2"))

        XCTAssertEqual(merge.verdict, .accepted)
        XCTAssertEqual(merge.primary.payload, "v2")
        XCTAssertNil(merge.conflict, "已接收这一态不该留冲突版")
        XCTAssertEqual(ledger.record(uid: "note-1")?.rev, 2)
        XCTAssertEqual(ledger.record(uid: "note-1")?.payload, "v2")
        XCTAssertTrue(ledger.conflicts.isEmpty)
    }

    /// 本地还没有这一行 ⇒ 首次见到就接收（幂等键的第一种情形）。
    func testFirstSightOfARecordIsAccepted() {
        var ledger = SyncLedger()
        let merge = ledger.apply(record(rev: 7, updatedAt: 500, payload: "new"))

        XCTAssertEqual(merge.verdict, .accepted)
        XCTAssertEqual(ledger.uids, ["note-1"])
        XCTAssertEqual(ledger.visible.map(\.payload), ["new"])
    }

    // MARK: - 三态 ② 已过期（`IR-16`）

    /// `rev` 更小 ⇒ 已过期 · **本地不变**。
    func testOlderRevisionIsExpiredAndLocalStaysUntouched() {
        var ledger = SyncLedger()
        ledger.apply(record(rev: 5, updatedAt: 500, payload: "local-newer"))

        let merge = ledger.apply(record(rev: 4, updatedAt: 900, payload: "cloud-older-rev"))

        XCTAssertEqual(merge.verdict, .expired)
        XCTAssertEqual(merge.primary.payload, "local-newer", "已过期这一态：本地一字不动")
        XCTAssertNil(merge.conflict)
        XCTAssertEqual(ledger.record(uid: "note-1")?.rev, 5)
        XCTAssertEqual(ledger.record(uid: "note-1")?.payload, "local-newer")
        XCTAssertTrue(ledger.conflicts.isEmpty, "已过期是丢弃，不是冲突 —— 不许顺手留一版")
    }

    // MARK: - 三态 ③ 冲突留两版（`IR-16`）

    /// `rev` 相同而 `updatedAt` 不同 ⇒ **冲突留两版**（两版都在，不静默丢弃）。
    func testEqualRevisionWithDifferentTimestampKeepsBothVersions() {
        var ledger = SyncLedger()
        ledger.apply(record(rev: 3, updatedAt: 300, payload: "local"))
        let merge = ledger.apply(record(rev: 3, updatedAt: 400, payload: "cloud"))

        XCTAssertEqual(merge.verdict, .conflict)
        XCTAssertEqual(merge.conflict?.payload, "local", "被留下的那一版要交回调用方")
        XCTAssertEqual(merge.primary.payload, "cloud", "同版本下 `updatedAt` 大的一版做主版本")

        let versions = ledger.allVersions(uid: "note-1")
        XCTAssertEqual(versions.count, 2, "冲突留两版：两版都要在账里")
        XCTAssertEqual(Set(versions.map(\.payload)), ["local", "cloud"])
        XCTAssertEqual(ledger.conflicts.count, 1)
    }

    /// 同版本 + 同 `updatedAt`（只有快照不同）⇒ 也留两版，且**主版本确定**（本地留主：同输入必同输出）。
    func testEqualRevisionAndTimestampWithDifferentPayloadAlsoKeepsBoth() {
        var ledger = SyncLedger()
        ledger.apply(record(rev: 9, updatedAt: 900, payload: "a"))

        let merge = ledger.apply(record(rev: 9, updatedAt: 900, payload: "b"))

        XCTAssertEqual(merge.verdict, .conflict)
        XCTAssertEqual(merge.primary.payload, "a", "时刻也相同 ⇒ 本地留作主版本（确定性）")
        XCTAssertEqual(merge.conflict?.payload, "b")
        XCTAssertEqual(ledger.allVersions(uid: "note-1").count, 2)
    }

    /// 幂等键（`uid` + `rev`）命中且内容一致 ⇒ 已接收，**不产生新版本、不报冲突**。
    func testIdenticalReplayOfTheSameIdentityIsAcceptedAndAddsNothing() {
        var ledger = SyncLedger()
        let version = record(rev: 2, updatedAt: 200, payload: "same")
        ledger.apply(version)

        let merge = ledger.apply(version)

        XCTAssertEqual(merge.verdict, .accepted)
        XCTAssertNil(merge.conflict)
        XCTAssertEqual(ledger.allVersions(uid: "note-1").count, 1, "同一次写入的重放不许堆版本")
        XCTAssertEqual(version.identity, SyncIdentity(uid: "note-1", rev: 2), "幂等键 = uid + rev")
    }

    // MARK: - 墓碑（`IR-17`）

    /// `deletedAt` 非空 ⇒ 本地按墓碑删（不进 `visible`），但**物理行不删**（行仍在账里）。
    func testTombstoneHidesTheNoteLocallyButKeepsThePhysicalRow() {
        var ledger = SyncLedger()
        ledger.apply(record(rev: 1, updatedAt: 100, payload: "alive"))
        XCTAssertEqual(ledger.visible.count, 1)

        let merge = ledger.apply(record(rev: 2, updatedAt: 300, deletedAt: 300, payload: "alive"))

        XCTAssertEqual(merge.verdict, .accepted)
        XCTAssertTrue(ledger.visible.isEmpty, "本地按墓碑删：它不该再出现在活行里")
        XCTAssertNotNil(ledger.record(uid: "note-1"), "物理行不删 —— 那一行还在账里")
        XCTAssertEqual(ledger.record(uid: "note-1")?.isTombstone, true)
        XCTAssertEqual(ledger.tombstones.map(\.uid), ["note-1"])
    }

    /// 更旧的墓碑压不过更新的活行（墓碑也是一版记录：§6.4.2 的 `rev` 决胜对墓碑同样成立）。
    func testStaleTombstoneCannotDeleteANewerLocalRow() {
        var ledger = SyncLedger()
        ledger.apply(record(rev: 4, updatedAt: 400, payload: "edited-after-delete"))

        let merge = ledger.apply(record(rev: 2, updatedAt: 200, deletedAt: 200, payload: "deleted"))

        XCTAssertEqual(merge.verdict, .expired)
        XCTAssertEqual(ledger.visible.count, 1)
        XCTAssertTrue(ledger.tombstones.isEmpty)
    }

    // MARK: - 增量游标（`IR-15`）

    /// 游标按「本页最大时刻」推进；与游标**同刻**的行不被跳过（U+1 记在边界里）。
    func testCursorAdvancesByNewestStampAndDoesNotSkipBoundaryRows() {
        var cursor = SyncCursor()
        let page1 = [
            record(uid: "n1", rev: 1, updatedAt: 100, payload: "p1"),
            record(uid: "n2", rev: 1, updatedAt: 200, payload: "p2"),
            record(uid: "n3", rev: 1, updatedAt: 200, payload: "p3"),
        ]

        XCTAssertEqual(cursor.unseen(in: page1).count, 3, "空游标 ⇒ 整页都要处理")
        cursor.advance(with: page1)

        XCTAssertEqual(cursor.updatedAfter, stamp(200))
        XCTAssertEqual(cursor.boundaryUIDs, ["n2", "n3"], "同刻的行要记住，否则下一轮会把它们重复拉回来")

        // 下一页里：已处理过的同刻行滤掉、同刻的**新**行仍要处理、更新的行当然要处理。
        let page2 = [
            record(uid: "n2", rev: 1, updatedAt: 200, payload: "p2"),
            record(uid: "n4", rev: 1, updatedAt: 200, payload: "p4"),
            record(uid: "n5", rev: 1, updatedAt: 300, payload: "p5"),
        ]
        XCTAssertEqual(cursor.unseen(in: page2).map(\.uid), ["n4", "n5"])

        cursor.advance(with: page2)
        XCTAssertEqual(cursor.updatedAfter, stamp(300))
        XCTAssertEqual(cursor.boundaryUIDs, ["n5"])
    }

    /// 乱序回包与空页不许把游标往回退（退回去 = 已处理的整段被重新拉一遍）。
    func testCursorNeverGoesBackwards() {
        var cursor = SyncCursor(updatedAfter: stamp(500), boundaryUIDs: ["n5"])

        cursor.advance(with: [])                                   // 空页
        XCTAssertEqual(cursor.updatedAfter, stamp(500))

        cursor.advance(with: [record(uid: "n9", rev: 1, updatedAt: 100)])   // 整页更旧
        XCTAssertEqual(cursor.updatedAfter, stamp(500))
        XCTAssertEqual(cursor.boundaryUIDs, ["n5"])
        XCTAssertTrue(cursor.unseen(in: [record(uid: "n9", rev: 1, updatedAt: 100)]).isEmpty)
    }

    // MARK: - 离线队列与退避（`IR-21`）

    /// 入队：同一条 `uid` 只欠一次（重复入队不新增条目），且**后写覆盖操作种类**。
    func testEnqueueKeepsOneEntryPerUIDAndLatestOperationWins() {
        let clock = TestClock(stamp(1_000))
        var queue = SyncQueue(now: { clock.now })

        XCTAssertTrue(queue.enqueue(uid: "n1", operation: .upsert))
        XCTAssertFalse(queue.enqueue(uid: "n1", operation: .upsert), "同一条 uid 不许入队两次")
        XCTAssertEqual(queue.pendingCount, 1)

        XCTAssertFalse(queue.enqueue(uid: "n1", operation: .delete))
        XCTAssertEqual(queue.entry(uid: "n1")?.operation, .delete, "后写的操作种类覆盖先写的")

        XCTAssertTrue(queue.enqueue(uid: "n2"))
        XCTAssertEqual(queue.ready(at: clock.now).map(\.uid), ["n1", "n2"], "重放按入队序")
    }

    /// 出队只在成功之后：`dequeue` 之后那条不再出现在待办里，重新入队是一条**新**条目（失败计数归零）。
    func testDequeueOnSuccessRemovesOnlyThatEntry() {
        let clock = TestClock(stamp(1_000))
        var queue = SyncQueue(now: { clock.now })
        queue.enqueue(uid: "n1")
        queue.enqueue(uid: "n2")
        XCTAssertNotNil(queue.fail(uid: "n1"), "先让它失败一次，验出队后计数确实归零")

        XCTAssertTrue(queue.dequeue(uid: "n1"))
        XCTAssertFalse(queue.dequeue(uid: "n1"), "已经出队了，第二次不该报成功")
        XCTAssertEqual(queue.entries.map(\.uid), ["n2"])

        XCTAssertTrue(queue.enqueue(uid: "n1"))
        XCTAssertEqual(queue.entry(uid: "n1")?.attempts, 0)
        XCTAssertEqual(queue.entry(uid: "n1")?.nextAttemptAt, clock.now, "新条目当场可重放")
    }

    /// **失败 ⇒ 退避序列单调递增 + 上限封顶**（用可注入时钟断言，不依赖真实等待）。
    func testRetryBackoffGrowsMonotonicallyAndStopsAtTheCeiling() {
        let clock = TestClock(stamp(1_000))
        let policy = SyncRetryPolicy(baseDelay: 2, multiplier: 2, maxDelay: 300)
        var queue = SyncQueue(policy: policy, now: { clock.now })
        queue.enqueue(uid: "n1")

        var applied: [TimeInterval] = []
        for _ in 0..<12 {
            guard let delay = queue.fail(uid: "n1") else {
                return XCTFail("队列里应当还有这一条 —— 失败不许把它出队")
            }
            // 时钟是可注入的那一个：本轮等待 == `nextAttemptAt - 注入的「现在」`。
            let wait = try? XCTUnwrap(queue.entry(uid: "n1")).nextAttemptAt.timeIntervalSince(clock.now)
            XCTAssertEqual(wait ?? -1, delay, "退避要落在注入时钟上，而不是墙上时钟")
            applied.append(delay)
            clock.advance(delay)   // 只推进注入的时钟，不真等
        }

        XCTAssertEqual(applied, [2, 4, 8, 16, 32, 64, 128, 256, 300, 300, 300, 300])
        for (previous, next) in zip(applied, applied.dropFirst()) {
            XCTAssertGreaterThanOrEqual(next, previous, "退避只许往上走，不许回落")
        }
        XCTAssertEqual(applied.last, 300, "上限封顶")
        XCTAssertFalse(applied.contains { $0 > 300 })
        XCTAssertEqual(queue.entry(uid: "n1")?.attempts, 12, "失败次数逐次累加（不因别的写入重置）")
        XCTAssertEqual(queue.entry(uid: "n1")?.nextAttemptAt, clock.now, "第 12 轮之后恰好到点")

        // 到点前 / 到点后：`ready(at:)` 的边界，同样只看注入的时钟。
        XCTAssertTrue(queue.ready(at: clock.now.addingTimeInterval(-0.5)).isEmpty, "没到点不许重放")
        XCTAssertEqual(queue.ready(at: clock.now).map(\.uid), ["n1"])
    }
}
