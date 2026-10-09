import Foundation

/// 工作区会话快照（`FR-EDIT-43` · 队列 `L-116` · `Q60` 取 B，两片合起来就是完整口径）。
///
/// 重启应用要回到**上次的工作区 + 页签集 + 光标与滚动位置**。
///  · 第一片（`L116-RESTORE-1`）= 页签集 + 上次工作区；
///  · 第二片（`L116-RESTORE-2`）= **插入点偏移**（`Tab.caretOffset`）与**垂直滚动偏移**
///    （`Tab.scrollOffset`）—— 这一片补上了，所以下面那两句「刻意没有」的历史口径不再成立。
///
/// 三条纪律（与需求条款一一对应，都有判据）：
///  ① **编解码 + 版本兼容**：`Codable` 纯逻辑、可单测；`version` 写进文件，读到**比本版本新**的
///     写法就**如实拒绝**（`Failure.unsupportedVersion`）—— 猜着读会把用户的页签洗掉；
///  ② **引用的文件被删 / 改名 ⇒ 如实标「找不到」，不静默丢页签**：页签照样回来，只是点名
///     （`WorkspaceSessionRestore.missingPaths`）；
///  ③ **脏缓冲不静默丢**（契约 ③ · 选项 a）：未保存的内容原样进快照、原样回来，并且**保持脏**
///     —— 界面上那枚「未保存」标记（`App/Views/WorkspaceTabStrip.swift` 的 `isDirty` 圆点，
///     `workspaceDirtyTag`）自己就会亮。
///
/// **为什么选 a（恢复并标注）而不是 b（启动时显式问一次）**：启动那一刻本来就是一串读盘，
/// 再插一个模态框会把「打开应用」变成「先回答一个问题」；a 的代价只是页签上多一枚**本来就有**的
/// 标记（内容照原样回来 ⇒ 页签仍是脏的 ⇒ `workspaceDirtyTag` 那句「未保存」自己就在）。
/// 这个二选一在本片卡片上声明过（选项 a）。
public struct WorkspaceSessionSnapshot: Codable, Sendable, Equatable {

    /// 当前格式版本。**只增不改**：旧字段的含义不许就地改（改了以后，新旧两侧读同一份文件会各读各的）。
    public static let currentVersion = 1

    /// 写入时记下的版本。缺字段（手写 / 更早期的文件）按 `1` 读 —— 见 `init(from:)`。
    public var version: Int

    /// 上次的工作区根目录；`nil` = 上次没选工作区。
    ///
    /// 粒度 = **工作区根**（不是「打开的目录树」里某一个子目录）：本产品一次只握一份工作区授权
    /// （`App/WorkspaceStore.swift` 的「工作区只保留一个」），所以「上次工作区」就是那一个根路径。
    /// **本片只记录它**：重新取用授权、读回书签仍是 `WorkspaceStore` 的既有职责（它有自己的
    /// `workspace-bookmark.json`），这里不重造那条路。
    public var workspacePath: String?

    /// 上次选中的页签在 `tabs` 里的下标（越界 = 当作没记过，落回第一个）。
    public var selectedTabIndex: Int?

    /// **选中那一页的插入点偏移**（`L116-RESTORE-2`）：UTF-16 单元数，与 `NSRange.location`
    /// 同一口径（0 = 文档开头）。`nil` = 没记过（旧快照 / 选中页不是文件 / 没来得及上报）。
    ///
    /// 为什么只记**选中那一页**的现场、而不是每页各记一份：会话恢复的落点是「接着上次往下写」——
    /// 那是**一个**位置（`selectedTabIndex` 指的那一页）。别页的光标位置是「切过去以后的事」，
    /// 记下来只会多出「恢复完一切页签，每页都跳一下」这种没人要的动静。
    public var caretOffset: Int?

    /// **选中那一页的垂直滚动偏移**（`L116-RESTORE-2`）：点，与 `NSScrollView` 的 clip view
    /// 原点同口径。`nil` = 没记过。
    public var scrollOffset: Double?

    public var tabs: [Tab]

    public init(
        version: Int = WorkspaceSessionSnapshot.currentVersion,
        workspacePath: String? = nil,
        selectedTabIndex: Int? = nil,
        caretOffset: Int? = nil,
        scrollOffset: Double? = nil,
        tabs: [Tab] = []
    ) {
        self.version = version
        self.workspacePath = workspacePath
        self.selectedTabIndex = selectedTabIndex
        self.caretOffset = caretOffset
        self.scrollOffset = scrollOffset
        self.tabs = tabs
    }

