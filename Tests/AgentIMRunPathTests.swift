import AppKit
import XCTest
@testable import DoyahCore
@testable import DoyahStudioApp

/// **IM 通道跑一轮的判据**（`FR-AGT-LINK-CHAN-003` 后半）。
///
/// 2026-11-04 真机缺陷：主人从手机发消息，机器人回
/// 「Could not start this run: this run produced no answer. No result to report.」
///
/// 现场读数（`~/Library/Application Support/DoyahStudio/startup.log`）：
/// ```
/// 13:08:02 IM 收到消息 … 字数=7
/// 13:08:02 IM 跑一轮开始 chat=51F9D128… 会话=780B97A6…
/// 13:08:03 IM 跑一轮结束 result=unavailable(code: "noAnswer")   ← 1 秒
/// ```
/// 而 `egress-log.jsonl` 在 13:08 那一秒**没有任何 `agentModel` 请求** ⇒
/// 这一轮**根本没有发过模型请求**：不是「模型没答」，是**开跑前就被本地拦下**。
///
/// 拦在哪：`AgentChatModel.start` 里 `state.beginRun` 的 `guard canSend`
/// （`Core/AgentChat.swift:317`）。`state.endpoint` 只是一面**显示用的镜子**，
/// 唯一的刷新点是 `AgentChatView.onAppear`（`App/Views/AgentChatView.swift:54`）——
/// IM 从后台进来时面板视图可能从没出现过，镜子还是 `.notConfigured` ⇒ 拒跑 ⇒
/// 没有任何助手消息 ⇒ IM 那侧按「没结论」回话（`App/DoyahStudioApp.swift:304`）。
///
/// 所以这里判的是四条：
/// ① 手机派活**不依赖面板刷过**端点：这一轮必须真跑并答出来；
/// ② 真拦下时要说**真实原因**（端点没配 / 上一轮还在跑），不许一律 `noAnswer`；
/// ③ 上一轮还在跑时**不许偷偷排队**（排队等于手机那头等一句永远不会来的结论）；
/// ④ 跑完但没正文（工具轮）/ 真失败，各报各的，不混成一句。
final class AgentIMRunPathTests: XCTestCase {

    // MARK: - ① 不依赖面板的那一面镜子

    /// **缺陷现场复现**：端点真值可用，但**面板从没刷新过**（`refreshEndpoint()` 没被调过，
    /// 等于 App 一直在后台、对话页签没出现过）。修前：这一轮连跑都没跑；
    /// 修后：照跑，并答出正文。
    @MainActor
    func testIMRunAnswersEvenIfThePaneNeverRefreshedTheEndpoint() async {
        let model = AgentChatModel()
        model.endpointProvider = { .ready(model: "m", endpoint: "https://example.invalid") }
        // 故意不调 `model.refreshEndpoint()` —— 这就是真机上的样子。
        installAnsweringLoop(on: model)

        let outcome = await model.runFromIM(prompt: "查一下天气")
        XCTAssertEqual(outcome, .answered("看过了。"),
                       "手机派活不许依赖「面板视图刷过一次端点」这个副作用")
    }

    // MARK: - ② 拦下要说真原因

    @MainActor
    func testIMRunReportsTheRealReasonNotNoAnswer() async {
        let model = AgentChatModel()
        model.endpointProvider = { .notConfigured }
        installAnsweringLoop(on: model)

        let outcome = await model.runFromIM(prompt: "查一下天气")
        XCTAssertEqual(outcome, .refused(code: "endpointNotConfigured"),
                       "端点没配要说「端点没配」，不许报成「这一轮没有产出结论」")
    }

    // MARK: - ③ 跑着的时候不排队

    /// 上一轮还在跑：IM 那侧必须**如实说忙**，不许把这条塞进面板队列
    /// （塞进去 ⇒ 手机那头立刻收到一句「没结论」，而任务稍后却在桌面偷偷跑起来）。
    @MainActor
    func testIMRunRefusesInsteadOfQueueingBehindARunningTurn() async {
        let model = AgentChatModel()
        model.endpointProvider = { .ready(model: "m", endpoint: "https://example.invalid") }
        installAnsweringLoop(on: model, delayMilliseconds: 600)
        model.input = "桌面这一轮先跑着"
        await model.send()
        XCTAssertTrue(model.isRunning, "前提：桌面那一轮还在跑")

        let outcome = await model.runFromIM(prompt: "手机又来一句")
        XCTAssertEqual(outcome, .refused(code: "busy"), "跑着的时候手机派活要如实说忙，不许排队")
    }

    // MARK: - ④ 没正文 / 真失败各报各的

