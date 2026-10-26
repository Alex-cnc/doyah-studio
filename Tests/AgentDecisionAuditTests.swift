import XCTest
@testable import DoyahCore
@testable import DoyahStudioApp

/// 「用户可见的自动化决定」落审计的判据
/// （`FR-AGT-GUARD-COST-001` · `FR-AGT-UX-CONV-008` · `FR-AGT-UX-CONV-009` 的「留痕可查」）。
///
/// 这三条的共同缺口是同一处：**屏上成立、日志里没有**。判据点名四件事：
///
/// ① 挡下 / 硬发**成对**留痕（只记其中一边，事后就看不出「挡了几次、几次是硬发的」）；
/// ② 通知记得住「两处出口各自出没出」（页内条与系统通知的判定不同，混成一句就查不出漏在哪）；
/// ③ 求助卡记得住「它要我去办哪件事」；
/// ④ 该安静的那些**一条都不写**（没发生的事留账，读日志的人会以为发生过）。
final class AgentDecisionAuditTests: XCTestCase {

    private let stamp = Date(timeIntervalSince1970: 1_760_000_000)

    private func trigger(digest: String = "0123456789abcdef", source: String = "chat") -> AgentGateTrigger {
        AgentGateTrigger(source: source, digest: digest, at: stamp)
    }

    private func memorySink() -> (sink: (AgentActionRecord) async -> Void, read: () -> [AgentActionRecord]) {
        final class Box: @unchecked Sendable {
            var records: [AgentActionRecord] = []
        }
        let box = Box()
        return ({ record in box.records.append(record) }, { box.records })
    }

    private let han = try! NSRegularExpression(pattern: "\\p{Han}", options: [])

