import Foundation

/// 对话里的消息角色。
public enum AgentChatRole: String, Sendable, Equatable {
    case user
    case assistant
    case tool
    /// 界面自己说的话（如实报的状态 / 原因）。
    case notice
}

public struct AgentChatMessage: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var role: AgentChatRole
    public var text: String
    /// 还在流式接收（界面据此显示光标 / 不做收尾）。
    public var isStreaming: Bool

    public init(id: UUID = UUID(), role: AgentChatRole, text: String, isStreaming: Bool = false) {
        self.id = id
        self.role = role
        self.text = text
        self.isStreaming = isStreaming
    }
}

/// 工具卡片的状态（`FR-AI-25` ③④）。
public enum AgentToolCardOutcome: Equatable, Sendable {
    case running
    /// 跑完了（摘要）。
    case executed(String)
    /// 被拒（原因，**机器形态**：`unregistered` / `deniedByPolicy` / `missing:path` …）。
    case denied(String)
    /// 等审批：**批准之前就要能看见要改什么**（差异 / 命令原文）。
    case pendingApproval(fingerprint: String, preview: String)
    /// 批了但还没应用。
    case approved(fingerprint: String, preview: String)
    /// 应用完成。
    case applied(fingerprint: String)

    public var isTerminal: Bool {
        switch self {
        case .executed, .denied, .applied: return true
        case .running, .pendingApproval, .approved: return false
        }
    }
}

public struct AgentToolCard: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var arguments: String
    public var outcome: AgentToolCardOutcome
    public var expanded: Bool

    public init(id: UUID = UUID(), name: String, arguments: String,
                outcome: AgentToolCardOutcome = .running, expanded: Bool = false) {
        self.id = id
        self.name = name
        self.arguments = arguments
        self.outcome = outcome
        self.expanded = expanded
    }

    /// 卡片的**副标题**（机器形态，界面负责给人话）。
    public var statusCode: String {
        switch outcome {
        case .running: return "running"
        case .executed: return "executed"
        case .denied(let reason): return "denied:\(reason)"
        case .pendingApproval: return "pendingApproval"
        case .approved: return "approved"
        case .applied: return "applied"
        }
    }

    /// 批准前要给人看的预览（差异 / 命令原文）。
    public var approvalPreview: String? {
        switch outcome {
        case .pendingApproval(_, let preview), .approved(_, let preview): return preview
        default: return nil
        }
    }

    /// 等审批时的**指纹**（界面拿它去兑现那一次批准）。
    public var approvalFingerprint: String? {
        switch outcome {
        case .pendingApproval(let fingerprint, _), .approved(let fingerprint, _): return fingerprint
        default: return nil
        }
    }
}

/// 端点配置状态（`FR-AI-25` ⑤：**连不上就如实说，不假装在跑**）。
public enum AgentChatEndpointState: Equatable, Sendable {
    /// 还没配端点 —— 界面如实说「没配」，且**不许发**。
    case notConfigured
    case ready(model: String, endpoint: String)
    /// 配置了但连不上（原因如实带出）。
    case unreachable(String)

    public var canSend: Bool {
        if case .ready = self { return true }
        return false
    }

    /// 界面上那句「为什么不能发」的**机器码**（人话由界面从语言表取）。
    public var blockerCode: String? {
        switch self {
        case .ready: return nil
        case .notConfigured: return "endpointNotConfigured"
        case .unreachable: return "endpointUnreachable"
        }
    }
}

/// 对话状态（**纯值 + 纯转移** —— 与 `WorkspaceTabSet` 同一条纪律：规则在 Core、状态在 App 的薄壳里）。
public struct AgentChatState: Equatable, Sendable {

    public var messages: [AgentChatMessage]
    public var cards: [AgentToolCard]
    public var endpoint: AgentChatEndpointState
    public var isRunning: Bool
    /// 已批准的指纹（**按次**：批准一次只能兑现一次，兑现后从集合里移走）。
    public var grants: Set<String>

    public init(messages: [AgentChatMessage] = [], cards: [AgentToolCard] = [],
                endpoint: AgentChatEndpointState = .notConfigured, isRunning: Bool = false,
                grants: Set<String> = []) {
        self.messages = messages
        self.cards = cards
        self.endpoint = endpoint
        self.isRunning = isRunning
        self.grants = grants
    }

    // MARK: - 提问

    /// 能不能发（不能就**如实说为什么**，不静默吞掉）。
    public var canSend: Bool { endpoint.canSend && !isRunning }

