import Foundation

/// 计划修订（`FR-AGT-PLAN-PLAN-004`）：执行中发现原计划不成立时，
/// **说出为什么改 + 给出新计划**，不许静默换路。
///
/// 判据：
/// ① 每一次改道都要一条记录：原步骤 → 新步骤 → 触发事实 → 理由（理由空 = 拒收，记不下来）；
/// ② 「静默换路」= 有步骤被换掉但日志里没有对应记录 ⇒ 可以机械查出来；
/// ③ 修订记录只追加不改写（谁改的、什么时候都在日志里）。
public struct AgentPlanRevision: Equatable, Sendable {
    public var stepID: String
    public var before: String
    public var after: String
    /// 触发事实（观察到什么让原计划不成立）—— 必填。
    public var trigger: String
    /// 为什么改成这样 —— 必填。
    public var reason: String
    public var at: Date

    public init(stepID: String, before: String, after: String, trigger: String, reason: String, at: Date = Date()) {
        self.stepID = stepID
        self.before = before
        self.after = after
        self.trigger = trigger
        self.reason = reason
        self.at = at
    }
}

public enum AgentPlanRevisionError: Error, Equatable, Sendable {
    /// 没写理由 —— 拒收（静默换路就是这么长出来的）。
    case missingReason
    /// 没写触发事实 —— 拒收。
    case missingTrigger
}

public struct AgentPlanRevisionLog: Sendable {
    private(set) public var revisions: [AgentPlanRevision] = []

    public init() {}

    @discardableResult
    public mutating func record(stepID: String, before: String, after: String,
                                trigger: String, reason: String, at: Date = Date()) throws -> AgentPlanRevision {
        guard !trigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentPlanRevisionError.missingTrigger
        }
        guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentPlanRevisionError.missingReason
        }
        let revision = AgentPlanRevision(stepID: stepID, before: before, after: after,
                                         trigger: trigger, reason: reason, at: at)
        revisions.append(revision)
        return revision
    }

    /// 某一步改过几次（0 = 没改过）。
    public func revisionCount(for stepID: String) -> Int {
        revisions.filter { $0.stepID == stepID }.count
    }

    /// 静默换路检查：`planned` 是原计划（步骤 ID → 文案），`executed` 是实际执行的（步骤 ID → 文案）。
    /// 同一 ID 文案变了但日志里没有该 ID 的修订 ⇒ 这就是静默换路。
    public func silentReroutes(planned: [String: String], executed: [String: String]) -> [String] {
        executed.compactMap { id, text in
            guard let old = planned[id], old != text else { return nil }
            return revisionCount(for: id) == 0 ? id : nil
        }.sorted()
    }

    /// 给用户看的一句话（有改动才出，没改返回 nil）。
    public var summaryLine: String? {
        guard !revisions.isEmpty else { return nil }
        let lines = revisions.map { "· \($0.stepID)：\($0.before) → \($0.after)（因为\($0.trigger)）" }
        return "改计划 \(revisions.count) 次：\n" + lines.joined(separator: "\n")
    }
}
