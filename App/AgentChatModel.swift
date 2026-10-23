import Foundation
import Combine
import DoyahCore

/// 对话页签的状态壳（`FR-AI-25`）。
///
/// **规则与状态在 Core 的 `AgentChatState`**（判据在那边咬）；本类只做三件事：
/// 把循环跑起来（并发）· 把循环的**进度事件**搬进状态 · 把界面动作翻译成 Core 的转移。
/// 这样「界面能不能用」不靠肉眼看 —— Core 那一侧已经判过一遍。
@MainActor
final class AgentChatModel: ObservableObject, AgentLoopObserver {

    @Published private(set) var state = AgentChatState()
    @Published var input = ""

    /// 宿主注入：给一个提示词，造一条**已经配好上下文**的循环（端点 / 模型 / 密钥 / 工具都在宿主那侧组装）。
    /// 造不出来 ⇒ 如实报，不假装在跑。
    /// `FR-AI-28` 门控：**没有新内容就不发请求**（省 token）。
    /// 判定是纯函数（`Core/AgentInvocationGate`），挡下留痕也在这一个类型里 —— 宿主无需干预，
    /// 也不接受宿主来"放行/挡下"（门控只回答"要不要问模型"，回答不了"能不能执行"）。
    var gate = AgentInvocationGate()
    /// 造循环。**是 `async` 的**：建循环时要现取一次本次上下文（`FR-AI-22`：当前连接的表结构摘要等），那一步是 IO。
    /// 第二个参数是**这一轮提问的落账**（`NFR-AI-08` ⑤：分账号 + 从第几跳起）—— 宿主据此把检查点
    /// 按「哪一轮提问」分账，而不是按会话号（否则下个提问会接上上个问题的检查点）。
    var makeLoop: ((String, AgentTurnPlan, any AgentLoopObserver) async -> (loop: AgentLoop, context: AgentLoopContext)?)?
    /// 宿主注入：真正把一次批准**兑现**（写盘 / 跑命令）。
    ///
    /// 结果是**机器码**而不是 `Bool`（`FR-AI-31` ①）：写冲突（`writeConflict`）/ 基线过期
    /// （`staleTarget`）/ 写盘失败（`failed`）三件事的处置不一样，一个 `false` 会把它们压成
    /// 同一句「没成」—— 那正是「静默覆盖」的另一面：**没说清为什么没写**。
    var applyApproval: ((AgentToolCard) async -> ApplyResult)?
    /// 宿主注入：把一次**已经应用**的改动撤回去（`FR-AI-25` ⑤：一步撤销，文件逐字节回到应用前）。
    /// 撤销目标由宿主按卡片号从账上找 —— 这里只传卡片，不传「要写什么」：
    /// 原文只该存在一处（Core 的 `AgentEditJournal`），界面与视图模型都不许自己记一份。
    var undoApplied: ((AgentToolCard) async -> UndoResult)?
    /// 宿主注入：授权粒度（`FR-AI-34`）。缺省 = 任务范围内代签；设成 `.askEachAction` 就回到每个动作都问。
    var scopeProvider: () -> AgentTaskScope.Mode = { .taskScope }
    /// 宿主注入：端点状态（界面出现 / 设置改过之后取一次）。
    var endpointProvider: () -> AgentChatEndpointState = { .notConfigured }
    /// 宿主注入：**当前档的真值源**（模型名 + 窗口 / 价目，`FR-AI-25` 信息面）。
    /// 缺省给空的 ⇒ 三格里只出现「端点自己报得出」的那一格，其余不画（宁缺不假）。
    var meterInputProvider: () -> AgentMeterInput = { AgentMeterInput() }

    /// 本会话累计（**每次跑完把这一轮的用量并进来**）。两侧共用 `TokenUsageLedger`，口径同一个。
    @Published private(set) var sessionUsage = TokenUsageLedger()
    /// 上一轮跑完用了多少秒（`nil` = 还没跑过）。
    @Published private(set) var lastElapsedSeconds: Double?
    /// 端点读数（状态条那几格）。
    var endpointState: AgentChatEndpointState { state.endpoint }

