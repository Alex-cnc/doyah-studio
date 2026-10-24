import Foundation

/// 「我自己这条连接在服务端叫什么」—— 会话管理面判「不许终止自己的会话」的唯一依据。
///
/// 为什么单开一个协议而不是往 `DatabaseService` 里加：那是**所有**驱动与测试桩都要满足的
/// 主协议（本仓有 6 个遵循者，其中 3 个是单测桩）。会话号只有真驱动才有，塞进主协议
/// 会让测试桩集体被迫实现一个它们根本没有的概念 —— 于是做成**可选能力**：
/// 会话说得上号的驱动遵循它，判据按 `as?` 取用，取不到就如实降级（不假装自己是别人的会话）。
///
/// 口径（概设 §4.9 · 详设 §6 `SESS_KILL_DENIED`）：
/// - 能取到自己的会话号 ⇒ 目标 pid 与它相等时**当场拒绝**，连语句都不发（发了就是自断连接）；
/// - 取不到 ⇒ 不假判「不是自己的」，交给服务端回答；服务端说没权限就照原话显示。
public protocol OwnSessionReporting: Sendable {
    /// 当前这条连接在服务端的会话号；拿不到（未连接 / 方言无此概念）返回 `nil`。
    func ownSessionPID() async -> Int?
}

extension PostgresService: OwnSessionReporting {
    /// PG：建连时查过一次 `SELECT pg_backend_pid()` 并缓存，这里只交缓存值。
    public func ownSessionPID() async -> Int? { await cachedOwnSessionPID() }
}

extension MySQLService: OwnSessionReporting {
    /// MySQL / GBase：建连时查过 `SELECT CONNECTION_ID()` 并缓存。
    public func ownSessionPID() async -> Int? { await cachedOwnSessionPID() }
}
