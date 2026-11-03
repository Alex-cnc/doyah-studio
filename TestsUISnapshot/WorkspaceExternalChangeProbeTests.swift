import AppKit
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// **外部改动监听（`FR-STD-WS-FS-009` / `-008`）的 App 内行为探针**。
///
/// ## 判什么
///
///   ① 真 `FSEvents` 流（`WorkspaceFileWatcher`）把外部写入的路径报上来；
///   ② 从那条真事件出发，**编辑器里开着的那一页**（`WorkspaceTabsModel`）跟着盘上的新正文重载；
///   ③ 脏页签**只记标记、不覆盖正文**，且界面读得到那个标记；
///   ④ 同一条事件链上**左侧文件树**（`WorkspaceStore`）重列了被改目录 ——
///      根目录新建的文件在 `visibleRows()` 里出现，`revision` 只 +1；
///   ⑤ `.git` / `.build` / `node_modules` 里的改动不触发回刷。
///
/// ## 2026-11-03 的**假绿**（这一版之前的样子，必须写清楚）
///
/// 上一版 ①③ 也是走真 FSEvents，但断言落在 `AppState.tabs` 上 —— 那是**数据库的 SQL 页签**
/// （界面上只有 `QueryWorkspaceView` 渲染它）。工作区编辑器渲染的是 `WorkspaceTabsModel`，
/// 而 `AppState.handleDiskChanges` **从头到尾没有碰过它**，它自己也没有「按盘上重载」的方法
/// ⇒ 探针全绿、真机「改了文件正文一动不动」。刷树那一半更远：`handleDiskChanges` 里打的是
/// `WorkspaceStore.shared`（藏起来的全局），探针给不了它根目录，所以「刷树」那一步
/// **从来没有被任何判据走过**（上一版自己在注释里承认了这一点，然后拿 store 的
/// `reloadDirectories` 直调代替）。
///
/// 现在夹具换成**生产的接线点** `WorkspaceDiskChangeWiring.attach`：真 store + 真页签模型 +
/// 真 `AppState`，外部写入由 `FileManager` 真落盘。**一处都不绕过**：
/// `startWorkspaceWatching` → 真 FSEvents → `handleDiskChanges` → 接线闭包 → store / tabs。
///
/// ## 反例（2026-11-03 实测，改坏 ⇒ 判红 ⇒ 逐字节还原 ⇒ 绿）
///
/// · 接线里去掉 `tabs.reloadFromDisk(changedPaths:)` ⇒ ③ 的「干净页签没重载」「脏页签没标记」红；
/// · 接线里去掉 `store.reloadDirectories(forChangedPaths:)` ⇒ ④ 的「新文件没出现在树上」红；
/// · `WorkspaceChangeScope.ignoredDirectoryNames` 去掉 `.git` / `.build` / `node_modules` ⇒ ⑤ 红。
///
/// ## 边界（如实登记）
///
/// · 「立即」有上限：判据给 8–10 秒窗口（FSEvents 本身有防抖 + 合并）——
///   这不是「1 帧内更新」的证明；渲染层读数另算；
/// · 图片页（`kind == .image`）不在这里判：它没有正文，展示面每次重建都从盘上读；
/// · 不碰用户数据：夹具是临时目录，书签 / 历史 / 会话快照都注入临时状态目录。
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

    /// 生产的接线：真 `AppState` + 真 store + 真页签模型，监听挂在这个临时根上。
    ///
    /// 根的写法用 `reported(...)`（`realpath` 那一版）：`FSEvents` 报的就是这个口径，
    /// 拿 `/var/...` 去挂、拿 `/private/var/...` 去比，判据会**恒不命中**（上一版踩过）。
    @MainActor
    private func liveHost(
        _ scratch: WorkspaceFileProbeKit.Scratch
    ) async throws -> (AppState, WorkspaceStore, WorkspaceTabsModel, String) {
        let store = try await WorkspaceFileProbeKit.store(for: scratch)
        let tabs = WorkspaceFileProbeKit.tabs(for: scratch)
        let state = AppState()
        WorkspaceDiskChangeWiring.attach(appState: state, store: store, tabs: tabs)
        let root = WorkspaceFileProbeKit.reported(scratch.root)
        state.startWorkspaceWatching(root: root)
        return (state, store, tabs, root)
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

    // MARK: - ②③ 真事件 → 编辑器里那一页重载 / 脏页签只记标记（**走生产接线**）

    @MainActor
    func testExternalEditReloadsTheOpenFileTabInTheWorkspaceEditor() async throws {
        let scratch = try makeScratch("fs-009b")
        defer { scratch.remove() }
        let (state, _, tabs, root) = try await liveHost(scratch)
        defer { state.stopWorkspaceWatching() }
        // **接线本身也判**：真机上「监听压根没起」与「没有改动」在界面上长得一模一样，
        // 而 `startWorkspaceWatching` 返回之后没有任何读数能区分这两件事（2026-11-03 排查点）。
        XCTAssertTrue(
            state.isWorkspaceWatching,
            "`startWorkspaceWatching(root:)` 之后监听没在跑（FSEvents 流没起来）—— 后面的判据全都无从谈起"
        )

        // 用户从左侧树上打开两个文件 —— 这就是编辑器渲染的那一页（`WorkspaceTabsModel`）。
        let cleanURL = WorkspaceFileProbeKit.reportedURL(try scratch.write("第一版\n", at: "src/notes.txt"))
        let dirtyURL = WorkspaceFileProbeKit.reportedURL(try scratch.write("另一个\n", at: "src/other.txt"))
        tabs.openFile(at: cleanURL)
        tabs.openFile(at: dirtyURL)

        let cleanTab = try XCTUnwrap(
            tabs.tabs.first { $0.path == cleanURL.path },
            "干净的那一页没开起来（页签集：\(tabs.tabs.map { $0.path ?? "<nil>" })）"
        )
        let dirtyTab = try XCTUnwrap(
            tabs.tabs.first { $0.path == dirtyURL.path },
            "要弄脏的那一页没开起来（页签集：\(tabs.tabs.map { $0.path ?? "<nil>" })）"
        )
        // 用户在编辑器里敲了字（界面上这就是「脏」的来源）。
        tabs.updateContent("我自己写的\n", for: dirtyTab.id)
        XCTAssertTrue(
            tabs.tabs.first { $0.id == dirtyTab.id }?.isDirty == true,
            "夹具没把这一页弄脏 —— 下面「脏页签不被覆盖」那条就成了空话"
        )

        // 编辑器之外的程序改这两个文件（`FileManager` 真写盘，与「另一个进程改了它」在磁盘上是同一件事）。
        try "外部第二版\n".write(to: cleanURL, atomically: true, encoding: .utf8)
        try "也被改过\n".write(to: dirtyURL, atomically: true, encoding: .utf8)

        let reloaded = await WorkspaceFileProbeKit.pumpAsync(timeout: 10) {
            tabs.tabs.first { $0.id == cleanTab.id }?.content == "外部第二版\n"
                && tabs.diskChangedTabIDs.contains(dirtyTab.id)
        }

        let cleanNow = tabs.tabs.first { $0.id == cleanTab.id }?.content
        let dirtyNow = tabs.tabs.first { $0.id == dirtyTab.id }?.content
        print(
            "WATCHER[页签·真接线] 根=\(root)"
                + " · 干净页签正文=\(cleanNow.debugDescription)"
                + " · 脏页签正文=\(dirtyNow.debugDescription)"
                + " · 标记=\(tabs.diskChangedTabIDs.contains(dirtyTab.id))"
                + " · 底部提示=\(tabs.noticeText.debugDescription)"
        )
        XCTAssertTrue(
            reloaded,
            "外部改动之后，编辑器里那一页没有重载 / 脏页签没有拿到「磁盘已变」的标记"
                + "（干净页签现在=\(cleanNow.debugDescription)）"
        )
        XCTAssertEqual(
            cleanNow, "外部第二版\n",
            "没有未保存改动的页签没跟着盘上的新正文重载 —— 屏幕上永远是旧内容（真机症状②）"
        )
        XCTAssertEqual(
            tabs.tabs.first { $0.id == cleanTab.id }?.isDirty, false,
            "干净页签重载之后不该变成脏的"
        )
        XCTAssertEqual(
            dirtyNow, "我自己写的\n",
            "有未保存改动的页签被外部内容覆盖了 —— 那是丢数据，需求要求**只记标记**"
        )
        XCTAssertTrue(
            tabs.diskChangedTabIDs.contains(dirtyTab.id),
            "脏页签既没被覆盖、也没被标出来 —— 用户永远不知道盘上已经变了"
        )
        XCTAssertNotNil(tabs.noticeText, "这次重载 / 标记没有在界面上说一句话")
    }

    // MARK: - ② 反方向：人点了「以磁盘为准重载」之后，脏页签按盘上覆盖

    @MainActor
    func testReloadFromDiskOverwritesADirtyTabOnlyWhenAsked() async throws {
        let scratch = try makeScratch("fs-009e")
        defer { scratch.remove() }
        let store = try await WorkspaceFileProbeKit.store(for: scratch)
        let tabs = WorkspaceFileProbeKit.tabs(for: scratch)
        let url = WorkspaceFileProbeKit.reportedURL(try scratch.write("第一版\n", at: "src/notes.txt"))
        tabs.openFile(at: url)
        let tab = try XCTUnwrap(tabs.tabs.first { $0.path == url.path })
        tabs.updateContent("我自己写的\n", for: tab.id)

        try "外部第二版\n".write(to: url, atomically: true, encoding: .utf8)
        tabs.reloadFromDisk(changedPaths: [WorkspaceFileProbeKit.reported(url)])
        XCTAssertEqual(
            tabs.tabs.first { $0.id == tab.id }?.content, "我自己写的\n",
            "没人表态就覆盖了脏页签 —— 丢的是用户敲的字"
        )
        XCTAssertTrue(tabs.diskChangedTabIDs.contains(tab.id))

        tabs.reloadFromDisk(tabID: tab.id, force: true)
        XCTAssertEqual(
            tabs.tabs.first { $0.id == tab.id }?.content, "外部第二版\n",
            "人已经点了「以磁盘为准重载」，正文却没换 —— 那个按钮等于没用"
        )
        XCTAssertFalse(
            tabs.tabs.first { $0.id == tab.id }?.isDirty ?? true,
            "按磁盘重载之后这一页应当是干净的（盘上就是现在这份）"
        )
        XCTAssertFalse(tabs.diskChangedTabIDs.contains(tab.id), "重载完标记还挂着，界面会一直问")
        _ = store
    }

    // MARK: - ④ 真事件 → 左侧文件树重列（根目录新建的文件要出现）

    @MainActor
    func testExternalNewFileAppearsInTheTreeThroughTheRealWatcher() async throws {
        let scratch = try makeScratch("fs-009c")
        defer { scratch.remove() }
        let (state, store, _, root) = try await liveHost(scratch)
        defer { state.stopWorkspaceWatching() }
        XCTAssertTrue(state.isWorkspaceWatching, "监听没在跑 —— 树那条链路无从谈起")
        // 再调一次**同一个根**：不许把已经起好的流停掉（`stopWorkspaceWatching` 之后
        // 同一个根要能重新起 —— 这是「先停后没起」那一类缺陷的判据）。
        state.startWorkspaceWatching(root: root)
        XCTAssertTrue(state.isWorkspaceWatching, "对同一个根再调一次之后监听没了")
        state.stopWorkspaceWatching()
        XCTAssertFalse(state.isWorkspaceWatching, "`stopWorkspaceWatching()` 之后监听还在跑")
        state.startWorkspaceWatching(root: root)
        XCTAssertTrue(state.isWorkspaceWatching, "停掉之后再用同一个根起，起不来了")

        // 用户眼前那棵树：根列着，`src` 展开着。
        store.toggle(try WorkspaceFileProbeKit.entry("src", in: scratch.root))
        XCTAssertTrue(store.visibleRows().contains { $0.entry.relativePath == "src/notes.txt" })
        let revisionBefore = store.revision

        // 外部程序在**根目录**新建一个文件（真机症状①的那一下）。
        let added = try scratch.write("外部新建\n", at: "root-added.txt")
        let shownUp = await WorkspaceFileProbeKit.pumpAsync(timeout: 10) {
            store.visibleRows().contains { $0.entry.relativePath == "root-added.txt" }
        }
        let rows = store.visibleRows().map(\.entry.relativePath)
        print(
            "WATCHER[树·真接线] 根=\(root) · 新建=\(WorkspaceFileProbeKit.reported(added))"
                + " · 行=\(rows) · revision \(revisionBefore) → \(store.revision)"
        )
        XCTAssertTrue(
            shownUp,
            "外部在根目录新建的文件没出现在树上 —— 真机症状①（树零反应）。当前行：\(rows)"
        )
        XCTAssertTrue(
            rows.contains("src/notes.txt"),
            "展开着的 `src` 被一起重刷了（行没了 / 收了）—— 需求要求只重列被改目录"
        )
        XCTAssertEqual(
            store.revision, revisionBefore + 1,
            "重列次数不对（\(revisionBefore) → \(store.revision)）：多刷了别的目录"
        )
    }

    // MARK: - ⑤ `.git` / `.build` / `node_modules` 不触发回刷

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

    // MARK: - ⑥ 路径口径：`/var` 与 `/private/var` 是同一个文件

    /// 这一条钉的是「比较恒不命中」那个静默失效：`FSEvents` 报 `realpath`，页签记用户写法。
    ///
    /// Foundation 的 `URL.resolvingSymlinksInPath()` **解不掉 `/var`**（2026-11-01 那版"修法"
    /// 因此是空的），所以口径唯一换算点是 `WorkspacePathIdentity.canonical`。
    func testFSEventStylePathMatchesAPlainlyWrittenPath() throws {
        let scratch = try makeScratch("fs-009f")
        defer { scratch.remove() }
        let plainly = scratch.url("src/notes.txt")
        let reported = WorkspaceFileProbeKit.reported(plainly)
        print("WATCHER[路径口径] 明写=\(plainly.path) · FSEvents 口径=\(reported)")
        XCTAssertEqual(
            WorkspacePathIdentity.canonical(plainly.path), reported,
            "两侧换算完还不是同一个字符串 —— 外部改动会被静默漏判"
        )
        XCTAssertNotEqual(
            plainly.resolvingSymlinksInPath().path, reported,
            "Foundation 的 resolvingSymlinksInPath 竟然解掉了 /var —— 那么这条判据的前提变了，要重新取证"
        )
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
