import Foundation
import DoyahCore

/// `query_db` 的执行器（`FR-AI-20` ①）—— 挂在**当前选中连接**上跑。
///
/// ## A 口径（人类主人 2026-10-15 拍板）
///
/// 只回**结构 / 行数 / 语句类型**，**行数据就地丢弃**。这不是"我们自觉不发"：`AgentQueryExecution`
/// 这个类型**根本没有行数据字段** —— 口径由类型保证，后来的人想发也发不出去。
///
/// ## 为什么要这层桥
///
/// `AgentQueryExecutor` 是**同步**协议（`AgentLoop` 的分发契约），而查库走的是
/// `DatabaseService.execute` 的**异步**事件流 ⇒ 这里用信号量把结果取回来。**前提**：调用方不在
/// `@MainActor` 上等 —— `Core/AgentLoop.swift` 已把工具分发挪进 `Task.detached`（那一行就是为这件事
/// 加的）；否则主 actor 腾不出来 ⇒ 死锁。改动其中任何一处，都要回来把这里一起看。
///
/// 宿主只暴露**一个注入点**（`execute`）：连接怎么选、服务怎么起、要不要回主 actor，全是宿主内部的事，
/// 这里不猜、也不自己判连接。
struct AgentConnectionQueryExecutor: AgentQueryExecutor {

    /// 宿主给的「跑一次 SQL，把**已脱敏的结构化结果**拿回来」。
    let execute: @Sendable (String) async throws -> AgentQueryExecution

    /// 单次查询上限（防呆：助手卡住不许把整个循环拖死）。
    var timeout: TimeInterval = 30

    init(timeout: TimeInterval = 30, execute: @escaping @Sendable (String) async throws -> AgentQueryExecution) {
        self.timeout = timeout
        self.execute = execute
    }

    func executeReadOnly(sql: String) -> AgentQueryExecution { bridge(sql) }
    func executeWrite(sql: String) -> AgentQueryExecution { bridge(sql) }

    /// 同步等异步：见类型注释里的"前提"。
    private func bridge(_ sql: String) -> AgentQueryExecution {
        // 结果经 box 传递：读在 `wait` 之后、写在 `signal` 之前 ⇒ 有一次确定的 happens-before，
        // 这里不需要再上一把锁（多上一把只会掩盖"到底谁在跨线程"这件事）。
        final class Box: @unchecked Sendable { var value = AgentQueryExecution() }
        let box = Box()
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached(priority: .userInitiated) {
            do { box.value = try await execute(sql) }
            catch { box.value = AgentQueryExecution(errorMessage: error.localizedDescription) }
            semaphore.signal()
        }
        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            return AgentQueryExecution(errorMessage: "查询超过 \(Int(timeout)) 秒还没返回 —— 已放弃等待（语句可能仍在服务端跑）")
        }
        return box.value
    }
}
