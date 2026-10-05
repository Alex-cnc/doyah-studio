import XCTest
@testable import DoyahCore

// `FR-PLUG-08` 第 3 批（`NoteStore` 换引擎）的机械证据：**界面与 CLI 走的那一层**（`NoteLibrary`）。
//
// 三条纪律（与第 2 批那份 `NoteStoreSQLiteTests` 同源）：
//   ① **都跑真库文件**（临时目录），不用 `:memory:` —— WAL、换名、快照在内存库里不存在；
//   ② **判据要成对**：说「界面/CLI 走新存储」不能只靠这句注释 —— 见
//      `testInterfaceAndCommandLineGoThroughTheLibrary`，它去源树里逐字找旧引擎的构造点，
//      并且**先自检判据没空转**（读到的文件太短就当场报红）；
//   ③ **删了要真查孤儿行**：级联删除不是声明了就生效（SQLite 默认关外键）。
final class NoteLibraryTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("doyah-note-library-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    // MARK: - 夹具

    private func url(_ name: String = NoteLibrary.fileName) -> URL {
        directory.appendingPathComponent(name, isDirectory: false)
    }

    private func library() -> NoteLibrary {
        NoteLibrary(databaseURL: url())
    }

    private func draft(title: String = "第一条", body: String = "SELECT 1", tags: [String] = []) -> NoteDraft {
        NoteDraft(
            title: title,
            body: body,
            tags: tags,
            source: NoteSource(kind: .diagnosis, connectionName: "本地库", fingerprint: "fp-1")
        )
    }

    private func writeLegacyJSON(_ notes: [Note], to fileURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(notes).write(to: fileURL)
    }

    // MARK: - 1) 还没有库

    func testFreshLibraryReportsAbsentAndCreatesNoFile() async throws {
        let store = library()
        let outcome = await store.loadOutcome()

        XCTAssertEqual(outcome, .absent, "第一次用应当是「还没有库」，不是「读不出来」")
        let loaded = try await store.load()
        XCTAssertTrue(loaded.isEmpty)
        // **读不该把库造出来**：一读就落一个空库，会让「第一次用」与「库被清空」长得一样。
        XCTAssertFalse(FileManager.default.fileExists(atPath: url().path), "读操作不许创建库文件")
    }

    // MARK: - 2) 写进的是 SQLite，不是旧格式

    func testUpsertWritesIntoSQLiteAndLeavesNoJSONFile() async throws {
        let store = library()
        _ = try await store.upsert(draft())

        XCTAssertTrue(FileManager.default.fileExists(atPath: url().path), "应当落下 \(NoteLibrary.fileName)")
        let legacy = url(NoteStore.fileName)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path), "不许再往旧格式文件里写")
        // 打开它、按库的方式念一遍（不是按 JSON 念）
        let database = try NoteDatabase(path: url().path)
        XCTAssertEqual(try database.noteCount(), 1)
        XCTAssertEqual(try database.userVersion, NoteDatabase.supportedVersion)
    }

    // MARK: - 3) 逐字段往返

    func testUpsertRoundTripsEveryField() async throws {
        let store = library()
        let capturedAt = Date(timeIntervalSince1970: 1_780_000_000)
        let source = NoteSource(kind: .skill, connectionName: "本地库", fingerprint: "fp-9", capturedAt: capturedAt)
        let note = try await store.upsert(
            NoteDraft(title: "运维笔记", body: "洞庭湖骑行", tags: ["骑行", "笔记"], source: source).withRowData()
        )

        let loaded = try await store.load()
        XCTAssertEqual(loaded.count, 1)
        let readBack = try XCTUnwrap(loaded.first)
        XCTAssertEqual(readBack.id, note.id)
        XCTAssertEqual(readBack.title, "运维笔记")
        XCTAssertEqual(readBack.body, "洞庭湖骑行")
        XCTAssertEqual(readBack.tags.sorted(), ["笔记", "骑行"].sorted())
        XCTAssertEqual(readBack.source.kind, .skill)
        XCTAssertEqual(readBack.source.connectionName, "本地库")
        XCTAssertEqual(readBack.source.fingerprint, "fp-9")
        XCTAssertEqual(readBack.source.capturedAt.timeIntervalSince1970, capturedAt.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertTrue(readBack.containsRowData, "「含结果集行数据」这条留痕必须存得住")
    }

    // MARK: - 4) 幂等：按 id 覆盖一次，不产生第二条

    func testSecondUpsertIsIdempotentAndKeepsCreatedAt() async throws {
        let store = library()
        let first = try await store.upsert(draft(title: "改前"))

        let later = first.updatedAt.addingTimeInterval(60)
        let second = try await store.upsert(draft(title: "改后"), id: first.id, now: later)

        let database = try NoteDatabase(path: url().path)
        XCTAssertEqual(try database.noteCount(), 1, "按 id 覆盖不该多出一条")
        XCTAssertEqual(second.id, first.id)
        XCTAssertEqual(second.title, "改后")
        // 创建时间是事实：改几个字不该把它改写成现在（旧引擎就是这么定的，换引擎不改语义）。
        XCTAssertEqual(second.createdAt.timeIntervalSince1970, first.createdAt.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(second.updatedAt.timeIntervalSince1970, later.timeIntervalSince1970, accuracy: 0.001)
    }

    // MARK: - 5) 删除要真删干净（级联，不是靠声明）

    func testDeleteRemovesTheNoteAndItsTagAndTimelineRows() async throws {
        let store = library()
        let note = try await store.upsert(draft(tags: ["骑行"]))

        // 先自检前提：写进去的时候，标签与时间线**确实**有行 —— 否则下面「删完是 0」等于什么都没验。
        let connection = try SQLiteConnection(path: url().path)
        let tagBefore = try connection.scalarInt("SELECT count(*) FROM note_tag")
        let timelineBefore = try connection.scalarInt("SELECT count(*) FROM note_timeline")
        XCTAssertEqual(tagBefore, 1)
        XCTAssertEqual(timelineBefore, 1, "每次写都该在时间线上留一条")

        try await store.delete(id: note.id)

        XCTAssertEqual(try connection.scalarInt("SELECT count(*) FROM note"), 0)
        XCTAssertEqual(try connection.scalarInt("SELECT count(*) FROM note_tag"), 0, "孤儿标签行 = 外键没开（PRAGMA 默认是关的）")
        XCTAssertEqual(try connection.scalarInt("SELECT count(*) FROM note_timeline"), 0, "孤儿时间线行同上")
        try connection.close()
        let remaining = try await store.load()
        XCTAssertTrue(remaining.isEmpty)
    }

    // MARK: - 6) 检索：所走的路线要如实报出来

    func testSearchReportsWhichRouteItTook() async throws {
        let store = library()
        _ = try await store.upsert(draft(title: "环洞庭湖", body: "洞庭湖骑行手记"))

        let fullText = try await store.search("洞庭湖")
        XCTAssertEqual(fullText.route, .fullText, "≥3 字该走 trigram")
        XCTAssertEqual(fullText.notes.count, 1)

        let substring = try await store.search("骑行")
        XCTAssertEqual(substring.route, .substring, "2 字查询 trigram 切不出 token，只能子串兜底")
        XCTAssertEqual(substring.notes.count, 1)

        let missing = try await store.search("不存在的词")
        XCTAssertTrue(missing.notes.isEmpty)
    }

    // MARK: - 6b) 界面要说的那一句：路线 → 文案键是一处纯映射（队列 L-44）

    func testSearchDisclosureMapsEveryRouteToItsCopy() throws {
        // 界面上「这一次是按子串找到的」不是视图的自由发挥：路线来自 Core，
        // 「哪条路要不要交代」也由 Core 说了算（`NoteSearchDisclosure`）。
        XCTAssertNil(NoteSearchDisclosure.key(for: .fullText), "全文检索命中是检索的正常结果，不该额外解释")
        XCTAssertEqual(NoteSearchDisclosure.key(for: .substring), .noteSearchSubstring)

        // 两条交代必须在语言表里**中英都在**（语言表自己的门禁只管占位符对账，
        // 「键有没有落进表」得有人管 —— 只加 case 不加文案，界面会静默显示成键名）。
        for key in [LKey.noteSearchSubstring, .noteSearchUnavailable] {
            for language in AppLanguage.allCases {
                XCTAssertFalse(
                    LocalizedStrings.text(key, language: language).isEmpty,
                    "\(key) 缺 \(language.rawValue) 文案"
                )
            }
        }
        // 失效交代带原因参数：中英都必须留着那个 `%@`（丢了就永远印不出原因）。
        for language in AppLanguage.allCases {
            XCTAssertTrue(
                LocalizedStrings.text(.noteSearchUnavailable, language: language).contains("%@"),
                "noteSearchUnavailable 的 \(language.rawValue) 模板少了 %@ —— 原因就印不出来了"
            )
        }
    }

    // MARK: - 7) 引擎迁移：旧格式搬进库、旧文件留档

    func testLegacyJSONIsImportedOnceAndKeptAsBackup() async throws {
        let jsonURL = url(NoteStore.fileName)
        let original = [
            Note(title: "旧库第一条", body: "SELECT 1", tags: ["a", "b"], source: NoteSource(kind: .manual)),
            Note(title: "旧库第二条", body: "SELECT 2", tags: [])
        ]
        try writeLegacyJSON(original, to: jsonURL)

        let report = NoteLibraryMigration.migrateIfNeeded(jsonURL: jsonURL, databaseURL: url())
        XCTAssertEqual(report.outcome, .migrated)
        XCTAssertEqual(report.noteCount, 2)
        XCTAssertEqual(report.backupURL?.lastPathComponent, NoteLibraryMigration.backupFileName)
        XCTAssertFalse(FileManager.default.fileExists(atPath: jsonURL.path), "旧文件应当改名留档，而不是原地不动")

        let outcome = await library().loadOutcome()
        guard case .loaded(let notes) = outcome else {
            return XCTFail("迁移之后界面该读到两份笔记，实际是 \(outcome)")
        }
        XCTAssertEqual(notes.map(\.title).sorted(), ["旧库第一条", "旧库第二条"])
        XCTAssertEqual(notes.first(where: { $0.title == "旧库第一条" })?.tags.sorted(), ["a", "b"])
    }

    // MARK: - 8) 迁移幂等：库已在，一个字节都不动

    func testEngineMigrationIsIdempotentAndTouchesNothing() async throws {
        let jsonURL = url(NoteStore.fileName)
        try writeLegacyJSON([Note(title: "旧库第一条", body: "SELECT 1")], to: jsonURL)
        XCTAssertEqual(NoteLibraryMigration.migrateIfNeeded(jsonURL: jsonURL, databaseURL: url()).outcome, .migrated)

        let before = try Data(contentsOf: url())
        try writeLegacyJSON([Note(title: "后来手动放回去的", body: "SELECT 2")], to: jsonURL)

        let second = NoteLibraryMigration.migrateIfNeeded(jsonURL: jsonURL, databaseURL: url())
        XCTAssertEqual(second.outcome, .skippedTargetExists, "库在就是更新的那一份 —— 幂等的落点")
        XCTAssertEqual(second.noteCount, 0)
        XCTAssertEqual(try Data(contentsOf: url()), before, "跳过时库文件不许被动过一个字节")
        XCTAssertTrue(FileManager.default.fileExists(atPath: jsonURL.path), "跳过时旧文件仍在原处（读数的人自己判断）")
    }

    // MARK: - 9) 坏文件：如实报、别建库

    func testBrokenLegacyJSONIsReportedAndCreatesNoLibrary() async throws {
        let jsonURL = url(NoteStore.fileName)
        try Data("{ 这不是笔记库".utf8).write(to: jsonURL)

        let report = NoteLibraryMigration.migrateIfNeeded(jsonURL: jsonURL, databaseURL: url())
        XCTAssertEqual(report.outcome, .legacyUnreadable)
        XCTAssertTrue(report.needsAttention)
        XCTAssertNotNil(report.failure, "原因要留给界面/CLI 说给人听（不翻译的那份原文）")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url().path), "读不懂就别建库")
        XCTAssertTrue(FileManager.default.fileExists(atPath: jsonURL.path), "坏文件原地保留，不许删")

        let outcome = await library().loadOutcome()
        XCTAssertEqual(outcome, .absent, "没有库 = 第一次用；「文件坏了」这条由迁移报告说清楚")
    }

    // MARK: - 10) 比代码新的库：拒绝用，不静默当空库

    func testLibraryNewerThanCodeIsReportedRatherThanEmptied() async throws {
        // 先造一个正常的库，再把它标成「将来那版写的」—— 模拟用户回退 App 版本。
        _ = try NoteDatabase(path: url().path)
        let connection = try SQLiteConnection(path: url().path)
        try connection.setPragma("user_version = 99")
        try connection.close()

        let outcome = await library().loadOutcome()
        guard case .unreadable(let failure) = outcome else {
            return XCTFail("比代码新的库必须如实报错，实际是 \(outcome)")
        }
        XCTAssertTrue(failure.contains("99"), "报错要说得出库里的版本号，实际：\(failure)")
    }

    // MARK: - 11) 备份 = 单文件快照（走 NoteLibrary 这条门）

    func testSnapshotFromTheLibraryReadsBackWithIntegrityOK() async throws {
        let store = library()
        _ = try await store.upsert(draft(title: "要备份的"))

        let snapshot = try await store.snapshot(to: directory.appendingPathComponent("backup.sqlite3"))
        XCTAssertEqual(snapshot.noteCount, 1)
        XCTAssertEqual(snapshot.integrity, "ok")
        XCTAssertEqual(snapshot.schemaVersion, NoteDatabase.supportedVersion)
        XCTAssertTrue(FileManager.default.fileExists(atPath: snapshot.url.path))
    }

    // MARK: - 12) 界面与 CLI 真的走这一层（源树判据）

    func testInterfaceAndCommandLineGoThroughTheLibrary() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let targets = ["App/AppState.swift", "CLI/main.swift"]

        for relative in targets {
            let url = root.appendingPathComponent(relative)
            let text = try String(contentsOf: url, encoding: .utf8)

            // **判据自己不许空转**：读到的文件太短（路径错了 / 换成空文件）当场报红。
            XCTAssertGreaterThan(text.count, 10_000, "\(relative) 读到的内容太短，这条判据不成立")

            XCTAssertTrue(text.contains("NoteLibrary"), "\(relative) 该走 NoteLibrary（SQLite 引擎）")
            XCTAssertFalse(
                text.contains("NoteStore("),
                "\(relative) 里出现了旧引擎的构造点 —— 换引擎之后界面/CLI 不许再直接构造 JSON 库"
            )
            XCTAssertFalse(
                text.contains("NoteStore.defaultStore("),
                "\(relative) 里出现了 `NoteStore.defaultStore()` —— 那是旧引擎（JSON）的入口"
            )
        }
    }
}
