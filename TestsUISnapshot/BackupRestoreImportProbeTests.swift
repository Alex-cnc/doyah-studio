import AppKit
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// 「备份 / 恢复 / 导入」三条**界面链**的 App 侧探针（`FR-STD-DB-IO-003` · `-004` · `-006` · `-007`）
/// —— B4 批次。
///
/// ## 这四条为什么一直停在 🟡（台账备注原文「界面点击待人工点验」）
///
/// 核盘之后要分开说两件事：
///   · 「argv 怎么拼、映射怎么对、分批怎么切、xlsx 怎么读」早有单测
///     （`BackupCommandTests` / `BackupExecutionTests` / `TableImportTests` / `XLSXReaderTests`）；
///   · 「文件怎么解析、COPY 负载怎么编码」也有**真机脚本**判过
///     （`test-backup-restore.sh` 本机 16.2 完整往返 / `test-data-import.sh` /
///      `test-copy-import.sh` / `test-xlsx-import.sh`，四个都 exit 0）；
///   · 缺的是**中间那一段**：从界面按下去（`startTableImport` / `runBackupPlan` /
///     `runRestoreSections`）到「一条命令 / 一条语句真的发出去」之间 —— 那一段可以少发一条
///     `SET search_path`、可以把三段的顺序搞反、可以把 `--section` 拼在 `--dbname` 前面、
///     可以在第二段失败后仍往下跑，上面那些用例照样全绿。
///
/// ## 怎么量（本机没有稳定在跑的实例，探针不依赖它）
///
/// 换**两处注入缝**（本批新开的两个 `AppState` 属性，生产默认仍是真进程 / 真连接）：
///   · `backupRunner`：假 `ExternalProcessRunner` 记下**收到的 executable / argv / 环境变量**，
///     并按 `--section` 给不同退出码 —— 判的是「点了执行到底跑了几条命令、每条长什么样」；
///   · `importServiceOverride`：假 `DatabaseService` 记下**收到的每一条语句与 COPY 负载**,
///     用产品的 `CopyTextFormat.unescape` 解回来逐格比对 —— 判的是「值有没有串列」。
///
/// ## 边界（如实登记，别把这条读成「人点过了」）
///
/// · **模态面板没点**：保存 / 打开 / 选目录那几个 `NSSavePanel` / `NSOpenPanel` 是模态的，
///   无人值守时弹出来就回不来 ⇒「弹出面板、用户选路径」这一跳由人承担；面板**之后**那一半
///   （`runBackupPlan` / `runRestoreSections` / `startTableImport`）由本文件判住。
/// · **不是真数据库**：真库那一面归四个真机脚本（本轮都跑过、都 exit 0）；本文件不冒充重跑。
/// · **真 Excel / Numbers 产出的 xlsx** 仍待人工（夹具由 `XLSXWriter` 造，与
///   `test-xlsx-import.sh` 里 Python 手写 OOXML 那套同边界）。
/// · 面板里**打字**（目标库手输、列映射下拉）不在本文件：那要求渲染 SwiftUI 再合成键入。
final class BackupRestoreImportProbeTests: XCTestCase {

    // MARK: - 假执行器（备份 / 恢复）

    /// 只做两件事：记下**收到了什么**，按 `--section` 给不同结局。
    final class FakeRunner: ExternalProcessRunner, @unchecked Sendable {
        struct Invocation: CustomStringConvertible {
            var executable: String
            var arguments: [String]
            var environment: [String: String]
            var description: String { ([executable] + arguments).joined(separator: " ") }
        }

        struct Outcome {
            var exitCode: Int32
            var lines: [String]
            static let ok = Outcome(exitCode: 0, lines: [])
        }

        private let lock = NSLock()
        private var recorded: [Invocation] = []
        /// 键 = `--section` 的值（不带段号时键是空串）。
        private let bySection: [String: Outcome]
        /// 起不来的情况（沙箱那条路）。
        private let launchError: Error?

        init(bySection: [String: Outcome] = [:], launchError: Error? = nil) {
            self.bySection = bySection
            self.launchError = launchError
        }

