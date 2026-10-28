import AppKit
import Combine
import DoyahCore
import DoyahPlatform

/// 工作区状态（FR-EDIT-32）：用户自选目录 + 沙箱授权书签 + 一层懒加载的文件树。
///
/// 关于授权：macOS 沙箱下访问用户目录必须持有 security-scoped bookmark，
/// 所以这里**在生命周期内一直握着 `DirectoryGrant`**（RAII：换工作区或清空时停止访问）。
/// 非沙箱构建里 `startAccessingSecurityScopedResource()` 会返回 false —— 那**不是**被拒绝，
/// 已有代码对此有专门处理（见 `SecureDirectoryAccess`）。
///
/// 关于树：只列**一层**，展开哪一层读哪一层。工程目录动辄几万条，
/// 递归读完会让界面卡住，而用户真正会点的只有当前这几行。
@MainActor
final class WorkspaceStore: ObservableObject {

    static let shared = WorkspaceStore()

    @Published private(set) var bookmark: DirectoryBookmark?
    @Published private(set) var status: DirectoryAccessStatus?
    @Published private(set) var rootURL: URL?
    @Published private(set) var isBusy = false
    /// 缓存内容变化时自增，驱动界面重绘（缓存本身不需要被观察）。
    @Published private(set) var revision = 0

    /// 文件操作给的实话（成功也给一句：删除尤其要说清「去哪儿了」）。`nil` = 没有要说的。
    @Published private(set) var noticeText: String?

    /// 正在**行内改名**的那个条目（相对路径）—— 新建之后直接进这一态（需求提出者原话）。
    @Published var renamingPath: String?

    /// 文件操作的**一次撤销**（`FR-STD-WS-FS-005` ③ / `FS-006` ③）。只有一层，撤销完就没了。
    @Published private(set) var undoLog = WorkspaceUndoLog()

    /// 界面据此决定要不要出「撤销」那一枚。
    var canUndoFileOperation: Bool { undoLog.canUndo }

    // MARK: 已知工作区（`FR-STD-WS-FS-010`）

    /// 已知工作区表 + 当前活动的那一条。**这张表是切换的唯一来源**：界面按 `knownWorkspaces`
    /// 画列表，点哪一条都走 `switchTo(_:)`，裁决由 `WorkspaceRegistry` 给（Core 侧逐条判过：
    /// 同一目录只一条 / 只有一个活动 / 不可用的切不过去 / 容量不淘汰活动那条）。
    @Published private(set) var registry = WorkspaceRegistry()

    /// 界面用的那一份（把 `activeID` 折成每一行的 `isActive`）。
    var knownWorkspaces: [KnownWorkspace] { registry.candidates }

    /// 活动书签 id 的落点：书签表只记「有哪些」，不记「在用哪个」。
    private static let activeDefaultsKey = "workspace.activeBookmarkID"

    private var storedActiveID: UUID? {
        UserDefaults.standard.string(forKey: Self.activeDefaultsKey).flatMap(UUID.init(uuidString:))
    }

    private func rememberActive(_ id: UUID?) {
        if let id {
            UserDefaults.standard.set(id.uuidString, forKey: Self.activeDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.activeDefaultsKey)
        }
    }

    /// 书签 → 可用性（Core 那档机器口径；人话在语言表里）。
    static func availability(of bookmark: DirectoryBookmark) -> WorkspaceAvailability {
        WorkspaceAvailability(MacDirectoryAccess.status(for: bookmark))
    }

    /// 切不过去时界面上那一句。`nil` = 这一档不该出现在界面上（表与裁决不一致，不编句子）。
    static func refusalText(_ refusal: WorkspaceSwitchDecision.Refusal) -> String? {
        switch refusal {
        case .unknownWorkspace, .unavailable(.notAuthorized), .unavailable(.unresolved):
            return L(.workspaceUnavailableUnresolved)
        case .unavailable(.missing):
            return L(.workspaceUnavailableMissing)
        case .unavailable(.denied):
            return L(.workspaceUnavailableDenied)
        case .unavailable(.available):
            return nil
        }
    }

