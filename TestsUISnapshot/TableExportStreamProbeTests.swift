import AppKit
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// 「整表 / 整库导出真跑一次落文件」的 **App 侧探针**（`FR-STD-DB-IO-002`）—— B1 批次第三片。
///
/// ## 这一行为什么停在 🟡（台账备注原文「差人工点一次」）
///
/// 核盘之后要分开说三件事：
///   · 「怎么点名、怎么分页、怎么拼文件名、账怎么记」早有 22 例判据（`Tests/TableExportTests`）；
///   · 上一批（第七十一批）把入口补进了**生产那份 AppKit 右键菜单**，并加了探针钉住「菜单里有那一项」
///     （`ObjectTreeContextMenuProbeTests.testProductionMenuCarriesExportEntries`）；
///   · 但**从菜单点下去之后到文件出现在盘上**这一段，一次都没跑过：`AppState.streamTable`
///     可以取第一页之后就断、可以忘了 `CLOSE` / `COMMIT`、可以写一半失败却留下半成品文件
///     —— 上面 23 例照样全绿。
///
/// ## 这一片怎么量（本机没有 PG，也不该去碰 217 真库）
///
/// 用**假 `DatabaseService`**：`streamTable` 只依赖 `DatabaseService.execute` 这一条缝，
/// 假服务按 `BEGIN` / `DECLARE` / `FETCH n` / `CLOSE` / `COMMIT` 逐条应答（并记下**它收到的每一条语句**）。
/// 于是「真跑一次导出」量到的是**生产那条路**：真 `CursorFetcher` 分页、真 `ResultStreamWriter`
/// 逐页写盘、真 `TableExport.selectSQL` 拼语句 —— 只有「数据从哪来」换成了假的。
/// 判据读**盘上的文件**（行数 / 表头 / 末行）、返回的行数、以及假服务收到的语句序列。
///
/// ## 边界（如实登记，别把这条读成「人点过了」）
///
/// · **保存面板没点**：`NSSavePanel.runModal()` 是模态的，无人值守的机器上弹出来就回不来
///   ⇒ 「弹出面板、用户选路径」这一跳由人承担；面板**之后**的那一半（`streamTable` 起）由本文件判住。
/// · **不是真数据库**：服务端游标语义（`DECLARE ... CURSOR` 在事务里、`FETCH FORWARD` 的可见性）
///   由假服务模拟。真库那一面在需求规格 R-036 记着「已真机验证 12 万行 / 27 MB」，
///   本文件不冒充重跑一遍。
/// · **内存不随行数增长**不做断言（要测峰值内存得上 `task_vm_info`，噪声大于信号）；
///   这一面由「逐页取、逐页写」的结构本身 + `LargeResultScrollProbeTests` 那条同族判据承担。
/// · 真鼠标右键点「导出整表…」那一跳由人承担（菜单项存在性由上一批的探针钉住）。
final class TableExportStreamProbeTests: XCTestCase {

    // MARK: - 假服务

    /// 只实现了导出会用到的那几条语句的服务。每条语句都记下来 —— 「CLOSE / COMMIT 有没有真的发」
    /// 只有从**服务端看到了什么**才判得住（写盘成功不代表事务收干净了）。
    final class FakeExportService: DatabaseService, @unchecked Sendable {
        let config = ConnectionConfig(name: "假库", database: "shop")
        private let lock = NSLock()
        private var remaining: Int
        private let failOnFetchNumber: Int?
        /// 整库那一条：游标声明在哪张表上，就从哪一张的账上取行数（DECLARE 里点名的最后一段）。
        private let rowsByTable: [String: Int]
        private let failOnFetchForTable: String?
        private var currentTable: String?
        private var fetchesForCurrentTable = 0

        private(set) var statements: [String] = []
        private(set) var fetchCount = 0

        init(totalRows: Int, failOnFetchNumber: Int? = nil) {
            self.remaining = totalRows
            self.failOnFetchNumber = failOnFetchNumber
            self.rowsByTable = [:]
            self.failOnFetchForTable = nil
        }

