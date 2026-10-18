import Foundation

/// **长跑监控**（`FR-AI-31` ③）—— 回边四件里 Monitoring 那一片。
///
/// 要害一句话：**循环跑飞不许静默**。四种跑飞形态各给一条**可读告警**，而且用户看得见：
/// · **卡住**（`stalled`）：距上次进展超过阈值 —— 界面那一行会一直挂着秒数，而不是「转圈到天荒地老」；
/// · **空转**（`spinning`）：连续 N 跳的形态一模一样（同样的工具 + 同样的参数 / 同样的答复）——
///   模型在原地打转，人得知道，而不是等步数上限把它掐掉；
/// · **反复重试**（`retryStorm`）：重试次数越过阈值（`FR-AI-30` ① 分档重试的观察面）；
/// · **预算将尽 / 用尽**（`budgetApproaching` / `budgetExhausted`）：接 `AgentQuota` + `NFR-AI-04` ——
///   **不许悄悄把配额烧到上限**，八成时先说一句，见底时再说一句。
///
/// 三条纪律：
/// 1. **同类只报一次**（`reported`）：告警是让人做决定的，不是刷屏的；同一形态反复触发不重复报。
/// 2. **数与阈值都带出来**：界面能说「已 95 秒没有进展（阈值 90）」而不是一句「卡住了」。
/// 3. **不改变循环的判定**：本类型只产出告警，**不替循环做停/继续的决定** ——
///    停仍是 `AgentLoopLimits` / `AgentQuota` 的事（判据分开咬，避免两套刹车）。
public struct AgentRunMonitorLimits: Equatable, Sendable {

    /// 多久没有进展算「卡住」（秒）。**参数而非写死**：跑长命令的机器可以放大。
    public var stallSeconds: TimeInterval
    /// 连续几跳形态相同算「空转」。
    public var maxIdenticalHops: Int
    /// 一次运行里重试几次算「反复重试」。
    public var maxRetries: Int
    /// 配额用到这个比例就预警（0…1）。
    public var budgetWarnFraction: Double

    public init(stallSeconds: TimeInterval = 90,
                maxIdenticalHops: Int = 3,
                maxRetries: Int = 3,
                budgetWarnFraction: Double = 0.8) {
        self.stallSeconds = stallSeconds
        self.maxIdenticalHops = maxIdenticalHops
        self.maxRetries = maxRetries
        self.budgetWarnFraction = budgetWarnFraction
    }
}

/// 告警的四种形态（机器码，人话在界面语言表翻）。
public enum AgentRunAlertKind: String, Equatable, Sendable, CaseIterable {
    /// 距上次进展超过阈值。
    case stalled
    /// 连续 N 跳形态相同（原地打转）。
    case spinning
    /// 重试次数越过阈值。
    case retryStorm
    /// 配额用到八成（**还没拦，先说话**）。
    case budgetApproaching
    /// 配额已经用尽（下一次调用会被拦）。
    case budgetExhausted
}

/// 一条告警。
public struct AgentRunAlert: Equatable, Sendable {

    public var kind: AgentRunAlertKind
    /// 观测到的值：卡住的秒数 / 连续同形跳数 / 重试次数 / 已用量。
    public var observed: Int
    /// 阈值：卡住秒数 / 允许的同形跳数 / 允许的重试数 / 配额上限（0 = 无阈值这一档）。
    public var threshold: Int

    public init(kind: AgentRunAlertKind, observed: Int, threshold: Int = 0) {
        self.kind = kind
        self.observed = observed
        self.threshold = threshold
    }

    /// 过程面 / 审计 / 界面读数吃的**机器码**（`FR-AI-31` ③：不许静默）。
    /// 形如 `spinning:3/3`、`budgetApproaching:48/60`。
    public var code: String {
        threshold > 0 ? "\(kind.rawValue):\(observed)/\(threshold)" : "\(kind.rawValue):\(observed)"
    }
}

/// 监控本体（**纯值 + 纯转移**：判据直接打这里，界面只读结论）。
///
/// 循环在跳与跳的边界上喂它（`recordHop` / `recordRetry` / `checkBudget`），
/// 宿主侧看门狗按秒喂 `checkStalled` —— 两处用的**是同一份阈值与同一条判定**，
/// 不会出现「循环说没卡、界面说卡了」这种两套标准。
public struct AgentRunMonitor: Equatable, Sendable {

    public var limits: AgentRunMonitorLimits
    /// 最近一次「有进展」的时刻（收到增量 / 工具开跑 / 工具收尾 / 跳结束都会刷它）。
    public private(set) var lastProgressAt: Date
    /// 最近几跳的形态指纹（只留够判定用的那几跳，不无限长）。
    public private(set) var hopSignatures: [String] = []
    /// 本次运行累计重试次数。
    public private(set) var retries: Int = 0
    /// 已经报过的形态（同类只报一次 —— 告警不刷屏）。
    public private(set) var reported: Set<AgentRunAlertKind> = []
    /// 本次运行报过的全部告警（事后可查「它跑飞时系统说过什么」）。
    public private(set) var alerts: [AgentRunAlert] = []

    public init(limits: AgentRunMonitorLimits = AgentRunMonitorLimits(),
                startedAt: Date = Date()) {
        self.limits = limits
        self.lastProgressAt = startedAt
    }

    /// 有进展（增量到了 / 工具动了 / 跳结束了）。
    public mutating func noteProgress(at now: Date = Date()) {
        lastProgressAt = now
    }

