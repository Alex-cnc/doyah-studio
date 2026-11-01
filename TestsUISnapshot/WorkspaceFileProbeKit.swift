import AppKit
import XCTest

import DoyahCore
@testable import DoyahStudioApp

/// **工作区文件操作族探针的共用夹具**（只在 `TestsUISnapshot` 里用，不进产品）。
///
/// ## 为什么要有这一份
///
/// `FR-STD-WS-FS-003 / 004 / 005 / 006 / 009` 五条需求的判据都要「一个真工作区 + 真
/// `WorkspaceStore` + 真页签模型」。若每条套件各搭一遍，夹具会长出五种口径
/// （根怎么给、书签落哪儿、页签历史写哪儿），而**口径一歪，判据就只在那一份夹具里成立**。
///
/// ## 三条纪律
///
/// ① **夹具全在临时目录里**：`FileManager.temporaryDirectory` 下自建、用完 `remove()`
///    —— 不写主人的书签表（`DirectoryBookmarkStore` 注入临时目录）、不写主人的页签历史；
/// ② **真入口、真磁盘**：`WorkspaceStore.choose` / `createEntry` / `rename` / `delete` /
///    `move` / `undoLastFileOperation` 一个都不 mock，断言落在 `FileManager` 读回来的真实结果上；
/// ③ **删进废纸篓的残渣由夹具收尾**：`trashItem` 是需求要求的真实行为，测试没撤回来的那些
///    记进 `rememberTrash`，`remove()` 时一起清掉（别往主人的废纸篓里留垃圾）。
enum WorkspaceFileProbeKit {

    /// 一个临时工作区 + 一个临时书签目录。
    final class Scratch {

        let root: URL
        private let stateDirectory: URL
        private var trashLeftovers: [URL] = []

        init(_ label: String) throws {
            let base = FileManager.default.temporaryDirectory
                .appendingPathComponent("doyah-ws-probe-\(label)", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            root = base.appendingPathComponent("workspace", isDirectory: true)
            stateDirectory = base.appendingPathComponent("state", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
        }

        func url(_ relative: String) -> URL {
            relative.isEmpty ? root : root.appendingPathComponent(relative)
        }

        /// 页签历史 / 会话快照这类**不该出现在工作区树里**的东西的落点。
        func stateFile(_ name: String) -> URL {
            stateDirectory.appendingPathComponent(name, isDirectory: false)
        }

        @discardableResult
        func write(_ text: String, at relative: String) throws -> URL {
            let target = url(relative)
            try FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: target, atomically: true, encoding: .utf8)
            return target
        }

        @discardableResult
        func mkdir(_ relative: String) throws -> URL {
            let target = url(relative)
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            return target
        }

        func names(in relative: String = "") throws -> [String] {
            try FileManager.default.contentsOfDirectory(atPath: url(relative).path).sorted()
        }

        func exists(_ relative: String) -> Bool {
            FileManager.default.fileExists(atPath: url(relative).path)
        }

        func text(at relative: String) throws -> String {
            try String(contentsOf: url(relative), encoding: .utf8)
        }

        func rememberTrash(_ url: URL?) {
            if let url { trashLeftovers.append(url) }
        }

        /// 收尾：临时工作区、临时状态目录、以及测试没撤回来的废纸篓残渣。
        func remove() {
            for leftover in trashLeftovers { try? FileManager.default.removeItem(at: leftover) }
            trashLeftovers = []
            try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
        }
    }

    // MARK: - 真入口

    /// 一个根目录 = 临时工作区的真 `WorkspaceStore`。
    ///
    /// 走的是产品那条路：`choose(url)` → 造书签 → 记进已知工作区表 → `adopt` 取用 → 读根目录。
    /// 书签表注入临时目录（见纪律 ①）。
    @MainActor
    static func store(for scratch: Scratch) async throws -> WorkspaceStore {
        let store = WorkspaceStore(
            store: DirectoryBookmarkStore(
                directoryURL: scratch.stateFile("bookmarks").deletingLastPathComponent(),
                fileName: "probe-bookmarks.json"
            )
        )
        await store.choose(scratch.root)
        let root = try XCTUnwrap(
            store.rootURL,
            "工作区没取用成功（errorText=\(store.errorText ?? "nil")）—— 后面所有判据都无从谈起"
        )
        XCTAssertEqual(
            root.standardizedFileURL.path,
            scratch.root.standardizedFileURL.path,
            "取用到的根不是那个临时工作区"
        )
        return store
    }

    /// 页签模型：历史与会话快照都落在临时状态目录里。
    @MainActor
    static func tabs(for scratch: Scratch) -> WorkspaceTabsModel {
        WorkspaceTabsModel(
            store: WorkspaceHistoryStore(fileURL: scratch.stateFile("probe-history.json")),
            sessionStore: WorkspaceSessionStore(fileURL: scratch.stateFile("probe-session.json"))
        )
    }

    // MARK: - 树上的条目（真列目录出来的，不是手搓的）

    static func entry(_ relative: String, in root: URL) throws -> WorkspaceEntry {
        let url = root.appendingPathComponent(relative)
        let entries = try WorkspaceTree.children(of: url.deletingLastPathComponent(), relativeTo: root)
        return try XCTUnwrap(
            entries.first { $0.relativePath == relative },
            "夹具里没有 `\(relative)`（这一层实际有 \(entries.map(\.relativePath))）"
        )
    }

