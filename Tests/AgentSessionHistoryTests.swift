import XCTest
@testable import DoyahCore

/// 会话**回看**这一层（列表 / 切换 / 会话内搜索）的机械判据。
///
/// 对应概设 §9.1.16 那两条缺口：「无会话列表 / 无历史会话切换」「面板里没有会话内搜索」。
/// 判的是**派生视图**（`AgentSessionSummary` / `AgentSessionReplay` / `AgentTranscriptSearch`），
/// 不是盘上格式 —— 盘上格式由 `AgentSessionTests` 那一族钉着，这里不动它。
final class AgentSessionHistoryTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-session-history-\\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeStore() -> AgentSessionStore { AgentSessionStore(directory: directory) }

    private func turn(_ session: String, _ workspace: String, _ kind: AgentSessionTurn.Kind,
                      _ role: String, _ text: String, seconds: Double,
                      approval: String? = nil) -> AgentSessionTurn {
        AgentSessionTurn(sessionID: session, workspace: workspace, kind: kind, role: role, text: text,
                         toolName: kind == .tool ? "list_dir" : nil,
                         toolCallID: kind == .tool ? "call-1" : nil,
                         approval: approval,
                         at: Date(timeIntervalSince1970: 1_700_000_000 + seconds))
    }

    // MARK: - B1 会话列表：标题 + 时间 + 跳数

    /// 列表要有**跳数**与**最近活动时刻**，且按最近活动倒序（最近聊的排最前）。
    func testSummaryListCarriesTurnCountAndSortsByRecentActivity() throws {
        let store = makeStore()
        try store.createSession(workspace: "ws-1", title: "老会话", sessionID: "s-old",
                                createdAt: Date(timeIntervalSince1970: 1_700_000_001))
        try store.createSession(workspace: "ws-1", title: "新会话", sessionID: "s-new",
                                createdAt: Date(timeIntervalSince1970: 1_700_000_002))
        try store.createSession(workspace: "ws-1", title: "空会话", sessionID: "s-empty",
                                createdAt: Date(timeIntervalSince1970: 1_700_000_003))

        // 老会话 3 跳，但活动时刻更早；新会话 1 跳、时刻更晚 ⇒ 新会话排前
        try store.append(turn("s-old", "ws-1", .model, "user", "问一", seconds: 10))
        try store.append(turn("s-old", "ws-1", .model, "assistant", "答一", seconds: 20))
        try store.append(turn("s-old", "ws-1", .tool, "tool", "list_dir 3 项", seconds: 30))
        try store.append(turn("s-new", "ws-1", .model, "user", "问二", seconds: 100))

        let result = store.summaryList(workspace: "ws-1")
        XCTAssertEqual(result.skippedFiles, 0)
        XCTAssertEqual(result.summaries.map(\.id), ["s-new", "s-old", "s-empty"], "最近活动的在前；没有跳的按创建时刻排")
        XCTAssertEqual(result.summaries.first?.turnCount, 1)
        XCTAssertEqual(result.summaries.first(where: { $0.id == "s-old" })?.turnCount, 3)
        XCTAssertEqual(result.summaries.first(where: { $0.id == "s-old" })?.title, "老会话")
        XCTAssertEqual(result.summaries.first(where: { $0.id == "s-empty" })?.turnCount, 0)
        XCTAssertNil(result.summaries.first(where: { $0.id == "s-empty" })?.lastTurnAt)
    }

    /// 空列表要有**可判的空态信号**（`isEmpty`），且别的会话不算进来。
    func testSummaryListIsEmptyForAnotherWorkspace() throws {
        let store = makeStore()
        try store.createSession(workspace: "ws-1", title: "别人的", sessionID: "s-1")

        let mine = store.summaryList(workspace: "ws-2")
        XCTAssertTrue(mine.isEmpty, "别的工作区的会话看不到 —— 不是「空会话」而是「没有会话」")
        XCTAssertFalse(store.summaryList(workspace: "ws-1").isEmpty)
    }

    /// 坏文件**跳过并计数**，不让整张列表不可用（与 `sessions(workspace:)` 同一口径）。
    func testSummaryListSkipsBrokenFilesAndCountsThem() throws {
        let store = makeStore()
        try store.createSession(workspace: "ws-1", title: "好的", sessionID: "s-good")
        try Data("这不是 JSONL\n".utf8).write(to: directory.appendingPathComponent("broken.jsonl"))

        let result = store.summaryList(workspace: "ws-1")
        XCTAssertEqual(result.summaries.map(\.id), ["s-good"])
        XCTAssertEqual(result.skippedFiles, 1)
    }

    // MARK: - B1 回看：盘上的跳 → 消息流

    /// 三类跳各自落到对的消息角色；空文本不生成空行；审批跳带上结论。
    func testReplayMapsTurnsToMessages() throws {
        let session = AgentSession(
            header: AgentSessionHeader(id: "s-1", workspace: "ws-1", title: "t",
                                       createdAt: Date(timeIntervalSince1970: 1_700_000_000)),
            turns: [
                turn("s-1", "ws-1", .model, "user", "看一下 users 表", seconds: 10),
                turn("s-1", "ws-1", .model, "assistant", "先读表结构", seconds: 20),
                turn("s-1", "ws-1", .tool, "tool", "list_dir 返回 3 项", seconds: 30),
                turn("s-1", "ws-1", .approval, "system", "写入 App/AppState.swift", seconds: 40, approval: "approved"),
                turn("s-1", "ws-1", .model, "system", "上下文已压缩", seconds: 50),
                turn("s-1", "ws-1", .model, "assistant", "   ", seconds: 60)
            ]
        )

        let messages = AgentSessionReplay.messages(from: session)
        XCTAssertEqual(messages.map(\.role), [.user, .assistant, .tool, .tool, .notice],
                       "空文本那条不生成空行")
        XCTAssertEqual(messages.map(\.text), ["看一下 users 表", "先读表结构", "list_dir 返回 3 项",
                                              "写入 App/AppState.swift · approved", "上下文已压缩"])
        XCTAssertTrue(messages.allSatisfy { !$0.isStreaming }, "回看的历史不许显示成还在流式")
    }

    // MARK: - B2 会话内搜索：定位 + 高亮区间

    /// 命中区间按**字符偏移**给，供界面拿同一份偏移去染富文本。
    func testOccurrencesGiveCharacterOffsets() {
        let text = "SQL 语法检查：sql 与 SQL"
        let ranges = AgentTranscriptSearch.occurrences(of: "sql", in: text)
        XCTAssertEqual(ranges.count, 3, "大小写不敏感，三条都算命中")
        for range in ranges {
            let start = text.index(text.startIndex, offsetBy: range.lowerBound)
            let end = text.index(text.startIndex, offsetBy: range.upperBound)
            XCTAssertEqual(text[start..<end].lowercased(), "sql", "区间必须正好盖住命中的那几个字")
        }
    }

    /// 空查询 = 零命中（不是「全部命中」）；没有命中就明说 0。
    func testEmptyQueryAndMissingTextBothGiveZero() {
        let messages = [AgentChatMessage(role: .user, text: "帮我看看这张表"),
                        AgentChatMessage(role: .assistant, text: "先读结构")]
        XCTAssertEqual(AgentTranscriptSearch.total("", in: messages), 0)
        XCTAssertEqual(AgentTranscriptSearch.total("   ", in: messages), 0)
        XCTAssertEqual(AgentTranscriptSearch.total("不存在的词", in: messages), 0)
        XCTAssertNil(AgentTranscriptSearch.firstMatchID("不存在的词", in: messages))
        XCTAssertTrue(AgentTranscriptSearch.hits("不存在的词", in: messages).isEmpty)
    }

    /// 命中跨消息累计，并给出**第一条**（界面据此定位滚动）。
    func testHitsAccumulateAcrossMessagesAndLocateFirst() {
        let first = AgentChatMessage(role: .user, text: "表结构看一下")
        let second = AgentChatMessage(role: .assistant, text: "表结构已读，表结构里有两列")
        let messages = [first, second]

        XCTAssertEqual(AgentTranscriptSearch.total("表结构", in: messages), 3)
        XCTAssertEqual(AgentTranscriptSearch.hits("表结构", in: messages).map(\.messageID), [first.id, second.id])
        XCTAssertEqual(AgentTranscriptSearch.firstMatchID("表结构", in: messages), first.id)
    }

    /// 命中区间**不重叠**：`aaa` 里搜 `aa` 只染第一段（重叠染色会让同一段字叠两层底色，
    /// 而且会让人以为「命中 2 处」）。这里同时钉住「游标必须前进」—— 否则死循环。
    func testOverlappingQueryDoesNotDoublePaintAndTerminates() {
        let ranges = AgentTranscriptSearch.occurrences(of: "aa", in: "aaa")
        XCTAssertEqual(ranges, [0..<2])
    }
}
