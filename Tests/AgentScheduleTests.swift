import XCTest
@testable import DoyahCore

/// `FR-AI-27` 定时 agent：调度判定（纯时间计算）、错过不补跑、定时不构成授权、停用不排期、留痕与失败记录。
///
/// 五条验收要点逐条对应下面的分组。时间**一律注入**（`now:` 由判据给），
/// 因此每一档都钉在一个确定的 `Date` 上，与「今天几号」无关。
final class AgentScheduleTests: XCTestCase {

    private var root: URL!

    /// 固定参照时刻（判据不许依赖当时几点）。
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-schedule-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - 夹具

    private func makeEntry(
        schedule: TaskSchedule = .manual,
        isEnabled: Bool = true,
        id: UUID = UUID()
    ) -> AgentScheduleEntry {
        AgentScheduleEntry(
            id: id,
            target: AgentScheduleTarget(
                kind: .conversation,
                title: "每日巡检",
                prompt: "看看昨天的订单有没有异常。",
                workspace: "orders"
            ),
            schedule: schedule,
            isEnabled: isEnabled,
            createdAt: epoch,
            updatedAt: epoch
        )
    }

    private func once(at moment: Date) -> TaskSchedule {
        TaskSchedule(kind: .once, runAt: moment)
    }

    private func recurring(every interval: TimeInterval, from start: Date) -> TaskSchedule {
        TaskSchedule(kind: .recurring, intervalSeconds: interval, startAt: start)
    }

    // MARK: - ① 调度判定是纯时间计算，五档逐档可断言

    func testManualEntryIsNotScheduled() {
        let entry = makeEntry()

        XCTAssertEqual(
            AgentSchedulePlanner.decision(for: entry, now: epoch),
            .notScheduled,
            "手动档 = 未排期"
        )
        XCTAssertNil(AgentSchedulePlanner.nextRun(for: entry, after: epoch))
        XCTAssertEqual(AgentSchedulePlanner.plan(for: entry, now: epoch), .idle(reason: .notScheduled))
    }

    func testOnceEntryWaitsThenIsDueAtThePlannedMoment() {
        let runAt = epoch.addingTimeInterval(3_600)
        let entry = makeEntry(schedule: once(at: runAt))

        XCTAssertEqual(
            AgentSchedulePlanner.decision(for: entry, now: epoch),
            .waiting(until: runAt),
            "还没到点 ⇒ .waiting 且带上时刻"
        )
        XCTAssertEqual(
            AgentSchedulePlanner.decision(for: entry, now: runAt),
            .due(plannedAt: runAt),
            "正好到点 ⇒ .due（宽限默认 0，差一秒就不算到点）"
        )
        XCTAssertEqual(AgentSchedulePlanner.nextRun(for: entry, after: epoch), runAt)
    }

    func testOnceEntryWithNoRunTimeIsNotScheduled() {
        XCTAssertEqual(
            AgentSchedulePlanner.decision(for: makeEntry(schedule: TaskSchedule(kind: .once)), now: epoch),
            .notScheduled,
            "一次性任务没给时刻 = 排期参数不全 ⇒ 未排期"
        )
    }

    func testRecurringEntryLandsOnTheGridAndReportsTheNextRun() {
        let entry = makeEntry(schedule: recurring(every: 3_600, from: epoch))

        XCTAssertEqual(
            AgentSchedulePlanner.decision(for: entry, now: epoch.addingTimeInterval(7_200), lastRun: epoch.addingTimeInterval(3_600)),
            .due(plannedAt: epoch.addingTimeInterval(7_200)),
            "周期任务：上一个格点跑过 ⇒ 这一个格点到点"
        )
        XCTAssertEqual(
            AgentSchedulePlanner.nextRun(for: entry, after: epoch.addingTimeInterval(7_200), lastRun: epoch.addingTimeInterval(3_600)),
            epoch.addingTimeInterval(10_800),
            "下一次 = 下一个格点（格点算法在 TaskScheduler 那边）"
        )
        XCTAssertNil(
            AgentSchedulePlanner.nextRun(for: makeEntry(schedule: recurring(every: 3_600, from: epoch), isEnabled: false),
                                         after: epoch),
            "停用的周期任务没有「下一次」"
        )
    }

