import AppKit
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// **外部改动监听（`FR-STD-WS-FS-009`）的 App 内行为探针**。
///
/// ## 判什么
///
///   ① 文件被**编辑器之外的程序**改动时，界面**立即**反映：真 `FSEvents` 流（`WorkspaceFileWatcher`）
///      把那条路径报上来，开着它的**干净页签**随即重载成盘上的新正文；
///   ② **只重列被改目录**：换一片缓存、不整树重来 —— 别的目录仍展开、行还在，`revision` 只 +1；
///   ③ **脏页签只记标记、不覆盖内容**：`diskChangedTabIDs` 收下它，正文一个字不动；
///   ④ `.git` / `.build` / `node_modules` 里的改动**不触发回刷**。
///
/// ## 怎么判
///
/// · ①③ 走**真接线**：`AppState.startWorkspaceWatching(root:)` → 真 FSEvents → `handleDiskChanges`
///   → `reloadTab(at:force:false)`。外部改动由 `FileManager` 真写一个文件模拟
///   （与「别的程序改了它」在磁盘上是同一件事）；
/// · ②④ 走**真入口** `WorkspaceStore.reloadDirectories(forChangedPaths:)`（与
///   `AppState.handleDiskChanges` 调的同一个），断言落在 `visibleRows()` / `revision` 上 ——
///   整树重刷会把 `expandedPaths` 清空（树塌），那是**能被看见**的差别；
/// · 断言全部是行为读数：盘上写了什么、模型里读回什么。**不 mock 文件系统、不比对源码字符串**。
///
/// ## 口径：报上来的路径是**解析过符号链接**的那一版
///
/// `FSEvents` 报 `/private/var/folders/…`，而 `URL.appendingPathComponent` 给的是
/// `/var/folders/…`。两种写法混着比字符串，`changed.contains(path)` 与 `path.hasPrefix(root)`
/// 都会静默不命中 —— 判据会变成恒绿（实测踩到：第一版就是这么"通过"了"忽略目录不刷树"那条）。
/// 所以夹具的路径一律先过 `WorkspaceFileProbeKit.reported(_:)`。
///
/// ## 反证记录（2026-11-01：改坏一处产品代码 → 红 → 逐字节还原 → 绿）
///
/// · `WorkspaceStore.reloadDirectories` 改成整树重刷（`childrenCache` / `expandedPaths` 清空）⇒
///   「另一个展开着的目录被一起重刷了」「被改目录里原有的行没了」「没展开的目录里的一次变化也触发了重列」红；
/// · `AppState.reloadTab` 去掉「脏页签只记标记」那一档 ⇒「脏页签被外部内容覆盖了」红；
/// · `WorkspaceChangeScope.ignoredDirectoryNames` 去掉 `.git` / `.build` / `node_modules` ⇒
///   忽略目录那条红。三处一起改坏时本文件 10 处红，还原后 4/4 绿。
///
/// ## 边界（如实登记）
///
/// · 「立即」有了上限：判据给 8–10 秒窗口（FSEvents 本身有防抖 + 合并），
///   超出窗口才算红 —— 这不是「界面在 1 帧内更新」的证明，那是渲染层的读数；
/// · 工作区**根之外**的单文件监听（`watch(file:)`）不在这里判：它走
///   `DispatchSourceFileSystemObject` 另一条路，需求这一条问的是工作区树；
/// · `WorkspaceStore.shared` 不参与：`AppState.handleDiskChanges` 里刷树那一步打的是单例，
///   探针给不了它根目录（也不能动主人的书签），所以「刷树」那一半单独在真 store 上判（②④）；
/// · 不碰用户数据：夹具是临时目录。
final class WorkspaceExternalChangeProbeTests: XCTestCase {

    override func setUpWithError() throws {
        try XCTSkipUnless(
            UISnapshot.isEnabled,
            "离屏活体宿主要显式打开：DOYAH_UI_SNAPSHOT=1（取证工具，不进每轮门禁）"
        )
    }

    /// 夹具：`src/notes.txt`、`src/other.txt`、`docs/readme.md`、`archive/old.txt`。
    private func makeScratch(_ label: String) throws -> WorkspaceFileProbeKit.Scratch {
        let scratch = try WorkspaceFileProbeKit.Scratch(label)
        try scratch.write("第一版\n", at: "src/notes.txt")
        try scratch.write("另一个\n", at: "src/other.txt")
        try scratch.write("文档\n", at: "docs/readme.md")
        try scratch.write("旧\n", at: "archive/old.txt")
        return scratch
    }

    // MARK: - ① 真 FSEvents 流把外部写入报上来（「立即反映」的下限）