    public mutating func beginRun(prompt: String) {
        guard canSend else {
            if let code = endpoint.blockerCode { appendNotice(code) }
            return
        }
        messages.append(AgentChatMessage(role: .user, text: prompt))
        messages.append(AgentChatMessage(role: .assistant, text: "", isStreaming: true))
        isRunning = true
    }

    /// 流式收尾：把「还在流式」那一条定稿。
    public mutating func endStreaming() {
        guard let index = messages.lastIndex(where: { $0.isStreaming }) else { return }
        messages[index].isStreaming = false
        if messages[index].text.isEmpty { messages.remove(at: index) }
    }

    /// 这一轮跑完了（收尾 + 不再显示「在跑」）。
    public mutating func finishRun() {
        endStreaming()
        isRunning = false
    }

    public mutating func appendNotice(_ code: String) {
        messages.append(AgentChatMessage(role: .notice, text: code))
    }

    // MARK: - 循环进度（② 增量 / ③ 卡片）

    public mutating func apply(_ event: AgentLoopEvent) {
        switch event {
        case .hopStarted:
            endStreaming()
            if messages.last?.role != .assistant || messages.last?.isStreaming == false {
                messages.append(AgentChatMessage(role: .assistant, text: "", isStreaming: true))
            }
        case .delta(let piece):
            // **增量就地追加** —— 不等整段（`FR-AI-25` ②）
            if let index = messages.lastIndex(where: { $0.isStreaming }) {
                messages[index].text += piece
            } else {
                messages.append(AgentChatMessage(role: .assistant, text: piece, isStreaming: true))
            }
        case .toolStarted(let name):
            cards.append(AgentToolCard(name: name, arguments: ""))
        case .toolFinished(let name, let outcome):
            guard let index = cards.lastIndex(where: { $0.name == name && $0.outcome == .running }) else { return }
            switch outcome {
            case "executed": cards[index].outcome = .executed(outcome)
            case "denied": cards[index].outcome = .denied("denied")
            default: cards[index].outcome = .denied(outcome)
            }
        case .stopped(let stop):
            endStreaming()
            appendNotice(stop.reason)
            isRunning = false
        case .failed(let message):
            endStreaming()
            appendNotice("failed:\(message)")
            isRunning = false
        }
    }

    /// 工具调用被拒时**把原因摆在卡片上**（`FR-AI-25` ③：未登记的调用也如实显示）。
    public mutating func markDenied(cardID: UUID, reason: String) {
        guard let index = cards.firstIndex(where: { $0.id == cardID }) else { return }
        cards[index].outcome = .denied(reason)
    }

    // MARK: - 审批（④）

    /// 某个写 / 执行工具要审批 —— **批准之前先把要改什么摆出来**。
    @discardableResult
    public mutating func requestApproval(name: String, fingerprint: String, preview: String) -> UUID {
        let card = AgentToolCard(name: name, arguments: preview,
                                 outcome: .pendingApproval(fingerprint: fingerprint, preview: preview),
                                 expanded: true)
        cards.append(card)
        return card.id
    }

    /// 批准（**只加一条按次授权**；应用是另一步 —— 见 `markApplied`）。
    @discardableResult
    public mutating func approve(cardID: UUID) -> Bool {
        guard let index = cards.firstIndex(where: { $0.id == cardID }),
              case .pendingApproval(let fingerprint, let preview) = cards[index].outcome else { return false }
        cards[index].outcome = .approved(fingerprint: fingerprint, preview: preview)
        grants.insert(fingerprint)
        return true
    }

    /// 拒绝（**不留授权**，卡片如实标被拒）。
    @discardableResult
    public mutating func deny(cardID: UUID) -> Bool {
        guard let index = cards.firstIndex(where: { $0.id == cardID }),
              case .pendingApproval(let fingerprint, _) = cards[index].outcome else { return false }
        cards[index].outcome = .denied("userRejected")
        grants.remove(fingerprint)
        return true
    }

    /// 应用完成（**并且把这条按次授权用掉** —— 再要动同一个东西得重新批）。
    @discardableResult
    public mutating func markApplied(cardID: UUID) -> Bool {
        guard let index = cards.firstIndex(where: { $0.id == cardID }),
              case .approved(let fingerprint, _) = cards[index].outcome else { return false }
        cards[index].outcome = .applied(fingerprint: fingerprint)
        grants.remove(fingerprint)
        return true
    }

    public mutating func toggleExpanded(cardID: UUID) {
        guard let index = cards.firstIndex(where: { $0.id == cardID }) else { return }
        cards[index].expanded.toggle()
    }

    public mutating func setEndpoint(_ state: AgentChatEndpointState) {
        endpoint = state
    }
}