    func testPastWindowIsMissedWithItsOverdueBy() {
        let entry = makeEntry(schedule: once(at: epoch))

        let decision = AgentSchedulePlanner.decision(for: entry, now: epoch.addingTimeInterval(600))
        XCTAssertEqual(decision, .missed(plannedAt: epoch, overdueBy: 600))
        XCTAssertFalse(decision.isDue)
        XCTAssertFalse(decision.message.isEmpty, "错过要给可读提示（沿用 TaskScheduler 的文案）")
        XCTAssertTrue(decision.message.contains("错过"), "错过的提示沿用 TaskScheduler 既有文案")
        XCTAssertEqual(
            AgentSchedulePlanner.missedRuns(for: entry, from: epoch, to: epoch.addingTimeInterval(3_600)),
            [epoch],
            "错过了哪几次也要报得出来"
        )
    }

    // MARK: - ② 错过窗口默认不补跑（负例：不会自己跑起来）

    func testMissedWindowDoesNotRunByItself() {
        let entry = makeEntry(schedule: once(at: epoch))
        let now = epoch.addingTimeInterval(600)
        let read = AgentScheduleAction(name: "query_db", guardVerdict: .allow)

        let plan = AgentSchedulePlanner.plan(for: entry, now: now, actions: [read])

        XCTAssertFalse(plan.runs, "错过窗口**默认不补跑** —— 这一轮不起会话")
        XCTAssertEqual(plan.idleReason, .missed(plannedAt: epoch, overdueBy: 600))
        XCTAssertTrue(plan.executableActions.isEmpty, "不起会话就没有任何条目会执行")
        XCTAssertTrue(plan.withheldActions.isEmpty, "「没起会话」与「起会话但扣下条目」是两件事，不许混")

        // 界面拿 `Reason.message` 提示并给「是否现在执行」那一句。
        XCTAssertTrue((plan.idleReason?.message ?? "").contains("确认"), "错过要给「是否现在执行」的提示")

        // 留痕：错过这一件**记一条 skipped**（它正是「没补跑」的证据）。
        let record = plan.record(entryID: entry.id, startedAt: now)
        XCTAssertEqual(record?.status, .skipped)
        XCTAssertEqual(record?.plannedAt, epoch)
        XCTAssertTrue(record?.executedActions.isEmpty ?? false)
    }

    func testConfirmedMissedRunsOnceAndKeepsTheOriginalPlannedTime() {
        let entry = makeEntry(schedule: once(at: epoch))
        let now = epoch.addingTimeInterval(600)

        let plan = AgentSchedulePlanner.plan(for: entry, now: now, confirmedMissed: true)

        XCTAssertTrue(plan.runs, "用户显式确认后才起这一次会话")
        guard case .run(let plannedAt, _) = plan else { return XCTFail("应是 .run") }
        XCTAssertEqual(plannedAt, epoch, "记的仍是**原**计划时刻，不是「现在」")

        let record = plan.record(entryID: entry.id, startedAt: now)
        XCTAssertEqual(record?.status, .running)
        XCTAssertEqual(record?.plannedAt, epoch)
        XCTAssertEqual(record?.isLate, true, "留痕要能看出这一跑是晚的")
        XCTAssertEqual(record?.startedAt, now)
    }

    func testMissingWindowsInThePastAreNotBackfilledInBulk() {
        let entry = makeEntry(schedule: recurring(every: 900, from: epoch))
        let now = epoch.addingTimeInterval(3_600)

        // 客户端整天没打开：睡着的那 4 个格点**一次都不会自己跑**。
        let plan = AgentSchedulePlanner.plan(for: entry, now: now, lastRun: epoch)
        XCTAssertFalse(plan.runs)
        guard let reason = plan.idleReason, case .missed(_, let overdueBy) = reason else {
            return XCTFail("应是 .missed")
        }
        XCTAssertEqual(overdueBy, 2_700, "晚的是**最近**那个格点（每个格点各自成档）")
        XCTAssertTrue(plan.executableActions.isEmpty, "起都没起，条目一个都不执行")
        XCTAssertEqual(
            AgentSchedulePlanner.missedRuns(for: entry, from: epoch, to: now, lastRun: epoch).count,
            3,
            "睡着的 3 个格点只用来提示 / 记历史，**不用来补跑**（epoch 那一格已跑过，不算）"
        )
    }

