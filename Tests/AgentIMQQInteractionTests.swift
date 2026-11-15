import XCTest
@testable import DoyahCore

/// 内联审批按钮（需求 ⑧「平台支持时改为内联按钮，码保留为兜底」）：
/// 按钮数据由我们定、点击必须 ACK、按钮与「批准 <码>」走**同一条**票据判定。
final class AgentIMQQInteractionTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dsh-im-btn-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    // MARK: - 按钮面板

    func testKeyboardCarriesApproveAndRejectWithCode() throws {
        let json = try XCTUnwrap(ProvisionerSupport.jsonObject(
            AgentIMQQKeyboard.approval(code: "c04c", language: .simplifiedChinese)))
        let content = try XCTUnwrap(json["content"] as? [String: Any])
        let rows = try XCTUnwrap(content["rows"] as? [[String: Any]])
        let buttons = try XCTUnwrap(rows.first?["buttons"] as? [[String: Any]])
        XCTAssertEqual(buttons.count, 2)
        let datas = buttons.compactMap { ($0["action"] as? [String: Any])?["data"] as? String }
        XCTAssertEqual(datas, ["approve:c04c", "reject:c04c"])
        let labels = buttons.compactMap { ($0["render_data"] as? [String: Any])?["label"] as? String }
        XCTAssertEqual(labels, ["批准", "拒绝"])
    }

    // MARK: - 按钮数据 → 决定

    func testButtonDataBecomesDecision() {
        XCTAssertEqual(AgentIMQQButtonData.decision(from: "approve:c04c")?.approve, true)
        XCTAssertEqual(AgentIMQQButtonData.decision(from: "APPROVE:C04C")?.code, "c04c")
        XCTAssertEqual(AgentIMQQButtonData.decision(from: "reject:ab12")?.approve, false)
    }

    func testMalformedButtonDataNeverApproves() {
        XCTAssertNil(AgentIMQQButtonData.decision(from: "approve:"), "没有码不许放行")
        XCTAssertNil(AgentIMQQButtonData.decision(from: "approve:zz"), "非十六进制不算码")
        XCTAssertNil(AgentIMQQButtonData.decision(from: "approve:c04c00ff00"), "超 8 位不算码")
        XCTAssertNil(AgentIMQQButtonData.decision(from: "点击批准"), "认不出的数据不猜")
    }

    // MARK: - 帧解析

    func testParsesInteractionFrame() throws {
        let data: [String: Any] = [
            "id": "inter-1",
            "chat_type": 0,
            "user_openid": "u-1",
            "data": ["type": 11, "resolved": ["button_data": "approve:c04c"]]
        ]
        let parsed = try XCTUnwrap(AgentIMQQInteractionParser.parse(data))
        XCTAssertEqual(parsed.interactionID, "inter-1")
        XCTAssertEqual(parsed.buttonData, "approve:c04c")
        XCTAssertEqual(parsed.chatKind, .c2c)
        XCTAssertEqual(parsed.chatID, "u-1")
    }

    func testInteractionWithoutButtonDataIsNotGuessed() {
        let data: [String: Any] = ["id": "inter-2", "user_openid": "u-1", "data": ["type": 11]]
        XCTAssertNil(AgentIMQQInteractionParser.parse(data))
    }

    // MARK: - ACK

    private final class FakeClient: AgentIMInteractionHTTPClient, @unchecked Sendable {
        private let lock = NSLock()
        private var _puts: [(String, String)] = []
        private let response: AgentIMHTTPResponse
        init(response: AgentIMHTTPResponse = AgentIMHTTPResponse(status: 200, body: "{}")) {
            self.response = response
        }
        var puts: [(String, String)] { lock.lock(); defer { lock.unlock() }; return _puts }
        func put(_ url: URL, payload: String, headers: [String: String]) async throws -> AgentIMHTTPResponse {
            lock.lock(); _puts.append((url.absoluteString, payload)); lock.unlock()
            return response
        }
    }

    func testAckUsesPutOnInteractionsEndpoint() async {
        let client = FakeClient()
        let acker = AgentIMQQInteractionAcker(
            client: client, environment: .sandbox,
            token: { AgentIMQQToken(value: "tok", expiresIn: 7200, obtainedAt: Date()) })
        let outcome = await acker.ack(AgentIMInteraction(interactionID: "inter-9",
                                                         buttonData: "approve:c04c",
                                                         chatID: "u-1", userID: "u-1", chatKind: .c2c))
        XCTAssertTrue(outcome.isDelivered)
        XCTAssertEqual(client.puts.count, 1)
        let (url, payload) = client.puts[0]
        XCTAssertTrue(url.hasSuffix("/interactions/inter-9"), url)
        XCTAssertEqual(payload, #"{"code":0}"#)
    }

    func testAckRefusesUnsafeInteractionID() async {
        let client = FakeClient()
        let acker = AgentIMQQInteractionAcker(
            client: client, environment: .sandbox,
            token: { AgentIMQQToken(value: "tok", expiresIn: 7200, obtainedAt: Date()) })
        let outcome = await acker.ack(AgentIMInteraction(interactionID: "../../etc/passwd",
                                                         buttonData: "approve:c04c",
                                                         chatID: "u-1", userID: "u-1", chatKind: .c2c))
        XCTAssertEqual(outcome, .notReady(code: "badInteractionID"), "外部输入不许拼进路径")
        XCTAssertTrue(client.puts.isEmpty)
    }
    /// **`action.type` 必须是 1（回调）**：取 2 是链接跳转，带 data 也不推 `INTERACTION_CREATE`
    /// —— 真机上表现为「点了没反应、日志里零事件」（2026-11-14 实测：历史全量 0 条按钮事件）。
    func testButtonsUseCallbackActionNotLink() throws {
        let json = AgentIMQQKeyboard.approval(code: "fd20", language: .simplifiedChinese)
        let root = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        let rows = (root?["content"] as? [String: Any])?["rows"] as? [[String: Any]]
        let buttons = rows?.first?["buttons"] as? [[String: Any]]
        XCTAssertEqual(buttons?.count, 2, "审批必须是两颗按钮")
        for button in buttons ?? [] {
            let action = button["action"] as? [String: Any]
            XCTAssertEqual(action?["type"] as? Int, 1, "回调按钮的 action.type 必须是 1；2 = 链接，平台不会推事件")
            XCTAssertEqual((action?["permission"] as? [String: Any])?["type"] as? Int, 2,
                           "permission.type = 2 才是所有人可点")
            XCTAssertFalse((action?["data"] as? String ?? "").isEmpty, "回调必须带 data")
        }
    }
}
