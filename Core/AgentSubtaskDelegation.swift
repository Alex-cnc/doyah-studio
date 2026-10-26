import Foundation

/// **系统工具**（`FR-AGT-TOOL-SYS-001/002` / 本端计划 P4-系统）：
/// 界面操作**每步可见**；**子任务委派要标来源**。
///
/// 两件事靠既有类型拼：可见性用 `AgentStepTrace`（一步一行，无静默步），
/// 委派结果必须带「谁派的、哪一轮派的」，否则界面分不清是主循环还是子任务干的。
public enum AgentSubtaskOrigin: Equatable, Sendable {
    /// 主循环自己做的。
    case mainLoop
    /// 某个子任务做的（带子任务标识与发起步号）。
    case subtask(id: String, delegatedAtStep: Int)
}

public struct AgentSubtaskDelegation: Equatable, Sendable {
    public var id: String
    public var goal: String
    public var origin: AgentSubtaskOrigin
    public var steps: AgentStepTrace

    public init(id: String, goal: String, origin: AgentSubtaskOrigin = .mainLoop, steps: AgentStepTrace = AgentStepTrace()) {
        self.id = id
        self.goal = goal
        self.origin = origin
        self.steps = steps
    }

    public mutating func recordStep(kind: AgentStepKind, label: String) {
        steps.record(kind: kind, label: label)
    }
}

/// 委派台账：主循环把活分出去、子任务回报，都落这里；界面按来源分组显示。
public struct AgentSubtaskLedger: Sendable {
    public private(set) var delegations: [AgentSubtaskDelegation]

    public init(delegations: [AgentSubtaskDelegation] = []) {
        self.delegations = delegations
    }

    /// 发起一次委派（记下发起步号 —— 「标来源」的落点）。
    @discardableResult
    public mutating func delegate(id: String, goal: String, atStep step: Int) -> AgentSubtaskDelegation {
        let delegation = AgentSubtaskDelegation(id: id, goal: goal,
                                                origin: .subtask(id: id, delegatedAtStep: step))
        delegations.append(delegation)
        return delegation
    }

    public mutating func appendStep(subtaskID: String, kind: AgentStepKind, label: String) {
        guard let index = delegations.firstIndex(where: { $0.id == subtaskID }) else { return }
        delegations[index].recordStep(kind: kind, label: label)
    }

    /// 全部步骤按来源汇总（主循环 + 各子任务），界面一屏能看到「谁干的」。
    public func allStepsGrouped() -> [(origin: AgentSubtaskOrigin, records: [AgentStepRecord])] {
        delegations.map { ($0.origin, $0.steps.records) }
    }

    /// 归属查询：某个 UI 动作是主循环还是子任务做的。
    public func origin(ofStep index: Int, inSubtask subtaskID: String) -> AgentSubtaskOrigin? {
        delegations.first { $0.id == subtaskID }?
            .steps.records.first { $0.index == index }
            .map { _ in AgentSubtaskOrigin.subtask(id: subtaskID, delegatedAtStep: 0) }
    }
}

/// 界面操作的一次记录（`AGT-TOOL-SYS-001`：每步可见）。
public struct AgentUIAction: Equatable, Sendable {
    public var action: String
    public var target: String
    public var origin: AgentSubtaskOrigin

    public init(action: String, target: String, origin: AgentSubtaskOrigin = .mainLoop) {
        self.action = action
        self.target = target
        self.origin = origin
    }

    /// 界面一行：`[subtask S1 @3] click:File>Save` / `[main] click:File>Save`。
    public var displayLine: String {
        switch origin {
        case .mainLoop:
            return "[main] \(action):\(target)"
        case .subtask(let id, let step):
            return "[subtask \(id) @\(step)] \(action):\(target)"
        }
    }
}