    // MARK: - ④ 停用后不再排期（负例：一次都不起）

    func testDisabledEntryNeverSchedulesEvenWhenTheWindowIsDue() {
        let entry = makeEntry(schedule: once(at: epoch), isEnabled: false)
        let now = epoch.addingTimeInterval(3_600)
        let read = AgentScheduleAction(name: "query_db", guardVerdict: .allow)

        XCTAssertEqual(AgentSchedulePlanner.decision(for: entry, now: now), .disabled)
        XCTAssertNil(AgentSchedulePlanner.nextRun(for: entry, after: epoch))

        // 就算到点、就算用户确认过错过的那一次、就算批准齐了 —— 停用 ⇒ 一次都不起。
        let plan = AgentSchedulePlanner.plan(
            for: entry,
            now: now,
            actions: [read],
            approvals: AgentScheduleApprovals(granted: ["whatever"]),
            confirmedMissed: true
        )
        XCTAssertFalse(plan.runs, "停用 ⇒ 不再排期")
        XCTAssertEqual(plan.idleReason, .disabled)
        XCTAssertTrue(plan.executableActions.isEmpty, "假端点侧收到 0 次请求 / 动作侧 0 次执行")
        XCTAssertEqual(plan.idleReason?.message, ScheduleDecision.disabled.message, "提示沿用既有档位的话")

        // 未排期 / 停用 / 还没到这三档**不记账**：没有发生过的触发可言。
        XCTAssertNil(plan.record(entryID: entry.id, startedAt: now))
    }

    // MARK: - ③ 定时不构成授权：危险动作仍逐次审批（负例：未审批不执行）

    func testScheduledWriteWithoutApprovalIsHeldAndNotExecuted() {
        let tools = AgentWorkspaceTools(root: root)
        guard case .needsApproval(let request) = tools.prepareWrite(path: "note.txt", content: "由定时任务写入。") else {
            return XCTFail("写类要先出单（指纹由工具侧算）")
        }

        let entry = makeEntry(schedule: once(at: epoch))
        // 护栏对「写自己工作区里的文件」这一条放行；要批的是**工具侧那张单**。
        let action = AgentScheduleAction(name: request.toolName, guardVerdict: .allow, approval: request)

        let plan = AgentSchedulePlanner.plan(for: entry, now: epoch, actions: [action])

        XCTAssertTrue(plan.runs, "到点了，会话确实起")
        XCTAssertTrue(plan.executableActions.isEmpty, "写类未审批 ⇒ **不执行**（定时不构成授权）")
        XCTAssertEqual(plan.withheldActions.map(\.name), [request.toolName])
        XCTAssertEqual(
            plan.withheldActions.first?.disposition,
            .heldForApproval(fingerprint: request.fingerprint),
            "扣下时带上工具侧那个指纹，人才找得到那张单"
        )
        XCTAssertEqual(plan.withheldActions.first?.payload, request.payload, "差异预览进计划，人能看到要改什么")

        // 扣下的条目也要留痕（⑤：不静默）。
        let record = plan.record(entryID: entry.id, startedAt: epoch)
        XCTAssertEqual(record?.executedActions, [])
        XCTAssertEqual(record?.withheldActions, [request.toolName])
    }

    func testWriteStatementThatNeedsApprovalIsHeldEvenWithoutARequest() {
        let verdict = AgentGuardrail.evaluate(sql: "UPDATE orders SET total = 0 WHERE id = 1",
                                              policy: AgentGuardPolicy(readOnly: false))
        guard case .requireApproval = verdict.verdict else {
            return XCTFail("写语句按 FR-AI-09 一律逐次批准")
        }

        let action = AgentScheduleAction(name: "query_db", guardVerdict: verdict.verdict)
        XCTAssertEqual(
            action.disposition(approvals: .none),
            .heldForApproval(fingerprint: nil),
            "护栏说要批、而还没有单 ⇒ 扣下，不执行"
        )
    }