    /// 工作区变化时通知外部（终端启动目录要跟着走）。
    var onWorkspaceChanged: ((String?) -> Void)?

    // MARK: 文件名搜索（FR-EDIT-32 / FR-EDIT-44）
    //
    // 界面入口只有一个：标头那个搜索框（`App/Views/WorkspaceHeaderSearch.swift`，`FR-EDIT-44`：
    // **文件名 + 内容关键字分两组**）。它自己按需调 `Core/WorkspaceSearch`（一次给两组结果），
    // 所以这里**不再保留**「只搜文件名」的那套状态与缓存 —— 同一条路留两个入口，
    // 迟早出现「这个框搜得到、那个框搜不到」，而那是静默的（第 155 轮 §3.33 已定「一套引擎、两个入口」，
    // 那个"两个入口"指的是标头框与跨文件搜索，不是同一个框的两份实现）。

    private var childrenCache: [String: [WorkspaceEntry]] = [:]
    private var expandedPaths: Set<String> = []
    private var loadError: String?
    private var grant: DirectoryGrant?

    /// 单独一个书签文件：不污染数据任务导出目录 / 查询归档的「使用已授权目录」列表。
    ///
    /// 之所以可从外部注入：**落盘路径是这类代码唯一没法靠纯逻辑单测的部分**，
    /// 而自检探针又跑在被沙箱限制的进程里（写不了 `~/Library/Application Support`）。
    /// 注入一个临时目录的 store，就能把"保存 → 读回 → 解析"这条链路真正跑通。
    private let store: DirectoryBookmarkStore

    init(store: DirectoryBookmarkStore = DirectoryBookmarkStore(fileName: "workspace-bookmark.json")) {
        self.store = store
    }

    var rootPath: String? { rootURL?.path }

    var displayName: String {
        if let name = bookmark?.displayName, !name.isEmpty { return name }
        return rootURL?.lastPathComponent ?? ""
    }

    var hasWorkspace: Bool { rootURL != nil }

    var errorText: String? { loadError }

    // MARK: 生命周期

    /// 启动时调用：读回书签 → 重建已知工作区表 → 判定可用性 → 取用授权 → 读根目录。
    func load() async {
        isBusy = true
        defer { isBusy = false }
        do {
            let bookmarks = try await store.all()
            // 活动那条：**落盘的 id 优先**；老版本只存过一条书签、从没记过活动 id
            // ⇒ 把第一条当活动（与升级前的行为一致，不让人一升级就「没打开工作区」）。
            registry = WorkspaceRegistry.reconciled(
                bookmarks: bookmarks,
                activeID: storedActiveID ?? bookmarks.first?.id,
                availability: Self.availability(of:)
            )
            guard let activeID = registry.activeID,
                  let activeBookmark = bookmarks.first(where: { $0.id == activeID })
            else {
                apply(status: .notAuthorized, bookmark: nil)
                return
            }
            bookmark = activeBookmark
            adopt(activeBookmark)
            rememberActive(activeID)
        } catch {
            loadError = error.localizedDescription
            apply(status: nil, bookmark: nil)
        }
    }

    /// 用户刚在面板里选好一个目录（**追加**到已知工作区表，并切过去）。
    ///
    /// 不再「先清空再存」：`FR-STD-WS-FS-010` 要求「可在多个已知工作区之间切换」，
    /// 清空等于把上一轮的选择删掉。落盘用的是表算出来的 id —— 同一目录已登记过时
    /// 复用的是**旧 id**，否则磁盘上会同时留着两条指向同一目录的书签。
    func choose(_ url: URL) async {
        isBusy = true
        defer { isBusy = false }
        do {
            let created = try MacDirectoryAccess.makeBookmark(for: url)
            let resolved = registry.add(
                WorkspaceRegistry.Entry(bookmark: created, availability: .available)
            )
            let saved = try await store.save(
                DirectoryBookmark(
                    id: resolved,
                    displayName: created.displayName,
                    bookmarkData: created.bookmarkData,
                    createdAt: created.createdAt,
                    lastKnownPath: created.lastKnownPath
                )
            )
            rememberActive(saved.id)
            bookmark = saved
            adopt(saved)
        } catch {
            loadError = ErrorPresenter.message(for: error)
        }
    }

