import XCTest
@testable import DoyahCore

/// `FR-AI-27` 定时 agent 的**界面半纯逻辑**：判定 → 档位、错过提示（②）、列表行、执行历史行（⑤）。
///
/// 两条口径在这里被钉住：
///   ① **状态与时间的词表整份复用 `FR-AI-06`** —— 断言直接与 `dataTaskStatus*` / `dataTaskRunStatus*`
///      两条既有键比，改词表两边一起动（不是各写一份人话）；
///   ② **Core 不写死人话** —— 每一句都从语言表取，中英各断言一次。
final class AgentSchedulePresentationTests: XCTestCase {

    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - 夹具

    private func makeEntry(
        kind: AgentScheduleTarget.Kind = .conversation,
        schedule: TaskSchedule? = nil,
        isEnabled: Bool = true,
        id: UUID = UUID()
    ) -> AgentScheduleEntry {
        AgentScheduleEntry(
            id: id,
            target: AgentScheduleTarget(
                kind: kind,
                title: "每日巡检",
                prompt: "看看昨天的订单有没有异常。",
                workspace: "orders"
            ),
            schedule: schedule ?? TaskSchedule(kind: .once, runAt: epoch.addingTimeInterval(3600)),
            isEnabled: isEnabled,
            createdAt: epoch,
            updatedAt: epoch
        )
    }

    // MARK: - 判定 → 档位（五档逐档，与数据任务同一档）

    func testDecisionMapsToTheFiveScheduleStatuses() {
        XCTAssertEqual(AgentSchedulePresentation.status(for: .notScheduled), .notScheduled)
        XCTAssertEqual(AgentSchedulePresentation.status(for: .disabled), .disabled)
        XCTAssertEqual(AgentSchedulePresentation.status(for: .waiting(until: epoch)), .waiting)
        XCTAssertEqual(AgentSchedulePresentation.status(for: .due(plannedAt: epoch)), .due)
        XCTAssertEqual(AgentSchedulePresentation.status(for: .missed(plannedAt: epoch, overdueBy: 120)), .missed)
    }

    func testStatusTextReusesTheDataTaskVocabulary() {
        for status in DataTaskPresentation.ScheduleStatus.allCases {
            XCTAssertEqual(
                AgentSchedulePresentation.statusText(status, language: .simplifiedChinese),
                LocalizedStrings.text(key(for: status), language: .simplifiedChinese)
            )
        }
    }

    func testRunStatusTextReusesTheDataTaskVocabulary() {
        XCTAssertEqual(
            AgentSchedulePresentation.runStatusText(.succeeded, language: .simplifiedChinese),
            LocalizedStrings.text(.dataTaskRunStatusSucceeded, language: .simplifiedChinese)
        )
        XCTAssertEqual(
            AgentSchedulePresentation.runStatusText(.skipped, language: .english),
            LocalizedStrings.text(.dataTaskRunStatusSkipped, language: .english)
        )
    }

    func testPlannedAtAndOverdueMinutes() {
        XCTAssertEqual(AgentSchedulePresentation.plannedAt(.due(plannedAt: epoch)), epoch)
        XCTAssertTrue(AgentSchedulePresentation.plannedAt(.disabled) == nil)

        // 不足 1 分钟按 1 分钟算（显示「晚了约 0 分钟」会让人以为没晚）
        XCTAssertEqual(AgentSchedulePresentation.overdueMinutes(.missed(plannedAt: epoch, overdueBy: 3)), 1)
        XCTAssertEqual(AgentSchedulePresentation.overdueMinutes(.missed(plannedAt: epoch, overdueBy: 120)), 2)
        XCTAssertNil(AgentSchedulePresentation.overdueMinutes(.waiting(until: epoch)))
    }

    // MARK: - ② 错过窗口：界面摆出「是否现在执行」，默认不补跑

    func testMissedPromptAppearsOnlyForTheMissedDecision() {
        let id = UUID()
        let missed = AgentSchedulePresentation.missedPrompt(
            for: .missed(plannedAt: epoch, overdueBy: 600),
            entryID: id,
            language: .simplifiedChinese
        )

        XCTAssertEqual(missed?.entryID, id)
        XCTAssertEqual(missed?.overdueMinutes, 10)
        XCTAssertEqual(missed?.plannedAt, epoch)
        XCTAssertEqual(
            missed?.text,
            LocalizedStrings.format(.dataTaskMissedNotice, language: .simplifiedChinese, 10)
        )

        for decision: ScheduleDecision in [.notScheduled, .disabled, .waiting(until: epoch), .due(plannedAt: epoch)] {
            XCTAssertNil(
                AgentSchedulePresentation.missedPrompt(for: decision, entryID: id, language: .simplifiedChinese),
                "\(decision) 不该给「是否现在执行」的提示"
            )
        }
    }

    func testMissedPromptFromEntryMatchesThePlannerDecision() {
        let entry = makeEntry(schedule: TaskSchedule(kind: .once, runAt: epoch))
        let now = epoch.addingTimeInterval(3600)

        let prompt = AgentSchedulePresentation.missedPrompt(
            for: entry,
            now: now,
            language: .simplifiedChinese
        )

        XCTAssertEqual(prompt?.plannedAt, epoch)
        XCTAssertEqual(prompt?.overdueMinutes, 60)
    }