    /// 一跳跑完：喂这一跳的**形态指纹**（工具名 + 参数指纹，或答复指纹）。
    /// 连续 `maxIdenticalHops` 跳形态相同 ⇒ 空转告警（同一形态只报一次）。
    @discardableResult
    public mutating func recordHop(signature: String, at now: Date = Date()) -> AgentRunAlert? {
        noteProgress(at: now)
        hopSignatures.append(signature)
        let window = max(2, limits.maxIdenticalHops)
        if hopSignatures.count > window { hopSignatures.removeFirst(hopSignatures.count - window) }
        guard hopSignatures.count >= window, Set(hopSignatures.suffix(window)).count == 1 else { return nil }
        return report(AgentRunAlert(kind: .spinning, observed: window, threshold: window))
    }

    /// 一次「按策略再试」。越过阈值 ⇒ 反复重试告警。
    @discardableResult
    public mutating func recordRetry(at now: Date = Date()) -> AgentRunAlert? {
        noteProgress(at: now)
        retries += 1
        guard retries > limits.maxRetries else { return nil }
        return report(AgentRunAlert(kind: .retryStorm, observed: retries, threshold: limits.maxRetries))
    }

    /// **预算**（接 `AgentQuota` + `NFR-AI-04`）：把「已用 + 本次预算」投进去，
    /// 八成时先报一声，见底时再报一声 —— **不许静默耗尽配额**。
    ///
    /// 判「见底」用的是配额自己的判定（`AgentQuota.decision`），本处**不另立一套算术**：
    /// 两处口径一旦分叉，就会出现「监控说还有、配额已经拦了」。
    public mutating func checkBudget(quota: AgentQuota,
                                     ledger: AgentQuotaLedger,
                                     requestedOutputTokens: Int? = nil) -> [AgentRunAlert] {
        guard !quota.isUnlimited else { return [] }
        var out: [AgentRunAlert] = []
        let decision = quota.decision(ledger: ledger, requestedOutputTokens: requestedOutputTokens)
        if !decision.isAllowed {
            switch decision {
            case .requestLimitReached(let limit):
                if let alert = report(AgentRunAlert(kind: .budgetExhausted,
                                                    observed: ledger.requestCount, threshold: limit)) {
                    out.append(alert)
                }
            case .tokenLimitReached(let limit, let used):
                if let alert = report(AgentRunAlert(kind: .budgetExhausted,
                                                    observed: used, threshold: limit)) {
                    out.append(alert)
                }
            case .outputTokenLimitExceeded:
                // 单次输出超限是**这一次**的错，不是「预算耗尽」；循环会按配额判定如实停，
                // 这里不冒充长跑告警（否则用户会以为配额用完了）。
                break
            case .allowed:
                break
            }
            return out
        }
        // 还没见底：八成时先说一句（对两种上限都看）。
        for (used, limit) in budgetPairs(quota: quota, ledger: ledger, requestedOutputTokens: requestedOutputTokens) {
            guard limit > 0, Double(used) >= Double(limit) * limits.budgetWarnFraction else { continue }
            if let alert = report(AgentRunAlert(kind: .budgetApproaching, observed: used, threshold: limit)) {
                out.append(alert)
            }
            break
        }
        return out
    }

    /// 「卡住」判定（宿主看门狗按秒喂）。超过阈值 ⇒ 报一次；再久也不重复报。
    @discardableResult
    public mutating func checkStalled(now: Date = Date()) -> AgentRunAlert? {
        guard let alert = Self.stallAlert(idleSeconds: Int(now.timeIntervalSince(lastProgressAt)),
                                          limits: limits) else { return nil }
        return report(alert)
    }

    /// 「卡住」的**纯判定**（不持状态 —— 宿主侧的看门狗与循环侧的判据共用这一条）。
    public static func stallAlert(idleSeconds: Int, limits: AgentRunMonitorLimits) -> AgentRunAlert? {
        let threshold = Int(limits.stallSeconds)
        guard threshold > 0, idleSeconds >= threshold else { return nil }
        return AgentRunAlert(kind: .stalled, observed: idleSeconds, threshold: threshold)
    }

    // MARK: - 内部

    /// 报一次（同类只报一次）。返回 `nil` = 这一类已经报过（不刷屏）。
    private mutating func report(_ alert: AgentRunAlert) -> AgentRunAlert? {
        guard !reported.contains(alert.kind) else { return nil }
        reported.insert(alert.kind)
        alerts.append(alert)
        return alert
    }

    /// 预算对（用完多少、上限多少）—— 两种上限各自成对，`0` 上限表示那一档没配。
    private func budgetPairs(quota: AgentQuota, ledger: AgentQuotaLedger,
                            requestedOutputTokens: Int?) -> [(Int, Int)] {
        var pairs: [(Int, Int)] = []
        if let limit = quota.maxTotalTokens {
            pairs.append((ledger.totalTokens + max(0, requestedOutputTokens ?? 0), limit))
        }
        if let limit = quota.maxRequestsPerSession {
            pairs.append((ledger.requestCount, limit))
        }
        return pairs
    }
}

extension AgentRunAlert {

    /// 供 `AgentChatState` 落进读数时用（与事件里那条一一对应）。
    public static func kinds(fromCode code: String) -> AgentRunAlertKind? {
        guard let head = code.split(separator: ":").first else { return nil }
        return AgentRunAlertKind(rawValue: String(head))
    }
}
