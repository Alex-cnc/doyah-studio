import XCTest
@testable import DoyahCore

/// `FR-STD-DB-TASK-003`（执行回执）的判据。
///
/// 钉的是三条验收 + 一句否定面：
/// ① 回执含四项读数（成功 / 失败 · 影响行数 · 耗时 · 错误原文）与执行时刻；
/// ② 可复制 / 导出且**已脱敏**（回执里不许出现口令与敏感字面量）；
/// ③ 失败也有回执（不因报错丢失）；
/// 以及「不把『完成』当回执」—— 所以「没测到影响行数」与「动了 0 行」必须能分开读，
/// 「被拦下」与「执行失败」也必须是两条。
///
/// 反例（改坏一处 ⇒ 本文件必须红）见 `.agent/evidence/2026-10-29-DB-TASK-003.md`。
final class ExecutionReceiptTests: XCTestCase {

    // MARK: - 夹具

    private let fixedDate = Date(timeIntervalSince1970: 1_790_000_000)
    private var utc: TimeZone { TimeZone(identifier: "UTC")! }

    private func labels() -> ExecutionReceipt.ReceiptLabels {
        ExecutionReceipt.ReceiptLabels(
            title: "执行回执",
            executedAt: "执行时刻",
            outcome: "结局",
            duration: "耗时",
            durationFormat: "%.3f 秒",
            affectedRows: "影响行数",
            affectedRowsUnmeasured: "未测到",
            statements: "语句数",
            connection: "连接",
            database: "库",
            scope: "范围",
            results: "结果集",
            resultsFormat: "%d 个 · 共 %d 行 × %d 列",
            resultsTruncated: "其中 %d 个被截断",
            error: "错误原文",
            sql: "SQL",
            redaction: "脱敏",
            redactionFormat: "%d 处（口令 %d · 连接串 %d）",
            outcomes: [
                .succeeded: "成功",
                .failed: "失败",
                .cancelled: "已取消",
                .refused: "未发出"
            ]
        )
    }

    private func receipt(
        sql: String = "select id, name from users where name = 'ann'",
        outcome: ExecutionOutcome = .succeeded,
        affectedRows: Int? = 3,
        errorText: String? = nil,
        duration: TimeInterval = 0.4215,
        results: ExecutionReceipt.ResultReading =
            ExecutionReceipt.ResultReading(resultSetCount: 1, rowCount: 40, columnCount: 6, truncatedCount: 0)
    ) -> ExecutionReceipt {
        ExecutionReceipt(
            executedAt: fixedDate,
            duration: duration,
            connectionName: "本机 217",
            database: "zxvmax",
            scopeTitle: "整篇",
            statementCount: 2,
            outcome: outcome,
            affectedRows: affectedRows,
            results: results,
            sql: sql,
            errorText: errorText
        )
    }

    // MARK: - ① 四项读数与执行时刻

    func testSucceededReceiptCarriesFourReadingsAndExecutedAt() {
        let value = receipt()
        XCTAssertEqual(value.outcome, .succeeded)
        XCTAssertEqual(value.affectedRows, 3)
        XCTAssertEqual(value.duration, 0.4215, accuracy: 0.0001)
        XCTAssertEqual(value.results.rowCount, 40)
        XCTAssertEqual(value.executedAt, fixedDate)
        // 上下文三样（审计要知道「在哪跑、跑的是哪一段」）
        XCTAssertEqual(value.connectionName, "本机 217")
        XCTAssertEqual(value.database, "zxvmax")
        XCTAssertEqual(value.scopeTitle, "整篇")
        XCTAssertEqual(value.statementCount, 2)
    }

    func testRenderContainsAllFourReadings() {
        let text = receipt(errorText: nil).render(labels: labels(), timeZone: utc)
        XCTAssertTrue(text.contains("执行回执"), text)
        XCTAssertTrue(text.contains("结局：成功"), text)
        XCTAssertTrue(text.contains("影响行数：3"), text)
        XCTAssertTrue(text.contains("耗时：0.421 秒") || text.contains("耗时：0.422 秒"), text)
        XCTAssertTrue(text.contains("结果集：1 个 · 共 40 行 × 6 列"), text)
        XCTAssertTrue(text.contains("执行时刻：2026-09-21"), text)
        XCTAssertTrue(text.contains("连接：本机 217"), text)
        XCTAssertTrue(text.contains("库：zxvmax"), text)
        XCTAssertTrue(text.contains("select id, name from users"), text)
    }

    func testRenderIsDeterministic() {
        let value = receipt()
        let first = value.render(labels: labels(), timeZone: utc)
        let second = value.render(labels: labels(), timeZone: utc)
        XCTAssertEqual(first, second)
    }

    // MARK: - ③ 失败 / 被拦下 / 取消各有回执，且都不是「成功」

    func testFailureReceiptKeepsErrorText() {
        let value = receipt(outcome: .failed, affectedRows: nil, errorText: "ERROR: relation \"nope\" does not exist")
        XCTAssertEqual(value.outcome, .failed)
        XCTAssertEqual(value.errorText, "ERROR: relation \"nope\" does not exist")
        let text = value.render(labels: labels(), timeZone: utc)
        XCTAssertTrue(text.contains("结局：失败"), text)
        XCTAssertTrue(text.contains("错误原文：ERROR: relation"), text)
    }

