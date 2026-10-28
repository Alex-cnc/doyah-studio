import XCTest
@testable import DoyahCore

/// `FR-AGT-LINK-CHAN-003` 的收尾片（2026-10-28 第四十三批）判据：**官方 REST 外发**。
///
/// 钉的是「手机派活 ⇒ 手机收结论」这条链的最后一段：
/// 结论不再糊成自建帧，而是按官方两条端点发出去 ——
/// 私聊 `POST /v2/users/{openid}/messages`、群 `POST /v2/groups/{group_openid}/messages`，
/// 被动回复带 `msg_id` + `msg_seq`（同一 `msg_id` 下不可重复、**同一条结果重发要复用**）。
///
/// 全程假 HTTP（不碰网络）：真发一条要 AppID + Secret + 一个真人手机，那半记 blocked，不在这里装绿。
final class AgentIMOutboundSendTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dsh-im-out-\\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    // MARK: - 夹具

    private struct StubError: Error {}

    private final class FakeClient: AgentIMOutboundHTTPClient, @unchecked Sendable {

        struct Call: Equatable {
            var url: String
            var payload: String
            var headers: [String: String]
        }

        private let lock = NSLock()
        private var _calls: [Call] = []
        private let _response: AgentIMHTTPResponse?
        private let _failure: Error?

        init(response: AgentIMHTTPResponse? = AgentIMHTTPResponse(status: 200, body: #"{"id":"m-out-1"}"#),
             failure: Error? = nil) {
            self._response = response
            self._failure = failure
        }

        var calls: [Call] { lock.lock(); defer { lock.unlock() }; return _calls }
        var count: Int { calls.count }

        func post(_ url: URL, payload: String, headers: [String: String]) async throws -> AgentIMHTTPResponse {
            lock.lock()
            _calls.append(Call(url: url.absoluteString, payload: payload, headers: headers))
            lock.unlock()
            if let _failure { throw _failure }
            guard let _response else { throw StubError() }
            return _response
        }
    }

    private func token() -> AgentIMQQToken {
        AgentIMQQToken(value: "tok-abc", expiresIn: 7200, obtainedAt: Date(timeIntervalSince1970: 0))
    }

    private func sender(_ client: FakeClient,
                        environment: AgentIMQQEnvironment = .production,
                        directory: URL? = nil) -> AgentIMOutboundSender {
        AgentIMOutboundSender(client: client,
                              environment: environment,
                              sequences: AgentIMReplySeqLedger(directory: directory ?? root),
                              token: {
                                  AgentIMQQToken(value: "tok-abc", expiresIn: 7200,
                                                 obtainedAt: Date(timeIntervalSince1970: 0))
                              })
    }

    private func entry(id: String = "e1",
                       chatID: String = "user-openid-A",
                       kind: AgentIMChatKind = .c2c,
                       text: String = "统计跑完了：3 张表，0 条异常",
                       replyTo: String? = "msg-in-1") -> AgentIMResultQueue.Entry {
        AgentIMResultQueue.Entry(id: id, chatID: chatID, text: text,
                                 createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                                 target: AgentIMOutboundTarget(kind: kind, openID: chatID),
                                 replyToMessageID: replyTo)
    }

    private func bodyObject(_ payload: String) -> [String: Any] {
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object
    }

    // MARK: - ① 两条端点：私聊走 users，群走 groups（走错 = 404 或发到别人会话）

    func testC2CReplyUsesUsersEndpointAndCarriesAuthorizationHeader() async throws {
        let client = FakeClient()
        let outcome = await sender(client).send(entry: entry())

        XCTAssertEqual(outcome, .delivered(messageID: "m-out-1"))
        let call = try XCTUnwrap(client.calls.first)
        XCTAssertEqual(call.url, "https://api.sgroup.qq.com/v2/users/user-openid-A/messages")
        XCTAssertEqual(call.headers["Authorization"], "QQBot tok-abc")
    }

    func testGroupReplyUsesGroupsEndpoint() async throws {
        let client = FakeClient()
        _ = await sender(client).send(entry: entry(chatID: "group-openid-9", kind: .group))
        let call = try XCTUnwrap(client.calls.first)
        XCTAssertEqual(call.url, "https://api.sgroup.qq.com/v2/groups/group-openid-9/messages")
    }

    func testSandboxEnvironmentUsesSandboxHost() async throws {
        let client = FakeClient()
        _ = await sender(client, environment: .sandbox).send(entry: entry())
        let call = try XCTUnwrap(client.calls.first)
        XCTAssertEqual(call.url, "https://sandbox.api.sgroup.qq.com/v2/users/user-openid-A/messages")
    }

    // MARK: - ② 正文：msg_id + msg_seq 必须成对；数字不许写成字符串

    func testPassiveReplyCarriesMessageIDAndNumericTypeAndSequence() async throws {
        let client = FakeClient()
        _ = await sender(client).send(entry: entry())
        let payload = try XCTUnwrap(client.calls.first?.payload)

        // 数字就是数字：`"msg_type":"0"` 会被官方按类型校验拒掉。
        XCTAssertTrue(payload.contains(#""msg_type":0"#), payload)
        XCTAssertFalse(payload.contains(#""msg_type":"0""#), payload)
        XCTAssertEqual(bodyObject(payload)["msg_id"] as? String, "msg-in-1")
        XCTAssertEqual(bodyObject(payload)["msg_seq"] as? Int, 1)
        XCTAssertEqual(bodyObject(payload)["content"] as? String, "统计跑完了：3 张表，0 条异常")
    }

    func testActiveMessageCarriesNeitherMessageIDNorSequence() async throws {
        let client = FakeClient()
        let ledger = AgentIMReplySeqLedger(directory: root)
        _ = await sender(client).send(entry: entry(replyTo: nil))
        let payload = try XCTUnwrap(client.calls.first?.payload)

        XCTAssertNil(bodyObject(payload)["msg_id"])
        XCTAssertNil(bodyObject(payload)["msg_seq"], "没有 msg_id 就不许带 msg_seq（官方那一对是绑定的）")
        XCTAssertEqual(ledger.count(), 0, "主动消息不占序号")
    }

    // MARK: - ③ 序号：同一条结果重发复用，同一个 msg_id 下不重复

    func testDifferentEntriesUnderSameMessageGetIncreasingSequences() async throws {
        let client = FakeClient()
        let outbound = sender(client)
        _ = await outbound.send(entry: entry(id: "e1"))
        _ = await outbound.send(entry: entry(id: "e2"))

        let sequences = client.calls.map { bodyObject($0.payload)["msg_seq"] as? Int }
        XCTAssertEqual(sequences, [1, 2], "同一 msg_id 下复用序号会被 QQ 当重复消息丢掉")
    }

    func testRetryOfSameEntryReusesItsSequenceEvenAfterRestart() async throws {
        let client = FakeClient()
        _ = await sender(client).send(entry: entry(id: "e1"))
        // 模拟「投递成功但 ack 没落盘，重连后补发」：**换一个 ledger 实例**（进程重启）再发同一条。
        _ = await sender(client).send(entry: entry(id: "e1"))

        let sequences = client.calls.map { bodyObject($0.payload)["msg_seq"] as? Int }
        XCTAssertEqual(sequences, [1, 1], "重发换号 = 手机上出现两条一样的结论")
    }

    // MARK: - ④ 结局分档：401 / 403 / 429 / 5xx / 其余原样带码

    func testStatusCodesMapToDistinctOutcomes() async {
        // 401 凭据 / 403 权限 / 429 限流 / 503 对方 / 418 原样带码。
        let cases: [(Int, String, AgentIMSendOutcome)] = [
            (401, "{}", .unauthorized),
            (403, "{}", .forbidden),
            (429, "{}", .rateLimited),
            (503, "{}", .serverFailed),
            (418, #"{"code":100016,"message":"bad"}"#, .rejected(status: 418, code: "100016")),
        ]
        for (status, body, expected) in cases {
            let client = FakeClient(response: AgentIMHTTPResponse(status: status, body: body))
            let outcome = await sender(client).send(entry: entry())
            XCTAssertEqual(outcome, expected, "HTTP \(status) 分错了档")
            XCTAssertFalse(outcome.isDelivered, "非 2xx 一律不算发出去")
        }
    }

    func testSuccessWithoutReadableBodyStillCountsAsDelivered() async {
        // 2xx 是官方状态码；正文认不出（被代理塞了 HTML）也只是「没有回执号」，不算失败。
        let client = FakeClient(response: AgentIMHTTPResponse(status: 200, body: "<html>ok</html>"))
        let outcome = await sender(client).send(entry: entry())
        XCTAssertEqual(outcome, .responseNotJSON)
        XCTAssertTrue(outcome.isDelivered)
    }

    func testTokenCredentialRejectionMapsToUnauthorizedWithoutAnyRequest() async {
        let client = FakeClient()
        let outbound = AgentIMOutboundSender(
            client: client,
            environment: .production,
            sequences: AgentIMReplySeqLedger(directory: root),
            token: { throw AgentIMQQProvisionProblem.credentialsRejected })

        let outcome = await outbound.send(entry: entry())
        XCTAssertEqual(outcome, .unauthorized)
        XCTAssertEqual(client.count, 0, "凭据不对时不许真的发（发了就是拿错凭据去撞接口）")
    }

    func testNetworkFailureIsDistinctFromRejection() async {
        let client = FakeClient(failure: StubError())
        let outcome = await sender(client).send(entry: entry())
        XCTAssertEqual(outcome, .networkFailed)
    }

    // MARK: - ⑤ 发不出去的三种「还没到发那一步」

    func testOpenIDWithPathCharactersIsRejectedBeforeAnyRequest() async {
        for openID in ["abc/../../evil", "a b", "x?y=1", "%2F", ".."] {
            let client = FakeClient()
            let bad = AgentIMResultQueue.Entry(id: "e1", chatID: openID, text: "结论",
                                               createdAt: Date(), target: AgentIMOutboundTarget(kind: .c2c, openID: openID),
                                               replyToMessageID: "m1")
            let outcome = await sender(client).send(entry: bad)
            XCTAssertEqual(outcome, .notReady(code: "badTarget"), "openid 会被拼进 URL 路径：\(openID) 必须当场拒")
            XCTAssertEqual(client.count, 0, "认不出的 openid 不许发出去")
        }
    }

    func testEmptyContentIsNotSent() async {
        let client = FakeClient()
        let outcome = await sender(client).send(entry: entry(text: "   \n "))
        XCTAssertEqual(outcome, .notReady(code: "emptyContent"))
        XCTAssertEqual(client.count, 0)
    }

    func testEntryWithoutTargetIsNotSentOverREST() async {
        // 第四十二批及以前的老条目 / 自建中继条目：`target` 为 nil，正文里存的是本侧帧。
        let client = FakeClient()
        let legacy = AgentIMResultQueue.Entry(id: "old", chatID: "chat-A",
                                              text: #"{"chatID":"chat-A","op":"reply","text":"旧的"}"#,
                                              createdAt: Date(), target: nil, replyToMessageID: nil)
        let outcome = await sender(client).send(entry: legacy)
        XCTAssertEqual(outcome, .notReady(code: "noTarget"))
        XCTAssertEqual(client.count, 0, "老条目的正文是帧，当 content 发出去 = 手机收到一坨 JSON")
    }

    // MARK: - ⑥ 补发：只补官方那条路，发成才 ack，失败的留在队列里

    func testDrainSendsOnlyOfficialEntriesAndAcksThem() async throws {
        let queue = AgentIMResultQueue(directory: root)
        let officialA = try queue.enqueue(chatID: "user-openid-A", text: "结论 A",
                                          target: AgentIMOutboundTarget(kind: .c2c, openID: "user-openid-A"),
                                          replyToMessageID: "m1")
        let officialB = try queue.enqueue(chatID: "group-openid-9", text: "结论 B",
                                          target: AgentIMOutboundTarget(kind: .group, openID: "group-openid-9"),
                                          replyToMessageID: "g1")
        let legacy = try queue.enqueue(chatID: "chat-A", text: #"{"op":"reply"}"#)

        let client = FakeClient()
        let outbound = sender(client)
        let drain = AgentIMOutboundDrain(queue: AgentIMResultQueue(directory: root),
                                        send: { await outbound.send(entry: $0) })
        let report = await drain.run()

        XCTAssertEqual(report.delivered, 2)
        XCTAssertEqual(report.failed, 0)
        XCTAssertEqual(client.count, 2)
        let pendingIDs = AgentIMResultQueue(directory: root).pending().map(\.id)
        XCTAssertEqual(pendingIDs, [legacy.id], "官方两条已 ack；老条目留给传输层那条路")
        XCTAssertFalse(pendingIDs.contains(officialA.id))
        XCTAssertFalse(pendingIDs.contains(officialB.id))
    }

    func testDrainKeepsFailedEntryPending() async throws {
        let queue = AgentIMResultQueue(directory: root)
        let failed = try queue.enqueue(chatID: "user-openid-A", text: "结论",
                                       target: AgentIMOutboundTarget(kind: .c2c, openID: "user-openid-A"),
                                       replyToMessageID: "m1")
        let client = FakeClient(response: AgentIMHTTPResponse(status: 429, body: "{}"))
        let outbound = sender(client)
        let drain = AgentIMOutboundDrain(queue: queue, send: { await outbound.send(entry: $0) })
        let report = await drain.run()

        XCTAssertEqual(report.delivered, 0)
        XCTAssertEqual(report.failed, 1)
        XCTAssertEqual(report.lastFailure, .rateLimited)
        XCTAssertEqual(AgentIMResultQueue(directory: root).pending().map(\.id), [failed.id],
                       "没发成的不许 ack（ack 了就等于把结论丢了）")
    }

    func testRelayPendingExcludesOfficialEntries() throws {
        let queue = AgentIMResultQueue(directory: root)
        let official = try queue.enqueue(chatID: "user-openid-A", text: "结论",
                                         target: AgentIMOutboundTarget(kind: .c2c, openID: "user-openid-A"))
        let legacy = try queue.enqueue(chatID: "chat-A", text: #"{"op":"reply"}"#)

        let relay = queue.relayPending().map(\.id)
        XCTAssertEqual(relay, [legacy.id], "官方条目往官方网关上糊本侧帧 = 一堆坏帧")
        XCTAssertFalse(relay.contains(official.id))
    }

    // MARK: - ⑦ 每一档都要有中英两句（面板与回话都直接用它）

    func testEveryOutcomeHasBothLanguageLines() {
        let outcomes: [AgentIMSendOutcome] = [.delivered(messageID: "m"),
                                              .notReady(code: "badTarget"),
                                              .unauthorized, .forbidden, .rateLimited,
                                              .serverFailed, .responseNotJSON,
                                              .rejected(status: 418, code: "100016"),
                                              .networkFailed]
        for outcome in outcomes {
            let zh = AgentIMSendText.line(for: outcome, language: .simplifiedChinese)
            let en = AgentIMSendText.line(for: outcome, language: .english)
            XCTAssertFalse(zh.isEmpty, "\(outcome.code) 缺中文")
            XCTAssertFalse(en.isEmpty, "\(outcome.code) 缺英文")
            XCTAssertNotEqual(zh, en, "\(outcome.code) 的英文译文没落地")
            XCTAssertFalse(zh.contains("%"), "占位符没被替换：\(zh)")
        }
    }

    // MARK: - ⑧ 解帧那一处要定死私聊 / 群（回话走哪条端点靠它）

    func testOfficialDispatchDecodesChatKind() throws {
        let c2c = #"{"op":0,"t":"C2C_MESSAGE_CREATE","d":{"id":"m1","content":" 跑一下统计 ","author":{"user_openid":"u-1"}}}"#
        let group = #"{"op":0,"t":"GROUP_AT_MESSAGE_CREATE","d":{"id":"g1","content":"跑一下统计","group_openid":"grp-9","author":{"member_openid":"u-2"}}}"#

        guard case .message(let direct)? = AgentIMQQHandshake.decode(c2c) else {
            return XCTFail("私聊那帧没解出来")
        }
        XCTAssertEqual(direct.chatKind, .c2c)
        XCTAssertEqual(direct.chatID, "u-1")

        guard case .message(let inGroup)? = AgentIMQQHandshake.decode(group) else {
            return XCTFail("群那帧没解出来")
        }
        XCTAssertEqual(inGroup.chatKind, .group, "群消息发成私聊 = 手机永远收不到结论")
        XCTAssertEqual(inGroup.chatID, "grp-9")
    }
}
