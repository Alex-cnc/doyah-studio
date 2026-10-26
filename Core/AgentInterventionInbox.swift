import Foundation

/// **中途干预信箱**（`FR-AGT-UX-CONV-007` / 本端计划 P1-8 的接线件）。
///
/// 循环在后台跑、界面在另一侧写 —— 所以这里必须是**引用类型 + 锁**：
/// 界面线程 `enqueue`，循环在**每跳边界** `drain`。语义由 `AgentInterventionQueue` 定（当前步后生效）。
public final class AgentInterventionInbox: @unchecked Sendable {
    private let lock = NSLock()
    private var queue = AgentInterventionQueue()

    public init() {}

    /// 界面侧调用：把一条干预挂到「第 step 步之后」。
    public func enqueue(_ intervention: AgentIntervention, duringStep step: Int) {
        lock.lock(); defer { lock.unlock() }
        queue.enqueue(intervention, duringStep: step)
    }

    /// 循环侧调用：第 step 步做完后取走已生效的干预（按入队顺序）。
    public func drain(afterCompleting step: Int) -> [AgentIntervention] {
        lock.lock(); defer { lock.unlock() }
        return queue.drain(afterCompleting: step)
    }

    /// 有没有排队的停手请求（界面「停手」按钮可据此置灰）。
    public var hasPendingStop: Bool {
        lock.lock(); defer { lock.unlock() }
        return queue.stopsRequested
    }

    public var isEmpty: Bool {
        lock.lock(); defer { lock.unlock() }
        return queue.isEmpty
    }

    /// 判据用：当前排队条数。
    public var pendingCount: Int {
        lock.lock(); defer { lock.unlock() }
        return queue.pending.count
    }
}
