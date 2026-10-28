import XCTest
@testable import DoyahCore

/// `FR-AGT-LINK-CHAN-003` **★0 凭据口径**的判据（2026-10-28 主人拍板）：
/// 「既然是 QQ 通道，为什么还要用户填 wss 地址？只要 AppID + AppSecret 就行。」
///
/// 这里钉的是那条链：`AppID + Secret + 环境` → 换 token → 问官方要网关地址 → 官方 `op` 码握手，
/// 以及**每一档失败都要说得出是哪一种**（401 与 403 不是同一件事，网络不通不是凭据错）。
/// 判据全用假 HTTP（不碰网络）：真连 QQ 要凭据，那半记 blocked，不在这里装绿。
final class AgentIMQQProvisioningTests: XCTestCase {

    // MARK: - 假 HTTP 客户端

    private struct StubError: Error {}

    private final class FakeHTTP: AgentIMQQHTTPClient, @unchecked Sendable {

        struct Call: Equatable {
            var method: String
            var url: String
            var body: [String: String]?
            var headers: [String: String]
        }

        private let lock = NSLock()
        private var _calls: [Call] = []

        var postHandler: (URL, [String: String]) throws -> AgentIMHTTPResponse = { _, _ in
            AgentIMHTTPResponse(status: 200, body: #"{"access_token":"tok-abc","expires_in":"7200"}"#)
        }
        var getHandler: (URL) throws -> AgentIMHTTPResponse = { _ in
            AgentIMHTTPResponse(status: 200, body: #"{"url":"wss://api.sgroup.qq.com/websocket/"}"#)
        }
        var postCount: Int {
            lock.lock(); defer { lock.unlock() }
            return _calls.filter { $0.method == "POST" }.count
        }
        var getCount: Int {
            lock.lock(); defer { lock.unlock() }
            return _calls.filter { $0.method == "GET" }.count
        }
        var calls: [Call] { lock.lock(); defer { lock.unlock() }; return _calls }

        func post(_ url: URL, json body: [String: String],
                  headers: [String: String]) async throws -> AgentIMHTTPResponse {
            lock.lock()
            _calls.append(Call(method: "POST", url: url.absoluteString, body: body, headers: headers))
            lock.unlock()
            return try postHandler(url, body)
        }

        func get(_ url: URL, headers: [String: String]) async throws -> AgentIMHTTPResponse {
            lock.lock()
            _calls.append(Call(method: "GET", url: url.absoluteString, body: nil, headers: headers))
            lock.unlock()
            return try getHandler(url)
        }
    }

    private func provisioner(_ client: FakeHTTP, at now: Date) -> AgentIMQQProvisioner {
        AgentIMQQProvisioner(client: client, now: { now })
    }

    private let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - 一、不填地址也能配齐：token + 网关都由程序取

    func testPrepareFetchesTokenAndGatewayWithoutAnyAddressFromUser() async throws {
        let client = FakeHTTP()
        let provisioning = try await provisioner(client, at: fixedNow)
            .prepare(appID: "102030405", secret: "s3cr3t", environment: .production)

        XCTAssertEqual(provisioning.token.value, "tok-abc")
        XCTAssertEqual(provisioning.token.expiresIn, 7200, "官方把 expires_in 给成字符串，也要读得出")
        XCTAssertEqual(provisioning.gateway.url.absoluteString, "wss://api.sgroup.qq.com/websocket/")
        XCTAssertEqual(provisioning.gateway.source, .discovered)
        XCTAssertNil(provisioning.gateway.note)

        // 取 token 打的是官方那一格，带的是 appId + clientSecret；用户一个地址都没填。
        XCTAssertEqual(client.calls.first?.url, "https://bots.qq.com/app/getAppAccessToken")
        XCTAssertEqual(client.calls.first?.body, ["appId": "102030405", "clientSecret": "s3cr3t"])
        // 取网关带的是官方鉴权头（`QQBot <token>`），不是本侧那套 HMAC。
        XCTAssertEqual(client.calls.last?.url, "https://api.sgroup.qq.com/gateway")
        XCTAssertEqual(client.calls.last?.headers["Authorization"], "QQBot tok-abc")
    }

    func testSandboxEnvironmentUsesSandboxEndpoints() async throws {
        let client = FakeHTTP()
        client.getHandler = { url in
            // 沙箱下 REST 取不到 ⇒ 也要用**沙箱**的固定地址，不能回落到正式环境（回声都收不到）。
            throw StubError()
        }
        let provisioning = try await provisioner(client, at: fixedNow)
            .prepare(appID: "1", secret: "s", environment: .sandbox)
        XCTAssertEqual(client.calls.last?.url, "https://sandbox.api.sgroup.qq.com/gateway")
        XCTAssertEqual(provisioning.gateway.url.absoluteString, "wss://sandbox.api.sgroup.qq.com/websocket/")
        XCTAssertEqual(provisioning.gateway.source, .fallback)
        XCTAssertEqual(provisioning.gateway.note, "networkFailed")
    }

    // MARK: - 二、失败要说得出是哪一种（反例成对）

    func testStatus401IsCredentialProblemNotNetworkProblem() async {
        let client = FakeHTTP()
        client.postHandler = { _, _ in
            AgentIMHTTPResponse(status: 401, body: #"{"code":100016,"message":"invalid appid or secret"}"#)
        }
        do {
            _ = try await provisioner(client, at: fixedNow)
                .prepare(appID: "1", secret: "wrong", environment: .production)
            XCTFail("401 必须抛错，不许当成拿到了 token")
        } catch let problem as AgentIMQQProvisionProblem {
            XCTAssertEqual(problem, .credentialsRejected)
            let zh = AgentIMQQProvisionText.line(for: problem, language: .simplifiedChinese)
            XCTAssertTrue(zh.contains("401"), zh)
            XCTAssertTrue(zh.contains("AppID") || zh.contains("Secret"), zh)
        } catch {
            XCTFail("抛的必须是机器码族的错：\(error)")
        }
        XCTAssertEqual(client.getCount, 0, "token 都没拿到，不许再去问网关地址")
    }

    func testStatus403IsPermissionProblem() async throws {
        let client = FakeHTTP()
        client.postHandler = { _, _ in AgentIMHTTPResponse(status: 403, body: "{}") }
        do {
            _ = try await provisioner(client, at: fixedNow)
                .prepare(appID: "1", secret: "s", environment: .production)
            XCTFail("403 必须抛错")
        } catch let problem as AgentIMQQProvisionProblem {
            XCTAssertEqual(problem, .permissionDenied)
            let line = AgentIMQQProvisionText.line(for: problem, language: .simplifiedChinese)
            XCTAssertTrue(line.contains("403"), line)
        }
    }

    func testUnknownStatusIsEchoedNotInvented() {
        // 认不出的状态码：原样带出去（编一句「网络错误」比贴码更误导）。
        let response = AgentIMHTTPResponse(status: 418, body: #"{"code":100016}"#)
        XCTAssertEqual(AgentIMQQProvisioner.problem(for: response), .rejected(status: 418, code: "100016"))
        let line = AgentIMQQProvisionText.line(for: .rejected(status: 418, code: "100016"),
                                              language: .simplifiedChinese)
        XCTAssertTrue(line.contains("418"), line)
        XCTAssertTrue(line.contains("100016"), line)
        // 5xx 单独一档：不是用户的配置问题。
        XCTAssertEqual(AgentIMQQProvisioner.problem(for: AgentIMHTTPResponse(status: 502, body: "")), .serverFailed)
        XCTAssertEqual(AgentIMQQProvisioner.problem(for: AgentIMHTTPResponse(status: 429, body: "")), .rateLimited)
    }

    func testMissingCredentialsNeverReachTheNetwork() async {
        let client = FakeHTTP()
        for (appID, secret, expected) in [("", "s", AgentIMQQProvisionProblem.appIDMissing),
                                          ("  ", "s", .appIDMissing),
                                          ("1", "", .secretMissing)] {
            do {
                _ = try await provisioner(client, at: fixedNow)
                    .prepare(appID: appID, secret: secret, environment: .production)
                XCTFail("缺凭据必须抛错")
            } catch let problem as AgentIMQQProvisionProblem {
                XCTAssertEqual(problem, expected)
            } catch {
                XCTFail("错类型不对：\(error)")
            }
        }
        XCTAssertEqual(client.calls.count, 0, "缺凭据时一个请求都不该发出去")
    }

    func testTokenWithoutAccessFieldIsItsOwnProblem() async {
        let client = FakeHTTP()
        client.postHandler = { _, _ in
            AgentIMHTTPResponse(status: 200, body: #"{"expires_in":"7200"}"#)
        }
        do {
            _ = try await provisioner(client, at: fixedNow)
                .prepare(appID: "1", secret: "s", environment: .production)
            XCTFail("没有 access_token 不许当成功")
        } catch let problem as AgentIMQQProvisionProblem {
            XCTAssertEqual(problem, .tokenMissing)
        } catch {
            XCTFail("\(error)")
        }
    }

    func testHTMLAnswerIsReportedAsNotJSON() async {
        let client = FakeHTTP()
        client.postHandler = { _, _ in
            AgentIMHTTPResponse(status: 200, body: "<html><body>portal login</body></html>")
        }
        do {
            _ = try await provisioner(client, at: fixedNow)
                .prepare(appID: "1", secret: "s", environment: .production)
            XCTFail("被代理拦回来一页 HTML 时必须说「不是 JSON」")
        } catch let problem as AgentIMQQProvisionProblem {
            XCTAssertEqual(problem, .responseNotJSON)
        } catch {
            XCTFail("\(error)")
        }
    }

    // MARK: - 三、自建中继：填了就不问官方网关

    func testRelayOverrideSkipsGatewayLookup() async throws {
        let client = FakeHTTP()
        let relay = URL(string: "wss://relay.example/ws")!
        let provisioning = try await provisioner(client, at: fixedNow)
            .prepare(appID: "1", secret: "s", environment: .production, relayOverride: relay)
        XCTAssertEqual(provisioning.gateway.url, relay)
        XCTAssertEqual(provisioning.gateway.source, .relay)
        XCTAssertEqual(client.getCount, 0, "填了自建中继还去问官方网关 = 用了不该用的地址")
        XCTAssertEqual(client.postCount, 1, "token 仍要取（重连要靠它续命）")
    }

    // MARK: - 四、token 到期前刷新（不是等它过期才换）

    func testTokenRefreshWindowIsBeforeExpiry() {
        let token = AgentIMQQToken(value: "tok-abc", expiresIn: 7200, obtainedAt: fixedNow)
        XCTAssertFalse(token.needsRefresh(now: fixedNow), "刚取到的 token 不该马上又换")
        // 7200 秒寿命 ⇒ 提前 1440 秒（20%）换。
        XCTAssertEqual(token.refreshLeadTime(), 1440)
        XCTAssertFalse(token.needsRefresh(now: fixedNow.addingTimeInterval(7200 - 1441)))
        XCTAssertTrue(token.needsRefresh(now: fixedNow.addingTimeInterval(7200 - 1440)),
                      "进入提前量就必须换 —— 等它过期那一跳的握手一定失败")
        // 短寿命 token（60 秒）也不能「提前 20% 只有 12 秒」：下限 60 秒。
        let short = AgentIMQQToken(value: "x", expiresIn: 60, obtainedAt: fixedNow)
        XCTAssertEqual(short.refreshLeadTime(), 60)
        XCTAssertTrue(short.needsRefresh(now: fixedNow))
    }

    func testVaultReusesFreshTokenAndRefreshesOnlyWhenNeeded() async throws {
        let vault = AgentIMQQTokenVault()
        let counter = Counter()
        let fresh = AgentIMQQToken(value: "tok-1", expiresIn: 7200, obtainedAt: fixedNow)

        let first = try await vault.current(now: fixedNow) { await counter.bump(); return fresh }
        let second = try await vault.current(now: fixedNow.addingTimeInterval(60)) {
            await counter.bump()
            return AgentIMQQToken(value: "tok-2", expiresIn: 7200, obtainedAt: self.fixedNow)
        }
        XCTAssertEqual(first.value, "tok-1")
        XCTAssertEqual(second.value, "tok-1", "还新鲜就复用，不该每跳重连都去换（会撞限流）")
        let afterReuse = await counter.value
        XCTAssertEqual(afterReuse, 1)

        let refreshed = try await vault.current(now: fixedNow.addingTimeInterval(7200 - 100)) {
            await counter.bump()
            return AgentIMQQToken(value: "tok-3", expiresIn: 7200, obtainedAt: self.fixedNow)
        }
        XCTAssertEqual(refreshed.value, "tok-3")
        let afterRefresh = await counter.value
        XCTAssertEqual(afterRefresh, 2)
    }

    func testVaultSingleFlightSharesOneRequest() async throws {
        let vault = AgentIMQQTokenVault()
        let counter = Counter()
        let token = AgentIMQQToken(value: "tok-sf", expiresIn: 7200, obtainedAt: fixedNow)

        // 两个调用方同时要换（传输层每一跳重连都会来要）：只许打一次网络。
        async let a = vault.current(now: fixedNow, forceRefresh: true) {
            try? await Task.sleep(nanoseconds: 40_000_000)
            await counter.bump()
            return token
        }
        async let b = vault.current(now: fixedNow, forceRefresh: true) {
            await counter.bump()
            return token
        }
        let results = try await [a, b]
        XCTAssertEqual(results.map(\.value), ["tok-sf", "tok-sf"])
        let fetchCount = await counter.value
        XCTAssertEqual(fetchCount, 1, "单飞被打破 ⇒ 重连风暴会被 QQ 限流")
    }

    func testVaultKeepsUsableTokenWhenRefreshFails() async throws {
        // 换不到新 token 时：手上那把还没过期就继续用（因为换不到就断线，比用旧 token 再试更糟）。
        let vault = AgentIMQQTokenVault()
        _ = try await vault.current(now: fixedNow) {
            AgentIMQQToken(value: "tok-old", expiresIn: 7200, obtainedAt: self.fixedNow)
        }
        let kept = try await vault.current(now: fixedNow.addingTimeInterval(7200 - 10),
                                           forceRefresh: true) { throw StubError() }
        XCTAssertEqual(kept.value, "tok-old")

        // 手上那把已经过期 ⇒ 必须抛（过期 token 拿去握手一定 401，装成能用更坏）。
        let staleVault = AgentIMQQTokenVault()
        _ = try await staleVault.current(now: fixedNow) {
            AgentIMQQToken(value: "tok-stale", expiresIn: 60, obtainedAt: self.fixedNow)
        }
        do {
            _ = try await staleVault.current(now: fixedNow.addingTimeInterval(600),
                                             forceRefresh: true) { throw StubError() }
            XCTFail("过期且换不到必须抛错")
        } catch {
            XCTAssertTrue(error is StubError)
        }
    }

    // MARK: - 五、官方 op 码口径（Identify / 心跳 / 恢复 / 解帧）

    func testIdentifyAndHeartbeatFollowOfficialOpcodes() throws {
        let token = AgentIMQQToken(value: "tok-abc", expiresIn: 7200, obtainedAt: fixedNow)
        XCTAssertEqual(AgentIMQQHandshake.authorizationHeaderName, "Authorization")
        XCTAssertEqual(token.authorizationHeaders["Authorization"], "QQBot tok-abc")

        let identify = try XCTUnwrap(ProvisionerSupport.jsonObject(AgentIMQQHandshake.identifyFrame(token: token)))
        XCTAssertEqual(identify["op"] as? Int, 2, "Identify 必须是 op=2")
        let data = try XCTUnwrap(identify["d"] as? [String: Any])
        XCTAssertEqual(data["token"] as? String, "QQBot tok-abc")
        XCTAssertEqual(data["intents"] as? Int, AgentIMQQHandshake.intentsC2CAndGroup)

        let heartbeat = try XCTUnwrap(ProvisionerSupport.jsonObject(AgentIMQQHandshake.heartbeatFrame(sequence: 7)))
        XCTAssertEqual(heartbeat["op"] as? Int, 1, "心跳必须是 op=1")
        XCTAssertEqual(heartbeat["d"] as? Int, 7)
        // 第一跳还没有 seq：官方收 null，不许编一个 0 出来。
        let firstBeat = try XCTUnwrap(ProvisionerSupport.jsonObject(AgentIMQQHandshake.heartbeatFrame(sequence: nil)))
        XCTAssertTrue(firstBeat["d"] is NSNull)

        let resume = try XCTUnwrap(ProvisionerSupport.jsonObject(
            AgentIMQQHandshake.resumeFrame(token: token, sessionID: "sess-1", sequence: 9)))
        XCTAssertEqual(resume["op"] as? Int, 6, "断线恢复必须是 op=6")
        let resumeData = try XCTUnwrap(resume["d"] as? [String: Any])
        XCTAssertEqual(resumeData["session_id"] as? String, "sess-1")
        XCTAssertEqual(resumeData["seq"] as? Int, 9)

        // Hello（op=10）给的心跳间隔是毫秒，换成秒。
        XCTAssertEqual(AgentIMQQHandshake.heartbeatInterval(of: #"{"op":10,"d":{"heartbeat_interval":41250}}"#),
                       41.25)
        XCTAssertEqual(AgentIMQQHandshake.sequence(of: #"{"op":0,"s":12,"t":"C2C_MESSAGE_CREATE"}"#), 12)
        XCTAssertNil(AgentIMQQHandshake.sequence(of: #"{"op":11}"#))
    }

    func testOfficialDispatchBecomesAnInboundMessage() throws {
        let c2c = """
        {"op":0,"s":3,"t":"C2C_MESSAGE_CREATE","d":{"id":"msg-1","content":"  帮我跑一下测试  ",
         "author":{"user_openid":"openid-A"}}}
        """
        guard case .message(let message) = try XCTUnwrap(AgentIMQQHandshake.decode(c2c)) else {
            return XCTFail("C2C 私聊必须解成一条任务")
        }
        XCTAssertEqual(message.platformMessageID, "msg-1")
        XCTAssertEqual(message.chatID, "openid-A", "同一个人再来一句话要落进同一条会话")
        XCTAssertEqual(message.senderID, "openid-A")
        XCTAssertEqual(message.text, "帮我跑一下测试", "官方 content 前面带空格，要修掉（否则策略判成空白消息）")

        let group = """
        {"op":0,"t":"GROUP_AT_MESSAGE_CREATE","d":{"id":"msg-2","content":"查下表结构",
         "group_openid":"group-9","author":{"member_openid":"member-B"}}}
        """
        guard case .message(let groupMessage) = try XCTUnwrap(AgentIMQQHandshake.decode(group)) else {
            return XCTFail("群里 @ 机器人也要解成一条任务")
        }
        XCTAssertEqual(groupMessage.chatID, "group-9", "群聊按群标识分会话（不是按发话人）")
        XCTAssertEqual(groupMessage.senderID, "member-B")

        // 认不出的事件不假装懂；心跳应答算 pong（否则心跳会被判死）。
        XCTAssertEqual(AgentIMQQHandshake.decode(#"{"op":0,"t":"GUILD_CREATE","d":{}}"#),
                       .unknown(op: "GUILD_CREATE"))
        XCTAssertEqual(AgentIMQQHandshake.decode(#"{"op":11}"#), .pong)
        XCTAssertEqual(AgentIMQQHandshake.decode(#"{"op":7}"#), .unknown(op: "reconnect"))
        XCTAssertNil(AgentIMQQHandshake.decode("not json"))
    }

    // MARK: - 六、panel 上不该出现的东西（反例：地址那一格必须真的删掉）

    func testTokenNeverShowsInFull() {
        let token = AgentIMQQToken(value: "tok-abcdefg", expiresIn: 7200, obtainedAt: fixedNow)
        XCTAssertEqual(token.redactedPreview, "…defg")
        XCTAssertFalse(token.redactedPreview.contains("tok-abcdefg"))
        let short = AgentIMQQToken(value: "abc", expiresIn: 7200, obtainedAt: fixedNow)
        XCTAssertFalse(short.redactedPreview.contains("abc"))
    }

    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testSettingsSheetNoLongerAsksForAGatewayAddress() throws {
        let sheet = try source("App/Views/AgentSettingsSheet.swift")
        XCTAssertFalse(sheet.contains("$imGatewayURL"), "「网关端点」那一格必须删掉（★0）")
        XCTAssertFalse(sheet.contains("agentIMFieldGatewayURL"), "旧键已作废，界面不许再引用")
        XCTAssertFalse(sheet.contains("$imBotIdentifier"), "机器人标识不再要用户填")
        XCTAssertTrue(sheet.contains("$imEnvironment"), "必须能选环境（正式 / 沙箱）")
        XCTAssertTrue(sheet.contains("agentIMRelayAdvanced"), "自建中继降为高级项")
        XCTAssertTrue(sheet.contains("https://q.qq.com"), "要做「去 QQ 开放平台」按钮（不做运行时扫码）")
    }

    func testAppStateWiresTheProvisioningChain() throws {
        let state = try source("App/AppState.swift")
        XCTAssertTrue(state.contains("AgentIMQQProvisioner("), "取 token / 取网关必须真的接上")
        XCTAssertTrue(state.contains("AgentIMQQTokenVault("), "token 要有唯一持有处（到期前刷新）")
        XCTAssertTrue(state.contains("AgentIMQQHandshake.identifyFrame("), "官方路径连上要先 Identify")
        XCTAssertTrue(state.contains("AgentIMQQProvisionText.line(for:"), "取 token 失败要说得出是哪一种")
        XCTAssertTrue(state.contains("handshake: usesRelay ? nil :"),
                      "自建中继与官方是两套握手口径，不许混用")
    }
}

/// 并发计数（单飞判据用）。
private actor Counter {
    private(set) var value = 0
    func bump() { value += 1 }
}