    func testApprovedWriteExecutesOnlyWithTheToolsOwnFingerprint() {
        let tools = AgentWorkspaceTools(root: root)
        guard case .needsApproval(let request) = tools.prepareWrite(path: "note.txt", content: "由定时任务写入。") else {
            return XCTFail("写类要先出单")
        }
        let entry = makeEntry(schedule: once(at: epoch))
        let action = AgentScheduleAction(name: request.toolName, guardVerdict: .allow, approval: request)

        // 同一张单的指纹 ⇒ 执行。
        let granted = AgentSchedulePlanner.plan(for: entry, now: epoch, actions: [action],
                                                approvals: AgentScheduleApprovals(granted: [request.fingerprint]))
        XCTAssertEqual(granted.executableActions.map(\.name), [request.toolName])

        // 别的指纹（换了参数 / 别处的批准）⇒ 仍扣下 —— 审批按**次**。
        let otherFingerprint = AgentSchedulePlanner.plan(for: entry, now: epoch, actions: [action],
                                                         approvals: AgentScheduleApprovals(granted: [request.fingerprint + "-x"]))
        XCTAssertTrue(otherFingerprint.executableActions.isEmpty, "指纹对不上就是没批")
    }

    func testRefusedActionIsNeverExecutedEvenWithAnApproval() {
        let denied = AgentGuardrail.evaluate(sql: "DELETE FROM orders", policy: .readOnlyDefault)
        guard case .deny = denied.verdict else { return XCTFail("只读模式必须拒绝写语句") }

        let action = AgentScheduleAction(name: "query_db", guardVerdict: denied.verdict)
        let disposition = action.disposition(approvals: AgentScheduleApprovals(granted: ["whatever"])
        )
        XCTAssertFalse(disposition.isExecuted, "策略拒绝**优先**于批准（批准不能突破只读模式）")
        if case .refused = disposition {} else { XCTFail("应是 .refused，而实际不是") }

        let entry = makeEntry(schedule: once(at: epoch))
        let plan = AgentSchedulePlanner.plan(for: entry, now: epoch, actions: [action],
                                             approvals: AgentScheduleApprovals(granted: ["whatever"]))
        XCTAssertTrue(plan.executableActions.isEmpty)
        XCTAssertEqual(plan.withheldActions.count, 1)
    }

