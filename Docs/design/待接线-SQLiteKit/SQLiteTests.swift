import XCTest
@testable import DoyahCore
import SQLiteKit

// 这一组用例只经 `SQLiteKit`（绑定层）判错 —— **不 import C 模块**：
// C 互操作集中在绑定层一个目标里，测试用它的语义判断（`isBusy` / `isConstraintViolation`…）
// 与 `codeName` 反向钉住码表，比在测试里再抄一遍 C 常量更不容易漂。

/// `SQLiteKit/SQLite.swift`（薄封装）+ vendored `sqlite3.c` 的机械证据（FR-PLUG-08 / Q23 拍板）。
///
/// 这一组用例刻意都跑在**临时目录的真数据库文件**上，不走 `:memory:`：
/// WAL、并发写、坏文件 —— 这三件事在内存库里根本不存在，用内存库测等于把最有价值的三条覆盖丢掉。
///
/// 用例分四类，对应四条口径：
///   ① **版本与编译宏自证** —— 跑起来的必须是**我们 vendor 的这一份**，四条宏必须真的生效；
///   ② **五种存储类往返** —— NULL / 空串 / 0 / 零长 blob 不许被混为一谈；
///   ③ **并发与事务** —— WAL + `BEGIN IMMEDIATE` + 嵌套 `SAVEPOINT`（笔记库会多进程读写）；
///   ④ **失败要说清楚** —— 坏文件 / 锁竞争 / 用已关闭的连接：错误码与语义判断都在类型上。
final class SQLiteTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("doyah-sqlite-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    private func databaseURL(_ name: String = "notes.sqlite3") -> URL {
        directory.appendingPathComponent(name, isDirectory: false)
    }

    /// 建一个最小的笔记式 schema（不是生产 schema —— 生产 schema 随存储层落地，见队列 L-25 第 2 批）。
    private func makeSchema(_ connection: SQLiteConnection) throws {
        try connection.execute(
            """
            CREATE TABLE note (
                id TEXT PRIMARY KEY NOT NULL,
                title TEXT NOT NULL,
                body TEXT NOT NULL DEFAULT '',
                updated_at REAL NOT NULL
            );
            """
        )
    }

    // MARK: - ① 版本与编译宏自证

    /// 跑起来的 SQLite 就是 vendored 的那一份（版本 + `SQLITE_SOURCE_ID` 双钉）。
    ///
    /// 这条为什么重要：`sqlite3_libversion()` 读的是**链接进来的实现**。若哪天有人把
    /// `CSQLite3` 换成系统 `libsqlite3` 或第三方封装，版本会跟着 OS 漂 —— 这条用例当场红。
    func testVendoredLibraryVersionIsPinned() {
        XCTAssertEqual(SQLiteConnection.libraryVersion, "3.53.4")
        XCTAssertEqual(
            SQLiteConnection.librarySourceID,
            "2026-07-24 19:02:57 bf7c7f30031888f4e796e429ab3978879485813aaca6f641c7b33e4e09459bcc"
        )
    }

    /// 四条编译宏真的生效（`sqlite3_compileoption_used` 是宏的机械判据）。
    ///
    /// 宏掉了不会有任何症状：编译过、打包过、单测过，只是行为悄悄变掉 —— 所以这里逐条断言。
    func testRequiredCompileOptionsAreInEffect() {
        XCTAssertTrue(SQLiteConnection.isCompiled(with: "SQLITE_ENABLE_FTS5"))
        XCTAssertTrue(SQLiteConnection.isCompiled(with: "SQLITE_OMIT_LOAD_EXTENSION"))
        XCTAssertTrue(SQLiteConnection.isCompiled(with: "SQLITE_THREADSAFE=1"))

        // `SQLITE_DQS=0` 不在 `compile_options` 列表里（它是编译期口径、不是可选特性名），
        // 所以它由行为证明：双引号不再是字符串字面量 —— 见下面的用例。
        let options = SQLiteConnection.compileOptions
        XCTAssertTrue(options.contains("ENABLE_FTS5"), "实际编译项：\(options)")
        XCTAssertTrue(options.contains("OMIT_LOAD_EXTENSION"), "实际编译项：\(options)")
        XCTAssertTrue(options.contains("THREADSAFE=1"), "实际编译项：\(options)")
    }

    /// `SQLITE_DQS=0` 的行为证据：双引号包着的**不存在的列名**必须当场报错，
    /// 而不是被静默当成字符串字面量（那一档会让「列名写错」变成「查出来一个常量」）。
    func testDoubleQuotedIdentifierIsNotAStringLiteral() throws {
        let connection = try SQLiteConnection(path: databaseURL().path)
        try makeSchema(connection)
        XCTAssertThrowsError(try connection.query("SELECT \"no_such_column\" FROM note")) { error in
            let failure = error as? SQLiteFailure
            XCTAssertEqual(failure?.codeName, "SQLITE_ERROR")
            XCTAssertTrue(failure?.message.contains("no such column") ?? false, "原话：\(failure?.message ?? "nil")")
        }
        // 单引号仍是字符串字面量（正常 SQL），不会被 DQS=0 误伤。
        XCTAssertEqual(try connection.scalarText("SELECT 'ok'"), "ok")
    }

    /// FTS5 不只是宏里有个 1 —— 真建虚拟表、真检索。
    func testFTS5IsUsable() throws {
        let connection = try SQLiteConnection(path: databaseURL().path)
        try connection.execute("CREATE VIRTUAL TABLE note_fts USING fts5(title, body);")
        try connection.execute("INSERT INTO note_fts(title, body) VALUES (?, ?)", [.text("索引重建"), .text("VACUUM 之后的全文索引")])
        try connection.execute("INSERT INTO note_fts(title, body) VALUES (?, ?)", [.text("别的"), .text("无关内容")])
        let rows = try connection.query("SELECT title FROM note_fts WHERE note_fts MATCH ? ORDER BY title", [.text("全文")])
        XCTAssertEqual(rows.compactMap { $0.text("title") }, ["索引重建"])
    }

    // MARK: - ② 五种存储类往返

    /// NULL / 空串 / 0 / 零长 blob 各自是什么，读回来还得是什么 —— 「NULL 与空串不是一回事」
    /// 是笔记库里最容易出错的一处（列默认值、`COALESCE`、导出时的空判断都靠它）。
    func testFiveStorageClassesRoundTrip() throws {
        let connection = try SQLiteConnection(path: databaseURL().path)
        try connection.execute("CREATE TABLE sample (id INTEGER PRIMARY KEY, value);")
        try connection.execute("INSERT INTO sample (value) VALUES (?)", [.null])
        try connection.execute("INSERT INTO sample (value) VALUES (?)", [.text("")])
        try connection.execute("INSERT INTO sample (value) VALUES (?)", [.integer(0)])
        try connection.execute("INSERT INTO sample (value) VALUES (?)", [.real(0)])
        try connection.execute("INSERT INTO sample (value) VALUES (?)", [.blob([])])
        try connection.execute("INSERT INTO sample (value) VALUES (?)", [.blob([0, 1, 255])])
        try connection.execute("INSERT INTO sample (value) VALUES (?)", [.text("文本")])

        let values = try connection.query("SELECT value FROM sample ORDER BY id").map { $0[0] }
        XCTAssertEqual(values.count, 7)
        XCTAssertTrue(values[0].isNull)
        XCTAssertEqual(values[1], .text(""))
        XCTAssertEqual(values[2], .integer(0))
        XCTAssertEqual(values[3], .real(0))
        XCTAssertEqual(values[4], .blob([]))
        XCTAssertEqual(values[5], .blob([0, 1, 255]))
        XCTAssertEqual(values[6], .text("文本"))

        // 语义判断也分开：NULL 不是「假」，0 是「假」。
        XCTAssertNil(values[0].boolValue)
        XCTAssertEqual(values[2].boolValue, false)
        XCTAssertEqual(values[3].doubleValue, 0)
        XCTAssertNil(values[1].boolValue, "空串不是布尔值 —— 不猜")
    }

    func testParameterCountMismatchIsRejected() throws {
        let connection = try SQLiteConnection(path: databaseURL().path)
        try makeSchema(connection)
        // 两个占位符只给一个绑定值：**当场报错**，而不是绑成 NULL 悄悄写坏一行。
        XCTAssertThrowsError(try connection.query("SELECT ? , ?", [.integer(1)])) { error in
            XCTAssertEqual((error as? SQLiteFailure)?.codeName, "SQLITE_RANGE")
        }
    }

    func testLastInsertRowIDAndChangeCount() throws {
        let connection = try SQLiteConnection(path: databaseURL().path)
        try makeSchema(connection)
        try connection.execute(
            "INSERT INTO note (id, title, updated_at) VALUES (?, ?, ?)",
            [.text("a"), .text("第一行"), .real(1)]
        )
        XCTAssertEqual(connection.changeCount, 1)
        XCTAssertEqual(connection.lastInsertRowID, 1)
        try connection.execute("UPDATE note SET title = ? WHERE id = ?", [.text("改过"), .text("a")])
        XCTAssertEqual(connection.changeCount, 1)
        XCTAssertEqual(try connection.scalarText("SELECT title FROM note WHERE id = ?", [.text("a")]), "改过")
    }

    // MARK: - ③ 并发与事务

    /// WAL 是真开着的（返回值必须是 `wal`，不能只看「没报错」）。
    func testWALModeIsEnabled() throws {
        let url = databaseURL()
        let connection = try SQLiteConnection(path: url.path)
        XCTAssertEqual(try connection.pragma("journal_mode")?.textValue, "wal")
        try makeSchema(connection)
        try connection.execute(
            "INSERT INTO note (id, title, updated_at) VALUES (?, ?, ?)",
            [.text("a"), .text("标题"), .real(1)]
        )
        // WAL 模式下写进 `-wal` 旁文件（提交后才落主库），这正是「不把活跃库文件直接扔进云同步」的原因。
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path + "-wal"))
    }

    /// 第二个连接能读到第一个连接已提交的数据（多进程读的同一件事）。
    func testSecondConnectionSeesCommittedData() throws {
        let url = databaseURL()
        let writer = try SQLiteConnection(path: url.path)
        try makeSchema(writer)
        try writer.execute(
            "INSERT INTO note (id, title, updated_at) VALUES (?, ?, ?)",
            [.text("a"), .text("标题"), .real(1)]
        )
        let reader = try SQLiteConnection(path: url.path)
        XCTAssertEqual(try reader.scalarInt("SELECT count(*) FROM note"), 1)
    }

    /// 锁竞争要**如实报成 BUSY**（而不是「查不到」这类看起来正常的失败）。
    func testWriteContentionIsReportedAsBusy() throws {
        let url = databaseURL()
        let first = try SQLiteConnection(path: url.path, busyTimeout: 50)
        try makeSchema(first)
        let second = try SQLiteConnection(path: url.path, busyTimeout: 50)

        try first.transaction {
            try first.execute("INSERT INTO note (id, title, updated_at) VALUES ('a', 'a', 1)")
            // 第一个连接持有写事务时，第二个连接的写必然撞锁。
            XCTAssertThrowsError(try second.transaction {
                try second.execute("INSERT INTO note (id, title, updated_at) VALUES ('b', 'b', 2)")
            }) { error in
                let failure = error as? SQLiteFailure
                XCTAssertEqual(failure?.isBusy, true, "实际错误：\(String(describing: failure))")
                XCTAssertTrue(failure?.isConstraintViolation == false)
            }
        }
        XCTAssertEqual(try first.scalarInt("SELECT count(*) FROM note"), 1)
    }

    /// 事务：抛错要回滚，成功才提交。
    func testTransactionRollsBackOnError() throws {
        let connection = try SQLiteConnection(path: databaseURL().path)
        try makeSchema(connection)

        struct Boom: Error {}
        XCTAssertThrowsError(
            try connection.transaction {
                try connection.execute("INSERT INTO note (id, title, updated_at) VALUES ('a', 'a', 1)")
                throw Boom()
            }
        )
        XCTAssertEqual(try connection.scalarInt("SELECT count(*) FROM note"), 0)
        XCTAssertFalse(connection.isInTransaction, "回滚之后不该还留在事务里")

        try connection.transaction {
            try connection.execute("INSERT INTO note (id, title, updated_at) VALUES ('a', 'a', 1)")
        }
        XCTAssertEqual(try connection.scalarInt("SELECT count(*) FROM note"), 1)
    }

    /// 嵌套事务走 `SAVEPOINT`：内层失败**只回滚内层** —— 外层已经写的不能被带下去
    /// （否则「一条笔记失败、整批笔记没了」）。
    func testNestedTransactionRollsBackOnlyInnerScope() throws {
        let connection = try SQLiteConnection(path: databaseURL().path)
        try makeSchema(connection)

        struct Boom: Error {}
        try connection.transaction {
            try connection.execute("INSERT INTO note (id, title, updated_at) VALUES ('outer', 'outer', 1)")
            XCTAssertThrowsError(
                try connection.transaction {
                    try connection.execute("INSERT INTO note (id, title, updated_at) VALUES ('inner', 'inner', 2)")
                    throw Boom()
                }
            )
        }
        let ids = try connection.query("SELECT id FROM note ORDER BY id").compactMap { $0.text("id") }
        XCTAssertEqual(ids, ["outer"])
    }

    // MARK: - ④ 失败要说清楚

    /// 坏文件（不是 SQLite 格式）要报成 NOTADB / CORRUPT，而不是一句「失败」——
    /// 这一条对应笔记库的「坏文件回退并如实报告」纪律。
    func testNotADatabaseFileIsReported() throws {
        let url = databaseURL("broken.sqlite3")
        try Data("this is not a database, it is a text file".utf8).write(to: url)
        let connection = try SQLiteConnection(path: url.path)
        XCTAssertThrowsError(try connection.scalarInt("SELECT count(*) FROM sqlite_master")) { error in
            let failure = error as? SQLiteFailure
            XCTAssertEqual(failure?.isNotADatabase, true, "实际错误：\(String(describing: failure))")
            XCTAssertEqual(failure?.operation, .step)
        }
    }

    /// 只读连接不许写（权限口径要能在类型上判断）。
    func testReadOnlyConnectionRejectsWrites() throws {
        let url = databaseURL()
        let writable = try SQLiteConnection(path: url.path)
        try makeSchema(writable)
        let readonly = try SQLiteConnection(path: url.path, readOnly: true)
        XCTAssertEqual(try readonly.scalarInt("SELECT count(*) FROM note"), 0)
        XCTAssertThrowsError(try readonly.execute("INSERT INTO note (id, title, updated_at) VALUES ('a','a',1)")) { error in
            XCTAssertEqual((error as? SQLiteFailure)?.isReadOnly, true, "实际错误：\(String(describing: error))")
        }
    }

    /// 关闭是幂等的；关掉之后再调方法要抛 `SQLITE_MISUSE`（而不是静默返回空结果）。
    func testCloseIsIdempotentAndUseAfterCloseIsRejected() throws {
        let connection = try SQLiteConnection(path: databaseURL().path)
        try makeSchema(connection)
        try connection.close()
        try connection.close()
        XCTAssertFalse(connection.isOpen)
        XCTAssertThrowsError(try connection.query("SELECT 1")) { error in
            XCTAssertEqual((error as? SQLiteFailure)?.codeName, "SQLITE_MISUSE")
        }
        XCTAssertEqual(connection.changeCount, 0)
        XCTAssertEqual(connection.lastInsertRowID, 0)
    }

    /// schema 版本用 `PRAGMA user_version` 记账（迁移判据），对象清单能从 `sqlite_master` 读出来。
    func testSchemaVersionAndObjectListing() throws {
        let connection = try SQLiteConnection(path: databaseURL().path)
        XCTAssertEqual(try connection.scalarInt("PRAGMA user_version"), 0)
        try makeSchema(connection)
        try connection.setPragma("user_version = 1")
        XCTAssertEqual(try connection.scalarInt("PRAGMA user_version"), 1)
        XCTAssertEqual(try connection.schemaObjects(), ["note"])
        XCTAssertTrue(try connection.tableExists("note"))
        XCTAssertFalse(try connection.tableExists("没有这张表"))
    }

    /// `SQLiteFailure` 的语义判断与文案：认得出的码给名字，认不出的就只给数字（不猜）。
    func testFailureSemanticsAndDescription() {
        let busy = SQLiteFailure(code: SQLiteResultCode.busy, message: "database is locked", operation: .step)
        XCTAssertEqual(busy.codeName, "SQLITE_BUSY")
        XCTAssertTrue(busy.isBusy)
        XCTAssertFalse(busy.isConstraintViolation)
        XCTAssertTrue(busy.description.contains("SQLITE_BUSY"))

        // 扩展码：约束冲突的细分码落在低 8 位之外，`isConstraintViolation` 按**低 8 位**判，
        // 所以「主键冲突」（1555 = 19 | 6<<8）也接得住 —— 这正是笔记库 upsert 会撞的那一支。
        let violation = SQLiteFailure(
            code: SQLiteResultCode.constraint,
            message: "UNIQUE constraint failed: note.id",
            operation: .step,
            sql: "INSERT INTO note(id) VALUES (?)",
            extendedCode: SQLiteResultCode.constraintPrimaryKey
        )
        XCTAssertTrue(violation.isConstraintViolation)
        XCTAssertFalse(violation.isBusy)
        XCTAssertFalse(violation.isReadOnly)
        XCTAssertEqual(violation.codeName, "SQLITE_CONSTRAINT")
        XCTAssertTrue(violation.description.contains("INSERT INTO note"))

        let unknown = SQLiteFailure(code: 1234, message: "?", operation: .open)
        XCTAssertEqual(unknown.codeName, "code 1234")
    }

    /// **码表反向对账**：`SQLiteResultCode` 里那几个数字必须正是绑定层 `codeName` 认得的码。
    /// 少了这条，Swift 侧那份常量和 `sqlite3.h` 各说各话也没人知道（数字写错不会报错，只会判错分支）。
    func testResultCodeTableMatchesCodeNames() {
        let pairs: [(Int32, String)] = [
            (SQLiteResultCode.ok, "SQLITE_OK"),
            (SQLiteResultCode.error, "SQLITE_ERROR"),
            (SQLiteResultCode.busy, "SQLITE_BUSY"),
            (SQLiteResultCode.locked, "SQLITE_LOCKED"),
            (SQLiteResultCode.readOnly, "SQLITE_READONLY"),
            (SQLiteResultCode.range, "SQLITE_RANGE"),
            (SQLiteResultCode.notADatabase, "SQLITE_NOTADB"),
            (SQLiteResultCode.misuse, "SQLITE_MISUSE"),
            (SQLiteResultCode.constraint, "SQLITE_CONSTRAINT")
        ]
        for (code, name) in pairs {
            XCTAssertEqual(SQLiteFailure(code: code, message: "", operation: .step).codeName, name)
        }
        // 主键冲突是**扩展码**：它不该被当成另一个基础码（低 8 位才是基础码）。
        XCTAssertEqual(SQLiteResultCode.constraintPrimaryKey & 0xFF, SQLiteResultCode.constraint)
    }
}
