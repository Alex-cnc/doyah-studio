import Foundation

/// **IM 侧「同一件事只说一遍」的闸门**（Core 里的纯值类型，视图与判据读同一份）。
///
/// 2026-11-14 真机：手机上一串「没有待批的单」刷了 20 多条，后面还跟着两张一模一样的审批卡。
/// 两个原因都不是「推送写错了」，是**没有去重**：
///
/// · QQ 的 `INTERACTION_CREATE`（按钮点击）是**带重试**的推送 —— 我们 ACK 慢一次，
///   同一个 `interaction_id` 就再来一遍；原先每个事件回一句话 ⇒ 重试 20 次，手机上 20 条；
/// · 一轮里同一张审批单会被**反复要确认**（工具重试），原先每次都推卡 ⇒ 手机上两张码不同的卡。
///
/// 纪律：
/// ① 一次点击只回一句话 —— 按 `interaction_id` 记最近 200 个（够覆盖平台重试窗口）；
/// ② 同一张单只推一次 —— 按**码**记 900 秒（与远程票据的过期时间同一档），过期自然忘掉；
/// ③ 只记标识，不存内容；容量满了先丢最旧的。
public struct AgentIMFloodGate: Sendable {

    /// 审批码的记忆时长（秒）：与远程票据 900 秒过期同一档。
    public var approvalTTL: TimeInterval
    /// 记住多少个点击（平台的同一个事件重试窗口远小于这个数）。
    public var interactionMemory: Int

    private var pushedApprovals: [String: Date] = [:]
    private var handledInteractions: Set<String> = []
    private var interactionOrder: [String] = []

    public init(approvalTTL: TimeInterval = 900, interactionMemory: Int = 200) {
        self.approvalTTL = approvalTTL
        self.interactionMemory = interactionMemory
    }

    /// 这张单要不要推？`true` = 还没推过（并且已经在里面记下了）。
    public mutating func shouldPushApproval(code: String, at now: Date = Date()) -> Bool {
        guard !code.isEmpty else { return false }
        if let pushedAt = pushedApprovals[code], now.timeIntervalSince(pushedAt) < approvalTTL {
            return false
        }
        pushedApprovals[code] = now
        if pushedApprovals.count > 64 {
            let cutoff = now.addingTimeInterval(-approvalTTL)
            pushedApprovals = pushedApprovals.filter { $0.value > cutoff }
        }
        return true
    }

    /// 这次点击要不要回话？`true` = 第一次见（并且已经记下）。
    public mutating func shouldReplyToInteraction(id: String) -> Bool {
        guard !id.isEmpty else { return false }
        if handledInteractions.contains(id) { return false }
        handledInteractions.insert(id)
        interactionOrder.append(id)
        if interactionOrder.count > interactionMemory {
            let dropped = interactionOrder.removeFirst()
            handledInteractions.remove(dropped)
        }
        return true
    }

    /// 同一张单已经推过多久（秒）；没推过返回 `nil`。日志用。
    public func ageOfPushedApproval(code: String, at now: Date = Date()) -> TimeInterval? {
        guard let pushedAt = pushedApprovals[code] else { return nil }
        return now.timeIntervalSince(pushedAt)
    }
}