    /// 模型只回了个「结束」（没有正文）：这是**跑完了但没有结论**，
    /// 报 `noText`（人话：跑完了但没有可读正文），不是 `noAnswer`（那一句说的是「没跑起来」）。
    @MainActor
    func testIMRunReportsNoTextWhenTheTurnFinishedWithoutAVerdict() async {
        let model = AgentChatModel()
        model.endpointProvider = { .ready(model: "m", endpoint: "https://example.invalid") }
        installAnsweringLoop(on: model, client: SilentClient())

        let outcome = await model.runFromIM(prompt: "查一下天气")
        XCTAssertEqual(outcome, .noText(ranSteps: model.state.steps.count),
                       "跑完但没正文要如实报 noText")
    }

    /// 循环抛错（连不上）：报**失败**（附技术串给日志），不是「没有产出结论」。
    @MainActor
    func testIMRunReportsTheFailureDetail() async {
        let model = AgentChatModel()
        model.endpointProvider = { .ready(model: "m", endpoint: "https://example.invalid") }
        installAnsweringLoop(on: model, client: FailingClient())

        let outcome = await model.runFromIM(prompt: "查一下天气")
        guard case let .failed(detail) = outcome else {
            return XCTFail("循环抛错要如实报失败，实际：\(outcome)")
        }
        XCTAssertTrue(detail.contains("连不上"), "技术串要留给日志：\(detail)")
    }

    // MARK: - 接线锚点（宿主必须真的走这条新路）

    func testAppRunsIMTurnsThroughTheModelEntry() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let app = try String(contentsOf: root.appendingPathComponent("App/DoyahStudioApp.swift"),
                             encoding: .utf8)
        XCTAssertTrue(app.contains("agentChat.runFromIM("),
                      "IM 那一路必须走 AgentChatModel.runFromIM（判定在模型里，宿主只翻译结局）")
        XCTAssertFalse(app.contains("return .unavailable(code: \"noAnswer\")"),
                       "「没有产出结论」这个兜底码随本次修复作废（它把真原因吞了）")
    }

    // MARK: - 假件

    @MainActor
    private func installAnsweringLoop(on model: AgentChatModel,
                                      client: LLMStreamingClient = AnsweringClient(),
                                      delayMilliseconds: Int = 0) {
        model.makeLoop = { _, _, observer in
            (loop: AgentLoop(client: DelayedClient(inner: client, delayMilliseconds: delayMilliseconds),
                             dispatcher: QuietDispatcher(),
                             // **观察口必须接上**：正文是靠 `.delta` 落到 `state.messages` 的
                             // （真实的 `makeLoop` 也是把 `observer` 交给循环），不接就等于
                             // 模型答了而界面一个字都没攒下来。
                             observer: observer),
             context: AgentLoopContext(systemPrompt: "你是助手。",
                                       userPrompt: "查一下天气",
                                       baseRequest: LLMRequest(endpoint: URL(string: "http://127.0.0.1:9/v1")!,
                                                               model: "fake",
                                                               systemPrompt: "",
                                                               userPrompt: ""),
                                       sessionID: "s-im-path",
                                       workspace: "ws-im-path"))
        }
    }
}

// MARK: - 测试用假件

private final class AnsweringClient: LLMStreamingClient, @unchecked Sendable {
    func stream(_ request: LLMRequest) async throws -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.textDelta("看过了。"))
            continuation.yield(.finished(reason: "stop"))
            continuation.yield(.done)
            continuation.finish()
        }
    }
}

/// 只报结束、不给正文（工具轮没给结论那种形状）。
private final class SilentClient: LLMStreamingClient, @unchecked Sendable {
    func stream(_ request: LLMRequest) async throws -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.finished(reason: "stop"))
            continuation.yield(.done)
            continuation.finish()
        }
    }
}

private final class FailingClient: LLMStreamingClient, @unchecked Sendable {
    func stream(_ request: LLMRequest) async throws -> AsyncThrowingStream<LLMStreamEvent, Error> {
        throw LLMError.transport("连不上：测试用假客户端")
    }
}

/// 让一跳有真实耗时（用来造「上一轮还在跑」）。
private final class DelayedClient: LLMStreamingClient, @unchecked Sendable {
    private let inner: LLMStreamingClient
    private let delayMilliseconds: Int

    init(inner: LLMStreamingClient, delayMilliseconds: Int) {
        self.inner = inner
        self.delayMilliseconds = delayMilliseconds
    }

    func stream(_ request: LLMRequest) async throws -> AsyncThrowingStream<LLMStreamEvent, Error> {
        if delayMilliseconds > 0 {
            try await Task.sleep(nanoseconds: UInt64(delayMilliseconds) * 1_000_000)
        }
        return try await inner.stream(request)
    }
}

private final class QuietDispatcher: AgentToolDispatcher, @unchecked Sendable {
    func dispatch(_ invocation: AgentToolInvocation, approvals: Set<String>) -> AgentToolOutcome {
        .file(AgentToolFileOutput(path: "a.txt", text: "", truncated: false, totalBytes: 0))
    }
}