        var snapshot: [Invocation] {
            lock.lock()
            defer { lock.unlock() }
            return recorded
        }

        func run(
            executable: String,
            arguments: [String],
            environment: [String: String],
            onOutput: @escaping @Sendable (String) -> Void
        ) async throws -> Int32 {
            lock.lock()
            recorded.append(Invocation(executable: executable, arguments: arguments, environment: environment))
            lock.unlock()

            if let launchError { throw launchError }
            let outcome = bySection[Self.section(of: arguments)] ?? .ok
            for line in outcome.lines { onOutput(line) }
            return outcome.exitCode
        }

        static func section(of arguments: [String]) -> String {
            guard let index = arguments.firstIndex(of: "--section"), index + 1 < arguments.count else { return "" }
            return arguments[index + 1]
        }
    }

    // MARK: - 假服务（导入）

    /// 记下**服务端收到了什么**：每一条语句原文 + 每一次 COPY 的表 / 列 / 负载。
    final class FakeImportService: DatabaseService, @unchecked Sendable {
        let config: ConnectionConfig

        private let lock = NSLock()
        private var recordedStatements: [String] = []
        private var recordedCopies: [(table: String, columns: [String], text: String)] = []
        private let copyThrows: Error?

        init(config: ConnectionConfig, copyThrows: Error? = nil) {
            self.config = config
            self.copyThrows = copyThrows
        }

        var statements: [String] {
            lock.lock()
            defer { lock.unlock() }
            return recordedStatements
        }

        var copies: [(table: String, columns: [String], text: String)] {
            lock.lock()
            defer { lock.unlock() }
            return recordedCopies
        }

        func connect() async throws -> ServerInfo {
            ServerInfo(version: "fake", database: config.database, user: config.username)
        }

        func disconnect() async {}
        func beginTransaction() async throws {}
        func commit() async throws {}
        func rollback() async throws {}
        func cancel(_ handle: ExecutionHandle) async -> CancelOutcome { .notActive }

        func copyFromText(table: String, columns: [String], text: String) async throws {
            lock.lock()
            recordedCopies.append((table, columns, text))
            lock.unlock()
            if let copyThrows { throw copyThrows }
        }

        func execute(
            _ sql: String,
            options: QueryOptions,
            handle: ExecutionHandle
        ) -> AsyncThrowingStream<QueryEvent, Error> {
            lock.lock()
            recordedStatements.append(sql)
            lock.unlock()
            // 服务端对多值 INSERT 报的行数 = VALUES 里行数（探针按同一口径回填，判「写的行数对不对」）。
            let affected = sql.uppercased().hasPrefix("INSERT")
                ? sql.components(separatedBy: "\n  (").count - 1
                : nil
            return AsyncThrowingStream { continuation in
                continuation.yield(.started(statementIndex: 0))
                if let affected {
                    continuation.yield(.resultSet(QueryResult(columns: [], rows: [], affectedRows: affected)))
                }
                continuation.yield(.finished(QuerySummary(statementCount: 1, duration: 0)))
                continuation.finish()
            }
        }
    }

    // MARK: - 夹具

    /// 在**第一次碰 `EgressLog.shared` 之前**把外发日志目录指到本仓 `.build/` 下一个可写目录。
    ///
    /// 为什么本类要管这件事：`EgressLog.shared` 是懒单例，谁先碰它，它的文件位置就定了；
    /// `AppState()` 一构造就碰它，而本类按字母序排在 `MarkdownPreviewProbeTests` 前面。
    /// 那两个类各自的口径（「本仓 `.build/` 下」「shared 必须与默认构造解到同一个文件」）
    /// 只有在 setenv 先落地时才同时成立 —— 本轮实测：不先指好，那条对照判据直接红。
    private static func pinEgressDirectoryIfNeeded() {
        let environment = ProcessInfo.processInfo.environment
        if let injected = environment["DOYAH_EGRESS_LOG_DIR"], !injected.isEmpty { return }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let fallback = root.appendingPathComponent(".build/ui-probe-egress", isDirectory: true)
        try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        setenv("DOYAH_EGRESS_LOG_DIR", fallback.path, 1)
    }

