import XCTest
@testable import DoyahCore

// 队列 `L-97` **界面半第六片**（跨架移动）的**落库**证据。
//
// 这一片落的四件东西：① 挪架只改 `shelf_uid` + 排序位（**顺延到目标架现有条数之后**，不重号）；
// ② 迁 `created_at` / `is_default` **原样带回**（挪架不是改名、也不是删 —— 契约 §2.12 第 2 条）；
// ③ 里面的笔记**一条都不动**（笔记跟着自己的笔记本走 ⇒ 归属对逐条不变）；
// ④ 认不出的笔记本 / 认不出的目标架 / 已经在该架 ⇒ `nil` 且**库一个字节不动**。
//
// 三条纪律（与 `NotebookStorageTests` / `NotebookEditStorageTests` 同一套）：
//   ① **跑真库文件**（临时目录，不用 `:memory:`）；
//   ② 「没写库」按**数据对账**证明（目录逐项相等 + 笔记条数），不是「没抛异常」；
//   ③ 写法提醒：`XCTAssert*` 的参数是 autoclosure，**不许在里面 `await`** —— 先取结果再断言。

final class NotebookShelfMoveStorageTests: XCTestCase {

    private var directory: URL!
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("doyah-notebook-shelf-move-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    private func databaseURL() -> URL {
        directory.appendingPathComponent(NoteDatabase.fileName, isDirectory: false)
    }

    private func makeDatabase() throws -> NoteDatabase {
        try NoteDatabase(path: databaseURL().path)
    }

    private func makeLibrary() -> NoteLibrary {
        NoteLibrary(databaseURL: databaseURL())
    }

    /// 种一个两层的库：架A（默认）里有笔记本A1（默认），架B 里已有两条笔记本（B1 / B2）。
    /// 架B 里**已有两条**是有意的 —— 「排序位顺延到现有条数之后」这条只有目标架非空前才判得出来。
    @discardableResult
    private func seed() throws -> NoteDatabase {
        let database = try makeDatabase()
        try database.upsert(Shelf(uid: "shelf-a", name: "架A", sortOrder: 0, createdAt: t0, isDefault: true))
        try database.upsert(Shelf(uid: "shelf-b", name: "架B", sortOrder: 1, createdAt: t0, isDefault: false))
        try database.upsert(Notebook(uid: "nb-a1", shelfUid: "shelf-a", name: "笔记本A1", sortOrder: 0, createdAt: t0, isDefault: true))
        try database.upsert(Notebook(uid: "nb-a2", shelfUid: "shelf-a", name: "笔记本A2", sortOrder: 1, createdAt: t0))
        try database.upsert(Notebook(uid: "nb-b1", shelfUid: "shelf-b", name: "笔记本B1", sortOrder: 0, createdAt: t0))
        try database.upsert(Notebook(uid: "nb-b2", shelfUid: "shelf-b", name: "笔记本B2", sortOrder: 1, createdAt: t0))
        return database
    }

    private func sampleNote(title: String) -> Note {
        Note(
            id: UUID(),
            title: title,
            body: "",
            tags: [],
            source: NoteSource(
                kind: .manual,
                connectionName: "连接甲",
                fingerprint: "fp-\(title)",
                capturedAt: t0
            ),
            createdAt: t0,
            updatedAt: t0,
            containsRowData: false
        )
    }

    // MARK: - ① 挪架：改归属 + 排序位顺延

    func testMoveNotebookChangesShelfAndAppendsSortOrder() async throws {
        try seed()
        let library = makeLibrary()
        let moved = try await library.moveNotebook(uid: "nb-a2", toShelf: "shelf-b")
        XCTAssertEqual(moved?.shelfUid, "shelf-b", "挪架就是改 `shelf_uid`")
        XCTAssertEqual(moved?.sortOrder, 2, "排序位**顺延到目标架现有条数之后**（架B 已有两条 ⇒ 这一条是 2）")
        XCTAssertEqual(moved?.isDefault, false, "非默认笔记本挪完还是非默认")
        XCTAssertEqual(moved?.createdAt, t0, "创建时刻是事实，挪架不许改写它")

        let directory = try await library.notebookDirectory()
        XCTAssertEqual(directory.notebooks(inShelf: "shelf-b").map(\.uid), ["nb-b1", "nb-b2", "nb-a2"], "在目标架里排在末尾")
        XCTAssertEqual(directory.notebooks(inShelf: "shelf-a").map(\.uid), ["nb-a1"], "原架里少了一条")
    }

    /// 默认笔记本**可以挪架** —— 契约 §2.12 第 2 条只禁「删」（改名同族：也不禁）。
    func testDefaultNotebookMayMoveAndStaysDefault() async throws {
        try seed()
        let library = makeLibrary()
        let moved = try await library.moveNotebook(uid: "nb-a1", toShelf: "shelf-b")
        XCTAssertEqual(moved?.shelfUid, "shelf-b", "默认笔记本挪到别的架是允许的")
        XCTAssertEqual(moved?.isDefault, true, "`is_default` 原样带回（挪架不该把它抹掉）")
        let directory = try await library.notebookDirectory()
        XCTAssertEqual(directory.notebook(uid: "nb-a1")?.isDefault, true, "库里读回来也还是默认那一条")
    }

    /// 里面的笔记**一条都不动**：归属对逐条不变（笔记跟着自己的笔记本走）。
    func testNotesKeepTheirNotebookPlacement() async throws {
        let database = try seed()
        let one = sampleNote(title: "第一条")
        let two = sampleNote(title: "第二条")
        try database.upsert(one)
        try database.upsert(two)
        try database.move(noteIDs: [one.id], toNotebook: "nb-a2")
        let before = try database.placements()
        XCTAssertEqual(before.count, 2)

        let library = makeLibrary()
        _ = try await library.moveNotebook(uid: "nb-a2", toShelf: "shelf-b")

        let reopened = try makeDatabase()
        let after = try reopened.placements().sorted { $0.noteID < $1.noteID }
        XCTAssertEqual(
            after,
            before.sorted { $0.noteID < $1.noteID },
            "挪的是笔记本，笔记的 `notebook_uid` 一个字节都不许动"
        )
    }

    // MARK: - ② 三处越界都不写库

    func testNoOpCasesLeaveTheDatabaseUntouched() async throws {
        let database = try seed()
        let before = try database.notebookDirectory()
        let library = makeLibrary()

        let current = try await library.moveNotebook(uid: "nb-b1", toShelf: "shelf-b")
        XCTAssertNil(current, "已经在该架 ⇒ `nil`（空操作）")
        let unknownTarget = try await library.moveNotebook(uid: "nb-b1", toShelf: "shelf-nope")
        XCTAssertNil(unknownTarget, "认不出的目标架 ⇒ `nil`（**不兜底到默认架**）")
        let unknownNotebook = try await library.moveNotebook(uid: "nb-nope", toShelf: "shelf-a")
        XCTAssertNil(unknownNotebook, "认不出的笔记本 ⇒ `nil`")

        let after = try database.notebookDirectory()
        XCTAssertEqual(after, before, "三条越界路径**库一个字节都不动**（按目录逐项对账）")
    }

    /// 没有库文件时也走同一条：`nil`、不建库（不许「点了没反应」变成「悄悄建一个库」）。
    func testMissingDatabaseIsNotCreated() async throws {
        let library = makeLibrary()
        let moved = try await library.moveNotebook(uid: "nb-a1", toShelf: "shelf-b")
        XCTAssertNil(moved, "没有库 ⇒ `nil`")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: databaseURL().path),
            "不因为一次挪架就凭空建出库文件"
        )
    }
}
