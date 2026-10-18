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
    var makeLoop: ((String, any AgentLoopObserver) async -> (loop: AgentLoop, context: AgentLoopContext)?)?
    /// 宿主注入：真正把一次批准**兑现**（写盘 / 跑命令）。返回是否成功。
    var applyApproval: ((AgentToolCard) async -> Bool)?
    /// 宿主注入：把一次**已经应用**的改动撤回去（`FR-AI-25` ⑤：一步撤销，文件逐字节回到应用前）。
    /// 撤销目标由宿主按卡片号从账上找 —— 这里只传卡片，不传「要写什么」：
    /// 原文只该存在一处（Core 的 `AgentEditJournal`），界面与视图模型都不许自己记一份。
    var undoApplied: ((AgentToolCard) async -> UndoResult)?
    /// 宿主注入：授权粒度（`FR-AI-34`）。缺省 = 任务范围内代签；设成 `.askEachAction` 就回到每个动作都问。
    var scopeProvider: () -> AgentTaskScope.Mode = { .taskScope }
    /// 宿主注入：端点状态（界面出现 / 设置改过之后取一次）。
    var endpointProvider: () -> AgentChatEndpointState = { .notConfigured }

    /// 本会话累计（**每次跑完把这一轮的用量并进来**）。两侧共用 `TokenUsageLedger`，口径同一个。
    @Published private(set) var sessionUsage = TokenUsageLedger()
    /// 上一轮跑完用了多少秒（`nil` = 还没跑过）。
    @Published private(set) var lastElapsedSeconds: Double?
    /// 端点读数（状态条那几格）。
    var endpointState: AgentChatEndpointState { state.endpoint }

    /// **上下文占用读数** = **上一次请求的输入 token**（端点自己报的那个数）。
    ///
    /// 为什么用「上次请求输入」而不是"会话累计"：会话累计是**花掉的总量**，上下文占用是**当前这一窗有多满** ——
    /// 两件事。Hermes 那格 `~227K/1M` 说的是后者。**百分比不给**：那要模型窗口大小，仓里没有这张表
    /// （如实登记，要加就在设置里补一格「上下文窗口」）。
    @Published private(set) var lastPromptTokens: Int?

    /// 当前动作（输入框上方那一行）。
    var currentAction: String? { state.currentAction }

    /// 会话标题（状态行最右）。
    var sessionTitle: String? { state.sessionTitle }

    /// **压缩读数**（`NFR-AI-08` ③）：界面上那一行「已压缩 N 段 · 省 ≈M token」。
    var contextCompression: AgentChatCompressionReading? { state.contextCompression }

    /// 吞吐（token/秒）：**只在这两样都有读数时给**，算不出来就不显示（不编）。
    var tokensPerSecond: Double? {
        guard let seconds = lastElapsedSeconds, seconds > 0.05, sessionUsage.completionTokens > 0 else { return nil }
        return Double(sessionUsage.completionTokens) / seconds
    }

    let sessionID: String
    private let cancellation = CancellationFlag()
    private var task: Task<Void, Never>?

    init(sessionID: String = "chat-\(UUID().uuidString)") {
        self.sessionID = sessionID
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

    func send() async {
        let prompt = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        // 授权粒度按设置走（**每次开跑前定一次**：本轮中途不换口径，免得一半问一半不问）。
        state.taskScope = AgentTaskScope(mode: scopeProvider())
        state.beginRun(prompt: prompt)
        guard state.isRunning else { return }   // 不能发时 `beginRun` 已如实出提示，这里不许往下走
        cancellation.reset()
        guard let prepared = await makeLoop?(prompt, self) else {
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
        let trigger = AgentGateTrigger(
            source: "chat",
            digest: AgentFingerprint.hash(prepared.context.systemPrompt + "\u{1}" + prepared.context.userPrompt),
            at: Date()
        )
        switch gate.decide(trigger) {
        case .skipped(let reason):
            gate.record(.skipped(reason: reason), for: trigger)
            state.apply(.failed(reason))       // 如实说"为什么没发"，不静默；**输入框不清空**（用户改一个字就能再发）
            return
        case .proceed:
            gate.record(.proceed, for: trigger)
        }
        input = ""
        let started = Date()
        task = Task { [weak self] in
            let result = await prepared.loop.run(context: prepared.context,
                                                 isCancelled: { [cancellation] in cancellation.isSet })
            await MainActor.run {
                self?.lastElapsedSeconds = Date().timeIntervalSince(started)
                self?.finish(result)
            }
        }
    }

    /// 取消：**在下一跳之前停**（循环口径），已产生的工具结果仍留痕。
    func stop() {
        cancellation.set()
    }

    func approve(_ cardID: UUID) {
        guard let card = state.cards.first(where: { $0.id == cardID }),
              let fingerprint = card.approvalFingerprint else { return }
        guard state.approve(cardID: cardID) else { return }
        guard let applyApproval else {
            state.appendNotice("noApplier")
            return
        }
        Task { [weak self] in
            let applied = await applyApproval(card)
            await MainActor.run {
                guard let self else { return }
                if applied {
                    self.state.markApplied(cardID: cardID)
                } else {
                    self.state.appendNotice("applyFailed")
                }
            }
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

    func toggle(_ cardID: UUID) {
        state.toggleExpanded(cardID: cardID)
    }

    // MARK: - 循环进度

    func observe(_ event: AgentLoopEvent) async {
        state.apply(event)
    }

    private func finish(_ result: AgentLoopResult) {
        state.finishRun()
        // 用量并进会话账（缺值不当 0 累加 —— 与 CLI 侧同一口径）。
        sessionUsage.add(prompt: result.usage.promptTokens, completion: result.usage.completionTokens)
        if let prompt = result.usage.promptTokens { lastPromptTokens = prompt }
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
}