    /// 切到另一个**已知**工作区（`FR-STD-WS-FS-010`）。
    ///
    /// 三条纪律：
    ///   ① 裁决只认 `WorkspaceRegistry`（Core 判过），这里不再自己判一遍；
    ///   ② **先确认真能取用、再动活动** —— 切不过去时用户留在原来的工作区里，
    ///      界面只说一句为什么（`noticeText`），不把人扔进一个画不出内容的空工作区；
    ///   ③ 切完把活动 id 落盘（下次启动就停在这一条）。
    func switchTo(_ id: UUID) async {
        switch registry.decision(for: id) {
        case .alreadyActive:
            return
        case .refuse(let refusal):
            noticeText = Self.refusalText(refusal)
        case .switchTo:
            do {
                let bookmarks = try await store.all()
                guard let target = bookmarks.first(where: { $0.id == id }) else {
                    // 表里有、盘上没有（书签文件被外部改了）⇒ 重算一次表，并且如实说一句。
                    registry = WorkspaceRegistry.reconciled(
                        bookmarks: bookmarks,
                        activeID: registry.activeID,
                        availability: Self.availability(of:)
                    )
                    noticeText = Self.refusalText(.unknownWorkspace)
                    return
                }
                let resolved = MacDirectoryAccess.status(for: target)
                guard case .granted = resolved else {
                    // 上次重建之后目录没了 / 权限变了：刷新表（让那一行如实显示不可用）并拒绝切换。
                    registry = WorkspaceRegistry.reconciled(
                        bookmarks: bookmarks,
                        activeID: registry.activeID,
                        availability: Self.availability(of:)
                    )
                    noticeText = Self.refusalText(.unavailable(WorkspaceAvailability(resolved)))
                    return
                }
                adopt(target)
                bookmark = target
                registry.activate(id)
                rememberActive(id)
            } catch {
                loadError = ErrorPresenter.message(for: error)
            }
        }
    }

    /// 弹出目录选择器（用户取消不是错误）。
    func pickAndChoose() async {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.message = L(.workspaceChoose)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        await choose(url)
    }

    func clear() async {
        grant?.stopAccessing()
        grant = nil
        childrenCache.removeAll()
        expandedPaths.removeAll()
        bookmark = nil
        rootURL = nil
        loadError = nil
        noticeText = nil
        renamingPath = nil
        undoLog.clear()
        // 表也一起清空：`clear()` 已经把书签文件删了（`store.removeAll()`），
        // 表里那些条目此刻在盘上都不存在 —— 留着会让界面列出点不动的行。
        registry = WorkspaceRegistry()
        rememberActive(nil)
        try? await store.removeAll()
        apply(status: .notAuthorized, bookmark: nil)
    }

    /// 外部改动后**只重列被改目录**（2026-10-27 人类主人拍板：「只用加载被修的节点就行」）。
    ///
    /// 与 `refresh()` 的区别是根本性的：`refresh()` 走 `adopt`，会
    /// `childrenCache.removeAll()` + `expandedPaths.removeAll()`（树整棵塌、展开状态清零），
    /// 那是给「换书签 / 目录被移动」用的整体重来；文件变化不该付这个代价。
    /// 这里只动**可见的**那几个目录的缓存，展开状态一个字都不碰。
    func reloadDirectories(forChangedPaths paths: [String]) {
        guard let rootPath else { return }
        let targets = WorkspaceChangeScope.directoriesToReload(
            changedPaths: paths, rootPath: rootPath, expandedPaths: expandedPaths)
        guard !targets.isEmpty else { return }
        for relative in targets {
            childrenCache[relative] = listChildren(relativePath: relative)
        }
        revision += 1
    }

    /// 重新解析书签并刷新根目录（书签可能被外部改动 / 目录被移动）。
    func refresh() async {
        guard let bookmark else { return }
        isBusy = true
        defer { isBusy = false }
        adopt(bookmark)
    }