    // MARK: - 下一次与调度一行

    func testNextRunTextIsNilWhenThereIsNoNextRun() {
        let disabled = makeEntry(schedule: TaskSchedule(kind: .once, runAt: epoch.addingTimeInterval(60)), isEnabled: false)
        XCTAssertNil(AgentSchedulePresentation.nextRunText(for: disabled, lastRun: nil, now: epoch))

        let overdue = makeEntry(schedule: TaskSchedule(kind: .once, runAt: epoch))
        XCTAssertNil(AgentSchedulePresentation.nextRunText(for: overdue, lastRun: nil, now: epoch.addingTimeInterval(3600)))

        let repeating = makeEntry(schedule: TaskSchedule(kind: .recurring, intervalSeconds: 3600, startAt: epoch))
        XCTAssertNotNil(AgentSchedulePresentation.nextRunText(for: repeating, lastRun: nil, now: epoch))
    }

    func testScheduleTextCoversTheThreeKinds() {
        XCTAssertEqual(
            AgentSchedulePresentation.scheduleText(.manual, language: .simplifiedChinese),
            LocalizedStrings.text(.dataTaskScheduleKindManual, language: .simplifiedChinese)
        )

        let once = AgentSchedulePresentation.scheduleText(
            TaskSchedule(kind: .once, runAt: epoch),
            language: .simplifiedChinese
        )
        XCTAssertTrue(once.hasPrefix(LocalizedStrings.text(.dataTaskScheduleKindOnce, language: .simplifiedChinese)))
        XCTAssertTrue(once.contains(AgentAuditPresentation.timestampText(epoch)))

        let recurring = AgentSchedulePresentation.scheduleText(
            TaskSchedule(kind: .recurring, intervalSeconds: 900, startAt: epoch),
            language: .english
        )
        XCTAssertTrue(recurring.contains("900"))
    }

    func testTargetKindTextCoversBothKinds() {
        XCTAssertEqual(
            AgentSchedulePresentation.targetKindText(.conversation, language: .simplifiedChinese),
            LocalizedStrings.text(.agentScheduleTargetConversation, language: .simplifiedChinese)
        )
        XCTAssertEqual(
            AgentSchedulePresentation.targetKindText(.agentTask, language: .english),
            LocalizedStrings.text(.agentScheduleTargetAgentTask, language: .english)
        )
    }

    // MARK: - 列表行

    func testRowCarriesStatusTargetAndDisabledHint() {
        let entry = makeEntry(isEnabled: false)
        let decision = AgentSchedulePlanner.decision(for: entry, now: epoch)

        let row = AgentSchedulePresentation.row(
            for: entry,
            decision: decision,
            now: epoch,
            language: .simplifiedChinese
        )

        XCTAssertEqual(row.entryID, entry.id)
        XCTAssertEqual(row.title, "每日巡检")
        XCTAssertTrue(row.targetText.contains(LocalizedStrings.text(.agentScheduleTargetConversation, language: .simplifiedChinese)))
        XCTAssertTrue(row.targetText.contains("orders"))
        XCTAssertEqual(row.statusText, LocalizedStrings.text(.dataTaskStatusDisabled, language: .simplifiedChinese))
        XCTAssertFalse(row.isEnabled)
        XCTAssertNotNil(row.disabledHint, "停用那一行要把话说出来")
    }

    func testEnabledRowHasNoDisabledHint() {
        let entry = makeEntry()
        let decision = AgentSchedulePlanner.decision(for: entry, now: epoch)

        let row = AgentSchedulePresentation.row(for: entry, decision: decision, now: epoch, language: .english)

        XCTAssertTrue(row.isEnabled)
        XCTAssertNil(row.disabledHint)
        XCTAssertNil(row.lastRunText, "还没跑过时不编一条")
    }

    func testRowLastRunTextCarriesStatusAndWithheldCount() {
        let entry = makeEntry()
        let decision = AgentSchedulePlanner.decision(for: entry, now: epoch)
        let record = AgentScheduleRunRecord(
            entryID: entry.id,
            plannedAt: epoch,
            startedAt: epoch.addingTimeInterval(5),
            status: .succeeded,
            executedActions: ["read_file"],
            withheldActions: ["write_file"]
        )

        let row = AgentSchedulePresentation.row(
            for: entry,
            decision: decision,
            latestRecord: record,
            now: epoch,
            language: .simplifiedChinese
        )

        XCTAssertEqual(
            row.lastRunText,
            AgentSchedulePresentation.runSummaryText(record, language: .simplifiedChinese)
        )
        XCTAssertTrue(row.lastRunText?.contains("被扣下 1 条") == true, "未审批不执行要看得见：\(row.lastRunText ?? "nil")")
    }

