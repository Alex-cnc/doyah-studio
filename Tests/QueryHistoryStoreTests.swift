import XCTest
@testable import DoyahCore

// 队列 `HIST-1`（契约 `DR-02` 由「内存态」改判为**持久化** · SRS v3.327）的机械证据。
//
// 这一片落的三件东西：① schema **v7**（`query_history` 一张表）；② `NoteDatabase` 的写读口
// （upsertQueryHistory / queryHistory / pruneQueryHistory / clearQueryHistory / deleteQueryHistory /
// queryHistoryCount）；③ `QueryHistoryStore` 门面四件（load / append / clear / delete）。
//
// 三条纪律（与 `ReminderStorageTests` / `TodoStorageTests` 同形）：
//   ① **都跑真库文件**（临时目录，不用 `:memory:`）——「关掉再开还在」只在真文件上走得到；
//   ② **向前兼容用手搭的 v6 库**（拿 v1~v6 的 DDL 逐版建出来，里面真有笔记）：
//      用当前代码建的库永远是最新版，测不到「老库升上来」，而那正是这一片唯一有风险的路径；
//   ③ **写完读回**：判据读的是库里的那一份事实，不是内存里刚构造的那个值。
//
// 两条测试卫生：
//   · **时钟是注入的**：门面 `load` / `append` 都收 `now`，用例把一个固定时刻当「现在」传进去
//     —— 90 天那条上限因此测得准（拿真实时钟写死 2023 年的时间戳会被**正确**地当过期裁掉）。
//   · 门面是 actor（与 `NoteLibrary` 同一条），碰它的用例都是 `async` ＋ `await`；
//     `await` 不能落在 `XCTAssert*` 的 autoclosure 里，先取值再断言。
final class QueryHistoryStoreTests: XCTestCase {

    private var directory: URL!

    /// 用例里的「现在」（固定时钟）。
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("doyah-query-history-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    private func url(_ name: String = NoteDatabase.fileName) -> URL {
        directory.appendingPathComponent(name, isDirectory: false)
    }

    private func store() -> QueryHistoryStore {
        QueryHistoryStore(databaseURL: url())
    }

    private let connectionID = UUID()

    private func entry(
        sql: String,
        at executedAt: Date,
        succeeded: Bool = true,
        duration: TimeInterval = 0.5
    ) -> QueryHistory {
        QueryHistory(connectionID: connectionID, sql: sql, executedAt: executedAt, duration: duration, succeeded: succeeded)
    }

    // MARK: - ⓪ 门面上限 = 契约里的两个数（`DR-02`：500 条 / 90 天）

    func testFacadeLimitsMatchContractNumbers() {
        XCTAssertEqual(QueryHistoryStore.maxEntries, 500, "DR-02 明文：上限 500 条")
        XCTAssertEqual(QueryHistoryStore.maxAge, 90 * 24 * 60 * 60, "DR-02 明文：上限 90 天")
    }

    // MARK: - 判据① 写入 → 关库重开 ⇒ 仍在（这不是一次「会话内」的列表）

    func testAppendSurvivesReopen() async throws {
        let written = try await store().append(entry(sql: "SELECT 1", at: now), now: now)
        let identifier = try XCTUnwrap(written.first).id

        // 换一个全新的门面实例（模拟「重启」：没有任何常驻句柄，只有那个库文件）。
        let reloaded = try await store().load(now: now)
        XCTAssertEqual(reloaded.count, 1, "关库重开后历史必须还在")
        let roundTripped = try XCTUnwrap(reloaded.first)
        XCTAssertEqual(roundTripped.id, identifier, "id 原样往返（「只刷新最新一条」靠它）")
        XCTAssertEqual(roundTripped.connectionID, connectionID)
        XCTAssertEqual(roundTripped.sql, "SELECT 1")
        XCTAssertEqual(roundTripped.duration, 0.5, accuracy: 1e-9)
        XCTAssertEqual(roundTripped.succeeded, true)
        XCTAssertEqual(roundTripped.executedAt.timeIntervalSince1970, now.timeIntervalSince1970, accuracy: 1e-6)

        // 库这一侧也自证一句：schema 是本版（v7），表真的在。
        let database = try NoteDatabase(path: url().path)
        XCTAssertEqual(NoteSchemaV7.version, 7)
        XCTAssertEqual(database.userVersion, NoteDatabase.supportedVersion)
        XCTAssertTrue(try database.tableNames().contains("query_history"))
        XCTAssertEqual(try database.queryHistoryCount(), 1)
    }

    /// 失败那一次也照样落盘（`succeeded = 0` 原样往返）—— 历史不是「成功流水」，是执行台账。
    func testFailedExecutionRoundTripsAsFailed() async throws {
        _ = try await store().append(entry(sql: "SELECT nope", at: now, succeeded: false), now: now)
        let loaded = try await store().load(now: now)
        let only = try XCTUnwrap(loaded.first)
        XCTAssertFalse(only.succeeded, "失败必须如实落盘，不许写成成功")
    }