    @MainActor
    private func makeState(readOnly: Bool = false) async -> (AppState, ConnectionConfig) {
        Self.pinEgressDirectoryIfNeeded()
        let config = ConnectionConfig(
            name: "探针库",
            dbType: .postgresql,
            host: "127.0.0.1",
            port: 5432,
            database: "shop",
            username: "probe",
            isReadOnly: readOnly
        )
        let state = AppState()
        // 启动链会回读盘上的连接册并重设选中项 —— 不等它落地就塞假连接，会被它盖掉（时序假红）。
        await state.startupChain?.value
        state.connections = [config]
        state.selectedConnectionID = config.id
        return (state, config)
    }

    private func temporaryFile(_ name: String, contents: Data) throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("b4-probe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try contents.write(to: url)
        return url
    }

    private let ordersColumns: [TableImport.TargetColumn] = [
        .init(name: "id", typeName: "integer", isNullable: false),
        .init(name: "name", typeName: "text"),
        .init(name: "note", typeName: "text")
    ]

    /// 把 COPY 负载解回二维值（NULL 仍是 `nil`）—— 用**产品自己的解码器**，不另写一份。
    private func decodeCopy(_ text: String) -> [[String?]] {
        text.components(separatedBy: CopyTextFormat.rowSeparator)
            .filter { !$0.isEmpty }
            .map { row in
                row.components(separatedBy: CopyTextFormat.columnSeparator).map(CopyTextFormat.unescape)
            }
    }

    @MainActor
    private func assertStarted(
        _ outcome: TableImportStart,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if case .started = outcome { return }
        XCTFail("导入没起来：\(String(describing: outcome))（被拒时理由写在 importError 上）", file: file, line: line)
    }

    @MainActor
    private func waitForImport(_ state: AppState, timeout: TimeInterval = 10) async {
        let deadline = Date().addingTimeInterval(timeout)
        while state.isImportRunning && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertFalse(state.isImportRunning, "导入在 \(timeout) 秒内没结束")
    }

    // MARK: - ① IO-003 备份：点了执行，argv 逐字对得上，密码不进 argv

    @MainActor
    func testDumpRunsExactlyOneCommandWithTheArgvThePanelPreviewed() async {
        let (state, _) = await makeState()
        let runner = FakeRunner()
        state.backupRunner = runner

        let plan = BackupPlan(
            kind: .dump,
            target: BackupCommand.Target(host: "127.0.0.1", port: 5432, user: "postgres", database: "shop"),
            format: .custom,
            filePath: "/tmp/shop.dump",
            noOwner: true,
            clean: true
        )
        let code = await state.runBackupPlan(plan, password: "p@ss w0rd")

        XCTAssertEqual(code, 0, "备份成功却报了非零退出码")
        XCTAssertEqual(runner.snapshot.count, 1, "一次备份应当只起一条命令（实际 \(runner.snapshot.count) 条）")
        guard let invocation = runner.snapshot.first else { return XCTFail("一条命令都没起") }

        // 逐字比 argv —— 「命令拼错必判红」就靠这一行：少一个参数、多一个破折号、顺序变了都红。
        XCTAssertEqual(invocation.executable, "pg_dump")
        XCTAssertEqual(
            invocation.arguments,
            ["--host", "127.0.0.1", "--port", "5432", "--username", "postgres",
             "--format", "custom", "--no-owner", "--clean", "--file", "/tmp/shop.dump", "shop"],
            "pg_dump 的 argv 与面板预览的那条不是同一条：\(invocation)"
        )
        // 密码走环境变量（进程列表对所有人可见，argv 里不许有它）。
        XCTAssertEqual(invocation.environment["PGPASSWORD"], "p@ss w0rd", "密码没有走 PGPASSWORD")
        XCTAssertFalse(invocation.description.contains("p@ss w0rd"), "密码进了 argv：\(invocation)")

        // 日志第一条是「要跑什么」（密码抹成 ***），末条是完成 —— 用户点完要能看见这两句。
        XCTAssertTrue(state.backupRestoreLog.first?.contains("PGPASSWORD=***") == true,
                      "日志第一条不是那条命令：\(state.backupRestoreLog.first ?? "nil")")
        XCTAssertFalse(state.backupRestoreLog.joined().contains("p@ss w0rd"), "真密码出现在日志里")
        XCTAssertTrue(state.backupRestoreLog.contains { $0.hasPrefix("完成：") },
                      "成功之后没有「完成」那一句：\(state.backupRestoreLog)")
        print("🧪 备份读数：1 条命令 · \(invocation) · 日志 \(state.backupRestoreLog.count) 行")
    }

