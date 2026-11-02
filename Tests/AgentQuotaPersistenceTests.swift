import XCTest
@testable import DoyahCore

/// `NFR-ALL-GATE-AI-004`（成本与配额）的四条判据：
///
/// ① 配额在**真实调用路径**上累计（含派出去的子代理）—— 调用次数与累计 token 两个上限都能触发；
/// ② 触顶后**拒绝发起新调用**并说明原因（不是静默失败）；
/// ③ **跨调用累计，重启后计数不重置**（账本落盘）；
/// ④ 「跨重启」不是让上限变成死路：面板上有清零入口，且清零是真删文件。
///
/// 为什么这组值得单独钉：在这片之前账本只活在 `AppState` 的内存里，注释还写着
/// 「按需求口径它是单次会话，所以退出应用即清零」—— 那句话与判据 ③ **正相反**；
/// 而编辑区 AI 辅助与「测试连接」两条真实外发路径压根没过配额判定。
final class AgentQuotaPersistenceTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quota-ledger-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    // MARK: - ③ 账本落盘：重启不重置

    /// 「重启」= 新建一个 `AgentQuotaLedgerStore` 实例读同一个目录（与进程重启等价）。
    func testLedgerSurvivesRestart() throws {
        let store = AgentQuotaLedgerStore(directory: directory)
        XCTAssertTrue(store.save(AgentQuotaLedger(requestCount: 7, totalTokens: 4_096)))

        let afterRestart = AgentQuotaLedgerStore(directory: directory).load()
        XCTAssertEqual(afterRestart.ledger, AgentQuotaLedger(requestCount: 7, totalTokens: 4_096))
        XCTAssertFalse(afterRestart.degraded)
    }

    /// 文件坏了 ⇒ 按 0 计但**如实标降级**（不许把「账本读不出来」说成「一次都没用过」）。
    func testCorruptLedgerIsReportedNotSilentlyZero() throws {
        let file = directory.appendingPathComponent(AgentQuotaLedgerStore.fileName)
        try Data("{ 这不是 JSON".utf8).write(to: file)

        let reading = AgentQuotaLedgerStore(directory: directory).load()
        XCTAssertEqual(reading.ledger, .empty)
        XCTAssertTrue(reading.degraded, "读不出来必须标降级，而不是安静地报 0")
    }

    /// 没有账本文件 = 全新账本，**不是**降级（两件事要分得开）。
    func testMissingFileIsFreshNotDegraded() {
        let reading = AgentQuotaLedgerStore(directory: directory).load()
        XCTAssertEqual(reading, .fresh)
        XCTAssertFalse(reading.degraded)
    }

    /// 清零 = **真删文件**（不是写一份 0 进去）。
    func testResetReallyDeletesTheFile() throws {
        let store = AgentQuotaLedgerStore(directory: directory)
        let file = directory.appendingPathComponent(AgentQuotaLedgerStore.fileName)
        XCTAssertTrue(store.save(AgentQuotaLedger(requestCount: 3, totalTokens: 30)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))

        XCTAssertTrue(store.reset())
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "清零必须是真删，盘上不许留一份 0")
        XCTAssertEqual(store.load().ledger, .empty)
        XCTAssertFalse(store.load().degraded)
    }

    // MARK: - ①② 重启之后，两个上限都还能拦住「下一次调用」

    private func configuration(maxRequests: Int? = nil, maxTotalTokens: Int? = nil) -> AgentConfiguration {
        AgentConfiguration(
            isEnabled: true,
            endpoint: "http://127.0.0.1:11434",
            model: "qwen2.5:7b",
            quota: AgentQuota(maxRequestsPerSession: maxRequests,
                              maxOutputTokensPerRequest: nil,
                              maxTotalTokens: maxTotalTokens)
        )
    }

    /// 只数请求次数的传输层（被拦下时它必须还是 0）。
    private final class CountingTransport: HTTPTransport, @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var sendCount: Int { lock.lock(); defer { lock.unlock() }; return count }

        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            lock.lock(); count += 1; lock.unlock()
            let body = #"{"choices":[{"message":{"content":"SELECT 1"},"finish_reason":"stop"}],"usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}}"#
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(body.utf8), response)
        }
    }

    /// 上一次运行把「2 次」用完了；重启后第一次调用就必须被拦，且**一次请求都不发**。
    func testRequestLimitSurvivesRestartAndBlocksBeforeSending() async throws {
        let store = AgentQuotaLedgerStore(directory: directory)
        store.save(AgentQuotaLedger(requestCount: 2, totalTokens: 20))

        let transport = CountingTransport()
        let client = OpenAICompatibleClient(transport: transport)
        do {
            _ = try await AgentSQLGenerator.generate(
                request: .init(instruction: "列出用户", schema: AgentSQLGenerator.SchemaSummary(tables: [])),
                configuration: configuration(maxRequests: 2),
                apiKey: nil,
                ledger: AgentQuotaLedgerStore(directory: directory).load().ledger,
                client: client
            )
            XCTFail("重启后账本里的 2 次已用满 ⇒ 这一次应当被拦下")
        } catch let error as LLMError {
            guard case .quotaExceeded(let message) = error else {
                return XCTFail("应当是 quotaExceeded，实际：\(error)")
            }
            XCTAssertFalse(message.isEmpty, "超限必须给可读原因（判据 ②）")
        }
        XCTAssertEqual(transport.sendCount, 0, "被配额拦下时一次请求都不许发出")
    }

    /// 累计 token 上限同样跨重启生效 —— 两个上限都要能触发，不许只判次数。
    func testTokenLimitSurvivesRestartAndBlocksBeforeSending() async throws {
        let store = AgentQuotaLedgerStore(directory: directory)
        store.save(AgentQuotaLedger(requestCount: 5, totalTokens: 200))

        let transport = CountingTransport()
        let client = OpenAICompatibleClient(transport: transport)
        do {
            _ = try await AgentSQLGenerator.generate(
                request: .init(instruction: "列出用户", schema: AgentSQLGenerator.SchemaSummary(tables: [])),
                configuration: configuration(maxTotalTokens: 200),
                apiKey: nil,
                ledger: AgentQuotaLedgerStore(directory: directory).load().ledger,
                client: client
            )
            XCTFail("累计 token 已到上限 ⇒ 应当被拦下")
        } catch let error as LLMError {
            guard case .quotaExceeded(let message) = error else {
                return XCTFail("应当是 quotaExceeded，实际：\(error)")
            }
            XCTAssertTrue(message.contains("200") || message.contains("token"), message)
        }
        XCTAssertEqual(transport.sendCount, 0)
    }

    // MARK: - 账本算术（合并 / 差）

    func testMergeAndDeltaArePlainArithmeticWithNoNegativeRefund() {
        let a = AgentQuotaLedger(requestCount: 2, totalTokens: 20)
        let b = AgentQuotaLedger(requestCount: 3, totalTokens: 30)
        XCTAssertEqual(a.merged(with: b), AgentQuotaLedger(requestCount: 5, totalTokens: 50))
        XCTAssertEqual(a.merged(with: .empty), a)
        // 顺序搞反 ⇒ 按 0（不许「凭空退配额」）
        XCTAssertEqual(a.delta(since: b), .empty)
        XCTAssertEqual(b.delta(since: a), AgentQuotaLedger(requestCount: 1, totalTokens: 10))
    }

    // MARK: - ① 派出去的子代理也算进主账

    /// 父任务派两路、两路各跑一跳：四次模型调用**全部**要计入主账本。
    ///
    /// 反向确认（本片实测）：去掉 `runSubagentDispatch` 的并账那一段 ⇒ 主账只记父的 2 跳，
    /// 子代理那 2 次调用在主账里「不存在」—— 配额会被「派出去」这条路绕过。
    func testSubagentCallsAreCountedInTheParentLedger() async {
        let client = ScriptedStreamingClient()
        client.script("主任务", [[
            .toolCallDelta(index: 0, id: "c1", name: "dispatch_subtasks",
                           argumentsFragment: tasksJSON([("a", "La", "做 a"), ("b", "Lb", "做 b")])),
            .usage(LLMUsage(promptTokens: 5, completionTokens: 5, totalTokens: 10), model: "fake"),
            .finished(reason: "tool_calls"),
        ], [
            .textDelta("都做完了"),
            .usage(LLMUsage(promptTokens: 5, completionTokens: 5, totalTokens: 10), model: "fake"),
            .finished(reason: "stop"),
        ]])
        client.script("做 a", [[
            .textDelta("结论A"),
            .usage(LLMUsage(promptTokens: 15, completionTokens: 15, totalTokens: 30), model: "fake"),
            .finished(reason: "stop"),
        ]])
        client.script("做 b", [[
            .textDelta("结论B"),
            .usage(LLMUsage(promptTokens: 15, completionTokens: 15, totalTokens: 30), model: "fake"),
            .finished(reason: "stop"),
        ]])

        var loop = AgentLoop(client: client, dispatcher: NullDispatcher())
        loop.subagentPolicy = AgentSubagentPolicy(maxConcurrent: 2)
        loop.quota = AgentQuota(maxTotalTokens: 1_000)
        let result = await loop.run(context: context(prompt: "主任务"))

        XCTAssertEqual(result.outcome, .finished(text: "都做完了"))
        XCTAssertEqual(client.callCount, 4, "父 2 跳 + 两路各 1 跳")
        let ledger = try? XCTUnwrap(result.quotaLedger)
        XCTAssertEqual(ledger?.requestCount, 4, "子代理那两次调用必须进主账（判据 ①）")
        XCTAssertEqual(ledger?.totalTokens, 80, "10 + 10（父）+ 30 + 30（子）")
    }

    // MARK: - 源锚点：四条真实外发路径都过同一个账本

    /// 判据 ① 的**覆盖面**这条只能从源树判：单测起不了 `AppState`，
    /// 但「哪条路读了账本、哪条路记了账」在源文本里是确定形状。
    func testEveryOutboundPathGoesThroughTheSharedLedger() throws {
        let source = try String(contentsOf: repoRoot().appendingPathComponent("App/AppState.swift"),
                                encoding: .utf8)

        let editAssist = try block("func editAssistComplete", in: source)
        XCTAssertTrue(editAssist.contains("agentQuotaLedgerForNextCall()"),
                      "编辑区 AI 辅助要先读共用账本再判")
        // 闸门形状要钉死：写成 `isAllowed || true` 这类摆设时，`LLMError.quotaExceeded` 那几个字还在，
        // 但闸门已经不存在了 —— 判据必须能判红这种「字在、闸没」的改法。
        XCTAssertTrue(editAssist.contains("guard quotaDecision.isAllowed else"),
                      "判定必须是真闸门（`guard isAllowed else`），不是 `|| true` 之类的摆设")
        XCTAssertTrue(editAssist.contains("LLMError.quotaExceeded"),
                      "超限要如实抛（可读原因），不许静默失败")
        XCTAssertTrue(editAssist.contains("recordAgentQuota("),
                      "这条路的调用也要记进账本")

        let connectionTest = try block("func testAgentConnection", in: source)
        XCTAssertTrue(connectionTest.contains("guard quotaDecision.isAllowed else"),
                      "测试连接也是一次真调用：闸门同样要是真的")
        XCTAssertTrue(connectionTest.contains("recordAgentQuota("))

        for signature in ["func generateAgentSQL", "func generateDataTaskSpec"] {
            let body = try block(signature, in: source)
            XCTAssertTrue(body.contains("ledger: agentQuotaLedgerForNextCall()"),
                          "\(signature) 必须读共用账本")
            XCTAssertTrue(body.contains("recordAgentQuota(result.quotaLedger)"),
                          "\(signature) 跑完必须回写账本")
        }

        // 对话那条路的账本同样是「读盘幂等后的那一份」
        XCTAssertTrue(source.contains("quotaLedger: agentQuotaLedgerForNextCall()"),
                      "对话循环的起点账本必须含跨重启读回的那一段")

        // 落盘那一句只许有一处（记账的唯一出口）
        XCTAssertEqual(occurrences(of: "agentQuotaLedgerStore.save(ledger)", in: source), 1,
                       "记账出口只许一处，免得哪条路漏写")
    }

    // MARK: - 夹具

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    /// 取一个函数的函数体（从签名到下一个顶层缩进 4 空格的 `func`）。
    private func block(_ signature: String, in source: String) throws -> String {
        guard let start = source.range(of: signature) else {
            throw NSError(domain: "quota", code: 1, userInfo: [NSLocalizedDescriptionKey: "找不到 \(signature)"])
        }
        let rest = source[start.upperBound...]
        if let end = rest.range(of: "\n    func ") {
            return String(rest[..<end.lowerBound])
        }
        return String(rest)
    }

    private func occurrences(of needle: String, in haystack: String) -> Int {
        var count = 0
        var searchStart = haystack.startIndex
        while let found = haystack.range(of: needle, range: searchStart..<haystack.endIndex) {
            count += 1
            searchStart = found.upperBound
        }
        return count
    }

    private func tasksJSON(_ entries: [(String, String, String)]) -> String {
        let array = entries.map { ["id": $0.0, "label": $0.1, "prompt": $0.2] }
        let inner = String(data: try! JSONSerialization.data(withJSONObject: array), encoding: .utf8)!
        let root = String(data: try! JSONSerialization.data(withJSONObject: ["tasks": inner]), encoding: .utf8)!
        return root
    }

    private func context(prompt: String, session: String = "quota-parent") -> AgentLoopContext {
        AgentLoopContext(systemPrompt: "系统", userPrompt: prompt,
                         baseRequest: LLMRequest(endpoint: URL(string: "http://127.0.0.1:1/v1")!,
                                                 model: "fake", systemPrompt: "", userPrompt: prompt),
                         sessionID: session, workspace: "ws")
    }

    /// 按提示词分脚本的假模型（与 `AgentSubagentDispatchTests` 同形；那份是私有类型）。
    private final class ScriptedStreamingClient: LLMStreamingClient, @unchecked Sendable {
        private let lock = NSLock()
        private var script: [String: [[LLMStreamEvent]]] = [:]
        private var calls = 0

        func script(_ prompt: String, _ hops: [[LLMStreamEvent]]) {
            lock.lock(); script[prompt] = hops; lock.unlock()
        }

        var callCount: Int { lock.lock(); defer { lock.unlock() }; return calls }

        func stream(_ request: LLMRequest) async throws -> AsyncThrowingStream<LLMStreamEvent, Error> {
            lock.lock()
            calls += 1
            let key = script.keys.first { request.userPrompt.contains($0) } ?? request.userPrompt
            var hops = script[key] ?? [[.textDelta("OK"), .finished(reason: "stop")]]
            let events = hops.count > 1 ? hops.removeFirst() : hops[0]
            script[key] = hops
            lock.unlock()
            return AsyncThrowingStream { continuation in
                for event in events { continuation.yield(event) }
                continuation.finish()
            }
        }
    }

    private final class NullDispatcher: AgentToolDispatcher, @unchecked Sendable {
        func dispatch(_ invocation: AgentToolInvocation, approvals: Set<String>) -> AgentToolOutcome {
            .file(AgentToolFileOutput(path: invocation.name, text: "", truncated: false, totalBytes: 0))
        }
    }
}