    // MARK: - 界面动作（逐行照抄 `WorkspaceExplorerView` 里那几段，不另写判定）

    /// `WorkspaceExplorerView.createEntry(in:asFile:)`：建 → 文件则**开进页签并落在第 1 行**。
    @MainActor
    @discardableResult
    static func createLikeTheView(
        in directory: WorkspaceEntry,
        asFile: Bool = true,
        store: WorkspaceStore,
        tabs: WorkspaceTabsModel
    ) -> URL? {
        guard let created = store.createEntry(in: directory, asFile: asFile) else { return nil }
        guard asFile else { return created }
        tabs.openFile(at: created, line: 1)
        return created
    }

    /// `WorkspaceExplorerView.commitRename(_:)`：改名成功之后**页签路径与标题跟着走**。
    @MainActor
    @discardableResult
    static func commitRename(
        _ entry: WorkspaceEntry,
        to name: String,
        store: WorkspaceStore,
        tabs: WorkspaceTabsModel
    ) -> URL? {
        let source = store.url(for: entry)
        guard let renamed = store.rename(entry, to: name) else { return nil }
        if let source, source.standardizedFileURL != renamed.standardizedFileURL {
            tabs.retarget(from: source.path, to: renamed.path)
        }
        return renamed
    }

    /// `WorkspaceExplorerView.treeRow` 的 `onDropInto`（拖拽落地 → 页签跟着走）。
    @MainActor
    @discardableResult
    static func drop(
        _ sourcePath: String,
        into directoryPath: String,
        store: WorkspaceStore,
        tabs: WorkspaceTabsModel
    ) -> WorkspaceStore.MoveOutcome {
        let outcome = store.move(sourcePath, into: directoryPath)
        if let from = outcome.from, let to = outcome.to {
            tabs.retarget(from: from.path, to: to.path)
        }
        return outcome
    }

    /// `WorkspaceExplorerView.undoLastFileOperation()`：撤销之后页签**跟着收 / 跟着改**。
    @MainActor
    @discardableResult
    static func undoLikeTheView(store: WorkspaceStore, tabs: WorkspaceTabsModel) -> WorkspaceFileUndo? {
        guard let undone = store.undoLastFileOperation() else { return nil }
        switch undone.kind {
        case .creation:
            tabs.closeTabs(atPath: undone.currentURL.path)
        case .rename, .move:
            if let original = undone.originalURL {
                tabs.retarget(from: undone.currentURL.path, to: original.path)
            }
        case .deletion:
            // 页签本来就指着原路径，文件回到原处之后它自然又有效。
            break
        }
        return undone
    }

    // MARK: - 路径口径（FSEvents 给的是**解析过符号链接**的路径）

    /// 把夹具里的路径换成 `FSEvents` 会报上来的那种写法。
    ///
    /// 为什么必须有这一步：`FSEvents` 报的是**解析过符号链接**的真实路径
    /// （临时目录 `/var/folders/…` → `/private/var/folders/…`），而 `URL.appendingPathComponent`
    /// 给的是没解析的写法。两边混着比字符串，`changed.contains(path)` 与 `path.hasPrefix(root)`
    /// 都会**静默**不命中 —— 判据会变成"恒绿"或"恒红"，与被测的那件事无关。
    ///
    /// **不能用 `URL.resolvingSymlinksInPath()`**（实测 2026-11-01）：Foundation 对 `/var` 这条
    /// 系统链接**不改成** `/private/var`，拿它算出来的还是 `/var/…`，与 FSEvents 报的对不上
    /// —— 第一版本就是这么写，`判定层给出=[]`、`revision 3 → 3`，看着像产品不刷树，
    /// 其实是探针自己的路径口径错。`realpath` 才是 FSEvents 那个口径。
    ///
    /// 产品侧同理：`WorkspaceStore.rootPath` 来自书签解析（也是 `/private/var/…` 那一版），
    /// 所以"外部改动报上来的路径"与"树里的根"本来就在同一个口径上。
    static func reported(_ url: URL) -> String {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        if let resolved = realpath(url.path, &buffer) {
            return String(cString: resolved)
        }
        return url.standardizedFileURL.path
    }

    /// 同一个口径的 URL 版本（给「页签打开的是哪一份文件」用）。
    static func reportedURL(_ url: URL) -> URL {
        URL(fileURLWithPath: reported(url), isDirectory: false)
    }

    // MARK: - 等异步落地

    /// 等一件事在**主 actor 让出之后**成立。
    ///
    /// 为什么不用 `RunLoop.run` 泵：那样泵着的时候「从别的线程跳回主 actor」的续体**落不了地**
    /// （`UISnapshotKit.LiveHost.pumpAsync` 的实测记录，第 101 / 106 轮）。监听回调正是
    /// `Task { @MainActor in … }` 这一跳 —— 用 `Task.sleep` 让出，才等得到它。
    @MainActor
    static func pumpAsync(
        timeout: TimeInterval = 8,
        interval: Double = 0.05,
        until condition: () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
        return condition()
    }
}
