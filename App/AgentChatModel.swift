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
    /// 造循环。**是 `async` 的**：建循环时要现取一次本次上下文（`FR-AI-22`：当前连接的表结构摘要等），那一步是 IO。
    var makeLoop: ((String, any AgentLoopObserver) async -> (loop: AgentLoop, context: AgentLoopContext)?)?
    /// 宿主注入：真正把一次批准**兑现**（写盘 / 跑命令）。返回是否成功。
    var applyApproval: ((AgentToolCard) async -> Bool)?
    /// 宿主注入：端点状态（界面出现 / 设置改过之后取一次）。
    var endpointProvider: () -> AgentChatEndpointState = { .notConfigured }

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
        state.beginRun(prompt: prompt)
        guard state.isRunning else { return }   // 不能发时 `beginRun` 已如实出提示，这里不许往下走
        input = ""
        cancellation.reset()
        guard let prepared = await makeLoop?(prompt, self) else {
            state.apply(.failed("loopUnavailable"))
            return
        }
        task = Task { [weak self] in
            let result = await prepared.loop.run(context: prepared.context,
                                                 isCancelled: { [cancellation] in cancellation.isSet })
            await MainActor.run { self?.finish(result) }
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

    func toggle(_ cardID: UUID) {
        state.toggleExpanded(cardID: cardID)
    }

    // MARK: - 循环进度

    func observe(_ event: AgentLoopEvent) async {
        state.apply(event)
    }

    private func finish(_ result: AgentLoopResult) {
        state.finishRun()
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