    // MARK: - ② IO-003 备份失败：退出码与线索都说出来，不许显示「完成」

    @MainActor
    func testDumpFailureSurfacesExitCodeAndTailInsteadOfSayingDone() async {
        let (state, _) = await makeState()
        let runner = FakeRunner(bySection: ["": .init(
            exitCode: 1,
            lines: ["pg_dump: error: connection to server at \"127.0.0.1\" failed: 拒绝连接"]
        )])
        state.backupRunner = runner

        let plan = BackupPlan(
            kind: .dump,
            target: BackupCommand.Target(host: "127.0.0.1", port: 5432, database: "shop"),
            format: .plain,
            filePath: "/tmp/shop.sql"
        )
        let code = await state.runBackupPlan(plan, password: nil)

        XCTAssertEqual(code, 1, "退出码没有如实带回界面")
        let log = state.backupRestoreLog.joined(separator: "\n")
        XCTAssertTrue(log.contains("失败（退出码 1）"), "日志没说清失败与退出码：\(log)")
        XCTAssertTrue(log.contains("拒绝连接"), "失败线索（末几行输出）没摊出来：\(log)")
        XCTAssertFalse(state.backupRestoreLog.contains { $0.hasPrefix("完成：") },
                       "失败那一次也写了「完成」—— 用户会以为备份成了")
    }

    // MARK: - ③ IO-004 恢复到指定库：三段按依赖顺序、目标库是用户选的那个

    @MainActor
    func testSectionedRestoreWalksAllThreeSectionsAgainstTheChosenDatabase() async {
        let (state, _) = await makeState()
        let runner = FakeRunner()
        state.backupRunner = runner

        let plan = BackupPlan(
            kind: .restore,
            target: BackupCommand.Target(host: "127.0.0.1", port: 5432, user: "postgres", database: "restore_target"),
            filePath: "/tmp/shop.dump",
            jobs: 4,
            clean: true
        )
        let code = await state.runRestoreSections(plan, password: nil)

        XCTAssertEqual(code, 0, "三段都成功却报了非零退出码")
        let invocations = runner.snapshot
        XCTAssertEqual(invocations.count, 3, "逐段恢复应当恰好起三条命令（实际 \(invocations.count)）")
        XCTAssertEqual(invocations.map { FakeRunner.section(of: $0.arguments) }, ["pre-data", "data", "post-data"],
                       "三段的顺序不是依赖顺序（先结构、再数据、最后索引与约束）")

        for (index, invocation) in invocations.enumerated() {
            XCTAssertEqual(invocation.executable, "pg_restore")
            XCTAssertEqual(
                invocation.arguments,
                ["--host", "127.0.0.1", "--port", "5432", "--username", "postgres",
                 "--dbname", "restore_target", "--clean", "--jobs", "4",
                 "--section", ["pre-data", "data", "post-data"][index], "--exit-on-error", "/tmp/shop.dump"],
                "第 \(index + 1) 段的 argv 不对：\(invocation)"
            )
        }
        XCTAssertFalse(state.backupRestoreLog.contains { $0.hasPrefix("失败") },
                       "明明三段都成功，日志里却有失败行")
    }

    // MARK: - ④ IO-004 中途失败：停在那一段，并给出可粘的续跑命令

