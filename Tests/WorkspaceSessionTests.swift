import XCTest
@testable import DoyahCore

/// 会话快照（`FR-EDIT-43` · 队列 `L-116` · 片 `L116-RESTORE-1`）。
///
/// 三组用例与卡片上的三条判据一一对应：
///  ① 快照 `encode → decode` **往返一致**（逐字段）；
///  ② 引用的文件**已删 / 已改名 ⇒ 如实标「找不到」**，不静默丢页签；
///  ③ **脏缓冲不静默丢**（契约 ③ 选项 a：恢复内容 + 标「未保存」）。
final class WorkspaceSessionTests: XCTestCase {

    // MARK: 夹具

    private func temporaryURL(_ ext: String = "json") -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("doyah-workspace-session-\(UUID().uuidString).\(ext)")
    }

    /// 造一个真的文件页签（语言按路径判，与 `WorkspaceTabSet.opening` 同口径）。
    private func fileTab(_ path: String, content: String, saved: String? = nil) -> WorkspaceTab {
        WorkspaceTab(
            title: WorkspaceTabSet.title(for: path),
            path: path,
            language: TextLanguage.detect(path: path),
            content: content,
            savedContent: saved
        )
    }

    // MARK: - ① 往返一致

    func testSnapshotRoundTripKeepsEveryField() throws {
        let home = WorkspaceTab.home(title: "首页")
        let clean = fileTab("/tmp/proj/index.ts", content: "let a = 1")
        let dirty = fileTab("/tmp/proj/a.ts", content: "let a = 2", saved: "let a = 1")
        XCTAssertTrue(dirty.isDirty)

        let snapshot = WorkspaceSessionSnapshot.capture(
            tabs: [home, clean, dirty],
            selectedID: dirty.id,
            workspacePath: "/tmp/proj"
        )
        XCTAssertEqual(snapshot.version, WorkspaceSessionSnapshot.currentVersion)

        let decoded = try WorkspaceSessionSnapshot.decode(from: JSONEncoder().encode(snapshot))

        XCTAssertEqual(decoded, snapshot)
        // **逐字段**（整条相等会掩盖「相等但字段被换过位置」的写法 —— 判据 ① 要的是逐字段）。
        XCTAssertEqual(decoded.version, 1)
        XCTAssertEqual(decoded.workspacePath, "/tmp/proj")
        XCTAssertEqual(decoded.selectedTabIndex, 2)
        XCTAssertEqual(decoded.tabs.count, 3)
        XCTAssertNil(decoded.tabs[0].path)
        XCTAssertEqual(decoded.tabs[0].title, "首页")
        XCTAssertEqual(decoded.tabs[0].language, "plainText")
        XCTAssertEqual(decoded.tabs[1].path, "/tmp/proj/index.ts")
        XCTAssertEqual(decoded.tabs[1].language, "typescript")
        XCTAssertEqual(decoded.tabs[2].unsavedContent, "let a = 2")
    }

    /// 干净页签**不带内容**进快照：内容以盘上的文件为准（存一份只会存出陈旧副本）。
    func testCleanTabCarriesNoContentIntoTheSnapshot() {
        let snapshot = WorkspaceSessionSnapshot.capture(
            tabs: [fileTab("/tmp/proj/index.ts", content: "let a = 1")],
            selectedID: nil,
            workspacePath: nil
        )
        XCTAssertNil(snapshot.tabs[0].unsavedContent)
    }

    /// **本片不碰光标 / 滚动位置**（那是紧接的下一片）—— 快照的字段面就是判据：
    /// 多出 `cursor` / `scroll` 之类的栏位当场变红，免得「写进去没人读」的半扇门留在文件里。
    ///
    /// 口径：`selectedTabIndex` 记过才有这一栏（Swift 对 `Optional` 的合成编码是「`nil` 就不写」）
    /// —— 所以这里选一个页签，把四栏都逼出来。
    func testSnapshotShapeHasNoCursorOrScrollFields() throws {
        let tab = fileTab("/tmp/proj/a.ts", content: "x", saved: "y")
        let snapshot = WorkspaceSessionSnapshot.capture(
            tabs: [tab],
            selectedID: tab.id,
            workspacePath: "/tmp/proj"
        )
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any]
        XCTAssertEqual(Set((json ?? [:]).keys), ["version", "workspacePath", "selectedTabIndex", "tabs"])
        let first = (json?["tabs"] as? [[String: Any]])?.first
        XCTAssertEqual(Set((first ?? [:]).keys), ["path", "title", "language", "unsavedContent"])
    }

    /// 版本兼容（读）：缺 `version` 栏（更早的手写文件 / 将来裁掉的栏位）按 `1` 读，不炸整个会话。
    func testDecoderTreatsMissingVersionAsTheCurrentFormat() throws {
        let json = #"{"tabs":[{"path":"/tmp/proj/a.ts","title":"a.ts","language":"typescript"}]}"#
        let decoded = try WorkspaceSessionSnapshot.decode(from: Data(json.utf8))
        XCTAssertEqual(decoded.version, 1)
        XCTAssertEqual(decoded.tabs.count, 1)
        XCTAssertNil(decoded.tabs[0].unsavedContent)
    }

    /// 版本兼容（拒）：比本版本新的写法**如实拒绝**，不猜着读（猜 = 把用户的页签洗掉）。
    func testNewerVersionIsRefusedNotGuessed() {
        let json = #"{"version":99,"tabs":[]}"#
        XCTAssertThrowsError(try WorkspaceSessionSnapshot.decode(from: Data(json.utf8))) { error in
            XCTAssertEqual(error as? WorkspaceSessionSnapshot.Failure, .unsupportedVersion(99))
        }
    }

    // MARK: - 落盘

    func testStoreReturnsNilWhenNoSnapshotWasEverWritten() throws {
        XCTAssertNil(try WorkspaceSessionStore(fileURL: temporaryURL()).load())
    }

    func testStoreRoundTripThroughDisk() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = WorkspaceSessionStore(fileURL: url)

        let snapshot = WorkspaceSessionSnapshot.capture(
            tabs: [WorkspaceTab.home(title: "首页"), fileTab("/tmp/proj/a.ts", content: "new", saved: "old")],
            selectedID: nil,
            workspacePath: "/tmp/proj"
        )
        try store.save(snapshot)
        XCTAssertEqual(try store.load(), snapshot)
    }

    /// 空文件（写到一半断电）当作**没有快照**，不是错误。
    func testStoreTreatsAnEmptyFileAsNoSnapshot() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data().write(to: url)
        XCTAssertNil(try WorkspaceSessionStore(fileURL: url).load())
    }

    /// 内容坏了要**抛错**（调用方如实告诉用户），而不是静默当成「没有上次会话」——
    /// 那样用户会以为页签丢了，其实是文件坏了。
    func testStoreThrowsOnCorruptFile() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not json".utf8).write(to: url)
        XCTAssertThrowsError(try WorkspaceSessionStore(fileURL: url).load())
    }

    func testStoreClearDropsTheSnapshot() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = WorkspaceSessionStore(fileURL: url)
        try store.save(WorkspaceSessionSnapshot(tabs: [.init(path: "/tmp/proj/a.ts", title: "a.ts", language: "typescript")]))
        XCTAssertNotNil(try store.load())
        try store.clear()
        XCTAssertNil(try store.load())
        // 再清一次不报错（本来就没有 = 没事发生，不是错误）。
        XCTAssertNoThrow(try store.clear())
    }

    /// 落盘位置跟同一家族的命名法（`workspace-history.json` / `browser-tabs.json` 同一个目录、
    /// 同一个后缀）：`DoyahStudio/workspace-session.json`。
    func testStandardLocationFollowsTheHouseNaming() {
        let base = URL(fileURLWithPath: "/tmp/appsupport")
        let store = WorkspaceSessionStore.standard(applicationSupport: base)
        XCTAssertEqual(store.fileURL.lastPathComponent, "workspace-session.json")
        XCTAssertEqual(store.fileURL.deletingLastPathComponent().lastPathComponent, DoyahIdentity.applicationSupportDirectoryName)
        XCTAssertEqual(store.fileURL.deletingLastPathComponent().deletingLastPathComponent().path, base.path)
    }

    // MARK: - ② 缺文件 ⇒ 如实标「找不到」，不丢页签

    func testMissingFileKeepsTheTabAndReportsIt() {
        let snapshot = WorkspaceSessionSnapshot.capture(
            tabs: [WorkspaceTab.home(title: "首页"), fileTab("/nowhere/gone.swift", content: "let a = 1")],
            selectedID: nil,
            workspacePath: nil
        )
        // 注入一个「盘上什么都没有」的读盘面：这条判据不该靠真去删一个文件来造。
        let restored = WorkspaceSessionSnapshot.restore(from: snapshot) { _ in nil }

        XCTAssertEqual(restored.tabs.count, 2)
        XCTAssertEqual(restored.tabs[1].path, "/nowhere/gone.swift")
        XCTAssertEqual(restored.tabs[1].title, "gone.swift")
        XCTAssertEqual(restored.missingPaths, ["/nowhere/gone.swift"])
    }

    /// 同一个判据走**默认读盘面**（真文件系统）：路径不存在 ⇒ 仍然如实标「找不到」。
    func testMissingFileIsReportedByTheRealReader() {
        let path = temporaryURL("swift").path
        try? FileManager.default.removeItem(atPath: path)
        let snapshot = WorkspaceSessionSnapshot.capture(
            tabs: [fileTab(path, content: "let a = 1")],
            selectedID: nil,
            workspacePath: nil
        )
        let restored = WorkspaceSessionSnapshot.restore(from: snapshot)
        XCTAssertEqual(restored.tabs.count, 1)
        XCTAssertEqual(restored.missingPaths, [path])
    }

    /// 改名与删除是同一件事的两面：快照里那个**旧路径**找不到 ⇒ 如实标出来（页签不丢）。
    func testRenamedFileIsReportedMissingUnderItsOldPath() throws {
        let old = temporaryURL("swift").path
        let renamed = temporaryURL("swift").path
        try Data("let a = 1".utf8).write(to: URL(fileURLWithPath: renamed))
        defer { try? FileManager.default.removeItem(atPath: renamed) }

        let snapshot = WorkspaceSessionSnapshot.capture(
            tabs: [fileTab(old, content: "let a = 1")],
            selectedID: nil,
            workspacePath: nil
        )
        let restored = WorkspaceSessionSnapshot.restore(from: snapshot)
        XCTAssertEqual(restored.missingPaths, [old])
        XCTAssertEqual(restored.tabs[0].path, old)
    }

    /// 盘上真有的文件：内容取**盘上的**（不是快照里的旧副本），且恢复出来是干净的。
    func testPresentFileRestoresDiskContent() throws {
        let path = temporaryURL("swift").path
        try Data("let onDisk = 42".utf8).write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }

        let snapshot = WorkspaceSessionSnapshot.capture(
            tabs: [fileTab(path, content: "let a = 1")],
            selectedID: nil,
            workspacePath: nil
        )
        let restored = WorkspaceSessionSnapshot.restore(from: snapshot)

        XCTAssertTrue(restored.missingPaths.isEmpty)
        XCTAssertEqual(restored.tabs[0].content, "let onDisk = 42")
        XCTAssertEqual(restored.tabs[0].savedContent, "let onDisk = 42")
        XCTAssertFalse(restored.tabs[0].isDirty)
    }

    // MARK: - ③ 脏缓冲不静默丢（选项 a：恢复内容 + 标「未保存」）

    func testDirtyBufferComesBackAndStaysDirty() throws {
        let path = temporaryURL("swift").path
        try Data("let a = 1".utf8).write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }

        let live = fileTab(path, content: "let a = 2", saved: "let a = 1")
        XCTAssertTrue(live.isDirty)
        let snapshot = WorkspaceSessionSnapshot.capture(tabs: [live], selectedID: live.id, workspacePath: nil)

        let restored = WorkspaceSessionSnapshot.restore(from: snapshot)

        XCTAssertEqual(restored.tabs[0].content, "let a = 2")     // 未保存的改动原样回来
        XCTAssertEqual(restored.unsavedPaths, [path])
        // **仍是脏的** ⇒ 界面那枚「未保存」标记（`workspaceDirtyTag`）自己会亮。
        XCTAssertTrue(restored.tabs[0].isDirty)
        // 且不是「假装保存过」：盘上那份内容没被当成用户的改动。
        XCTAssertEqual(restored.tabs[0].savedContent, "let a = 1")
    }

    /// 文件没了**又**带着未保存改动：两条都要说出来（内容取自快照，且仍是脏的）。
    func testDirtyBufferSurvivesAFileThatIsGone() {
        let path = "/nowhere/unsaved.swift"
        let live = fileTab(path, content: "let a = 2", saved: "let a = 1")
        let snapshot = WorkspaceSessionSnapshot.capture(tabs: [live], selectedID: nil, workspacePath: nil)

        let restored = WorkspaceSessionSnapshot.restore(from: snapshot) { _ in nil }

        XCTAssertEqual(restored.tabs.count, 1)
        XCTAssertEqual(restored.tabs[0].content, "let a = 2")
        XCTAssertTrue(restored.tabs[0].isDirty)
        XCTAssertEqual(restored.missingPaths, [path])
        XCTAssertEqual(restored.unsavedPaths, [path])
    }

    // MARK: - 选中与落脚点

    func testRestoreKeepsTheRecordedSelection() {
        let first = fileTab("/tmp/proj/a.ts", content: "a")
        let second = fileTab("/tmp/proj/b.ts", content: "b")
        let snapshot = WorkspaceSessionSnapshot.capture(
            tabs: [first, second],
            selectedID: second.id,
            workspacePath: "/tmp/proj"
        )
        let restored = WorkspaceSessionSnapshot.restore(from: snapshot) { _ in "x" }
        XCTAssertEqual(restored.tabs.count, 2)
        XCTAssertEqual(restored.selectedTabID, restored.tabs[1].id)
        XCTAssertEqual(restored.workspacePath, "/tmp/proj")
    }

    /// 下标越界（手改过的文件 / 页签数变了）⇒ 落回第一个，不猜、也不空手。
    func testRestoreFallsBackToTheFirstTabWhenTheIndexIsOutOfRange() {
        let snapshot = WorkspaceSessionSnapshot(
            workspacePath: nil,
            selectedTabIndex: 7,
            tabs: [WorkspaceSessionSnapshot.Tab(path: "/tmp/proj/a.ts", title: "a.ts", language: "typescript")]
        )
        let restored = WorkspaceSessionSnapshot.restore(from: snapshot) { _ in "x" }
        XCTAssertEqual(restored.selectedTabID, restored.tabs.first?.id)
    }

    /// 认不出的语言标识（快照比本版本新 / 表里删过一条）⇒ 按路径重判，判不出是纯文本。
    func testUnknownLanguageIdentifierFallsBackToThePath() {
        let snapshot = WorkspaceSessionSnapshot(
            workspacePath: nil,
            selectedTabIndex: nil,
            tabs: [
                WorkspaceSessionSnapshot.Tab(path: "/tmp/proj/a.swift", title: "a.swift", language: "kotlin-prime"),
                WorkspaceSessionSnapshot.Tab(path: nil, title: "首页", language: "kotlin-prime")
            ]
        )
        let restored = WorkspaceSessionSnapshot.restore(from: snapshot) { _ in "x" }
        XCTAssertEqual(restored.tabs[0].language, .swift)
        XCTAssertEqual(restored.tabs[1].language, .plainText)
    }

    func testRestoreOfAnEmptySnapshotYieldsNothing() {
        let restored = WorkspaceSessionSnapshot.restore(from: WorkspaceSessionSnapshot()) { _ in nil }
        XCTAssertTrue(restored.tabs.isEmpty)
        XCTAssertNil(restored.selectedTabID)
        XCTAssertTrue(restored.missingPaths.isEmpty)
        XCTAssertTrue(restored.unsavedPaths.isEmpty)
    }
}