    /// **上下文占用读数** = **上一次请求的输入 token**（端点自己报的那个数）。
    ///
    /// 为什么用「上次请求输入」而不是"会话累计"：会话累计是**花掉的总量**，上下文占用是**当前这一窗有多满** ——
    /// 两件事。Hermes 那格 `~227K/1M` 说的是后者。**分母**（模型窗口）由当前档的真值源给
    /// （用户填的优先，其次内置表，认不出就显示「窗口未知」）。
    @Published private(set) var lastPromptTokens: Int?

    /// **信息面三格**（`FR-AI-25`）：上下文占用 / 缓存命中率 / 本会话估算花费。
    ///
    /// 换算是**纯函数**（`AgentModelMeter`，判据在 `Tests/AgentModelMeterTests.swift`），
    /// 这里只把三样输入递进去：当前档真值源 + 会话账 + 上次输入 token。
    /// 任何一格缺真值源就不画（不当 0、不猜）。
    var modelReadings: AgentModelReadings {
        AgentModelMeter.readings(input: meterInputProvider(),
                                 ledger: sessionUsage,
                                 lastPromptTokens: lastPromptTokens)
    }

    /// 当前动作（输入框上方那一行）。
    var currentAction: String? { state.currentAction }

    /// 会话标题（状态行最右）。
    var sessionTitle: String? { state.sessionTitle }

    /// **压缩读数**（`NFR-AI-08` ③）：界面上那一行「已压缩 N 段 · 省 ≈M token」。
    var contextCompression: AgentChatCompressionReading? { state.contextCompression }

    /// **续跑读数**（`NFR-AI-08` ⑤）：界面上那一行「已续上 … · 退回 N 跳」。`nil` = 这一轮不是续跑。
    var resumeReading: AgentChatResumeReading? { state.resumeReading }

    /// **完成判据读数**（`FR-AI-31` ②）：`verified:N` / `unverified:<reason>` / `notClaimed`。
    /// `nil` = 这一轮没有完成声明（也没接验证器）。
    var completionReading: AgentChatCompletionReading? { state.completionReading }

    /// **长跑监控读数**（`FR-AI-31` ③）：卡住 / 空转 / 反复重试 / 配额将尽 —— 状态块上要有这一行。
    /// `nil` = 这一轮没跑飞（那格不出现，不留空壳）。
    var monitorReading: AgentChatMonitorReading? { state.monitorReading }

    /// **监控阈值**（`FR-AI-31` ③）：`stallSeconds` 就是「卡住」的判据。
    /// 阈值是**参数**（契约只钉「卡住要报」，不钉某个秒数）—— 跑长命令的机器可以放大。
    var monitorLimits = AgentRunMonitorLimits()
    /// 看门狗多久 tick 一次（秒）。
    static let watchdogTickSeconds: Double = 5

    /// 宿主注入：把这一轮的**配额账本**回写（`NFR-AI-04`）。
    /// 不接 ⇒ 这一轮不记账（如实：跨轮累计不会涨，配额也就永远到不了上限 —— 那正是旧缺口）。
    var recordQuotaLedger: ((AgentQuotaLedger) -> Void)?

    /// 吞吐（token/秒）：**只在这两样都有读数时给**，算不出来就不显示（不编）。
    var tokensPerSecond: Double? {
        guard let seconds = lastElapsedSeconds, seconds > 0.05, sessionUsage.completionTokens > 0 else { return nil }
        return Double(sessionUsage.completionTokens) / seconds
    }

