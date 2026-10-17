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

/// 一步（= 循环里的**一跳**）在界面上的样子。
///
/// 由头（人类主人 2026-10-17）：「DSH-tui 在对话输入框上面的那个**任务清单**也挺好，
/// 用户可以看到你**正在执行到哪一步**了」⇒ 把「走到哪了」做成输入框上方的一块清单，
/// 而不是让用户自己去正文里找。
public struct AgentChatStep: Identifiable, Equatable, Sendable {
    public enum Status: String, Equatable, Sendable { case running, done, failed }

    public let id: UUID
    /// 第几步（1 起）。
    public var index: Int
    public var status: Status
    /// 这一步里跑过的工具名（按发生顺序，允许重复 —— 同一工具两次就是两笔）。
    public var tools: [String]

    public init(id: UUID = UUID(), index: Int, status: Status = .running, tools: [String] = []) {
        self.id = id
        self.index = index
        self.status = status
        self.tools = tools
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
    /// 本次任务的步骤清单（输入框上方那块）。
    public var steps: [AgentChatStep]
    /// **当前动作**（输入框上方那一行 —— 对齐 dsh-tui 的 `🌙 … Firing a command … · 1s`）。
    ///
    /// 命门在**就地更新、不追加**：开跑时写上，收尾时清掉 ⇒ 无论跑多少跳，这一行永远只占**一行**
    /// （人类主人 2026-10-17 口径：「执行的命令都是在 cli 对话框上面**一行滚动**而已，不会刷屏」）。
    /// 与「过程块」的分工：过程块留**走过哪些步**（可回看），这一行只显示**此刻在干什么**。
    public var currentAction: String?
    public var endpoint: AgentChatEndpointState
    public var isRunning: Bool
    /// 已批准的指纹（**按次**：批准一次只能兑现一次，兑现后从集合里移走）。
    public var grants: Set<String>
    /// 授权粒度（`FR-AI-34`）：默认「任务范围内代签」，受保护路径与超上限转人工。
    /// 设成 `.askEach` 就回到"每个动作都问"的老行为。
    /// **Core 默认仍是逐次批**（不改既有语义、不动老判据）；由宿主按用户设置切成 `.taskScope`。
    public var taskScope: AgentTaskScope = .askEach
    /// 本轮**代签**过的动作（事后可审；与 `grants` 不同：`grants` 会被 `markApplied` 用掉，这里永久留痕）。
    public private(set) var autoApprovals: [AgentAutoApproval] = []

    public init(messages: [AgentChatMessage] = [], cards: [AgentToolCard] = [],
                steps: [AgentChatStep] = [],
                endpoint: AgentChatEndpointState = .notConfigured, isRunning: Bool = false,
                grants: Set<String> = []) {
        self.messages = messages
        self.cards = cards
        self.steps = steps
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
        // 新一轮 = 新任务 ⇒ 清单**重新起**（上一轮的步骤不混进来）。
        steps = []
        isRunning = true
    }

    /// 流式收尾：把「还在流式」那一条定稿。
    public mutating func endStreaming() {
        guard let index = messages.lastIndex(where: { $0.isStreaming }) else { return }
        messages[index].isStreaming = false
        if messages[index].text.isEmpty { messages.remove(at: index) }
    }

    /// **会话标题**（状态行最右那格 —— 人类主人 2026-10-17：「hermes 还有一个会话标题在最右侧我觉得挺好」）。
    ///
    /// 取**首条提问**（真值，不另调模型生成标题 —— 生成标题要额外花 token，第十条：成本是一等公民）。
    /// 超长截断，换行压成空格；还没有提问 ⇒ `nil`（那格就不出现，不留空壳）。
    public var sessionTitle: String? {
        guard let first = messages.first(where: { $0.role == .user })?.text else { return nil }
        let flat = first.split(whereSeparator: { $0.isNewline }).joined(separator: " ")
        guard !flat.isEmpty else { return nil }
        return flat.count <= 28 ? flat : String(flat.prefix(28)) + "…"
    }

    /// 这一轮跑完了（收尾 + 不再显示「在跑」）。
    public mutating func finishRun() {
        endStreaming()
        isRunning = false
        currentAction = nil
        // 收尾：最后一步没被标成失败就是走完了（`failed` / `stopped` 那两条路各自标过）。
        if let index = steps.indices.last, steps[index].status == .running {
            steps[index].status = .done
        }
    }

    public mutating func appendNotice(_ code: String) {
        messages.append(AgentChatMessage(role: .notice, text: code))
    }

    // MARK: - 循环进度（② 增量 / ③ 卡片）

    public mutating func apply(_ event: AgentLoopEvent) {
        switch event {
        case .hopStarted(let hopIndex):
            // 每跳 = 清单里的一步。**用事件自带的跳号**（0 起）换算成「第 N 步」（1 起）——
            // 不自己数数：续跑（`NFR-AI-08`）时跳号会从中间起，自己数会显示成「第 1 步」。
            steps.append(AgentChatStep(index: hopIndex + 1))
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
        case .toolStarted(let name, let summary):
            // **自跑的命令收在同一条过程消息里**（人类主人 2026-10-17 实机反馈原话：「智能体自己执行的命令
            // 这些信息应该是在同一条信息中滚动，避免刷屏」）。改前：每调一次工具就 `cards.append` 一张卡片
            // ⇒ 一跑十几跳就是一屏卡片。现在卡片**只留给要人动手的那几种**（等审批 / 已批 / 已应用，
            // 见 `requestApproval`）—— 那些必须逐张可点，不能并进正文。
            appendProgressLine(Self.progressBullet + name + (summary.isEmpty ? "" : " · " + summary))
            if let index = steps.indices.last { steps[index].tools.append(name) }
            currentAction = summary.isEmpty ? name : "\(name)(\(summary))"
        case .toolFinished(let name, let outcome, let millis):
            // **就地收尾同一行**（同一行改状态，不新开行、不新开块）+ 如实报耗时。
            closeProgressLine(tool: name,
                              mark: (outcome == "executed" ? "✓" : "✗ " + outcome) + Self.durationSuffix(millis))
            currentAction = nil
        case .stopped(let stop):
            endStreaming()
            appendNotice(stop.reason)
            isRunning = false
            currentAction = nil
            if let index = steps.indices.last { steps[index].status = .failed }
        case .failed(let message):
            endStreaming()
            appendNotice("failed:\(message)")
            isRunning = false
            currentAction = nil
            if let index = steps.indices.last { steps[index].status = .failed }
        }
    }

    // MARK: - 过程行（自跑的命令都在这条消息里）

    /// 过程行的前缀（给人看的形状；判据只认「同一块」这一点）。
    private static let progressBullet = "▸ "

    /// 把一行过程**追加到既有那块**里；没有块就新开一条。
    ///
    /// 合并口径：只并进**最近那块、且其后没有新的用户提问**（新提问 = 新一轮，块要分开）。
    private mutating func appendProgressLine(_ line: String) {
        if let index = messages.lastIndex(where: { $0.role == .tool }),
           !messages[(index + 1)...].contains(where: { $0.role == .user }) {
            messages[index].text += "\n" + line
        } else {
            messages.append(AgentChatMessage(role: .tool, text: line))
        }
    }

    /// 耗时的显示后缀（`0.3s` / `1.2s`）；`nil` = 这一步没真跑 ⇒ **不显示**（不报假耗时）。
    static func durationSuffix(_ millis: Int?) -> String {
        guard let millis else { return "" }
        return String(format: " · %.1fs", Double(millis) / 1000)
    }

    /// 把某个工具**那一行**就地收尾（同一行改状态，不新开行）。
    private mutating func closeProgressLine(tool: String, mark: String) {
        guard let index = messages.lastIndex(where: { $0.role == .tool }) else { return }
        var lines = messages[index].text.components(separatedBy: "\n")
        guard let row = lines.lastIndex(where: { $0.hasPrefix(Self.progressBullet + tool) }) else { return }
        lines[row] += "  " + mark
        messages[index].text = lines.joined(separator: "\n")
    }

    /// 工具调用被拒时**把原因摆在卡片上**（`FR-AI-25` ③：未登记的调用也如实显示）。
    public mutating func markDenied(cardID: UUID, reason: String) {
        guard let index = cards.firstIndex(where: { $0.id == cardID }) else { return }
        cards[index].outcome = .denied(reason)
    }

    /// 一条**代签**记录（"我没问就做了"要能被查、被推翻）。
    public struct AgentAutoApproval: Equatable, Sendable {
        public var tool: String
        public var fingerprint: String
        public var preview: String
        public var reason: String
    }

    // MARK: - 审批（④）

    /// 某个写 / 执行工具要审批 —— **批准之前先把要改什么摆出来**。
    @discardableResult
    public mutating func requestApproval(name: String, fingerprint: String, preview: String) -> UUID {
        // **任务范围内代签**（`FR-AI-34`）：用户说一句"把这个修好"，不该再被问二十次。
        // 代签**不绕过护栏** —— 沙箱与伤害刹停都在工具层更早生效；这里只是"这一步要不要人手点一下"。
        // 代签必须**可见可审**：卡片建出来就是已批态，另记一条 `autoApprovals`（理由带出处）。
        switch AgentScopeGate.judge(tool: name, preview: preview,
                                    autoApprovedCount: autoApprovals.count, scope: taskScope) {
        case .autoApproved(let reason):
            let card = AgentToolCard(name: name, arguments: preview,
                                     outcome: .approved(fingerprint: fingerprint, preview: preview),
                                     expanded: false)
            cards.append(card)
            grants.insert(fingerprint)
            autoApprovals.append(AgentAutoApproval(tool: name, fingerprint: fingerprint,
                                                   preview: preview, reason: reason))
            return card.id
        case .needsHuman:
            let card = AgentToolCard(name: name, arguments: preview,
                                     outcome: .pendingApproval(fingerprint: fingerprint, preview: preview),
                                     expanded: true)
            cards.append(card)
            return card.id
        }
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
