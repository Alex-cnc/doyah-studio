import XCTest
@testable import DoyahCore

/// `G` 片（`FR-AI-31` ④ 调用链可追溯）的机械判据 —— 验收要点 ①②③。
final class AgentChainTests: XCTestCase {

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

    /// 第一次调用要审批（⇒ 审批跳），第二次给答复。
    private final class ApprovalSeekingDispatcher: AgentToolDispatcher, @unchecked Sendable {
        private(set) var calls = 0
        func dispatch(_ invocation: AgentToolInvocation, approvals: Set<String>) -> AgentToolOutcome {
            calls += 1
            return .needsApproval(AgentApprovalRequest(toolName: invocation.name,
                                                      fingerprint: "fp-1",
                                                      payload: invocation.argumentsJSON))
        }
    }

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-chain-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - ① 两跳 + 一次审批 ⇒ 审计里 **4 条同一标识**

    func testTwoHopsPlusOneApprovalShareASingleChainIdentifier() async throws {
        let sink = RecordingSink()
        let client = ScriptedStreamingClient([
            [.toolCallDelta(index: 0, id: "c1", name: "write_file", argumentsFragment: #"{"path":"a.txt","content":"x"}"#),
             .finished(reason: "tool_calls"), .done],
            [.textDelta("那我等你批准"), .finished(reason: "stop"), .done],
        ])
        let loop = AgentLoop(client: client, dispatcher: ApprovalSeekingDispatcher(),
                             sessionStore: AgentSessionStore(directory: directory), audit: sink)
        let context = AgentLoopContext(systemPrompt: "s", userPrompt: "写个文件",
                                       baseRequest: LLMRequest(endpoint: URL(string: "http://127.0.0.1:11434/v1")!,
                                                               model: "m", systemPrompt: "", userPrompt: ""),
                                       sessionID: "s-chain", workspace: "ws")
        _ = await loop.run(context: context)

        // 循环留下：模型(跳0) · 工具(待审批) · 模型(跳1)
        let loopRecords = sink.records
        XCTAssertEqual(loopRecords.count, 3, "两跳 + 一次工具（待审批）⇒ 3 条")
        // 审批跳（批准）由审批那一侧记 —— 同一个链路标识
        let chainID = context.chainID
        try await AgentAuditLog(directoryURL: directory).append(
            AgentActionRecord.makeToolCall(toolName: "write_file", argumentsSummary: #"{"path":"a.txt"}"#,
                                          outcome: .approved, detail: "fp-1",
                                          sessionID: context.sessionID, hopIndex: 0, chainID: chainID))

        let log = AgentAuditLog(directoryURL: directory)
        for record in loopRecords { try await log.append(record) }

        let records = try await log.entries()
        XCTAssertEqual(records.count, 4, "两跳 + 一次审批 ⇒ 4 条")
        XCTAssertEqual(Set(records.map(\.chainID)), [chainID], "**4 条同一个标识**")
        XCTAssertEqual(records.map(\.origin), [.action, .modelCall, .action, .modelCall], "首次写入的是那条审批跳")
        XCTAssertEqual(records.map { $0.hopIndex }, [0, 0, 0, 1])
        XCTAssertTrue(records.allSatisfy { $0.chainID?.isEmpty == false })

        // 导出里也是同一条链（导出的是同一份日志）
        let json = String(data: try await log.exportJSON(), encoding: .utf8) ?? ""
        XCTAssertEqual(json.components(separatedBy: chainID).count - 1, 4, "导出里 4 条都带这个标识")
    }

    // MARK: - ② 跨进程重启仍可串（读回日志重建）

    func testTheChainSurvivesAProcessRestart() async throws {
        let chainID = "chain:restart-me"
        do {
            let log = AgentAuditLog(directoryURL: directory)
            try await log.append(AgentActionRecord.makeModelCall(
                requestSummary: "跳一", model: "m", durationMilliseconds: 1, outcome: .generated,
                endpoint: "e", sessionID: "s", hopIndex: 0, chainID: chainID))
            try await log.append(AgentActionRecord.makeToolCall(
                toolName: "read_file", argumentsSummary: "{}", outcome: .executed,
                sessionID: "s", hopIndex: 0, chainID: chainID))
        }
        // 「重启」= 全新实例、只靠盘上的文件（没有任何内存里的链状态）
        let reopened = AgentAuditLog(directoryURL: directory)
        let records = try await reopened.entries()
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(Set(records.compactMap(\.chainID)), [chainID], "重启后仍串得起")
        // 再追加一条（第三次调用）也进同一条链
        try await reopened.append(AgentActionRecord.makeModelCall(
            requestSummary: "跳二", model: "m", durationMilliseconds: 1, outcome: .generated,
            endpoint: "e", sessionID: "s", hopIndex: 1, chainID: chainID))
        let after = try await AgentAuditLog(directoryURL: directory).entries()
        XCTAssertEqual(Set(after.compactMap(\.chainID)), [chainID])
        XCTAssertEqual(after.map(\.hopIndex), [0, 0, 1])
    }

    /// 缺这个字段的老日志照样读（可选字段，`nil` 而已）。
    func testOldRecordsWithoutAChainIdentifierStillDecode() async throws {
        let log = AgentAuditLog(directoryURL: directory)
        let bare = AgentActionRecord.makeModelCall(requestSummary: "老记录", model: "m",
                                                   durationMilliseconds: 1, outcome: .generated)
        XCTAssertNil(bare.chainID)
        try await log.append(bare)
        let records = try await log.entries()
        XCTAssertEqual(records.count, 1)
        XCTAssertNil(records.first?.chainID)
    }

    // MARK: - ③ 源树判据：**不许出现第二套日志 / 第二个留痕通道**

    private func swiftFiles(in folder: String) -> [(name: String, text: String)] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        guard let enumerator = FileManager.default.enumerator(at: root.appendingPathComponent(folder),
                                                             includingPropertiesForKeys: nil) else { return [] }
        return enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .map { (name: "\(folder)/\($0.lastPathComponent)",
                    text: (try? String(contentsOf: $0, encoding: .utf8)) ?? "") }
    }