    /// 本会话的 id（**切换会话时会变**：新一轮跳要落到被切到的那份文件里）。
    ///
    /// 以前是 `let`（模型一生成就定死），于是「历史会话」只能看、不能续 —— 切过去再提问，
    /// 新跳会写进一个新建的会话文件，用户的体感是「切了个假的」。现在它是可变状态：
    /// `openSession` / `startNewSession` 改它，`makeLoop` 每次开跑现读。
    @Published private(set) var sessionID: String
    /// 会话列表（最近活动的在前）。**只在打开列表时刷新** —— 每敲一个字都扫盘是浪费。
    @Published private(set) var sessions: [AgentSessionSummary] = []
    /// 读不出来的会话文件数（坏文件跳过并计数，不静默丢）。
    @Published private(set) var sessionsSkippedFiles = 0
    /// 宿主注入：会话存储（列表 / 切换都要读盘）。没接 ⇒ 列表为空、切换如实说不可用。
    var sessionStore: AgentSessionStore?

    private let cancellation = CancellationFlag()
    private var task: Task<Void, Never>?
    /// 看门狗（`FR-AI-31` ③「卡住」）：跑着的时候每 `watchdogTickSeconds` 秒看一眼。
    private var watchdog: Task<Void, Never>?

    /// `state` 可注入：界面快照（`TestsUISnapshot/`）要拍得出「有一屏消息」的样子，
    /// 而消息只能从 `AgentChatState` 进来。这是**依赖注入**，不是测试专用开关 ——
    /// 生产路径照旧走默认值。
    init(sessionID: String = "chat-\(UUID().uuidString)",
         state: AgentChatState = AgentChatState(),
         queue: AgentPromptQueue = AgentPromptQueue()) {
        self.sessionID = sessionID
        self.state = state
        self.queue = queue
    }

