import AppKit
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// 「超大结果集流式落盘」的 **App 侧探针**（`FR-STD-DB-RES-013`）—— v0.3.0 数据库运维面 B2 批次。
///
/// ## 这一行为什么原来停在 🟡
/// 台账备注原文是「界面点击待人工点验」。`Core/CursorPaging` 与 `Core/ResultStreamWriter` 各有单测，
/// 但它们**一个都没走 AppState 那条路**：导出可以先把整份结果取回内存、可以忘了 `CLOSE` /
/// `COMMIT`（游标与事务挂着）、可以取到一半断了还留个半截文件、可以不发 `FETCH` 而用
/// `LIMIT / OFFSET` 翻页 —— 上面那些单测照样全绿。
///
/// ## 这一片怎么量（本机没有 PG，也不该去碰 217 真库）
/// 用**假 `DatabaseService`**：`exportResultStreaming` 现在把「服务从哪来」提成形参（与
/// `streamTable` 同一条口径），于是探针能把生产那条链**真跑一遍** —— 真 `CursorFetcher` 逐页取、
/// 真 `ResultStreamWriter` 逐页写盘、真 `CursorPaging` 拼语句，只有「数据从哪来」换成假的。
/// 假服务按 `BEGIN` / `DECLARE` / `FETCH n` / `CLOSE` / `COMMIT` 逐条应答，并记下**它收到的每一条语句**。
///
/// ## 边界（如实登记）
/// · 证得住：语句序列里只有游标顺序读取（没有 `LIMIT` / `OFFSET`）、盘上是全部行、
///   分块落盘（`flushCount > 1` ⇒ 内存不随总行数线性增长）、结束必 `CLOSE` + `COMMIT`、
///   中途失败不留半成品且事务回滚、同一份状态随后还能再导一次；
/// · **证不住**：真库上 `DECLARE ... CURSOR` 的可见性与 12 万行 / 27 MB 的真机内存峰值
///   （后者见需求规格 R-036 的 CLI 实测记录；本文件不冒充重跑一遍）；
/// · **保存面板没点**：`NSSavePanel.runModal()` 是模态的，无人值守的机器上弹出来就回不来
///   ⇒ 「弹出面板、用户选路径」这一跳由人承担；面板**之后**的那一半由本文件判住；
/// · 默认 `XCTSkip`（要 `DOYAH_UI_SNAPSHOT=1`）。
final class ResultStreamExportProbeTests: XCTestCase {

    // MARK: - 假服务

    /// 只实现了流式导出会用到的那几条语句的服务。每条语句都记下来 ——
    /// 「用的是游标还是 LIMIT / OFFSET」「CLOSE / COMMIT 有没有真的发」只有从**服务端看到了什么**才判得住。
    final class FakeCursorService: DatabaseService, @unchecked Sendable {
        let config = ConnectionConfig(name: "假库", database: "shop")

        private let lock = NSLock()
        private let totalRows: Int
        private let failOnFetchNumber: Int?
        private var remaining: Int
        private(set) var statements: [String] = []
        private(set) var fetchCount = 0

        init(totalRows: Int, failOnFetchNumber: Int? = nil) {
            self.totalRows = totalRows
            self.remaining = totalRows
            self.failOnFetchNumber = failOnFetchNumber
        }

        struct FakeError: LocalizedError {
            var errorDescription: String? { "假服务在取第三页时断了（模拟取到一半失败）" }
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

        static func requestedCount(in sql: String) -> Int {
            // `FETCH FORWARD 1000 FROM "cur_1"`
            let parts = sql.split(separator: " ")
            guard parts.count >= 3, let value = Int(parts[2]) else { return 0 }
            return value
        }

