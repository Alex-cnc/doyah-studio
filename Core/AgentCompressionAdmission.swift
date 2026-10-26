import Foundation

/// **压缩只在会话边界发生**（详设 §3.21 · `FR-AGT-KNOW-CTX-002` · 本端计划 P1-9）。
///
/// 四条契约结局：`.runNow` / `.deferToBoundary` / `.skip` / `.refuse`。
/// 唯一硬约束：**回合内任何调用只许返回 `.deferToBoundary`** —— 回合内能说话的只有预算报告。
/// 这条是把 Hermes `context_engine.py` 的生命周期注释落成判据（不做 per-turn 压缩）。
public enum AgentSessionBoundary: String, Codable, Sendable, CaseIterable {
    /// ① 会话开始前（新会话装载历史）。
    case beforeSession
    /// ② 用户显式 `/compact`。
    case userCompact
    /// ③ 会话结束落盘前。
    case beforeSessionEnd
    /// ④ 网关侧会话过期回收。
    case gatewayExpiry
}

/// 压缩丢掉的类别（只记类别，不记正文 —— 日志禁记被压缩正文）。
public enum AgentDroppedKind: String, Codable, Sendable, CaseIterable {
    case detail
    case verboseBody
    case repeatedToolResults
}

public enum AgentCompressionSkipReason: String, Codable, Sendable {
    /// 没有可用压缩器 —— 如实说「这次没压」，不许假装压过。
    case noEngine
    /// 会话边界判定不明（跨进程恢复）—— 可重试，下一轮再判。
    case boundaryUnknown
}

public enum AgentCompressionRefusalReason: Equatable, Sendable {
    /// 压完还是超上限 —— **不许静默截断**。
    case stillOverLimit(before: Int, after: Int)
}

/// `.runNow` 时必须一起交出来的三样可读输出。
public struct AgentCompressionProduct: Equatable, Sendable {
    public var boundary: AgentSessionBoundary
    public var tokensBefore: Int
    public var tokensAfter: Int
    /// ① 压缩后仍能回答「刚才决定了什么」：保留的决策 / 约束。
    public var decisionsKept: [String]
    /// ② 明确写出丢了什么类别。
    public var droppedKinds: [AgentDroppedKind]
    /// ③ 截断处标记（界面可见的那一句）。
    public var marker: String

    public init(boundary: AgentSessionBoundary, tokensBefore: Int, tokensAfter: Int,
                decisionsKept: [String], droppedKinds: [AgentDroppedKind], marker: String) {
        self.boundary = boundary
        self.tokensBefore = tokensBefore
        self.tokensAfter = tokensAfter
        self.decisionsKept = decisionsKept
        self.droppedKinds = droppedKinds
        self.marker = marker
    }
}

public enum CompressionAdmission: Equatable, Sendable {
    case runNow(boundary: AgentSessionBoundary, product: AgentCompressionProduct)
    /// 回合内被要求压缩：只许排队，并把唯一允许说话的东西（预算报告）带出来。
    case deferToBoundary(next: AgentSessionBoundary, budget: AgentBudgetReport?)
    case skip(reason: AgentCompressionSkipReason)
    case refuse(reason: AgentCompressionRefusalReason)
}

/// 详设 §3.21 的落点：`AgentContextCompression.admit(at:)`。
///
/// 入参刻意拆开（边界 / 是否回合内 / 前后 token / 引擎是否可用），
/// 这样判据可以只喂纯数据，不必起真循环。
public enum AgentContextCompression {

    /// 压缩判决。
    /// - Parameters:
    ///   - boundary: 调用点所属的会话边界；`nil` = 判不出来（跨进程恢复）
    ///   - inTurn: 是否发生在回合内
    ///   - tokensBefore: 压缩前 token（取自 `AgentModelMeter` 实测量）
    ///   - tokenLimit: 上限（150 步 / 262,144 口径里的后者）
    ///   - estimatedAfter: 压缩后 token；`nil` = 估不出来，按「没压」处理
    ///   - engineAvailable: 压缩器可用且带策略
    ///   - decisionsKept / droppedKinds / marker: `.runNow` 时要交出去的三样输出
    ///   - budget: 回合内那句唯一允许说话的东西
    public static func admit(
        at boundary: AgentSessionBoundary?,
        inTurn: Bool,
        tokensBefore: Int,
        tokenLimit: Int,
        estimatedAfter: Int?,
        engineAvailable: Bool,
        decisionsKept: [String] = [],
        droppedKinds: [AgentDroppedKind] = [],
        marker: String = "[compressed]",
        budget: AgentBudgetReport? = nil
    ) -> CompressionAdmission {
        // ① 引擎缺失优先说清楚（不然「没压」会被误读成「不需要压」）。
        guard engineAvailable else { return .skip(reason: .noEngine) }

        // ② 回合内：一律排队。这是本节存在的理由。
        if inTurn {
            return .deferToBoundary(next: nextBoundary(after: boundary), budget: budget)
        }

        // ③ 边界判不出来：可重试，下一轮再判。
        guard let boundary else { return .skip(reason: .boundaryUnknown) }

        // ④ 压完仍超限：如实报，不静默截断。
        let after = estimatedAfter ?? tokensBefore
        if after > tokenLimit {
            return .refuse(reason: .stillOverLimit(before: tokensBefore, after: after))
        }

        return .runNow(boundary: boundary,
                       product: AgentCompressionProduct(boundary: boundary,
                                                        tokensBefore: tokensBefore,
                                                        tokensAfter: after,
                                                        decisionsKept: decisionsKept,
                                                        droppedKinds: droppedKinds,
                                                        marker: marker))
    }

    /// 回合内排队时「下一个边界」取哪个：会话还没结束就是用户 `/compact`，已在收尾就是落盘前。
    public static func nextBoundary(after boundary: AgentSessionBoundary?) -> AgentSessionBoundary {
        switch boundary {
        case .beforeSessionEnd, .gatewayExpiry: return .beforeSessionEnd
        default: return .userCompact
        }
    }
}

/// 同一 `(sessionID, boundary)` 重复调用**幂等**：返回首次结局，不重复耗预算。
public struct AgentCompressionLedger: Equatable, Sendable {
    private var firstOutcome: [String: CompressionAdmission] = [:]

    public init() {}

    private func key(_ sessionID: String, _ boundary: AgentSessionBoundary) -> String {
        "\(sessionID)#\(boundary.rawValue)"
    }

    /// 记录并返回「该采纳的结局」：已有首次结局就原样返回它。
    public mutating func record(_ admission: CompressionAdmission,
                                sessionID: String,
                                boundary: AgentSessionBoundary) -> CompressionAdmission {
        let k = key(sessionID, boundary)
        if let first = firstOutcome[k] { return first }
        firstOutcome[k] = admission
        return admission
    }

    public func outcome(sessionID: String, boundary: AgentSessionBoundary) -> CompressionAdmission? {
        firstOutcome[key(sessionID, boundary)]
    }
}
