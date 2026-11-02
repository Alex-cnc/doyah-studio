import Foundation

/// 工作区页签（FR-EDIT-35 / 36）。
///
/// **为什么不复用 `QueryTab`**：`QueryTab` 是 SQL 专用（`sql` / `connectionID` / `results` /
/// 事务态 / 执行状态…）。把"打开一个 JS 文件"塞进它，等于给一个已经承担执行语义的结构再加一套
/// 完全无关的状态 —— 最后会变成一个谁都不敢改的万能类。所以工作区页签**另起类型**，
/// 与 `QueryTab` 并列，各自演进。
public struct WorkspaceTab: Identifiable, Sendable, Equatable {

    /// 页签的种类（`FR-AI-25` ①）：**对话页签是 Home 区页签条上的一种**，不是新开一个侧栏 / 分栏。
    public enum Kind: String, Sendable, Equatable, CaseIterable {
        /// Home 欢迎页（工作区的落脚点）。
        case home
        /// 文件页。
        case file
        /// 智能体对话页签。
        case agentChat
        /// 图片页（`FR-STD-WS-FS-008` ①）：**不进文本编辑器**，由图片查看器呈现。
        /// 它没有 `content`（图片不是文本），因此永远不是「脏」的。
        case image
    }

    public let id: UUID
    /// 页签标题（文件页 = 文件名；**Home 页由调用点从语言表取** —— `L(.workspaceTabHome)` → 中文「首页」/ 英文 `Home`。
    /// Core 不认识语言表（`L(_:)` 在 App 侧），所以这里**不写死任何文案**）。
    public var title: String
    /// 文件路径；`nil` = **Home 欢迎页或对话页签**（后者看 `kind`）。
    public var path: String?
    public var language: TextLanguage
    /// 当前内容。
    public var content: String
    /// 上次读盘 / 存盘时的内容 —— `dirty` 由它俩比出来，不额外维护一个布尔（布尔迟早与内容不一致）。
    public var savedContent: String
    /// 种类。**由既有字段推出来**：`path == nil` ⇒ Home，否则文件页；
    /// 对话页签是显式传入的第三种（老调用点一个字都不用改）。
    public var kind: Kind
    /// 这一页的**缩进口径**（`FR-STD-WS-EDIT-022`）：打开时按内容判定，用户可以改（改过的不再被覆盖）。
    /// 状态栏显示它、编辑器的 Tab 与自动缩进用它 —— 三处读同一格，不各判一次。
    public var indent: IndentProfile

    /// 这一页**在会话内**的折叠状态（`FR-STD-WS-EDIT-017` ③）。
    ///
    /// 为什么挂在页签上：需求要的是「切到别的文件再回来仍保持」。页签就是"这份文件在本次会话里
    /// 的那一份"（`openAsText` 按路径去重 ⇒ 一个文件只有一页），所以状态住这里既不丢、
    /// 也不会串到别的文件上。**新打开的页签一律全展开** —— 一进来就是折的会让人以为文件短了一截。
    public var folds: FoldState

    /// 这一页的**打开形态**（编码 + 换行 + BOM，`FR-STD-WS-EDIT-023`）：保存时按它写回，
    /// 状态栏按它显示、菜单按它改。**住页签上**而不是每次保存现读盘一眼：
    /// 用户在状态栏把编码切到 GB18030 之后，那个选择就是这一页现在的事实。
    public var format: TextFileFormat

    /// 上一次存盘时的形态（= 盘上那份文件的形态）。与 `format` 比出「形态改过还没存」，
    /// 与 `savedContent` 比出「内容改过还没存」—— 两者合起来才是「这一页有未保存改动」。
    /// 少了这一半，用户切了编码却看不到任何"未保存"的提示，关页签时那份改动就悄悄没了。
    public var savedFormat: TextFileFormat

    public init(id: UUID = UUID(), title: String, path: String? = nil, language: TextLanguage,
                content: String = "", savedContent: String? = nil, kind: Kind? = nil,
                indent: IndentProfile = .fallback, folds: FoldState = FoldState(),
                format: TextFileFormat = .utf8LF, savedFormat: TextFileFormat? = nil) {
        self.id = id
        self.title = title
        self.path = path
        self.language = language
        self.content = content
        self.savedContent = savedContent ?? content
        self.kind = kind ?? (path == nil ? .home : .file)
        self.indent = indent
        self.folds = folds
        self.format = format
        self.savedFormat = savedFormat ?? format
    }

