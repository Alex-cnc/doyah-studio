import XCTest
@testable import DoyahCore

/// QQ 扫码接入的协议层判据（`FR-AGT-LINK-CHAN-003`）。
///
/// 盯住三处：**只认这四种事件**（噪声不许当事件）、**缺一半凭据算没成**（不许落库半套）、
/// **成功即定稿**（新码 / 过期通知不许把成功打回去）。
final class AgentIMQRLoginTests: XCTestCase {

    // MARK: - 解析

    func testParsesQRURL() {
        XCTAssertEqual(AgentIMQRLogin.parse(line: #"{"event":"qr","url":"https://q.qq.com/x"}"#),
                       .qr(url: "https://q.qq.com/x"))
    }

    func testParsesSuccessWithOwnerOpenID() {
        let line = #"{"event":"success","appId":"10293","appSecret":"s3cr3t","openId":"A1B2"}"#
        XCTAssertEqual(AgentIMQRLogin.parse(line: line),
                       .succeeded(appID: "10293", appSecret: "s3cr3t", ownerOpenID: "A1B2"))
    }

    func testSuccessWithoutOwnerOpenIDIsStillSuccess() {
        let line = #"{"event":"success","appId":"10293","appSecret":"s3cr3t","openId":""}"#
        XCTAssertEqual(AgentIMQRLogin.parse(line: line),
                       .succeeded(appID: "10293", appSecret: "s3cr3t", ownerOpenID: nil))
    }

    func testHalfCredentialsAreFailureNotSuccess() {
        // 只有 AppID 没有 Secret ⇒ 没成（落进去也连不上）
        let line = #"{"event":"success","appId":"10293","appSecret":""}"#
        guard case .failed(let reason)? = AgentIMQRLogin.parse(line: line) else {
            return XCTFail("缺 AppSecret 必须判失败")
        }
        XCTAssertTrue(reason.contains("AppID") || reason.contains("AppSecret"))
    }

    func testIgnoresNoiseAndBrokenJSON() {
        for line in ["", "   ", "npm WARN something", "{\"event\":\"qr\"}", "{\"event\":", "[]", "{\"event\":\"other\"}"] {
            XCTAssertNil(AgentIMQRLogin.parse(line: line), "噪声不该被当成事件：\(line)")
        }
    }

    func testParsesExpiredAndFailed() {
        XCTAssertEqual(AgentIMQRLogin.parse(line: #"{"event":"expired"}"#), .expired)
        XCTAssertEqual(AgentIMQRLogin.parse(line: #"{"event":"failed","error":"找不到连接器"}"#),
                       .failed(reason: "找不到连接器"))
    }

    // MARK: - 状态推进

    func testQRMovesToShowing() {
        XCTAssertEqual(AgentIMQRLogin.next(.idle, event: .qr(url: "https://a")), .showing(qr: "https://a"))
    }

    func testExpiredKeepsLastQR() {
        let expired = AgentIMQRLogin.next(.showing(qr: "https://a"), event: .expired)
        XCTAssertEqual(expired, .expired(lastQR: "https://a"))
        // 过期之后又来一张新码 ⇒ 回到出码中
        XCTAssertEqual(AgentIMQRLogin.next(expired, event: .qr(url: "https://b")), .showing(qr: "https://b"))
    }

    func testSucceededIsFinal() {
        let success = AgentIMQRLoginState.succeeded(appID: "1", appSecret: "s", ownerOpenID: nil)
        XCTAssertEqual(AgentIMQRLogin.next(success, event: .qr(url: "https://late")), success)
        XCTAssertEqual(AgentIMQRLogin.next(success, event: .expired), success)
        XCTAssertTrue(success.isTerminal)
        XCTAssertFalse(success.allowsRestart == false, "成功之后允许重来（换个机器人）")
    }

    func testShowingBlocksRestartButFailureAllowsIt() {
        XCTAssertFalse(AgentIMQRLoginState.showing(qr: "https://a").allowsRestart, "出码中不许重复起进程")
        XCTAssertTrue(AgentIMQRLoginState.failed(reason: "x").allowsRestart)
        XCTAssertTrue(AgentIMQRLoginState.idle.allowsRestart)
    }

    func testCredentialsOnlyComeFromSuccess() {
        XCTAssertNil(AgentIMQRLogin.credentials(from: .showing(qr: "https://a")))
        let success = AgentIMQRLoginState.succeeded(appID: "1", appSecret: "s", ownerOpenID: "o")
        XCTAssertEqual(AgentIMQRLogin.credentials(from: success)?.appID, "1")
        XCTAssertEqual(AgentIMQRLogin.credentials(from: success)?.appSecret, "s")
    }

    // MARK: - 起桥

    func testLaunchUsesTheBundledBridgePathAndNothingElse() {
        let args = AgentIMQRLogin.launchArguments(bridgePath: "/repo/Scripts/qq-qr-bridge.mjs")
        XCTAssertEqual(args, ["/repo/Scripts/qq-qr-bridge.mjs"], "起桥只传脚本路径（不留参数注入面）")
        XCTAssertEqual(AgentIMQRLogin.bridgeRelativePath, "Scripts/qq-qr-bridge.mjs")
    }

    func testEnvironmentInjectsConnectorEntryOnlyWhenGiven() {
        let inherited = ["PATH": "/usr/bin"]
        XCTAssertEqual(AgentIMQRLogin.environment(connectorEntry: nil, inherited: inherited), inherited)
        XCTAssertEqual(AgentIMQRLogin.environment(connectorEntry: "", inherited: inherited), inherited)
        let withEntry = AgentIMQRLogin.environment(connectorEntry: "/x/index.js", inherited: inherited)
        XCTAssertEqual(withEntry["DOYAH_QQ_CONNECTOR_ENTRY"], "/x/index.js")
        XCTAssertEqual(withEntry["PATH"], "/usr/bin")
    }

    // MARK: - 桥脚本真的在盘上

    func testBridgeScriptExistsAndDeclaresTheProtocol() throws {
        let path = FileManager.default.currentDirectoryPath + "/" + AgentIMQRLogin.bridgeRelativePath
        let source = try String(contentsOfFile: path, encoding: .utf8)
        XCTAssertTrue(source.contains("startQrConnect"), "桥必须用官方连接器，不许自己拼扫码协议")
        for event in ["\"qr\"", "\"expired\"", "\"success\"", "\"failed\""] {
            XCTAssertTrue(source.contains(event), "桥必须吐 \(event) 事件")
        }
    }
}