    // MARK: 树

    func isExpanded(_ entry: WorkspaceEntry) -> Bool {
        expandedPaths.contains(entry.relativePath)
    }

    func toggle(_ entry: WorkspaceEntry) {
        guard entry.isExpandable else { return }
        if expandedPaths.contains(entry.relativePath) {
            expandedPaths.remove(entry.relativePath)
        } else {
            expandedPaths.insert(entry.relativePath)
            if childrenCache[entry.relativePath] == nil {
                childrenCache[entry.relativePath] = listChildren(relativePath: entry.relativePath)
            }
        }
        revision += 1
    }

    /// 当前可见的行（按展开状态扁平化）。
    func visibleRows() -> [WorkspaceRow] {
        var rows: [WorkspaceRow] = []
        func append(_ entries: [WorkspaceEntry], depth: Int) {
            for entry in entries {
                rows.append(WorkspaceRow(entry: entry, depth: depth))
                if entry.isExpandable, expandedPaths.contains(entry.relativePath) {
                    append(childrenCache[entry.relativePath] ?? [], depth: depth + 1)
                }
            }
        }
        append(childrenCache[""] ?? [], depth: 0)
        return rows
    }

    func url(for entry: WorkspaceEntry) -> URL? {
        guard let rootURL else { return nil }
        return WorkspaceTree.resolve(relativePath: entry.relativePath, in: rootURL)
    }

    /// 在访达中显示（目录就打开它，文件则选中它）。
    func reveal(_ entry: WorkspaceEntry? = nil) {
        let target = entry.flatMap { url(for: $0) } ?? rootURL
        guard let target else { return }
        NSWorkspace.shared.activateFileViewerSelecting([target])
    }

    /// 在终端中打开（`FR-STD-WS-FS-003`）：文件开它**所在的目录**，目录开它自己。
    ///
    /// 走 `Core/WorkspaceTerminalOpen` 算出来的计划（`/usr/bin/open -a Terminal <目录>`，
    /// 路径作为一个 argv 原样传）—— 这里只负责起进程与如实报错。
    func openInTerminal(_ entry: WorkspaceEntry? = nil) {
        guard let rootURL else { return }
        guard let plan = WorkspaceTerminalOpen.plan(
            relativePath: entry?.relativePath ?? "",
            isDirectory: entry?.isDirectory ?? true,
            in: rootURL
        ) else {
            noticeText = L(.workspaceFileOpNotContained)
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: plan.tool)
        process.arguments = plan.arguments
        do {
            try process.run()
            noticeText = nil
        } catch {
            noticeText = L(.workspaceFileOpFailed, error.localizedDescription)
        }
    }

    // MARK: 文件操作（FR-EDIT-41 · 队列 L-114）
    //
    // 形态由需求提出者 2026-09-30 定（2026-10-02 追加「必须在 Alpha 2 交付」）：文件夹行 = 加号
    // （点开「新建文件 / 新建文件夹」）/ 减号（删到废纸篓）/ 铅笔（改名）；文件行 = 减号 / 铅笔。
    // 这里只管**动作与状态**；按钮长什么样、悬浮怎么出现，都在 `WorkspaceExplorerView`。