        func execute(
            _ sql: String,
            options: QueryOptions,
            handle: ExecutionHandle
        ) -> AsyncThrowingStream<QueryEvent, Error> {
            lock.lock()
            statements.append(sql)
            var page: [[String?]] = []
            var shouldFail = false
            if sql.hasPrefix("FETCH FORWARD") {
                fetchCount += 1
                let requested = Self.requestedCount(in: sql)
                if let failOnFetchNumber, fetchCount == failOnFetchNumber {
                    shouldFail = true
                } else {
                    let take = min(requested, remaining)
                    let firstRowNumber = totalRows - remaining + 1
                    page = (0..<take).map { offset -> [String?] in
                        let number = firstRowNumber + offset
                        // 每行约 60 字节：12 万行 ⇒ 7 MB 上下，足以让写盘缓冲翻好几次页。
                        return ["\(number)", "note-\(number)-padding-padding-padding-padding"]
                    }
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

        var snapshot: [String] {
            lock.lock()
            defer { lock.unlock() }
            return statements
        }
    }

    // MARK: - 夹具

    private func temporaryURL(_ name: String) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("stream-export-probe-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(name)
    }

    private func makeDirectory(for url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    /// 一份「连接已选好、页签里有单条查询」的状态（与用户从结果区点「导出」时的形状一致）。
    @MainActor
    private func makeState(sql: String) -> (AppState, QueryTab) {
        let state = AppState()
        let connection = ConnectionConfig(name: "假库", dbType: .postgresql, database: "shop")
        state.connections.append(connection)
        let tab = QueryTab(
            title: "orders",
            sql: sql,
            results: [QueryResult(columns: [
                ColumnMeta(id: 0, name: "id"),
                ColumnMeta(id: 1, name: "note"),
            ], rows: [["1", "note-1"]])],
            connectionID: connection.id,
            database: "shop"
        )
        state.tabs.append(tab)
        return (state, tab)
    }

    private func lines(of url: URL) throws -> [String] {
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.components(separatedBy: "\n")
            .map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
            .filter { !$0.isEmpty }
    }

    private func skipUnlessProbeEnabled() throws {
        guard ProcessInfo.processInfo.environment["DOYAH_UI_SNAPSHOT"] == "1" else {
            throw XCTSkip("流式导出探针要起真 App 状态与真写盘：DOYAH_UI_SNAPSHOT=1 才跑（取证才跑，门禁不跑）")
        }
    }

    // MARK: - ① 十二万行：游标顺序取、盘上全部行

    @MainActor
    func testLargeResultSetStreamsThroughACursorWithoutLimitOrOffset() async throws {
        try skipUnlessProbeEnabled()
        let url = temporaryURL("orders.csv")
        try makeDirectory(for: url)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let (state, tab) = makeState(sql: "SELECT id, note FROM orders ORDER BY id")
        let service = FakeCursorService(totalRows: 120_000)
        let ok = await state.exportResultStreaming(
            tab: tab,
            fallbackColumns: tab.results[0].columns,
            format: .csv,
            url: url,
            baseName: "orders",
            dialect: PostgresDialect(),
            service: service
        )

        XCTAssertTrue(ok, "流式导出报失败：\(state.errorMessage ?? "（没有错误消息）")")
        let written = try lines(of: url)
        XCTAssertEqual(written.count, 120_001, "盘上应当是表头 + 12 万行（实际 \(written.count) 行）")
        XCTAssertEqual(written.first, "id,note", "第一行不是表头：\(written.first ?? "nil")")
        XCTAssertEqual(written.last, "120000,note-120000-padding-padding-padding-padding",
                       "末行不是第 12 万行：\(written.last ?? "nil")")

        let statements = service.snapshot
        XCTAssertEqual(statements.first, "BEGIN", "第一条不是 BEGIN（游标必须在事务里）")
        XCTAssertTrue(statements.count > 1 && statements[1].uppercased().hasPrefix("DECLARE"),
                      "第二条不是 DECLARE：\(statements.prefix(3))")
        XCTAssertEqual(statements.last, "COMMIT", "最后一条不是 COMMIT（事务没收干净）")
        XCTAssertEqual(statements.filter { $0.uppercased().hasPrefix("CLOSE") }.count, 1,
                       "CLOSE 没有恰好发一次（游标留着不放）")
        // 12 万行恰好是 120 个整页 ⇒ 第 121 趟是「再问一次才知道到底了」的那一趟（返回 0 行）。
        XCTAssertEqual(statements.filter { $0.uppercased().hasPrefix("FETCH FORWARD") }.count, 121,
                       "FETCH 次数不对：12 万行 / 每页 1000 ⇒ 120 满页 + 1 趟确认（实际 \(service.fetchCount)）")

        // ② 顺序读取：整条链上不许出现 LIMIT / OFFSET（那是「每翻一页重扫一遍」的 O(n²) 走法）。
        let paged = statements.filter {
            let upper = $0.uppercased()
            return upper.contains("LIMIT") || upper.contains("OFFSET")
        }
        XCTAssertTrue(paged.isEmpty, "导出用了 LIMIT / OFFSET 翻页：\(paged.prefix(3))")
        print("🧪 流式读数：\(written.count - 1) 行 / \(statements.count) 条语句 / FETCH \(service.fetchCount) 趟 / LIMIT·OFFSET \(paged.count) 处")
    }

    // MARK: - ② 分块落盘（内存不随总行数线性增长）与进度

    @MainActor
    func testStreamedWriteIsChunkedAndReportsProgressPerPage() async throws {
        try skipUnlessProbeEnabled()
        let url = temporaryURL("orders.csv")
        try makeDirectory(for: url)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let (state, tab) = makeState(sql: "SELECT id, note FROM orders ORDER BY id")
        let service = FakeCursorService(totalRows: 120_000)
        var report: ResultStreamWriter.Report?
        let ok = await state.exportResultStreaming(
            tab: tab,
            fallbackColumns: tab.results[0].columns,
            format: .csv,
            url: url,
            baseName: "orders",
            dialect: PostgresDialect(),
            service: service,
            onReport: { report = $0 }
        )
        XCTAssertTrue(ok, "流式导出报失败：\(state.errorMessage ?? "（没有错误消息）")")

        let finished = try XCTUnwrap(report, "导出结束没交出读数")
        XCTAssertEqual(finished.rowCount, 120_000, "读数里的行数不对")
        XCTAssertEqual(finished.fileURL.standardizedFileURL, url.standardizedFileURL, "读数指向的不是目标文件")
        let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        XCTAssertEqual(finished.byteCount, size, "读数里的字节数与盘上的不一致（写盘那一半报的是另一个数）")
        XCTAssertGreaterThan(finished.flushCount, 1,
                             "只落了 \(finished.flushCount) 次盘 —— 说明是攒到最后一次写出去的，内存随行数线性增长")

        // 进度写在**页签**日志里（全局状态栏没有视图在读，写进去等于没说）。
        // 按 id 找**这一条**页签：`AppState()` 会把上次会话的页签一并恢复，`tabs.first` 未必是它。
        let log = state.tabs.first(where: { $0.id == tab.id })?.outputLog.map(\.message) ?? []
        XCTAssertGreaterThanOrEqual(
            log.filter { $0.contains("已取") || $0.contains("fetched") }.count, 2,
            "页签日志里没有逐页进度：\(log.suffix(3))"
        )
        let last = try XCTUnwrap(log.last, "页签日志是空的（导出过程一句都没说）")
        XCTAssertTrue(last.contains(url.lastPathComponent), "末条日志没说是哪个文件：\(last)")
        // 数字用的是本地化格式（`120,000`），判的是「这个数在不在」，不是分隔符长什么样。
        XCTAssertTrue(last.replacingOccurrences(of: ",", with: "").contains("120000"),
                      "末条日志没报行数：\(last)")
        print("🧪 分块读数：\(finished.rowCount) 行 / \(finished.byteCount) 字节 / 落盘 \(finished.flushCount) 次 / 日志 \(log.count) 条")
        print("🧪 末条日志：\(last)")
    }

    // MARK: - ③ / ④ 中途失败：不留半成品、事务回滚、游标关掉、连接还能再用

    @MainActor
    func testCancelMidwayLeavesNoFileAndReleasesTheCursor() async throws {
        try skipUnlessProbeEnabled()
        let failing = temporaryURL("half.csv")
        try makeDirectory(for: failing)
        defer { try? FileManager.default.removeItem(at: failing.deletingLastPathComponent()) }

        let (state, tab) = makeState(sql: "SELECT id, note FROM orders ORDER BY id")
        let brokenService = FakeCursorService(totalRows: 120_000, failOnFetchNumber: 3)
        let ok = await state.exportResultStreaming(
            tab: tab,
            fallbackColumns: tab.results[0].columns,
            format: .csv,
            url: failing,
            baseName: "orders",
            dialect: PostgresDialect(),
            service: brokenService
        )

        XCTAssertFalse(ok, "取到一半断了却报成功 —— 用户会拿到一个看起来成功的半截文件")
        XCTAssertNotNil(state.errorMessage, "失败没给出任何错误消息")
        XCTAssertFalse(FileManager.default.fileExists(atPath: failing.path), "写了一半的文件留在盘上")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: failing.deletingLastPathComponent().path)
        XCTAssertTrue(leftovers.isEmpty, "临时目录里还留着残件（`.partial-` 之类）：\(leftovers)")

        let statements = brokenService.snapshot
        XCTAssertTrue(statements.contains { $0.uppercased().hasPrefix("CLOSE") }, "失败那条路上没发 CLOSE")
        XCTAssertEqual(statements.last, "ROLLBACK", "失败那条路上事务没收（实际末条：\(statements.last ?? "nil")）")

        // 同一份状态随后还能再导一次：证明上一条失败没把游标 / 连接留在半开状态。
        let healthy = temporaryURL("retry.csv")
        try makeDirectory(for: healthy)
        defer { try? FileManager.default.removeItem(at: healthy.deletingLastPathComponent()) }
        let retryOK = await state.exportResultStreaming(
            tab: tab,
            fallbackColumns: tab.results[0].columns,
            format: .csv,
            url: healthy,
            baseName: "orders",
            dialect: PostgresDialect(),
            service: FakeCursorService(totalRows: 2_500)
        )
        XCTAssertTrue(retryOK, "上一次失败之后同一份状态再也导不出来了（连接 / 游标被留在半开状态）")
        XCTAssertEqual(try lines(of: healthy).count, 2_501, "重试那次落盘的行数不对")
        print("🧪 中途失败读数：语句 \(statements.count) 条 · 末条 \(statements.last ?? "nil") · 残件 \(leftovers) · 重试 \(retryOK)")
    }
}
