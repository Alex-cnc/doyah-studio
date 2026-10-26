import Foundation

/// **中途干预**（`FR-AGT-UX-CONV-007` / 本端计划 P1-8）：插话、停手、追加约束。
///
/// 语义只有一条要紧的：干预**在当前步做完之后生效**，不打断正在跑的那一步，
/// 也不清空已经产生的中间结果 —— 清空是「丢已产生结果」，与判据相反。
public enum AgentIntervention: Equatable, Sendable {
    /// 改方向：下一跳起按新指令走。
    case redirect(instruction: String)
    /// 停手：当前步做完即停，不再起新的一跳。
    case stop(reason: String)
    /// 追加约束：后续所有动作都要满足（如「只读」「不许改 Vendor/」）。
    case constraint(text: String)
}

/// 干预的生效方式（界面与循环共用，别各写一套）。
public enum AgentInterventionEffect: String, Equatable, Sendable {
    /// 当前步结束后生效，循环继续（`redirect` / `constraint`）。
    case appliesAtNextStep
    /// 当前步结束后停止，不再起新跳（`stop`）。
    case stopsAfterCurrentStep
}

public struct PendingIntervention: Equatable, Sendable {
    public var at: Int
    public var value: AgentIntervention

    public init(at: Int, value: AgentIntervention) {
        self.at = at
        self.value = value
    }
}

public struct AgentInterventionQueue: Equatable, Sendable {
    /// 入队时记下「在第几步之后生效」；`at` 就是当时的步号。
    private(set) var pending: [PendingIntervention]

    public init() {
        self.pending = []
    }

    public var isEmpty: Bool { pending.isEmpty }

    public mutating func enqueue(_ intervention: AgentIntervention, duringStep step: Int) {
        pending.append(PendingIntervention(at: max(0, step), value: intervention))
    }

    /// 第 `step` 步做完后取出并移除所有已生效的干预（按入队顺序）。**只取出，不动结果**。
    public mutating func drain(afterCompleting step: Int) -> [AgentIntervention] {
        let due = pending.filter { $0.at <= step }.map(\.value)
        pending.removeAll { $0.at <= step }
        return due
    }

    /// 这一批里是否有「停手」—— 循环据此决定是否再起一跳。
    public var stopsRequested: Bool {
        pending.contains { if case .stop = $0.value { return true } else { return false } }
    }

    public static func effect(of intervention: AgentIntervention) -> AgentInterventionEffect {
        switch intervention {
        case .stop: return .stopsAfterCurrentStep
        case .redirect, .constraint: return .appliesAtNextStep
        }
    }

    /// 把已生效的约束累积成一份「必须满足」列表（循环在发下一跳前拼进提示）。
    public static func constraints(from drained: [AgentIntervention]) -> [String] {
        drained.compactMap { if case .constraint(let text) = $0 { return text } else { return nil } }
    }

    /// 把已生效的改方向指令取出来（后到的覆盖先到的：人最后一次说的算）。
    public static func redirect(from drained: [AgentIntervention]) -> String? {
        drained.compactMap { if case .redirect(let text) = $0 { return text } else { return nil } }.last
    }

    /// 这一批里是否要求停手。
    public static func stops(in drained: [AgentIntervention]) -> Bool {
        drained.contains { if case .stop = $0 { return true } else { return false } }
    }
}