    /// 一页的存档形态。
    public struct Tab: Codable, Sendable, Equatable {
        /// `nil` = **Home 欢迎页**（与 `WorkspaceTab.path` 同一口径）。
        public var path: String?
        /// 标题。Home 页的标题由调用点从语言表取（Core 不认识语言表），所以这里必须存下来。
        public var title: String
        /// 语言标识（`TextLanguage.rawValue`）—— 存标识而不是整个定义：语言表才是知识的唯一出处。
        public var language: String
        /// **只在有未保存改动时**才带这一栏（脏缓冲不静默丢）。
        ///
        /// 干净页签**不带内容**：它的内容以**盘上的文件**为准，快照里再存一份只会存出一个
        /// 「陈旧副本」（文件被别人改了，恢复出来的却是几天前的样子）。这条口径与
        /// `Core/WorkspaceHistory.swift` 的「不存内容」同源。
        public var unsavedContent: String?

        public init(path: String?, title: String, language: String, unsavedContent: String? = nil) {
            self.path = path
            self.title = title
            self.language = language
            self.unsavedContent = unsavedContent
        }

        /// 从活页签取存档形态。
        public init(_ tab: WorkspaceTab) {
            self.init(
                path: tab.path,
                title: tab.title,
                language: tab.language.rawValue,
                unsavedContent: tab.isDirty ? tab.content : nil
            )
        }
    }

    /// 认不出的快照（**如实说，不静默当成空会话** —— 那会把用户的页签洗掉）。
    public enum Failure: Error, Equatable {
        /// 文件比本版本新：本片认不出它的写法，不猜。
        case unsupportedVersion(Int)
    }

    // MARK: 编码 / 解码

    private enum CodingKeys: String, CodingKey {
        case version, workspacePath, selectedTabIndex, tabs, caretOffset, scrollOffset
    }

