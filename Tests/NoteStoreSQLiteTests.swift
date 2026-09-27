import XCTest
@testable import DoyahCore

// `FR-PLUG-08`（Q23 拍板：桌面各端笔记存储统一到本地 SQLite）的机械证据：schema v1 / 映射 /
// 全文检索 / 快照备份 / 一次性迁移。
//
// 三条纪律：
//   ① **都跑真库文件**（临时目录），不用 `:memory:` —— WAL、并发、换名、快照在内存库里不存在；
//   ② **判据要成对**：例如"trigram 能按中文子串命中"要配一条"默认分词器命中 0"的对照，
//      否则「换一张刚好有那两个字作独立词的表」也能骗过去；
//   ③ **孤儿行要真查一遍**（级联删除不是声明了就生效 —— SQLite 默认关着外键，
//      这一条就是盯着"忘了 `PRAGMA foreign_keys = ON`"这类静默失效）。
final class NoteStoreSQLiteTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("doyah-note-sqlite-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    private func url(_ name: String = NoteDatabase.fileName) -> URL {
        directory.appendingPathComponent(name, isDirectory: false)
    }

    private func makeDatabase() throws -> NoteDatabase {
        try NoteDatabase(path: url().path)
    }

    private func sampleNote(
        title: String,
        body: String = "",
        tags: [String] = [],
        connectionName: String? = nil,
        containsRowData: Bool = false,
        updatedAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> Note {
        Note(
            id: UUID(),
            title: title,
            body: body,
            tags: tags,
            source: NoteSource(
                kind: .manual,
                connectionName: connectionName,
                fingerprint: "fp-\(title)",
                capturedAt: Date(timeIntervalSince1970: 1_699_000_000)
            ),
            createdAt: Date(timeIntervalSince1970: 1_699_500_000),
            updatedAt: updatedAt,
            containsRowData: containsRowData
        )
    }

    // MARK: - ① schema v1

    func testSchemaIsCreatedAtVersionOneWithEveryDeclaredObject() throws {
        let database = try makeDatabase()
        XCTAssertEqual(database.userVersion, NoteSchemaV1.version)

        let tables = try database.tableNames()
        for expected in NoteSchemaV1.tables {
            XCTAssertTrue(tables.contains(expected), "缺表 \(expected)；实际：\(tables)")
        }
        let triggers = try database.triggerNames()
        for expected in NoteSchemaV1.triggers {
            XCTAssertTrue(triggers.contains(expected), "缺触发器 \(expected)；实际：\(triggers)")
        }
        let indexes = try SQLiteConnection(path: url().path).schemaObjects(kind: "index")
        for expected in NoteSchemaV1.indexes {
            XCTAssertTrue(indexes.contains(expected), "缺索引 \(expected)；实际：\(indexes)")
        }
        XCTAssertEqual(try database.integrityCheck(), "ok")
    }

    /// 打开第二次不许动数据（幂等）：schema 已是 v1 就不再跑 DDL，笔记条数不变。
    func testReopeningDoesNotReshapeOrLoseData() throws {
        let first = try makeDatabase()
        try first.upsert(sampleNote(title: "第一条"))
        try first.close()

        let second = try makeDatabase()
        XCTAssertEqual(second.userVersion, 1)
        XCTAssertEqual(try second.noteCount(), 1)
        XCTAssertEqual(try second.notes().first?.title, "第一条")
    }

    func testWALAndForeignKeysAreEnabled() throws {
        let database = try makeDatabase()
        XCTAssertEqual(database.journalMode, "wal")
        XCTAssertTrue(database.foreignKeysEnabled, "外键没开 ⇒ 级联删除是装饰品")
    }

    /// 库的 schema 比代码更新（用户回退过 App 版本）时**拒绝打开**，而不是拿旧代码去改新库。
    func testNewerSchemaVersionIsRejectedInsteadOfDowngraded() throws {
        try makeDatabase().close()
        let raw = try SQLiteConnection(path: url().path)
        try raw.setPragma("user_version = 99")
        try raw.close()

        XCTAssertThrowsError(try makeDatabase()) { error in
            guard case NoteStorageFailure.unsupportedSchemaVersion(let found, let supported) = error else {
                return XCTFail("期望 unsupportedSchemaVersion，实际：\(error)")
            }
            XCTAssertEqual(found, 99)
            XCTAssertEqual(supported, NoteSchemaV1.version)
        }
    }

    // MARK: - ② 映射（笔记 ↔ 表）

    func testEveryFieldSurvivesTheRoundTrip() throws {
        let database = try makeDatabase()
        let note = Note(
            id: UUID(),
            title: "关于骑行的笔记",
            body: "洞庭湖边吹尺八",
            // 标签按**表里的集合口径**给（去重 + 排序）：`Note.tags` 在库里是集合语义，
            // 顺序不是信息（主键 `(note_id, tag)` 本来就无序）。第 21 轮接线时这条用例先按原序给，
            // 于是"读回来排序过"被判成不相等 —— 判据改成：**先按同一口径给**，再单独断言排序口径。
            tags: ["尺八", "骑行"],
            source: NoteSource(
                kind: .diagnosis,
                connectionName: "本地 16.2",
                fingerprint: "abc123",
                capturedAt: Date(timeIntervalSince1970: 1_699_999_999)
            ),
            createdAt: Date(timeIntervalSince1970: 1_699_000_001),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_002),
            containsRowData: true
        )
        try database.upsert(note)

        guard let read = try database.note(id: note.id) else {
            return XCTFail("刚写进去的笔记读不回来")
        }
        // `Note` 是 Equatable：逐字段比（含时间、来源、含行数据标记）。
        XCTAssertEqual(read, note)

        // 标签的**序列化口径**单独钉一条：乱序 + 重复写进去，读回来是一份排好序的集合。
        var messy = sampleNote(title: "标签口径", tags: ["b", "a", "b"])
        try database.upsert(messy)
        XCTAssertEqual(try database.note(id: messy.id)?.tags, ["a", "b"])
        messy.tags = ["骑行", "尺八"]
        try database.upsert(messy)
        XCTAssertEqual(try database.note(id: messy.id)?.tags, ["尺八", "骑行"], "读回来是排序过的稳定口径")
    }

    /// `NULL`（没有连接来源）与空串（有来源、名字是空的）**必须分得开**。
    func testNullAndEmptyStringConnectionNamesStayDistinct() throws {
        let database = try makeDatabase()
        let noSource = sampleNote(title: "无来源", connectionName: nil)
        let emptySource = sampleNote(title: "空名来源", connectionName: "")
        try database.upsert(noSource)
        try database.upsert(emptySource)

        XCTAssertNil(try database.note(id: noSource.id)?.source.connectionName)
        XCTAssertEqual(try database.note(id: emptySource.id)?.source.connectionName, "")
    }

    /// `containsRowData` 是**永久留痕**（SRS §4.13 安全边界）：写进去就得读得出来。
    func testContainsRowDataFlagIsPersisted() throws {
        let database = try makeDatabase()
        let plain = sampleNote(title: "普通")
        let withRows = sampleNote(title: "含行数据", containsRowData: true)
        try database.upsert(plain)
        try database.upsert(withRows)

        XCTAssertEqual(try database.note(id: plain.id)?.containsRowData, false)
        XCTAssertEqual(try database.note(id: withRows.id)?.containsRowData, true)
    }

    /// 标签是**全量替换**语义，不是累加；重复标签按集合口径收一次。
    func testTagsAreReplacedNotAccumulated() throws {
        let database = try makeDatabase()
        var note = sampleNote(title: "标签", tags: ["a", "b", "a"])
        try database.upsert(note)
        XCTAssertEqual(try database.note(id: note.id)?.tags, ["a", "b"])

        note.tags = ["b", "c"]
        note.updatedAt = note.updatedAt.addingTimeInterval(60)
        try database.upsert(note)
        XCTAssertEqual(try database.note(id: note.id)?.tags, ["b", "c"])
        XCTAssertEqual(try database.noteCount(), 1, "同一 uuid 是覆盖（upsert），不是新增")
    }

    /// 时间线是**流水**（只增不改）：一次 upsert 一条痕迹。
    func testTimelineAccumulatesAndAttachmentsKeepPathsOnly() throws {
        let database = try makeDatabase()
        var note = sampleNote(title: "带附件")
        try database.upsert(note)
        try database.addAttachment(
            NoteAttachment(path: "/Users/alex/Documents/行情快照.csv", byteCount: 2048),
            to: note.id
        )
        note.updatedAt = note.updatedAt.addingTimeInterval(120)
        try database.upsert(note)

        let timeline = try database.timeline(of: note.id)
        XCTAssertEqual(timeline.count, 2)
        XCTAssertEqual(timeline.map(\.kind), [NoteTimelineKind.upsert, NoteTimelineKind.upsert])
        XCTAssertTrue(timeline[0].at <= timeline[1].at, "时间线按时间正序")

        let attachments = try database.attachments(of: note.id)
        XCTAssertEqual(attachments.count, 1)
        XCTAssertEqual(attachments.first?.path, "/Users/alex/Documents/行情快照.csv")
        XCTAssertEqual(attachments.first?.byteCount, 2048)
    }

    /// 删一条笔记，标签 / 时间线 / 附件索引**一起走**（真查孤儿行，不看声明）。
    func testDeleteCascadesToTagsTimelineAndAttachments() throws {
        let database = try makeDatabase()
        let note = sampleNote(title: "待删", tags: ["x", "y"])
        try database.upsert(note)
        try database.addAttachment(NoteAttachment(path: "/tmp/a.txt"), to: note.id)

        try database.delete(id: note.id)

        let raw = try SQLiteConnection(path: url().path)
        for table in ["note_tag", "note_timeline", "note_attachment"] {
            let orphans = try raw.scalarInt(
                "SELECT count(*) FROM \(table) WHERE note_id NOT IN (SELECT id FROM note)"
            )
            XCTAssertEqual(orphans, 0, "\(table) 留下了孤儿行")
            let total = try raw.scalarInt("SELECT count(*) FROM \(table)")
            XCTAssertEqual(total, 0, "\(table) 该随笔记一起被级联删掉")
        }
        XCTAssertEqual(try database.noteCount(), 0)
    }

    /// 表里出现这一版不认识的 `source_kind`：**抛错**，不静默降级成 `.manual`。
    func testUnknownSourceKindIsRejectedInsteadOfDowngraded() throws {
        let database = try makeDatabase()
        try database.close()
        // 绕过存储层直接写一行"将来版本才认识的 kind"（模拟 App 回退后遇到新数据）。
        let raw = try SQLiteConnection(path: url().path)
        try raw.execute(
            """
            INSERT INTO note (uuid, title, body, source_kind, source_captured_at, created_at, updated_at)
            VALUES (?, '未来笔记', '', 'future-kind', 1, 1, 1);
            """,
            [.text(UUID().uuidString)]
        )
        let reopened = try makeDatabase()
        XCTAssertThrowsError(try reopened.notes()) { error in
            XCTAssertEqual(error as? NoteStorageFailure, .unknownSourceKind("future-kind"))
        }
    }

    // MARK: - ③ 检索

    /// 中文全文检索：**trigram 能按子串命中**（≥3 字），而 1~2 字查询走子串兜底。
    ///
    /// 成对判据：① 3 字中文命中且路线是 `fullText`；② 2 字中文也能命中（路线 `substring`）——
    /// 后者是第 18 轮实测的直接后果（trigram 不产出 1~2 字 token），不兜底就等于"检索不到"。
    func testChineseFullTextSearchUsesTrigramWithSubstringFallback() throws {
        let database = try makeDatabase()
        try database.upsert(sampleNote(title: "环洞庭湖热身", body: "关于骑行与尺八的几件事"))
        try database.upsert(sampleNote(title: "别的", body: "无关内容"))

        let fullText = try database.search("洞庭湖")
        XCTAssertEqual(fullText.route, .fullText)
        XCTAssertEqual(fullText.notes.map(\.title), ["环洞庭湖热身"])

        let substring = try database.search("骑行")
        XCTAssertEqual(substring.route, .substring)
        XCTAssertEqual(substring.notes.map(\.title), ["环洞庭湖热身"])

        // `LIKE` 的通配符要转义：搜 `%` 不该匹配到所有笔记。
        XCTAssertTrue(try database.search("%%%").notes.isEmpty)
    }

    /// 索引与正文**结构性同步**（触发器），改标题后旧词查不到、新词查得到；删掉后查不到。
    func testFullTextIndexFollowsUpdatesAndDeletes() throws {
        let database = try makeDatabase()
        var note = sampleNote(title: "南太行拉练", body: "第一天")
        try database.upsert(note)
        XCTAssertEqual(try database.search("南太行").notes.count, 1)

        note.title = "云南拉练"
        note.body = "第二天"
        try database.upsert(note)
        XCTAssertTrue(try database.search("南太行").notes.isEmpty, "旧词必须从索引里消失")
        XCTAssertEqual(try database.search("云南拉练").notes.count, 1)

        try database.delete(id: note.id)
        XCTAssertTrue(try database.search("云南拉练").notes.isEmpty, "删笔记要连索引一起清")
        // 外部内容表：索引空了，内容表也该是空的（没有残留行把 count 撑起来）。
        let raw = try SQLiteConnection(path: url().path)
        XCTAssertEqual(try raw.scalarInt("SELECT count(*) FROM note_fts"), 0)
    }

    /// 空查询给全部（更新时间倒序），不是给空 —— 界面打开时的默认列表就走这一条。
    func testEmptyQueryReturnsEveryNoteInStableOrder() throws {
        let database = try makeDatabase()
        let older = sampleNote(title: "旧", updatedAt: Date(timeIntervalSince1970: 100))
        let newer = sampleNote(title: "新", updatedAt: Date(timeIntervalSince1970: 200))
        try database.upsert(older)
        try database.upsert(newer)

        XCTAssertEqual(try database.search("   ").notes.map(\.title), ["新", "旧"])
        XCTAssertEqual(try database.notes().map(\.title), ["新", "旧"])
    }

    // MARK: - ④ 快照备份（VACUUM INTO）

    /// 快照必须**自洽且能用**：读回来行数与完整性都对，而且真的能当库打开（不是"存了个文件"）。
    func testSnapshotIsReadableAndMatchesTheSource() throws {
        let database = try makeDatabase()
        for index in 1...3 {
            try database.upsert(sampleNote(title: "第 \(index) 条", body: "洞庭湖 \(index)"))
        }
        let target = url("snapshots/notes-20260927T143000.sqlite3")

        let snapshot = try database.snapshot(to: target)
        XCTAssertEqual(snapshot.noteCount, 3)
        XCTAssertEqual(snapshot.schemaVersion, NoteSchemaV1.version)
        XCTAssertEqual(snapshot.integrity, "ok")
        XCTAssertGreaterThan(snapshot.byteCount, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: target.path + ".partial"),
            "中间件不该留在盘上"
        )

        let restored = try NoteDatabase(path: target.path)
        XCTAssertEqual(try restored.notes().map(\.title), try database.notes().map(\.title))
        XCTAssertEqual(try restored.search("洞庭湖").notes.count, 3, "快照里的全文索引也要能用")
        try restored.close()
    }

    /// **不覆盖已有备份**：备份顶掉上一次的备份，等于把"后悔药"变成一颗。
    func testSnapshotRefusesToOverwriteAnExistingBackup() throws {
        let database = try makeDatabase()
        try database.upsert(sampleNote(title: "唯一一条"))
        let target = url("snapshots/notes-fixed.sqlite3")
        try database.snapshot(to: target)
        let before = try Data(contentsOf: target)

        XCTAssertThrowsError(try database.snapshot(to: target)) { error in
            XCTAssertEqual(error as? NoteStorageFailure, .snapshotTargetExists(target.path))
        }
        XCTAssertEqual(try Data(contentsOf: target), before, "既有备份一个字节都不许动")
    }

    /// 快照文件名带 UTC 时间戳（同一个文件不会被下一次备份撞上）。
    func testSnapshotFileNameIsTimestamped() {
        let name = NoteDatabase.snapshotFileName(at: Date(timeIntervalSince1970: 1_774_000_000))
        XCTAssertTrue(name.hasPrefix("notes-"))
        XCTAssertTrue(name.hasSuffix(".sqlite3"))
        XCTAssertEqual(name.count, "notes-20260327T060000.sqlite3".count)
        // 两秒之差 → 文件名必须不同（否则连续两次备份会互相顶掉）。
        XCTAssertNotEqual(name, NoteDatabase.snapshotFileName(at: Date(timeIntervalSince1970: 1_774_000_002)))
    }

    // MARK: - ⑤ 一次性迁移（notes.json → notes.sqlite3）

    /// 常规路径：数据全搬过去、旧文件**改名留档**（不删）、再跑一次幂等。
    func testMigrationMovesEveryNoteAndKeepsTheLegacyFile() async throws {
        let notes = [
            sampleNote(title: "第一条", body: "洞庭湖", tags: ["骑行", "尺八"], connectionName: "本地"),
            sampleNote(title: "第二条", body: "南太行", tags: ["徒步"])
        ]
        let jsonURL = url(NoteStore.fileName)
        try await NoteStore(fileURL: jsonURL).save(notes)
        let originalBytes = try Data(contentsOf: jsonURL)

        let report = NoteLibraryMigration.migrateIfNeeded(jsonURL: jsonURL, databaseURL: url())
        XCTAssertEqual(report.outcome, .migrated)
        XCTAssertEqual(report.noteCount, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: jsonURL.path), "旧文件应该已经改名")
        XCTAssertEqual(report.backupURL?.lastPathComponent, NoteLibraryMigration.backupFileName)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(report.backupURL)), originalBytes, "留档要逐字节一致")

        let database = try makeDatabase()
        XCTAssertEqual(try database.noteCount(), 2)
        XCTAssertEqual(
            NoteLibraryMigration.normalized(try database.notes()),
            NoteLibraryMigration.normalized(notes),
            "搬过去的必须是同一批笔记（逐字段）"
        )
        // 标签进的是集合语义的表：查一下真的落了两行。
        let raw = try SQLiteConnection(path: url().path)
        XCTAssertEqual(try raw.scalarInt("SELECT count(*) FROM note_tag"), 3)

        // 幂等：目标库已存在 ⇒ 一个字节都不动。
        let again = NoteLibraryMigration.migrateIfNeeded(jsonURL: jsonURL, databaseURL: url())
        XCTAssertEqual(again.outcome, .skippedTargetExists)
    }

    /// 目标库已存在时**先判后做**：连旧文件都不该碰（旧文件放在那里，也不许被搬走）。
    func testMigrationSkipsWhenTargetDatabaseAlreadyExists() async throws {
        try makeDatabase().close()
        let jsonURL = url(NoteStore.fileName)
        try await NoteStore(fileURL: jsonURL).save([sampleNote(title: "旧的")])

        let report = NoteLibraryMigration.migrateIfNeeded(jsonURL: jsonURL, databaseURL: url())
        XCTAssertEqual(report.outcome, .skippedTargetExists)
        XCTAssertTrue(FileManager.default.fileExists(atPath: jsonURL.path), "旧文件必须原地不动")
    }

    /// 坏文件（不是 JSON）：**原地保留、不建库**，并如实报出原因。
    func testBrokenLegacyFileIsReportedAndLeftAlone() throws {
        let jsonURL = url(NoteStore.fileName)
        let broken = Data("不是 JSON，是随手写的文本".utf8)
        try broken.write(to: jsonURL)

        let report = NoteLibraryMigration.migrateIfNeeded(jsonURL: jsonURL, databaseURL: url())
        XCTAssertEqual(report.outcome, .legacyUnreadable)
        XCTAssertNotNil(report.failure)
        XCTAssertTrue(report.needsAttention)
        XCTAssertEqual(try Data(contentsOf: jsonURL), broken, "读不懂就别搬：一个字节都不动")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url().path), "目标库不该被建出来")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: url().path + NoteLibraryMigration.incomingSuffix),
            "中间件也不该留下"
        )
    }

    /// 旧文件不存在 ⇒ 什么都没有要搬（第一次用）。
    func testMigrationDoesNothingWithoutALegacyFile() throws {
        let report = NoteLibraryMigration.migrateIfNeeded(jsonURL: url(), databaseURL: url())
        XCTAssertEqual(report.outcome, .nothingToMigrate)
        XCTAssertFalse(report.needsAttention)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url().path))
    }

    /// 空库（JSON 是空数组）照样算搬完：不报错、也不留半个文件。
    func testMigrationOfAnEmptyLegacyLibrary() async throws {
        let jsonURL = url(NoteStore.fileName)
        try await NoteStore(fileURL: jsonURL).save([])

        let report = NoteLibraryMigration.migrateIfNeeded(jsonURL: jsonURL, databaseURL: url())
        XCTAssertEqual(report.outcome, .migrated)
        XCTAssertEqual(report.noteCount, 0)
        XCTAssertEqual(try makeDatabase().userVersion, 1)
    }

    /// 生效的 `DOYAH_NOTES_DIR` 覆盖 ⇒ 主动让路（别把真实用户的笔记搬进临时目录）。
    func testMigrationStepsAsideWhenNotesDirectoryIsOverridden() {
        let report = NoteLibraryMigration.migrateIfNeeded(
            environment: ["DOYAH_NOTES_DIR": directory.path]
        )
        XCTAssertEqual(report.outcome, .skippedOverridden)
        XCTAssertFalse(report.needsAttention)
    }

    /// 迁移后的库是**单文件**交付（没有 `-wal` 侧车留在原地 —— 换名只搬主库文件）。
    func testMigratedDatabaseIsDeliveredAsASingleFile() async throws {
        let jsonURL = url(NoteStore.fileName)
        try await NoteStore(fileURL: jsonURL).save([sampleNote(title: "单文件")])
        XCTAssertEqual(
            NoteLibraryMigration.migrateIfNeeded(jsonURL: jsonURL, databaseURL: url()).outcome,
            .migrated
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: url().path + "-wal"),
            "交付的库不该拖着一个 -wal 旁文件"
        )
        // 打开后（App 的常规路径）再切成 WAL：这条开关跟着库走。
        XCTAssertEqual(try makeDatabase().journalMode, "wal")
    }
}