        /// 整库导出用：每张表各一个行数（`empty` 那张给 0），`failingTable` 那张在第二页上断。
        init(rowsByTable: [String: Int], failOnFetchForTable: String? = nil) {
            self.remaining = 0
            self.failOnFetchNumber = nil
            self.rowsByTable = rowsByTable
            self.failOnFetchForTable = failOnFetchForTable
        }

        struct FakeError: LocalizedError {
            var errorDescription: String? { "假服务在第二页上断了（模拟取到一半失败）" }
        }

        var columns: [ColumnMeta] {
            [ColumnMeta(id: 0, name: "id"), ColumnMeta(id: 1, name: "note")]
        }

        func connect() async throws -> ServerInfo { ServerInfo(version: "fake", database: "shop", user: "fake") }
        func disconnect() async {}
        func beginTransaction() async throws {}
        func commit() async throws {}
        func rollback() async throws {}
        func copyFromText(table: String, columns: [String], text: String) async throws {}
        func cancel(_ handle: ExecutionHandle) async -> CancelOutcome { .notActive }

        func execute(
            _ sql: String,
            options: QueryOptions,
            handle: ExecutionHandle
        ) -> AsyncThrowingStream<QueryEvent, Error> {
            lock.lock()
            statements.append(sql)
            var page: [[String?]] = []
            var shouldFail = false
            if sql.hasPrefix("DECLARE") {
                // `DECLARE "cur" CURSOR FOR SELECT * FROM "public"."orders"` ⇒ 取 `FROM` 之后
                // 最后一段（去掉方言加的那对引号）就是表名。
                let tail = sql.components(separatedBy: "FROM").last ?? sql
                let raw = tail.split(separator: ".").last.map(String.init) ?? ""
                let table = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\" \n\t"))
                currentTable = table
                fetchesForCurrentTable = 0
                remaining = rowsByTable[table] ?? remaining
            }
            if sql.hasPrefix("FETCH FORWARD") {
                fetchCount += 1
                fetchesForCurrentTable += 1
                let requested = Self.requestedCount(in: sql)
                if let failOnFetchNumber, fetchCount == failOnFetchNumber {
                    shouldFail = true
                } else if let failOnFetchForTable, failOnFetchForTable == currentTable, fetchesForCurrentTable == 1 {
                    shouldFail = true
                } else {
                    let take = min(requested, remaining)
                    let start = 1
                    let produced = (0..<take).map { offset -> [String?] in
                        let number = start + offset + (fetchCount - 1) * requested
                        return [String(number), "note-\(number)"]
                    }
                    page = produced
                    remaining -= take
                }
            }
            lock.unlock()

