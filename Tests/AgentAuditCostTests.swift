import XCTest
@testable import DoyahCore

/// `FR-AI-24`（审计扩展：逐跳 + 成本字段）的机械判据 —— 验收要点 ①②③④。
final class AgentAuditCostTests: XCTestCase {

    /// 收审计记录的假口（线程安全：循环是 async 的）。
    private final class RecordingSink: AgentAuditSink, @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [AgentActionRecord] = []
        var records: [AgentActionRecord] {
            lock.lock(); defer { lock.unlock() }
            return storage
        }
        func record(_ record: AgentActionRecord) async {
            lock.lock(); storage.append(record); lock.unlock()
        }
    }

    private final class ScriptedStreamingClient: LLMStreamingClient, @unchecked Sendable {
        var hops: [[LLMStreamEvent]]
        init(_ hops: [[LLMStreamEvent]]) { self.hops = hops }
        func stream(_ request: LLMRequest) async throws -> AsyncThrowingStream<LLMStreamEvent, Error> {
            let events = hops.isEmpty ? [.textDelta("（用尽）"), .done] : hops.removeFirst()
            return AsyncThrowingStream { continuation in
                for event in events { continuation.yield(event) }
                continuation.finish()
            }
        }
    }

    private final class StubDispatcher: AgentToolDispatcher, @unchecked Sendable {
        func dispatch(_ invocation: AgentToolInvocation, approvals: Set<String>) -> AgentToolOutcome {
            .file(AgentToolFileOutput(path: "a.txt", text: "内容", truncated: false, totalBytes: 6))
        }
    }

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-audit-cost-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func loopContext() -> AgentLoopContext {
        AgentLoopContext(systemPrompt: "你是助手。", userPrompt: "读一下 a.txt",
                         baseRequest: LLMRequest(endpoint: URL(string: "http://127.0.0.1:11434/v1")!,
                                                 model: "fake-model", systemPrompt: "", userPrompt: ""),
                         sessionID: "s-audit", workspace: "ws-1")
    }

    // MARK: - ① 两跳 ⇒ **2 条模型记录 + 1 条工具记录**（条数与顺序都可断言）

    func testTwoHopsProduceTwoModelRecordsAndOneToolRecord() async {
        let sink = RecordingSink()
        let client = ScriptedStreamingClient([
            [.toolCallDelta(index: 0, id: "c1", name: "read_file", argumentsFragment: #"{"path":"a.txt"}"#),
             .usage(LLMUsage(promptTokens: 11, completionTokens: 7, totalTokens: 18), model: "fake-model"),
             .finished(reason: "tool_calls"), .done],
            [.textDelta("内容就是「内容」"),
             .usage(LLMUsage(promptTokens: 20, completionTokens: 9, totalTokens: 29), model: "fake-model"),
             .finished(reason: "stop"), .done],
        ])
        let loop = AgentLoop(client: client, dispatcher: StubDispatcher(),
                             sessionStore: AgentSessionStore(directory: directory),
                             audit: sink)

        let result = await loop.run(context: loopContext())
        XCTAssertEqual(result.steps, 2)

        let records = sink.records
        XCTAssertEqual(records.count, 3, "两跳对话 = 2 条模型记录 + 1 条工具记录，实际 \(records.count) 条")
        XCTAssertEqual(records.map(\.origin), [.modelCall, .action, .modelCall], "顺序也要对")
        XCTAssertEqual(records.map { $0.hopIndex }, [0, 0, 1], "工具记录挂在它那一跳上")
        XCTAssertEqual(records.filter { $0.resolvedOrigin == .modelCall }.count, 2)
        XCTAssertEqual(records.filter { $0.resolvedOrigin == .action }.count, 1)
        for record in records { XCTAssertEqual(record.sessionID, "s-audit", "同一会话要串得起来") }
    }

    // MARK: - ② 每条含模型 / 端点 / token / 耗时 / 状态

    func testEveryRecordCarriesTheCostFields() async {
        let sink = RecordingSink()
        let client = ScriptedStreamingClient([
            [.toolCallDelta(index: 0, id: "c1", name: "read_file", argumentsFragment: #"{"path":"a.txt"}"#),
             .usage(LLMUsage(promptTokens: 11, completionTokens: 7, totalTokens: 18), model: "fake-model"),
             .finished(reason: "tool_calls"), .done],
            [.textDelta("好"), .done],
        ])
        let loop = AgentLoop(client: client, dispatcher: StubDispatcher(), audit: sink)
        _ = await loop.run(context: loopContext())

        let models = sink.records.filter { $0.resolvedOrigin == .modelCall }
        for (index, record) in models.enumerated() {
            XCTAssertEqual(record.model, "fake-model")
            XCTAssertEqual(record.endpoint, "http://127.0.0.1:11434/v1/chat/completions")
            XCTAssertNotNil(record.durationMilliseconds, "耗时要有")
            XCTAssertEqual(record.outcome, .generated)
            XCTAssertFalse(record.sql.isEmpty, "请求摘要要有（能看出当时让它干什么）")
            if index == 0 {
                XCTAssertEqual(record.promptTokens, 11)
                XCTAssertEqual(record.completionTokens, 7)
                XCTAssertEqual(record.totalTokens, 18)
            }
        }
        let tools = sink.records.filter { $0.resolvedOrigin == .action }
        XCTAssertEqual(tools.first?.outcome, .executed)
        XCTAssertTrue(tools.first?.sql.contains("read_file") == true, "工具记录要写清是哪个工具")
        XCTAssertTrue(tools.first?.sql.contains("a.txt") == true, "以及什么参数")
    }

    // MARK: - ③ 导出：键集合是白名单、**不含密钥**

    func testExportsCarryTheCostFieldsAndNeverLeakSecrets() async throws {
        let log = AgentAuditLog(directoryURL: directory)
        let secret = "sk-abcdefghijklmnopqrstuvwxyz012345"
        let modelRecord = AgentActionRecord.makeModelCall(
            requestSummary: "改一下 \(secret)", model: "m-1", durationMilliseconds: 42,
            outcome: .generated, endpoint: "http://127.0.0.1:11434/v1/chat/completions",
            usage: LLMUsage(promptTokens: 3, completionTokens: 4, totalTokens: 7),
            sessionID: "s-1", hopIndex: 0)
        let toolRecord = AgentActionRecord.makeToolCall(
            toolName: "read_file", argumentsSummary: #"{"path":"a.txt"}"#, outcome: .executed,
            detail: "file:a.txt:6", sessionID: "s-1", hopIndex: 0)
        try await log.append(modelRecord)
        try await log.append(toolRecord)

        let csv = try await log.exportCSV()
        let json = String(data: try await log.exportJSON(), encoding: .utf8) ?? ""

        // 键集合 = 声明的白名单（CSV 表头与列定义同一份）
        XCTAssertEqual(csv.components(separatedBy: "\n").first, AgentAuditLog.csvColumns.joined(separator: ","))
        for column in ["model", "endpoint", "prompt_tokens", "completion_tokens", "total_tokens", "session", "hop", "duration_ms", "outcome"] {
            XCTAssertTrue(AgentAuditLog.csvColumns.contains(column), "成本列要有 `\(column)`")
        }
        // 不含密钥（落盘与导出两道都过 `AgentAudit.redacted`）
        XCTAssertFalse(csv.contains(secret), "CSV 不许带密钥")
        XCTAssertFalse(json.contains(secret), "JSON 不许带密钥")
        XCTAssertTrue(csv.contains("[redacted]") || !csv.contains("sk-"), "密钥片段被挡")
        for forbidden in ["apiKey", "api_key", "secret", "authorization"] {
            XCTAssertFalse(json.contains(forbidden), "JSON 里不许出现 `\(forbidden)` 这种键")
        }
        // 成本读数真的在导出里
        XCTAssertTrue(csv.contains("m-1"))
        XCTAssertTrue(csv.contains("127.0.0.1:11434/v1/chat/completions"))
        XCTAssertTrue(csv.contains(",3,4,7,"))     // prompt / completion / total 三列
        XCTAssertTrue(csv.contains("s-1"))
    }

    // MARK: - ④ 审计里能回答「哪一次用了哪个模型 / 端点」

    func testAuditAnswersWhichModelAndEndpointEachCallUsed() async throws {
        let log = AgentAuditLog(directoryURL: directory)
        try await log.append(AgentActionRecord.makeModelCall(
            requestSummary: "第一跳", model: "model-a", durationMilliseconds: 5, outcome: .generated,
            endpoint: "http://127.0.0.1:11434/v1/chat/completions", sessionID: "s", hopIndex: 0))
        try await log.append(AgentActionRecord.makeModelCall(
            requestSummary: "第二跳", model: "model-b", durationMilliseconds: 6, outcome: .generated,
            endpoint: "https://api.example.com/v1/chat/completions", sessionID: "s", hopIndex: 1))

        let records = try await log.entries()
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records[0].model, "model-a")
        XCTAssertEqual(records[1].model, "model-b")
        XCTAssertNotEqual(records[0].endpoint, records[1].endpoint, "两条的端点不同 ⇒ 能按跳区分")
        XCTAssertEqual(records.map(\.hopIndex), [0, 1])
    }

    // MARK: - 老日志仍然读得回来（新增字段全是可选的）

    func testOldLogLinesWithoutCostFieldsStillDecode() async throws {
        let log = AgentAuditLog(directoryURL: directory)
        // 手写一条**旧形状**的日志行（没有 endpoint / token / session / hop 这些键；键名是属性名的 camelCase）
        let old = """
        {"id":"\(UUID().uuidString)","timestamp":"2026-10-01T00:00:00Z","model":"old-model","sql":"SELECT 1","statementKind":"readQuery","risk":"low","findings":[],"outcome":"generated","origin":"modelCall"}
        """
        try old.appending("\n").write(to: await log.fileLocation(), atomically: true, encoding: .utf8)

        let records = try await log.entries()
        XCTAssertEqual(records.count, 1, "老日志必须还能读 —— 新增字段一律可选")
        XCTAssertEqual(records.first?.model, "old-model")
        XCTAssertNil(records.first?.endpoint)
        XCTAssertNil(records.first?.totalTokens)
        XCTAssertNil(records.first?.sessionID)
        XCTAssertNil(records.first?.hopIndex)
        XCTAssertEqual(records.first?.durationMilliseconds, nil)
    }

    /// 记录本体的键集合就是那份白名单（新增的成本字段在内，别的键一个没有）。
    func testRecordKeySetIsTheDeclaredWhitelist() {
        let record = AgentActionRecord.makeModelCall(
            requestSummary: "x", model: "m", durationMilliseconds: 1, outcome: .generated,
            endpoint: "e", usage: LLMUsage(promptTokens: 1, completionTokens: 2, totalTokens: 3),
            sessionID: "s", hopIndex: 0)
        let keys = Set(Mirror(reflecting: record).children.compactMap { $0.label })
        XCTAssertEqual(keys, ["id", "timestamp", "connectionName", "database", "model", "sql", "statementKind",
                              "risk", "findings", "outcome", "detail", "origin", "durationMilliseconds",
                              "endpoint", "promptTokens", "completionTokens", "totalTokens", "sessionID", "hopIndex"])
        for forbidden in ["apiKey", "authorization", "rows", "data"] {
            XCTAssertFalse(keys.contains(forbidden), "记录里不许有 `\(forbidden)`")
        }
    }
}
