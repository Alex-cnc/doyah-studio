import XCTest
@testable import DoyahCore

/// `NFR-ALL-GATE-AI-007`（会话持久化与密钥 / 审计 / 配额同一条口径）的三条判据：
///
/// ① 会话跨重启可读回，且按工作区隔离；
/// ② 配置文件里查不到密钥，审计导出（与落盘）不含密钥字段；
/// ③ 与既有密钥存储 / 审计 / 配额对齐，不出现第二套实现。
///
/// 为什么这组值得单独钉：这三条此前各自散在别的族里（`AgentSessionTests` 判存储往返、
/// `AgentAuditCostTests` 判导出脱敏、`AgentQuotaPersistenceTests` 判账本落盘），而**产品路径**
/// 上「谁把审计传给了循环」没人判过 —— 实测那一处写的是 `AgentAuditLog.shared`，与本类其余
/// 取用点（`agentAuditLog` = override ?? shared）是两个口子：探针把审计指到临时目录时，
/// 循环那几跳仍写进用户的真审计文件。
final class AgentSessionDurabilityTests: XCTestCase {

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

    private final class RecordingSink: AgentAuditSink, @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [AgentActionRecord] = []
        var records: [AgentActionRecord] { lock.lock(); defer { lock.unlock() }; return storage }
        func record(_ record: AgentActionRecord) async {
            lock.lock(); storage.append(record); lock.unlock()
        }
    }

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("durability-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    private func context(sessionID: String = "s-dura", workspace: String = "ws-1") -> AgentLoopContext {
        AgentLoopContext(systemPrompt: "你是助手。", userPrompt: "读一下 a.txt",
                         baseRequest: LLMRequest(endpoint: URL(string: "http://127.0.0.1:11434/v1")!,
                                                 model: "fake", systemPrompt: "", userPrompt: ""),
                         sessionID: sessionID, workspace: workspace)
    }

    private func twoHopScript() -> [[LLMStreamEvent]] {
        [
            [.toolCallDelta(index: 0, id: "call-0", name: "read_file",
                            argumentsFragment: #"{"path":"a.txt"}"#),
             .finished(reason: "tool_calls"), .done],
            [.textDelta("a.txt 里是「内容」"), .finished(reason: "stop"), .done],
        ]
    }

    // MARK: - ① 会话跨重启可读回（产品路径：循环写 → 新实例读）

    /// 跑两跳（用户提问 / 工具 / 答复），然后**换一个新的 `AgentSessionStore`** 读同一个目录
    /// —— 与进程重启等价（同 `AgentQuotaPersistenceTests` 的重启口径）。
    func testSessionReadsBackAfterRestartWithUserToolAndAnswer() async throws {
        let loop = AgentLoop(client: ScriptedStreamingClient(twoHopScript()),
                             dispatcher: RecordingDispatcher(),
                             sessionStore: AgentSessionStore(directory: directory),
                             checkpointEvery: 0)
        let result = await loop.run(context: context())
        XCTAssertEqual(result.steps, 2)

        let afterRestart = AgentSessionStore(directory: directory)
            .load(sessionID: "s-dura", workspace: "ws-1")
        let session = try XCTUnwrap(afterRestart.session, "重启后必须读回同一会话")
        XCTAssertEqual(afterRestart.skippedLines, 0)

        let roles = session.turns.map { "\($0.kind.rawValue)/\($0.role)" }
        XCTAssertEqual(roles.first, "model/user", "用户那句原话要能读回（不然回看只剩半边）")
        XCTAssertTrue(roles.contains("model/assistant"), "答复那一跳要在：\(roles)")
        XCTAssertTrue(roles.contains("tool/tool"), "工具那一跳要在：\(roles)")
        XCTAssertTrue(session.turns.contains { $0.toolName == "read_file" },
                      "工具跳要带工具名，回看时才知道调了什么")
    }

    /// 工作区隔离：同一个文件被别的工作区读到 ⇒ **看不到**（不是「空会话」）。
    func testSessionIsInvisibleFromAnotherWorkspaceAfterRestart() async throws {
        let loop = AgentLoop(client: ScriptedStreamingClient(twoHopScript()),
                             dispatcher: RecordingDispatcher(),
                             sessionStore: AgentSessionStore(directory: directory),
                             checkpointEvery: 0)
        _ = await loop.run(context: context())

        let store = AgentSessionStore(directory: directory)
        let other = store.load(sessionID: "s-dura", workspace: "ws-2")
        XCTAssertNil(other.session, "别的工作区不许读到这条会话")
        XCTAssertTrue(other.workspaceMismatch, "要如实说是「别人的会话」，不是「没有会话」")
        XCTAssertEqual(store.sessions(workspace: "ws-2").headers.count, 0)
        XCTAssertEqual(store.sessions(workspace: "ws-1").headers.count, 1)
    }

    // MARK: - ② 审计覆盖模型与工具调用；导出 / 落盘都不带密钥

    /// 两跳对话 ⇒ 两次模型记录 + 一次工具记录，且模型记录带 token（「令牌 / 成本可查」）。
    func testLoopAuditsEveryModelCallAndToolCallWithCostFields() async throws {
        let sink = RecordingSink()
        let loop = AgentLoop(client: ScriptedStreamingClient([
            [.toolCallDelta(index: 0, id: "call-0", name: "read_file",
                            argumentsFragment: #"{"path":"a.txt"}"#),
             .usage(LLMUsage(promptTokens: 11, completionTokens: 7, totalTokens: 18), model: "fake"),
             .finished(reason: "tool_calls"), .done],
            [.textDelta("答完了"),
             .usage(LLMUsage(promptTokens: 3, completionTokens: 5, totalTokens: 8), model: "fake"),
             .finished(reason: "stop"), .done],
        ]), dispatcher: RecordingDispatcher(),
            sessionStore: AgentSessionStore(directory: directory),
            audit: sink, checkpointEvery: 0)
        _ = await loop.run(context: context())

        let models = sink.records.filter { $0.resolvedOrigin == .modelCall }
        let tools = sink.records.filter { $0.resolvedOrigin == .action }
        XCTAssertEqual(models.count, 2, "每一次模型调用都要有一条")
        XCTAssertEqual(tools.count, 1, "每一次工具调用都要有一条")
        XCTAssertEqual(models.map(\.totalTokens), [18, 8], "token 用量要逐跳可查")
        XCTAssertEqual(models.first?.sessionID, "s-dura")
        XCTAssertTrue(tools.first?.sql.contains("read_file") == true)
    }

    /// 密钥形状的片段进了请求摘要 / 附注 ⇒ 落盘那一行与两个导出**都必须是脱敏后的**。
    func testSecretNeverSurvivesOnDiskOrInExports() async throws {
        let sentinel = "sk-durability-9f8e7d6c5b4a"
        let log = AgentAuditLog(directoryURL: directory)
        try await log.append(AgentActionRecord.makeModelCall(
            requestSummary: "用这把 key 试试 \(sentinel)", model: "m-1",
            durationMilliseconds: 12, outcome: .generated,
            detail: "api_key=\(sentinel)", sessionID: "s-dura", hopIndex: 0))

        let raw = try String(contentsOf: await log.fileLocation(), encoding: .utf8)
        XCTAssertFalse(raw.contains(sentinel), "落盘那一行不许带密钥（写入即脱敏）")
        let json = String(data: try await log.exportJSON(), encoding: .utf8) ?? ""
        let csv = try await log.exportCSV()
        XCTAssertFalse(json.contains(sentinel), "JSON 导出不许带密钥")
        XCTAssertFalse(csv.contains(sentinel), "CSV 导出不许带密钥")
        for forbidden in ["\"apiKey\"", "\"api_key\"", "\"password\"", "\"authorization\""] {
            XCTAssertFalse(json.contains(forbidden), "导出里不许出现 \(forbidden) 这种键")
        }
    }

    /// 配置文件里查不到密钥：`agent.json` 里既没有密钥字段，也没有任何密钥值。
    func testConfigurationFileCarriesNoKeyFieldOrKeyValue() async throws {
        let sentinel = "sk-durability-config-0123456789"
        var configuration = AgentConfiguration.default
        configuration.isEnabled = false
        try await AgentConfigurationStore(directoryURL: directory).save(configuration)

        let raw = try String(contentsOf: directory.appendingPathComponent("agent.json"),
                             encoding: .utf8)
        XCTAssertFalse(raw.contains(sentinel), "配置里不许出现密钥值")
        for forbidden in ["\"apiKey\"", "\"api_key\"", "\"password\"", "\"authorization\""] {
            XCTAssertFalse(raw.contains(forbidden), "配置里不许有 \(forbidden) 字段")
        }
        // 档里只有**钥匙串条目键名**（`secretKey`），不是密钥本体 —— 这是设计内的字段。
        XCTAssertTrue(raw.contains("secretKey"), "档里应只有条目键名（键名 ≠ 密钥本体）")
    }

    // MARK: - ③ 不出现第二套实现（源锚点：单测起不了 AppState，但形状在源文本里是确定的）

    /// 循环的审计口必须走 `AppState` 那一处取用点；全 App 不许再出现 `AgentAuditLog.shared`。
    func testChatLoopUsesTheSingleAuditAccessor() throws {
        let app = try String(contentsOf: repoRoot().appendingPathComponent("App/AppState.swift"),
                             encoding: .utf8)
        let loopBody = try block("func makeAgentChatLoop", in: app)
        XCTAssertTrue(loopBody.contains("audit: agentAuditLog"),
                      "循环的审计口要走本类唯一取用点（override ?? shared）")
        XCTAssertFalse(loopBody.contains("audit: AgentAuditLog.shared"),
                       "不许在循环这一处另写 .shared —— 探针改不到，会写进用户真审计")

        for file in try appSources() {
            let text = try String(contentsOf: file, encoding: .utf8)
            XCTAssertEqual(occurrences(of: "AgentAuditLog.shared", in: text), 0,
                           "\(file.lastPathComponent) 里不许直接取 .shared（取用点只许 `agentAuditLog`）")
        }
    }

    /// 会话 / 检查点 / 配额 / 记忆四类存储都在同一个 Application Support 根下（不另开文件体系）。
    func testAllLocalStoresShareTheSameRoot() {
        let root = URL(fileURLWithPath: NSSearchPathForDirectoriesInDomains(
            .applicationSupportDirectory, .userDomainMask, true).first!)
            .appendingPathComponent("DoyahStudio", isDirectory: true)
        let session = AgentSessionStore.defaultDirectory
        XCTAssertTrue(session.path.hasPrefix(root.path + "/"), "会话存储要在同一根下：\(session.path)")
        XCTAssertTrue((AgentCheckpointStore.defaultDirectory.path + "/").hasPrefix(root.path + "/"),
                      "检查点要在同一根下")
        XCTAssertTrue((AgentMemoryStore.defaultDirectory.path + "/").hasPrefix(root.path + "/"),
                      "记忆要在同一根下")
    }

    /// 长上下文的两条接线（压缩 / 检查点）都在同一个装配点上，且检查点按「哪一轮提问」分账。
    func testCompressionAndCheckpointAreWiredOnTheSameChatLoop() throws {
        let app = try String(contentsOf: repoRoot().appendingPathComponent("App/AppState.swift"),
                             encoding: .utf8)
        let loopBody = try block("func makeAgentChatLoop", in: app)
        for needle in ["compressionBudget: AgentContextCompressionBudget()",
                       "checkpointStore: AgentCheckpointStore(directory: AgentCheckpointStore.defaultDirectory)",
                       "quotaLedger: agentQuotaLedgerForNextCall()"] {
            XCTAssertTrue(loopBody.contains(needle), "循环装配点缺 `\(needle)`")
        }
        XCTAssertTrue(app.contains("checkpointScopeID:"), "检查点要按「哪一轮提问」分账（不许跨问题续跑）")
    }

    // MARK: - 夹具

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private func appSources() throws -> [URL] {
        let root = repoRoot().appendingPathComponent("App", isDirectory: true)
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        var result: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension == "swift" { result.append(url) }
        }
        return result
    }

    private func block(_ signature: String, in source: String) throws -> String {
        guard let start = source.range(of: signature) else {
            throw NSError(domain: "durability", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "找不到 \(signature)"])
        }
        let rest = source[start.upperBound...]
        if let end = rest.range(of: "\n    func ") { return String(rest[..<end.lowerBound]) }
        return String(rest)
    }

    private func occurrences(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }
}