    @MainActor
    func testSectionedRestoreStopsAtTheFailingSectionAndOffersTheResumeCommand() async {
        let (state, _) = await makeState()
        let runner = FakeRunner(bySection: ["data": .init(
            exitCode: 1,
            lines: ["pg_restore: error: could not execute query: relation \"t\" already exists"]
        )])
        state.backupRunner = runner

        let plan = BackupPlan(
            kind: .restore,
            target: BackupCommand.Target(host: "127.0.0.1", port: 5432, database: "restore_target"),
            filePath: "/tmp/shop.dump",
            jobs: 2,
            clean: true
        )
        let code = await state.runRestoreSections(plan, password: nil)

        XCTAssertEqual(code, 1, "失败那一段的退出码没有带回界面")
        XCTAssertEqual(runner.snapshot.map { FakeRunner.section(of: $0.arguments) }, ["pre-data", "data"],
                       "数据段失败之后仍在往下跑（或干脆没跑前面那段）")

        let log = state.backupRestoreLog.joined(separator: "\n")
        XCTAssertTrue(log.contains("already exists"), "失败线索没摊出来：\(log)")
        XCTAssertTrue(log.contains("下一步："), "失败后没有「下一步」那一行：\(log)")
        XCTAssertTrue(log.contains("--section data"),
                      "续跑命令不是从失败的那一段（data）接着做：\(log)")
        XCTAssertTrue(log.contains("--fail-fast"), "续跑命令没带「遇错即停」：\(log)")
        XCTAssertTrue(log.contains("--database restore_target"), "续跑命令丢了目标库：\(log)")
        XCTAssertTrue(log.contains("索引与约束（post-data）"),
                      "没有把剩下还没做的段列出来：\(log)")
    }

    // MARK: - ⑤ IO-006 CSV 导入（COPY 快路径）：值不串列、NULL 与空串分得开

    @MainActor
    func testCSVImportSendsEveryValueToTheRightColumnOverCopy() async throws {
        let (state, config) = await makeState()
        let service = FakeImportService(config: config)
        state.importServiceOverride = service

        // 一份**真文件**：引号里的逗号与换行、`""` 转义、未加引号的空（NULL）、加了引号的空（空串）。
        let csv = "id,name,note\n"
            + "1,\"豆花, 加辣\",\"第一行\n第二行\"\n"
            + "2,\"他说\"\"行\"\"\",\n"
            + "3,,\"\"\n"
        let url = try temporaryFile("orders.csv", contents: Data(csv.utf8))
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let parsed = try DelimitedTextReader.read(
            try TextFileDecoder.decode(contentsOf: url).text,
            options: DelimitedTextReader.Options(hasHeader: true)
        )
        XCTAssertEqual(parsed.header, ["id", "name", "note"])
        XCTAssertEqual(parsed.rows.count, 3, "解析出来的行数不对：\(parsed.rows)")
        XCTAssertEqual(parsed.rows[0], ["1", "豆花, 加辣", "第一行\n第二行"], "引号里的逗号 / 换行被读坏了")
        XCTAssertEqual(parsed.rows[1], ["2", "他说\"行\"", nil], "`\"\"` 转义或 NULL 判错：\(parsed.rows[1])")
        XCTAssertEqual(parsed.rows[2], ["3", nil, ""], "未加引号的空（NULL）与加引号的空（空串）没分开")

        let plan = TableImport.plan(
            table: "orders",
            schema: "public",
            sourceHeader: parsed.header,
            targetColumns: ordersColumns
        )
        let request = TableImportRequest(
            table: "orders",
            schema: "public",
            plan: plan,
            rows: parsed.rows,
            mode: .copy,
            bypassingSafetyCheck: true
        )
        assertStarted(state.startTableImport(request))
        await waitForImport(state)

        XCTAssertNil(state.importError, "COPY 导入报了错：\(state.importError ?? "nil")")
        // schema 限定名表达不到 COPY（驱动只加表名的引号）⇒ 必须先在同一连接上设 search_path。
        XCTAssertEqual(service.statements, ["SET search_path TO \"public\""],
                       "COPY 之前没有（或不止一次）设 search_path：\(service.statements)")
        XCTAssertEqual(service.copies.count, 1, "COPY 应当一次提交整段（实际 \(service.copies.count) 次）")
        guard let copy = service.copies.first else { return XCTFail("一次 COPY 都没发") }
        XCTAssertEqual(copy.table, "orders")
        XCTAssertEqual(copy.columns, ["id", "name", "note"], "COPY 的列清单与映射不一致：\(copy.columns)")

        // 负载用产品自己的解码器解回来逐格比 —— 「服务端会收到的值」就是这个。
        XCTAssertEqual(decodeCopy(copy.text), parsed.rows, "COPY 负载里的值串列了：\(decodeCopy(copy.text))")
        print("🧪 CSV→COPY 读数：语句 \(service.statements) · 列 \(copy.columns) · 负载 \(decodeCopy(copy.text))")
    }

