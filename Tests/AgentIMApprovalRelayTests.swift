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
}
