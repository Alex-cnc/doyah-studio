import XCTest
@testable import DoyahCore

// 队列 `L-97` **第二片**（两层归属**落库 + 一次性迁移**）的机械证据。
//
// 这一片落的四件东西：① schema **v2**（`shelf` / `notebook` 两张表 + `note.notebook_uid` 补列）；
// ② 存量 v1 库**升得上来**（逐版 `ALTER`，不是「按最新版直接建」）；③ 缺归属的笔记**回填默认笔记本**；
// ④ 归属落库后**幂等**（再开一次库一个字节都不变）。
//
// 三条纪律：
//   ① **都跑真库文件**（临时目录，不用 `:memory:`）—— v1 → v2 那条升级路只在真文件上走得到；
//   ② **升级路径用手搭的 v1 库**：用当前代码建出来的库**永远是最新版**，测不到「老库升上来」，
//      而那正是这一片唯一有风险的路径；
//   ③ **幂等按数据对账**（uid / 条数 / 时间戳逐项比），不是「再调一次没抛异常」。
final class NotebookStorageTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("doyah-notebook-storage-\(UUID().uuidString)", isDirectory: true)
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
        updatedAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> Note {
        Note(
            id: UUID(),
            title: title,
            body: body,
            tags: tags,
            source: NoteSource(
                kind: .manual,
                connectionName: "连接甲",
                fingerprint: "fp-\(title)",
                capturedAt: Date(timeIntervalSince1970: 1_699_000_000)
            ),
            createdAt: Date(timeIntervalSince1970: 1_699_500_000),
            updatedAt: updatedAt,
            containsRowData: false
        )
    }

    /// 手搭一个 **v1 库** —— 存量用户的库长什么样：只有 v1 的 DDL、笔记行里**没有**归属列、
    /// `user_version = 1`。（`NoteSchemaV1.ddl` 保持 v1 形状正是为了这一条能成立。）
    private func makeVersionOneDatabase(notes: [Note]) throws {
        let connection = try SQLiteConnection(path: url().path)
        for statement in NoteSchemaV1.ddl { try connection.execute(statement) }
        for note in notes {
            try connection.execute(
                """
                INSERT INTO note (
                    uuid, title, body, source_kind, source_connection_name, source_fingerprint,
                    source_captured_at, created_at, updated_at, contains_row_data, storage_version
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                """,
                [
                    .text(note.id.uuidString),
                    .text(note.title),
                    .text(note.body),
                    .text(note.source.kind.rawValue),
                    note.source.connectionName.map { SQLiteValue.text($0) } ?? .null,
                    note.source.fingerprint.map { SQLiteValue.text($0) } ?? .null,
                    .real(note.source.capturedAt.timeIntervalSince1970),
                    .real(note.createdAt.timeIntervalSince1970),
                    .real(note.updatedAt.timeIntervalSince1970),
                    .integer(note.containsRowData ? 1 : 0),
                    .integer(Int64(NoteSchemaV1.version))
                ]
            )
            // 标签在 v1 里也是**另一张表**（`note_tag`）：fixture 必须一起写，
            // 否则「标签搬过来没有」这条判据在 fixture 这一步就已经是假的。
            if let rowID = try connection.scalarInt("SELECT id FROM note WHERE uuid = ?", [.text(note.id.uuidString)]) {
                for tag in note.tags {
                    try connection.execute(
                        "INSERT INTO note_tag (note_id, tag) VALUES (?, ?)",
                        [.integer(rowID), .text(tag)]
                    )
                }
            }
        }
        try connection.setPragma("user_version = \(NoteSchemaV1.version)")
        try connection.close()
    }

    // MARK: - ① 存量库升级（v1 → v2）

    /// 存量 v1 库打开后**升到 v2**，两张新表与补列都在，且笔记**一字不丢**。
    func testVersionOneDatabaseUpgradesToVersionTwoWithoutLosingNotes() throws {
        let note = sampleNote(title: "存量笔记", body: "洞庭湖", tags: ["骑行"])
        try makeVersionOneDatabase(notes: [note])

        let database = try makeDatabase()
        XCTAssertEqual(database.userVersion, NoteSchemaV3.version)
        let tables = try database.tableNames()
        for expected in NoteSchemaV2.tables {
            XCTAssertTrue(tables.contains(expected), "升级后缺表 \(expected)；实际：\(tables)")
        }
        // 补列真的在：这一句读的就是 `note.notebook_uid`（列不存在就抛）
        XCTAssertEqual(try database.unassignedNoteCount(), 1, "存量笔记此刻还没有归属")
        XCTAssertEqual(try database.noteCount(), 1)
        let restored = try XCTUnwrap(try database.notes().first)
        XCTAssertEqual(restored.id, note.id)
        XCTAssertEqual(restored.title, "存量笔记")
        XCTAssertEqual(restored.body, "洞庭湖")
        XCTAssertEqual(restored.tags, ["骑行"])
        XCTAssertEqual(restored.updatedAt, note.updatedAt)
    }

    /// 升级之后走一次**一次性迁移**：默认架 / 默认笔记本建出来，缺归属的笔记全部落进默认笔记本。
    func testUpgradeBackfillsEveryNoteIntoTheDefaultNotebook() throws {
        try makeVersionOneDatabase(notes: [sampleNote(title: "第一条"), sampleNote(title: "第二条")])

        let database = try makeDatabase()
        let directory = try database.ensureDefaultContainers(shelfName: "默认笔记本架", notebookName: "默认笔记本")

        XCTAssertEqual(directory.shelves.count, 1)
        XCTAssertEqual(directory.notebooks.count, 1)
        let shelf = try XCTUnwrap(directory.defaultShelf)
        let notebook = try XCTUnwrap(directory.defaultNotebook)
        XCTAssertTrue(shelf.isDefault)
        XCTAssertTrue(notebook.isDefault)
        XCTAssertEqual(notebook.shelfUid, shelf.uid, "笔记本必须挂在架上（不存在无归属笔记本）")
        XCTAssertEqual(notebook.name, "默认笔记本")
        XCTAssertEqual(shelf.name, "默认笔记本架")

        XCTAssertEqual(try database.unassignedNoteCount(), 0)
        let placements = try database.placements()
        XCTAssertEqual(placements.count, 2)
        XCTAssertTrue(
            placements.allSatisfy { $0.notebookUid == notebook.uid },
            "回填后每一条都该落在默认笔记本：\(placements.map(\.notebookUid))"
        )
        // 过滤那一半也认这条归属（不靠索引、逐条复核 —— 契约 §2.12 第 5 条）
        XCTAssertEqual(directory.notes(placements, inNotebook: notebook.uid).count, 2)
        XCTAssertEqual(directory.notes(placements, inShelf: shelf.uid).count, 2)
    }

    /// **幂等**：再调一次迁移，架 / 笔记本的 uid 与时间戳一字不变，笔记归属也不动。
    func testEnsureDefaultContainersIsIdempotent() throws {
        try makeVersionOneDatabase(notes: [sampleNote(title: "存量")])
        let database = try makeDatabase()
        let first = try database.ensureDefaultContainers(shelfName: "架", notebookName: "笔记本")

        let second = try database.ensureDefaultContainers(shelfName: "别的名字", notebookName: "别的名字")

        XCTAssertEqual(try database.shelves(), first.shelves, "第二次不该建第二条架、也不该改名")
        XCTAssertEqual(try database.notebooks(), first.notebooks)
        XCTAssertEqual(second.defaultNotebook?.uid, first.defaultNotebook?.uid)
        XCTAssertEqual(try database.unassignedNoteCount(), 0)
    }

    /// 新写的笔记**直接落默认笔记本**（不经过「先 NULL 再回填」—— 库里不留无归属的行）。
    func testNewNotesLandInTheDefaultNotebook() throws {
        let database = try makeDatabase()
        let directory = try database.ensureDefaultContainers(shelfName: "架", notebookName: "笔记本")
        let note = sampleNote(title: "新写的")
        try database.upsert(note)

        XCTAssertEqual(try database.notebookUid(of: note.id), directory.defaultNotebook?.uid)
        XCTAssertEqual(try database.unassignedNoteCount(), 0)
        // 再存一次（编辑正文）归属不动
        var edited = note
        edited.title = "改过标题"
        try database.upsert(edited)
        XCTAssertEqual(try database.notebookUid(of: note.id), directory.defaultNotebook?.uid)
    }

    // MARK: - ② 落库之后的读写

    /// 跨笔记本移动：归属变了、`updatedAt` **没变**（契约 §2.12 第 4 条）。
    func testMoveDoesNotRefreshUpdatedAt() throws {
        let database = try makeDatabase()
        let directory = try database.ensureDefaultContainers(shelfName: "架", notebookName: "笔记本")
        let shelfUid = try XCTUnwrap(directory.defaultShelf?.uid)
        let target = Notebook(shelfUid: shelfUid, name: "第二个笔记本", sortOrder: 1)
        try database.upsert(target)

        let note = sampleNote(title: "要搬家的", updatedAt: Date(timeIntervalSince1970: 1_650_000_000))
        try database.upsert(note)
        let before = try XCTUnwrap(try database.note(id: note.id)).updatedAt

        XCTAssertEqual(try database.move(noteIDs: [note.id], toNotebook: target.uid), 1)

        XCTAssertEqual(try database.notebookUid(of: note.id), target.uid)
        XCTAssertEqual(try XCTUnwrap(try database.note(id: note.id)).updatedAt, before, "移动不是一次内容更新")
    }

    /// 目标笔记本认不出（uid 是编的 / 已被删）⇒ **落默认笔记本**，不是「写进去一个悬空 uid」。
    func testUnknownTargetNotebookFallsBackToTheDefault() throws {
        let database = try makeDatabase()
        let directory = try database.ensureDefaultContainers(shelfName: "架", notebookName: "笔记本")
        let note = sampleNote(title: "兜底")
        try database.upsert(note)

        try database.move(noteIDs: [note.id], toNotebook: "不存在的笔记本")

        XCTAssertEqual(try database.notebookUid(of: note.id), directory.defaultNotebook?.uid)
        XCTAssertEqual(try database.unassignedNoteCount(), 0)
    }

    /// 笔记本必须挂在**存在**的架上（外键真的在拦 —— 这是「不存在无归属笔记本」的机器证据）。
    func testNotebookWithUnknownShelfIsRejected() throws {
        let database = try makeDatabase()
        try database.ensureDefaultContainers(shelfName: "架", notebookName: "笔记本")

        XCTAssertThrowsError(try database.upsert(Notebook(shelfUid: "不存在的架", name: "孤儿笔记本"))) { error in
            guard let failure = error as? SQLiteFailure else {
                return XCTFail("期望外键失败，实际：\(error)")
            }
            XCTAssertTrue(failure.isConstraintViolation, "应当是外键约束失败：\(failure.codeName)")
        }
    }

    /// 删笔记本**这一行**不会删掉里面的笔记（`note.notebook_uid` 刻意无外键 ⇒ 没有级联删除；
    /// 笔记的处置由 `ContainerRemovalPlan` 算，见 `Core/Notebook.swift`）。
    func testDeletingANotebookRowKeepsItsNotes() throws {
        let database = try makeDatabase()
        let directory = try database.ensureDefaultContainers(shelfName: "架", notebookName: "笔记本")
        let shelfUid = try XCTUnwrap(directory.defaultShelf?.uid)
        let doomed = Notebook(shelfUid: shelfUid, name: "要删的", sortOrder: 1)
        try database.upsert(doomed)
        let note = sampleNote(title: "不能跟着没")
        try database.upsert(note)
        try database.move(noteIDs: [note.id], toNotebook: doomed.uid)

        try database.deleteNotebook(uid: doomed.uid)

        XCTAssertEqual(try database.noteCount(), 1, "删笔记本不许把笔记一起带走")
        let placements = try database.placements()
        XCTAssertEqual(placements.count, 1)
        XCTAssertEqual(placements.first?.notebookUid, doomed.uid, "库里留的是原值；认不出由目录兜底")
        XCTAssertEqual(
            try database.notebookDirectory().resolvedNotebookUid(placements.first?.notebookUid),
            directory.defaultNotebook?.uid,
            "归属复核：指向已删笔记本的笔记算在默认笔记本里"
        )
    }

    /// 快照把归属一起带走（备份是真的备份 —— 恢复出来的库两层结构逐项相同）。
    func testSnapshotCarriesOwnership() throws {
        let database = try makeDatabase()
        let directory = try database.ensureDefaultContainers(shelfName: "架", notebookName: "笔记本")
        let shelfUid = try XCTUnwrap(directory.defaultShelf?.uid)
        let extra = Notebook(shelfUid: shelfUid, name: "另一个", sortOrder: 1)
        try database.upsert(extra)
        let note = sampleNote(title: "备份它")
        try database.upsert(note)
        try database.move(noteIDs: [note.id], toNotebook: extra.uid)

        let target = url("snapshots/notes-20261003T213000.sqlite3")
        let snapshot = try database.snapshot(to: target)
        XCTAssertEqual(snapshot.schemaVersion, NoteSchemaV3.version)

        let restored = try NoteDatabase(path: target.path)
        defer { try? restored.close() }
        XCTAssertEqual(try restored.shelves(), try database.shelves())
        XCTAssertEqual(try restored.notebooks(), try database.notebooks())
        XCTAssertEqual(try restored.placements(), try database.placements())
        XCTAssertEqual(try restored.unassignedNoteCount(), 0)
    }

    // MARK: - ④ 收藏（队列 `L-184` 第三片）

    /// **v1 存量库一路升到 v3**：补列之后老笔记一律「没收藏」（默认 0）；**收藏不刷新 `updatedAt`**；
    /// **编辑保存不清收藏**（`upsert` 的 `ON CONFLICT` 段刻意不碰这一列 —— 与 `notebook_uid` 同一条教训）。
    func testVersionOneDatabaseUpgradesToVersionThreeWithFavoritesOffByDefault() throws {
        let note = sampleNote(title: "存量笔记", body: "洞庭湖", tags: ["骑行"])
        try makeVersionOneDatabase(notes: [note])

        let database = try makeDatabase()
        XCTAssertEqual(database.userVersion, NoteSchemaV3.version, "v1 库要一路升到 v3")
        let restored = try XCTUnwrap(try database.note(id: note.id))
        XCTAssertFalse(restored.isFavorite, "存量笔记的语义就是「没收藏」—— 默认 0 是如实，不是填充")

        let before = restored.updatedAt
        XCTAssertEqual(try database.setFavorite(true, id: note.id), 1)
        let favorited = try XCTUnwrap(try database.note(id: note.id))
        XCTAssertTrue(favorited.isFavorite)
        XCTAssertEqual(favorited.updatedAt, before, "收藏是组织行为 —— 不许刷新 updated_at（否则列表次序整体错乱）")

        // **编辑保存不清收藏**：内存里故意写成「没收藏」，库里那份才是事实
        var edited = favorited
        edited.body = "改了几个字"
        edited.isFavorite = false
        try database.upsert(edited)
        let afterEdit = try XCTUnwrap(try database.note(id: note.id))
        XCTAssertEqual(afterEdit.body, "改了几个字")
        XCTAssertTrue(afterEdit.isFavorite, "改几个字保存不许把收藏静默抹掉")
        XCTAssertEqual(try database.isFavorite(id: note.id), true)
    }

    /// 收藏只改那一列；**认不出的 id ⇒ 0 行**（调用方据此如实交代，而不是假装改成了）。
    func testSetFavoriteReportsUnmatchedIdentifiersInsteadOfPretending() throws {
        let database = try makeDatabase()
        let note = sampleNote(title: "只有这一条")
        try database.upsert(note)
        XCTAssertEqual(try database.setFavorite(true, id: note.id), 1)
        XCTAssertEqual(try database.setFavorite(true, id: note.id), 1, "同值重写仍是命中一行（UPDATE 按 WHERE 命中计）")
        XCTAssertEqual(try database.setFavorite(false, id: UUID()), 0, "库里没有这个 id ⇒ 一行都不该被改")
        XCTAssertNil(try database.isFavorite(id: UUID()), "问一条不存在的笔记 ⇒ nil，不是 false")
        XCTAssertEqual(try database.noteCount(), 1)
    }

    // MARK: - ③ 门面（`NoteLibrary` actor）

    /// 界面 / CLI 走的那一层门面也要能用：`ensureOwnership` → `notebookDirectory` → `placements`。
    func testNoteLibraryFacadeExposesOwnership() async throws {
        try makeVersionOneDatabase(notes: [sampleNote(title: "门面")])
        let library = NoteLibrary(databaseURL: url())

        let directory = try await library.ensureOwnership(shelfName: "架", notebookName: "笔记本")

        XCTAssertEqual(directory.notebooks.count, 1)
        // `await` 不能写在 `XCTAssertEqual` 的 autoclosure 里 ⇒ 先把值取出来再断言。
        let shelves = try await library.notebookDirectory().shelves
        XCTAssertEqual(shelves.count, 1)
        let placements = try await library.placements()
        XCTAssertEqual(placements.count, 1)
        XCTAssertEqual(placements.first?.notebookUid, directory.defaultNotebook?.uid)
        let loaded = try await library.load()
        XCTAssertEqual(loaded.count, 1)
    }
}