    /// 新建（文件 / 文件夹）：建完**直接进入改名态** —— 所以顺手把 `renamingPath` 置成新条目。
    ///
    /// 返回**建出来的那个 URL**（`nil` = 失败，失败原因已进 `noticeText`）——
    /// `FR-STD-WS-FS-004` ③「新建后自动打开且光标在首行」要靠它：store 管文件，页签归
    /// `WorkspaceTabsModel`，所以打开这一步由调用点拿这个 URL 去做（这里不越界去开页签）。
    @discardableResult
    func createEntry(in directory: WorkspaceEntry?, asFile: Bool) -> URL? {
        guard let rootURL else { return nil }
        let parent = directory.flatMap { url(for: $0) } ?? rootURL
        do {
            let created: URL
            if asFile {
                created = try WorkspaceFileOperations.createFile(
                    baseName: L(.workspaceNewFileBase),
                    fileExtension: "txt",
                    in: parent,
                    workspaceURL: rootURL
                )
            } else {
                created = try WorkspaceFileOperations.createDirectory(
                    baseName: L(.workspaceNewFolder),
                    in: parent,
                    workspaceURL: rootURL
                )
            }
            // 建在已展开的目录里：父目录不展开，新行根本看不见（用户会以为「点了没反应」）。
            if let directory { expandedPaths.insert(directory.relativePath) }
            guard let relative = WorkspaceTree.relativePath(of: created, in: rootURL) else { return created }
            reload(parentOf: relative)
            noticeText = nil
            renamingPath = relative
            undoLog.record(.creation(created: created, workspace: rootURL))
            return created
        } catch {
            noticeText = Self.operationMessage(for: error)
            return nil
        }
    }

    /// 改名。返回**改出来的新 URL**（`nil` = 没成）—— 失败要留在改名态里，别把输入框收掉
    /// （收掉等于把用户敲的字扔了）。
    ///
    /// 返回新 URL 而不是 `Bool` 的理由（`FR-STD-WS-FS-005` ①）：改名之后**已打开的页签要跟着走**，
    /// 那一步在页签模型里，调用点必须知道「从哪改到哪」。
    @discardableResult
    func rename(_ entry: WorkspaceEntry, to newName: String) -> URL? {
        guard let rootURL, let source = url(for: entry) else { return nil }
        do {
            let renamed = try WorkspaceFileOperations.rename(source, to: newName, in: rootURL)
            reload(parentOf: entry.relativePath)
            noticeText = nil
            renamingPath = nil
            // 同名提交（`rename` 返回原 URL）不算一次改动 ⇒ 记 `nil`，顺手清掉上一条撤销。
            if renamed.standardizedFileURL == source.standardizedFileURL {
                undoLog.record(nil)
            } else {
                undoLog.record(.rename(from: source, to: renamed, workspace: rootURL))
            }
            return renamed
        } catch {
            noticeText = Self.operationMessage(for: error)
            return nil
        }
    }

    /// 一次拖拽搬动的结局。
    ///
    /// 为什么不是 `Bool`：搬成功了**页签要跟着走**（`WorkspaceTabSet.retargeting`），
    /// 页签不归 store 管 —— 所以把「从哪搬到哪」带回去，由调用点决定怎么接。
    /// `from` / `to` 只有真搬了才有值（「落在同一层」与各种拒绝都是空）。
    struct MoveOutcome: Equatable {
        let accepted: Bool
        let from: URL?
        let to: URL?

        static let refused = MoveOutcome(accepted: false, from: nil, to: nil)
    }

