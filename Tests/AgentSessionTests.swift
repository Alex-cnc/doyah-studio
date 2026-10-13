import XCTest
@testable import DoyahCore

/// `FR-AI-17`（对话会话按工作区持久化）的机械判据 —— 照 SRS 五条验收要点逐条落。
final class AgentSessionTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-session-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeStore() -> AgentSessionStore { AgentSessionStore(directory: directory) }

    private func turn(_ session: String, _ workspace: String, _ kind: AgentSessionTurn.Kind,
                      _ role: String, _ text: String, seconds: Double,
                      tool: String? = nil, approval: String? = nil) -> AgentSessionTurn {
        AgentSessionTurn(sessionID: session, workspace: workspace, kind: kind, role: role, text: text,
                         toolName: tool, toolCallID: tool == nil ? nil : "call-\(tool!)",
                         approval: approval, at: Date(timeIntervalSince1970: 1_700_000_000 + seconds))
    }

    // MARK: - ① 同一工作区重启后读回同一会话（条数与顺序逐条一致）

    func testRoundTripAfterRestartKeepsOrderAndCount() throws {
        let store = makeStore()
        let header = try store.createSession(workspace: "ws-1", title: "第一次对话", sessionID: "s-1")

        // 故意乱序写入（时刻与写入次序不一致），读回必须按时刻排
        let first = turn("s-1", "ws-1", .model, "user", "帮我看下 users 表", seconds: 10)
        let second = turn("s-1", "ws-1", .model, "assistant", "好的，先读表结构", seconds: 20)
        let third = turn("s-1", "ws-1", .tool, "tool", "list_dir 返回 3 项", seconds: 30, tool: "list_dir")
        try store.append(second)
        try store.append(third)
        try store.append(first)

        // 「重启」= 新实例、新对象，只靠盘上文件
        let reopened = makeStore().load(sessionID: "s-1", workspace: "ws-1")
        XCTAssertEqual(reopened.skippedLines, 0)
        XCTAssertFalse(reopened.workspaceMismatch)
        XCTAssertEqual(reopened.session?.header, header)
        XCTAssertEqual(reopened.session?.turns.count, 3, "条数要一致")
        XCTAssertEqual(reopened.session?.turns, [first, second, third], "顺序与字段都要逐条一致")
    }

    /// 同一时刻的跳**保持写入次序**（不许被重排成随机序）。
    func testTurnsAtTheSameInstantKeepTheirWriteOrder() throws {
        let store = makeStore()
        try store.createSession(workspace: "ws-1", title: "t", sessionID: "s-2")
        let a = turn("s-2", "ws-1", .model, "user", "A", seconds: 5)
        let b = turn("s-2", "ws-1", .model, "user", "B", seconds: 5)
        let c = turn("s-2", "ws-1", .model, "user", "C", seconds: 5)
        for item in [a, b, c] { try store.append(item) }
        XCTAssertEqual(store.load(sessionID: "s-2", workspace: "ws-1").session?.turns.map(\.text), ["A", "B", "C"])
    }

    // MARK: - ② 换工作区看不到别的会话

    func testSessionsAreScopedByWorkspace() throws {
        let store = makeStore()
        try store.createSession(workspace: "ws-1", title: "一号", sessionID: "s-a", createdAt: Date(timeIntervalSince1970: 1))
        try store.createSession(workspace: "ws-2", title: "二号", sessionID: "s-b", createdAt: Date(timeIntervalSince1970: 2))
        try store.append(turn("s-a", "ws-1", .model, "user", "只在 ws-1", seconds: 1))
        try store.append(turn("s-b", "ws-2", .model, "user", "只在 ws-2", seconds: 1))

        XCTAssertEqual(store.load(sessionID: "s-a", workspace: "ws-1").session?.turns.count, 1)
        XCTAssertNil(store.load(sessionID: "s-a", workspace: "ws-2").session, "别的工作区看不到")
        XCTAssertTrue(store.load(sessionID: "s-a", workspace: "ws-2").workspaceMismatch,
                      "「看不到」要与「空会话」分得开")

        let list1 = store.sessions(workspace: "ws-1")
        let list2 = store.sessions(workspace: "ws-2")
        XCTAssertEqual(list1.headers.map(\.id), ["s-a"])
        XCTAssertEqual(list2.headers.map(\.id), ["s-b"])
        XCTAssertEqual(list1.skippedFiles, 0)

        // 归属不符的跳**写不进去**（不静默落到别人家的会话里）
        XCTAssertFalse(try store.append(turn("s-a", "ws-2", .model, "user", "越界", seconds: 2)))
        XCTAssertEqual(store.load(sessionID: "s-a", workspace: "ws-1").session?.turns.count, 1)
    }

    // MARK: - ③ 导出按时间顺序回放，且模型跳 / 工具跳 / 审批跳都在

    func testExportReplaysInTimeOrderWithAllThreeKinds() throws {
        let store = makeStore()
        try store.createSession(workspace: "ws-1", title: "三类跳", sessionID: "s-3")
        let model = turn("s-3", "ws-1", .model, "assistant", "我想调用 write_file", seconds: 30)
        let tool = turn("s-3", "ws-1", .tool, "tool", "write_file 结果：已写", seconds: 40, tool: "write_file")
        let approval = turn("s-3", "ws-1", .approval, "system", "用户批准 write_file", seconds: 20, tool: "write_file", approval: "approved")
        for item in [model, tool, approval] { try store.append(item) }

        guard let session = store.load(sessionID: "s-3", workspace: "ws-1").session else { return XCTFail("要读得回") }
        let data = try store.export(session)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let exported = object?["turns"] as? [[String: Any]]

        XCTAssertEqual(exported?.count, 3)
        XCTAssertEqual(exported?.compactMap { $0["kind"] as? String }, ["approval", "model", "tool"], "导出必须按时间顺序回放")
        XCTAssertEqual(Set(exported?.compactMap { $0["kind"] as? String } ?? []), ["model", "tool", "approval"],
                       "三类跳一个都不能丢")
        XCTAssertEqual(object?["workspace"] as? String, "ws-1")
        XCTAssertEqual(exported?.first?["approval"] as? String, "approved")
        XCTAssertEqual(exported?.last?["toolName"] as? String, "write_file")
    }

    // MARK: - ④ 键集合是白名单（结构上没有行数据与密钥的落点）

    func testKeySetsAreExactlyTheDeclaredWhitelists() throws {
        let turnKeys = Set(Mirror(reflecting: turn("s", "w", .tool, "tool", "x", seconds: 1, tool: "read_file"))
            .children.compactMap { $0.label })
        XCTAssertEqual(turnKeys, AgentSessionTurn.keyWhitelist)
        XCTAssertEqual(Set(Mirror(reflecting: AgentSessionHeader(id: "i", workspace: "w", title: "t"))
            .children.compactMap { $0.label }), AgentSessionHeader.keyWhitelist)

        let encoded = try AgentSessionStore.encoder.encode(turn("s", "w", .tool, "tool", "x", seconds: 1, tool: "read_file"))
        let keys = Set((try JSONSerialization.jsonObject(with: encoded) as? [String: Any] ?? [:]).keys)
        for forbidden in ["rows", "data", "apiKey", "token", "result", "content"] {
            XCTAssertFalse(keys.contains(forbidden), "会话跳里不许有 `\(forbidden)` 这种字段")
        }
    }

    // MARK: - ⑤ 坏会话文件跳过并计数（整张列表仍可用）；坏行同理

    func testCorruptFilesAndLinesAreSkippedAndCounted() throws {
        let store = makeStore()
        try store.createSession(workspace: "ws-1", title: "好会话", sessionID: "s-good")
        try store.append(turn("s-good", "ws-1", .model, "user", "好的一跳", seconds: 1))

        // 坏文件乙：完全不是 JSONL
        let garbage = directory.appendingPathComponent("broken.jsonl")
        try "这不是会话文件".write(to: garbage, atomically: true, encoding: .utf8)
        // 坏文件丙：只有跳、没有头一行
        let headless = directory.appendingPathComponent("headless.jsonl")
        let orphan = try AgentSessionStore.encoder.encode(turn("s-x", "ws-1", .model, "user", "没有头", seconds: 1))
        try (String(data: orphan, encoding: .utf8) ?? "").appending("\n").write(to: headless, atomically: true, encoding: .utf8)

        let list = store.sessions(workspace: "ws-1")
        XCTAssertEqual(list.headers.map(\.id), ["s-good"], "坏文件不许让整张列表不可用")
        XCTAssertEqual(list.skippedFiles, 2, "跳过了几个文件要如实报")

        // 好会话里插一行坏 JSON ⇒ 跳过并计数，其余照读
        let url = store.fileURL(sessionID: "s-good")
        let text = try String(contentsOf: url, encoding: .utf8)
        try (text + "坏行不是 JSON\n").write(to: url, atomically: true, encoding: .utf8)
        let loaded = store.load(sessionID: "s-good", workspace: "ws-1")
        XCTAssertEqual(loaded.skippedLines, 1)
        XCTAssertEqual(loaded.session?.turns.count, 1, "坏行不许让整个会话读不出来")
    }
}
