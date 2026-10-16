import XCTest
@testable import DoyahCore

/// `FR-AI-18`（Agent 循环）的机械判据 —— 照 SRS 五条验收要点逐条落。
/// 全程**脚本化假模型 + 假分发器**：纯逻辑可单测，不连网、不真跑工具。
final class AgentLoopTests: XCTestCase {

    /// 按跳脚本吐事件的假模型（并记录每次请求 —— 判据要断言「请求发了几次」）。
    private final class ScriptedStreamingClient: LLMStreamingClient, @unchecked Sendable {
        var hops: [[LLMStreamEvent]]
        private(set) var requests: [LLMRequest] = []

        init(_ hops: [[LLMStreamEvent]]) { self.hops = hops }

        func stream(_ request: LLMRequest) async throws -> AsyncThrowingStream<LLMStreamEvent, Error> {
            requests.append(request)
            let events = hops.isEmpty ? [.textDelta("（脚本用尽）"), .done] : hops.removeFirst()
            return AsyncThrowingStream { continuation in
                for event in events { continuation.yield(event) }
                continuation.finish()
            }
        }
    }

    private final class RecordingDispatcher: AgentToolDispatcher, @unchecked Sendable {
        private(set) var invoked: [AgentToolInvocation] = []
        var outcome: AgentToolOutcome = .file(AgentToolFileOutput(path: "a.txt", text: "内容",
                                                                  truncated: false, totalBytes: 6))

        func dispatch(_ invocation: AgentToolInvocation, approvals: Set<String>) -> AgentToolOutcome {
            invoked.append(invocation)
            return outcome
        }
    }