    /// 是不是 Home 欢迎页（**注意：对话页签不是它**）。
    public var isHome: Bool { kind == .home }

    /// 是不是对话页签（`FR-AI-25`）。
    public var isAgentChat: Bool { kind == .agentChat }

    /// 是不是图片页（`FR-STD-WS-FS-008` ①）。
    ///
    /// 用它而不是 `language == .image`：那是一句「按语言身份分支」，
    /// 正是 `FR-EDIT-38` ① 要清掉的形状（门禁 A 档会判红）。种类是页签自己的事实。
    public var isImage: Bool { kind == .image }

    /// 有未保存改动。
    ///
    /// **内容或形态任一不同都算脏**（`FR-STD-WS-EDIT-023`）：用户只把编码从 UTF-8 切到
    /// GB18030、一个字都没改，那一页也必须在关页签时被问一句 —— 否则"编码切换"这个动作
    /// 会随页签一起无声消失。
    public var isDirty: Bool { content != savedContent || format != savedFormat }

    /// 形态改过但还没存（状态栏那行据此说"保存后生效"）。
    public var hasPendingFormatChange: Bool { format != savedFormat }


    /// 打开一个文件页签。
    ///
    /// **缩进口径在打开这一刻按内容判定**（`FR-STD-WS-EDIT-022`）：`WorkspaceTab.file` 是「打开文件」
    /// 的唯一入口（双击、右键「以源码打开」、CLI 都走它）⇒ 口径只算一次、也不算第二次。
    ///
    /// **打开形态由调用点从字节算好传进来**（`FR-STD-WS-EDIT-023`）：这里只拿到已经归一到 LF 的文本，
    /// 编码与 BOM 只有看过字节的人知道。缺省 UTF-8 · LF · 无 BOM（新建文件 / 认不出时）。
    public static func file(path: String, content: String, format: TextFileFormat = .utf8LF) -> WorkspaceTab {
        WorkspaceTab(
            title: WorkspaceTabSet.title(for: path),
            path: path,
            language: TextLanguage.detect(path: path),
            content: content,
            indent: IndentProfile.detect(in: content),
            format: format
        )
    }

    /// Home 页签（工作区的落脚点）。
    ///
    /// **标题由调用点传入**：Core 里不许出现展示文案 —— 之前这里写死 `"Home"`，中文界面也显示 Home（`L-108`）。
    public static func home(title: String) -> WorkspaceTab {
        WorkspaceTab(title: title, language: .plainText, kind: .home)
    }

    /// 对话页签（`FR-AI-25` ①）。标题同样由调用点从语言表取。
    public static func agentChat(title: String) -> WorkspaceTab {
        WorkspaceTab(title: title, language: .plainText, kind: .agentChat)
    }

    /// 图片页签（`FR-STD-WS-FS-008` ①）：有路径、没有文本。
    ///
    /// **内容留空、`format` 取缺省**，于是 `isDirty` 恒为假（图片没有「未保存的编辑」这回事）：
    /// 关页签时不会被问「要不要保存」，也不会写盘。语言标识取登记表里那一条
    /// （`TextLanguage.detect` 会把它判成 `.image`，两处同一个事实）。
    public static func image(path: String) -> WorkspaceTab {
        WorkspaceTab(
            title: WorkspaceTabSet.title(for: path),
            path: path,
            language: TextLanguage.detect(path: path),
            kind: .image
        )
    }

    /// 存盘成功：把"已保存内容"与"已保存形态"一起对齐到当前值。
    ///
    /// 两样一起对齐是硬要求：只对内容不对形态 ⇒ 用户切了编码再保存，页签仍然是脏的（永远存不掉）；
    /// 只对形态不对内容 ⇒ 那才是真正的漏存。
    public mutating func markSaved() {
        savedContent = content
        savedFormat = format
    }
}

/// 工作区页签集合的**规则**（纯函数，可单测）。
public enum WorkspaceTabSet {

    /// 页签栏上显示的名字 = 路径最后一段。
    public static func title(for path: String) -> String {
        let name = (path as NSString).lastPathComponent
        return name.isEmpty ? path : name
    }

