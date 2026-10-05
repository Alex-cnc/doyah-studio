import XCTest
@testable import DoyahCore

/// 工作区文件操作（`FR-EDIT-41` / 队列 `L-114`）：真实文件系统上跑，连同**越界与符号链接**这两条边界。
///
/// 为什么用真文件系统：这一族的价值就在「真的动了盘」—— 名字撞没撞、废纸篓进没进、
/// 目录跟着链接跑没跑出去，都是环境事实，桩替不了。
final class WorkspaceFileOperationsTests: XCTestCase {

    private var sandbox: URL!
    private var workspace: URL!

    override func setUpWithError() throws {
        sandbox = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("doyah-fileops-\(UUID().uuidString)")
        workspace = sandbox.appendingPathComponent("ws")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: sandbox)
    }

    private func makeFile(_ name: String, in directory: URL, contents: String = "x") throws -> URL {
        let url = directory.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: 建

    func testCreateFileTakesAUniqueNameAndWritesAnEmptyFile() throws {
        let first = try WorkspaceFileOperations.createFile(
            baseName: "Untitled", fileExtension: "txt", in: workspace, workspaceURL: workspace
        )
        let second = try WorkspaceFileOperations.createFile(
            baseName: "Untitled", fileExtension: "txt", in: workspace, workspaceURL: workspace
        )

        XCTAssertEqual(first.lastPathComponent, "Untitled.txt")
        XCTAssertEqual(second.lastPathComponent, "Untitled 2.txt", "撞名要顺延，不是覆盖也不是失败")
        XCTAssertEqual(try Data(contentsOf: first), Data(), "新建的是**空文件**（不是模板）")
    }

    func testCreateDirectoryTakesAUniqueName() throws {
        let first = try WorkspaceFileOperations.createDirectory(
            baseName: "New Folder", in: workspace, workspaceURL: workspace
        )
        let second = try WorkspaceFileOperations.createDirectory(
            baseName: "New Folder", in: workspace, workspaceURL: workspace
        )

        XCTAssertEqual(first.lastPathComponent, "New Folder")
        XCTAssertEqual(second.lastPathComponent, "New Folder 2")

        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    func testCreateFileRefusesANonDirectoryParent() throws {
        let file = try makeFile("a.txt", in: workspace)
        XCTAssertThrowsError(
            try WorkspaceFileOperations.createFile(
                baseName: "b", fileExtension: "txt", in: file, workspaceURL: workspace
            )
        ) { error in
            XCTAssertEqual(error as? WorkspaceFileOperations.Failure, .notADirectory("a.txt"))
        }
    }

    // MARK: 名字校验

    func testValidateRejectsEmptyUnsafeAndPaddedNames() {
        XCTAssertEqual(WorkspaceFileOperations.validate(name: ""), .emptyName)
        XCTAssertEqual(WorkspaceFileOperations.validate(name: "   "), .emptyName)
        XCTAssertEqual(WorkspaceFileOperations.validate(name: "."), .illegalName("."))
        XCTAssertEqual(WorkspaceFileOperations.validate(name: ".."), .illegalName(".."))
        XCTAssertEqual(WorkspaceFileOperations.validate(name: "a/b"), .illegalName("a/b"))
        XCTAssertEqual(WorkspaceFileOperations.validate(name: "a:b"), .illegalName("a:b"))
        XCTAssertEqual(WorkspaceFileOperations.validate(name: " a"), .illegalName(" a"))
        XCTAssertEqual(WorkspaceFileOperations.validate(name: "a "), .illegalName("a "))
        XCTAssertNil(WorkspaceFileOperations.validate(name: "正常名字.txt"))
        XCTAssertNil(WorkspaceFileOperations.validate(name: "notes 2.md"))
    }

    // MARK: 改名

    func testRenameMovesTheEntry() throws {
        let file = try makeFile("old.txt", in: workspace, contents: "body")
        let renamed = try WorkspaceFileOperations.rename(file, to: "new.txt", in: workspace)

        XCTAssertEqual(renamed.lastPathComponent, "new.txt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(try String(contentsOf: renamed, encoding: .utf8), "body", "改名不该动内容")
    }

    func testRenameToTheSameNameIsNotAFailure() throws {
        let file = try makeFile("same.txt", in: workspace)
        let renamed = try WorkspaceFileOperations.rename(file, to: "same.txt", in: workspace)
        XCTAssertEqual(renamed.standardizedFileURL, file.standardizedFileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testRenameRefusesAnExistingName() throws {
        _ = try makeFile("a.txt", in: workspace)
        let b = try makeFile("b.txt", in: workspace)
        XCTAssertThrowsError(try WorkspaceFileOperations.rename(b, to: "a.txt", in: workspace)) { error in
            XCTAssertEqual(error as? WorkspaceFileOperations.Failure, .alreadyExists("a.txt"))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: b.path), "拒绝之后原文件必须还在原处")
    }

    func testRenameRefusesUnsafeNames() throws {
        let file = try makeFile("c.txt", in: workspace)
        for bad in ["", " ", "x/y", "x:y", ".", ".."] {
            XCTAssertThrowsError(try WorkspaceFileOperations.rename(file, to: bad, in: workspace)) { error in
                guard let failure = error as? WorkspaceFileOperations.Failure else {
                    return XCTFail("应当给结构化失败，而不是 \(error)")
                }
                switch failure {
                case .emptyName, .illegalName: break
                default: XCTFail("改名的名字校验只许报「空」或「非法」，实际 \(failure)")
                }
            }
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    // MARK: 删

    func testDeleteGoesToTheTrashAndLeavesNothingBehind() throws {
        let file = try makeFile("trash-me.txt", in: workspace)
        let trashed = try WorkspaceFileOperations.delete(file, in: workspace)

        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "原位置必须没了")
        if let trashed {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: trashed.path),
                "`trashItem` 说移到哪就得到哪（这是「可撤销」的凭据）"
            )
            try? FileManager.default.removeItem(at: trashed)  // 判据自己收拾干净，不给用户废纸篓留垃圾
        }
    }

    func testDeleteRefusesTheWorkspaceRoot() throws {
        XCTAssertThrowsError(try WorkspaceFileOperations.delete(workspace, in: workspace)) { error in
            XCTAssertEqual(error as? WorkspaceFileOperations.Failure, .rootNotDeletable)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.path))
    }

    func testDeletionSummaryCountsTheWholeSubtree() throws {
        let folder = try WorkspaceFileOperations.createDirectory(
            baseName: "d", in: workspace, workspaceURL: workspace
        )
        let inner = folder.appendingPathComponent("e")
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: false)
        _ = try makeFile("a", in: folder)
        _ = try makeFile("b", in: folder)
        _ = try makeFile("c", in: inner)

        // 自身 + a + b + e + c
        XCTAssertEqual(
            WorkspaceFileOperations.deletionSummary(at: folder),
            WorkspaceFileOperations.DeletionSummary(items: 5, truncated: false)
        )
        XCTAssertEqual(
            WorkspaceFileOperations.deletionSummary(at: folder.appendingPathComponent("a")),
            WorkspaceFileOperations.DeletionSummary(items: 1, truncated: false),
            "文件就是 1 项"
        )
    }

    func testDeletionSummaryStopsAtTheLimitAndSaysSo() throws {
        let folder = try WorkspaceFileOperations.createDirectory(
            baseName: "many", in: workspace, workspaceURL: workspace
        )
        for index in 0..<(WorkspaceFileOperations.deletionCountLimit + 5) {
            try Data().write(to: folder.appendingPathComponent("f\(index)"))
        }
        let summary = WorkspaceFileOperations.deletionSummary(at: folder)
        XCTAssertTrue(summary.truncated, "数到上限就停 —— 不为说一句话把十万条目录读完")
        XCTAssertEqual(summary.items, WorkspaceFileOperations.deletionCountLimit)
    }

    // MARK: 边界：越界与符号链接

    func testOperationsRefuseTargetsOutsideTheWorkspace() throws {
        let outside = sandbox.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)

        XCTAssertThrowsError(
            try WorkspaceFileOperations.createFile(
                baseName: "nope", fileExtension: "txt", in: outside, workspaceURL: workspace
            )
        ) { error in
            XCTAssertEqual(error as? WorkspaceFileOperations.Failure, .notContained)
        }

        XCTAssertThrowsError(
            try WorkspaceFileOperations.createDirectory(
                baseName: "nope", in: outside, workspaceURL: workspace
            )
        ) { error in
            XCTAssertEqual(error as? WorkspaceFileOperations.Failure, .notContained)
        }

        let outsideFile = try makeFile("o.txt", in: outside)
        XCTAssertThrowsError(try WorkspaceFileOperations.delete(outsideFile, in: workspace)) { error in
            XCTAssertEqual(error as? WorkspaceFileOperations.Failure, .notContained)
        }

        let inside = try makeFile("i.txt", in: workspace)
        XCTAssertThrowsError(try WorkspaceFileOperations.rename(inside, to: "x.txt", in: outside)) { error in
            XCTAssertEqual(error as? WorkspaceFileOperations.Failure, .notContained)
        }
    }

    /// 符号链接是 `isContained` 拦不住的那一类（它比的是字符串路径）—— 这里钉住「先解链接再判」。
    func testSymlinkEscapeIsRefused() throws {
        let outside = sandbox.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let link = workspace.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

        XCTAssertThrowsError(
            try WorkspaceFileOperations.createFile(
                baseName: "escaped", fileExtension: "txt", in: link, workspaceURL: workspace
            )
        ) { error in
            XCTAssertEqual(error as? WorkspaceFileOperations.Failure, .notContained)
        }

        XCTAssertThrowsError(
            try WorkspaceFileOperations.createDirectory(baseName: "escaped", in: link, workspaceURL: workspace)
        ) { error in
            XCTAssertEqual(error as? WorkspaceFileOperations.Failure, .notContained)
        }
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: outside.appendingPathComponent("escaped.txt").path),
            "越界请求被拒之后，工作区外不许留下任何东西"
        )
    }
}
