import XCTest
@testable import DoyahCore

/// `FR-AGT-LINK-CHAN-003` 后半的判据：入站一句话 ⇒ 真跑一轮 ⇒ 结论推回原 chat。
///
/// 钉的是**那条链**（策略 → 去重 → 建任务 → 跑 → 入队 → 推 → 推成才 ack），
/// 链上的「跑」与「推」都是闭包，所以整条链在单测里一段不缺；真网关那半缺凭据，另记 blocked。
final class AgentIMInboundRunTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dsh-im-run-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    // MARK: - 夹具

    /// 记录「跑过哪几轮」与「推过哪几条」的盒子（测试里同步读）。
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var _tasks: [AgentIMTask] = []
        private var _delivered: [AgentIMResultQueue.Entry] = []
        private var _deliverSucceeds = true

        func record(_ task: AgentIMTask) { lock.lock(); _tasks.append(task); lock.unlock() }
        func record(delivery entry: AgentIMResultQueue.Entry) { lock.lock(); _delivered.append(entry); lock.unlock() }
        func setDeliverSucceeds(_ value: Bool) { lock.lock(); _deliverSucceeds = value; lock.unlock() }

        var tasks: [AgentIMTask] { lock.lock(); defer { lock.unlock() }; return _tasks }
        var delivered: [AgentIMResultQueue.Entry] { lock.lock(); defer { lock.unlock() }; return _delivered }
        var deliverSucceeds: Bool { lock.lock(); defer { lock.unlock() }; return _deliverSucceeds }
    }

    private struct Boom: Error {}

    private func makeRunner(recorder: Recorder,
                            answer: String = "统计跑完了：3 张表，0 条异常",
                            result: AgentIMTaskRunResult? = nil,
                            fails: Bool = false) -> AgentIMInboundRunner {
        AgentIMInboundRunner(
            sessionMap: AgentIMSessionMap(directory: root),
            resultQueue: AgentIMResultQueue(directory: root),
            ledger: AgentIMInboundLedger(directory: root),
            run: { task in
                recorder.record(task)
                if fails { throw Boom() }
                return result ?? .answered(answer)
            },
            deliver: { entry in
                recorder.record(delivery: entry)
                return recorder.deliverSucceeds
            })
    }

    private func frame(id: String = "m1", chatID: String = "chat-A",
                       text: String = "跑一下统计") -> AgentIMInboundFrame {
        .message(AgentIMInboundMessage(platformMessageID: id, chatID: chatID,
                                       senderID: "u1", text: text))
    }

    private let ready = AgentIMReadiness(missing: [])
    private let online = AgentIMConnectionState.online(attempt: 1)

    private func queue() -> AgentIMResultQueue { AgentIMResultQueue(directory: root) }

    // MARK: - ① 一条链：跑一次、结论推回原 chat、推成才 ack

    func testInboundMessageRunsOnceAndPushesReplyBackToTheSameChat() async throws {
        let recorder = Recorder()
        let runner = makeRunner(recorder: recorder)
        let outcome = await runner.handle(frame(), receiveTasks: true, readiness: ready,
                                          connection: online, language: .simplifiedChinese)

        XCTAssertEqual(outcome, .replied(delivered: true))
        XCTAssertEqual(recorder.tasks.count, 1)
        XCTAssertEqual(recorder.tasks.first?.prompt, "跑一下统计", "提示词要原样交出去")
        XCTAssertEqual(recorder.tasks.first?.chatID, "chat-A")
        XCTAssertEqual(recorder.tasks.first?.alwaysRequiresDesktopApproval, true, "IM 不放宽审批")

        // 入队的那一条：正文就是结论（**不是帧** —— 官方 REST 把它放进 content），
        // 并且带着「回哪个 chat / 私聊还是群 / 回哪一条消息」—— 断线补发时只认这一份。
        let entry = try XCTUnwrap(recorder.delivered.first)
        XCTAssertEqual(entry.text, "统计跑完了：3 张表，0 条异常")
        XCTAssertFalse(entry.text.contains(#""op":"reply""#), "官方那条路不许再往正文里塞本侧帧")
        XCTAssertEqual(entry.chatID, "chat-A")
        XCTAssertEqual(entry.target, AgentIMOutboundTarget(kind: .c2c, openID: "chat-A"))
        XCTAssertEqual(entry.replyToMessageID, "m1", "被动回复要带派活那条消息的 msg_id")

        // 推成才 ack：队列里留痕但不再待投递。
        XCTAssertTrue(queue().pending().isEmpty, "推成功的必须 ack，否则每次重连都重发")
        XCTAssertEqual(queue().all().count, 1, "留痕不删")
    }

    // MARK: - ①b 群聊：目标落在群那条端点、`msg_id` 是派活那条

    func testGroupMessageCarriesGroupTargetAndReplyTo() async throws {
        let recorder = Recorder()
        let runner = makeRunner(recorder: recorder)
        let groupFrame = AgentIMInboundFrame.message(
            AgentIMInboundMessage(platformMessageID: "g-1", chatID: "group-openid-9",
                                  senderID: "member-openid", text: "跑一下统计",
                                  chatKind: .group))

        let outcome = await runner.handle(groupFrame, receiveTasks: true, readiness: ready,
                                          connection: online, language: .simplifiedChinese)

        XCTAssertEqual(outcome, .replied(delivered: true))
        let entry = try XCTUnwrap(recorder.delivered.first)
        XCTAssertEqual(entry.target, AgentIMOutboundTarget(kind: .group, openID: "group-openid-9"),
                       "群里派活得回到群那条端点，不能发成私聊")
        XCTAssertEqual(entry.replyToMessageID, "g-1")
    }

    // MARK: - ② 开关关掉：一条都不进，且不记去重（之后打开开关，重投的那条仍该跑）

    func testReceiveSwitchOffDropsEverythingAndLeavesNoTrace() async throws {
        let recorder = Recorder()
        let runner = makeRunner(recorder: recorder)
        let outcome = await runner.handle(frame(), receiveTasks: false, readiness: ready,
                                          connection: online, language: .simplifiedChinese)

        XCTAssertEqual(outcome, .dropped(reason: .notEnabled))
        XCTAssertTrue(recorder.tasks.isEmpty, "关掉开关时一条都不许跑")
        XCTAssertTrue(queue().all().isEmpty, "也不许往结果队列里写东西")
        XCTAssertFalse(AgentIMInboundLedger(directory: root).hasSeen("m1"),
                       "被挡下的消息不许记成「见过」—— 打开开关后重投的那条仍该跑")
    }

    // MARK: - ③ 没配齐 / 不在线：两档原因分开

    func testNotConfiguredAndOfflineAreDifferentReasons() async {
        let recorder = Recorder()
        let runner = makeRunner(recorder: recorder)

        let notConfigured = await runner.handle(frame(id: "m1"), receiveTasks: true,
                                                readiness: AgentIMReadiness(missing: [.appID]),
                                                connection: online, language: .simplifiedChinese)
        let offline = await runner.handle(frame(id: "m2"), receiveTasks: true,
                                          readiness: ready, connection: .idle,
                                          language: .simplifiedChinese)
        XCTAssertEqual(notConfigured, .dropped(reason: .notConfigured))
        XCTAssertEqual(offline, .dropped(reason: .notConnected))
        XCTAssertTrue(recorder.tasks.isEmpty)
    }

    // MARK: - ④ 重投同一条：只跑一次（QQ 会重投）

    func testRedeliveredMessageRunsOnlyOnceEvenAfterRestart() async {
        let recorder = Recorder()
        let runner = makeRunner(recorder: recorder)
        let first = await runner.handle(frame(), receiveTasks: true, readiness: ready,
                                        connection: online, language: .simplifiedChinese)
        let second = await runner.handle(frame(), receiveTasks: true, readiness: ready,
                                         connection: online, language: .simplifiedChinese)
        XCTAssertEqual(first, .replied(delivered: true))
        XCTAssertEqual(second, .duplicate(platformMessageID: "m1"))
        XCTAssertEqual(recorder.tasks.count, 1, "同一条平台消息号不许跑两遍")
        XCTAssertEqual(queue().all().count, 1, "也不许推两遍")

        // 重启（换一个 runner 实例、新读盘）仍认得出 —— 去重台账是落盘的。
        let restarted = makeRunner(recorder: recorder)
        let afterRestart = await restarted.handle(frame(), receiveTasks: true, readiness: ready,
                                                  connection: online, language: .simplifiedChinese)
        XCTAssertEqual(afterRestart, .duplicate(platformMessageID: "m1"))
        XCTAssertEqual(recorder.tasks.count, 1)
    }

    // MARK: - ⑤ 推不出去：结果留 pending、不 ack

    func testDeliverFailureKeepsResultPendingAndUnacked() async {
        let recorder = Recorder()
        recorder.setDeliverSucceeds(false)
        let runner = makeRunner(recorder: recorder)
        let outcome = await runner.handle(frame(), receiveTasks: true, readiness: ready,
                                          connection: online, language: .simplifiedChinese)

        XCTAssertEqual(outcome, .replied(delivered: false))
        XCTAssertEqual(queue().pending().count, 1, "没推出去的必须留在待投递里")
        XCTAssertNil(queue().pending().first?.ackedAt)
    }

    // MARK: - ⑥ 离线期间产生的结论：重连后补发（真传输层，假 socket）
    //
    // 第四十三批改了口径：官方结论走 REST，**不再**往官方 WebSocket 上写本侧帧。
    // ⇒ 这里钉的是「补发只补中继那条路」，官方那条留给 `AgentIMOutboundDrain`（见
    // `Tests/AgentIMOutboundSendTests.swift`）。

    func testReconnectReplaysOnlyRelayShapedResultsOverWebSocket() async throws {
        let results = queue()
        let official = try results.enqueue(chatID: "chat-B", text: "统计跑完了：3 张表，0 条异常",
                                         target: AgentIMOutboundTarget(kind: .c2c, openID: "chat-B"),
                                         replyToMessageID: "m1")
        let relay = try results.enqueue(chatID: "chat-B2",
                                      text: AgentIMOutboundFrame.reply(chatID: "chat-B2",
                                                                       text: "统计跑完了：中继那条"))
        XCTAssertEqual(results.pending().count, 2)

        // 起真传输层（假 socket）：连上那一刻先补发没 ack 的**中继条目**。
        let socket = RecordingSocket()
        let link = AgentIMTransport(
            config: AgentIMTransportConfig(gatewayURL: URL(string: "wss://gateway.test/ws")!,
                                           heartbeatSeconds: 30),
            signer: AgentIMGatewaySigner(appID: "12345678", secret: "s3cret"),
            makeSocket: { _, _ in socket },
            sleep: { _ in })
        await link.attachResultQueue(results)
        await link.start()
        let replayed = await waitUntil(2) {
            results.all().first(where: { $0.id == relay.id })?.ackedAt != nil
        }
        XCTAssertTrue(replayed, "中继那条重连后没补发：\(results.pending())")
        await link.stop()

        let frames = socket.sentFrames
        XCTAssertTrue(frames.contains { $0.contains(#""chatID":"chat-B2""#) && $0.contains("中继那条") },
                      "补发的那一帧要带回原 chat 与结论：\(frames)")
        XCTAssertFalse(frames.contains { $0.contains("统计跑完了：3 张表") },
                       "官方条目走 REST，不许往官方网关糊本侧帧：\(frames)")
        XCTAssertEqual(results.pending().map(\.id), [official.id],
                       "官方那条仍在队列里等 REST 补发")
    }

    // MARK: - ⑦ 跑抛错：仍推一句能读的「没跑成」（技术串不外泄）

    func testFailedRunStillPushesAReadableFailureLine() async throws {
        let recorder = Recorder()
        let runner = makeRunner(recorder: recorder, fails: true)
        let outcome = await runner.handle(frame(), receiveTasks: true, readiness: ready,
                                          connection: online, language: .simplifiedChinese)
        guard case .failed(let reason, let delivered) = outcome else {
            return XCTFail("抛错必须走 .failed，实际 \(outcome)")
        }
        XCTAssertTrue(delivered)
        XCTAssertTrue(reason.contains("Boom"), "技术串只进日志：\(reason)")

        let sent = try XCTUnwrap(recorder.delivered.first?.text)
        XCTAssertTrue(sent.contains("没跑成"), sent)
        XCTAssertFalse(sent.contains("Boom"), "异常类型名不许贴给手机那头：\(sent)")
    }

    // MARK: - ⑧ 停在审批上：回话不许装成有结论

    func testAwaitingApprovalRepliesWithoutPretendingThereIsAResult() async throws {
        let recorder = Recorder()
        let runner = makeRunner(recorder: recorder, result: .awaitingApproval)
        let outcome = await runner.handle(frame(), receiveTasks: true, readiness: ready,
                                          connection: online, language: .simplifiedChinese)
        XCTAssertEqual(outcome, .replied(delivered: true))

        let sent = try XCTUnwrap(recorder.delivered.first?.text)
        XCTAssertTrue(sent.contains("等你在桌面那台机器上批准"), sent)
        XCTAssertFalse(sent.contains("统计跑完了"), "不许把别的结论贴上去")
    }

    // MARK: - ⑨ 起不来：原因码翻人话；不认识的码原样贴出来

    func testUnavailableReasonCodesAreLocalizedAndUnknownOnesAreShownAsIs() {
        let zhBusy = AgentIMReplyText.text(for: .unavailable(code: "busy"), language: .simplifiedChinese)
        XCTAssertTrue(zhBusy.contains("上一轮还在跑"), zhBusy)

        let unknown = AgentIMReplyText.text(for: .unavailable(code: "weirdCode"),
                                            language: .simplifiedChinese)
        XCTAssertTrue(unknown.contains("weirdCode"), "不认识的码原样贴出来，别编一句「出错了」：\(unknown)")
    }

    // MARK: - ⑩ 长结论按上限截断，并说清全文在哪

    func testLongAnswerIsTruncatedAndSaysWhereTheFullTextIs() {
        let long = String(repeating: "字", count: AgentIMReplyText.maxAnsweredLength + 500)
        let bounded = AgentIMReplyText.bounded(long, language: .simplifiedChinese)
        XCTAssertTrue(bounded.count < long.count)
        XCTAssertTrue(bounded.hasPrefix(String(long.prefix(64))))
        XCTAssertTrue(bounded.contains("完整内容在桌面那一条会话里"), bounded.suffix(80).description)

        let short = "短结论"
        XCTAssertEqual(AgentIMReplyText.bounded(short, language: .simplifiedChinese), short,
                       "不超限的一个字都不许动")
    }

    // MARK: - ⑪ 不是消息帧（pong / 不认识的 op）：不跑不推

    func testNonMessageFramesAreIgnored() async {
        let recorder = Recorder()
        let runner = makeRunner(recorder: recorder)
        let pong = await runner.handle(.pong, receiveTasks: true, readiness: ready,
                                       connection: online, language: .simplifiedChinese)
        let unknown = await runner.handle(.unknown(op: "notice"), receiveTasks: true,
                                          readiness: ready, connection: online,
                                          language: .simplifiedChinese)
        XCTAssertEqual(pong, .ignored)
        XCTAssertEqual(unknown, .ignored)
        XCTAssertTrue(recorder.tasks.isEmpty)
        XCTAssertTrue(queue().all().isEmpty)
    }

    // MARK: - ⑫ 空白消息：不起一轮

    func testBlankMessageIsDroppedAsEmptyText() async {
        let recorder = Recorder()
        let runner = makeRunner(recorder: recorder)
        let outcome = await runner.handle(frame(text: "   \n "), receiveTasks: true,
                                          readiness: ready, connection: online,
                                          language: .simplifiedChinese)
        XCTAssertEqual(outcome, .dropped(reason: .emptyText))
        XCTAssertTrue(recorder.tasks.isEmpty, "空白消息不许烧一跳模型")
    }

    // MARK: - ⑬ 会话归属：同一 chat 同一条会话号，不同 chat 不串

    func testSameChatKeepsOneSessionAndDifferentChatsDoNotShare() async {
        let recorder = Recorder()
        let runner = makeRunner(recorder: recorder)
        _ = await runner.handle(frame(id: "m1", chatID: "chat-A"), receiveTasks: true,
                                readiness: ready, connection: online, language: .simplifiedChinese)
        _ = await runner.handle(frame(id: "m2", chatID: "chat-A"), receiveTasks: true,
                                readiness: ready, connection: online, language: .simplifiedChinese)
        _ = await runner.handle(frame(id: "m3", chatID: "chat-B"), receiveTasks: true,
                                readiness: ready, connection: online, language: .simplifiedChinese)

        let sessions = recorder.tasks.map(\.sessionID)
        XCTAssertEqual(sessions.count, 3)
        XCTAssertEqual(sessions[0], sessions[1], "同一个 chat 的两条消息必须落同一条会话")
        XCTAssertNotEqual(sessions[0], sessions[2], "不同 chat 不许共用一条会话（上下文会串）")
    }

    // MARK: - ⑭ 两语言都要有话说（不许一条回话只有中文）

    func testEveryReplyKindHasBothLanguages() {
        let kinds: [AgentIMTaskRunResult] = [.answered("done"), .awaitingApproval,
                                             .unavailable(code: "busy")]
        for kind in kinds {
            let zh = AgentIMReplyText.text(for: kind, language: .simplifiedChinese)
            let en = AgentIMReplyText.text(for: kind, language: .english)
            XCTAssertFalse(zh.isEmpty)
            XCTAssertFalse(en.isEmpty)
            XCTAssertFalse(en.unicodeScalars.contains { $0.value >= 0x4E00 && $0.value <= 0x9FFF },
                           "\(kind) 的英文回话里混了汉字：\(en)")
        }
    }

    // MARK: - ⑮ 接线锚点（Core 有判定、宿主必须真的接上）

    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testAppStateWiresRunnerQueueAndLedger() throws {
        let state = try source("App/AppState.swift")
        XCTAssertTrue(state.contains("AgentIMInboundRunner("), "入站必须走那条唯一链")
        XCTAssertTrue(state.contains("attachResultQueue("), "结果队列要在 start 之前接上（重连补发走真路）")
        XCTAssertTrue(state.contains("AgentIMInboundLedger("), "去重要落盘（重投不许跑两遍）")
        XCTAssertFalse(state.contains("本版只登记、不进对话"),
                       "「本版只登记」那句必须随本片作废（留着就是假话）")
    }

    func testAppInjectsARunnerThatKeepsApprovals() throws {
        let app = try source("App/DoyahStudioApp.swift")
        XCTAssertTrue(app.contains("appState.agentIMTaskRunner = {"), "宿主必须注入跑一轮的闭包")
        XCTAssertTrue(app.contains("agentChat.adoptSession("), "IM 的会话号要接管（两个 chat 不共用上下文）")
        XCTAssertTrue(app.contains("hasPendingApproval"), "停在审批上要如实回，不许装成有结论")
        XCTAssertTrue(app.contains("agentChat.send()"), "走手动那条路 ⇒ 同一套审批")
    }

    func testSettingsSheetShowsHandledAndRepliedApart() throws {
        let sheet = try source("App/Views/AgentSettingsSheet.swift")
        XCTAssertTrue(sheet.contains("agentIMInboundHandled"), "面板必须报跑过几轮")
        XCTAssertTrue(sheet.contains("agentIMInboundReplied"), "推回几条要单独报（与跑过几轮不是同一个数）")
    }

    private func waitUntil(_ seconds: TimeInterval, _ condition: () async -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if await condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return await condition()
    }
}

/// 假 socket：只记「发出去的帧」，收帧永远挂着（补发类判据用不到对端回话）。
private final class RecordingSocket: AgentIMSocket, @unchecked Sendable {
    private let lock = NSLock()
    private var _sent: [String] = []

    var sentFrames: [String] { lock.lock(); defer { lock.unlock() }; return _sent }

    func open() async throws {}
    func send(_ text: String) async throws { lock.lock(); _sent.append(text); lock.unlock() }
    func receive() async throws -> String {
        try await Task.sleep(nanoseconds: 30_000_000_000)
        throw CancellationError()
    }
    func close() async {}
}
