import XCTest
@testable import DoyahCore

// 队列 `L-97` **界面半第四片**（新建 / 重命名 / 排序）的**落库**证据。
//
// 这一片落的四件东西：① 新建笔记本（落进指定架 + 排序位按该架现算）；② 改名（架 / 笔记本，
// **默认容器也可改名**）；③ 排序一步（**整层重排**，含 `sort_order` 重号的历史数据）；④ 认不出的目标
// 一律 `nil` / `false` 且**库一个字节不动**（不能「点了没反应」变成「悄悄写到别处」）。
//
// 三条纪律（与 `NotebookStorageTests` 同一套）：
//   ① **跑真库文件**（临时目录）；② **重号档用手写 `sort_order` 造**（界面点出来的数据不会重号，
//   而存量库会）；③ 「没写库」按**数据对账**证明，不是「没抛异常」。
//
// 写法提醒：`XCTAssert*` 的参数是 autoclosure，**不许在里面 `await`** —— 先把结果取出来再断言。

final class NotebookEditStorageTests: XCTestCase {

    private var directory: URL!
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("doyah-notebook-edit-\(UUID().uuidString)", isDirectory: true)
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

    /// 种一个两层的库：架A（默认）里有笔记本A1（默认）/ 笔记本A2，架B 里有笔记本B1。
    @discardableResult
    private func seed() throws -> NoteDatabase {
        let database = try makeDatabase()
        try database.upsert(Shelf(uid: "shelf-a", name: "架A", sortOrder: 0, createdAt: t0, isDefault: true))
        try database.upsert(Shelf(uid: "shelf-b", name: "架B", sortOrder: 1, createdAt: t0, isDefault: false))
        try database.upsert(Notebook(uid: "nb-a1", shelfUid: "shelf-a", name: "笔记本A1", sortOrder: 0, createdAt: t0, isDefault: true))
        try database.upsert(Notebook(uid: "nb-a2", shelfUid: "shelf-a", name: "笔记本A2", sortOrder: 1, createdAt: t0))
        try database.upsert(Notebook(uid: "nb-b1", shelfUid: "shelf-b", name: "笔记本B1", sortOrder: 0, createdAt: t0))
        return database
    }

    // MARK: - ① 新建

    func testCreateNotebookLandsInTheShelfWithTheNextSortOrder() async throws {
        try seed()
        let library = makeLibrary()
        let created = try await library.createNotebook(inShelf: "shelf-b", name: "新本子")
        XCTAssertEqual(created?.shelfUid, "shelf-b")
        XCTAssertEqual(created?.sortOrder, 1, "排序位 = 该架内现有条数（架B 里先有 1 个）")
        XCTAssertEqual(created?.isDefault, false, "新建的永远不是默认笔记本")

        let after = try await library.notebookDirectory()
        XCTAssertEqual(after.notebooks(inShelf: "shelf-b").map(\.name), ["笔记本B1", "新本子"], "新的一条排在架里最后")
        XCTAssertEqual(after.notebooks(inShelf: "shelf-a").count, 2, "别的架一个字都不动")

        // 名字**原样落库**（洗净是调用方的事：Core 给规则、界面把洗净后的名字传下来）。
        XCTAssertEqual(after.notebook(uid: created!.uid)?.name, "新本子")
    }

    func testCreateNotebookRefusesAnUnknownShelfWithoutTouchingTheLibrary() async throws {
        try seed()
        let library = makeLibrary()
        let before = try await library.notebookDirectory()
        let created = try await library.createNotebook(inShelf: "gone", name: "无处安放")
        XCTAssertNil(created, "认不出的架 ⇒ 不兜底到默认架，如实说建不了")
        let after = try await library.notebookDirectory()
        XCTAssertEqual(after, before, "库一个字节不动")
    }

    func testCreateNotebookWithoutADatabaseCreatesNothing() async throws {
        let library = makeLibrary()
        let created = try await library.createNotebook(inShelf: "shelf-a", name: "还没库")
        XCTAssertNil(created, "库不存在时不该顺手建一个空库")
        XCTAssertFalse(FileManager.default.fileExists(atPath: databaseURL().path))
    }

    // MARK: - ② 重命名

    func testRenameShelfKeepsOrderAndDefaultFlag() async throws {
        try seed()
        let library = makeLibrary()
        let renamed = try await library.renameShelf(uid: "shelf-a", name: "  改名后的架  ")
        XCTAssertEqual(renamed?.name, "  改名后的架  ", "库这一层不做洗净 —— 传进来什么就落什么（洗净是 Core 规则的事）")

        let after = try await library.notebookDirectory()
        let shelf = after.shelf(uid: "shelf-a")
        XCTAssertEqual(shelf?.name, "  改名后的架  ")
        XCTAssertEqual(shelf?.sortOrder, 0, "改名**不许**顺手把排序位抹成别的数")
        XCTAssertEqual(shelf?.isDefault, true, "改名**不许**丢默认位")
        XCTAssertEqual(shelf?.createdAt, t0, "改名不动创建时刻")
        XCTAssertEqual(after.shelves.count, 2)
    }