    private func containsHan(_ text: String) -> Bool {
        han.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)) != nil
    }

    // MARK: - 门控：挡下与硬发

    func testGateSkipIsRecordedAsNotice() {
        let recall = AgentGateRecall(prompt: "再问一次同样的", reason: "同样的问法刚问过", trigger: trigger())
        let record = AgentDecisionAudit.gateSkipped(recall, sessionID: "s-1", at: stamp)

        XCTAssertEqual(record.resolvedOrigin, .notice, "来源必须是新开的那一档，面板才不会显示成「无法识别的语句」")
        XCTAssertEqual(record.outcome, .denied, "挡下 = 这一跳没发生")
        XCTAssertEqual(record.sessionID, "s-1")
        XCTAssertEqual(record.timestamp, stamp)
        // 「语句」列放机器码：导出后能直接 grep 出「这段时间挡了几次」。
        XCTAssertTrue(record.sql.hasPrefix("gateSkipped chat "), "机器码与来源要进语句列：\(record.sql)")
        XCTAssertTrue(record.sql.contains("01234567"), "指纹前 8 位要能对上「哪一次」")
        XCTAssertFalse(record.sql.contains("0123456789abcdef"), "整段指纹不进日志")
        XCTAssertEqual(record.detail, "门控挡下：同样的问法刚问过（这一跳一个请求都没发）")
    }

    func testGateForceIsPairedWithTheSkip() {
        let recall = AgentGateRecall(prompt: "再问一次同样的", reason: "同样的问法刚问过", trigger: trigger())
        let record = AgentDecisionAudit.gateForced(recall, at: stamp)

        XCTAssertEqual(record.outcome, .executed, "硬发是真的发了")
        XCTAssertTrue(record.sql.hasPrefix("gateForced chat "))
        XCTAssertEqual(record.resolvedOrigin, .notice)
        // 与挡下**同一条指纹**：成对出现在日志里，才看得出这是同一次问法的两次决定。
        XCTAssertEqual(AgentDecisionAudit.shortDigest(recall.trigger.digest),
                       record.sql.split(separator: " ").last.map(String.init) ?? "")
        XCTAssertTrue(record.detail?.contains("仍然发送") == true, "要写明是用户让它硬发的")
    }

    // MARK: - 通知：两处出口各自出没出

    func testNotificationRecordsBothOutlets() {
        let policy = AgentNotifyPolicy(longTaskThresholdSeconds: 30)
        // 人看着这一页 + 长任务 ⇒ 页内条出、系统通知不出（这条最容易漏记成「都出了」）。
        let watching = policy.plan(.longTaskFinished(elapsedSeconds: 95), userIsLookingAtThisPane: true)
        let record = try? XCTUnwrap(AgentDecisionAudit.notification(.longTaskFinished(elapsedSeconds: 95),
                                                                    plan: watching,
                                                                    sessionID: "s-2",
                                                                    at: stamp))
        XCTAssertEqual(record?.outcome, .executed)
        XCTAssertTrue(record?.sql.hasPrefix("notified longTaskFinished ") == true, "机器码要带档位：\(record?.sql ?? "")")
        XCTAssertTrue(record?.detail?.contains("页内提示条 已出") == true, "页内条出没出要记：\(record?.detail ?? "")")
        XCTAssertTrue(record?.detail?.contains("系统通知 未出") == true, "人就在这页 —— 系统那一格没出，要如实记")
    }

    func testNotificationRecordsSystemOutletWhenUserIsAway() {
        let policy = AgentNotifyPolicy(longTaskThresholdSeconds: 30)
        let away = policy.plan(.longTaskFinished(elapsedSeconds: 95), userIsLookingAtThisPane: false, userIsIdle: true)
        let record = AgentDecisionAudit.notification(.longTaskFinished(elapsedSeconds: 95), plan: away, at: stamp)
        XCTAssertTrue(record?.detail?.contains("系统通知 已出") == true, "走开了就该弹，也要记上")
    }

    /// 该安静的那一档不写账：短任务的判定本来就是「什么都不用出」。
    func testSilentPlanLeavesNoRecord() {
        let policy = AgentNotifyPolicy(longTaskThresholdSeconds: 30)
        let quiet = policy.plan(.longTaskFinished(elapsedSeconds: 5), userIsLookingAtThisPane: true)
        XCTAssertTrue(quiet.isEmpty)
        XCTAssertNil(AgentDecisionAudit.notification(.longTaskFinished(elapsedSeconds: 5), plan: quiet, at: stamp),
                     "没发生的事不许留一条「什么都没做」的记录")
    }

    // MARK: - 求助卡

    func testHelpCardRecordsWhatItAsksFor() {
        let help = AgentHelpCatalogue.missingLoop()
        let record = try? XCTUnwrap(AgentDecisionAudit.helpRequested(help, sessionID: "s-3", at: stamp))
        XCTAssertEqual(record?.outcome, .pendingApproval, "卡在等人办")
        XCTAssertEqual(record?.resolvedOrigin, .notice)
        XCTAssertTrue(record?.sql.hasPrefix("helpRequested information") == true, "类别进机器码：\(record?.sql ?? "")")
        XCTAssertTrue(record?.detail?.contains(help.ask) == true, "卡上那句「要什么」要进账")
    }

    /// 不合格的求助单（缺「要什么」或「为什么」）不出卡也不留账 —— 那种卡本来就不该出。
    func testUnusableHelpIsNotRecorded() {
        let empty = AgentHelpRequest(kind: .information, ask: "   ", why: "反正就是不行")
        XCTAssertFalse(empty.isActionable)
        XCTAssertNil(AgentDecisionAudit.helpRequested(empty, at: stamp))
        let noWhy = AgentHelpRequest(kind: .grant, ask: "给我一个端点", why: "")
        XCTAssertNil(AgentDecisionAudit.helpRequested(noWhy, at: stamp))
    }

    // MARK: - 语言与形状

    /// 英文界面下附注不许漏汉字（这一格是给人读的，必须跟着界面语言走）。
    func testRecordsFollowTheInterfaceLanguage() {
        let recall = AgentGateRecall(prompt: "p", reason: "reason", trigger: trigger())
        let records = [AgentDecisionAudit.gateSkipped(recall, language: .english, at: stamp),
                       AgentDecisionAudit.gateForced(recall, language: .english, at: stamp),
                       AgentDecisionAudit.helpRequested(AgentHelpCatalogue.missingLoop(language: .english),
                                                        language: .english, at: stamp)].compactMap { $0 }
        XCTAssertEqual(records.count, 3)
        for record in records {
            XCTAssertFalse(containsHan(record.detail ?? ""), "英文界面下不该出现汉字：\(record.detail ?? "")")
            // 机器码永远是 ASCII（导出后要能 grep），与界面语言无关。
            XCTAssertFalse(containsHan(record.sql), "语句列是机器面，不许跟着语言变：\(record.sql)")
        }
    }

    /// 边界：超长理由把「语句」列撑爆之前就被截断（一条日志不该被一段理由撑成几屏）。
    func testLongReasonDoesNotInflateTheMachineColumn() {
        let longReason = String(repeating: "因为上下文没有变化所以不必再问一遍", count: 40)
        let recall = AgentGateRecall(prompt: String(repeating: "x", count: 2_000),
                                     reason: longReason,
                                     trigger: trigger(digest: String(repeating: "f", count: 64)))
        let record = AgentDecisionAudit.gateSkipped(recall, at: stamp)
        XCTAssertLessThanOrEqual(record.sql.count, AgentActionRecord.requestSummaryLimit + 1)
        XCTAssertEqual(record.sql.split(separator: " ").last.map(String.init), "ffffffff", "指纹只留 8 位")
    }

    /// 落盘 / 读回：新档位必须能过 `agent-audit.jsonl` 的编解码（老日志那条 `nil ⇒ .action` 的口径不变）。
    func testNoticeOriginSurvivesDiskRoundTrip() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("agent-decision-audit-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = AgentAuditLog(directoryURL: directory)
        let recall = AgentGateRecall(prompt: "p", reason: "同样的问法刚问过", trigger: trigger())
        try await log.append(AgentDecisionAudit.gateSkipped(recall, sessionID: "s-4", at: stamp))
        let entries = try await log.entries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.resolvedOrigin, .notice)
        XCTAssertEqual(entries.first?.sessionID, "s-4")
    }

    // MARK: - 接线：界面模型真的把决定交给了审计口

    /// 宿主没接装配 ⇒ 求助卡出，同时**审计里要有一行**（此前只有屏上有）。
    @MainActor
    func testChatModelAuditsHelpCardWhenLoopIsMissing() async {
        let sink = memorySink()
        let model = AgentChatModel()
        model.endpointProvider = { .ready(model: "m", endpoint: "https://example.invalid") }
        model.refreshEndpoint()
        model.makeLoop = { _, _, _ in nil }
        model.auditSink = sink.sink
        model.input = "看一下这个库"
        await model.send()

        let records = sink.read()
        XCTAssertEqual(records.count, 1, "求助卡一条，不多不少")
        XCTAssertEqual(records.first?.resolvedOrigin, .notice)
        XCTAssertTrue(records.first?.sql.hasPrefix("helpRequested") == true, "记的是求助卡：\(records.first?.sql ?? "")")
    }

    /// 一轮失败 ⇒ 主动通知那一格要进审计（页内条出、系统按「在不在看」判）。
    @MainActor
    func testChatModelAuditsNotificationWhenTurnFails() async {
        let sink = memorySink()
        let model = AgentChatModel()
        model.endpointProvider = { .ready(model: "m", endpoint: "https://example.invalid") }
        model.refreshEndpoint()
        model.auditSink = sink.sink
        model.paneIsVisible = { true }
        model.makeLoop = { _, _, _ in
            (loop: AgentLoop(client: ThrowingClient(), dispatcher: QuietDispatcher()),
             context: AgentLoopContext(systemPrompt: "你是助手。",
                                       userPrompt: "跑一下",
                                       baseRequest: LLMRequest(endpoint: URL(string: "http://127.0.0.1:9/v1")!,
                                                               model: "fake",
                                                               systemPrompt: "",
                                                               userPrompt: ""),
                                       sessionID: "s-wire",
                                       workspace: "ws-wire"))
        }
        model.input = "跑一下"
        await model.send()
        // 失败会先走重试与退避（`LLMRetryPolicy`）⇒ 给足时间，别把它读成「没留痕」。
        await waitUntil(timeout: 20) { sink.read().contains { $0.sql.hasPrefix("notified") } }

        let records = sink.read()
        XCTAssertTrue(records.contains { $0.sql.hasPrefix("notified") },
                      "失败的那一轮要通知，通知也要留痕：\(records.map(\.sql))")
        for record in records {
            XCTAssertEqual(record.resolvedOrigin, .notice, "所有决定记录的来源都是这一档")
            XCTAssertEqual(record.sessionID, model.sessionID, "会话号取界面模型的那一个，日志才能按会话串起来")
        }
    }

    /// 同一个问法连发两次 ⇒ 第二次被门控挡下并**留痕**；按「仍然发送」再发一次 ⇒ 硬发那一条也留痕。
    ///
    /// 这一段是「挡下 / 仍然发送」的可查性来源：屏上那条提示与那两个按钮此前都不进日志。
    @MainActor
    func testChatModelAuditsGateSkipAndForceSend() async {
        let sink = memorySink()
        let model = AgentChatModel()
        model.endpointProvider = { .ready(model: "m", endpoint: "https://example.invalid") }
        model.refreshEndpoint()
        model.auditSink = sink.sink
        model.makeLoop = { _, _, _ in
            (loop: AgentLoop(client: AnsweringClient(), dispatcher: QuietDispatcher()),
             context: AgentLoopContext(systemPrompt: "你是助手。",
                                       userPrompt: "同一个问题",
                                       baseRequest: LLMRequest(endpoint: URL(string: "http://127.0.0.1:9/v1")!,
                                                               model: "fake",
                                                               systemPrompt: "",
                                                               userPrompt: ""),
                                       sessionID: "s-gate",
                                       workspace: "ws-gate"))
        }
        model.input = "同一个问题"
        await model.send()
        await waitUntil { model.state.isRunning == false }
        // 第二遍：提示词逐字相同 ⇒ 门控挡下（省 token 的那一刀）。
        model.input = "同一个问题"
        await model.send()
        await waitUntil { sink.read().contains { $0.sql.hasPrefix("gateSkipped") } }
        XCTAssertNotNil(model.gateRecall, "挡下之后界面上要留那两个按钮")
        let skipped = sink.read().filter { $0.sql.hasPrefix("gateSkipped") }
        XCTAssertEqual(skipped.count, 1, "挡几次就记几条：\(sink.read().map(\.sql))")
        XCTAssertEqual(skipped.first?.outcome, .denied)

        // 按「仍然发送」：同一份提示词硬发一次，审计里与挡下**成对**。
        await model.forceSend()
        await waitUntil { sink.read().contains { $0.sql.hasPrefix("gateForced") } }
        XCTAssertEqual(sink.read().filter { $0.sql.hasPrefix("gateForced") }.count, 1)
    }

    /// 源码面：四条决定都有投影，且**只有一个落审计的出口**（`auditDecision`）。
    ///
    /// 为什么要扫源码：这是口径问题 —— 只要有一条决定绕开那个出口，屏上照样看得见、
    /// 日志里就是缺一条，而判据是绿的（此前三条能力的缺口正是这么留下来的）。
    func testEveryDecisionHasOneExitInTheChatModel() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("App/AgentChatModel.swift"),
                                encoding: .utf8)
        for kind in ["gateSkipped", "gateForced", "notification", "helpRequested"] {
            XCTAssertTrue(source.contains("AgentDecisionAudit.\(kind)("),
                          "`AgentDecisionAudit.\(kind)` 在界面模型里没有投影 ⇒ 那条决定不留痕")
        }
        XCTAssertEqual(source.components(separatedBy: "func auditDecision(").count - 1, 1,
                       "落审计的出口只许一个（两条路就是两套口径）")
    }

    /// 等一个条件成立（最多 2 秒）：界面模型把一轮跑在单独的 Task 里，收尾是异步的。
    @MainActor
    private func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    // MARK: - 夹具

    private final class ThrowingClient: LLMStreamingClient, @unchecked Sendable {
        func stream(_ request: LLMRequest) async throws -> AsyncThrowingStream<LLMStreamEvent, Error> {
            throw LLMError.transport("连不上：测试用假客户端")
        }
    }

    private final class QuietDispatcher: AgentToolDispatcher, @unchecked Sendable {
        func dispatch(_ invocation: AgentToolInvocation, approvals: Set<String>) -> AgentToolOutcome {
            .file(AgentToolFileOutput(path: "a.txt", text: "", truncated: false, totalBytes: 0))
        }
    }

    /// 一跳就收尾的假模型（用来把「同一问法连发两次」跑到门控那一格）。
    private final class AnsweringClient: LLMStreamingClient, @unchecked Sendable {
        func stream(_ request: LLMRequest) async throws -> AsyncThrowingStream<LLMStreamEvent, Error> {
            AsyncThrowingStream { continuation in
                continuation.yield(.textDelta("看过了。"))
                continuation.yield(.finished(reason: "stop"))
                continuation.yield(.done)
                continuation.finish()
            }
        }
    }
}