    // MARK: - ⑥ IO-006 批量 INSERT 回退：分批复用同一套映射，行数报对

    @MainActor
    func testImportFallsBackToBatchedInsertAndReportsEveryRow() async {
        let (state, config) = await makeState()
        let service = FakeImportService(config: config)
        state.importServiceOverride = service

        let rows: [[String?]] = (1...1200).map { index in
            [String(index), "名-\(index)", index % 2 == 0 ? nil : "note-\(index)"]
        }
        let plan = TableImport.plan(
            table: "orders",
            schema: "public",
            sourceHeader: ["id", "name", "note"],
            targetColumns: ordersColumns
        )
        let request = TableImportRequest(
            table: "orders",
            schema: "public",
            plan: plan,
            rows: rows,
            mode: .batchInsert,
            bypassingSafetyCheck: true
        )
        assertStarted(state.startTableImport(request))
        await waitForImport(state)

        XCTAssertNil(state.importError, "批量 INSERT 报了错：\(state.importError ?? "nil")")
        let statements = service.statements
        XCTAssertEqual(statements.count, 3, "1200 行 / 每批 500 ⇒ 500 · 500 · 200 三条（实际 \(statements.count)）")
        for (index, sql) in statements.enumerated() {
            XCTAssertTrue(sql.hasPrefix("INSERT INTO \"public\".\"orders\" (\"id\", \"name\", \"note\") VALUES"),
                          "第 \(index + 1) 条不是那张表 / 那几列：\(sql.prefix(80))")
        }
        // 数字列不加引号（加了索引失效）、NULL 与空串分开写。
        XCTAssertTrue(statements[0].contains("(1, '名-1', 'note-1')"), "第一行写坏了：\(statements[0].prefix(120))")
        XCTAssertTrue(statements[0].contains("(2, '名-2', NULL)"), "偶数行的 NULL 没写成 NULL：\(statements[0].prefix(120))")
        XCTAssertEqual(state.importProgress, 1.0, accuracy: 0.0001, "进度没有走到 100%")
        XCTAssertEqual(state.importLog.count, 3, "日志应当逐批一行（实际 \(state.importLog.count) 行）")
    }

    // MARK: - ⑦ IO-007 xlsx：真工作簿 → 向导读表 → 值原样落到目标列

    @MainActor
    func testXLSXWizardReadsARealWorkbookAndImportsEveryCell() async throws {
        let (state, config) = await makeState()
        let service = FakeImportService(config: config)
        state.importServiceOverride = service

        // 夹具由产品的写入器造（真 ZIP + OOXML）；空单元格写 nil ⇒ 读回来应当仍是 NULL。
        let workbook = XLSXWriter.workbook(
            sheetName: "订单",
            columns: ["id", "name", "note"],
            rows: [["1", "豆花", "第一行"], ["2", "拿铁", nil]],
            numericColumns: [0]
        )
        let url = try temporaryFile("orders.xlsx", contents: workbook)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        // 走界面那条读法：`XLSXReader.importResult(data, sheet:hasHeader:)`（ImportPanel 里就是它）。
        let parsed = try XLSXReader.importResult(try Data(contentsOf: url), sheet: 0, hasHeader: true)
        XCTAssertEqual(parsed.header, ["id", "name", "note"], "xlsx 的表头没读对：\(parsed.header)")
        XCTAssertEqual(parsed.rows, [["1", "豆花", "第一行"], ["2", "拿铁", nil]],
                       "xlsx 的格子没读对（中文 / 空单元格）：\(parsed.rows)")

        let plan = TableImport.plan(
            table: "orders",
            schema: "public",
            sourceHeader: parsed.header,
            targetColumns: ordersColumns
        )
        XCTAssertEqual(plan.unknownSourceColumns, [], "工作簿的列没对上目标表")
        let request = TableImportRequest(
            table: "orders",
            schema: "public",
            plan: plan,
            rows: parsed.rows,
            mode: .copy,
            bypassingSafetyCheck: true
        )
        assertStarted(state.startTableImport(request))
        await waitForImport(state)

        XCTAssertNil(state.importError, "xlsx 导入报了错：\(state.importError ?? "nil")")
        guard let copy = service.copies.first else { return XCTFail("xlsx 导入一次 COPY 都没发") }
        XCTAssertEqual(decodeCopy(copy.text), [["1", "豆花", "第一行"], ["2", "拿铁", nil]],
                       "xlsx 的值进 COPY 负载时变了：\(decodeCopy(copy.text))")
    }