    /// 搬进另一个目录（`FR-STD-WS-FS-003` 的拖拽移动）。
    ///
    /// 入参用**相对路径**而不是 `WorkspaceEntry`：拖拽的载荷本来就是字符串（`NSItemProvider`），
    /// 在 drop 时再回头去树里找一个 entry 是多余的一步，而且找到的那个 entry 可能已经是旧的。
    ///
    /// 判定只走 `WorkspaceFileMove.placement` 这一处（与界面「这一行接不接」同一份口径）：
    /// 根不搬 / 不搬进自己里面 / 同一层不动 —— 三条都在这里落地成一句话。
    ///
    /// - Returns: `accepted` = 这条拖拽被接下了（含「落在同一层」这种不用动的情形）；
    ///   `from` / `to` = 真搬了才给（界面照它把页签搬过去）。
    @discardableResult
    func move(_ sourcePath: String, into directoryPath: String) -> MoveOutcome {
        guard let rootURL,
              let source = WorkspaceTree.resolve(relativePath: sourcePath, in: rootURL)
        else { return .refused }
        switch WorkspaceFileMove.placement(source: sourcePath, into: directoryPath) {
        case .refused(.rootNotMovable):
            noticeText = L(.workspaceFileOpRootMove)
            return .refused
        case .refused(.intoOwnSubtree):
            noticeText = L(.workspaceFileOpOwnSubtree, source.lastPathComponent)
            return .refused
        case .noop:
            // 落在同一层：什么都不做，顺手清掉上一条撤销（否则「撤销」会去撤更早的那一下）。
            undoLog.record(nil)
            return MoveOutcome(accepted: true, from: nil, to: nil)
        case .move:
            break
        }
        let targetDirectory = WorkspaceTree.resolve(relativePath: directoryPath, in: rootURL) ?? rootURL
        do {
            let moved = try WorkspaceFileOperations.move(source, into: targetDirectory, in: rootURL)
            reload(parentOf: sourcePath)
            if let movedRelative = relativePath(of: moved, in: rootURL) {
                reload(parentOf: movedRelative)
            }
            renamingPath = nil
            undoLog.record(.move(from: source, to: moved, workspace: rootURL))
            // 目标目录要展开：不然搬进去的那一条看不见，用户会以为「拖丢了」。
            expandedPaths.insert(directoryPath)
            noticeText = L(.workspaceFileMoved, source.lastPathComponent, moved.deletingLastPathComponent().lastPathComponent)
            return MoveOutcome(accepted: true, from: source, to: moved)
        } catch {
            noticeText = Self.operationMessage(for: error)
            return .refused
        }
    }

    /// 删除（**走废纸篓**）：确认框在界面上，这里只管做与说。
    ///
    /// 撤回来的凭据 = `trashItem` 给的废纸篓位置，一路记进 `undoLog`（`FR-STD-WS-FS-006` ③）。
    @discardableResult
    func delete(_ entry: WorkspaceEntry) -> Bool {
        guard let rootURL, let target = url(for: entry) else { return false }
        do {
            let trashed = try WorkspaceFileOperations.delete(target, in: rootURL)
            reload(parentOf: entry.relativePath)
            noticeText = L(.workspaceFileTrashed, entry.name)
            undoLog.record(.deletion(original: target, trashedTo: trashed, workspace: rootURL))
            return true
        } catch {
            noticeText = Self.operationMessage(for: error)
            return false
        }
    }

    /// 撤销最近一次文件操作（`FR-STD-WS-FS-005` ③ / `FS-006` ③）。返回**被撤销的那一条**。
    ///
    /// 三条纪律：
    ///   ① **撤不回来就不算撤销** —— 失败时条目留在账上（用户还能再试），只把原因说出来；
    ///   ② 成功后**只刷新受影响的那些目录**（与新建 / 改名 / 删除同一条路，`reload(parentOf:)`）；
    ///   ③ 页签跟不跟随由调用点做（页签不归 store）—— 所以把那条记录原样返回。
    @discardableResult
    func undoLastFileOperation() -> WorkspaceFileUndo? {
        guard let rootURL, let entry = undoLog.pending else { return nil }
        do {
            _ = try WorkspaceUndoLog.revert(entry)
            undoLog.consume()
            switch entry.kind {
            case .creation:
                reload(parentOf: relativePath(of: entry.currentURL, in: rootURL) ?? "")
                noticeText = L(.workspaceUndoCreation, entry.currentURL.lastPathComponent)
            case .rename:
                let back = relativePath(of: entry.originalURL ?? entry.currentURL, in: rootURL) ?? ""
                reload(parentOf: back)
                noticeText = L(
                    .workspaceUndoRename,
                    entry.currentURL.lastPathComponent,
                    entry.originalURL?.lastPathComponent ?? ""
                )
            case .deletion:
                let back = relativePath(of: entry.currentURL, in: rootURL) ?? ""
                reload(parentOf: back)
                noticeText = L(.workspaceUndoDeletion, entry.currentURL.lastPathComponent)
            case .move:
                // 搬回原处：来源目录与搬走后的目录都要重列（两边各少 / 各多一条）。
                reload(parentOf: relativePath(of: entry.originalURL ?? entry.currentURL, in: rootURL) ?? "")
                reload(parentOf: relativePath(of: entry.currentURL, in: rootURL) ?? "")
                noticeText = L(.workspaceUndoMove, entry.currentURL.lastPathComponent)
            }
            renamingPath = nil
            return entry
        } catch {
            noticeText = Self.operationMessage(for: error)
            return nil
        }
    }

