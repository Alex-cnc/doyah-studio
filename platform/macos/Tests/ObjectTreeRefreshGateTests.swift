import XCTest
@testable import DoyahCore

/// 队列 `L-96`：「**同一次刷新只许有一次在途**」——`ObjectTreeRefreshGate` 的那几条语义。
///
/// 这里判的四件事，每一条都对应一个**真实的错法**：
/// ① 同一把键的第二个来者**并到第一发上**（不是各取一次数）—— 反例就是两条刷新各自查一遍库、
///    谁后落地谁说了算；
/// ② **不同的键互不挡**（换连接之后那一发不许被上一发挡住）—— 反例是闸门做成了全局开关；
/// ③ **第一发失败时，等着的拿到同一个错**，且闸门**当场释放**（不许把键永久封印在在途表里）；
/// ④ **第一发的调用方被取消**（视图被销毁重建时 `.task` 会取消上一发）⇒ 已经发出去的那一发
///    对**眼前这份数据仍然有用**：并上来的人照样拿到它，闸门照样收尾。
///
/// 计数用的是**测试自己给的 `load` 闭包**（数它被调了几次）—— 不是产品代码里的自报数。
@MainActor
final class ObjectTreeRefreshGateTests: XCTestCase {

    /// 计数器 + 一个「把取数按住」的续体表：让「在途」这个状态在测试里**确定性地**停在原地
    /// （不靠 sleep 撞时间）。
    ///
    /// ⚠️ 续体必须**一个一格地存**：两个不同的键同时在途时，单槽会把第一个的续体覆盖掉 ——
    /// 那一发永远醒不过来，测试挂死（本轮实测踩过：判据自己成了死锁）。
    @MainActor
    private final class LoadProbe {
        var calls = 0
        private var pending: [CheckedContinuation<Void, Never>] = []

        var inFlight: Int { pending.count }

        func make(error: Error? = nil) -> () async throws -> [DatabaseObject] {
            { [self] in
                calls += 1
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    pending.append(continuation)
                }
                if let error { throw error }
                return [DatabaseObject(id: "server/db", name: "db", kind: .server)]
            }
        }