    /// **版本兼容的读法**：`version` 缺字段（更早的手写文件、或将来裁掉的栏位）按 `1` 读；
    /// 其余字段一律 `decodeIfPresent`，缺了按「没记过」处理 —— 把「文件里少了一栏」当成
    /// 解码失败去炸掉整个会话，代价比少恢复一栏大得多。
    ///
    /// 这里也是**旧快照（第一片那份只有页签集、没有光标 / 滚动两栏）读取不崩**的落点：
    /// 两栏缺席 ⇒ `nil` ⇒ 恢复时**不把光标拽到任何地方**（而不是当成 0 把光标顶到开头）。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        workspacePath = try container.decodeIfPresent(String.self, forKey: .workspacePath)
        selectedTabIndex = try container.decodeIfPresent(Int.self, forKey: .selectedTabIndex)
        tabs = try container.decodeIfPresent([Tab].self, forKey: .tabs) ?? []
        caretOffset = try container.decodeIfPresent(Int.self, forKey: .caretOffset)
        scrollOffset = try container.decodeIfPresent(Double.self, forKey: .scrollOffset)
    }

    /// 从字节解码并**判版本**（比本版本新 ⇒ `Failure.unsupportedVersion`）。
    ///
    /// 为什么单开一个入口而不只给 `JSONDecoder().decode(...)`：版本这一关**必须**有人把，
    /// 否则「新写法的文件被旧程序读」这件事就只剩注释在管。
    public static func decode(from data: Data) throws -> WorkspaceSessionSnapshot {
        let snapshot = try JSONDecoder().decode(WorkspaceSessionSnapshot.self, from: data)
        guard snapshot.version <= currentVersion else {
            throw Failure.unsupportedVersion(snapshot.version)
        }
        return snapshot
    }

    // MARK: 拍快照

    /// 把当前页签集拍成快照（**纯函数**：不落盘、不看文件系统）。
    ///
    /// `caretOffset` / `scrollOffset` 是**选中那一页**编辑器现场的读数（UTF-16 偏移 / 点），
    /// 由调用方（`WorkspaceTabsModel.saveSession()`）从编辑器上报里取。**只对选中页记**
    /// —— 没有选中页（空集 / 选中项已不在）时这一栏如实空着，不编一个位置出来。
    public static func capture(
        tabs: [WorkspaceTab],
        selectedID: UUID?,
        workspacePath: String?,
        caretOffset: Int? = nil,
        scrollOffset: Double? = nil
    ) -> WorkspaceSessionSnapshot {
        var snapshot = WorkspaceSessionSnapshot(
            workspacePath: workspacePath,
            tabs: tabs.map(Tab.init)
        )
        // 选中项记成**下标**：页签的身份（`WorkspaceTab.id`）是每次启动现生成的 UUID，
        // 存进文件下次也对不上（那才是「恢复了但选不中」的静默错位）。
        if let selectedID, let index = tabs.firstIndex(where: { $0.id == selectedID }) {
            snapshot.selectedTabIndex = index
            // 光标 / 滚动与「哪一页」是同一件事的三面：选中页认不出来时它们也没有归属。
            snapshot.caretOffset = caretOffset
            snapshot.scrollOffset = scrollOffset
        }
        return snapshot
    }

    // MARK: 恢复

    /// 从快照恢复页签集（**纯函数**，除读盘之外不碰外界）。
    ///
    /// 这个入口走**真实文件系统**；要造「文件没了」的用例就传一个假读盘面（下面那个重载）。
    ///
    /// 每一页的去向（三条路都不静默）：
    ///  · 盘上读得出 ⇒ 内容取**盘上的**（干净页签以文件为权威）；
    ///  · 读不出 ⇒ 页签**照样回来**，并进 `missingPaths`（如实标「找不到」，不丢页签）；
    ///  · 有未保存内容 ⇒ 内容取**快照里的**，并进 `unsavedPaths`（回来后仍是脏的）。
    ///
    /// **边界如实写在这里**：找不到的页签回来时是**空文本**、`path` 仍指着原来那个位置 ——
    /// 于是用户按 ⌘S 会在那个路径上写出一个空文件（「页签不丢」的另一面）。界面怎么处置
    /// （提示另存 / 置成不可写）不在本片。
    public static func restore(from snapshot: WorkspaceSessionSnapshot) -> WorkspaceSessionRestore {
        restore(from: snapshot, readFile: readText(at:))
    }

    /// `readFile` 是**注入的读盘面**：给路径、给盘上的文本；`nil` = 这一页拿不到盘上的内容
    /// （不存在 / 已被改名 / 目录 / 二进制 / 读不出）。
    public static func restore(
        from snapshot: WorkspaceSessionSnapshot,
        readFile: (String) -> String?
    ) -> WorkspaceSessionRestore {
        var result = WorkspaceSessionRestore(workspacePath: snapshot.workspacePath)

        for stored in snapshot.tabs {
            let language = language(of: stored)
            guard let path = stored.path else {
                // Home 页：标题随快照（拍快照那一刻从语言表取的），没有对应文件。
                result.tabs.append(WorkspaceTab(title: stored.title, language: language))
                continue
            }

            let onDisk = readFile(path)
            if onDisk == nil { result.missingPaths.append(path) }

            let content: String
            if let unsaved = stored.unsavedContent {
                content = unsaved
                result.unsavedPaths.append(path)
            } else {
                // 读不出就没有盘上的内容可用（空文本），页签仍是那一页 —— 不是「静默丢掉」。
                content = onDisk ?? ""
            }

            result.tabs.append(
                WorkspaceTab(
                    title: WorkspaceTabSet.title(for: path),
                    path: path,
                    language: language,
                    content: content,
                    // 「上次存盘时的内容」= **现在盘上的内容**：于是有未保存内容的那一页回来仍是脏的
                    // （界面上那枚「未保存」标记自己会亮），没有未保存内容的那一页回来是干净的。
                    savedContent: onDisk ?? ""
                )
            )
        }

        // 选中的下标越界（手改过的文件 / 页签数变了）⇒ 落回第一个，不猜。
        if let index = snapshot.selectedTabIndex, result.tabs.indices.contains(index) {
            result.selectedTabID = result.tabs[index].id
            // 插入点 / 滚动：**只有选中的是文件页签**才给落脚点（Home 没有编辑器）。
            // 越界的偏移一律**夹进文档范围**——「记下来的位置」与「恢复后的文档」长度不一定一致
            // （文件在两次启动之间被改短了），原样塞给 `setSelectedRange` 会让光标静默跳到别处
            // 或者干脆不动（两种都是「恢复了但不对」，比不恢复更难查）。
            if !result.tabs[index].isHome {
                if let caret = snapshot.caretOffset {
                    result.caretOffset = clampCaret(caret, in: result.tabs[index].content)
                }
                if let scroll = snapshot.scrollOffset {
                    result.scrollOffset = clampScroll(scroll)
                }
            }
        } else {
            result.selectedTabID = result.tabs.first?.id
        }
        return result
    }

    /// **插入点落脚点**（纯函数）：负数 → 0；超出文档 → 文档末尾。
    ///
    /// 口径与 `NSRange.location` 一致（UTF-16 单元），所以用 `content.utf16.count` 量文档长度
    /// —— 用 `count`（字素簇）在中文 / emoji 上是**另一个数**，会把光标停在实际字符中间。
    public static func clampCaret(_ offset: Int, in content: String) -> Int {
        min(max(0, offset), content.utf16.count)
    }

    /// **滚动落脚点**（纯函数）：负数 → 0。上界不在这里判 —— 文档高度由 `NSScrollView` 按
    /// 排版结果自己夹（`Core` 不量排版），这里只管「不给出一个倒退的滚动位置」。
    public static func clampScroll(_ offset: Double) -> Double {
        max(0, offset)
    }

    /// 语言：认标识（登记表里有这一条就用它）；认不出（快照比本版本新 / 表里删过一条）
    /// ⇒ 按路径重判，判不出是纯文本。**不静默编一个看起来像语言的东西。**
    private static func language(of stored: Tab) -> TextLanguage {
        if let language = TextLanguage(rawValue: stored.language) { return language }
        guard let path = stored.path else { return .plainText }
        return TextLanguage.detect(path: path)
    }

    /// 默认读盘面：与 `WorkspaceTabsModel.openFile(at:)` 同一套判决（非 UTF-8 走 `TextFileDecoder`；
    /// 看起来是二进制就不当文本）。读不出的一律 `nil` —— 在「恢复」这条路上，它们的共同结局
    /// 都是「这一页拿不到盘上的内容」，由调用方如实报出来。
    private static func readText(at path: String) -> String? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)), !data.contains(0) else {
            return nil
        }
        return try? TextFileDecoder.decode(data).text
    }
}