    /// 取消标记（跨并发域读：用锁，不掺进界面状态）。
    private final class CancellationFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var flag = false
        func set() { lock.lock(); flag = true; lock.unlock() }
        func reset() { lock.lock(); flag = false; lock.unlock() }
        var isSet: Bool { lock.lock(); defer { lock.unlock() }; return flag }
    }

    // MARK: - 界面读的东西

    var messages: [AgentChatMessage] { state.messages }
    var cards: [AgentToolCard] { state.cards }
    /// 输入框上方那块清单（一步步走）。
    var steps: [AgentChatStep] { state.steps }
    var isRunning: Bool { state.isRunning }

    /// 排队中的提问（`/queue` 的同义物）。**归客户端所有**：循环不知道它存在，
    /// 所以三端（macOS / Windows / Linux）都能有、行为一致，不依赖任何平台能力。
    @Published private(set) var queue = AgentPromptQueue()
    var grants: Set<String> { state.grants }

    /// 端点那一句话（如实说，不写死；文案从语言表取）。
    var blockerText: String? {
        switch state.endpoint.blockerCode {
        case "endpointNotConfigured": return L(.agentChatEndpointNotConfigured)
        case "endpointUnreachable": return L(.agentChatEndpointUnreachable)
        default: return nil
        }
    }

    /// 自动滚动用的**单调读数**（消息条数 + 全部正文长度 + 卡片数）。
    ///
    /// 为什么不用 `messages.last?.text` 当读数：流式那条**不一定是最后一条** —— 过程块会排在它下面
    /// （`AgentChat.swift` 的 `appendProgressLine`）⇒ 只看最后一条，逐段出现时界面滚不动。
    var scrollTick: Int {
        state.messages.reduce(state.messages.count + state.cards.count + state.steps.count) { $0 + $1.text.count }
    }

    var canSend: Bool {
        state.canSend && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func refreshEndpoint() {
        state.setEndpoint(endpointProvider())
    }

    // MARK: - 界面动作

    /// 上一轮提问的落账（`NFR-AI-08` ⑤）：下一轮「能不能续」看它。
    /// 只活在内存里 —— 进程重启后要不要续是另一件事（那要看会话留痕，不在本片）。
    private var lastTurn: AgentTurnRecord?
    /// 上一轮的原话（「继续上次」沿用它 —— 不让用户重打一遍）。
    private var lastPrompt: String?

    /// **能不能续上一次**：上一轮没走完（限额 / 取消 / 失败）才有得续。
    ///
    /// 判定走 Core 的 `AgentTurnPlanner`（纯函数），界面只读结论 —— 这里不另写一套规矩，
    /// 否则「什么时候能续」会有两个答案。
    var canContinue: Bool {
        guard !state.isRunning, lastPrompt != nil else { return false }
        return continuePlan?.resumes == true
    }

    /// 「继续上次」会从第几跳之后接着跑（`nil` = 没得续）。1 起，给人看的数。
    var continueStep: Int? {
        guard let plan = continuePlan, plan.resumes else { return nil }
        return plan.requestedStep
    }

    private var continuePlan: AgentTurnPlan? {
        guard lastPrompt != nil else { return nil }
        return AgentTurnPlanner.plan(sessionID: sessionID, previous: lastTurn, intent: .continueLast)
    }

    func send() async {
        let prompt = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        // **一轮还在跑时提交的提问不丢、也不打断**：排进队列，这一轮结束后按序接着跑
        // （Hermes CLI 的 `/queue` 同义；这里用界面表达，不要求用户记斜杠命令）。
        if state.isRunning {
            guard queue.enqueue(prompt) != nil else { return }
            input = ""
            return
        }
        await start(prompt: prompt, intent: .newQuestion)
    }

    /// 撤掉一条排队中的提问（界面上那个 `✕`）。
    func removeQueued(id: UUID) {
        queue.remove(id: id)
    }

    /// 清空队列。
    func clearQueue() {
        queue.clear()
    }

    // MARK: - 会话列表与切换（§9.1.16 缺口 ②）

    /// 刷新会话列表（打开列表 / 跑完一轮之后调）。
    ///
    /// 判据面：列表项的**标题 / 时间 / 跳数**由 `AgentSessionStore.summaryList` 给（Core 判据
    /// `AgentSessionHistoryTests`），这里只负责「什么工作区、什么时候读」。
    func reloadSessions(workspacePath: String?) {
        guard let store = sessionStore, let workspacePath, !workspacePath.isEmpty else {
            sessions = []
            sessionsSkippedFiles = 0
            return
        }
        let result = store.summaryList(workspace: workspacePath)
        sessions = result.summaries
        sessionsSkippedFiles = result.skippedFiles
    }

    /// 能不能切会话：跑着的时候不行（切过去会让正在跑的那一轮把跳写进另一份文件）。
    var canSwitchSession: Bool { !state.isRunning }

    /// 切到一条历史会话：把盘上那些跳摊回消息流，并把 `sessionID` 指向它
    /// （之后提的问题就续在这条会话上，不另起一份）。
    ///
    /// 读不出来 ⇒ **如实说**（追加一条 notice），界面保持在原地 —— 不静默什么也不做。
    @discardableResult
    func openSession(_ id: String, workspacePath: String?) -> Bool {
        guard canSwitchSession else { return false }
        guard let store = sessionStore, let workspacePath, !workspacePath.isEmpty else {
            state.appendNotice("sessionUnavailable")
            return false
        }
        let loaded = store.load(sessionID: id, workspace: workspacePath)
        guard let session = loaded.session else {
            state.appendNotice("sessionUnavailable")
            return false
        }
        sessionID = session.header.id
        let endpoint = state.endpoint
        let scope = state.taskScope
        resetForReplay()
        state = AgentChatState(messages: AgentSessionReplay.messages(from: session), endpoint: endpoint)
        state.taskScope = scope
        return true
    }

    /// 开一条新会话（旧会话留在盘上，随时可以从列表里切回去）。
    func startNewSession() {
        guard canSwitchSession else { return }
        let endpoint = state.endpoint
        let scope = state.taskScope
        sessionID = "chat-\(UUID().uuidString)"
        resetForReplay()
        state = AgentChatState(endpoint: endpoint)
        state.taskScope = scope
    }

    /// 换会话时**清掉按会话累计的读数**：换了一条会话还挂着上一条的 token 账，
    /// 界面就是在报别人的数（`NFR-AI-04` 的账随会话走）。
    private func resetForReplay() {
        lastPrompt = nil
        lastTurn = nil
        lastElapsedSeconds = nil
        lastPromptTokens = nil
        sessionUsage = TokenUsageLedger()
    }

    /// 重发（§9.1.16 ③）：以该条助手消息对应的**那次提问**为锚再跑一轮，旧轮保留。
    ///
    /// 找不到锚点（例如这条是开场白、前面没有提问）⇒ **什么都不做**并如实说一句，
    /// 不许拿输入框里现有的字凑数 —— 那会变成「重发」出一句人没问过的话。
    func resend(assistantMessageID: UUID) async {
        guard !state.isRunning else { return }
        guard let prompt = AgentResendAnchor.userPrompt(before: assistantMessageID, in: state.messages) else {
            state.appendNotice(L(.agentResendNoAnchor))
            return
        }
        await start(prompt: prompt, intent: .newQuestion)
    }

    /// **继续上次**（`NFR-AI-08` ⑤）：接着上一轮停在的那一跳跑，**不再发已完成的跳**。
    ///
    /// 为什么不复用 `send()`：它要清空输入框、要追加一条用户消息；续跑问的还是同一个问题，
    /// 再塞一条会让人以为问了第二遍。所以两件事拆开，共用 `start`。
    func continueLast() async {
        guard let prompt = lastPrompt, canContinue else { return }
        await start(prompt: prompt, intent: .continueLast)
    }

    private func start(prompt: String, intent: AgentTurnIntent) async {
        // **分账**（`NFR-AI-08` ⑤）：新提问 ⇒ 新分账号（不接上一个问题的检查点）；
        // 显式继续 ⇒ 沿用上一轮的分账号 + 报出停在第几跳。
        let plan = AgentTurnPlanner.plan(sessionID: sessionID, previous: lastTurn, intent: intent)
        if intent == .continueLast && !plan.resumes {
            // 按钮本该是灰的；走到这里说明状态不新鲜 —— **如实说**，不假装续上了。
            state.appendNotice(plan.note)
            return
        }
        // 授权粒度按设置走（**每次开跑前定一次**：本轮中途不换口径，免得一半问一半不问）。
        state.taskScope = AgentTaskScope(mode: scopeProvider())
        switch intent {
        case .newQuestion: state.beginRun(prompt: prompt)
        case .continueLast: state.beginResume()
        }
        guard state.isRunning else { return }   // 不能发时 `beginRun` 已如实出提示，这里不许往下走
        cancellation.reset()
        startWatchdog()
        guard let prepared = await makeLoop?(prompt, plan, self) else {
            stopWatchdog()
            state.apply(.failed("loopUnavailable"))
            return
        }
        // `FR-AI-28` 门控：**没有新内容就不发请求**（省 token）。
        //
        // 放在 `makeLoop` **之后**、`loop.run` **之前** —— 因为指纹要覆盖**整段提示词**（含本次上下文），
        // 而上下文是 `makeLoop` 里现取的。同样的问法再来一次 ⇒ 提示词逐字相同 ⇒ 挡下。
        //
        // **边界**（条文写死）：门控只决定"要不要问模型"；「能不能执行」仍归 `AgentGuardrail` + 审批队列 ——
        // 本处不碰那件事，也**不许**顺手把提示词改了（放行的语义就是"当它没来过"）。
        //
        // **续跑那一档例外**（`NFR-AI-08` ⑤）：提示词与上一轮逐字相同是**必然的**（问的还是同一个问题），
        // 而「继续上次」是用户明确的继续动作、且**不发已完成的跳** ⇒ 门控的历史那一条对它不适用。
        // 门控的语义没被放宽：它管的仍是「没有新内容就不发」，只是续跑本来就是「没新内容」。
        let trigger = AgentGateTrigger(
            source: intent == .continueLast ? "chat:resume" : "chat",
            digest: AgentFingerprint.hash(prepared.context.systemPrompt + "\u{1}" + prepared.context.userPrompt),
            at: Date()
        )
        let decision = intent == .continueLast
            ? gate.decide(trigger, ignoringHistory: true)
            : gate.decide(trigger)
        switch decision {
        case .skipped(let reason):
            gate.record(.skipped(reason: reason), for: trigger)
            state.apply(.failed(reason))       // 如实说"为什么没发"，不静默；**输入框不清空**（用户改一个字就能再发）
            return
        case .proceed:
            gate.record(.proceed, for: trigger)
        }
        if intent == .newQuestion { input = "" }
        lastPrompt = prompt
        let started = Date()
        task = Task { [weak self] in
            let result = await prepared.loop.run(context: prepared.context,
                                                 requestedStep: plan.requestedStep,
                                                 isCancelled: { [cancellation] in cancellation.isSet })
            await MainActor.run {
                guard let self else { return }
                self.lastElapsedSeconds = Date().timeIntervalSince(started)
                // 记这一轮的账：下一轮能不能续、从第几跳续，看的就是它。
                self.lastTurn = AgentTurnPlanner.record(turn: plan.turn, result: result)
                self.finish(result)
            }
        }
    }

    /// 取消：**在下一跳之前停**（循环口径），已产生的工具结果仍留痕。
    func stop() {
        cancellation.set()
    }

    // MARK: - 看门狗（`FR-AI-31` ③「卡住」那一档）

    /// 跑着的时候按秒看一眼：距上次进展超过阈值 ⇒ 报一次「卡住」。
    ///
    /// 为什么在界面而不在循环里：循环正卡在 `await` 里，它自己腾不出来喊「我卡住了」。
    /// 判定本身仍是 Core 的 `AgentRunMonitor.stallAlert`（阈值只有一份），这里只负责按点敲。
    private func startWatchdog() {
        stopWatchdog()
        let tick = Self.watchdogTickSeconds
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(tick * 1_000_000_000))
                guard !Task.isCancelled, let self else { return }
                guard self.state.isRunning else { return }
                self.state.checkStall(limits: self.monitorLimits)
            }
        }
    }

    private func stopWatchdog() {
        watchdog?.cancel()
        watchdog = nil
    }

    func approve(_ cardID: UUID) {
        guard state.cards.first(where: { $0.id == cardID })?.approvalFingerprint != nil else { return }
        guard state.approve(cardID: cardID) else { return }
        Task { [weak self] in
            await self?.applyApproved(cardID: cardID)
        }
    }

    /// 正在兑现的卡片（防同一张卡被「点了」与「代签」两条路各写一遍）。
    private var inFlightApply: Set<UUID> = []

    /// 兑现一张**已批但还没落地**的卡片（`FR-AI-31` ① 的落地那一格）。
    ///
    /// · **幂等**：同一张卡在途就跳过（重复事件不写第二遍）；
    /// · **失败如实说**：宿主没接 / 没写成就报 `noApplier` / `applyFailed`，卡片停在「已批」——
    ///   绝不改成「已应用」而盘上没动。
    private func applyApproved(cardID: UUID) async {
        guard !inFlightApply.contains(cardID) else { return }
        guard let card = state.cards.first(where: { $0.id == cardID }), card.isAwaitingApply else { return }
        guard let applyApproval else {
            state.appendNotice("noApplier")
            return
        }
        inFlightApply.insert(cardID)
        let result = await applyApproval(card)
        inFlightApply.remove(cardID)
        switch result {
        case .success:
            state.markApplied(cardID: cardID)
        case .failure(let code):
            // **原因原样报出来**：写冲突 / 基线过期 / 写盘失败不是一句话。
            state.appendNotice(code)
        }
    }

    func deny(_ cardID: UUID) {
        _ = state.deny(cardID: cardID)
    }

    /// **一步撤销**（`FR-AI-25` ⑤）：把这张卡片已经落盘的改动退回去。
    ///
    /// 三处纪律：
    /// · 只从「已应用」出发（`state.canUndo`）—— 别的状态点它没有意义，直接不响应；
    /// · 撤不了就**如实说为什么**（`undoFailed` / `undoDrifted`），卡片留在「已应用」，
    ///   绝不把卡片改成「已撤销」而文件其实没回去；
    /// · 宿主没接这条 ⇒ 如实报 `noUndoer`（与 `noApplier` 同一条规矩：不假装撤了）。
    func undo(_ cardID: UUID) {
        guard state.canUndo(cardID: cardID),
              let card = state.cards.first(where: { $0.id == cardID }) else { return }
        guard let undoApplied else {
            state.appendNotice("noUndoer")
            return
        }
        Task { [weak self] in
            let result = await undoApplied(card)
            await MainActor.run {
                guard let self else { return }
                switch result {
                case .success:
                    self.state.markUndone(cardID: cardID)
                case .failure(let code):
                    // 失败原因**机器码**（`drifted` = 应用之后文件又被改过），人话在界面翻。
                    self.state.appendNotice(code)
                }
            }
        }
    }

    /// 撤销的结局。用结果类型而不是 `Bool`：撤销失败有两种**处置不同**的原因
    /// （`drifted` = 文件被又改过 ⇒ 人要先看清正文；`failed` = 写盘出错 ⇒ 可以原样重试），
    /// 一个 `false` 会把这两件事压成同一句「撤不了」。
    enum UndoResult: Equatable {
        case success
        case failure(String)
    }

    /// 兑现一次的结局（`FR-AI-31` ①）：成功 / 失败（**机器码**，人话在界面翻）。
    enum ApplyResult: Equatable {
        case success
        case failure(String)
    }

    func toggle(_ cardID: UUID) {
        state.toggleExpanded(cardID: cardID)
    }

    // MARK: - 循环进度

    func observe(_ event: AgentLoopEvent) async {
        state.apply(event)
        // **代签那一档（`FR-AI-34`）建单即已批** ⇒ 观测口立刻兑现。
        // `observe` 在循环里是 `await` 的 ⇒ 这次写盘落在**下一跳之前**，
        // 模型下一跳看到的是「文件已改」，而不是「还在等一个不会来的人」。
        if case .approvalRequested = event {
            for card in state.cards where card.isAwaitingApply {
                await applyApproved(cardID: card.id)
            }
        }
    }

    private func finish(_ result: AgentLoopResult) {
        stopWatchdog()
        state.finishRun()
        drainQueue()
        // 用量并进会话账（缺值不当 0 累加 —— 与 CLI 侧同一口径）。
        // **缓存读数一并记**（`FR-AI-25` 第二格）：端点没报 ⇒ `nil`，账上不算一次「命中率读数」。
        sessionUsage.add(prompt: result.usage.promptTokens,
                         completion: result.usage.completionTokens,
                         cached: result.usage.cachedPromptTokens)
        if let prompt = result.usage.promptTokens { lastPromptTokens = prompt }
        // **配额回写**（`NFR-AI-04`）：这一轮跳级累加过的账本交回宿主，跨轮才累计得起来
        //（不回写 ⇒ 每个上限在真实路径上都永远不会触发，正是 v3.88 修掉的那条第 1 项缺口）。
        if let ledger = result.quotaLedger { recordQuotaLedger?(ledger) }
        switch result.outcome {
        case .finished:
            state.appendNotice("finished")
        case .failed(let reason):
            // 连不上就**如实说连不上**（下一轮界面据此拦住输入，不假装在跑）。
            state.setEndpoint(.unreachable(reason))
        case .stopped:
            break   // 停止那一档：循环已经发过 `stopped` 事件，这里不重复报。
        }
    }

    /// 把队列里的下一条接着跑起来。
    ///
    /// 只在**真的空闲**时才起：`finish` 之外也可能有人手动改状态，
    /// 起早了会和还没落地的这一轮撞在一起。
    private func drainQueue() {
        guard !state.isRunning, let next = queue.dequeue() else { return }
        Task { await start(prompt: next.text, intent: .newQuestion) }
    }
}