        /// 按到达顺序放行前 `count` 发。
        func letGo(count: Int = 1) {
            let allowed = min(count, pending.count)
            guard allowed > 0 else { return }
            let going = Array(pending.prefix(allowed))
            pending.removeFirst(allowed)
            for continuation in going { continuation.resume() }
        }
    }

    private func root(_ name: String) -> DatabaseObject {
        DatabaseObject(id: "server/\(name)", name: name, kind: .server)
    }

    private let keyA = ObjectTreeRefreshKey(connectionID: UUID(), revision: 0)
    private let keyB = ObjectTreeRefreshKey(connectionID: UUID(), revision: 0)

    // MARK: - ① 同键第二发：并进第一发，不再取数

    func testSecondCallerWithSameKeyJoinsTheFirst() async throws {
        let gate = ObjectTreeRefreshGate()
        let probe = LoadProbe()
        let load = probe.make()

        let first = Task { try await gate.roots(for: keyA, load: load) }
        await waitUntil { probe.calls == 1 }
        let second = Task { try await gate.roots(for: keyA, load: load) }
        await settle(turns: 8)

        XCTAssertEqual(gate.loadStats.started, 1, "第一发之外又开了一发 —— 闸门没拦住")
        XCTAssertEqual(gate.loadStats.joined, 1, "第二个来者没有并到第一发上")
        XCTAssertEqual(gate.inFlightCount, 1)
        XCTAssertEqual(probe.calls, 1, "同一次刷新取了两遍数")

        probe.letGo()
        let fromFirst = try await awaiting(first)
        let fromSecond = try await awaiting(second)
        XCTAssertEqual(fromFirst, fromSecond, "并上来的那一发拿到的不是同一份结果")
        XCTAssertEqual(probe.calls, 1)
        XCTAssertEqual(gate.inFlightCount, 0, "收尾之后键还留在在途表里")
    }

    // MARK: - ② 不同的键互不挡

    func testDifferentKeysLoadIndependently() async throws {
        let gate = ObjectTreeRefreshGate()
        let probe = LoadProbe()
        let load = probe.make()

        let first = Task { try await gate.roots(for: keyA, load: load) }
        await waitUntil { probe.calls == 1 }
        let second = Task { try await gate.roots(for: keyB, load: load) }
        await waitUntil { probe.calls == 2 }
        XCTAssertEqual(gate.loadStats.joined, 0, "不同的键被告成同一次刷新")

        probe.letGo(count: 2)
        _ = try await awaiting(first)
        _ = try await awaiting(second)
        XCTAssertEqual(probe.calls, 2, "换了键却没再取数 —— 闸门做成了全局开关")
        XCTAssertEqual(gate.inFlightCount, 0)
    }

    // MARK: - ③ 第一发失败：等着的拿到同一个错，闸门释放

    func testFailureReachesJoinersAndReleasesTheKey() async throws {
        struct Boom: Error, Equatable { let text: String }
        let gate = ObjectTreeRefreshGate()
        let probe = LoadProbe()
        let failing = probe.make(error: Boom(text: "连不上"))

        let first = Task { try await gate.roots(for: keyA, load: failing) }
        await waitUntil { probe.calls == 1 }
        let second = Task { try await gate.roots(for: keyA, load: failing) }
        await settle(turns: 8)
        XCTAssertEqual(probe.calls, 1, "失败之前又开了一发")

        probe.letGo()

        do {
            _ = try await awaiting(second)
            XCTFail("并上来的那一发没有拿到第一发的错")
        } catch let error as Boom {
            XCTAssertEqual(error, Boom(text: "连不上"))
        }
        _ = try? await awaiting(first)
        XCTAssertEqual(gate.inFlightCount, 0, "失败之后键没摘掉 —— 这一把键从此刷不出来")

        // 释放之后同一把键可以再来
        _ = try await gate.roots(for: keyA, load: { [self] in [root("retry")] })
        XCTAssertEqual(gate.loadStats.started, 2, "键被永久封印了：失败之后同键再也取不到数")
    }

    // MARK: - ④ 第一发的调用方被取消（视图销毁）：并上来的人照样拿到数据

    func testCancellingTheFirstCallerKeepsTheLoadAliveForJoiners() async throws {
        let gate = ObjectTreeRefreshGate()
        let probe = LoadProbe()
        let load = probe.make()

        let first = Task { try await gate.roots(for: keyA, load: load) }
        await waitUntil { probe.calls == 1 }
        let second = Task { try await gate.roots(for: keyA, load: load) }
        await settle(turns: 8)

        // 视图被销毁重建：上一发的 `.task` 被取消。
        first.cancel()
        await settle(turns: 4)
        XCTAssertEqual(probe.calls, 1, "取消把「已经发出去的那一发」也带走了 —— 新起来的实例就没得可并")

        probe.letGo()
        let fromSecond = try await awaiting(second)
        XCTAssertEqual(fromSecond.count, 1, "并上来的人没拿到数据")
        _ = try? await awaiting(first)
        XCTAssertEqual(gate.inFlightCount, 0, "取消之后键没摘掉")
    }

    // MARK: - 辅助：确定性地等（不用 sleep 撞时间）

    private struct TimedOut: Error {}

    /// 等一个子任务，**带超时**。
    ///
    /// 为什么不能直接 `await task.value`：判据一旦写错（例如续体没人放行），`await` 会**永远等下去**，
    /// 整个测试进程跟着挂死 —— 门禁不是「红」，而是**跑不完**。本轮实测踩过一次（单槽续体被覆盖）。
    private func awaiting<T: Sendable>(_ task: Task<T, Error>, seconds: Double = 5) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await task.value }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimedOut()
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw TimedOut() }
            return first
        }
    }

    /// 等条件成立，靠 `Task.yield()` 让出主 actor（每一轮都换一次调度机会）。
    private func waitUntil(timeoutTurns: Int = 200, _ condition: () -> Bool) async {
        for _ in 0..<timeoutTurns {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("等条件成立等超时了（\(timeoutTurns) 轮让出）")
    }

    /// 让出若干轮，把子任务推进到「已登记 / 已挂起」。
    private func settle(turns: Int) async {
        for _ in 0..<turns {
            await Task.yield()
        }
    }
}