    func testThereIsExactlyOneAuditChannel() {
        let files = swiftFiles(in: "Core") + swiftFiles(in: "App")

        // ① 只有一个类型遵循审计口，且它落到既有 `AgentAuditLog`
        let conformances = files.filter { $0.text.contains(": AgentAuditSink") || $0.text.contains(", AgentAuditSink") }
        XCTAssertEqual(conformances.map(\.name).sorted(), ["Core/AgentLoop.swift"],
                       "审计口只许一处遵循（新增通道 = 判红）")
        XCTAssertTrue(files.first { $0.name == "Core/AgentLoop.swift" }?.text.contains("extension AgentAuditLog: AgentAuditSink") == true,
                      "唯一那处遵循必须是把既有 `AgentAuditLog` 接上，而不是自建一个新存储")

        // ② **写入口只有一个**：审计文件只许有**一个**写入者（第二套留痕通道 = 判红）。
        //    注意：文件名在展示 / 语言表里出现不算「第二套日志」—— 判的是**谁在往盘上写**。
        let writers = files.filter { $0.text.contains("agent-audit") && $0.text.contains("forWritingTo") }
        XCTAssertEqual(writers.map(\.name).sorted(), ["Core/AgentAudit.swift"],
                       "审计的写入口只许一处，实际 = \(writers.map(\.name))")

        // ③ 记录只许由 `AgentAudit.swift` 里的工厂产出（别处直接构造 = 绕过唯一留痕口）
        let constructors = files.filter { $0.text.contains("AgentActionRecord(") }
        XCTAssertEqual(constructors.map(\.name).sorted(), ["Core/AgentAudit.swift"],
                       "记录构造点只许一处，实际 = \(constructors.map(\.name))")

        XCTAssertGreaterThan(files.count, 40, "扫到的文件太少 ⇒ 判据自己失效")
    }
}