    func testRefusedReceiptIsNeitherFailedNorSucceeded() {
        let value = receipt(outcome: .refused, affectedRows: nil, errorText: "只读连接：拒绝执行写语句")
        XCTAssertNotEqual(value.outcome, .failed)
        XCTAssertNotEqual(value.outcome, .succeeded)
        let text = value.render(labels: labels(), timeZone: utc)
        XCTAssertTrue(text.contains("结局：未发出"), text)
    }

    func testCancelledReceiptIsNotSuccess() {
        let value = receipt(outcome: .cancelled, affectedRows: nil, errorText: "已取消")
        XCTAssertNotEqual(value.outcome, .succeeded)
        XCTAssertTrue(value.render(labels: labels(), timeZone: utc).contains("结局：已取消"))
    }

    func testUnmeasuredAffectedRowsIsNotZero() {
        let unmeasured = receipt(affectedRows: nil)
        let text = unmeasured.render(labels: labels(), timeZone: utc)
        XCTAssertTrue(text.contains("影响行数：未测到"), text)
        XCTAssertFalse(text.contains("影响行数：0"), "没读数不许读成 0 行：\(text)")

        // 对照件：真的是 0 行（语句报过行数）⇒ 就写 0
        let zero = receipt(affectedRows: 0)
        XCTAssertTrue(zero.render(labels: labels(), timeZone: utc).contains("影响行数：0"))
    }

    func testTruncatedResultIsReportedOnReceipt() {
        let value = receipt(
            results: ExecutionReceipt.ResultReading(resultSetCount: 1, rowCount: 10_000, columnCount: 4, truncatedCount: 1)
        )
        XCTAssertTrue(value.render(labels: labels(), timeZone: utc).contains("其中 1 个被截断"))
    }

    // MARK: - ② 脱敏（四类形状）

    func testPasswordClauseLiteralIsMasked() {
        let value = receipt(sql: "ALTER USER bob PASSWORD 'hunter2'")
        XCTAssertFalse(value.sql.contains("hunter2"), value.sql)
        XCTAssertTrue(value.sql.contains("PASSWORD '***'"), value.sql)
        XCTAssertEqual(value.redaction.passwordLiterals, 1)
        XCTAssertEqual(value.redaction.urlCredentials, 0)
        XCTAssertFalse(value.redaction.isClean)
    }

    func testIdentifiedByLiteralIsMasked() {
        let value = receipt(sql: "CREATE USER bob IDENTIFIED BY 's3cret'")
        XCTAssertFalse(value.sql.contains("s3cret"), value.sql)
        XCTAssertTrue(value.sql.uppercased().contains("IDENTIFIED BY '***'"), value.sql)
        XCTAssertEqual(value.redaction.total, 1)
    }

    func testDoubleQuotedTokenIsMasked() {
        let value = receipt(sql: "SET token = \"abc123\"")
        XCTAssertFalse(value.sql.contains("abc123"), value.sql)
        XCTAssertEqual(value.redaction.passwordLiterals, 1)
    }

    func testKeyValueFormsAreMasked() {
        let equal = receipt(sql: "connect password=hunter2 dbname=zxvmax")
        XCTAssertFalse(equal.sql.contains("hunter2"), equal.sql)
        XCTAssertTrue(equal.sql.contains("dbname=zxvmax"), "非凭据的参数不许被抹：\(equal.sql)")

        let colon = receipt(sql: "token: abc123")
        XCTAssertFalse(colon.sql.contains("abc123"), colon.sql)
    }

    func testCLIFlagIsMasked() {
        let spaced = receipt(sql: "pg_dump --password hunter2 zxvmax")
        XCTAssertFalse(spaced.sql.contains("hunter2"), spaced.sql)

        let glued = receipt(sql: "pg_dump --password=hunter2 zxvmax")
        XCTAssertFalse(glued.sql.contains("hunter2"), glued.sql)
        // 同一条只记一次（③ 先于 ②，不许两边各记一次）
        XCTAssertEqual(glued.redaction.passwordLiterals, 1, glued.sql)
    }

    func testURLUserinfoPasswordIsMasked() {
        let value = receipt(sql: "attach 'postgres://alex:hunter2@db:5432/zxvmax'")
        XCTAssertFalse(value.sql.contains("hunter2"), value.sql)
        XCTAssertTrue(value.sql.contains("postgres://alex:***@db:5432/zxvmax"), value.sql)
        XCTAssertEqual(value.redaction.urlCredentials, 1)
    }

    func testErrorTextIsRedactedToo() {
        let value = receipt(
            sql: "select 1",
            outcome: .failed,
            affectedRows: nil,
            errorText: "FATAL: password authentication failed for user \"bob\" (PASSWORD 'hunter2')"
        )
        XCTAssertFalse(value.errorText?.contains("hunter2") ?? false, value.errorText ?? "")
        XCTAssertEqual(value.redaction.passwordLiterals, 1)
    }

