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
    /// 已撤销（`FR-AI-25` ⑤）：应用之后人点了一下「撤销」，文件已回到应用前。
    /// 与 `denied` 分开：被拒是**没动过文件**，撤销是**动过又退回去了** —— 审计上不是一回事。
    case undone(fingerprint: String)

    public var isTerminal: Bool {
        switch self {
        case .executed, .denied, .applied, .undone: return true
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
    /// **出单那一刻**目标的基线串（`FR-AI-31` ①）：执行类动作没有目标文件 ⇒ `nil`。
    /// 兑现时把它交回工具层复核 —— 审批之后文件被改过就**不拿旧审批盖新内容**。
    public var baseDigest: String?

    public init(id: UUID = UUID(), name: String, arguments: String,
                outcome: AgentToolCardOutcome = .running, expanded: Bool = false,
                baseDigest: String? = nil) {
        self.id = id
        self.name = name
        self.arguments = arguments
        self.outcome = outcome
        self.expanded = expanded
        self.baseDigest = baseDigest
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
        case .undone: return "undone"
        }
    }

    /// 批准前要给人看的预览（差异 / 命令原文）。
    public var approvalPreview: String? {
        switch outcome {
        case .pendingApproval(_, let preview), .approved(_, let preview): return preview
        default: return nil
        }
    }

    /// **批了但还没落地**（`FR-AI-31` ① 的兑现那一格）。
    ///
    /// 手动批是「点了就立刻兑现」，代签（`FR-AI-34`）是「建单即已批、等宿主观测口兑现」——
    /// 两种都停在 `.approved` 这一档，界面据此决定要不要去兑现。
    public var isAwaitingApply: Bool {
        if case .approved = outcome { return true }
        return false
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

/// **压缩读数**（`NFR-AI-08` ③）：界面上那一行「压了几段 / 省了多少 token」吃它。
///
/// 只放**报得出来的数**：压掉的条目数、估算省下的 token、留下几条、最早被压掉的那条摘要
/// （摘要留着是为了人点一下能看见「丢了哪些」）。累加口径 = 本会话跨轮累计（`apply` 里加）。
public struct AgentChatCompressionReading: Equatable, Sendable {
    public var entries: Int
    public var estimatedTokensSaved: Int
    public var kept: Int
    public var earliest: String

    public init(entries: Int = 0, estimatedTokensSaved: Int = 0, kept: Int = 0, earliest: String = "") {
        self.entries = entries
        self.estimatedTokensSaved = estimatedTokensSaved
        self.kept = kept
        self.earliest = earliest
    }
}

/// **续跑读数**（`NFR-AI-08` ⑤）：界面上那一行「从第 N 跳接上 · 跳过 M 跳」吃它。
///
/// 三个数都是**检查点自己报的**（不是界面猜的）：从第几跳接上、相对上一轮停在的那一跳
/// 实际退了几跳、读盘时跳过几个坏行。`nil` = 这一轮不是续跑（那格就不出现，不留空壳）。
public struct AgentChatResumeReading: Equatable, Sendable {
    public var fromStep: Int
    public var skippedSteps: Int
    public var skippedCheckpointLines: Int

    public init(fromStep: Int, skippedSteps: Int = 0, skippedCheckpointLines: Int = 0) {
        self.fromStep = fromStep
        self.skippedSteps = skippedSteps
        self.skippedCheckpointLines = skippedCheckpointLines
    }
}

/// **完成判据读数**（`FR-AI-31` ②）：界面上那一行「完成判据 ✓ N 条 / 未验证 · 原因」吃它。
///
/// `nil` = 这一轮没出现完成声明、也没接验证器（那格不出现，不留空壳）。
/// 为什么**不**用「跑完了」冒充：一轮跑完（`finished`）只是模型给了答复；
/// 「这件事做成了没有」是另一问，答案由 `AgentCompletionVerifier` 按当次证据给。
public struct AgentChatCompletionReading: Equatable, Sendable {
    /// 机器码：`verified:N` / `unverified:<reason>` / `notClaimed`。
    public var code: String
    public var citations: Int

    public init(code: String, citations: Int = 0) {
        self.code = code
        self.citations = citations
    }

    public var isVerified: Bool { code.hasPrefix("verified") }
    public var isUnverified: Bool { code.hasPrefix("unverified") }
    /// 原因码（`unverified:` 之后那段；没原因就是空串）。
    public var reason: String {
        let prefix = "unverified:"
        return code.hasPrefix(prefix) ? String(code.dropFirst(prefix.count)) : ""
    }
}

/// **长跑监控读数**（`FR-AI-31` ③）：界面上那一行「长跑告警 · 空转 3 跳」吃它。
///
/// `nil` = 这一轮没跑飞（那格不出现，不留空壳）。`kind` 是机器码：
/// `stalled` / `spinning` / `retryStorm` / `budgetApproaching` / `budgetExhausted`；
/// `observed` = 观测值、`threshold` = 阈值（0 = 这一档没有阈值）、`alerts` = 本轮累计报过几条。
/// 为什么留 `alerts`：告警**同类只报一次**，但「这一轮到底响过几次」事后要能回答。
public struct AgentChatMonitorReading: Equatable, Sendable {
    public var kind: String
    public var observed: Int
    public var threshold: Int
    public var alerts: Int

    public init(kind: String, observed: Int, threshold: Int = 0, alerts: Int = 1) {
        self.kind = kind
        self.observed = observed
        self.threshold = threshold
        self.alerts = alerts
    }

    /// 是不是「卡住」那一档（界面据此上更重的颜色 —— 卡住是要人动手的）。
    public var isStalled: Bool { kind == AgentRunAlertKind.stalled.rawValue }
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
    /// **压缩读数**（`NFR-AI-08` ③）：跨轮累计 —— 压了几段、估算省了多少 token。
    /// `nil` = 这个会话一次都没压过（界面那一行就不出现，不留空壳）。
    public private(set) var contextCompression: AgentChatCompressionReading?
    /// **续跑读数**（`NFR-AI-08` ⑤）：这一轮是不是从检查点接上的。
    /// 每开一次跑就清一次（`beginRun` / `beginResume`）—— 不该让上一轮的读数冒充这一轮。
    public private(set) var resumeReading: AgentChatResumeReading?
    /// **完成判据读数**（`FR-AI-31` ②）：这一轮模型有没有拿得出可复核的完成证据。
    /// 每开一次跑就清一次（与续跑读数同一条口径：上一轮的结论不许冒充这一轮）。
    public private(set) var completionReading: AgentChatCompletionReading?
    /// **长跑监控读数**（`FR-AI-31` ③）：这一轮跑飞过没有、哪一档、观测值多少。
    /// 每开一次跑就清一次（同上：上一轮的告警不许冒充这一轮）。
    public private(set) var monitorReading: AgentChatMonitorReading?
    /// 看门狗的心跳（`FR-AI-31` ③「卡住」）：最近一次有进展的时刻。
    /// 为什么放在状态里而不是监控器里：看门狗住在界面（按秒 tick），而监控器住在循环里（按跳喂）——
    /// 两边共用 `AgentRunMonitor.stallAlert` 这一条判定，阈值只有一份。
    public private(set) var lastProgressAt: Date?
    /// 这一轮已经报过「卡住」没有（同类只报一次 —— 告警不刷屏）。
    public private(set) var stallReported = false

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
        // 上一轮的续跑读数不许冒充这一轮（`NFR-AI-08` ⑤）。
        resumeReading = nil
        // 上一轮的完成判据结论同样不许冒充这一轮（`FR-AI-31` ②）。
        completionReading = nil
        // 长跑告警与心跳：新一轮从零起算（`FR-AI-31` ③）。
        monitorReading = nil
        lastProgressAt = Date()
        stallReported = false
        isRunning = true
    }

    /// **继续上次**（`NFR-AI-08` ⑤）：接着上一轮停在的那一跳跑。
    ///
    /// 与 `beginRun` 的两点不同：
    /// · **不追加用户消息**（问的还是同一个问题；再塞一条会让人以为问了第二遍）；
    /// · 步骤清单照样重起（跳号由事件自带的号码给，从中间起也显示得对）。
    public mutating func beginResume() {
        guard canSend else {
            if let code = endpoint.blockerCode { appendNotice(code) }
            return
        }
        steps = []
        resumeReading = nil
        completionReading = nil
        // 续跑同样是「新的一轮跑」：告警与心跳从零起算（`FR-AI-31` ③）。
        monitorReading = nil
        lastProgressAt = Date()
        stallReported = false
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
        // 收到任何事件都算「有进展」的迹象 —— 心跳在这一处刷（看门狗吃它，`FR-AI-31` ③「卡住」那一档）。
        // 放在最前面而不是每个 case 里各写一遍：漏一个 case 就会出现「明明在动、界面却说卡住」。
        noteProgress()
        switch event {
        case .retrying(let attempt, let after, let reason):
            // 过程行里追一句：**第几次重试、等多久、为什么** —— 别让人以为卡死了。
            appendProgressLine("retry \(attempt): \(reason) (\(String(format: "%.1f", after))s)")
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
            // **写冲突 / 基线过期不许只留在过程行的机器码里**（`FR-AI-31` ①）：
            // 这两种都是「文件没被写」而模型可能以为写过了 ⇒ 另出一句可读的提示（码留给界面翻）。
            if outcome.hasPrefix("denied:") {
                let code = String(outcome.dropFirst("denied:".count))
                if code == AgentToolRefusal.writeConflict.rawValue
                    || code == AgentToolRefusal.staleTarget.rawValue {
                    appendNotice(code)
                }
            }
        case .approvalRequested(let name, let fingerprint, let preview, let baseDigest):
            // **要审批就真的出一张单**（`FR-AI-23` ④）：批准之前先能看见要改什么。
            // 单子的基线跟着卡片走（`FR-AI-31` ①）—— 兑现时交回工具层复核。
            // 代签那一档（`FR-AI-34`）在这里被 `requestApproval` 判成「已批」，落地由宿主观测口立刻兑现。
            requestApproval(name: name, fingerprint: fingerprint, preview: preview,
                            baseDigest: baseDigest.isEmpty ? nil : baseDigest)
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
        case .contextCompressed(let entries, let tokensSaved, let kept, let earliest):
            // `NFR-AI-08` ③：压缩**不许静默** —— 读数是**跨轮累计**（这一轮压了两段、上一轮压了一段 ⇒ 三段）。
            // 只改这一个字段，不往消息流里塞一条：它是**读数**，不是过程（人类主人 2026-10-18：
            // 「压缩了几轮、省了多少 token，界面上要有一行」—— 那一行在状态块里，不刷屏）。
            let previous = contextCompression
            contextCompression = AgentChatCompressionReading(
                entries: (previous?.entries ?? 0) + entries,
                estimatedTokensSaved: (previous?.estimatedTokensSaved ?? 0) + tokensSaved,
                kept: kept,
                earliest: earliest.isEmpty ? (previous?.earliest ?? "") : earliest
            )
        case .completionChecked(let code, let citations):
            // `FR-AI-31` ②：完成判据**不许静默** —— 复核过了就把结论摆出来。
            // 读数进状态块那一行；`unverified` 另出**一条可读提示**（人类主人要看懂「它说做完了，但没验证」），
            // 与写冲突那两种拒因同一条口径：码留给界面翻，别让人去读机器码。
            completionReading = AgentChatCompletionReading(code: code, citations: citations)
            if code.hasPrefix("unverified") {
                appendNotice("completionUnverified")
            }
        case .resumed(let fromStep, let skipped, let skippedLines):
            // `NFR-AI-08` ⑤：续跑**不许静默** —— 三个数原样落到读数里（从第几跳接上 / 退了几跳 / 坏了几行），
            // 界面那一行吃它。与压缩同一条口径：这是**读数**，不往消息流里塞一条。
            resumeReading = AgentChatResumeReading(fromStep: fromStep,
                                                   skippedSteps: skipped,
                                                   skippedCheckpointLines: skippedLines)
        case .monitorAlert(let kind, let observed, let threshold):
            // `FR-AI-31` ③：跑飞了**不许静默** —— 读数进状态块那一行，另出一条可读提示
            //（与写冲突 / 完成未验证同一条口径：码留给界面翻，别让人去读机器码）。
            applyMonitor(AgentRunAlert(kind: AgentRunAlertKind(rawValue: kind) ?? .spinning,
                                       observed: observed, threshold: threshold))
        }
    }

    // MARK: - 长跑监控（`FR-AI-31` ③）

    /// **有进展**（增量到了 / 工具动了 / 跳开始了）：界面把它喂进来，看门狗据此判「卡住」。
    public mutating func noteProgress(at now: Date = Date()) {
        guard isRunning else { return }
        lastProgressAt = now
    }

    /// **看门狗**：距上次进展超过阈值 ⇒ 报一次「卡住」（同类只报一次）。
    ///
    /// 为什么这一档不在循环里判：循环正卡在 `await` 里，它自己腾不出来报「我卡住了」；
    /// 由界面按秒 tick 才是真的「卡住能看见」。判定本身共用 `AgentRunMonitor.stallAlert`。
    @discardableResult
    public mutating func checkStall(now: Date = Date(),
                                    limits: AgentRunMonitorLimits = AgentRunMonitorLimits()) -> AgentRunAlert? {
        guard isRunning, !stallReported else { return nil }
        let idle = Int(now.timeIntervalSince(lastProgressAt ?? now))
        guard let alert = AgentRunMonitor.stallAlert(idleSeconds: idle, limits: limits) else { return nil }
        applyMonitor(alert)
        return alert
    }

    /// 把一条告警落进读数 + 出一条可读提示。
    private mutating func applyMonitor(_ alert: AgentRunAlert) {
        if alert.kind == .stalled { stallReported = true }
        monitorReading = AgentChatMonitorReading(kind: alert.kind.rawValue,
                                                observed: alert.observed,
                                                threshold: alert.threshold,
                                                alerts: (monitorReading?.alerts ?? 0) + 1)
        appendNotice("monitor:\(alert.kind.rawValue)")
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
    ///
    /// `baseDigest` = 出单那一刻目标的基线串（`FR-AI-31` ①）：跟着卡片活到兑现那一步，
    /// 兑现时交回工具层复核。不给 ⇒ 不记基线（旧行为逐字不变）。
    @discardableResult
    public mutating func requestApproval(name: String, fingerprint: String, preview: String,
                                         baseDigest: String? = nil) -> UUID {
        // **任务范围内代签**（`FR-AI-34`）：用户说一句"把这个修好"，不该再被问二十次。
        // 代签**不绕过护栏** —— 沙箱与伤害刹停都在工具层更早生效；这里只是"这一步要不要人手点一下"。
        // 代签必须**可见可审**：卡片建出来就是已批态，另记一条 `autoApprovals`（理由带出处）。
        switch AgentScopeGate.judge(tool: name, preview: preview,
                                    autoApprovedCount: autoApprovals.count, scope: taskScope) {
        case .autoApproved(let reason):
            let card = AgentToolCard(name: name, arguments: preview,
                                     outcome: .approved(fingerprint: fingerprint, preview: preview),
                                     expanded: false,
                                     baseDigest: baseDigest)
            cards.append(card)
            grants.insert(fingerprint)
            autoApprovals.append(AgentAutoApproval(tool: name, fingerprint: fingerprint,
                                                   preview: preview, reason: reason))
            return card.id
        case .needsHuman:
            let card = AgentToolCard(name: name, arguments: preview,
                                     outcome: .pendingApproval(fingerprint: fingerprint, preview: preview),
                                     expanded: true,
                                     baseDigest: baseDigest)
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

    /// 撤销完成（`FR-AI-25` ⑤）：卡片从「已应用」变「已撤销」。
    ///
    /// **只允许从 `applied` 转**：还在跑 / 等审批 / 被拒的卡片点撤销没有意义（文件没被改过），
    /// 允许转就是给界面留一条「点了没反应但状态变了」的假路径。
    @discardableResult
    public mutating func markUndone(cardID: UUID) -> Bool {
        guard let index = cards.firstIndex(where: { $0.id == cardID }),
              case .applied(let fingerprint) = cards[index].outcome else { return false }
        cards[index].outcome = .undone(fingerprint: fingerprint)
        return true
    }

    /// 这张卡片现在能不能撤销（界面据此决定「撤销」按钮出不出现）。
    public func canUndo(cardID: UUID) -> Bool {
        guard let card = cards.first(where: { $0.id == cardID }) else { return false }
        if case .applied = card.outcome { return true }
        return false
    }

    public mutating func toggleExpanded(cardID: UUID) {
        guard let index = cards.firstIndex(where: { $0.id == cardID }) else { return }
        cards[index].expanded.toggle()
    }

    public mutating func setEndpoint(_ state: AgentChatEndpointState) {
        endpoint = state
    }
}