    func testRunSummaryTextOmitsTheWithheldClauseWhenNothingWasHeldBack() {
        let id = UUID()
        let clean = AgentScheduleRunRecord(entryID: id, startedAt: epoch, status: .succeeded, executedActions: ["read_file"])

        let text = AgentSchedulePresentation.runSummaryText(clean, language: .simplifiedChinese)

        XCTAssertFalse(text.contains("被扣下"))
        XCTAssertTrue(text.contains(LocalizedStrings.text(.dataTaskRunStatusSucceeded, language: .simplifiedChinese)))
    }

    // MARK: - ⑤ 执行历史

    func testHistoryRowsFilterByEntryAndCarryStatus() {
        let first = UUID()
        let second = UUID()
        let records = [
            AgentScheduleRunRecord(entryID: first, plannedAt: epoch, startedAt: epoch, status: .succeeded),
            AgentScheduleRunRecord(entryID: second, plannedAt: epoch, startedAt: epoch.addingTimeInterval(60), status: .skipped, detail: "错过窗口，未补跑")
        ]

        let all = AgentSchedulePresentation.historyRows(records, language: .simplifiedChinese)
        let onlyFirst = AgentSchedulePresentation.historyRows(records, for: first, language: .simplifiedChinese)

        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(onlyFirst.count, 1)
        XCTAssertEqual(onlyFirst[0].statusText, LocalizedStrings.text(.dataTaskRunStatusSucceeded, language: .simplifiedChinese))
        XCTAssertEqual(all[1].detailText, "错过窗口，未补跑")
    }

    func testHistoryRowMarksALateRunAsLate() {
        let id = UUID()
        let late = AgentScheduleRunRecord(
            entryID: id,
            plannedAt: epoch,
            startedAt: epoch.addingTimeInterval(900),
            status: .succeeded
        )
        let onTime = AgentScheduleRunRecord(entryID: id, plannedAt: epoch, startedAt: epoch, status: .succeeded)

        let rows = AgentSchedulePresentation.historyRows([late, onTime], language: .simplifiedChinese)

        XCTAssertTrue(rows.contains { $0.isLate })
        XCTAssertTrue(rows.contains { !$0.isLate })
    }

    func testHistoryRowHasNoDetailWhenThereIsNone() {
        let id = UUID()
        let record = AgentScheduleRunRecord(entryID: id, startedAt: epoch, status: .running)

        let row = AgentSchedulePresentation.historyRows([record], language: .english)[0]

        XCTAssertNil(row.detailText)
        XCTAssertNil(row.executedText)
        XCTAssertNil(row.withheldText)
        XCTAssertEqual(row.durationText, DataTaskPresentation.durationText(nil))
    }

    func testHistoryRowCarriesExecutedAndWithheldCounts() {
        let id = UUID()
        let record = AgentScheduleRunRecord(
            entryID: id,
            startedAt: epoch,
            finishedAt: epoch.addingTimeInterval(2),
            status: .succeeded,
            executedActions: ["read_file", "search"],
            withheldActions: ["write_file"]
        )

        let row = AgentSchedulePresentation.historyRows([record], language: .simplifiedChinese)[0]

        XCTAssertEqual(row.executedText, LocalizedStrings.format(.agentScheduleExecuted, language: .simplifiedChinese, 2))
        XCTAssertEqual(row.withheldText, LocalizedStrings.format(.agentScheduleWithheld, language: .simplifiedChinese, 1))
        XCTAssertEqual(row.durationText, DataTaskPresentation.durationText(2))
    }

    func testSilentFailuresComeFromTheLedger() {
        let ledger = AgentScheduleLedger(records: [
            AgentScheduleRunRecord(entryID: UUID(), startedAt: epoch, status: .failed)
        ])

        XCTAssertEqual(AgentSchedulePresentation.silentFailures(ledger).count, 1)
    }

    // MARK: - 计数

    func testCountsSplitEnabledDueAndMissed() {
        let due = makeEntry(schedule: TaskSchedule(kind: .once, runAt: epoch))
        let missed = makeEntry(schedule: TaskSchedule(kind: .once, runAt: epoch.addingTimeInterval(-7200)), id: UUID())
        let waiting = makeEntry(schedule: TaskSchedule(kind: .recurring, intervalSeconds: 3600, startAt: epoch.addingTimeInterval(7200)))
        let off = makeEntry(isEnabled: false)
        let entries = [due, missed, waiting, off]

        var decisions: [UUID: ScheduleDecision] = [:]
        for entry in entries {
            decisions[entry.id] = AgentSchedulePlanner.decision(for: entry, now: epoch, grace: 600)
        }
        let counts = AgentSchedulePresentation.counts(entries: entries, decisions: decisions)

        XCTAssertEqual(counts.total, 4)
        XCTAssertEqual(counts.enabled, 3)
        XCTAssertEqual(counts.disabled, 1)
        XCTAssertEqual(counts.due, 1)
        XCTAssertEqual(counts.missed, 1)
    }

    // MARK: - 内部

    private func key(for status: DataTaskPresentation.ScheduleStatus) -> LKey {
        switch status {
        case .notScheduled: return .dataTaskStatusNotScheduled
        case .disabled: return .dataTaskStatusDisabled
        case .waiting: return .dataTaskStatusWaiting
        case .due: return .dataTaskStatusDue
        case .missed: return .dataTaskStatusMissed
        }
    }
}