    func testTargetFileStaysByteIdenticalWhenTheScheduledWriteIsNotApproved() throws {
        let target = root.appendingPathComponent("note.txt")
        try "原始内容\n".write(to: target, atomically: true, encoding: .utf8)
        let before = try Data(contentsOf: target)

        let tools = AgentWorkspaceTools(root: root)
        let dispatcher = AgentStandardDispatcher(workspace: tools)
        let call = AgentToolInvocation(name: "write_file",
                                       argumentsJSON: #"{"path":"note.txt","content":"被定时任务改掉了\n"}"#)

        guard case .needsApproval(let request) = dispatcher.dispatch(call, approvals: []) else {
            return XCTFail("写类要先出单")
        }

        let entry = makeEntry(schedule: once(at: epoch))
        let action = AgentScheduleAction(name: request.toolName, guardVerdict: .allow, approval: request)

        // 到点了，但审批队列里**没有任何决定**。
        let plan = AgentSchedulePlanner.plan(for: entry, now: epoch, actions: [action], approvals: .none)
        let grantedByPlan = Set(
            [action].filter { $0.disposition(approvals: .none).isExecuted }.compactMap(\.approval?.fingerprint)
        )
        XCTAssertTrue(grantedByPlan.isEmpty, "计划放行的条目里没有这一条写")

        // 未审批 ⇒ 分发器只**回到出单**（那一次写根本没发生）。
        guard case .needsApproval(let pending) = dispatcher.dispatch(call, approvals: grantedByPlan) else {
            return XCTFail("未审批的写**不许落盘**")
        }
        XCTAssertEqual(pending.fingerprint, request.fingerprint)
        XCTAssertEqual(try Data(contentsOf: target), before, "目标文件逐字节未变")

        // 指纹对不上（拿别处的批准来兑）⇒ 工具侧那一道也如实拒。
        let stale = tools.writeFile(path: "note.txt", content: "被定时任务改掉了\n",
                                    fingerprint: request.fingerprint + "-x", granted: [request.fingerprint + "-x"])
        guard case .refused(let staleCode, _) = stale else {
            return XCTFail("指纹对不上的批准不许落盘")
        }
        XCTAssertEqual(staleCode, .approvalRequired)
        XCTAssertEqual(try Data(contentsOf: target), before, "被拒两次，目标文件仍逐字节未变")

        // 正控：把**这一条**的具体批准给上 ⇒ 真落盘（前后两个读数都在，才算证明）。
        let approved = AgentSchedulePlanner.plan(for: entry, now: epoch, actions: [action],
                                                 approvals: AgentScheduleApprovals(granted: [request.fingerprint]))
        XCTAssertEqual(approved.executableActions.map(\.name), [request.toolName])
        guard case .wrote(let written) = dispatcher.dispatch(call, approvals: [request.fingerprint]) else {
            return XCTFail("批准后才真写")
        }
        XCTAssertEqual(written.text, "被定时任务改掉了\n")
        XCTAssertNotEqual(try Data(contentsOf: target), before, "批了就该真的改了")
    }

    // MARK: - ⑤ 每次触发与结果留痕（时间 / 条目 / 结果状态），失败不静默

    func testTriggerAndResultAreRecordedWithTimeActionsAndStatus() throws {
        let entry = makeEntry(schedule: once(at: epoch))
        let tools = AgentWorkspaceTools(root: root)
        guard case .needsApproval(let request) = tools.prepareWrite(path: "note.txt", content: "写一句话。") else {
            return XCTFail("写类要先出单")
        }
        let read = AgentScheduleAction(name: "query_db", guardVerdict: .allow)
        let write = AgentScheduleAction(name: request.toolName, guardVerdict: .allow, approval: request)

        let plan = AgentSchedulePlanner.plan(for: entry, now: epoch, actions: [read, write])
        guard let started = plan.record(entryID: entry.id, startedAt: epoch) else {
            return XCTFail("起了一次会话就必须留痕")
        }

        // 时间 / 条目 / 结果状态 —— 三样都在。
        XCTAssertEqual(started.status, .running)
        XCTAssertEqual(started.plannedAt, epoch)
        XCTAssertEqual(started.startedAt, epoch)
        XCTAssertEqual(started.executedActions, ["query_db"])
        XCTAssertEqual(started.withheldActions, [request.toolName], "扣下的条目也在留痕里，不静默")
        XCTAssertNil(started.duration, "还没结束就没有耗时")

        var ledger = AgentScheduleLedger()
        try ledger.record(started)
        let finished = try ledger.finish(id: started.id, status: .succeeded, at: epoch.addingTimeInterval(12))
        XCTAssertEqual(finished.status, .succeeded)
        XCTAssertEqual(finished.duration, 12)
        XCTAssertEqual(finished.executedActions, ["query_db"], "收尾时条目原样留着")
        XCTAssertEqual(ledger.records.count, 1)
        XCTAssertTrue(ledger.failures(for: entry.id).isEmpty)
        XCTAssertEqual(ledger.lastSuccessfulRun(for: entry.id), epoch)
    }

    func testFailedRecordWithoutDetailIsRejectedAndTheLedgerKeepsNothing() throws {
        let entryID = UUID()
        var ledger = AgentScheduleLedger()

        let silent = AgentScheduleRunRecord(entryID: entryID, plannedAt: epoch, startedAt: epoch, status: .failed)
        XCTAssertFalse(silent.hasFailureDetail)
        XCTAssertThrowsError(try ledger.record(silent)) { error in
            XCTAssertEqual(error as? AgentScheduleLedgerError, .failureWithoutDetail)
        }
        XCTAssertTrue(ledger.records.isEmpty, "失败不静默：给不出原因的失败**不入账**")

        // 收尾判失败同样必须给原因，而且抛错时账上一个字都不动。
        let running = AgentScheduleRunRecord(entryID: entryID, plannedAt: epoch, startedAt: epoch)
        try ledger.record(running)
        XCTAssertThrowsError(try ledger.finish(id: running.id, status: .failed, at: epoch)) { error in
            XCTAssertEqual(error as? AgentScheduleLedgerError, .failureWithoutDetail)
        }
        XCTAssertEqual(ledger.records.first?.status, .running, "没记上就不是失败")

        // 给了原因（人话由调用方从语言表给）⇒ 记下来，并且看得到。
        try ledger.finish(id: running.id, status: .failed, at: epoch.addingTimeInterval(3), detail: "连接超时")
        XCTAssertEqual(ledger.failures(for: entryID).count, 1)
        XCTAssertEqual(ledger.failures(for: entryID).first?.detail, "连接超时")
        XCTAssertTrue(ledger.silentFailures.isEmpty)
    }

    func testLedgerReportsSilentFailuresReadBackFromDisk() {
        let entryID = UUID()
        let fromDisk = AgentScheduleRunRecord(entryID: entryID, plannedAt: epoch, startedAt: epoch, status: .failed)
        let withReason = AgentScheduleRunRecord(entryID: entryID, plannedAt: epoch, startedAt: epoch,
                                               status: .failed, detail: "写盘失败")

        let ledger = AgentScheduleLedger(records: [fromDisk, withReason])

        XCTAssertEqual(ledger.silentFailures.map { $0.id }, [fromDisk.id],
                       "读回来的账里静默失败也要报出来（不许当没发生）")
        XCTAssertEqual(ledger.failures(for: entryID).count, 2)
    }

    func testLedgerFinishOnAnUnknownRecordIsReportedNotInvented() throws {
        var ledger = AgentScheduleLedger()
        let ghost = UUID()

        XCTAssertThrowsError(try ledger.finish(id: ghost, status: .succeeded, at: epoch)) { error in
            XCTAssertEqual(error as? AgentScheduleLedgerError, .unknownRecord(ghost))
        }
        XCTAssertTrue(ledger.records.isEmpty, "认不出的 id ⇒ 如实报，不悄悄新建一条")
    }

    func testSuccessfulRunFeedsTheNextDecision() throws {
        let entryID = UUID()
        let entry = makeEntry(schedule: once(at: epoch), id: entryID)
        var ledger = AgentScheduleLedger()
        try ledger.record(AgentScheduleRunRecord(entryID: entryID, plannedAt: epoch, startedAt: epoch,
                                                finishedAt: epoch.addingTimeInterval(1), status: .succeeded,
                                                executedActions: ["query_db"]))

        let lastRun = ledger.lastSuccessfulRun(for: entryID)
        XCTAssertEqual(lastRun, epoch)
        XCTAssertEqual(
            AgentSchedulePlanner.decision(for: entry, now: epoch.addingTimeInterval(10), lastRun: lastRun),
            .notScheduled,
            "跑过的一次性任务回到「未排期」—— 判定仍由 FR-AI-06 的 TaskScheduler 给"
        )
    }

    // MARK: - 源码锚点：复用与「不读时钟」

    private func coreSourceURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Core")
            .appendingPathComponent("AgentSchedule.swift")
    }