    private func relativePath(of url: URL, in rootURL: URL) -> String? {
        WorkspaceTree.relativePath(of: url, in: rootURL)
    }

    /// 删之前那句「将删几项」（非空文件夹必须让用户先看见数字）。
    func deletionSummary(for entry: WorkspaceEntry) -> WorkspaceFileOperations.DeletionSummary {
        guard let target = url(for: entry) else {
            return WorkspaceFileOperations.DeletionSummary(items: 0, truncated: false)
        }
        return WorkspaceFileOperations.deletionSummary(at: target)
    }

    /// 失败要说得清是哪一类（Core 只给结构，句子在这里）。
    static func operationMessage(for error: Error) -> String {
        guard let failure = error as? WorkspaceFileOperations.Failure else {
            return L(.workspaceFileOpFailed, error.localizedDescription)
        }
        switch failure {
        case .emptyName: return L(.workspaceFileOpEmptyName)
        case .illegalName(let name): return L(.workspaceFileOpIllegalName, name)
        case .alreadyExists(let name): return L(.workspaceFileOpExists, name)
        case .notContained: return L(.workspaceFileOpNotContained)
        case .notADirectory(let name): return L(.workspaceFileOpNotADirectory, name)
        case .rootNotDeletable: return L(.workspaceFileOpRoot)
        case .rootNotMovable: return L(.workspaceFileOpRootMove)
        case .intoOwnSubtree(let name): return L(.workspaceFileOpOwnSubtree, name)
        case .trashCopyMissing(let name): return L(.workspaceUndoTrashMissing, name)
        case .system(let reason): return L(.workspaceFileOpFailed, reason)
        }
    }

    /// 改完 / 删完只刷新**那一层**（父目录），不整棵树重来。
    private func reload(parentOf relativePath: String) {
        let parent = (relativePath as NSString).deletingLastPathComponent
        childrenCache[parent] = listChildren(relativePath: parent)
        revision += 1
    }

    // MARK: 内部

    /// 采用一份书签：解析状态 → 取用授权 → 读根目录。
    private func adopt(_ bookmark: DirectoryBookmark) {
        let resolved = MacDirectoryAccess.status(for: bookmark)
        grant?.stopAccessing()
        grant = nil
        childrenCache.removeAll()
        expandedPaths.removeAll()
        loadError = nil

        guard case .granted(let path, _) = resolved else {
            rootURL = nil
            apply(status: resolved, bookmark: bookmark)
            return
        }
        do {
            grant = try MacDirectoryAccess.open(bookmark)
        } catch {
            // 解析得到路径但取用失败：仍然把目录显示出来（非沙箱下这是常态），只记下原因。
            loadError = ErrorPresenter.message(for: error)
        }
        rootURL = URL(fileURLWithPath: path, isDirectory: true)
        childrenCache[""] = listChildren(relativePath: "")
        apply(status: resolved, bookmark: bookmark)
    }

    private func apply(status: DirectoryAccessStatus?, bookmark: DirectoryBookmark?) {
        self.status = status
        if bookmark == nil { self.bookmark = nil }
        revision += 1
        onWorkspaceChanged?(rootURL?.path)
    }

    private func listChildren(relativePath: String) -> [WorkspaceEntry] {
        guard let rootURL else { return [] }
        let directory = relativePath.isEmpty
            ? rootURL
            : WorkspaceTree.resolve(relativePath: relativePath, in: rootURL) ?? rootURL
        do {
            // 传 rootURL 而不是 directory：relativePath 必须**始终相对工作区根**，
            // 它既是展开状态的键、也是路径解析的输入（见 WorkspaceTree.children 的注释）。
            return try WorkspaceTree.children(of: directory, relativeTo: rootURL)
        } catch {
            loadError = ErrorPresenter.message(for: error)
            return []
        }
    }
}
