import XCTest
@testable import DoyahCore

/// `FR-STD-DB-TASK-001`（一句话 → 一条可执行任务）的判据。
///
/// 钉的是三条验收要点 + 概设 §5.3 的两条禁令：
/// ① 任务可保存并在下次复用；② 目标库与定义不符时拒绝并说明；③ 只读任务里出现写语句被拦下；
/// 以及「禁止绕过上限」与「不许把定义与实际参数不一致的请求发出去」。
///
/// 反例（改坏一处 ⇒ 本文件必须红）见 `.agent/evidence/2026-10-28-DB-TASK-001.md`。
final class SQLTaskDefinitionTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dsh-sqltask-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    // MARK: - 夹具

    private let connectionID = UUID()

    private func task(
        name: String = "每日对账",
        sql: String = "select * from orders",
        database: String = "zxvmax",
        accessMode: SQLTaskDefinition.AccessMode = .readOnly,
        rowLimit: Int? = nil,
        requiresApproval: Bool = true
    ) -> SQLTaskDefinition {
        SQLTaskDefinition(
            name: name,
            sql: sql,
            connectionID: connectionID,
            connectionName: "本机 217",
            targetDatabase: database,
            accessMode: accessMode,
            rowLimit: rowLimit,
            requiresApproval: requiresApproval
        )
    }

    private func execution(
        database: String? = "zxvmax",
        accessMode: SQLTaskDefinition.AccessMode = .writable,
        rowLimit: Int? = nil,
        sql: String = "select * from orders"
    ) -> SQLTaskExecution {
        SQLTaskExecution(
            connectionID: connectionID,
            database: database,
            accessMode: accessMode,
            rowLimit: rowLimit,
            sql: sql
        )
    }

    // MARK: - ① 可保存并在下次复用

    func testDefaultsFollowOverview() {
        let value = SQLTaskDefinition(name: "n", sql: "select 1", targetDatabase: "db")
        XCTAssertEqual(value.accessMode, .readOnly, "概设 §5.3：读写模式默认只读")
        XCTAssertTrue(value.requiresApproval, "概设 §5.3：默认需审批")
        XCTAssertNil(value.rowLimit, "概设 §5.3：上限是选填")
        XCTAssertTrue(value.isValid)
    }

    func testSaveThenReuseFromFreshStore() async throws {
        let store = SQLTaskStore(directoryURL: root)
        let saved = try await store.save(task(name: "  每日对账  ", rowLimit: 100))

        // 另一个实例读同一个目录 —— 「下次复用」就是这条路径（不是内存里那份数组）。
        let reopened = SQLTaskStore(directoryURL: root)
        let all = try await reopened.tasks()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.id, saved.id)
        XCTAssertEqual(all.first?.name, "每日对账", "存的时候去首尾空白")
        XCTAssertEqual(all.first?.rowLimit, 100)
        XCTAssertEqual(all.first?.targetDatabase, "zxvmax")
        // 文件里就是一条 JSON 数组，没有第二份真相。
        let location = await reopened.fileLocation()
        XCTAssertEqual(location.lastPathComponent, "sql-tasks.json")
    }

    func testDuplicateNameRejectedAndFileUntouched() async throws {
        let store = SQLTaskStore(directoryURL: root)
        try await store.save(task(name: "对账"))
        let other = task(name: " 对账 ")  // 去空白后同名，id 不同
        do {
            _ = try await store.save(other)
            XCTFail("同名不同 id 必须被拒")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("同名任务"), error.localizedDescription)
        }
        let all = try await store.tasks()
        XCTAssertEqual(all.count, 1, "拒了就一条都不许多")
    }

    func testSameIDSaveIsInPlaceAndKeepsCreatedAt() async throws {
        let store = SQLTaskStore(directoryURL: root)
        let first = try await store.save(task(name: "对账"))
        var edited = first
        edited.sql = "select 1"
        edited.rowLimit = 50
        let second = try await store.save(edited)

        let all = try await store.tasks()
        XCTAssertEqual(all.count, 1, "同 id 是原地改，不是新增一条")
        // 落盘走 ISO8601（到秒）：比的是**盘上那份**的创建时刻没被这次保存冲掉。
        XCTAssertEqual(second.createdAt.timeIntervalSince1970,
                       all.first?.createdAt.timeIntervalSince1970 ?? -1,
                       accuracy: 0.001)
        XCTAssertEqual(all.first?.rowLimit, 50)
    }

    func testIncompleteDefinitionListsEveryIssue() async throws {
        let store = SQLTaskStore(directoryURL: root)
        let broken = SQLTaskDefinition(
            name: "   ",
            sql: "\n\t",
            targetDatabase: " ",
            rowLimit: 0
        )
        XCTAssertEqual(broken.issues().count, 4, "四个问题一次列全：空名 / 空语句 / 空库 / 上限非正")
        do {
            _ = try await store.save(broken)
            XCTFail("不完整的定义不许进文件")
        } catch let error {
            let text = error.localizedDescription
            XCTAssertTrue(text.contains("任务名不能为空"), text)
            XCTAssertTrue(text.contains("没有语句"), text)
            XCTAssertTrue(text.contains("目标库"), text)
            XCTAssertTrue(text.contains("正整数"), text)
        }
        let all = try await store.tasks()
        XCTAssertTrue(all.isEmpty)
    }

    func testDeleteLeavesOthers() async throws {
        let store = SQLTaskStore(directoryURL: root)
        let a = try await store.save(task(name: "A"))
        let b = try await store.save(task(name: "B"))
        try await store.delete(id: a.id)
        let all = try await store.tasks()
        XCTAssertEqual(all.map(\.id), [b.id])
    }

    // MARK: - ② 目标库与定义不符 ⇒ 拒绝并说明

    func testDatabaseMismatchRefusedAndSaysBothNames() {
        var planned = execution()
        planned.database = "another_db"
        let verdict = SQLTaskGuard.check(task: task(database: "zxvmax"), execution: planned)

        XCTAssertTrue(verdict.isRefused)
        let text = verdict.message
        XCTAssertTrue(text.contains("zxvmax"), "要说清定义的那个库：\(text)")
        XCTAssertTrue(text.contains("another_db"), "也要说清这次要跑的库：\(text)")
        XCTAssertTrue(text.contains("不符"), text)
        XCTAssertTrue(verdict.statements.isEmpty, "库不符时不列语句：一条都不会发")
    }

    func testMissingDatabaseIsRefusedNotAssumed() {
        var planned = execution()
        planned.database = nil
        let verdict = SQLTaskGuard.check(task: task(), execution: planned)
        XCTAssertTrue(verdict.isRefused, "没选定库不等于「就是定义那个库」")
        XCTAssertTrue(verdict.message.contains("还没选定库"), verdict.message)
    }

    func testConnectionMismatchRefused() {
        var planned = execution()
        planned.connectionID = UUID()
        let verdict = SQLTaskGuard.check(task: task(), execution: planned)
        XCTAssertTrue(verdict.isRefused)
        XCTAssertTrue(verdict.message.contains("另一个连接"), verdict.message)
    }

    // MARK: - ③ 只读任务里的写语句必须拦下

    func testReadOnlyTaskRefusesWriteStatements() {
        var planned = execution()
        planned.sql = "select 1;\nupdate orders set note = 'x';\ndelete from orders where id = 1"
        let verdict = SQLTaskGuard.check(task: task(accessMode: .readOnly), execution: planned)

        XCTAssertTrue(verdict.isRefused)
        XCTAssertEqual(verdict.statements.count, 2, "两条写语句各列一条：\(verdict.statements)")
        XCTAssertTrue(verdict.message.contains("只读"), verdict.message)
    }

    func testReadOnlyTaskAllowsPureSelect() {
        var planned = execution()
        planned.sql = "select id from orders where id = 1"
        let verdict = SQLTaskGuard.check(
            task: task(accessMode: .readOnly, requiresApproval: true),
            execution: planned
        )
        XCTAssertEqual(verdict, .allow, "纯读不该被拦，也不该问审批")
    }

    func testWritableTaskOnReadOnlyConnectionRefused() {
        var planned = execution()
        planned.accessMode = .readOnly
        planned.sql = "update orders set note = 'x' where id = 1"
        let verdict = SQLTaskGuard.check(task: task(accessMode: .writable), execution: planned)
        XCTAssertTrue(verdict.isRefused)
        XCTAssertTrue(verdict.message.contains("只读连接"), verdict.message)
    }

    // MARK: - 上限：不许绕过

    func testRowLimitLoosenedIsRefused() {
        // ① 这次没带上限
        let noLimit = SQLTaskGuard.check(
            task: task(accessMode: .writable, rowLimit: 100),
            execution: execution(rowLimit: nil, sql: "update orders set note = 'x' where id = 1")
        )
        XCTAssertTrue(noLimit.isRefused, "定义有上限、这次没带 ⇒ 拒")
        XCTAssertTrue(noLimit.message.contains("100"), noLimit.message)

        // ② 这次要更大的上限
        let looser = SQLTaskGuard.check(
            task: task(accessMode: .writable, rowLimit: 100),
            execution: execution(rowLimit: 500, sql: "update orders set note = 'x' where id = 1")
        )
        XCTAssertTrue(looser.isRefused, "放宽上限 ⇒ 拒")
        XCTAssertTrue(looser.message.contains("500"), looser.message)
    }

    func testRowLimitStricterIsAllowed() {
        let verdict = SQLTaskGuard.check(
            task: task(accessMode: .writable, rowLimit: 100, requiresApproval: false),
            execution: execution(rowLimit: 10, sql: "update orders set note = 'x' where id = 1")
        )
        XCTAssertEqual(verdict, .allow, "收紧上限不是绕过，放行")
    }

    // MARK: - 审批：只在真会改东西时问人

    func testWritesNeedApprovalWhenDefinitionSaysSo() {
        let verdict = SQLTaskGuard.check(
            task: task(accessMode: .writable, requiresApproval: true),
            execution: execution(sql: "delete from orders where id = 1")
        )
        guard case .needsApproval(let reasons, let statements) = verdict else {
            return XCTFail("可写任务默认要审批，实际：\(verdict)")
        }
        XCTAssertEqual(statements.count, 1)
        XCTAssertTrue(reasons.contains { $0.contains("要求执行前审批") }, reasons.joined(separator: " / "))
        XCTAssertTrue(reasons.contains { $0.contains("zxvmax") }, "审批单要写目标库")
    }

    func testApprovalNotRequiredWhenDefinitionSaysNo() {
        let verdict = SQLTaskGuard.check(
            task: task(accessMode: .writable, requiresApproval: false),
            execution: execution(sql: "update orders set note = 'x' where id = 1")
        )
        XCTAssertEqual(verdict, .allow)
    }

    func testHandEditedDefinitionRefusedAtExecution() {
        // 文件可能被手改过：执行前再判一次定义完整性。
        var broken = task()
        broken.targetDatabase = "   "
        let verdict = SQLTaskGuard.check(task: broken, execution: execution(database: "   "))
        XCTAssertTrue(verdict.isRefused)
        XCTAssertTrue(verdict.message.contains("定义不完整"), verdict.message)
    }

    // MARK: - 执行之后的读数：超限与「没量到」必须分得开

    func testRowVerdictFourCases() {
        XCTAssertEqual(SQLTaskGuard.rowVerdict(limit: nil, actual: 9_999), .unlimited)
        XCTAssertEqual(SQLTaskGuard.rowVerdict(limit: 100, actual: 100), .within(limit: 100, actual: 100))
        XCTAssertEqual(SQLTaskGuard.rowVerdict(limit: 100, actual: 101), .exceeded(limit: 100, actual: 101))
        XCTAssertEqual(SQLTaskGuard.rowVerdict(limit: 100, actual: nil), .unmeasured(limit: 100))
    }

    func testUnmeasuredIsNotReadAsZero() {
        let unmeasured = SQLTaskGuard.rowVerdict(limit: 100, actual: nil)
        XCTAssertFalse(unmeasured.isExceeded)
        XCTAssertNotEqual(unmeasured, .within(limit: 100, actual: 0), "没读数不等于动了 0 行")
        XCTAssertTrue(unmeasured.message.contains("拿不到影响行数"), unmeasured.message)

        XCTAssertEqual(SQLTaskGuard.rowVerdict(limit: 100, actual: 0).message, "",
                       "没超限不吭声（正常执行不该多一行噪音）")
        XCTAssertTrue(SQLTaskGuard.rowVerdict(limit: 3, actual: 4).isExceeded)
    }

    // MARK: - 判定口唯一：写语句的识别与「只读连接」那条路同一套词法

    func testWriteStatementDetectionMatchesGuardrailLexicon() {
        let writes = SQLTaskGuard.writeStatements(
            in: "select 1; insert into t values (1); truncate table t",
            databaseType: .postgresql
        )
        XCTAssertEqual(writes.count, 2, "\(writes)")
        // 与既有只读连接判定同一结果（同一段 SQL 走两条路必须同口径）。
        let safety = ExecutionSafety.check(
            sql: "select 1; insert into t values (1); truncate table t",
            databaseType: .postgresql,
            policy: ExecutionSafetyPolicy(isEnabled: false, isReadOnly: true)
        )
        if case .refused(_, let offenders) = safety {
            XCTAssertEqual(offenders.count, writes.count)
        } else {
            XCTFail("同一段 SQL 在只读连接那条路上应被拒：\(safety)")
        }
    }

    func testTaskIsCodableRoundTrip() throws {
        let value = task(accessMode: .writable, rowLimit: 20, requiresApproval: false)
        let data = try JSONEncoder().encode(value)
        let back = try JSONDecoder().decode(SQLTaskDefinition.self, from: data)
        XCTAssertEqual(back, value, "存下来再读回必须逐字段相同（复用靠这条）")
    }
}
