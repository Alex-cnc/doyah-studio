import XCTest
@testable import DoyahCore

/// `FR-AI-27` 定时 agent 的落盘（⑤ 的存储半）：条目全量 + 历史追加 —— 形状与 `FR-AI-06` 的 `DataTaskStore` 同一套。
///
/// 本文件只碰存储：写得进去、读得回来、判失败却给不出原因**写不进去**、删条目时历史一并清掉。
/// 时间一律注入（`epoch`）。
final class AgentScheduleStoreTests: XCTestCase {

    private var root: URL!
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-schedule-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - 夹具

    private func makeEntry(
        schedule: TaskSchedule? = nil,
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
            schedule: schedule ?? TaskSchedule(kind: .once, runAt: epoch.addingTimeInterval(3600)),
            isEnabled: isEnabled,
            createdAt: epoch,
            updatedAt: epoch
        )
    }

    private func makeStore() -> AgentScheduleStore {
        AgentScheduleStore(directoryURL: root)
    }

    // MARK: - 条目

    func testEmptyStoreReadsAsEmptyNotAsError() async throws {
        let store = makeStore()

        let entries = try await store.entries()
        let runs = try await store.runs()

        XCTAssertTrue(entries.isEmpty)
        XCTAssertTrue(runs.isEmpty)
    }

    func testSaveThenReadBackKeepsEveryField() async throws {
        let store = makeStore()
        let entry = makeEntry()

        try await store.save(entry)
        let stored = try await store.entries()

        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored[0].id, entry.id)
        XCTAssertEqual(stored[0].target, entry.target)
        XCTAssertEqual(stored[0].schedule, entry.schedule)
        XCTAssertEqual(stored[0].isEnabled, true)
        // 日期精确往返（ISO8601 · 秒级）
        XCTAssertEqual(stored[0].createdAt.timeIntervalSince1970, epoch.timeIntervalSince1970, accuracy: 0.5)
    }

    func testSavingSameIdentifierReplacesInsteadOfAppending() async throws {
        let store = makeStore()
        let id = UUID()
        var entry = makeEntry(id: id)
        try await store.save(entry)

        entry.target.title = "改名了"
        _ = try await store.save(entry)
        let stored = try await store.entries()

        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored[0].target.title, "改名了")
    }

    /// 验收要点 ④ 的存储半：翻开关只动 `isEnabled`，**碰不到 `createdAt`**
    /// （周期格点由创建时刻推，翻开关不该让格点漂）。
    func testSetEnabledKeepsCreatedAtAndFlipsOnlyTheSwitch() async throws {
        let store = makeStore()
        let id = UUID()
        try await store.save(makeEntry(id: id))

        let updated = try await store.setEnabled(false, id: id)

        XCTAssertEqual(updated?.isEnabled, false)
        XCTAssertEqual(updated?.createdAt.timeIntervalSince1970 ?? 0, epoch.timeIntervalSince1970, accuracy: 0.5)
        let stored = try await store.entries()
        XCTAssertEqual(stored[0].isEnabled, false)
    }

    /// 存盘 → 读回来的条目喂给判定机，停用档必须真的落在 `.disabled` 上（跨件读数，不是自己比自己）。
    func testDisabledEntryReadBackDecidesAsDisabled() async throws {
        let store = makeStore()
        let id = UUID()
        try await store.save(makeEntry(id: id))
        _ = try await store.setEnabled(false, id: id)

        let stored = try await store.entries()
        let decision = AgentSchedulePlanner.decision(
            for: stored[0],
            now: epoch.addingTimeInterval(7200)
        )

        XCTAssertEqual(decision, .disabled)
    }

    func testDeleteRemovesEntryAndItsHistory() async throws {
        let store = makeStore()
        let id = UUID()
        let keep = UUID()
        try await store.save(makeEntry(id: id))
        try await store.save(makeEntry(id: keep))
        try await store.appendRun(AgentScheduleRunRecord(entryID: id, startedAt: epoch, status: .succeeded))
        try await store.appendRun(AgentScheduleRunRecord(entryID: keep, startedAt: epoch, status: .succeeded))

        try await store.delete(id: id)

        let entries = try await store.entries()
        XCTAssertEqual(entries.map(\.id), [keep])
        let runs = try await store.runs()
        XCTAssertEqual(runs.map(\.entryID), [keep])
    }

    func testFileNamesMatchTheDataTaskConvention() async throws {
        let store = makeStore()
        let entriesName = await store.entriesFileLocation().lastPathComponent
        let runsName = await store.runsFileLocation().lastPathComponent

        XCTAssertEqual(entriesName, "agent-schedules.json")
        XCTAssertEqual(runsName, "agent-schedule-runs.jsonl")
    }

    // MARK: - 执行历史（⑤）

    func testAppendRunAndReadBack() async throws {
        let store = makeStore()
        let id = UUID()
        try await store.appendRun(
            AgentScheduleRunRecord(entryID: id, plannedAt: epoch, startedAt: epoch, status: .running)
        )

        let runs = try await store.runs()

        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs[0].entryID, id)
        XCTAssertEqual(runs[0].status, .running)
        XCTAssertEqual(runs[0].plannedAt?.timeIntervalSince1970 ?? 0, epoch.timeIntervalSince1970, accuracy: 0.5)
    }

    /// **失败不静默**：判 `failed` 而不给原因 ⇒ 抛错，且盘上一条都没多。
    func testFailedRunWithoutDetailIsRefusedAndNothingIsWritten() async throws {
        let store = makeStore()
        let id = UUID()

        do {
            try await store.appendRun(
                AgentScheduleRunRecord(entryID: id, startedAt: epoch, status: .failed)
            )
            XCTFail("判失败却不给原因，应当被拒收")
        } catch let error as AgentScheduleLedgerError {
            XCTAssertEqual(error, .failureWithoutDetail)
        }

        let runs = try await store.runs()
        XCTAssertTrue(runs.isEmpty)
    }

    func testFinishRunWritesBackTheTerminalState() async throws {
        let store = makeStore()
        let id = UUID()
        let record = AgentScheduleRunRecord(
            entryID: id,
            plannedAt: epoch,
            startedAt: epoch,
            status: .running,
            executedActions: ["read_file"]
        )
        try await store.appendRun(record)

        let finished = try await store.finishRun(
            id: record.id,
            status: .succeeded,
            at: epoch.addingTimeInterval(3),
            executedActions: ["read_file", "search"],
            withheldActions: ["write_file"]
        )

        XCTAssertEqual(finished.status, .succeeded)
        XCTAssertEqual(finished.duration ?? 0, 3, accuracy: 0.5)
        let runs = try await store.runs()
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs[0].executedActions, ["read_file", "search"])
        XCTAssertEqual(runs[0].withheldActions, ["write_file"])
    }

    func testFinishRunToFailedWithoutDetailIsRefused() async throws {
        let store = makeStore()
        let id = UUID()
        let record = AgentScheduleRunRecord(entryID: id, startedAt: epoch, status: .running)
        try await store.appendRun(record)

        do {
            _ = try await store.finishRun(id: record.id, status: .failed, at: epoch.addingTimeInterval(1))
            XCTFail("判失败却不给原因，应当被拒收")
        } catch let error as AgentScheduleLedgerError {
            XCTAssertEqual(error, .failureWithoutDetail)
        }

        let runs = try await store.runs()
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs[0].status, .running, "被拒的收尾不该改动盘上那一条")
    }

    func testFinishRunOnUnknownIdentifierReportsInsteadOfCreatingOne() async throws {
        let store = makeStore()

        do {
            _ = try await store.finishRun(id: UUID(), status: .succeeded, at: epoch)
            XCTFail("找不到那一条时应当如实报错，而不是悄悄新建")
        } catch let error as AgentScheduleLedgerError {
            if case .unknownRecord = error {} else {
                XCTFail("应当是 unknownRecord，实际 \(error)")
            }
        }
        let runs = try await store.runs()
        XCTAssertTrue(runs.isEmpty)
    }

    func testLastSuccessfulRunIgnoresFailedAndRunning() async throws {
        let store = makeStore()
        let id = UUID()
        try await store.appendRun(AgentScheduleRunRecord(entryID: id, startedAt: epoch, status: .failed, detail: "端点 502"))
        try await store.appendRun(AgentScheduleRunRecord(entryID: id, startedAt: epoch.addingTimeInterval(600), status: .running))
        try await store.appendRun(AgentScheduleRunRecord(entryID: id, startedAt: epoch.addingTimeInterval(1200), status: .succeeded))

        let last = try await store.lastSuccessfulRun(for: id)

        XCTAssertEqual(last?.timeIntervalSince1970 ?? 0, epoch.addingTimeInterval(1200).timeIntervalSince1970, accuracy: 0.5)
    }

    /// 历史是追加文件：一行坏掉**不该让整本账读不出来**（读不出的行跳过，其余照读）。
    func testCorruptedLineIsSkippedInsteadOfFailingTheWholeLedger() async throws {
        let store = makeStore()
        let id = UUID()
        try await store.appendRun(AgentScheduleRunRecord(entryID: id, startedAt: epoch, status: .succeeded))

        let runsURL = await store.runsFileLocation()
        let handle = try FileHandle(forWritingTo: runsURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{ 这不是一条记录 }\n".utf8))
        try handle.close()

        let runs = try await store.runs()

        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs[0].status, .succeeded)
    }

    /// 读回来的账里「判失败却给不出原因」的那些要能被如实报出来（正常写入路径写不进去，人手改过才可能）。
    func testSilentFailuresAreReportedFromTheLedger() async throws {
        let store = makeStore()
        let id = UUID()
        try await store.appendRun(AgentScheduleRunRecord(entryID: id, startedAt: epoch, status: .succeeded))

        let ledger = try await store.ledger()
        XCTAssertTrue(ledger.silentFailures.isEmpty)

        let ledgerWithOne = AgentScheduleLedger(records: ledger.records + [
            AgentScheduleRunRecord(entryID: id, startedAt: epoch.addingTimeInterval(60), status: .failed)
        ])
        XCTAssertEqual(ledgerWithOne.silentFailures.count, 1)
    }
}