    // MARK: - ⑧ 唯一闸门：只读连接上按下去，一条语句都不许发

    @MainActor
    func testReadOnlyConnectionRefusesTheImportBeforeAnythingIsSent() async throws {
        let (state, config) = await makeState(readOnly: true)
        let service = FakeImportService(config: config)
        state.importServiceOverride = service

        let plan = TableImport.plan(
            table: "orders",
            schema: "public",
            sourceHeader: ["id", "name", "note"],
            targetColumns: ordersColumns
        )
        let request = TableImportRequest(
            table: "orders",
            schema: "public",
            plan: plan,
            rows: [["1", "豆花", ""]],
            mode: .copy,
            bypassingSafetyCheck: false
        )

        switch state.startTableImport(request) {
        case .refused(let reason):
            XCTAssertFalse(reason.isEmpty, "拒绝时没给理由")
        case .needsConfirmation:
            XCTFail("只读连接不该退成「确认后就能写」")
        case .started:
            XCTFail("只读连接上导入被放行了")
        }
        await waitForImport(state, timeout: 1)
        XCTAssertTrue(service.statements.isEmpty, "被拒绝却仍发了语句：\(service.statements)")
        XCTAssertTrue(service.copies.isEmpty, "被拒绝却仍发了 COPY")
    }

    // MARK: - ⑨ 源锚点：四条链仍走生产那一个入口（不是探针另开的路）

    func testBackupAndImportStayOnOneProductionPath() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let state = try String(contentsOf: root.appendingPathComponent("App/AppState.swift"), encoding: .utf8)

        XCTAssertTrue(state.contains("var backupRunner: any ExternalProcessRunner"), "备份执行器的注入缝没了")
        XCTAssertEqual(state.components(separatedBy: "BackupExecutor(runner: backupRunner)").count - 1, 2,
                       "备份 / 逐段恢复没有共用同一个执行器注入点")
        XCTAssertTrue(state.contains("var importServiceOverride: (any DatabaseService)?"), "导入的服务注入缝没了")
        XCTAssertEqual(state.components(separatedBy: "if let importServiceOverride").count - 1, 1,
                       "导入路径上出现了第二个取服务的地方")

        // 面板只转交，不自己起进程、也不自己拼命令。
        let sheet = try String(contentsOf: root.appendingPathComponent("App/Views/BackupRestoreSheet.swift"), encoding: .utf8)
        XCTAssertFalse(sheet.contains("FoundationProcessRunner"), "备份面板自己起了进程")
        XCTAssertTrue(sheet.contains("appState.runRestoreSections("), "恢复不再走逐段那一条生产入口")

        let panel = try String(contentsOf: root.appendingPathComponent("App/Views/ImportPanel.swift"), encoding: .utf8)
        XCTAssertTrue(panel.contains("appState.startTableImport(request)"), "导入面板不再走那一个入口")
        XCTAssertTrue(panel.contains("XLSXReader.importResult("), "xlsx 不走产品的读取器了")
    }
}
