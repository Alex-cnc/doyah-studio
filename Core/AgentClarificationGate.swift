import Foundation

/// 主动澄清（`FR-AGT-PLAN-CLAR-001`）。
///
/// 语义：**开跑前**遇到三种情况先问一句再动，别猜着干 ——
/// ① 目标不清（没有可执行的动作 / 目标里只有名词没有动词）；
/// ② 缺关键参数（缺了就跑错方向的那些，不是能靠默认值兜的）；
/// ③ 两种做法代价差很大（工时 / 风险 / 不可逆性差 ≥ 阈值）。
///
/// 反过来也钉死：**不该问的别问** —— 缺失参数有安全默认值、目标已可执行、代价差小 ⇒ 直接干。
/// 这一条是为了不让「主动澄清」变成「动不动就请示」。
public struct AgentClarificationRequest: Equatable, Sendable {
    public enum Reason: String, Equatable, Sendable {
        case ambiguousGoal
        case missingParameter
        case costTradeoff
    }

    public var reason: Reason
    /// 问人的那一句（一句话，带具体缺口，不许写「请补充更多信息」）。
    public var question: String
    /// 可选项（代价差 / 两种做法时给出；其它情况为空）。
    public var options: [String]

    public init(reason: Reason, question: String, options: [String] = []) {
        self.reason = reason
        self.question = question
        self.options = options
    }
}

public enum AgentClarificationDecision: Equatable, Sendable {
    case proceed
    case ask(AgentClarificationRequest)
}

public struct AgentClarificationGate: Sendable {
    /// 代价差达到这个倍数就值得问（默认 3 倍：差 2 倍以内自己选一条更像样的路）。
    public var costRatioThreshold: Double
    /// 「手段动词」白名单：目标里出现任何一个就认为可执行，不必问。
    public let actionVerbs: Set<String>

    public init(costRatioThreshold: Double = 3.0,
                actionVerbs: Set<String> = [
                    "查", "看", "改", "写", "建", "删", "跑", "导", "导出", "导入", "备份", "恢复",
                    "生成", "统计", "对比", "解释", "优化", "迁移", "清理", "重跑", "校对", "拉取", "推送",
                ]) {
        self.costRatioThreshold = costRatioThreshold
        self.actionVerbs = actionVerbs
    }

    /// - Parameters:
    ///   - goal: 用户原话（目标）。
    ///   - missingRequiredParameters: 缺了就做不对的参数（**只放真关键项**；有安全默认值的不要塞进来）。
    ///   - approaches: 两种及以上候选做法的代价估算（分钟）；小于两项时忽略。
    public func decide(goal: String,
                       missingRequiredParameters: [String] = [],
                       approaches: [String: Double] = [:]) -> AgentClarificationDecision {
        let text = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            return .ask(AgentClarificationRequest(
                reason: .ambiguousGoal,
                question: "你要我做哪件事？给我一个动词（查 / 改 / 建 / 导出 …）加对象就行。"))
        }
        if !missingRequiredParameters.isEmpty {
            let list = missingRequiredParameters.joined(separator: "、")
            return .ask(AgentClarificationRequest(
                reason: .missingParameter,
                question: "要动之前缺关键参数：\(list)。给我这几个值，或者告诉我按哪个默认来。"))
        }
        if !containsActionVerb(text) {
            return .ask(AgentClarificationRequest(
                reason: .ambiguousGoal,
                question: "「\(truncated(text))」要落成什么动作？比如「查 / 改 / 导出」哪一个。"))
        }
        if let pair = widestCostGap(approaches), pair.second.value > 0,
           pair.first.value / pair.second.value >= costRatioThreshold {
            let first = pair.first, second = pair.second
            let options = approaches.sorted { $0.value < $1.value }
                .map { "\($0.key)（≈\(Int($0.value)) 分钟）" }
            return .ask(AgentClarificationRequest(
                reason: .costTradeoff,
                question: "两条路的代价差得比较多（\(Int(first.value / second.value)) 倍）：走哪条？",
                options: options))
        }
        return .proceed
    }

    private func containsActionVerb(_ text: String) -> Bool {
        // 英文动词单独认（大写开头 / 全小写都算），中文按子串
        let lowered = text.lowercased()
        let english: Set<String> = ["query", "select", "update", "insert", "delete", "create", "drop",
                                    "backup", "restore", "export", "import", "explain", "vacuum", "analyze"]
        if english.contains(where: { lowered.contains($0) }) { return true }
        return actionVerbs.contains { text.contains($0) }
    }

    private func widestCostGap(_ approaches: [String: Double]) -> (first: (key: String, value: Double), second: (key: String, value: Double))? {
        let sorted = approaches.sorted { $0.value > $1.value }
        guard sorted.count >= 2 else { return nil }
        return ((sorted[0].key, sorted[0].value), (sorted[1].key, sorted[1].value))
    }

    private func truncated(_ text: String) -> String {
        text.count <= 30 ? text : String(text.prefix(30)) + "…"
    }
}