    @MainActor
    func testExternalWriteIsReportedByTheRealWatcher() async throws {
        let scratch = try makeScratch("fs-009a")
        defer { scratch.remove() }
        let root = WorkspaceFileProbeKit.reportedURL(scratch.root)

        let box = PathBox()
        let watcher = WorkspaceFileWatcher(debounce: 0.05)
        watcher.start(root: root.path) { paths in box.append(paths) }
        defer { watcher.stop() }

        let target = WorkspaceFileProbeKit.reported(try scratch.write("外部第二版\n", at: "src/notes.txt"))

        let reported = await WorkspaceFileProbeKit.pumpAsync(timeout: 8) {
            box.paths.contains { $0 == target }
        }
        print("WATCHER[外部改动] 目标=\(target)")
        print("WATCHER[外部改动] 实收=\(box.paths.sorted())")
        XCTAssertTrue(
            reported,
            "外部写入之后 8 秒内没收到 `\(target)` —— 界面永远不会反映这次改动。实收：\(box.paths.sorted())"
        )
        XCTAssertTrue(
            box.paths.allSatisfy { $0.hasPrefix(root.path) },
            "报上来的路径跑出了工作区：\(box.paths.filter { !$0.hasPrefix(root.path) })"
        )
    }

    // MARK: - ①③ 干净页签跟着重载 / 脏页签只记标记

    @MainActor
    func testExternalEditReloadsACleanTabAndOnlyMarksADirtyOne() async throws {
        let scratch = try makeScratch("fs-009b")
        defer { scratch.remove() }
        let root = WorkspaceFileProbeKit.reportedURL(scratch.root)

        let state = AppState()
        defer { state.stopWorkspaceWatching() }
        let cleanURL = WorkspaceFileProbeKit.reportedURL(try scratch.write("第一版\n", at: "src/notes.txt"))
        let dirtyURL = WorkspaceFileProbeKit.reportedURL(try scratch.write("另一个\n", at: "src/other.txt"))

        state.openFile(at: cleanURL)
        state.openFile(at: dirtyURL)
        state.startWorkspaceWatching(root: root.path)

        let cleanIndex = try XCTUnwrap(state.tabs.firstIndex { $0.fileURL?.path == cleanURL.path })
        let dirtyIndex = try XCTUnwrap(state.tabs.firstIndex { $0.fileURL?.path == dirtyURL.path })
        let dirtyID = state.tabs[dirtyIndex].id
        // 用户在编辑器里敲了字（界面上这就是「脏」的来源）。
        state.tabs[dirtyIndex].sql = "我自己写的\n"
        state.tabs[dirtyIndex].isDirty = true

        // 编辑器之外的程序改这两个文件。
        try "外部第二版\n".write(to: cleanURL, atomically: true, encoding: .utf8)
        try "也被改过\n".write(to: dirtyURL, atomically: true, encoding: .utf8)

        let reloaded = await WorkspaceFileProbeKit.pumpAsync(timeout: 10) {
            state.tabs[cleanIndex].sql == "外部第二版\n" && state.diskChangedTabIDs.contains(dirtyID)
        }

        print(
            "WATCHER[页签] 干净页签正文=\(state.tabs[cleanIndex].sql.debugDescription)"
                + " · 脏页签正文=\(state.tabs[dirtyIndex].sql.debugDescription)"
                + " · 标记=\(state.diskChangedTabIDs.contains(dirtyID))"
        )
        XCTAssertTrue(reloaded, "外部改动之后，干净页签没有重载 / 脏页签没有拿到「磁盘已变」的标记")

        XCTAssertEqual(
            state.tabs[cleanIndex].sql, "外部第二版\n",
            "没有未保存改动的页签应当跟着盘上的新正文重载 —— 否则屏幕上永远是旧内容"
        )
        XCTAssertFalse(state.tabs[cleanIndex].isDirty, "干净页签重载之后不该变成脏的")
        XCTAssertEqual(
            state.tabs[dirtyIndex].sql, "我自己写的\n",
            "有未保存改动的页签被外部内容覆盖了 —— 那是丢数据，需求要求**只记标记**"
        )
        XCTAssertTrue(
            state.diskChangedTabIDs.contains(dirtyID),
            "脏页签既没被覆盖、也没被标出来 —— 用户永远不知道盘上已经变了"
        )
        XCTAssertNotNil(state.statusMessage, "这次重载/标记没有在状态栏说一句话")
    }

    // MARK: - ② 只重列被改目录（展开状态不塌、别的目录不跟着刷）

