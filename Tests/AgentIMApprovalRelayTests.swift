import XCTest
@testable import DoyahCore
@testable import DoyahStudioApp

/// **审批请求必须送到手机**（2026-11-13 真机：确认只弹在 PC 端，手机上等了 20 多分钟）。
///
/// 三件事分开验：① 桌面发起的一轮停在审批上时，继电器被叫醒、票据登记；② 那条通知带码 + 两颗按钮；
/// ③ 「最后一条聊天」落盘得住（否则重启后桌面发起的审批又无处可去）。
@MainActor
final class AgentIMApprovalRelayTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dsh-im-relay-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    // MARK: - ① 桌面发起的一轮：继电器要响

    func testDesktopRunApprovalReachesTheRelay() async {
        let model = AgentChatModel()
        var notices: [AgentChatModel.IMApprovalNotice] = []
        model.imApprovalRelay = { notices.append($0) }

        await model.observe(.approvalRequested(name: "run_shell",
                                               fingerprint: "c04c00ff11",
                                               preview: "npm test",
                                               baseDigest: ""))

        XCTAssertEqual(notices.count, 1, "桌面跑的一轮停在审批上，手机必须收到一条")
        XCTAssertEqual(notices.first?.code, "c04c", "码 = 指纹前四位（同一张单稳定）")
        XCTAssertTrue(notices.first?.tool.contains("npm test") == true, "要带上在跑的是哪条命令")
    }

    func testApprovalRegistersTicketEvenWithoutProgressReporter() async {
        let model = AgentChatModel()
        model.imApprovalRelay = { _ in }
        await model.observe(.approvalRequested(name: "run_shell",
                                               fingerprint: "ab120001",
                                               preview: "ls",
                                               baseDigest: ""))
        XCTAssertNotNil(model.imApprovalTickets["ab12"], "没有播报器的轮次也要能凭码放行")
    }

    func testNoRelayMeansNoCrash() async {
        let model = AgentChatModel()   // 没接线（IM 没配）
        await model.observe(.approvalRequested(name: "run_shell",
                                               fingerprint: "ffee0001",
                                               preview: "ls",
                                               baseDigest: ""))
        XCTAssertNotNil(model.imApprovalTickets["ffee"], "没接线也别把票据丢了")
    }

    // MARK: - ② 通知内容：码 + 两颗按钮

    func testApprovalTextCarriesCodeAndBothButtons() {
        let text = LocalizedStrings.format(.agentIMApprovalRequest, language: .simplifiedChinese,
                                           "run_shell：npm test", "c04c", "c04c")
        XCTAssertTrue(text.contains("c04c"))
        XCTAssertTrue(text.contains("npm test"))
        XCTAssertTrue(text.contains("批准"), text)

        let keyboard = AgentIMQQKeyboard.approval(code: "c04c", language: .simplifiedChinese)
        XCTAssertTrue(keyboard.contains("approve:c04c"))
        XCTAssertTrue(keyboard.contains("reject:c04c"))
    }

    // MARK: - ③ 最后一条聊天落盘

    func testLastChatSurvivesRestart() {
        let store = AgentIMLastChatStore(directory: root)
        XCTAssertNil(store.load(), "没记过就是没有 —— 不许猜一个目标出来")
        store.remember(kind: .c2c, openID: "user-9")
        let loaded = store.load()
        XCTAssertEqual(loaded?.openID, "user-9")
        XCTAssertEqual(loaded?.kind, .c2c)
    }

    func testCorruptLastChatIsTreatedAsAbsent() throws {
        try Data("not json".utf8).write(to: root.appendingPathComponent("im-last-chat.json"))
        XCTAssertNil(AgentIMLastChatStore(directory: root).load())
    }

    // MARK: - ④ 队列条目带着键盘走

    func testQueueEntryKeepsKeyboardThroughDisk() throws {
        let queue = AgentIMResultQueue(directory: root)
        let keyboard = AgentIMQQKeyboard.approval(code: "c04c", language: .english)
        let entry = try queue.enqueue(chatID: "c1", text: "等确认", target: .init(kind: .c2c, openID: "c1"),
                                      keyboardJSON: keyboard)
        XCTAssertEqual(entry.keyboardJSON, keyboard)
        let pending = queue.pending()
        XCTAssertEqual(pending.first?.keyboardJSON, keyboard, "落盘再读回来不许把按钮弄丢")
    }
    /// 退路：`im-last-chat.json` 还没有（本版新加）时，退到 `im-sessions.json` 的**唯一**候选。
    func testFallsBackToTheOnlySessionWhenNoLastChatRecorded() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("last-chat-fallback-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let sessions = ["qq:51F9D1286CB793F5F7E7016DF8E45C9A": "780B97A6-212D-4B95-B31C-0389801EDAA0",
                        "qq:selftest": "778DD7BA-9396-444E-A1DD-9E88FB1FE314"]
        try JSONSerialization.data(withJSONObject: sessions)
            .write(to: dir.appendingPathComponent("im-sessions.json"))

        let chat = AgentIMLastChatStore(directory: dir).load()
        XCTAssertEqual(chat?.openID, "51F9D1286CB793F5F7E7016DF8E45C9A",
                       "只剩一条真聊天时应当认出它（自测那条不算）")
        XCTAssertEqual(chat?.kind, .c2c)
    }

    /// 多于一条候选 ⇒ **不猜**（推错人比不推更糟）。
    func testDoesNotGuessWhenSeveralSessionsExist() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("last-chat-many-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let sessions = ["qq:AAA": "1", "qq:BBB": "2"]
        try JSONSerialization.data(withJSONObject: sessions)
            .write(to: dir.appendingPathComponent("im-sessions.json"))

        XCTAssertNil(AgentIMLastChatStore(directory: dir).load(),
                     "两条候选还挑一条 = 猜；这条必须返回 nil")
    }

    /// 落盘的那条**优先**于退路。
    func testRecordedLastChatWinsOverSessions() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("last-chat-priority-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let sessions = ["qq:AAA": "1", "qq:BBB": "2"]
        try JSONSerialization.data(withJSONObject: sessions)
            .write(to: dir.appendingPathComponent("im-sessions.json"))
        let store = AgentIMLastChatStore(directory: dir)
        store.remember(kind: .group, openID: "GROUP-1")

        let chat = store.load()
        XCTAssertEqual(chat?.openID, "GROUP-1", "有落盘记录时必须用它，不许被退路顶掉")
        XCTAssertEqual(chat?.kind, .group)
    }
    // MARK: - 刷屏闸门（2026-11-14 真机：一串「没有待批的单」+ 两张一样的卡）

    func testSameApprovalIsPushedOnceWithinItsLife() {
        var gate = AgentIMFloodGate()
        let t0 = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(gate.shouldPushApproval(code: "6b1b", at: t0), "第一次必须推")
        XCTAssertFalse(gate.shouldPushApproval(code: "6b1b", at: t0.addingTimeInterval(30)),
                       "同一张单 30 秒后再要确认，不许再推一张卡")
        XCTAssertTrue(gate.shouldPushApproval(code: "6b1b", at: t0.addingTimeInterval(901)),
                      "过了票据寿命（900 秒）就该当新单推")
        XCTAssertTrue(gate.shouldPushApproval(code: "b726", at: t0.addingTimeInterval(1)),
                      "**别的单**不许被前一张挡住")
    }

    func testInteractionRetryIsAckedButAnsweredOnce() {
        var gate = AgentIMFloodGate()
        XCTAssertTrue(gate.shouldReplyToInteraction(id: "IX-1"), "第一次点击要回话")
        for _ in 0..<19 {
            XCTAssertFalse(gate.shouldReplyToInteraction(id: "IX-1"),
                           "平台重试同一个 interaction_id ⇒ 只 ACK，不再回话（否则手机上 20 条一样的话）")
        }
        XCTAssertTrue(gate.shouldReplyToInteraction(id: "IX-2"), "新的点击另算")
    }

    func testGateForgetsOldestWhenMemoryIsFull() {
        var gate = AgentIMFloodGate(interactionMemory: 3)
        for i in 0..<3 { _ = gate.shouldReplyToInteraction(id: "IX-\(i)") }
        _ = gate.shouldReplyToInteraction(id: "IX-3")
        XCTAssertTrue(gate.shouldReplyToInteraction(id: "IX-0"),
                      "记忆只有 3 个时，最旧的那个该被忘掉（否则长跑一轮就把记忆吃满）")
        XCTAssertFalse(gate.shouldReplyToInteraction(id: "IX-3"), "最近那个还在记忆里")
    }
}
