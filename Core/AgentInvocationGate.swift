import Foundation

/// 门控的判定（`FR-AI-28`）：**要问模型 / 挡下**，以及挡下时给用户的**可读理由**。
///
/// 这一族只有两个出口，且都不带"能不能执行"的含义 —— **门控只决定「要不要问模型」**；
/// 「能不能执行」永远归 `AgentGuardrail` + 审批队列（条文里写死的那条边界，本文件不许越）。
public enum AgentGateDecision: Equatable, Sendable {
    /// 放行：照常发起模型请求（请求体与**不经门控时逐字节一致** —— 门控不改提示词）。
    case proceed
    /// 挡下：**一次请求都不发**，并给一句人话（谁被挡下、为什么）。
    case skipped(reason: String)

    public var isSkipped: Bool { if case .skipped = self { return true }; return false }
}

/// 一次触发（门控的输入）。
///
/// **两个字段都是"喂进来"的**：`at` 由调用方给（门控自己**不读时钟**），`digest` 由调用方算
/// （门控**不读网络、不读磁盘**）—— 这样它才是纯函数，同输入两次调用结果逐字一致（判据②）。
public struct AgentGateTrigger: Equatable, Sendable {
    /// 触发来源（可读）：`"chat"` / `"scheduled"` / `"retry"` …
    public var source: String
    /// 本次触发的**内容指纹**：提示词 + 上下文引用等的摘要。同样的指纹 = 同样的问法。
    public var digest: String
    /// 触发时刻（**由调用方传**）。
    public var at: Date

    public init(source: String, digest: String, at: Date) {
        self.source = source
        self.digest = digest
        self.at = at
    }
}

/// 省 token 的**调用门控**（`FR-AI-28`）：在「触发」与「模型调用」之间加一道判定。
///
/// ## 它做什么
///
/// · **重复的问法不问第二遍**：同一 `source` 上一次放行的 `digest` 与这次相同 ⇒ 挡下，
///   理由里带上"上次问的是什么、什么时候"。这就是省 token 的那一刀；
/// · **没变化 = 没新内容**：调用方把"当前上下文"算成 `digest`；上下文没变时它逐字相同 ⇒ 自然被挡；
/// · **每次挡下都留痕**（时间 / 来源 / 理由），可导出（判据④）；
/// · **放行时一个字节都不改**：`proceed` 的语义就是"当它没来过"（判据③）。
///
/// ## 它**不**做什么（边界，写在最显眼处）
///
/// · 不判"能不能执行"（那是 `AgentGuardrail` 与审批队列的事）；
/// · 不读时钟、不读网络、不读磁盘 ⇒ 纯函数、可单测；
/// · 不做节流 / 限速（那是配额 `AgentQuota` 的事，本条只回答"这次要不要问"）。
public struct AgentInvocationGate: Sendable {

    /// 上一次**放行**过的触发，按来源记（`source` → 上一次）。
    /// 只记放行过的：被挡下的那些不构成"问过了"。
    public private(set) var lastProceeded: [String: AgentGateTrigger]
    /// 挡下记录（**可导出**）：时间 / 来源 / 理由。只增不删。
    public private(set) var skips: [AgentGateSkip]

    /// 一条挡下记录。
    public struct AgentGateSkip: Equatable, Sendable {
        public var at: Date
        public var source: String
        public var digest: String
        public var reason: String

        public init(at: Date, source: String, digest: String, reason: String) {
            self.at = at
            self.source = source
            self.digest = digest
            self.reason = reason
        }

        /// 导出用一行（JSON Lines 同族：一行一条，字段名与其余留痕一致）。
        public var jsonLine: String {
            let stamp = ISO8601DateFormatter().string(from: at)
            let esc = { (s: String) in s.replacingOccurrences(of: "\"", with: "\\\"") }
            return "{\"at\":\"\(stamp)\",\"source\":\"\(esc(source))\",\"digest\":\"\(esc(digest))\",\"reason\":\"\(esc(reason))\"}"
        }
    }

    public init(lastProceeded: [String: AgentGateTrigger] = [:], skips: [AgentGateSkip] = []) {
        self.lastProceeded = lastProceeded
        self.skips = skips
    }

    /// 判定这次触发要不要问模型。**纯**：不改任何外部状态，只读自身记录 + 入参。
    ///
    /// - Parameter ignoringHistory: 用户显式"再问一次"（界面那个按钮）⇒ 传 `true`，绕过"重复"那一档。
    public func decide(_ trigger: AgentGateTrigger, ignoringHistory: Bool = false) -> AgentGateDecision {
        guard !ignoringHistory else { return .proceed }
        guard let previous = lastProceeded[trigger.source] else { return .proceed }
        guard previous.digest == trigger.digest else { return .proceed }
        let stamp = ISO8601DateFormatter().string(from: previous.at)
        return .skipped(reason: "同样的问法刚问过（\(trigger.source) · 上次 \(stamp)）—— 没有新内容就不重复发请求（省 token）。要再问一次：点「仍然发送」。")
    }

    /// 记下这次结果（放行则更新"上一次"，挡下则入挡下账）。**与 `decide` 分开**：判定是纯的，记账是显式的。
    public mutating func record(_ decision: AgentGateDecision, for trigger: AgentGateTrigger) {
        switch decision {
        case .proceed:
            lastProceeded[trigger.source] = trigger
        case .skipped(let reason):
            skips.append(AgentGateSkip(at: trigger.at, source: trigger.source, digest: trigger.digest, reason: reason))
        }
    }

    /// 挡下账的导出文本（一行一条）。
    public var exportText: String {
        skips.map(\.jsonLine).joined(separator: "\n")
    }
}