    @MainActor
    func testOnlyTheChangedDirectoryIsRelisted() async throws {
        let scratch = try makeScratch("fs-009c")
        defer { scratch.remove() }
        let store = try await WorkspaceFileProbeKit.store(for: scratch)
        let rootPath = try XCTUnwrap(store.rootPath)

        // 两个目录都展开着（这就是「用户眼前的那棵树」）。
        store.toggle(try WorkspaceFileProbeKit.entry("src", in: scratch.root))
        store.toggle(try WorkspaceFileProbeKit.entry("docs", in: scratch.root))
        XCTAssertTrue(store.visibleRows().contains { $0.entry.relativePath == "src/notes.txt" })
        XCTAssertTrue(store.visibleRows().contains { $0.entry.relativePath == "docs/readme.md" })

        let revisionBefore = store.revision

        // 外部程序在 src 里新建了一个文件（FSEvents 报的是解析后的绝对路径）。
        let added = WorkspaceFileProbeKit.reported(try scratch.write("外部新建\n", at: "src/added.txt"))
        store.reloadDirectories(forChangedPaths: [added])

        let rows = store.visibleRows().map(\.entry.relativePath)
        print("WATCHER[只重列] 根=\(rootPath) · 上报=\(added) · 判定层给出=\(WorkspaceChangeScope.directoriesToReload(changedPaths: [added], rootPath: rootPath, expandedPaths: ["src", "docs"]))")
        print("WATCHER[只重列] 被改目录后的行=\(rows) · revision \(revisionBefore) → \(store.revision)")
        XCTAssertTrue(rows.contains("src/added.txt"), "被改的那个目录没有重列 —— 新文件在树上永远看不见")
        XCTAssertTrue(
            rows.contains("docs/readme.md"),
            "另一个展开着的目录被一起重刷了（行没了 / 展开了又收起）—— 需求要求只重列被改目录"
        )
        XCTAssertTrue(rows.contains("src/other.txt"), "被改目录里原有的行没了")
        XCTAssertEqual(store.revision, revisionBefore + 1, "重列次数不对（\(revisionBefore) → \(store.revision)）：多刷了别的目录")

        // 没展开的目录里有变化 ⇒ 不取（看不见的东西，取了也没人画）。
        let hidden = WorkspaceFileProbeKit.reported(try scratch.write("归档里新增\n", at: "archive/new.txt"))
        let revisionBeforeHidden = store.revision
        store.reloadDirectories(forChangedPaths: [hidden])
        XCTAssertEqual(
            store.revision, revisionBeforeHidden,
            "没展开的目录里的一次变化也触发了重列 —— 懒加载白做了"
        )
    }

    // MARK: - ④ `.git` / `.build` / `node_modules` 不触发回刷

    @MainActor
    func testChangesInsideIgnoredDirectoriesDoNotTriggerAReload() async throws {
        let scratch = try makeScratch("fs-009d")
        defer { scratch.remove() }
        let store = try await WorkspaceFileProbeKit.store(for: scratch)
        let rootPath = try XCTUnwrap(store.rootPath)
        store.toggle(try WorkspaceFileProbeKit.entry("src", in: scratch.root))
        XCTAssertTrue(store.visibleRows().contains { $0.entry.relativePath == "src/notes.txt" })

        // 这些目录里的写入每次编译 / 提交都会发生；树上看不到它们，重列等于白刷。
        let noisy = [
            WorkspaceFileProbeKit.reported(try scratch.write("ref: refs/heads/main\n", at: ".git/HEAD")),
            WorkspaceFileProbeKit.reported(try scratch.write("objc\n", at: ".build/debug/probe.o")),
            WorkspaceFileProbeKit.reported(try scratch.write("module.exports={}\n", at: "node_modules/pkg/index.js"))
        ]
        let revisionBefore = store.revision
        let rowsBefore = store.visibleRows().map(\.entry.relativePath)

        store.reloadDirectories(forChangedPaths: noisy)

        print("WATCHER[忽略目录] revision \(revisionBefore) → \(store.revision)")
        XCTAssertEqual(
            store.revision, revisionBefore,
            "`.git` / `.build` / `node_modules` 里的写入触发了文件树重刷 —— 每次编译都会刷一遍树"
        )
        XCTAssertEqual(
            store.visibleRows().map(\.entry.relativePath), rowsBefore,
            "忽略目录里的改动让树上的行变了"
        )
        // 同一条口径在纯判定那一层也要成立（否则 store 与判定两处会给出不同答案）。
        XCTAssertEqual(
            WorkspaceChangeScope.directoriesToReload(
                changedPaths: noisy, rootPath: rootPath, expandedPaths: ["src", "docs"]
            ),
            [],
            "判定层没把这三个目录排除掉"
        )
        // 对照：同一棵树上，一个**普通**目录里的改动必须刷（否则上一条"没刷"可能只是因为整体失灵）。
        let plain = WorkspaceFileProbeKit.reported(try scratch.write("普通新增\n", at: "src/plain.txt"))
        store.reloadDirectories(forChangedPaths: [plain])
        XCTAssertEqual(store.revision, revisionBefore + 1, "普通目录里的改动也没刷 —— 「忽略目录不刷」那条成了空话")
    }
}

// MARK: - 回调收集盒

/// `FSEvents` 的回调在监听器自己的队列上 —— 给个带锁的盒子，别让「收集」这件事变成竞态。
private final class PathBox: @unchecked Sendable {

    private let lock = NSLock()
    private var collected: [String] = []

    var paths: [String] {
        lock.lock(); defer { lock.unlock() }
        return collected
    }

    func append(_ paths: [String]) {
        lock.lock(); collected.append(contentsOf: paths); lock.unlock()
    }
}
