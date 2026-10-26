import Foundation

/// 失败分级（`FR-AGT-UX-CONV-004` 的前半）：**先分档，再决定处置**，三档各走各的路。
///
/// - `transient` 可重试：网络断 / 408 / 429 / 5xx ⇒ 按退避表等，**退避有上限**；
/// - `needsHuman` 需人处理：禁用了 / 无权限 / 配额用尽 ⇒ **别自己死磕**，出一张求助单（要授权还是要信息）；
/// - `terminal` 不该重试：响应结构坏 / 空回复 ⇒ 停，说清原因（重试只会浪费配额）。
///
/// 与 `LLMRetryPolicy.isRetryable` 的关系：那条是布尔捷径，这里给出**处置**（等多久 / 找谁 / 是否停）。
public enum AgentFailureTier: String, Equatable, Sendable, CaseIterable {
    case transient
    case needsHuman
    case terminal

    public var label: String {
        switch self {
        case .transient: return "可重试"
        case .needsHuman: return "需人处理"
        case .terminal: return "不该重试"
        }
    }
}

public struct AgentFailureTriage: Equatable, Sendable {
    public var tier: AgentFailureTier
    /// 可重试时要等的秒数（其它档为 0）。
    public var waitSeconds: TimeInterval
    /// 需人处理时给用户看的求助单（其它档为 nil）。
    public var help: AgentHelpRequest?
    /// 一句话说清（审计 / 失败提示都贴这一句）。
    public var note: String

    public var isRetryable: Bool { tier == .transient }
}

public struct AgentFailureClassifier: Sendable {

    public init() {}

    /// - Parameters:
    ///   - error: 这一跳的错误。
    ///   - attempt: 第几次尝试（1 = 初次；用于取退避间隔）。
    ///   - policy: 退避表（复用 `LLMRetryPolicy`，不另造一套）。
    public func classify(_ error: LLMError, attempt: Int, policy: LLMRetryPolicy) -> AgentFailureTriage {
        switch error {
        case .transport:
            return .init(tier: .transient, waitSeconds: policy.delayBeforeRetry(attempt),
                         help: nil, note: "网络层失败（\(error.localizedDescription)），按退避表等待后重试")
        case let .httpStatus(code, detail):
            let detailText = detail ?? ""
            if code == 408 || code == 429 || (500...599).contains(code) {
                return .init(tier: .transient, waitSeconds: policy.delayBeforeRetry(attempt),
                             help: nil, note: "HTTP \(code)：服务端暂时不可用或限流，稍后重试")
            }
            if code == 401 || code == 403 {
                return .init(tier: .needsHuman, waitSeconds: 0,
                             help: .init(kind: .grant,
                                         ask: "检查这个模型的 API Key 是否还有效、是否有该模型的权限",
                                         why: "请求被拒（HTTP \(code)\(detailText.isEmpty ? "" : "：\(detailText)")），重试不会变好"),
                             note: "HTTP \(code)：凭据或权限问题，需人处理")
            }
            return .init(tier: .terminal, waitSeconds: 0, help: nil,
                         note: "HTTP \(code)：请求本身不被接受，重试无意义")
        case .forbidden:
            return .init(tier: .needsHuman, waitSeconds: 0,
                         help: .init(kind: .grant, ask: "在设置里为这个端点放行（或换一个可用端点）",
                                     why: "当前配置禁止调用该端点"),
                         note: "端点被禁：需人放行")
        case .disabled:
            return .init(tier: .needsHuman, waitSeconds: 0,
                         help: .init(kind: .information, ask: "选一个可用模型，或填写 API Key 后再跑",
                                     why: "智能体当前没有可用的模型配置"),
                         note: "未配置模型：需人选择")
        case .quotaExceeded:
            return .init(tier: .needsHuman, waitSeconds: 0,
                         help: .init(kind: .grant, ask: "给这个账号充值 / 提高配额，或换成另一个 Key",
                                     why: "配额已用尽，再试也不会通过"),
                         note: "配额用尽：需人处理")
        case .malformedResponse:
            return .init(tier: .terminal, waitSeconds: 0, help: nil,
                         note: "响应结构不符合协议：重试大概率同样坏，停下并如实报告")
        case .emptyCompletion:
            return .init(tier: .terminal, waitSeconds: 0, help: nil,
                         note: "模型返回空回复：重试只会重复空回复")
        }
    }

    /// 非 `LLMError` 的失败（起进程失败 / 解析失败 …）：一律不可重试，**不猜**它可恢复。
    public func classifyUnknown(_ description: String) -> AgentFailureTriage {
        .init(tier: .terminal, waitSeconds: 0, help: nil, note: "非模型错误（\(description)）：不自动重试")
    }
}
