import Foundation

/// 连接状态机（概设 §6.1 闭集，详设 §4.4 第一台）。
///
/// **闭集**：只有这五个状态，不允许新增。任何新增状态都必须先改概设 §6.1。
/// - `idle`：未连接（还没试过，或已被复位）
/// - `connecting`：正在建立连接
/// - `connected`：已连接，可用
/// - `failed`：最近一次连接失败（原因由呈现层给，状态本身不带字符串，便于断言）
/// - `disconnected`：曾经连上、后来主动断开
///
/// 反例是这台机的重点：**`failed` 不可直跳 `connected`** —— 必须重新经过 `connecting`，
/// 否则「重试」就成了把旧失败悄悄改成成功。
public enum ConnectionState: String, Equatable, Sendable, CaseIterable {
    case idle
    case connecting
    case connected
    case failed
    case disconnected

    /// 允许的流转表（唯一真源；`AppState` 与测试都读这里，不各写一份）。
    public static let allowedTransitions: [ConnectionState: Set<ConnectionState>] = [
        .idle: [.connecting],
        .connecting: [.connected, .failed, .idle],
        .connected: [.disconnected, .failed],
        // 失败后只允许重新连（或复位）；**不包含 .connected**
        .failed: [.connecting, .idle],
        .disconnected: [.connecting, .idle],
    ]

    /// 从 `self` 到 `next` 是否合法。
    public func canTransition(to next: ConnectionState) -> Bool {
        Self.allowedTransitions[self]?.contains(next) ?? false
    }

    /// 合法则返回 `next`，非法返回 `nil`（调用方必须处理 `nil`，不许静默当成功）。
    public func transition(to next: ConnectionState) -> ConnectionState? {
        canTransition(to: next) ? next : nil
    }

    /// 闭集清单（判据用：任何「多出来的状态」都表示有人动了闭集）。
    public static var closedSet: [String] { allCases.map(\.rawValue).sorted() }
}