    /// 打开对话页签：**已经有就复用**（同一个对话开成两个页签 = 两条流各写各的，用户会看花眼）。
    /// 与 `opening(path:…)` 同一条纪律。
    public static func openingAgentChat(title: String,
                                        in tabs: [WorkspaceTab]) -> (tabs: [WorkspaceTab], selected: UUID) {
        if let existing = tabs.first(where: { $0.isAgentChat }) {
            return (tabs, existing.id)
        }
        let tab = WorkspaceTab.agentChat(title: title)
        return (tabs + [tab], tab.id)
    }

    /// 打开一个文件：
    /// - 已经开着 → **复用**（选中它），不重复开；
    /// - 没开过 → 追加到末尾并选中。
    ///
    /// 为什么"复用"是硬规则：同一个文件开成两个页签，改一边、存另一边，
    /// 是这类编辑器最经典的丢改动方式。
    public static func opening(path: String, in tabs: [WorkspaceTab], content: String,
                               format: TextFileFormat = .utf8LF) -> (tabs: [WorkspaceTab], selected: UUID) {
        if let existing = tabs.first(where: { $0.path == path }) {
            return (tabs, existing.id)
        }
        let tab = WorkspaceTab.file(path: path, content: content, format: format)
        return (tabs + [tab], tab.id)
    }

    /// 打开一张图片（`FR-STD-WS-FS-008` ①）：与文本文件同一条去重纪律 —— 同一个路径
    /// **只许一页**（开成两页的话「关一页」与「切回去」会给出不同答案）。
    public static func openingImage(path: String, in tabs: [WorkspaceTab]) -> (tabs: [WorkspaceTab], selected: UUID) {
        if let existing = tabs.first(where: { $0.path == path }) {
            return (tabs, existing.id)
        }
        let tab = WorkspaceTab.image(path: path)
        return (tabs + [tab], tab.id)
    }

    /// 关闭一个页签：Home **关不掉**（它是工作区的落脚点，关了就没有默认页了）。
    public static func closing(id: UUID, in tabs: [WorkspaceTab]) -> [WorkspaceTab] {
        tabs.filter { $0.id != id || $0.isHome }
    }

    /// 选中项在关闭之后落到谁身上：优先它右边那个，没有就左边，都没有就返回 nil。
    public static func selection(afterClosing id: UUID, in tabs: [WorkspaceTab], selected: UUID?) -> UUID? {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return selected }
        let remaining = closing(id: id, in: tabs)
        if remaining.contains(where: { $0.id == selected ?? id }) { return selected }
        if remaining.isEmpty { return nil }
        let fallback = min(index, remaining.count - 1)
        return remaining[fallback].id
    }

    // MARK: 改名之后页签跟着走（`FR-STD-WS-FS-005` ①）

    /// 把落在 `oldPath` 底下（含整棵子树）的路径改写成 `newPath` 底下；不在其中回 `nil`。
    ///
    /// 两条必须是纯字符串判断、且**带分隔符**：
    ///   - `newPath` 原样给出（不改大小写、不标准化 —— 那是文件系统的事，Core 不猜）；
    ///   - 前缀比较必须带上 `/`，否则改名 `a.txt` 会把 `a.txt2` 那条页签一起搬走
    ///     （这类「差一个字符」的误伤在页签上是静默的：标题变了、路径指向一个不存在的文件）。
    public static func retargetedPath(_ path: String, from oldPath: String, to newPath: String) -> String? {
        if path == oldPath { return newPath }
        let prefix = oldPath.hasSuffix("/") ? oldPath : oldPath + "/"
        guard path.hasPrefix(prefix) else { return nil }
        let tail = String(path.dropFirst(prefix.count))
        guard !tail.isEmpty else { return newPath }
        return newPath.hasSuffix("/") ? newPath + tail : newPath + "/" + tail
    }

    /// 改名之后页签要跟着走：**路径与标题一起换**，而内容 / 脏标记 / 标识一个都不动。
    ///
    /// 为什么标识不能重发（`WorkspaceTab` 的 `id` 保持原样）：重发一个新 `id` 等于「关掉旧的再开新的」，
    /// 选中项、滚动位置、撤销栈全断 —— 而用户只是改了个文件名。
    public static func retargeting(tabs: [WorkspaceTab], from oldPath: String, to newPath: String) -> [WorkspaceTab] {
        tabs.map { tab in
            guard let path = tab.path,
                  let updated = retargetedPath(path, from: oldPath, to: newPath)
            else { return tab }
            var copy = tab
            copy.path = updated
            copy.title = title(for: updated)
            return copy
        }
    }
}
