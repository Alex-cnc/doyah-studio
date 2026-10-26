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
    @Published var input = "" {
        didSet { refreshSlashSuggestions() }
    }

    /// 斜杠命令候选（`FR-AGT-UX-CONV-014` 输入侧）：只在「敲命令名」这一段有，进了参数区就空。
    /// 纯 Core 判定（`AgentSlashCompleter`），这里只负责跟着输入刷新与填字。
    @Published private(set) var slashSuggestions: [AgentSlashSuggestion] = []

    private let slashCompleter = AgentSlashCompleter()

    /// 选一条候选：把插入文本写进输入框（`/model ` 带尾随空格，省一次敲键）；候选随之收掉。
    func applySlashSuggestion(_ suggestion: AgentSlashSuggestion) {
        input = suggestion.insertion
    }

    private func refreshSlashSuggestions() {
        let next = slashCompleter.suggestions(for: input)
        if next != slashSuggestions { slashSuggestions = next }
    }

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

    /// 宿主注入：把**一条**审计记录落到审计面（与工具调用、模型调用同一条追加通道 —— 不另开日志文件）。
    /// 不接 ⇒ 命令照旧在本机做完，但审计那一行写不进去；界面会另外如实说一句（不静默）。
    var auditSink: ((AgentActionRecord) async -> Void)?
    /// 宿主注入：把一条**已批准**的配置变更真的落进配置。
    /// 返回 `false` = 本版还没有这条落地入口（`/model` 就属于这一档）—— 如实说，不假装改过。
    var applyConfigChange: ((AgentSlashCommandKind, String) -> Bool)?

    // MARK: - 主动通知 / 求助卡 / 门控重发（`FR-AGT-UX-CONV-008` · `-009` · `FR-AGT-GUARD-COST-001`）

    /// 宿主注入：把一条**系统通知**发出去（macOS 走 `UserNotifications`）。
    ///
    /// 不接 ⇒ **页内提示条照出**：发不出系统通知不代表这件事不该被看见，
    /// 两个出口是「与」不是「或」的替代关系（缺一个照样有话要说）。
    var notifySink: ((AgentNotification) -> Void)?
    /// 宿主注入：人此刻是否正看着这一页（前台 + 当前页签）。
    /// 缺省 `true` = **保守**：没接这一格就当人正在看 ⇒ 不弹系统通知（宁少弹，不乱弹）。
    var paneIsVisible: () -> Bool = { true }
    /// 通知门槛。**阈值只有一处**（`Core/AgentNotifyPolicy`），这里只放实例。
    var notifyPolicy = AgentNotifyPolicy()
    /// 系统通知开关（`FR-AGT-OPS-OBS-002` 的「通知规则」）：宿主从运行策略里现读，
    /// **每轮都读**，所以面板上关掉立刻生效（不必重启）。缺省开着。
    var systemNotificationsEnabledProvider: () -> Bool = { true }
    /// 日配额判定（宿主注入；`nil` = 没接 ⇒ 不拦，如实意味着「这条路上还没有配额面」）。
    var dailyQuotaCheck: (() -> AgentDailyUsageLedger.Verdict?)?
    /// 记当日用量（宿主注入）。记账是旁路：写不进去也不该让这一轮失败。
    var dailyUsageRecorder: ((Int) -> Void)?
    /// 文案语言（界面语言，缺省跟随本机语言设置）。
    var languageProvider: () -> AppLanguage = { LocalizationManager.shared.effectiveLanguage }
    /// **显示开关的真值源**（`FR-AGT-UX-CONV-012`）：宿主每次现读 ⇒ 面板上改一项，
    /// 下一次按发送 / 下一次重绘就按新的来（不必重启）。缺省 = 契约默认那一份。
    var displayPreferencesProvider: () -> AgentDisplayPreferences = { AgentDisplayPreferences() }

    /// 页内提示条（通知那一格的**可见**出口；`nil` = 没有要说的）。
    @Published private(set) var notifyBanner: AgentNotification?
    /// 求助卡（`FR-AGT-UX-CONV-009`）：需人处理 / 缺装配 / 缺点端才出，其余 `nil`。
    @Published private(set) var helpRequest: AgentHelpRequest?
    /// 被门控挡下的那一次（`FR-AGT-GUARD-COST-001`）—— 留着提示词与原由，等「仍然发送」或「不用了」。
    @Published private(set) var gateRecall: AgentGateRecall?

    /// 收起提示条（只收起这一条，不改任何状态）。
    func dismissNotifyBanner() { notifyBanner = nil }

    /// 收起求助卡（人已经看到了；**不代表那件事已经办完**）。
    func dismissHelpRequest() { helpRequest = nil }

    /// 放弃强发（「不用了」）：被挡下的那一跳本来就没发请求，放弃 = 什么都不用撤。
    func dismissGateRecall() { gateRecall = nil }

    /// **仍然发送**（`FR-AGT-GUARD-COST-001`）：用被挡下那一刻的提示词与触发强发一次。
    ///
    /// 三条边界：
    /// · 走的是**同一个提示词**（`AgentGateRecall.prompt`），不读输入框 —— 输入框这时候可能已被改过；
    /// · 门控这一次不看历史（`forcedProceed`），并且照常记账（否则下一次同样问法立刻又被挡）；
    /// · 强发**不改任何其他设置**：审批 / 事故闸门 / 配额一个都不绕过（门控只管「要不要问模型」）。
    func forceSend() async {
        guard let recall = gateRecall else { return }
        gateRecall = nil
        // 先记账（`forcedProceed` 恒放行 + 更新「上一次问过什么」），再带 `ignoringGate` 真发 ——
        // 两步都要：只记账不发 = 按钮没反应；只发不记账 = 下一次同样问法立刻又被挡。
        _ = gate.forcedProceed(recall)
        await start(prompt: recall.prompt, intent: .newQuestion, ignoringGate: true)
    }


    /// 正在跑的那一个循环（`/steer` 要把话插进它的干预信箱；没在跑就是 `nil`）。
    private var runningLoop: AgentLoop?
    /// 当前进行到第几跳（observer 的 `hopStarted` 给数）—— `/steer` 用它算「当前步做完生效」。
    private var currentHop = 0
    /// `/queue` 排下的内容：本轮结束后按序发出，不打断当前回合。
    private var queuedPrompts: [String] = []

    /// 斜杠命令的「解析 → 要做什么」纯函数（`FR-AGT-UX-CONV-014`）。
    private let slashRuntime = AgentSlashCommandRuntime()
    /// 一条待批的配置变更（`/model` `/theme`）。`nil` = 没有在等审批的单。
    @Published private(set) var pendingSlashChange: AgentSlashPendingChange?

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

    /// 跨启动续跑提示（`nil` = 不做续跑恢复）。
    ///
    /// 为什么不塞进会话文件：会话文件是**留痕**（只追加、供回看），续跑提示是**状态**
    /// （覆盖写、末次为准、随时可清）—— 两种写入语义混一份迟早互相踩。
    var resumeStore: AgentTurnResumeStore?

    /// 当前活动工作区（续跑提示要按工作区校验身份；`nil` = 还不知道，不写盘）。
    private var activeWorkspacePath: String?

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

    /// **有没有一张在等人点的审批卡**（§5.3.8 六态「权限不足」那一档）。
    ///
    /// 有它的时候输入框要禁用：审批没过，这一轮就停在原地 —— 再塞一句进去只会排队，
    /// 而「先发后问」正是这条契约明令禁止的形状。
    var hasPendingApproval: Bool {
        state.cards.contains { card in
            if case .pendingApproval = card.outcome { return true }
            return false
        }
    }

    /// **再试一次**（§5.3.8 六态「错误」那一档的可重试入口）：拿上一轮的原话重跑一轮。
    ///
    /// 与「重发」的区别：那个以**某条助手消息**为锚（历史里点哪条重发哪条），
    /// 这个是「刚才那一轮没跑成」的直接续命 —— 没有原话（还没问过）就什么都不做，
    /// **不拿输入框里现有的字凑数**（那不是他刚才问的那句）。
    func retryLastTurn() async {
        guard !state.isRunning, let prompt = lastPrompt else { return }
        await start(prompt: prompt, intent: .newQuestion)
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
        // **斜杠命令在本地做完，不进模型**（`FR-AGT-UX-CONV-014`）。
        //
        // 为什么要抢在「排队」之前：命令不是提问，排进队列会被当成人话发给模型 ——
        // 那正是「本地执行不进模型」要禁掉的那件事。命令也不清队列、不打断在跑的那一轮
        // （`/stop` 才是打断，且它自己走 `stop()`）。
        if let effect = slashRuntime.plan(prompt) {
            input = ""
            await perform(effect)
            return
        }
        // **一轮还在跑时提交的提问不丢**：排进队列，这一轮结束后按序接着跑
        // （Hermes CLI 的 `/queue` 同义；这里用界面表达，不要求用户记斜杠命令）。
        //
        // 两种处置由显示开关「运行中提交」定（`FR-AGT-UX-CONV-012` ⑨）：
        // · **打断（契约默认）= 先停后发**：先把在跑的这一轮停掉，这条排进队列 ——
        //   停稳之后 `finish` 会 `drainQueue` 把它接着跑起来；
        // · **排队**：不动在跑的那一轮，只把这条排进去。
        // 两条路**都进队列**（提问不许因为「正在跑」被吞掉），差别只在要不要先停。
        if state.isRunning {
            guard queue.enqueue(prompt) != nil else { return }
            if AgentDisplayProjection.abortsInFlightBeforeSending(displayPreferencesProvider()) {
                stop()
            }
            input = ""
            return
        }
        await start(prompt: prompt, intent: .newQuestion)
    }

    // MARK: - 斜杠命令的落地（`FR-AGT-UX-CONV-014` / `FR-AGT-UX-CONV-015`）

    /// 把一条 effect 落成界面动作 + **一行**审计。
    ///
    /// 三条纪律：
    /// · **不构造模型请求**（没有 `makeLoop`、没有 `gate`、没有 token）；
    /// · **改配置的命令只出单**：`/model` `/theme` 一律落到 `pendingSlashChange` 等人工批准，
    ///   命令自己不许碰配置（`CONV-015`）；批准之后才由宿主注入的 `applyConfigChange` 落地；
    /// · 审计**一条命令一条记录**，结局按事实写：做成 `.executed`、等审批 `.pendingApproval`、
    ///   拒收 `.denied`、做不到 `.failed`（`/compact` 这一版没有手动触发点，就写 `.failed` 并附原因）。
    private func perform(_ effect: AgentSlashCommandEffect) async {
        switch effect {
        case let .help(lines):
            state.appendNotice(lines.joined(separator: "\n"))
            await writeSlashAudit(effect, outcome: .executed)

        case .clearContext:
            // **盘上的会话文件不动**（留痕只追加，回看得到）；清的是往后要带进提示词的上下文。
            state.clearTranscript()
            resetForReplay()
            state.appendNotice(L(.agentSlashCleared))
            await writeSlashAudit(effect, outcome: .executed)

        case .compactContext:
            // 压缩本身在 `AgentLoop` 的请求边界上按预算自动发生（`AgentContextCompressionBudget`）；
            // 本版**没有**手动触发点 —— 如实说，不假装压过。
            state.appendNotice(L(.agentSlashCompactNoTrigger))
            await writeSlashAudit(effect, outcome: .failed, detail: "noManualTrigger")

        case let .searchSessions(query):
            // 会话列表按工作区读一次（每敲一句就扫盘是浪费；这里是显式命令，扫一次合理）。
            reloadSessions(workspacePath: activeWorkspacePath)
            let needle = query.lowercased()
            let hits = sessions.filter { $0.title.lowercased().contains(needle) }
            state.appendNotice(L(.agentSlashSearch, query, hits.count))
            await writeSlashAudit(effect, outcome: .executed, detail: "hits=\(hits.count)")

        case .stopRun:
            if state.isRunning {
                stop()
                state.appendNotice(L(.agentSlashStopRequested))
                await writeSlashAudit(effect, outcome: .executed)
            } else {
                // 没在跑也如实说：不假装停过（停了什么也没停）。
                state.appendNotice(L(.agentSlashStopNotRunning))
                await writeSlashAudit(effect, outcome: .denied, detail: "notRunning")
            }

        case let .steerRun(instruction):
            // 插话落在**干预信箱**上（`AgentIntervention.redirect`）：当前步做完生效，
            // 不清空已产生的中间结果。没在跑就如实说「无处可插」，不留一条假审计。
            if let loop = runningLoop, let inbox = loop.interventionInbox {
                inbox.enqueue(.redirect(instruction: instruction), duringStep: currentHop)
                state.appendNotice("已插话：当前这一步做完后按新指令走")
                await writeSlashAudit(effect, outcome: .executed, detail: "step=\(currentHop)")
            } else {
                state.appendNotice("现在没有在跑的一轮，插话无处可去（要开新话题直接发消息）")
                await writeSlashAudit(effect, outcome: .denied, detail: "notRunning")
            }

        case let .queuePrompt(text):
            // 排队：**不打断本轮**，本轮结束后按序发出。
            queuedPrompts.append(text)
            state.appendNotice("已排队（第 \(queuedPrompts.count) 条）：本轮结束后依次发出")
            await writeSlashAudit(effect, outcome: .executed, detail: "queued=\(queuedPrompts.count)")

        case let .configChange(kind, argument):
            // 出单（待批），**不落地**。审计那一行随单一起写（`pendingApproval`）——
            // 批准 / 拒绝的时候再各写一条终态，与工具审批同一条留痕口径。
            let record = slashRuntime.auditRecord(for: effect, outcome: .pendingApproval, sessionID: sessionID)
            let approval = AgentApproval(record: record, state: .pending)
            pendingSlashChange = AgentSlashPendingChange(effect: effect, approval: approval)
            state.appendNotice(L(.agentSlashPendingApproval, kind.rawValue, argument))
            await writeRecord(record)

        case let .rejected(command):
            // 不认识的命令 / 缺参数：把**原命令**说清楚（`auditLine` 是单行的机器形态）。
            state.appendNotice(L(.agentSlashRejected, command.auditLine))
            await writeSlashAudit(effect, outcome: .denied, detail: "rejected")
        }
    }

    /// 批准一条待批的配置变更（界面那两个按钮的「批准」）。
    func approveSlashChange() async {
        guard var change = pendingSlashChange else { return }
        do {
            try change.approval.approve(by: NSUserName())
        } catch {
            // 非法流转（已经被处理过 / 已失效）不猜、不硬改，照实报。
            state.appendNotice(ErrorPresenter.message(for: error))
            return
        }
        pendingSlashChange = nil
        // **先落审计，再动配置**（与工具审批同一顺序）：写不进日志就不改配置。
        guard await writeRecord(change.approval.record) else {
            state.appendNotice(L(.agentSlashAuditUnavailable, change.auditLine))
            return
        }
        let applied = applyConfigChange?(change.kind, change.argument) ?? false
        if applied {
            state.appendNotice(L(.agentSlashApproved, change.auditLine))
            await writeSlashAudit(.configChange(kind: change.kind, argument: change.argument),
                                  outcome: .executed, detail: "applied")
        } else {
            // 批准了但**没有落地入口**（本版 `/model` 就属这一档）—— 如实说，不假装改过。
            state.appendNotice(L(.agentSlashApplyUnavailable, change.auditLine))
            await writeSlashAudit(.configChange(kind: change.kind, argument: change.argument),
                                  outcome: .failed, detail: "noApplier")
        }
    }

    /// 拒绝一条待批的配置变更。
    func rejectSlashChange() async {
        guard var change = pendingSlashChange else { return }
        do {
            try change.approval.reject(by: NSUserName())
        } catch {
            state.appendNotice(ErrorPresenter.message(for: error))
            return
        }
        pendingSlashChange = nil
        _ = await writeRecord(change.approval.record)
        state.appendNotice(L(.agentSlashRejectedChange, change.auditLine))
    }

    /// 写一条斜杠命令的审计（一条命令一条）。
    private func writeSlashAudit(_ effect: AgentSlashCommandEffect,
                                 outcome: AgentActionRecord.Outcome,
                                 detail: String? = nil) async {
        var record = slashRuntime.auditRecord(for: effect, outcome: outcome, sessionID: sessionID)
        if let detail { record.detail = detail }
        _ = await writeRecord(record)
    }

    /// 交给宿主写审计。`false` = 没接审计面或写失败（调用方据此决定要不要如实说一句）。
    @discardableResult
    private func writeRecord(_ record: AgentActionRecord) async -> Bool {
        guard let auditSink else { return false }
        await auditSink(record)
        return true
    }

    /// 撤掉一条排队中的提问（界面上那个 `✕`）。
    func removeQueued(id: UUID) {
        queue.remove(id: id)
    }

    /// 调一条排队提问的位置（`offset` = -1 上移 / +1 下移；越界夹紧）。
    func moveQueued(id: UUID, offset: Int) {
        queue = queue.moving(id: id, offset: offset)
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
        activeWorkspacePath = workspacePath
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
        activeWorkspacePath = workspacePath
        // **跨启动续跑**（`FR-AGT-CORE-SESS-001` ①）：把上一轮的提问与落账填回去，
        // 「继续上次」在重启之后照样出现；拿不到就当没有（不回退成假装能续）。
        if case let .found(hint) = resumeStore?.load(sessionID: session.header.id, workspace: workspacePath) ?? .absent {
            lastPrompt = hint.prompt
            lastTurn = hint.record
        }
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

    // MARK: - 会话生命周期（`FR-AGT-UX-SESS-001` 界面接线）

    /// 归档面列表（打开列表时与活跃面一起刷）。
    @Published private(set) var archivedSessions: [AgentSessionSummary] = []
    /// 归档面读不出来的文件数（与活跃面同一口径：跳过并计数）。
    @Published private(set) var archivedSkippedFiles = 0
    /// 上一个生命周期动作的**一句结论**（成功也说话、被拒也说清为什么）。
    @Published private(set) var sessionLifecycleLine: String?

    /// 界面侧唯一入口（`Core/AgentSessionLifecycleDesk`）：工作区与续跑旁挂件目录都在这里固定，
    /// 视图那侧没有机会漏传（漏传的后果是「删了会话、磁盘上还留着续跑件」）。
    private func lifecycleDesk(workspacePath: String?) -> AgentSessionLifecycleDesk? {
        guard let store = sessionStore, let workspacePath, !workspacePath.isEmpty else { return nil }
        // 旁挂件与会话同目录（生产路径由 `DoyahStudioApp` 一起接到 `defaultDirectory`）；
        // `resumeStore` 没接时退回会话目录 —— 那是它该在的地方，不是「猜一个位置」。
        let sidecar = resumeStore?.directory ?? store.directory
        return AgentSessionLifecycleDesk(store: store, workspace: workspacePath, sidecarDirectories: [sidecar])
    }

    private func requireDesk(_ workspacePath: String?) -> AgentSessionLifecycleDesk? {
        guard let desk = lifecycleDesk(workspacePath: workspacePath) else {
            sessionLifecycleLine = L(.agentChatSessionLifecycleUnavailable)
            return nil
        }
        return desk
    }

    /// 刷两个面（活跃 + 归档）：一次动作之后两个列表都可能变，只刷一个会留下「刚归档的还在」。
    private func refreshAfterLifecycle(workspacePath: String?) {
        reloadSessions(workspacePath: workspacePath)
        reloadArchivedSessions(workspacePath: workspacePath)
    }

    /// 归档面刷新（打开列表时调；归档 / 恢复之后也调）。
    func reloadArchivedSessions(workspacePath: String?) {
        guard let desk = lifecycleDesk(workspacePath: workspacePath) else {
            archivedSessions = []
            archivedSkippedFiles = 0
            return
        }
        let result = desk.archivedSummaries()
        archivedSessions = result.summaries
        archivedSkippedFiles = result.skippedFiles
    }

    /// 归档（①）：挪进归档面，列表里立刻看不见。
    func archiveSession(_ id: String, workspacePath: String?) {
        guard let desk = requireDesk(workspacePath) else { return }
        do {
            let outcome = try desk.archive(sessionID: id)
            sessionLifecycleLine = outcome.changed ? L(.agentChatSessionArchived)
                                                   : L(.agentChatSessionArchiveNoop)
            refreshAfterLifecycle(workspacePath: workspacePath)
        } catch {
            sessionLifecycleLine = L(.agentChatSessionLifecycleFailed, Self.lifecycleReason(error))
        }
    }

    /// 从归档面恢复（①）。
    func restoreSession(_ id: String, workspacePath: String?) {
        guard let desk = requireDesk(workspacePath) else { return }
        do {
            let outcome = try desk.restore(sessionID: id)
            sessionLifecycleLine = outcome.changed ? L(.agentChatSessionRestored)
                                                   : L(.agentChatSessionRestoreNoop)
            refreshAfterLifecycle(workspacePath: workspacePath)
        } catch {
            sessionLifecycleLine = L(.agentChatSessionLifecycleFailed, Self.lifecycleReason(error))
        }
    }

    /// 真删（②）：活跃文件 + 归档副本 + 续跑旁挂件一起删。删的是当前这条 ⇒ 换一条新会话
    /// （否则界面上还挂着一条已经不存在的会话，下一跳会写回一个同名文件）。
    func deleteSession(_ id: String, workspacePath: String?) {
        guard let desk = requireDesk(workspacePath) else { return }
        do {
            let outcome = try desk.delete(sessionID: id)
            sessionLifecycleLine = L(.agentChatSessionDeleted, outcome.removedFileCount)
            if id == sessionID { startNewSession() }
            refreshAfterLifecycle(workspacePath: workspacePath)
        } catch {
            sessionLifecycleLine = L(.agentChatSessionLifecycleFailed, Self.lifecycleReason(error))
        }
    }

    /// 导出（③）：**只产出数据**，落哪个目录由界面的保存面板决定。
    /// 返回（建议文件名, 数据）；出错则把理由写进那一行并回 `nil`。
    ///
    /// **不在这里报「已导出」** —— 用户可能紧接着在保存面板上按取消，
    /// 那时说「已导出」就是在撒谎。结论由 `writeExportedSession` 在真写完之后给。
    func exportSessionData(_ id: String, workspacePath: String?) -> (fileName: String, data: Data)? {
        guard let desk = requireDesk(workspacePath) else { return nil }
        do {
            let exported = try desk.export(sessionID: id)
            let title = sessions.first { $0.id == id }?.title ?? archivedSessions.first { $0.id == id }?.title ?? id
            return (AgentChatSessionFileName.suggested(title: title, sessionID: id), exported.data)
        } catch {
            sessionLifecycleLine = L(.agentChatSessionLifecycleFailed, Self.lifecycleReason(error))
            return nil
        }
    }

    /// 把导出数据写到用户选的位置（写失败也进**同一行**结论 —— 界面不再自己拼错误文案）。
    func writeExportedSession(_ payload: (fileName: String, data: Data), to url: URL) {
        do {
            try payload.data.write(to: url, options: .atomic)
            sessionLifecycleLine = L(.agentChatSessionExported, payload.data.count)
        } catch {
            sessionLifecycleLine = L(.agentChatSessionLifecycleFailed, ErrorPresenter.message(for: error))
        }
    }

    /// 重新导入（③）：落进**当前工作区**；同名会话号默认拒收（不静默覆盖别人那份）。
    ///
    /// 界面对「带走的导出文件」用 `.assignNewID`（那是「换台机器接着用」的正常心意），
    /// 撞名时给新号并把新号报出来 —— 不许悄悄覆盖已有那条。
    func importSessionData(_ data: Data, workspacePath: String?) {
        guard let desk = requireDesk(workspacePath) else { return }
        do {
            let receipt = try desk.importSession(data, conflict: .assignNewID)
            sessionLifecycleLine = L(.agentChatSessionImported, receipt.header.title)
            refreshAfterLifecycle(workspacePath: workspacePath)
        } catch {
            sessionLifecycleLine = L(.agentChatSessionLifecycleFailed, Self.lifecycleReason(error))
        }
    }

    /// 生命周期错误的**人话**（四个机器码各有各的说法；认不出的原样报码，不编）。
    static func lifecycleReason(_ error: Error) -> String {
        guard let failure = error as? AgentSessionLifecycleError else {
            return ErrorPresenter.message(for: error)
        }
        switch failure {
        case .sessionNotFound: return L(.agentChatSessionNotFound)
        case .workspaceMismatch: return L(.agentChatSessionOtherWorkspace)
        case .conflictingSessionExists: return L(.agentChatSessionNameConflict)
        case .malformedPayload: return L(.agentChatSessionBadExportFile)
        }
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

    private func start(prompt: String, intent: AgentTurnIntent, ignoringGate: Bool = false) async {
        // **日配额闸**（`FR-AGT-OPS-OBS-002` 的「改完立即生效」之一）：额度用完就不再发请求。
        // 拦在「人按下发送」与「真的发出去」之间，并且**说清是哪两个数**（用掉多少 / 上限多少）——
        // 只回一句「超限」用户没法判断该调上限还是等明天。
        if let verdict = dailyQuotaCheck?(), case let .exhausted(used, quota) = verdict {
            state.appendNotice(L(.agentChatDailyQuotaExhausted, used, quota))
            return
        }
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
        // 新的一轮开始 ⇒ 上一轮的提示条与求助卡收起来（它们说的都是上一轮的事）。
        notifyBanner = nil
        helpRequest = nil
        startWatchdog()
        guard let prepared = await makeLoop?(prompt, plan, self) else {
            stopWatchdog()
            state.apply(.failed("loopUnavailable"))
            // 求助卡（`FR-AGT-UX-CONV-009`）：这一轮**连循环都没造出来** —— 缺的是装配，
            // 不是网络。**如实要人办一件事**（要什么 / 为什么 / 给完从哪接），而不是只说一句失败。
            helpRequest = AgentHelpCatalogue.missingLoop(language: languageProvider())
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
        let decision = (ignoringGate || intent == .continueLast)
            ? gate.decide(trigger, ignoringHistory: true)
            : gate.decide(trigger)
        switch decision {
        case .skipped(let reason):
            gate.record(.skipped(reason: reason), for: trigger)
            state.apply(.failed(reason))       // 如实说"为什么没发"，不静默；**输入框不清空**（用户改一个字就能再发）
            // 「仍然发送」（`FR-AGT-GUARD-COST-001`）：留住**这一次真的要发的**提示词 + 触发 +
            // 理由 —— 界面上那一行按钮按的就是这一份，不读输入框（它可能已被改过）。
            gateRecall = AgentGateRecall(prompt: prompt, reason: reason, trigger: trigger)
            return
        case .proceed:
            gate.record(.proceed, for: trigger)
            gateRecall = nil
        }
        if intent == .newQuestion { input = "" }
        lastPrompt = prompt
        let started = Date()
        task = Task { [weak self] in
            runningLoop = prepared.loop
            defer { runningLoop = nil }
            let result = await prepared.loop.run(context: prepared.context,
                                                 requestedStep: plan.requestedStep,
                                                 isCancelled: { [cancellation] in cancellation.isSet })
            await MainActor.run {
                guard let self else { return }
                self.lastElapsedSeconds = Date().timeIntervalSince(started)
                // 记这一轮的账：下一轮能不能续、从第几跳续，看的就是它。
                let record = AgentTurnPlanner.record(turn: plan.turn, result: result)
                self.lastTurn = record
                // 落盘（重启后 `openSession` 读回）：写失败只影响「重启后续跑」，不影响这一轮结论。
                if let store = self.resumeStore, let workspace = self.activeWorkspacePath {
                    let hint = AgentTurnResumeHint(sessionID: self.sessionID, workspace: workspace,
                                                   prompt: prompt, record: record)
                    do { try store.save(hint) } catch { self.state.appendNotice("sessionUnavailable") }
                }
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
        if case let .hopStarted(index) = event { currentHop = index }
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
        // **日配额记账**（`FR-AGT-OPS-OBS-002`）：这一轮真花掉的 token 进当日账。
        // 只算这一轮的增量（不是会话累计）—— 日配额按「今天花了多少」算，不是「这条会话花了多少」。
        let turnTokens = (result.usage.promptTokens ?? 0) + (result.usage.completionTokens ?? 0)
        if turnTokens > 0 { dailyUsageRecorder?(turnTokens) }
        switch result.outcome {
        case .finished:
            state.appendNotice("finished")
        case .failed(let reason):
            // 连不上就**如实说连不上**（下一轮界面据此拦住输入，不假装在跑）。
            state.setEndpoint(.unreachable(reason))
        case .stopped:
            break   // 停止那一档：循环已经发过 `stopped` 事件，这里不重复报。
        }

        // `/queue`：本轮收尾后按序发下一条（不打断、不丢；发完队列清空）。
        if !queuedPrompts.isEmpty {
            let next = queuedPrompts.removeFirst()
            state.appendNotice("队列里的下一条已发出（还剩 \(queuedPrompts.count) 条）")
            // `finish` 不是 async（它在状态收尾里）⇒ 起一个任务去发下一条，不在这里阻塞收尾。
            Task { @MainActor [weak self] in
                await self?.start(prompt: next, intent: .newQuestion)
            }
            return
        }

        // **主动通知**（`FR-AGT-UX-CONV-008`）：长任务做完 / 出错 / 要人决定才叫人。
        //
        // 两处出口一次算齐（`AgentNotifyPolicy.plan`）：页内提示条永远先出（人在这页也看得见），
        // 系统通知按「他是不是正看着这一页」判 —— 缺 `notifySink` 只是少了系统那一格，
        // 不许因此把页内那一格也省掉。
        let elapsed = Int((lastElapsedSeconds ?? 0).rounded())
        let reason: AgentNotifyReason?
        switch result.outcome {
        case .finished:
            reason = .longTaskFinished(elapsedSeconds: elapsed)
        case .failed(let detail):
            // 人自己按的「停止」不叫人（他知道发生了什么，再弹一次是骚扰）。
            reason = detail == "cancelled" ? nil : .failed(summary: detail)
        case .stopped:
            reason = nil
        }
        if let reason {
            let plan = notifyPolicy.plan(reason,
                                        userIsLookingAtThisPane: paneIsVisible(),
                                        userIsIdle: false,
                                        systemNotificationsEnabled: systemNotificationsEnabledProvider(),
                                        language: languageProvider())
            if let banner = plan.banner { notifyBanner = banner }
            if let system = plan.system { notifySink?(system) }
        }
        // **求助卡**（`FR-AGT-UX-CONV-009`）：只有「需人处理」那一档才出卡
        // （求助单由失败分级给，不是这里编的）；能自己好的失败不出卡，免得每次网络抖动都来要人办件事。
        if let help = result.failureHelp { helpRequest = help }
        // **交付前拦一道**（`FR-AGT-QUAL-VERIFY-004` ③）：结论指不到出处的不许当交付物。
        //
        // 挂在这一处而不是另开弹窗：页内提示条是人已经在看的那一屏（与主动通知同一个出口），
        // 拦下几条就点名几条 —— 拦了不说话，人会以为答案里本来只有这些。
        // 顺序有意放在通知之后：这段说的是**这段答案本身**能不能信，比「长任务跑完了」更该占屏。
        if let provenance = result.answerProvenance {
            let decision = AgentDeliverableDecision(provenance: provenance, language: languageProvider())
            if let notice = decision.notice(language: languageProvider()) { notifyBanner = notice }
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
