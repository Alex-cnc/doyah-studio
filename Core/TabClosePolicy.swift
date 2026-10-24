import Foundation

/// 关闭页签的判定（概设 §6.4 页签状态机 · 详设 §4.4 / 用例 `T-4.4-07`、`T-4.4-08`）。
///
/// 现状是「执行中就静默 return」—— 用户点了没有任何反馈，属于详设 §7.1 第五档（静默失败）。
/// 这里把判定抽成纯函数：返回**为什么不能关**，由装配层负责把它呈现出来。
public enum TabCloseDecision: Equatable, Sendable {
    /// 可以关（内容已保存，且不在执行中）
    case close
    /// 正在执行：拒绝关闭，并说明「先停止」
    case refuseExecuting
    /// 只剩一个页签：拒绝关闭（关了就空白）
    case refuseLastTab
    /// 有未保存改动：需要用户确认后才关
    case needsConfirmation
}

public enum TabClosePolicy {

    /// 判定顺序（固定，不许调换）：
    /// 1. 只剩一个页签 ⇒ 拒绝（关掉就没地方显示，任何确认都无意义）；
    /// 2. 正在执行 ⇒ 拒绝（半途关页签会把结果丢掉，必须先停止）；
    /// 3. 有未保存改动 ⇒ 需确认；
    /// 4. 否则可关。
    public static func decide(isExecuting: Bool, isDirty: Bool, tabCount: Int) -> TabCloseDecision {
        if tabCount <= 1 { return .refuseLastTab }
        if isExecuting { return .refuseExecuting }
        if isDirty { return .needsConfirmation }
        return .close
    }
}

/// 未保存关闭被确认时留下的快照（详设 `T-4.4-08`：确认后**进快照**，不是直接丢掉）。
///
/// 快照只存在内存里，不落盘、不进导出 —— 与 §6.6 数据归属一致（读数与缓冲不落盘）。
public struct ClosedTabSnapshot: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let title: String
    public let sql: String
    public let capturedAt: Date

    public init(id: UUID, title: String, sql: String, capturedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.sql = sql
        self.capturedAt = capturedAt
    }
}

/// 快照栈（有界：只留最近 N 条，避免长会话内存涨）。
public struct ClosedTabSnapshotStore {
    public static let capacity = 20
    private(set) var snapshots: [ClosedTabSnapshot] = []

    public init() {}

    public mutating func push(_ snapshot: ClosedTabSnapshot) {
        snapshots.append(snapshot)
        if snapshots.count > Self.capacity {
            snapshots.removeFirst(snapshots.count - Self.capacity)
        }
    }

    public var latest: ClosedTabSnapshot? { snapshots.last }
}
