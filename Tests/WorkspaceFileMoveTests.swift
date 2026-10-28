import XCTest
@testable import DoyahCore

/// 拖拽移动的判据（`FR-STD-WS-FS-003` 的「拖拽移动」那一条）。
///
/// 分两半，缺一不可：
///   ① **几何判定**（`WorkspaceFileMove.placement`）—— 界面靠它决定「这一行接不接」，
///      判据钉住「根不搬 / 不搬进自己里面 / 同一层不动 / 兄弟目录名字前缀不误伤」；
///   ② **真搬**（`WorkspaceFileOperations.move`）—— 在真文件系统上跑：搬完源处不在、落点内容一字不差；
///      撞名 / 落点不是目录 / 越界 / 搬根 四档都必须拒且**源不动**。
///
/// 为什么两半要一起判：只判几何会放过「界面接了但盘上没动」，只判真搬会放过
/// 「盘上能搬但界面永远不接」—— 那种缺陷在界面上表现为「拖了没反应」，最难查。
final class WorkspaceFileMoveTests: XCTestCase {

    private var sandbox: URL!
    private var workspace: URL!

    override func setUpWithError() throws {
        sandbox = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("doyah-move-\(UUID().uuidString)")
        workspace = sandbox.appendingPathComponent("ws")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: sandbox)
    }

    private func makeDirectory(_ relative: String) throws -> URL {
        let url = workspace.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeFile(_ relative: String, contents: String = "x") throws -> URL {
        let url = workspace.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - ① 几何判定（界面这一半的同一份口径）

    func testPlacementMovesIntoAnotherDirectory() {
        XCTAssertEqual(
            WorkspaceFileMove.placement(source: "src/a.txt", into: "src/dest"),
            .move(to: "src/dest/a.txt")
        )
        XCTAssertEqual(
            WorkspaceFileMove.placement(source: "a.txt", into: "deep/nested/dir"),
            .move(to: "deep/nested/dir/a.txt"),
            "顶层的条目也要能拖进任意深的目录"
        )
    }

    func testPlacementIsNoopInTheSameDirectory() {
        XCTAssertEqual(WorkspaceFileMove.placement(source: "src/a.txt", into: "src"), .noop)
        XCTAssertEqual(WorkspaceFileMove.placement(source: "a.txt", into: ""), .noop, "拖回根 = 本来就在根")
    }

    func testPlacementRefusesTheWorkspaceRoot() {
        XCTAssertEqual(WorkspaceFileMove.placement(source: "", into: "src"), .refused(.rootNotMovable))
        XCTAssertEqual(WorkspaceFileMove.placement(source: "", into: ""), .refused(.rootNotMovable))
    }

    func testPlacementRefusesItsOwnSubtree() {
        XCTAssertEqual(
            WorkspaceFileMove.placement(source: "src", into: "src/dist"),
            .refused(.intoOwnSubtree),
            "目录搬进自己子树里：搬完 `src` 就没了，底下的东西跟着一起消失"
        )
        XCTAssertEqual(
            WorkspaceFileMove.placement(source: "src", into: "src"),
            .refused(.intoOwnSubtree),
            "落在自己身上也不是「同一层不用动」—— 它是自己"
        )
    }

    func testPlacementDoesNotConfuseSiblingNamePrefixes() {
        // `ab` 不是 `a` 的子树（字符串前缀下会被判成一家人），所以这里必须是「搬得进去」。
        XCTAssertEqual(WorkspaceFileMove.placement(source: "a", into: "ab"), .move(to: "ab/a"))
        XCTAssertEqual(WorkspaceFileMove.placement(source: "ab", into: "a"), .move(to: "a/ab"))
    }

    // MARK: - ② 真搬

    func testMoveMovesTheFileAndKeepsItsContents() throws {
        let source = try makeFile("src/report.md", contents: "hello")
        let destination = try makeDirectory("dest")

        let moved = try WorkspaceFileOperations.move(source, into: destination, in: workspace)

        XCTAssertEqual(moved.path, destination.appendingPathComponent("report.md").path)
        XCTAssertEqual(try String(contentsOf: moved, encoding: .utf8), "hello", "搬不是复制：内容一字不差")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: source.path),
            "源处必须不再有它 —— 两边都留一份等于静默复制"
        )
    }

    func testMoveMovesADirectoryWithItsContents() throws {
        let folder = try makeDirectory("src/kit")
        _ = try makeFile("src/kit/inner.txt", contents: "inner")
        let destination = try makeDirectory("dest")

        let moved = try WorkspaceFileOperations.move(folder, into: destination, in: workspace)

        XCTAssertEqual(moved.lastPathComponent, "kit")
        XCTAssertEqual(
            try String(contentsOf: moved.appendingPathComponent("inner.txt"), encoding: .utf8),
            "inner"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }

    func testMoveRefusesAnExistingNameAndLeavesBothSidesAlone() throws {
        let source = try makeFile("src/a.txt", contents: "mine")
        let destination = try makeDirectory("dest")
        _ = try makeFile("dest/a.txt", contents: "theirs")

        XCTAssertThrowsError(try WorkspaceFileOperations.move(source, into: destination, in: workspace)) { error in
            XCTAssertEqual(error as? WorkspaceFileOperations.Failure, .alreadyExists("a.txt"))
        }
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "mine", "源不动")
        XCTAssertEqual(
            try String(contentsOf: destination.appendingPathComponent("a.txt"), encoding: .utf8),
            "theirs",
            "落点那一份不许被覆盖"
        )
    }

    func testMoveRefusesItsOwnSubtreeOnDisk() throws {
        let folder = try makeDirectory("src/kit")
        _ = try makeFile("src/kit/inner.txt", contents: "inner")
        let ownChild = try makeDirectory("src/kit/dist")

        XCTAssertThrowsError(try WorkspaceFileOperations.move(folder, into: ownChild, in: workspace)) { error in
            XCTAssertEqual(error as? WorkspaceFileOperations.Failure, .intoOwnSubtree("kit"))
        }
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: folder.appendingPathComponent("inner.txt").path),
            "拒掉之后源目录必须原样在（这一条是防「先搬走再发现不对」）"
        )
    }

    func testMoveInTheSameDirectoryChangesNothing() throws {
        let source = try makeFile("src/a.txt", contents: "x")
        let sameParent = try makeDirectory("src")

        let moved = try WorkspaceFileOperations.move(source, into: sameParent, in: workspace)

        XCTAssertEqual(moved.standardizedFileURL, source.standardizedFileURL, "同一层：返回原 URL，什么都不做")
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "x")
    }

    func testMoveRefusesTheWorkspaceRoot() throws {
        let destination = try makeDirectory("dest")
        XCTAssertThrowsError(try WorkspaceFileOperations.move(workspace, into: destination, in: workspace)) { error in
            XCTAssertEqual(error as? WorkspaceFileOperations.Failure, .rootNotMovable)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.path))
    }

    func testMoveRefusesADestinationOutsideTheWorkspace() throws {
        let source = try makeFile("src/a.txt")
        let outside = sandbox.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)

        XCTAssertThrowsError(try WorkspaceFileOperations.move(source, into: outside, in: workspace)) { error in
            XCTAssertEqual(error as? WorkspaceFileOperations.Failure, .notContained)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), "越界拒掉时源必须还在原处")
    }

    func testMoveRefusesADestinationThatIsAFile() throws {
        let source = try makeFile("src/a.txt")
        let file = try makeFile("dest/b.txt")

        XCTAssertThrowsError(try WorkspaceFileOperations.move(source, into: file, in: workspace)) { error in
            XCTAssertEqual(error as? WorkspaceFileOperations.Failure, .notADirectory("b.txt"))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testMoveIsUndoableInOneStep() throws {
        let source = try makeFile("src/a.txt", contents: "x")
        let destination = try makeDirectory("dest")
        let moved = try WorkspaceFileOperations.move(source, into: destination, in: workspace)

        let undone = try WorkspaceUndoLog.revert(.move(from: source, to: moved, workspace: workspace))

        XCTAssertEqual(undone?.standardizedFileURL, source.standardizedFileURL, "撤销 = 搬回原目录")
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "x")
        XCTAssertFalse(FileManager.default.fileExists(atPath: moved.path))
    }

    /// 撤销账的 `kind` / 两个 URL 对新的那一档要如实 —— 界面靠 `kind` 选句子、靠 URL 收页签。
    func testMoveUndoEntryReportsItsEndpoints() throws {
        let from = workspace.appendingPathComponent("src/a.txt")
        let to = workspace.appendingPathComponent("dest/a.txt")
        let entry = WorkspaceFileUndo.move(from: from, to: to, workspace: workspace)

        XCTAssertEqual(entry.kind, .move)
        XCTAssertEqual(entry.originalURL, from)
        XCTAssertEqual(entry.currentURL, to)
        XCTAssertEqual(entry.workspaceURL, workspace)
        XCTAssertEqual(WorkspaceFileUndo.Kind.allCases.count, 4)
    }
}
