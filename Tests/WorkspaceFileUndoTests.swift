import XCTest
@testable import DoyahCore

/// 文件操作的一次撤销 + 改名后页签跟随（`FR-STD-WS-FS-004` ③ / `FR-STD-WS-FS-005` ①②③ / `FR-STD-WS-FS-006` ③）。
///
/// 为什么用**真文件系统**：撤销三条路全都落到盘上（搬回废纸篓、搬回来、改回去），
/// 「废纸篓里那份还在不在」「原位置有没有被占」都是环境事实，桩替不了。
final class WorkspaceFileUndoTests: XCTestCase {

    private var sandbox: URL!
    private var workspace: URL!
    private var other: URL!

    override func setUpWithError() throws {
        sandbox = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("doyah-undo-\(UUID().uuidString)")
        workspace = sandbox.appendingPathComponent("ws")
        other = sandbox.appendingPathComponent("other")
        for url in [workspace!, other!] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: sandbox)
    }

    private func makeFile(_ name: String, in directory: URL, contents: String = "x") throws -> URL {
        let url = directory.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// 判据自己收拾废纸篓，不给用户留垃圾。
    private func cleanUpTrash(_ url: URL?) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: 撤销「新建」：再移进废纸篓（不是抹掉）

    func testUndoingACreationMovesItToTheTrashInsteadOfErasingIt() throws {
        let created = try WorkspaceFileOperations.createFile(
            baseName: "Untitled", fileExtension: "txt", in: workspace, workspaceURL: workspace
        )
        let undo = WorkspaceFileUndo.creation(created: created, workspace: workspace)

        let landed = try WorkspaceUndoLog.revert(undo)

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: created.path),
            "撤销「新建」之后原位置必须没了"
        )
        let trashed = try XCTUnwrap(landed, "撤销「新建」要把废纸篓位置交回来，否则这个动作自己不可恢复")
        XCTAssertTrue(FileManager.default.fileExists(atPath: trashed.path), "废纸篓里必须真的有一份")
        XCTAssertFalse(
            WorkspaceTree.isContained(trashed.path, in: workspace.path),
            "那一份应当在废纸篓里（工作区之外），不是被顺手删掉"
        )
        cleanUpTrash(trashed)
    }

    // MARK: 撤销「删除」：从废纸篓搬回来

    func testUndoingADeletionBringsTheFileBackWithItsContents() throws {
        let file = try makeFile("notes.md", in: workspace, contents: "body")
        let trashed = try WorkspaceFileOperations.delete(file, in: workspace)
        let undo = WorkspaceFileUndo.deletion(original: file, trashedTo: trashed, workspace: workspace)

        let landed = try WorkspaceUndoLog.revert(undo)

        XCTAssertEqual(landed?.standardizedFileURL.path, file.standardizedFileURL.path, "必须回到原处")
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "body", "内容一个字都不许变")
        if let trashed {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: trashed.path),
                "搬回来之后废纸篓里不该再留一份（否则下一次撤销会撞名）"
            )
        }
    }

    func testUndoingADeletionRefusesWhenTheTrashCopyIsGone() throws {
        let file = try makeFile("gone.txt", in: workspace, contents: "body")
        let trashed = try WorkspaceFileOperations.delete(file, in: workspace)
        if let trashed { try FileManager.default.removeItem(at: trashed) }  // 用户清过废纸篓

        let undo = WorkspaceFileUndo.deletion(original: file, trashedTo: trashed, workspace: workspace)
        XCTAssertThrowsError(try WorkspaceUndoLog.revert(undo)) { error in
            XCTAssertEqual(
                error as? WorkspaceFileOperations.Failure,
                .trashCopyMissing(file.lastPathComponent),
                "废纸篓副本没了要如实说做不到 —— 不许拿别的同名文件顶上"
            )
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "做不到就不许凭空造一个空文件")
    }

    func testUndoingADeletionRefusesWhenTheOriginalNameIsTaken() throws {
        let file = try makeFile("dup.txt", in: workspace, contents: "old")
        let trashed = try WorkspaceFileOperations.delete(file, in: workspace)
        let recreated = try makeFile("dup.txt", in: workspace, contents: "new")

        let undo = WorkspaceFileUndo.deletion(original: file, trashedTo: trashed, workspace: workspace)
        XCTAssertThrowsError(try WorkspaceUndoLog.revert(undo)) { error in
            XCTAssertEqual(
                error as? WorkspaceFileOperations.Failure,
                .alreadyExists("dup.txt"),
                "原位置被占了要拒绝 —— 覆盖掉的是用户后来新建的那份"
            )
        }
        XCTAssertEqual(try String(contentsOf: recreated, encoding: .utf8), "new", "后来那份一个字节都不许动")
        cleanUpTrash(trashed)
    }

    func testUndoingAFolderDeletionRestoresTheWholeSubtree() throws {
        let folder = try WorkspaceFileOperations.createDirectory(
            baseName: "docs", in: workspace, workspaceURL: workspace
        )
        let inner = folder.appendingPathComponent("deep")
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: false)
        _ = try makeFile("a.md", in: folder, contents: "A")
        _ = try makeFile("b.md", in: inner, contents: "B")

        let trashed = try WorkspaceFileOperations.delete(folder, in: workspace)
        let undo = WorkspaceFileUndo.deletion(original: folder, trashedTo: trashed, workspace: workspace)
        _ = try WorkspaceUndoLog.revert(undo)

        XCTAssertEqual(
            try String(contentsOf: folder.appendingPathComponent("a.md"), encoding: .utf8), "A"
        )
        XCTAssertEqual(
            try String(contentsOf: inner.appendingPathComponent("b.md"), encoding: .utf8), "B",
            "整棵子树都要回来（只搬回目录壳 = 把用户的东西丢了）"
        )
    }

    // MARK: 撤销「改名」

    func testUndoingARenamePutsTheOriginalNameBack() throws {
        let original = try makeFile("before.txt", in: workspace, contents: "body")
        let renamed = try WorkspaceFileOperations.rename(original, to: "after.txt", in: workspace)
        let undo = WorkspaceFileUndo.rename(from: original, to: renamed, workspace: workspace)

        let landed = try WorkspaceUndoLog.revert(undo)

        XCTAssertEqual(landed?.lastPathComponent, "before.txt")
        XCTAssertEqual(try String(contentsOf: original, encoding: .utf8), "body")
        XCTAssertFalse(FileManager.default.fileExists(atPath: renamed.path), "改名后的那个名字不该还留着")
    }

    func testUndoingARenameRefusesWhenTheOldNameCameBack() throws {
        let original = try makeFile("taken.txt", in: workspace, contents: "old")
        let renamed = try WorkspaceFileOperations.rename(original, to: "renamed.txt", in: workspace)
        _ = try makeFile("taken.txt", in: workspace, contents: "squatter")

        let undo = WorkspaceFileUndo.rename(from: original, to: renamed, workspace: workspace)
        XCTAssertThrowsError(try WorkspaceUndoLog.revert(undo)) { error in
            XCTAssertEqual(error as? WorkspaceFileOperations.Failure, .alreadyExists("taken.txt"))
        }
        XCTAssertEqual(
            try String(contentsOf: renamed, encoding: .utf8), "old",
            "拒绝之后被改名的那个文件必须还在原处（不许半搬运）"
        )
    }

    // MARK: 一次撤销的语义

    func testUndoLogKeepsOnlyTheMostRecentOperation() {
        let a = URL(fileURLWithPath: "/ws/a.txt")
        let b = URL(fileURLWithPath: "/ws/b.txt")
        var log = WorkspaceUndoLog()
        XCTAssertFalse(log.canUndo, "没做过操作时不该有撤销")

        log.record(.creation(created: a, workspace: URL(fileURLWithPath: "/ws")))
        log.record(.rename(from: a, to: b, workspace: URL(fileURLWithPath: "/ws")))
        XCTAssertEqual(log.pending?.kind, .rename, "只认最近那一次（「一次撤销」不是撤销栈）")

        XCTAssertEqual(log.consume()?.kind, .rename)
        XCTAssertFalse(log.canUndo, "撤过一次就没有第二次（没有重做栈）")
        XCTAssertNil(log.consume(), "再取一次必须什么都没有")
    }

    func testRecordingNothingClearsThePreviousEntry() {
        var log = WorkspaceUndoLog()
        log.record(.creation(created: URL(fileURLWithPath: "/ws/a.txt"), workspace: URL(fileURLWithPath: "/ws")))
        // 「点开改名又原样提交」= 这次什么都没变 ⇒ 记 nil，顺手把上一条清掉
        // （否则界面上的撤销会去撤一件更早的事，而用户以为它撤的是刚才那一下）。
        log.record(nil)
        XCTAssertFalse(log.canUndo)
    }

    func testUndoEntryIsBoundToItsOwnWorkspace() throws {
        let file = try makeFile("inside.txt", in: workspace, contents: "body")
        // 拿「另一个工作区」去撤同一份东西：必须被越界检查拦下，文件原样不动。
        let crossed = WorkspaceFileUndo.creation(created: file, workspace: other)
        XCTAssertThrowsError(try WorkspaceUndoLog.revert(crossed)) { error in
            XCTAssertEqual(error as? WorkspaceFileOperations.Failure, .notContained)
        }
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "body", "撤不动就一个字节都不许动")
    }

    // MARK: 改名后页签跟随（纯函数）

    func testRetargetedPathMovesOnlyTheRenamedSubtree() {
        // 自己
        XCTAssertEqual(
            WorkspaceTabSet.retargetedPath("/ws/a.txt", from: "/ws/a.txt", to: "/ws/b.txt"), "/ws/b.txt"
        )
        // 子树（目录改名）
        XCTAssertEqual(
            WorkspaceTabSet.retargetedPath("/ws/dir/x/y.swift", from: "/ws/dir", to: "/ws/docs"),
            "/ws/docs/x/y.swift"
        )
        // **差一个字符的兄弟不许被误伤**（`a.txt2` 不是 `a.txt` 的孩子）
        XCTAssertNil(WorkspaceTabSet.retargetedPath("/ws/a.txt2", from: "/ws/a.txt", to: "/ws/b.txt"))
        // 不相干的
        XCTAssertNil(WorkspaceTabSet.retargetedPath("/ws/other.swift", from: "/ws/dir", to: "/ws/docs"))
        // 前缀相同但不同目录（`/ws/dir2` 不是 `/ws/dir` 的子树）
        XCTAssertNil(WorkspaceTabSet.retargetedPath("/ws/dir2/z", from: "/ws/dir", to: "/ws/docs"))
    }

    func testRenamingADirectoryRetargetsEveryTabUnderItAndKeepsDirtyContent() {
        let home = WorkspaceTab.home(title: "Home")
        let under = WorkspaceTab.file(path: "/ws/dir/x/one.swift", content: "let a = 1")
        var dirty = WorkspaceTab.file(path: "/ws/dir/two.md", content: "edited")
        dirty.content = "edited twice"     // 未保存的改动（脏页签）
        let sibling = WorkspaceTab.file(path: "/ws/dir2/three.swift", content: "")
        let chat = WorkspaceTab.agentChat(title: "对话")
        let tabs = [home, under, dirty, sibling, chat]

        let retargeted = WorkspaceTabSet.retargeting(tabs: tabs, from: "/ws/dir", to: "/ws/docs")

        XCTAssertEqual(retargeted.count, tabs.count, "改名不该多一个或少一个页签")
        XCTAssertEqual(retargeted[1].path, "/ws/docs/x/one.swift")
        XCTAssertEqual(retargeted[1].title, "one.swift")
        XCTAssertEqual(retargeted[2].path, "/ws/docs/two.md")
        XCTAssertEqual(retargeted[2].content, "edited twice", "页签里没保存的字一个字都不许动")
        XCTAssertTrue(retargeted[2].isDirty, "脏标记必须跟着（否则关页签时不再提醒保存）")
        XCTAssertEqual(retargeted[0], home, "Home 页不受影响")
        XCTAssertEqual(retargeted[3].path, "/ws/dir2/three.swift", "`dir2` 不是 `dir` 的子树")
        XCTAssertEqual(retargeted[4], chat, "对话页签不受影响")
        // 标识必须原样：重发 id 等于「关掉旧的再开新的」，选中项与撤销栈都会断。
        XCTAssertEqual(retargeted.map(\.id), tabs.map(\.id))
    }

    // MARK: 接线（源码锚点：Core 有代码不等于界面上点得到）

    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testStoreRecordsUndoForAllThreeOperations() throws {
        let store = try source("App/WorkspaceStore.swift")
        XCTAssertTrue(store.contains("undoLog.record(.creation(created:"), "新建没有记账 ⇒ 新建撤不回来")
        XCTAssertTrue(store.contains("undoLog.record(.rename(from:"), "改名没有记账 ⇒ 改名撤不回来")
        XCTAssertTrue(store.contains("undoLog.record(.deletion(original:"), "删除没有记账 ⇒ 删除撤不回来")
        XCTAssertTrue(store.contains("undoLog.consume()"), "撤销成功之后没有把账清掉 ⇒ 能反复撤，第二次会撤到更早那件事")
        XCTAssertTrue(
            store.contains("try WorkspaceUndoLog.revert(entry)"),
            "撤销必须真的调 Core 的 revert（自己再写一遍搬运 = 两套语义）"
        )
    }

    func testExplorerWiresAutoOpenTabFollowAndUndoButton() throws {
        let view = try source("App/Views/WorkspaceExplorerView.swift")
        XCTAssertTrue(
            view.contains("workspaceTabs.openFile(at: created, line: 1)"),
            "新建文件之后没有自动打开 + 光标首行（`FR-STD-WS-FS-004` ③）"
        )
        XCTAssertTrue(
            view.contains("workspaceTabs.retarget(from: source.path, to: renamed.path)"),
            "改名之后页签没有跟着改（`FR-STD-WS-FS-005` ①）"
        )
        XCTAssertTrue(
            view.contains("workspace.undoLastFileOperation()"),
            "界面上没有撤销入口（判据过了但用户点不到 = 没做）"
        )
        XCTAssertTrue(
            view.contains("workspaceTabs.closeTabs(atPath: undone.currentURL.path)"),
            "撤销「新建」之后没有收掉指向废纸篓的页签"
        )
        XCTAssertTrue(
            view.contains("if workspace.canUndoFileOperation {"),
            "撤销按钮必须只在有账时出现（常驻一个灰按钮等于让用户每次猜为什么点不动）"
        )
        XCTAssertTrue(
            view.contains("accessibilityIdentifier(\"workspace-undo\")"),
            "撤销按钮没有可定位标识 ⇒ 仪器与无障碍都够不着它"
        )
    }
}