            let columns = self.columns
            return AsyncThrowingStream { continuation in
                continuation.yield(.started(statementIndex: 0))
                if shouldFail {
                    continuation.finish(throwing: FakeError())
                    return
                }
                continuation.yield(.resultSet(QueryResult(columns: columns, rows: page)))
                continuation.yield(.finished(QuerySummary(statementCount: 1, duration: 0)))
                continuation.finish()
            }
        }

        static func requestedCount(in sql: String) -> Int {
            // `FETCH FORWARD 1000 FROM "cur_1"`
            let parts = sql.split(separator: " ")
            guard parts.count >= 3, let value = Int(parts[2]) else { return 0 }
            return value
        }

        var snapshot: [String] {
            lock.lock()
            defer { lock.unlock() }
            return statements
        }
    }

    // MARK: - 夹具

    private func temporaryURL(_ name: String) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("export-probe-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(name)
    }

    private func makeDirectory(for url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    // MARK: - ① 真跑一次：逐页取、逐页写，盘上是全部行

    @MainActor
    func testCursorExportWritesARealFileWithEveryRow() async throws {
        let url = temporaryURL("orders.csv")
        try makeDirectory(for: url)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let service = FakeExportService(totalRows: 2_500) // 1000 + 1000 + 500 + 0
        let state = AppState()
        var progress: [(Int, Int)] = []
        let written = try await state.streamTable(
            "orders",
            schema: "public",
            to: url,
            format: .csv,
            dialect: PostgresDialect(),
            service: service
        ) { rows, pages in progress.append((rows, pages)) }

        XCTAssertEqual(written, 2_500, "返回的行数与盘上应当一致")
        let text = try String(contentsOf: url, encoding: .utf8)
        // CSV 走 CRLF（Excel 那一侧的口径），按行切开时要把 \r 一并去掉再判。
        let lines = text.components(separatedBy: "\n")
            .map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
            .filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 2_501, "文件里应当是表头 + 2500 行（实际 \(lines.count) 行）")
        XCTAssertEqual(lines.first, "id,note", "第一行不是表头：\(lines.first ?? "nil")")
        XCTAssertEqual(lines.last, "2500,note-2500", "末行不是第 2500 行：\(lines.last ?? "nil")")

        // 语句序列：事务开在游标**之前**、收干净在最后（CLOSE 与 COMMIT 缺一条就是「事务留着不放」）。
        let statements = service.snapshot
        XCTAssertEqual(statements.first, "BEGIN", "第一条不是 BEGIN（游标必须在事务里）")
        XCTAssertTrue(statements[1].uppercased().hasPrefix("DECLARE"), "第二条不是 DECLARE：\(statements[1])")
        XCTAssertEqual(statements.last, "COMMIT", "最后一条不是 COMMIT（事务没收干净）")
        XCTAssertEqual(statements.filter { $0.uppercased().hasPrefix("CLOSE") }.count, 1,
                       "CLOSE 没有恰好发一次（游标留着不放）")
        XCTAssertEqual(statements.filter { $0.uppercased().hasPrefix("FETCH") }.count, 3,
                       "FETCH 次数不对：2500 行 / 每页 1000 ⇒ 1000 · 1000 · 500，末页不足一页即收（实际 \(statements.filter { $0.uppercased().hasPrefix("FETCH") }.count)）")
        XCTAssertEqual(progress.last?.0, 2_500, "进度回调最后一格不是总行数")

        // 页大小就是产品那个常量（不是探针自己挑的一个数）。
        XCTAssertTrue(statements[2].hasSuffix("\(AppState.streamingExportPageSize) FROM \"\(statements[1].split(separator: "\"")[1])\""),
                      "FETCH 的页大小与游标名没对上：\(statements[2])")
        print("🧪 整表导出读数：\(written) 行 / \(lines.count) 行文件 / 语句 \(statements.count) 条 · 进度末格 \(progress.last.map { "\($0.0)行/\($0.1)页" } ?? "nil")")
        print("🧪 语句序列：\(statements)")
    }

    // MARK: - ② 空表：抛可读错误、**不生成文件**

    @MainActor
    func testEmptyTableThrowsAndLeavesNoFileBehind() async throws {
        let url = temporaryURL("empty.csv")
        try makeDirectory(for: url)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let service = FakeExportService(totalRows: 0)
        let state = AppState()
        do {
            _ = try await state.streamTable(
                "empty", schema: "public", to: url,
                format: .csv, dialect: PostgresDialect(), service: service
            ) { _, _ in }
            XCTFail("空表没有抛错 —— 那用户会拿到一个只有表头的文件还以为是成功")
        } catch let error as AppState.TableExportEmptyTable {
            XCTAssertFalse(error.errorDescription?.isEmpty ?? true, "空表那句理由没有内容")
        } catch {
            XCTFail("空表抛的不是那个专用错误：\(error)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "空表也落了文件")

        // 空表也要把事务收干净（不留一条悬着的事务）。
        let statements = service.snapshot
        XCTAssertEqual(statements.last, "COMMIT", "空表那条路上事务没收（实际末条：\(statements.last ?? "nil")）")
        print("🧪 空表读数：语句 \(statements.count) 条 · 文件存在 \(FileManager.default.fileExists(atPath: url.path))")
    }

    // MARK: - ③ 取到一半失败：报错、**不留半成品**

    @MainActor
    func testFailureMidwayLeavesNoPartialFile() async throws {
        let url = temporaryURL("half.csv")
        try makeDirectory(for: url)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let service = FakeExportService(totalRows: 2_500, failOnFetchNumber: 2) // 第二页断
        let state = AppState()
        do {
            _ = try await state.streamTable(
                "orders", schema: "public", to: url,
                format: .csv, dialect: PostgresDialect(), service: service
            ) { _, _ in }
            XCTFail("取到一半断了却没报错 —— 用户会拿到一个看起来成功的半截文件")
        } catch {
            // 期望：抛错（话术归 ErrorPresenter，不在本条判据里）
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path),
                       "写了一半的文件留在盘上 —— 用户会当成完整导出")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        XCTAssertTrue(leftovers.isEmpty, "临时目录里还留着残件：\(leftovers)")

        // 失败也要收事务（不留悬着的事务）。
        let statements = service.snapshot
        XCTAssertTrue(statements.contains { $0.uppercased().hasPrefix("CLOSE") }, "失败那条路上没发 CLOSE")
        XCTAssertEqual(statements.last, "ROLLBACK", "失败那条路上事务没收（实际末条：\(statements.last ?? "nil")）")
        print("🧪 半途失败读数：语句 \(statements.count) 条 · 末条 \(statements.last ?? "nil") · 残件 \(leftovers)")
    }

    // MARK: - ④ 整库：逐张落文件、一张没成不打断、账分两栏

    @MainActor
    func testDatabaseExportWritesOneFilePerTableAndKeepsOneFailureFromStoppingTheRest() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("db-export-probe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let plan = TableExport.databasePlan(
            [
                TableExport.Candidate(kind: .table, name: "orders", schema: "public"),
                TableExport.Candidate(kind: .table, name: "empty", schema: "public"),
                TableExport.Candidate(kind: .table, name: "bad", schema: "public"),
                TableExport.Candidate(kind: .sequence, name: "orders_seq", schema: "public"),
            ],
            format: .csv
        )
        XCTAssertEqual(plan.jobs.count, 3, "名单应当是表 / 空表 / 会断的那张（序列记跳过）")

        let service = FakeExportService(
            rowsByTable: ["orders": 1_200, "empty": 0, "bad": 1_200],
            failOnFetchForTable: "bad"
        )
        let state = AppState()
        let ledger = await state.streamDatabase(
            plan: plan,
            directory: directory,
            format: .csv,
            dialect: PostgresDialect(),
            service: service
        )

        print("🧪 整库语句：\(service.snapshot)")
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        XCTAssertEqual(files, ["orders.csv"], "落盘的文件不是「成的那一张各一个」：\(files)")
        XCTAssertEqual(ledger.succeededCount, 1, "账上成功数不对")
        XCTAssertEqual(ledger.failedCount, 2, "空表与断掉的那张都该记成没成（实际 \(ledger.failedCount)）")

        let text = try String(contentsOf: directory.appendingPathComponent("orders.csv"), encoding: .utf8)
        let lines = text.components(separatedBy: "\n").map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }.filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 1_201, "orders.csv 应当是表头 + 1200 行（实际 \(lines.count)）")
        print("🧪 整库读数：文件 \(files) / 成 \(ledger.succeededCount) 张 / 没成 \(ledger.failedCount) 张")
    }

    // MARK: - ④ 源锚点：整表与整库共用同一条取数路

    /// 这一条盯的是「两处各写一套循环」那种漂移 —— 它不会让上面任何断言变红，
    /// 但会让「空表算失败还是成功」「失败了留不留半成品」这类口径在两条路上分叉。
    @MainActor
    func testBothExportEntriesShareOneStreamingPath() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("App/AppState.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("func streamTable("), "取数写盘那一处不见了")
        let calls = source.components(separatedBy: "try await streamTable(").count - 1
        XCTAssertEqual(calls, 2, "`streamTable` 的调用点应当是两处（整表 / 整库），实际 \(calls) 处")
        XCTAssertTrue(source.contains("let fetcher = CursorFetcher(plan: plan"),
                      "取数不再走服务端游标")
        XCTAssertFalse(source.contains("for try await event in service.execute(query"),
                       "有人在 `streamTable` 之外又开了一条逐行取数的循环")

        // 入口那一侧：方言拦在入口（MySQL / GBase 今天没有服务端游标）。
        XCTAssertTrue(source.contains("guard TableExport.streamingSupported(configuration.dbType)"),
                      "整表 / 整库入口不再按方言拦 —— 非 PG 上会摆一个点了必然失败的按钮")
    }
}