    func testCoreFileNeverReadsTheClock() throws {
        let source = try String(contentsOf: coreSourceURL(), encoding: .utf8)

        XCTAssertFalse(source.contains("Date()"), "时间一律由调用方传入：件内不许出现读钟调用")
        XCTAssertFalse(source.contains("Date.now"), "同上")
        XCTAssertFalse(source.contains("DispatchQueue"), "也不许自己起定时器 / 定时队列")
        XCTAssertFalse(source.contains("Timer"), "判定是纯时间计算，不起定时器、不持状态")
    }

    func testDecisionVocabularyIsReusedFromTaskScheduler() throws {
        let source = try String(contentsOf: coreSourceURL(), encoding: .utf8)

        // 三个判定口**转交**给 FR-AI-06，不另造一套时间计算。
        for call in ["TaskScheduler.decision", "TaskScheduler.nextRun", "TaskScheduler.missedRuns"] {
            XCTAssertTrue(source.contains(call), "判定应当转交给 FR-AI-06 的 TaskScheduler")
        }
        // 档位与排期形状也整份沿用它 —— 本件里不许再定义一遍。
        XCTAssertTrue(source.contains("ScheduleDecision"))
        XCTAssertTrue(source.contains("TaskSchedule"))
        XCTAssertFalse(source.contains("case notScheduled"), "档位词表不许另造一份")
        XCTAssertFalse(source.contains("enum ScheduleDecision"), "档位类型不许另造一份")
        XCTAssertFalse(source.contains("struct TaskSchedule"), "排期形状不许另造一份")
    }
}