    func testHarmlessSQLIsUntouched() {
        let sql = "select id, name, email from users where name = 'ann' and id > 10"
        let value = receipt(sql: sql)
        XCTAssertEqual(value.sql, sql)
        XCTAssertTrue(value.redaction.isClean)
    }

    func testRedactionIsIdempotent() {
        let once = SensitiveTextRedactor.redact("ALTER USER bob PASSWORD 'hunter2' · postgres://a:hunter2@h/d")
        let twice = SensitiveTextRedactor.redact(once.text)
        XCTAssertEqual(once.text, twice.text)
        XCTAssertFalse(twice.text.contains("hunter2"))
    }

    // MARK: - ② 复制 / 导出且已脱敏

    func testRenderNeverCarriesTheSecret() {
        let value = receipt(sql: "ALTER USER bob PASSWORD 'hunter2'", errorText: "失败：token 'hunter2'")
        let text = value.render(labels: labels(), timeZone: utc)
        XCTAssertFalse(text.contains("hunter2"), text)
        XCTAssertTrue(text.contains("脱敏："), "抹过就要在回执上说出来：\(text)")
    }

    func testExportJSONIsRedactedAndDeterministic() throws {
        let value = receipt(sql: "ALTER USER bob PASSWORD 'hunter2'")
        let first = try value.exportData()
        let second = try value.exportData()
        XCTAssertEqual(first, second, "同一份回执两遍导出必须逐字节相同")

        let text = String(decoding: first, as: UTF8.self)
        XCTAssertFalse(text.contains("hunter2"), text)
        XCTAssertTrue(text.contains("\"succeeded\""), text)
        XCTAssertTrue(text.contains("\"passwordLiterals\" : 1"), text)
    }

    func testDecodingReappliesRedaction() throws {
        // 别的工具（或人）造一份带原文的文件再读回来：入口仍是同一个脱敏口。
        let json = """
        {
          "id": "8A4A6C51-6C0B-4E52-9E39-1A2B3C4D5E6F",
          "executedAt": "2026-09-21T00:00:00Z",
          "duration": 0.5,
          "connectionName": "本机 217",
          "database": "zxvmax",
          "scopeTitle": "整篇",
          "statementCount": 1,
          "outcome": "failed",
          "sql": "ALTER USER bob PASSWORD 'hunter2'",
          "errorText": "PASSWORD 'hunter2' rejected"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let value = try decoder.decode(ExecutionReceipt.self, from: Data(json.utf8))
        XCTAssertFalse(value.sql.contains("hunter2"), value.sql)
        XCTAssertFalse(value.errorText?.contains("hunter2") ?? false, value.errorText ?? "")
        XCTAssertEqual(value.redaction.passwordLiterals, 2)
    }

    // MARK: - 会话上的回执册

    func testLogKeepsNewestAndDropsOldest() {
        var log = ExecutionReceiptLog()
        for index in 0..<(ExecutionReceiptLog.capacity + 5) {
            log.append(receipt(sql: "select \(index)"))
        }
        XCTAssertEqual(log.count, ExecutionReceiptLog.capacity)
        XCTAssertEqual(log.receipts.first?.sql, "select 5", "超容量丢最旧的")
        XCTAssertEqual(log.receipts.last?.sql, "select \(ExecutionReceiptLog.capacity + 4)")
        XCTAssertEqual(log.newestFirst.first?.sql, log.receipts.last?.sql)
    }

    func testLogExportTextJoinsEveryReceipt() {
        var log = ExecutionReceiptLog()
        log.append(receipt(sql: "select 1"))
        log.append(receipt(sql: "select 2"))
        let text = log.exportText(labels: labels(), timeZone: utc)
        XCTAssertEqual(text.components(separatedBy: "\n\n---\n\n").count, 2)
        XCTAssertTrue(text.contains("select 1"))
        XCTAssertTrue(text.contains("select 2"))
    }

    func testLogExportJSONRoundTripKeepsRedaction() throws {
        var log = ExecutionReceiptLog()
        log.append(receipt(sql: "ALTER USER bob PASSWORD 'hunter2'"))
        let data = try log.exportData()
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("hunter2"))

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode([ExecutionReceipt].self, from: data)
        XCTAssertEqual(restored.count, 1)
        XCTAssertFalse(restored[0].sql.contains("hunter2"))
    }

    func testLogRemoveAll() {
        var log = ExecutionReceiptLog(receipts: [receipt()])
        XCTAssertFalse(log.isEmpty)
        log.removeAll()
        XCTAssertTrue(log.isEmpty)
        XCTAssertTrue(log.exportText(labels: labels()).isEmpty)
    }

    func testLogInitialiserCapsOversizedInput() {
        let many = (0..<(ExecutionReceiptLog.capacity + 3)).map { receipt(sql: "select \($0)") }
        let log = ExecutionReceiptLog(receipts: many)
        XCTAssertEqual(log.count, ExecutionReceiptLog.capacity)
        XCTAssertEqual(log.receipts.first?.sql, "select 3")
    }
}