    func testRenameTheDefaultNotebookIsAllowed() async throws {
        try seed()
        let library = makeLibrary()
        let renamed = try await library.renameNotebook(uid: "nb-a1", name: "默认也能改名")
        XCTAssertEqual(renamed?.name, "默认也能改名", "契约 §2.12 第 2 条：默认容器不可删、**可改名**")
        XCTAssertEqual(renamed?.isDefault, true)
        let after = try await library.notebookDirectory()
        XCTAssertEqual(after.notebook(uid: "nb-a1")?.shelfUid, "shelf-a", "改名不该把它挪到别的架")
        XCTAssertEqual(after.notebook(uid: "nb-a2")?.name, "笔记本A2", "同架的另一个一动不动")
    }

    func testRenameWithUnknownUIDChangesNothing() async throws {
        try seed()
        let library = makeLibrary()
        let before = try await library.notebookDirectory()
        let shelfResult = try await library.renameShelf(uid: "gone", name: "x")
        let notebookResult = try await library.renameNotebook(uid: "gone", name: "x")
        XCTAssertNil(shelfResult)
        XCTAssertNil(notebookResult)
        let after = try await library.notebookDirectory()
        XCTAssertEqual(after, before)
    }

    // MARK: - ③ 排序

    /// **重号档**：两条 `sort_order` 都是 1 时，「交换两个数」是空操作；
    /// 整层重排才真的把可见次序换过来（这是本片唯一一条**会悄悄失效**的路）。
    func testReorderMovesATiedNotebookUpOnTheVisibleOrder() async throws {
        let database = try seed()
        // 手写重号：架A 里再造一条 `sort_order = 1` 的笔记本 —— 与 nb-a2 同号（存量库的样子）。
        try database.upsert(
            Notebook(uid: "nb-a3", shelfUid: "shelf-a", name: "笔记本A3", sortOrder: 1, createdAt: t0.addingTimeInterval(5))
        )
        let before = try database.notebookDirectory()
        XCTAssertEqual(before.notebook(uid: "nb-a2")?.sortOrder, before.notebook(uid: "nb-a3")?.sortOrder, "确认起点真的是重号")
        XCTAssertEqual(before.notebooks(inShelf: "shelf-a").map(\.uid), ["nb-a1", "nb-a2", "nb-a3"], "重号时可见次序靠创建时刻兜底")

        let library = makeLibrary()
        let moved = try await library.reorder(kind: .notebook, containerUid: "nb-a3", direction: .up)
        XCTAssertTrue(moved)

        let after = try await library.notebookDirectory()
        XCTAssertEqual(after.notebooks(inShelf: "shelf-a").map(\.uid), ["nb-a1", "nb-a3", "nb-a2"], "上移一步真的换了次序")
        XCTAssertEqual(after.notebooks(inShelf: "shelf-a").map(\.sortOrder), [0, 1, 2], "整层重写成 0..<n（重号被顺手归一）")
        XCTAssertEqual(after.notebooks(inShelf: "shelf-b").map(\.uid), ["nb-b1"], "另一个架一个字都不动")
    }

    func testReorderAtTheEdgeReturnsFalseAndWritesNothing() async throws {
        try seed()
        let library = makeLibrary()
        let before = try await library.notebookDirectory()
        let topUp = try await library.reorder(kind: .notebook, containerUid: "nb-a1", direction: .up)
        let bottomDown = try await library.reorder(kind: .notebook, containerUid: "nb-a2", direction: .down)
        let shelfUp = try await library.reorder(kind: .shelf, containerUid: "shelf-a", direction: .up)
        let ghost = try await library.reorder(kind: .notebook, containerUid: "gone", direction: .up)
        XCTAssertFalse(topUp, "已经在最前")
        XCTAssertFalse(bottomDown, "已经在最后")
        XCTAssertFalse(shelfUp, "架上同理")
        XCTAssertFalse(ghost, "认不出的 uid")
        let after = try await library.notebookDirectory()
        XCTAssertEqual(after, before, "四条都不许写库")
    }

    func testShelfReorderSwapsTheTwoShelves() async throws {
        try seed()
        let library = makeLibrary()
        let moved = try await library.reorder(kind: .shelf, containerUid: "shelf-b", direction: .up)
        XCTAssertTrue(moved)
        let after = try await library.notebookDirectory()
        XCTAssertEqual(after.sortedShelves.map(\.uid), ["shelf-b", "shelf-a"], "架层换过来了")
        XCTAssertEqual(after.notebooks(inShelf: "shelf-a").map(\.uid), ["nb-a1", "nb-a2"], "架换了位置，里面的笔记本不动")
    }

    func testReorderWithoutADatabaseWritesNothing() async throws {
        let library = makeLibrary()
        let moved = try await library.reorder(kind: .shelf, containerUid: "shelf-a", direction: .up)
        XCTAssertFalse(moved)
        XCTAssertFalse(FileManager.default.fileExists(atPath: databaseURL().path))
    }
}
