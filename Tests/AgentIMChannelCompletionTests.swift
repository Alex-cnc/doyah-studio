import XCTest
@testable import DoyahCore

/// IM 通道完善（beta1.2.x）的六条判据 —— **每条都要能判红**。
///
/// ① 重投去重；② 断线重连补发不重复（逐条 id 对比）；③ 长任务进度封顶且含阶段变化；
/// ④ 不可逆操作经 IM 发起仍进审批并回人话；⑤ 自检五环逐环读数；⑥ 状态页四读数取真值。
final class AgentIMChannelCompletionTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("doyah-im-completion-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    // MARK: - 夹具

    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var _tasks: [AgentIMTask] = []
        private var _delivered: [AgentIMResultQueue.Entry] = []
        private var _notes: [String] = []

        func run(_ task: AgentIMTask) { lock.lock(); _tasks.append(task); lock.unlock() }
        func deliver(_ entry: AgentIMResultQueue.Entry) {
            lock.lock(); _delivered.append(entry); lock.unlock()
        }
        func note(_ note: String) { lock.lock(); _notes.append(note); lock.unlock() }

        var tasks: [AgentIMTask] { lock.lock(); defer { lock.unlock() }; return _tasks }
        var delivered: [AgentIMResultQueue.Entry] { lock.lock(); defer { lock.unlock() }; return _delivered }
        var notes: [String] { lock.lock(); defer { lock.unlock() }; return _notes }
    }

    private func frame(id: String = "m1", chatID: String = "chat-A",
                       text: String = "跑一下统计") -> AgentIMInboundFrame {
        .message(AgentIMInboundMessage(platformMessageID: id, chatID: chatID,
                                       senderID: "u1", text: text))
    }

    private let ready = AgentIMReadiness(missing: [])
    private let online = AgentIMConnectionState.online(attempt: 1)

    private func runner(_ box: Box,
                        cadence: AgentIMProgressCadence = AgentIMProgressCadence(),
                        body: @escaping @Sendable (AgentIMProgressReporter?) async -> AgentIMTaskRunResult)
    -> AgentIMInboundRunner {
        AgentIMInboundRunner(
            sessionMap: AgentIMSessionMap(directory: root),
            resultQueue: AgentIMResultQueue(directory: root),
            ledger: AgentIMInboundLedger(directory: root),
            cadence: cadence,
            onDuplicate: { id in box.note("dup:\(id)") },
            run: { task, reporter in
                box.run(task)
                return await body(reporter)
            },
            deliver: { entry in
                box.deliver(entry)
                return true
            })
    }

    // MARK: - ① 同一平台消息重投 3 次 ⇒ 只执行 1 次（其余去重丢弃并计数）

    func testRedeliveredThreeTimesRunsOnceAndCountsTheDrops() async {
        let box = Box()
        let subject = runner(box) { _ in .answered("统计跑完了") }

        var outcomes: [AgentIMInboundOutcome] = []
        var board = AgentIMChannelStatusBoard()
        for _ in 1...3 {
            let outcome = await subject.handle(frame(), receiveTasks: true, readiness: ready,
                                               connection: online, language: .simplifiedChinese)
            if case .duplicate = outcome { board.recordDuplicate() }
            outcomes.append(outcome)
        }

        XCTAssertEqual(box.tasks.count, 1, "重投 3 次只许执行 1 次（实际执行 \(box.tasks.count) 次）")
        XCTAssertEqual(outcomes.filter { $0 == .replied(delivered: true) }.count, 1)
        XCTAssertEqual(outcomes.filter { $0 == .duplicate(platformMessageID: "m1") }.count, 2,
                       "另 2 次必须报重复：\(outcomes)")
        XCTAssertEqual(board.duplicatesDropped, 2, "去重丢弃要计数（读数贴出来才有用）")
        XCTAssertEqual(box.notes.filter { $0 == "dup:m1" }.count, 2, "重复要经回调通知宿主")
    }

    // MARK: - ② 断线 → 重连 ⇒ 未 ack 结果全部补发且不重复（逐条 id 对比）

    func testReconnectReplaysEveryUnackedIDExactlyOnceAcrossPasses() async throws {
        let queue = AgentIMResultQueue(directory: root)
        var seeded: [String] = []
        for index in 1...3 {
            let entry = try queue.enqueue(chatID: "chat-\(index)",
                                          text: "结论 \(index)",
                                          target: AgentIMOutboundTarget(kind: .c2c, openID: "chat-\(index)"),
                                          replyToMessageID: "m\(index)")
            seeded.append(entry.id)
        }
        XCTAssertEqual(queue.pending().count, 3)

        // 第一趟（断线期间／首次连上）：第 2 条网络没通 ⇒ 它留在队列里，其余 ack。
        let firstPass = await AgentIMOutboundDrain(queue: queue, send: { entry in
            entry.text.contains("结论 2") ? .networkFailed : .delivered(messageID: "ok-\(entry.id)")
        }).run()

        XCTAssertEqual(firstPass.deliveredIDs, [seeded[0], seeded[2]], "发出去的是 1 / 3")
        XCTAssertEqual(firstPass.failedIDs, [seeded[1]], "第 2 条没发出去")
        XCTAssertEqual(Set(firstPass.deliveredIDs).count, firstPass.deliveredIDs.count,
                       "同一趟里同一条 id 只许发一次：\(firstPass.deliveredIDs)")
        XCTAssertEqual(queue.pending().map { $0.id }, [seeded[1]])

        // 「进程重启」：新的队列实例（只认盘上的账）—— 未 ack 的那一条必须还在。
        let restarted = AgentIMResultQueue(directory: root)
        XCTAssertEqual(restarted.pending().map { $0.id }, [seeded[1]],
                       "重启后未 ack 队列不许丢")

        // 第二趟（重连成功）：只补发未 ack 的那一条；已 ack 的两条**一条都不许重发**。
        let secondPass = await AgentIMOutboundDrain(queue: restarted, send: { entry in
            .delivered(messageID: "ok2-\(entry.id)")
        }).run()

        XCTAssertEqual(secondPass.deliveredIDs, [seeded[1]], "重连只补发未 ack 的那一条")
        XCTAssertTrue(Set(secondPass.deliveredIDs).isDisjoint(with: Set(firstPass.deliveredIDs)),
                      "已 ack 的 id 不许在第二趟里再出现")
        XCTAssertTrue(restarted.pending().isEmpty, "补发成功后队列必须清空")
    }

    // MARK: - ③ 60 秒长任务 ⇒ 进度 ≤ 3 条（只报关键节点），结束必有一条结论

    func testSixtySecondRunPushesAtMostThreeLinesAndReportsKeyMoments() async throws {
        let box = Box()
        let subject = runner(box) { reporter in
            // 60 秒、每 10 秒一跳；阶段：0–19 思考、20–44 工具、45–60 收尾。
            for second in 0...60 {
                let stage: AgentIMRunStage = second < 20 ? .thinking : (second < 45 ? .tool : .finalizing)
                let hop = second / 10 + 1
                await reporter?.report(AgentIMRunProgress(
                    hop: hop,
                    tool: stage == .tool ? "read_file" : nil,
                    summary: stage == .tool ? "Core/AgentIMChannel.swift" : "",
                    elapsed: TimeInterval(second),
                    toolCalls: stage == .tool ? second / 10 : 2,
                    stage: stage))
            }
            return .answered("60 秒那一轮跑完了")
        }

        let outcome = await subject.handle(frame(), receiveTasks: true, readiness: ready,
                                           connection: online, language: .simplifiedChinese)
        XCTAssertEqual(outcome, .replied(delivered: true))

        let progress = box.delivered.filter { $0.text.contains("已跑") }
        XCTAssertLessThanOrEqual(progress.count, 3, "60 秒最多 3 条进度（只报关键节点）：\(progress.map(\.text))")
        XCTAssertGreaterThanOrEqual(progress.count, 1, "60 秒至少一条进度（不许一片空白）")
        XCTAssertFalse(progress.contains { $0.text.contains("正在 read_file") && $0.text.contains("20 秒") },
                       "工具↔思考的振荡不许一条条推（刷屏的正源）：\(progress.map(\.text))")
        XCTAssertTrue(progress.contains { $0.text.contains("收尾") },
                      "阶段变化（收尾）必须单独有一条：\(progress.map(\.text))")
        XCTAssertEqual(box.delivered.last?.text, "60 秒那一轮跑完了", "结束必须推结论，且是最后一条")
        // 进度封顶 3 + 结论 1（ack 是另一条，不在这里数）。
        XCTAssertLessThanOrEqual(box.delivered.count, 5, "整轮消息条数要有上限：\(box.delivered.count)")
    }

    // MARK: - ④ 不可逆操作经 IM 发起 ⇒ 仍进审批（拦截发生）并回人话

    func testIrreversibleActionFromIMIsStoppedAndRepliesWithAHumanLine() async throws {
        // 审批闸本身：删除 / 对外发送 一律要桌面批，**盘上有授权也不认**。
        let gate = AgentIMOriginGate(origin: .im)
        let deleteHazard = AgentScopeGate.hazard(tool: "delete_records",
                                                 preview: "rm -rf /tmp/doyah-test")
        XCTAssertEqual(deleteHazard, .destructive, "删除类调用必须被判成不可逆")
        XCTAssertEqual(gate.decide(hazard: deleteHazard, hasStoredGrant: true),
                       .requiresDesktopApproval(reason: .irreversible),
                       "就算有一条旧授权，IM 来的删除也必须去桌面批")

        let sendHazard = AgentScopeGate.hazard(tool: "send_message", preview: "发给客户")
        XCTAssertEqual(sendHazard, .outbound, "对外发送必须被判成发出去收不回")

        // 代签路径（任务范围内不问人）对四档危险面必须转人工 —— 这正是「IM 免审」的老洞。
        if case .needsHuman(let reason) = AgentScopeGate.judge(tool: "delete_records",
                                                              preview: "rm -rf /tmp/doyah-test",
                                                              autoApprovedCount: 0,
                                                              scope: .default) {
            XCTAssertTrue(reason.hasPrefix("hazard:"), "理由要指着危险面：\(reason)")
        } else {
            XCTFail("任务范围内也不许代签删除")
        }
        if case .autoApproved = AgentScopeGate.judge(tool: "write_file", preview: "Sources/a.swift",
                                                     autoApprovedCount: 0, scope: .default) {
            // 普通改写不受影响（否则这条改动会把日常使用变成逐次点批准）。
        } else {
            XCTFail("普通改写仍应能在任务范围内代签")
        }

        // 整条链：IM 派来一句「删掉测试库」⇒ 拦截发生 ⇒ 回给手机一句人话。
        let box = Box()
        let subject = runner(box) { _ in
            let verdict = gate.decide(hazard: deleteHazard, hasStoredGrant: true)
            box.note(verdict == .requiresDesktopApproval(reason: .irreversible)
                     ? "gate:blocked" : "gate:allowed")
            return .blockedByApproval(reason: .irreversible, action: "删除测试库的记录")
        }
        let outcome = await subject.handle(frame(text: "把测试库的记录删掉"),
                                           receiveTasks: true, readiness: ready,
                                           connection: online, language: .simplifiedChinese)
        XCTAssertEqual(outcome, .replied(delivered: true), "挡下也要给手机一句回话（不许静默）")
        XCTAssertEqual(box.notes.first, "gate:blocked", "拦截必须真的发生在跑之前")

        let reply = try XCTUnwrap(box.delivered.last?.text)
        XCTAssertTrue(reply.contains("桌面"), "要说清去哪批：\(reply)")
        XCTAssertTrue(reply.contains("不替你放行"), "要说清 IM 不放宽：\(reply)")
        XCTAssertFalse(reply.contains("删掉了") || reply.contains("已完成"), "挡下时不许假装做完了：\(reply)")

        let english = AgentIMReplyText.text(for: .blockedByApproval(reason: .irreversible, action: "delete the test database"),
                                            language: .english)
        XCTAssertTrue(english.contains("approval on the desktop"), english)
        XCTAssertFalse(english.unicodeScalars.contains { $0.value >= 0x4E00 && $0.value <= 0x9FFF },
                       "英文回话里混了汉字：\(english)")
    }

    // MARK: - ⑤ 自检五环：正例全绿；Secret 置空 ⇒ 只在第一环红

    private func probes(hasSecret: Bool,
                        token: AgentIMSelfCheckStep = .pass("tail ab12"),
                        handshake: AgentIMSelfCheckStep = .pass("READY"),
                        receive: AgentIMSelfCheckStep = .pass("hello"),
                        send: AgentIMSelfCheckStep = .pass("ping")) -> AgentIMSelfCheckProbes {
        AgentIMSelfCheckProbes(
            facts: AgentIMSelfCheckFacts(appID: "102030405", hasSecret: hasSecret,
                                         environment: .production, receiveTasks: true,
                                         configFileExists: true),
            token: { token },
            handshake: { handshake },
            receive: { receive },
            send: { send })
    }

    func testSelfCheckFiveRingsAllGreenWithReadings() async {
        let report = await AgentIMSelfCheckRunner.run(probes(hasSecret: true),
                                                      language: .simplifiedChinese)
        XCTAssertEqual(report.readouts.map(\.ring),
                       [.configuration, .token, .handshake, .receive, .send],
                       "五环顺序固定")
        XCTAssertTrue(report.isAllGreen, "正例五环全绿：\(report.readouts.map(\.line))")
        XCTAssertEqual(report.passedCount, 5)
        XCTAssertNil(report.failedRing)
        for readout in report.readouts {
            XCTAssertTrue(readout.line.contains("通过"), "每一环都要有可读读数：\(readout.line)")
            XCTAssertFalse(readout.line.contains("102030405"), "AppID 只许显示尾 4 位：\(readout.line)")
        }
        XCTAssertTrue(report.readouts[0].line.contains("0405"), report.readouts[0].line)
        XCTAssertTrue(report.summary(language: .simplifiedChinese).contains("5/5"),
                      report.summary(language: .simplifiedChinese))
    }

    func testSelfCheckWithEmptySecretOnlyRedsTheFirstRing() async {
        let report = await AgentIMSelfCheckRunner.run(probes(hasSecret: false),
                                                      language: .simplifiedChinese)
        XCTAssertEqual(report.failedRing, .configuration, "红的只有第一环")
        XCTAssertEqual(report.readouts.filter { $0.verdict.isFailed }.count, 1,
                       "别的环不许跟着红（它们根本没跑）：\(report.readouts.map(\.line))")
        for readout in report.readouts.dropFirst() {
            if case .blocked(let by, _) = readout.verdict {
                XCTAssertEqual(by, .configuration)
            } else {
                XCTFail("Secret 空 ⇒ 后四环只能是「没跑到」：\(readout.line)")
            }
        }
        XCTAssertTrue(report.readouts[0].line.contains("Secret"), report.readouts[0].line)
        XCTAssertTrue(report.summary(language: .simplifiedChinese).contains("第 1 环"),
                      report.summary(language: .simplifiedChinese))
    }

    func testSelfCheckTokenFailurePointsAtTheSecondRing() async {
        let report = await AgentIMSelfCheckRunner.run(
            probes(hasSecret: true, token: .fail("unauthorized", "凭据不对")),
            language: .simplifiedChinese)
        XCTAssertEqual(report.failedRing, .token, "token 取不到 ⇒ 指到第二环")
        XCTAssertEqual(report.readouts.filter { $0.verdict.isFailed }.count, 1)
        guard case .blocked(let by, _) = report.readouts[2].verdict else {
            return XCTFail("握手环应为「没跑到」：\(report.readouts[2].line)")
        }
        XCTAssertEqual(by, .token)
    }

    func testEveryNewReadingHasBothLanguages() async {
        let report = await AgentIMSelfCheckRunner.run(probes(hasSecret: true), language: .english)
        for readout in report.readouts {
            XCTAssertFalse(readout.line.isEmpty)
            XCTAssertFalse(readout.line.unicodeScalars.contains { $0.value >= 0x4E00 && $0.value <= 0x9FFF },
                           "英文读数里混了汉字：\(readout.line)")
        }
        var board = AgentIMChannelStatusBoard()
        board.recordInbound(at: Date())
        board.recordFailure(stage: .send, code: "rateLimited")
        for reading in board.readings(connection: online, readiness: ready, pending: 2,
                                      language: .english) {
            XCTAssertFalse(reading.value.isEmpty)
            XCTAssertFalse(reading.value.unicodeScalars.contains { $0.value >= 0x4E00 && $0.value <= 0x9FFF },
                           "\(reading.kind) 的英文读数里混了汉字：\(reading.value)")
        }
    }

    // MARK: - ⑥ 状态页四读数都能取到（真实值，不是占位）

    func testStatusBoardReadsRealConnectionTrafficBacklogAndFailure() throws {
        var board = AgentIMChannelStatusBoard()
        let inboundAt = Date(timeIntervalSince1970: 1_760_000_000)
        board.recordInbound(at: inboundAt)

        var readings = board.readings(connection: online, readiness: ready, pending: 0,
                                      language: .simplifiedChinese)
        XCTAssertEqual(readings.map(\.kind), [.connection, .delivery, .queue, .failure],
                       "四个读数身份固定")
        XCTAssertTrue(readings[0].value.contains("已连接"), "连接状态取真值：\(readings[0].value)")
        let clock = AgentIMChannelStatusBoard.clock(inboundAt)
        XCTAssertTrue(readings[1].value.contains("收 \(clock)"), "收的时刻要真实：\(readings[1].value)")
        XCTAssertTrue(readings[1].value.contains("发 —"), "还没发过就说「—」，不编一个时间")
        XCTAssertEqual(readings[2].value.contains("0 条"), true, readings[2].value)
        XCTAssertEqual(readings[3].value, "没有失败记录", "没有失败就说没有，别留一句旧红字")

        // 后发生的：一次成功外发 + 一次失败 + 3 条待发。
        let outboundAt = inboundAt.addingTimeInterval(65)
        board.recordOutbound(at: outboundAt)
        board.recordFailure(stage: .send, code: "unauthorized")
        readings = board.readings(connection: .waiting(reason: "heartbeatLost", attempt: 2, retryIn: 4),
                                  readiness: ready, pending: 3,
                                  language: .simplifiedChinese)
        XCTAssertTrue(readings[1].value.contains("发 \(AgentIMChannelStatusBoard.clock(outboundAt))"),
                      readings[1].value)
        XCTAssertTrue(readings[2].value.contains("3 条"), readings[2].value)
        XCTAssertTrue(readings[3].value.contains("发消息"), "失败要说清哪一环：\(readings[3].value)")
        XCTAssertTrue(readings[3].value.contains("凭据"), "要人话，不是 JSON / 机器码：\(readings[3].value)")
        XCTAssertFalse(readings[3].value.contains("{"), "不许把原始 JSON 贴给人：\(readings[3].value)")
        XCTAssertTrue(readings[3].isFault)
        XCTAssertTrue(readings[0].isFault, "不在线时连接那一条要是红的")

        // 再成功一次 ⇒ 旧失败自动清掉（否则面板一直挂着一条像还在失败的红字）。
        board.recordOutbound()
        let cleared = board.readings(connection: online, readiness: ready, pending: 0,
                                     language: .simplifiedChinese)
        XCTAssertEqual(cleared[3].value, "没有失败记录")
        XCTAssertFalse(cleared[3].isFault)
    }

    func testStatusBoardCountsDuplicatesSeparatelyFromFailures() {
        var board = AgentIMChannelStatusBoard()
        board.recordDuplicate()
        board.recordDuplicate()
        XCTAssertEqual(board.duplicatesDropped, 2)
        XCTAssertNil(board.lastFailure, "去重丢弃不是失败（不许混进失败读数）")
    }

    // MARK: - 阶段节流是纯函数（判据 ③ 的判定物）

    /// **关键阶段变化才放行**（2026-11-11 真机后收窄：`thinking ↔ tool` 振荡不再算转折）。
    func testCadenceAdmitsOnStageChangeButRespectsFirstPushGate() {
        let cadence = AgentIMProgressCadence()
        let t0 = Date()
        // 刚开跑：阶段变了也不推（会跟 ack 撞车）。
        XCTAssertFalse(cadence.admits(hop: 1, elapsed: 2, stage: .tool, at: t0,
                                      track: AgentIMProgressCadence.Track()))
        // 过了首条闸：**关键**阶段变化立刻放行（不看步数差、不看时间间隔）。
        let track = AgentIMProgressCadence.Track(pushes: 1, lastPushAt: t0, lastHop: 9,
                                                 lastStage: .thinking)
        XCTAssertTrue(cadence.admits(hop: 9, elapsed: 25, stage: .finalizing,
                                     at: t0.addingTimeInterval(1), track: track))
        // 同阶段、步数与时间都不够 ⇒ 不推。
        let settled = AgentIMProgressCadence.Track(pushes: 2, lastPushAt: t0, lastHop: 9,
                                                   lastStage: .finalizing)
        XCTAssertFalse(cadence.admits(hop: 10, elapsed: 15, stage: .finalizing,
                                      at: t0.addingTimeInterval(1), track: settled))
    }
}