    /// 连续重复执行同一条 SQL：**只刷新最新一条**（复用 id ⇒ 库里仍是一行，不是两行）。
    func testRepeatedStatementRefreshesTheLatestRowInsteadOfAppending() async throws {
        let first = try await store().append(entry(sql: "SELECT 1", at: now, duration: 0.5), now: now)
        var repeatEntry = try XCTUnwrap(first.first)
        repeatEntry.executedAt = now.addingTimeInterval(10)
        repeatEntry.duration = 9.5

        let after = try await store().append(repeatEntry, now: now)
        XCTAssertEqual(after.count, 1, "同一条 SQL 再执行一次不该多出一行")
        let refreshed = try XCTUnwrap(after.first)
        XCTAssertEqual(refreshed.duration, 9.5, accuracy: 1e-9)
        XCTAssertEqual(refreshed.executedAt.timeIntervalSince1970, now.addingTimeInterval(10).timeIntervalSince1970, accuracy: 1e-6)
        // 库里那一份事实也对得上（不是只有回读列表变了）。
        XCTAssertEqual(try NoteDatabase(path: url().path).queryHistoryCount(), 1)
    }

    // MARK: - 判据② 写 501 条 ⇒ 只留 500（上限那一处在门面，不在界面）

    func testRetentionKeepsOnlyTheNewestFiveHundred() async throws {
        var latest: [QueryHistory] = []
        for index in 0..<501 {
            let moment = now.addingTimeInterval(TimeInterval(index))
            latest = try await store().append(entry(sql: "SELECT \(index)", at: moment), now: now)
        }

        XCTAssertEqual(latest.count, 500, "501 条写进去，回来就只能有 500 条")
        XCTAssertEqual(latest.first?.sql, "SELECT 500", "留下的是**最新**那 500 条")
        XCTAssertEqual(latest.last?.sql, "SELECT 1", "最老的（第 0 条）应当已被裁掉")
        XCTAssertFalse(latest.contains { $0.sql == "SELECT 0" }, "第 0 条必须不在")

        // 库里那一份事实与回读一致（不是只有内存列表缩了）。
        let database = try NoteDatabase(path: url().path)
        XCTAssertEqual(try database.queryHistoryCount(), 500)
        let reloaded = try await store().load(now: now)
        XCTAssertEqual(reloaded.count, 500)
    }

    // MARK: - 判据③ 早于 90 天 ⇒ 被裁（边界两侧各看一眼）

    func testEntriesOlderThanNinetyDaysArePruned() async throws {
        // 91 天前：超出时间上限 ⇒ 裁掉。
        _ = try await store().append(
            entry(sql: "SELECT old", at: now.addingTimeInterval(-91 * 24 * 60 * 60)),
            now: now
        )
        let afterOld = try await store().load(now: now)
        XCTAssertEqual(afterOld.count, 0, "早于 90 天的历史必须被裁掉")

        // 89 天前：还在窗口里 ⇒ 留着（证明上面那条不是「把所有东西都删了」）。
        _ = try await store().append(
            entry(sql: "SELECT young", at: now.addingTimeInterval(-89 * 24 * 60 * 60)),
            now: now
        )
        let kept = try await store().load(now: now)
        XCTAssertEqual(kept.map(\.sql), ["SELECT young"], "正好在 90 天内的那条要留下")
    }

    /// 启动加载也过一次裁剪：上一次运行遗留的过期历史不该等到「再执行一条」才被清掉。
    func testLoadAlsoPrunesStaleEntries() async throws {
        _ = try await store().append(
            entry(sql: "SELECT historical", at: now.addingTimeInterval(-120 * 24 * 60 * 60)),
            now: now
        )
        let reloaded = try await store().load(now: now)
        XCTAssertEqual(reloaded.count, 0, "load() 自己也要裁")
        XCTAssertEqual(try NoteDatabase(path: url().path).queryHistoryCount(), 0, "库里那行真的没了")
    }

    // MARK: - 判据④ 清空 / 单条删（各自 1 例；「二次确认」那一半归 HIST-2 的界面片）

    func testClearRemovesEveryRow() async throws {
        _ = try await store().append(entry(sql: "SELECT 1", at: now), now: now)
        _ = try await store().append(entry(sql: "SELECT 2", at: now.addingTimeInterval(1)), now: now)
        let before = try await store().load(now: now)
        XCTAssertEqual(before.count, 2, "清空之前先自证真的有两行")

        try await store().clear()

        let reloaded = try await store().load(now: now)
        XCTAssertEqual(reloaded.count, 0, "清空后回读必须是空表")
        XCTAssertEqual(try NoteDatabase(path: url().path).queryHistoryCount(), 0, "库里也该一行不剩")
    }