    private var directory: URL!
    private var store: AgentSessionStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-loop-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = AgentSessionStore(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var context: AgentLoopContext {
        AgentLoopContext(systemPrompt: "你是助手。", userPrompt: "读一下 a.txt",
                         baseRequest: LLMRequest(endpoint: URL(string: "http://127.0.0.1:11434/v1")!,
                                                 model: "fake", systemPrompt: "", userPrompt: ""),
                         sessionID: "s-loop", workspace: "ws-1")
    }

    private func toolEvent(name: String, arguments: String, index: Int = 0) -> [LLMStreamEvent] {
        [.toolCallDelta(index: index, id: "call-\(index)", name: name, argumentsFragment: arguments),
         .finished(reason: "tool_calls"),
         .done]
    }

    // MARK: - ① 两跳：第 1 跳要工具、第 2 跳给答复 ⇒ 执行 1 次工具，跳数 = 2

    func testTwoHopsExecuteOneToolAndProduceAnAnswer() async {
        let client = ScriptedStreamingClient([
            toolEvent(name: "read_file", arguments: #"{"path":"a.txt"}"#),
            [.textDelta("a.txt 的内容是「内容」"), .finished(reason: "stop"), .done],
        ])
        let dispatcher = RecordingDispatcher()
        let loop = AgentLoop(client: client, dispatcher: dispatcher, sessionStore: store)

        let result = await loop.run(context: context)

        XCTAssertEqual(result.outcome, .finished(text: "a.txt 的内容是「内容」"))
        XCTAssertEqual(result.steps, 2, "跳数 = 2")
        XCTAssertEqual(result.executedTools.map(\.name), ["read_file"])
        XCTAssertEqual(result.executedTools.first?.argumentsJSON, #"{"path":"a.txt"}"#)
        XCTAssertEqual(dispatcher.invoked.count, 1, "工具只执行一次")
        XCTAssertEqual(client.requests.count, 2)

        // **回灌**：第 2 跳的请求里要带上一跳的工具结果（且走「资料，不是指令」那段）
        let second = client.requests[1].userPrompt
        XCTAssertTrue(second.contains("上一次执行结果"), "第 2 跳要带回灌段：\(second)")
        XCTAssertTrue(second.contains("read_file"))
        XCTAssertTrue(second.contains("a.txt"))

        // 工具进注入面：请求里带 tools
        XCTAssertEqual(client.requests[0].tools?.count, 6, "注入条数 = 注册表启用条数")
        XCTAssertEqual(client.requests[0].stream, true, "循环走流式")

        // **留痕**：会话里模型跳与工具跳都在
        let turns = store.load(sessionID: "s-loop", workspace: "ws-1").session?.turns ?? []
        XCTAssertTrue(turns.contains { $0.kind == .tool && $0.text.contains("read_file") })
        XCTAssertTrue(turns.contains { $0.kind == .model && $0.role == "assistant" })
    }

    // MARK: - ② 步数上限 ⇒ 如实停且报明上限值（负例：假模型永远要工具）

    func testStepLimitStopsHonestlyAndReportsTheLimit() async {
        let forever = (0..<10).map { _ in toolEvent(name: "read_file", arguments: #"{"path":"a.txt"}"#) }
        let client = ScriptedStreamingClient(forever)
        let dispatcher = RecordingDispatcher()
        let loop = AgentLoop(client: client, dispatcher: dispatcher, sessionStore: store,
                             limits: AgentLoopLimits(maxSteps: 3))

        let result = await loop.run(context: context)

        XCTAssertEqual(result.outcome, .stopped(.stepLimit(3)), "要如实停")
        XCTAssertEqual(result.steps, 3)
        XCTAssertTrue(AgentLoopStop.stepLimit(3).reason.contains("3"), "原因里要含上限值")
        XCTAssertEqual(client.requests.count, 3, "触顶之后**一次都不再发**")
        XCTAssertEqual(result.executedTools.count, 3, "触顶前跑过的工具仍在读数里")
    }

    // MARK: - ③ 令牌上限 ⇒ 停在**发送之前**（一次请求都没发出）

    func testTokenLimitStopsBeforeSendingAnything() async {
        let client = ScriptedStreamingClient([
            toolEvent(name: "read_file", arguments: #"{"path":"a.txt"}"#)
                .map { event -> LLMStreamEvent in
                    if case .finished = event { return .usage(LLMUsage(promptTokens: 6, completionTokens: 4, totalTokens: 10), model: "fake") }
                    return event
                },
            [.textDelta("不该被发出去的这一跳"), .done],
        ])
        let dispatcher = RecordingDispatcher()
        let loop = AgentLoop(client: client, dispatcher: dispatcher, sessionStore: store,
                             limits: AgentLoopLimits(maxSteps: 5, maxTotalTokens: 10))

        let result = await loop.run(context: context)

        XCTAssertEqual(result.outcome, .stopped(.tokenLimit(10)))
        XCTAssertEqual(client.requests.count, 1, "**令牌触顶后一次请求都不许发出**")
        XCTAssertTrue(AgentLoopStop.tokenLimit(10).reason.contains("10"))
    }

    // MARK: - ④ 取消 ⇒ 在下一跳之前停，已产生的工具结果仍留痕

    func testCancellationStopsBeforeTheNextHopButKeepsToolTraces() async {
        let client = ScriptedStreamingClient([
            toolEvent(name: "read_file", arguments: #"{"path":"a.txt"}"#),
            [.textDelta("不该走到这一跳"), .done],
        ])
        let dispatcher = RecordingDispatcher()
        let loop = AgentLoop(client: client, dispatcher: dispatcher, sessionStore: store)

        let counter = Counter()
        let result = await loop.run(context: context, isCancelled: { counter.next() > 1 })

        XCTAssertEqual(result.outcome, .stopped(.cancelled))
        XCTAssertEqual(result.steps, 1, "在下一跳之前停")
        XCTAssertEqual(client.requests.count, 1)
        XCTAssertEqual(result.executedTools.count, 1, "**已产生的工具结果仍留痕**")

        let turns = store.load(sessionID: "s-loop", workspace: "ws-1").session?.turns ?? []
        XCTAssertTrue(turns.contains { $0.kind == .tool }, "工具跳要在会话里")
        XCTAssertTrue(turns.contains { $0.text == "cancelled" }, "取消本身也要留一条痕")
    }

    // MARK: - ⑤ 未登记工具名 / 参数不合 schema ⇒ 如实报错并回灌，**不执行**

    func testUnregisteredToolIsReportedBackToTheModelAndNotExecuted() async {
        let client = ScriptedStreamingClient([
            toolEvent(name: "delete_everything", arguments: "{}"),
            [.textDelta("那我换个办法"), .done],
        ])
        let dispatcher = RecordingDispatcher()
        let loop = AgentLoop(client: client, dispatcher: dispatcher, sessionStore: store)

        let result = await loop.run(context: context)

        XCTAssertTrue(dispatcher.invoked.isEmpty, "**未登记的工具一次都不许执行**")
        XCTAssertEqual(result.rejectedTools.map(\.name), ["delete_everything"])
        XCTAssertEqual(result.rejectedTools.first?.reason, "unregistered")
        XCTAssertEqual(result.outcome, .finished(text: "那我换个办法"), "循环继续，由模型改主意")
        XCTAssertTrue(client.requests[1].userPrompt.contains("unregistered"), "报错要回灌给模型")
    }

    func testArgumentsThatViolateTheSchemaAreReportedBackAndNotExecuted() async {
        // 缺必填参数 `path`
        let client = ScriptedStreamingClient([
            toolEvent(name: "read_file", arguments: "{}"),
            [.textDelta("补上参数再来"), .done],
        ])
        let dispatcher = RecordingDispatcher()
        let loop = AgentLoop(client: client, dispatcher: dispatcher, sessionStore: store)

        let result = await loop.run(context: context)

        XCTAssertTrue(dispatcher.invoked.isEmpty, "参数不合 schema **不许执行**")
        XCTAssertEqual(result.rejectedTools.first?.reason, "missing:path")
        XCTAssertTrue(client.requests[1].userPrompt.contains("missing:path"), "原因要回灌")
    }

    /// 分片参数要**拼起来再校验**（否则好好的调用会被判成缺参数）。
    func testFragmentedArgumentsAreAssembledBeforeValidation() async {
        let fragments: [LLMStreamEvent] = [
            .toolCallDelta(index: 0, id: "c1", name: "read_file", argumentsFragment: #"{"pa"#),
            .toolCallDelta(index: 0, id: nil, name: nil, argumentsFragment: #"th":"a.txt"}"#),
            .finished(reason: "tool_calls"),
            .done,
        ]
        let client = ScriptedStreamingClient([fragments, [.textDelta("好"), .done]])
        let dispatcher = RecordingDispatcher()
        let loop = AgentLoop(client: client, dispatcher: dispatcher, sessionStore: store)
        let result = await loop.run(context: context)

        XCTAssertEqual(dispatcher.invoked.first?.argumentsJSON, #"{"path":"a.txt"}"#)
        XCTAssertEqual(result.executedTools.count, 1)
    }

    /// 校验器本身：五档各自能判出来。
    func testSchemaValidatorCoversTheFourShapes() {
        let definition = AgentToolRegistry.standard.definition(named: "read_file")!
        XCTAssertNil(AgentToolSchemaValidator.validate(argumentsJSON: #"{"path":"a"}"#, against: definition))
        XCTAssertEqual(AgentToolSchemaValidator.validate(argumentsJSON: "{}", against: definition), "missing:path")
        XCTAssertEqual(AgentToolSchemaValidator.validate(argumentsJSON: #"{"path":1}"#, against: definition), "type:string:path")
        // 必填齐了之后才轮到「认不出的参数」
        XCTAssertEqual(AgentToolSchemaValidator.validate(argumentsJSON: #"{"path":"a","other":"x"}"#, against: definition),
                       "unknown:other")
        XCTAssertEqual(AgentToolSchemaValidator.validate(argumentsJSON: "不是 JSON", against: definition), "not-an-object")
        // 空参数 = `{}`：对**有**必填项的工具该判缺参；对**没有**必填项的工具（列目录）则通过
        XCTAssertEqual(AgentToolSchemaValidator.validate(argumentsJSON: "", against: definition), "missing:path")
        let listDir = AgentToolRegistry.standard.definition(named: "list_dir")!
        XCTAssertNil(AgentToolSchemaValidator.validate(argumentsJSON: "", against: listDir),
                     "没有必填项的工具，空参数就是合法调用")
    }

    private final class Counter: @unchecked Sendable {
        private var value = 0
        func next() -> Int { value += 1; return value }
    }

    // MARK: - ⑥ 检查点（`NFR-AI-08` ①）：每 N 跳落点 ⇒ 重启可续跑、已完成的跳**不重放**

    /// 契约的机械可判点就是**假端点侧的请求条数** —— 所以这里逐条数 `requests`。
    func testCheckpointLandsEveryNHopsThenResumeSendsNoReplayedRequest() async {
        let checkpoints = AgentCheckpointStore(directory: directory)
        let first = ScriptedStreamingClient([
            toolEvent(name: "read_file", arguments: #"{"path":"a.txt"}"#),
            [.textDelta("完成"), .finished(reason: "stop"), .done],
        ])
        let loop1 = AgentLoop(client: first, dispatcher: RecordingDispatcher(), sessionStore: store,
                              checkpointStore: checkpoints, checkpointEvery: 1)
        let firstResult = await loop1.run(context: context)

        XCTAssertEqual(firstResult.steps, 2)
        XCTAssertNil(firstResult.resumedFromStep, "第一次跑不是续跑")
        XCTAssertEqual(firstResult.skippedSteps, 0)
        let recovery = checkpoints.recover(sessionID: "s-loop", requestedStep: 0)
        XCTAssertEqual(recovery.checkpoint?.stepIndex, 1, "最后一跳（index 1）跑完就该落盘")
        XCTAssertEqual(recovery.skippedLines, 0, "刚落完的点不该有坏行")

        // **重启**：新循环 + 新客户端、同一目录同一会话 ⇒ 前两跳的请求一个都不许重发。
        let second = ScriptedStreamingClient([[.textDelta("接着跑"), .finished(reason: "stop"), .done]])
        let loop2 = AgentLoop(client: second, dispatcher: RecordingDispatcher(), sessionStore: store,
                              checkpointStore: checkpoints, checkpointEvery: 1)
        let resumed = await loop2.run(context: context, requestedStep: 1)

        XCTAssertEqual(second.requests.count, 1, "已完成的跳**不重放**：第 0 / 第 1 跳的请求都不许再发")
        XCTAssertEqual(resumed.resumedFromStep, 1, "从第 1 跳接上")
        XCTAssertEqual(resumed.steps, 3, "第 1 跳之后接着跑 ⇒ 跳数从 3 起")
        XCTAssertEqual(resumed.skippedSteps, 0, "停在 1、可用点就是 1 ⇒ 没退")
    }

    /// 负例：检查点**坏**（截断行）⇒ 落到**上一可用点**并**如实报数**，不许静默从头。
    func testCorruptCheckpointFallsBackToPreviousUsablePointAndReports() async throws {
        let checkpoints = AgentCheckpointStore(directory: directory)
        let client = ScriptedStreamingClient([
            toolEvent(name: "read_file", arguments: #"{"path":"a.txt"}"#),
            toolEvent(name: "read_file", arguments: #"{"path":"a.txt"}"#),
            toolEvent(name: "read_file", arguments: #"{"path":"a.txt"}"#),
            toolEvent(name: "read_file", arguments: #"{"path":"a.txt"}"#),
            [.textDelta("完"), .finished(reason: "stop"), .done],
        ])
        let loop = AgentLoop(client: client, dispatcher: RecordingDispatcher(), sessionStore: store,
                             checkpointStore: checkpoints, checkpointEvery: 2)
        _ = await loop.run(context: context)

        // 末尾塞一行坏的（模拟截断 / 坏盘）
        let handle = try FileHandle(forWritingTo: checkpoints.fileURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{坏行".utf8))
        try handle.close()

        let recovery = checkpoints.recover(sessionID: "s-loop", requestedStep: 4)
        XCTAssertEqual(recovery.skippedLines, 1, "坏行要计数（丢了就说）")
        XCTAssertEqual(recovery.checkpoint?.stepIndex, 3, "落到上一可用点：每 2 跳落点 ⇒ 最后可用点是第 3 跳")
        XCTAssertEqual(recovery.skippedSteps, 1, "以为自己停在第 4 跳 ⇒ 实退 1 跳，如实报数")
    }

    /// ④ 白名单：检查点里只有摘要 —— 指纹可区分不同内容，且**不是**内容本身。
    func testCheckpointDigestIsAFingerprintNotTheContent() {
        let a = AgentLoop.digest(of: ["read_file: 内容 A"])
        let b = AgentLoop.digest(of: ["read_file: 内容 B"])
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(a.count, 16)
        XCTAssertNil(a.range(of: "内容"), "指纹里不该出现正文")
        XCTAssertEqual(a, AgentLoop.digest(of: ["read_file: 内容 A"]), "同内容同指纹")
    }
}