/// 恢复出来的东西（从快照还原，还没接到界面那一层）。
public struct WorkspaceSessionRestore: Sendable, Equatable {
    /// 恢复出来的页签集（次序与快照一致）。
    public var tabs: [WorkspaceTab] = []
    /// 该选中的那一页（快照里的下标 → 新页签的 id；越界落回第一个；空集为 `nil`）。
    public var selectedTabID: UUID?
    /// 上次的工作区根目录（原样带回来）。
    public var workspacePath: String?
    /// **选中那一页的插入点落脚点**（已经夹进恢复后文档的范围）。`nil` = 快照里没这一栏 /
    /// 选中页是 Home —— 这时**不许**把光标拽到任何地方（拽到 0 是「恢复了但跳到开头」的假恢复）。
    public var caretOffset: Int?
    /// **选中那一页的滚动落脚点**（已夹成 ≥ 0）。`nil` = 没记过。
    public var scrollOffset: Double?
    /// 引用的文件**找不到**了（已删 / 已改名 / 读不出）—— 这些页签**仍然在 `tabs` 里**。
    public var missingPaths: [String] = []
    /// 带着**未保存改动**回来的页签（内容原样恢复，且仍是脏的）。
    public var unsavedPaths: [String] = []

    public init(
        tabs: [WorkspaceTab] = [],
        selectedTabID: UUID? = nil,
        workspacePath: String? = nil,
        caretOffset: Int? = nil,
        scrollOffset: Double? = nil,
        missingPaths: [String] = [],
        unsavedPaths: [String] = []
    ) {
        self.tabs = tabs
        self.selectedTabID = selectedTabID
        self.workspacePath = workspacePath
        self.caretOffset = caretOffset
        self.scrollOffset = scrollOffset
        self.missingPaths = missingPaths
        self.unsavedPaths = unsavedPaths
    }
}

/// 会话快照的落盘（`FR-EDIT-43`）。
///
/// 与「最近打开」「浏览器页签」「工作区书签」同一套路：**一个 JSON、按需读写、坏了不致命**，
/// 落在 `~/Library/Application Support/DoyahStudio/workspace-session.json`（同一个目录，
/// 与 `workspace-history.json` / `browser-tabs.json` 并列）。文件名按同一家族的命名法取名。
///
/// **没有快照**（第一次启动）⇒ `load()` 给 `nil`，不是错误；**文件坏了** ⇒ **抛错**
/// （调用方如实告诉用户，不静默当成「没有上次会话」—— 那样用户会以为页签丢了，其实是文件坏了）。
public struct WorkspaceSessionStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// 默认位置：应用数据目录下的 `workspace-session.json`。
    public static func standard(applicationSupport: URL? = nil) -> WorkspaceSessionStore {
        let base = applicationSupport ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return WorkspaceSessionStore(
            fileURL: base
                .appendingPathComponent(DoyahIdentity.applicationSupportDirectoryName, isDirectory: true)
                .appendingPathComponent("workspace-session.json", isDirectory: false)
        )
    }

    /// 读取；文件不存在或空文件（写到一半断电）视为**没有快照**。
    public func load() throws -> WorkspaceSessionSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return nil }
        return try WorkspaceSessionSnapshot.decode(from: data)
    }

    /// 写入（原子替换；目录不存在时先建）。
    public func save(_ snapshot: WorkspaceSessionSnapshot) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(snapshot).write(to: fileURL, options: .atomic)
    }

    /// 丢掉快照（用户主动清会话时用）。
    public func clear() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}