    func testDeleteRemovesOnlyTheGivenRow() async throws {
        let first = try await store().append(entry(sql: "SELECT 1", at: now), now: now)
        let identifier = try XCTUnwrap(first.first).id
        _ = try await store().append(entry(sql: "SELECT 2", at: now.addingTimeInterval(1)), now: now)

        try await store().delete(id: identifier)

        let remaining = try await store().load(now: now)
        XCTAssertEqual(remaining.map(\.sql), ["SELECT 2"], "只该少掉点掉的那一条")
        // 认不出的 id 是幂等的：再删一次不抛错、也不动别的行。
        try await store().delete(id: identifier)
        let afterSecond = try await store().load(now: now)
        XCTAssertEqual(afterSecond.map(\.sql), ["SELECT 2"])
    }

    /// 库还没建时不顺手建库（与 `NoteLibrary.load()` 同一条纪律）。
    func testLoadOnAbsentDatabaseDoesNotCreateIt() async throws {
        let reloaded = try await store().load(now: now)
        XCTAssertEqual(reloaded.count, 0)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: url().path),
            "只读一次历史不该把笔记库凭空建出来"
        )
    }

    // MARK: - 判据⑤ 向前兼容：v6 库打开 ⇒ 升到 v7，既有数据一字不动

    func testVersionSixDatabaseUpgradesToVersionSevenKeepingExistingRows() async throws {
        let note = Note(
            title: "存量笔记",
            body: "洞庭湖",
            tags: ["骑行"],
            source: NoteSource(kind: .manual, connectionName: "连接甲", fingerprint: "fp-1"),
            createdAt: now,
            updatedAt: now.addingTimeInterval(1)
        )
        try makeVersionSixDatabase(note: note)
        XCTAssertEqual(try rawUserVersion(), 6, "手搭的库确实停在 v6")

        // 打开（这一步就是「旧库遇到新代码」）：rc = 0、版本 +1、既有行数前后同值。
        let database = try NoteDatabase(path: url().path)
        XCTAssertEqual(database.userVersion, NoteDatabase.supportedVersion, "v6 库要升到 v7")
        XCTAssertEqual(database.userVersion, 7)
        XCTAssertEqual(try database.noteCount(), 1, "既有 note 行数前后同值")
        let existing = try XCTUnwrap(try database.note(id: note.id))
        XCTAssertEqual(existing.tags, ["骑行"], "既有笔记与标签原样在")
        XCTAssertEqual(try database.queryHistoryCount(), 0, "补表不带数据")

        // 升级后新表立刻能用（老库上的查询历史真的写得进去）。
        _ = try await store().append(entry(sql: "SELECT 1", at: now.addingTimeInterval(2)), now: now)
        let reloaded = try await store().load(now: now)
        XCTAssertEqual(reloaded.count, 1)
        XCTAssertEqual(try NoteDatabase(path: url().path).userVersion, 7, "幂等：再开一次仍是 v7")
    }

    // MARK: - 私有

    /// 手搭一个 **v6 库** —— 存量用户的库长什么样：v1~v6 的 DDL 都在、`user_version = 6`、
    /// 里面有一条真笔记（含标签）。
    private func makeVersionSixDatabase(note: Note) throws {
        let connection = try SQLiteConnection(path: url().path)
        for statement in NoteSchemaV1.ddl { try connection.execute(statement) }
        for statement in NoteSchemaV2.ddl { try connection.execute(statement) }
        for statement in NoteSchemaV3.ddl { try connection.execute(statement) }
        for statement in NoteSchemaV4.ddl { try connection.execute(statement) }
        for statement in NoteSchemaV5.ddl { try connection.execute(statement) }
        for statement in NoteSchemaV6.ddl { try connection.execute(statement) }
        try connection.execute(
            """
            INSERT INTO note (
                uuid, title, body, source_kind, source_connection_name, source_fingerprint,
                source_captured_at, created_at, updated_at, contains_row_data, storage_version,
                favorite, pinned
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, 0);
            """,
            [
                .text(note.id.uuidString),
                .text(note.title),
                .text(note.body),
                .text(note.source.kind.rawValue),
                .text(note.source.connectionName ?? ""),
                .text(note.source.fingerprint ?? ""),
                .real(note.source.capturedAt.timeIntervalSince1970),
                .real(note.createdAt.timeIntervalSince1970),
                .real(note.updatedAt.timeIntervalSince1970),
                .integer(note.containsRowData ? 1 : 0),
                .integer(Int64(NoteSchemaV1.version))
            ]
        )
        if let rowID = try connection.scalarInt("SELECT id FROM note WHERE uuid = ?", [.text(note.id.uuidString)]) {
            for tag in note.tags {
                try connection.execute("INSERT INTO note_tag (note_id, tag) VALUES (?, ?)", [.integer(rowID), .text(tag)])
            }
        }
        try connection.setPragma("user_version = \(NoteSchemaV6.version)")
        try connection.close()
    }

    /// 直接读库头（**不经** `NoteDatabase` —— 否则会被顺手升版，读不到「打开前」的那个数）。
    private func rawUserVersion() throws -> Int32 {
        let connection = try SQLiteConnection(path: url().path)
        defer { try? connection.close() }
        return Int32(try connection.scalarInt("PRAGMA user_version") ?? 0)
    }
}
