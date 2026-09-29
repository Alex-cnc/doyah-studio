import Foundation

/// 终端页签标题的推导与清洗（队列 L-84 / `FR-EDIT-29`「多会话」这一半的唯一出处）。
///
/// 口径三条（都有单测）：
/// 1. **标题取前台进程名**，不是「终端 1 / 终端 2」—— 用户开多个页签是为了让它们干**不同的活**
///    （`dsh-tui` / `psql` / `zsh`），编号对他没有信息量。
/// 2. **认不出就没有标题**（返回 nil），兜底词由界面从语言表取 —— 不拿路径或空串硬凑一个
///    看着像名字的东西（R-45：Core 不出用户可见文案）。
/// 3. **清洗在 Core 做、只做一次**：标题要画进单行窄条，所以换行 / 制表 / 连续空白一律收成
///    一个空格、控制字符丢掉、超长截断 —— 否则页签头会被撑破或出现竖排。
public enum TerminalTabTitle {
    /// 标题长度上限（页签头是窄条：超出部分对用户没价值，还会把别的页签挤掉）。
    public static let maxLength = 28
    /// 超长时补的省略号。
    static let ellipsis = "…"

    /// 从可执行文件路径推标题：`/bin/zsh` → `zsh`；`-zsh`（login shell）→ `zsh`。
    /// 拿不到可用名字（空串 / 只有分隔符）时返回 nil。
    public static func derive(fromExecutablePath path: String?) -> String? {
        guard let path else { return nil }
        // 只取最后一段（`/usr/local/bin/dsh-tui` → `dsh-tui`）；`/` 这种没有段的一律认不出。
        guard let last = path.split(separator: "/").last else { return nil }
        // login shell 的可执行名带前导短横（`-zsh`）：那是会话类型标记，不是进程名的一部分。
        let trimmed = String(last).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return sanitize(trimmed)
    }

    /// 清洗一个候选标题（前台进程名与用户重命名**共用这一条**）：
    /// 空白收成一个空格、丢掉控制字符、去首尾空白、超长截断；洗不出东西来返回 nil。
    public static func sanitize(_ raw: String) -> String? {
        var collapsed: [Character] = []
        var pendingSpace = false
        for character in raw {
            if character.isNewline || character.isWhitespace {
                if !collapsed.isEmpty { pendingSpace = true }
                continue
            }
            // 控制字符与格式字符（ESC / DEL / 方向控制那一族）直接丢：它们画不出来，
            // 只会把页签头弄乱 —— 而被丢掉的字符**不能**顶替一个空格（否则标题会莫名变宽）。
            if let scalar = character.unicodeScalars.first {
                let category = scalar.properties.generalCategory
                if category == .control || category == .format { continue }
            }
            if pendingSpace {
                collapsed.append(" ")
                pendingSpace = false
            }
            collapsed.append(character)
        }
        guard let first = collapsed.firstIndex(where: { $0 != " " }),
              let last = collapsed.lastIndex(where: { $0 != " " }) else { return nil }
        let cleaned = collapsed[first...last]
        guard cleaned.count > maxLength else { return String(cleaned) }
        return String(cleaned.prefix(maxLength - 1)) + ellipsis
    }
}

/// 一个终端页签**与 PTY 无关**的那一半状态。
///
/// 刻意只放「界面要展示、逻辑要判断」的字段：屏幕缓冲、PTY 句柄、环境都在 App / Platform 侧，
/// 这样这个类型能在单测里穷举（真开 shell 的路径无法在闭环里每条都跑）。
public struct TerminalTab: Identifiable, Equatable, Sendable {

    /// 会话状态。
    public enum State: Equatable, Sendable {
        /// 会话在跑。
        case live
        /// shell 已退出（界面标「已退出」并给重启入口）；拿不到退出码时 `code` 是 nil。
        case exited(code: Int32?)
    }

    /// 页签标识：**单调递增**，关掉中间的页签也不重号
    /// （重号会让「切到第 3 个」指到另一个会话，而用户看到的是「我明明切的是它」）。
    public let id: Int
    /// 这个页签启动的 shell（兜底标题 + 判断「前台的到底是不是 shell 自己」）。
    public let shellPath: String
    /// 用户重命名（nil = 用前台进程名）。
    /// 写入口只有 `TerminalTabs.rename`（`internal(set)`：Core 之外的模块只能读）。
    public internal(set) var customTitle: String?
    /// 前台进程的**可执行路径**（由 PTY 侧查询后回填；查不到就是 nil）。
    public internal(set) var foregroundProcess: String?
    /// 会话状态。
    public internal(set) var state: State

    public init(
        id: Int,
        shellPath: String,
        foregroundProcess: String? = nil,
        customTitle: String? = nil,
        state: State = .live
    ) {
        self.id = id
        self.shellPath = shellPath
        self.foregroundProcess = foregroundProcess
        self.customTitle = customTitle
        self.state = state
    }

    /// 页签上显示的名字：用户重命名 ＞ 前台进程名 ＞ shell 名；三者都拿不到就是 nil
    /// （界面用语言表里的兜底词，Core 不出用户可见文案）。
    public var title: String? {
        customTitle
            ?? TerminalTabTitle.derive(fromExecutablePath: foregroundProcess)
            ?? TerminalTabTitle.derive(fromExecutablePath: shellPath)
    }

    /// 当前名字是不是用户自己起的（界面可据此把「我来起名」的入口收起来）。
    public var isRenamed: Bool { customTitle != nil }

    /// shell 已经退出。
    public var isExited: Bool {
        if case .exited = state { return true }
        return false
    }

    /// 前台跑的是不是 **shell 自己**（真 = 关掉这个页签没什么可丢的）。
    ///
    /// **查不到前台进程时也判「是 shell 自己」**：判据不许把「不知道」当成「有程序在跑」——
    /// 那会让每次关闭都弹一次确认，用户三下之后就闭眼点「关」（保护反而失效）。
    /// 真正的保护来自两处事实：会话已退出（`state`）与前台进程名推出来的结论。
    public var isShellInForeground: Bool {
        guard let name = TerminalTabTitle.derive(fromExecutablePath: foregroundProcess) else { return true }
        return name == TerminalTabTitle.derive(fromExecutablePath: shellPath)
    }
}

/// 关闭页签的判定 —— 界面拿它决定「直接关」还是「先问一句」。
public enum TerminalTabCloseDecision: Equatable, Sendable {
    /// 前台就是 shell 本身（或会话已退出）→ 直接关。
    case canClose
    /// 前台是别的程序（`dsh-tui` / `psql` / `vim` …）→ 先确认。
    case needsConfirmation
    /// 不许关（见 `TerminalTabCloseRefusal`）。
    case refuse(TerminalTabCloseRefusal)
}

/// 不许关闭的理由（写全，界面照原话给用户一个说法；不许静默无反应）。
public enum TerminalTabCloseRefusal: Equatable, Sendable {
    /// **最后一个页签不许关**：关掉它，这块面板就成了一块没有内容的空壳，
    /// 而「把终端收起来」这件事本来就有专门的入口（收起面板）——
    /// 关页签的语义是「销毁这个会话」，不该顺手把面板也变空。
    case lastTab
    /// 页签不存在（界面拿的是过期的 id：会话已被别人关掉）。
    case unknownTab
}

/// 终端面板的**页签集合** —— 纯逻辑（不碰 PTY、不碰界面）。
///
/// 为什么单独一个值类型：多会话的坑几乎全在**顺序与归属**上 —— 新页签插在哪、
/// 关掉当前页签之后谁接管、⌘1…9 落到哪个会话、重命名之后标题怎么回落、最后一个能不能关。
/// 这些判断**不需要真开一个 shell 就能穷举**；留在视图里就只能靠手点（`FR-EDIT-29` 的判据
/// 明确要求「Core 纯逻辑单测：会话集合的新建 / 关闭 / 切换 / 标题推导 / 关闭确认判定」）。
///
/// 口径（与需求提出者 2026-09-29 的口径逐条对应，见队列 `L-84`）：
/// · **首个页签 = 现状**（`init(shellPath:)` 建一个，行为与单终端时一致）；
/// · 新页签插在**当前页签右侧**并激活它（iTerm / VS Code 的惯例：连续开出来的页签挨着，
///   而不是飞到最右边）；
/// · 关闭当前页签后，**右邻居接管**，没有右邻居就**左邻居**接管（永远不留「没有当前页签」的状态）；
/// · ⌘1…9 按**显示顺序**（1 基）取，越界不动（不是环绕：按错了不该跳到一个你没想到的会话）；
/// · ⌘⇧[ / ⌘⇧] 是**环绕**的（页签就那几个，来回绕比记住边界有用）。
public struct TerminalTabs: Equatable, Sendable {

    /// 全部页签（**按显示顺序**）。
    public private(set) var tabs: [TerminalTab]
    /// 当前页签的 id（**永远是 `tabs` 里真实存在的那个**：所有写入口都维持这条不变量）。
    public private(set) var activeID: Int
    /// 下一个新页签的号（单调递增，见 `TerminalTab.id`）。
    private var nextID: Int

    /// 首建：一个页签、它就是当前页签（= 需求口径⑥「首个页签 = 现状，行为不变」）。
    public init(shellPath: String) {
        self.tabs = [TerminalTab(id: 1, shellPath: shellPath)]
        self.activeID = 1
        self.nextID = 2
    }

    public var count: Int { tabs.count }

    /// 当前页签在 `tabs` 里的下标。
    public var activeIndex: Int { index(of: activeID) ?? 0 }

    /// 当前页签。
    public var activeTab: TerminalTab { tabs[activeIndex] }

    /// 某个 id 的下标（不存在 = nil）。
    public func index(of id: Int) -> Int? {
        tabs.firstIndex { $0.id == id }
    }

    /// 某个 id 的页签（不存在 = nil）。
    public func tab(id: Int) -> TerminalTab? {
        index(of: id).map { tabs[$0] }
    }

    /// 全部 id（按显示顺序）—— 界面按 `⌘1…9` 显示序号、单测核对顺序时用。
    public var ids: [Int] { tabs.map(\.id) }

    // MARK: 新建 / 切换

    /// 新建页签：插在**当前页签右侧**并激活，返回新页签的 id。
    /// `shellPath` 缺省沿用当前页签的 shell（同一个面板里的会话用同一个 shell）。
    @discardableResult
    public mutating func newTab(shellPath: String? = nil, foregroundProcess: String? = nil) -> Int {
        let id = nextID
        nextID += 1
        let tab = TerminalTab(
            id: id,
            shellPath: shellPath ?? activeTab.shellPath,
            foregroundProcess: foregroundProcess
        )
        tabs.insert(tab, at: activeIndex + 1)
        activeID = id
        return id
    }

    /// 切到某个 id（不存在 = 不动、返回 false）。
    @discardableResult
    public mutating func select(id: Int) -> Bool {
        guard index(of: id) != nil else { return false }
        activeID = id
        return true
    }

    /// ⌘1…9：按**显示顺序**切（1 基）；越界或页签不存在 = 不动、返回 false。
    @discardableResult
    public mutating func select(numbered number: Int) -> Bool {
        guard number >= 1, number <= tabs.count else { return false }
        activeID = tabs[number - 1].id
        return true
    }

    /// ⌘⇧]：下一个（**环绕**）；只有一个页签 = 不动、返回 false。
    @discardableResult
    public mutating func selectNext() -> Bool {
        select(offset: 1)
    }

    /// ⌘⇧[：上一个（**环绕**）；只有一个页签 = 不动、返回 false。
    @discardableResult
    public mutating func selectPrevious() -> Bool {
        select(offset: -1)
    }

    private mutating func select(offset: Int) -> Bool {
        guard tabs.count > 1 else { return false }
        let target = (activeIndex + offset + tabs.count) % tabs.count
        activeID = tabs[target].id
        return true
    }

    // MARK: 名字

    /// 重命名（双击页签头进来的那条路）。
    /// 口径：**重名允许**（两个 `psql` 会话是两件事，硬去重只会让用户没法叫出自己想叫的名字）；
    /// 洗不出东西来（空串 / 全空白）**等于清除重命名**，标题回落到前台进程名。
    @discardableResult
    public mutating func rename(id: Int, to raw: String) -> Bool {
        guard let index = index(of: id) else { return false }
        tabs[index].customTitle = TerminalTabTitle.sanitize(raw)
        return true
    }

    /// 前台进程变了（PTY 侧查询后回填）—— 标题随之变化，但**用户重命名优先**。
    @discardableResult
    public mutating func setForegroundProcess(_ path: String?, for id: Int) -> Bool {
        guard let index = index(of: id) else { return false }
        tabs[index].foregroundProcess = path
        return true
    }

    // MARK: 状态

    /// shell 退出了。
    @discardableResult
    public mutating func markExited(id: Int, code: Int32?) -> Bool {
        guard let index = index(of: id) else { return false }
        tabs[index].state = .exited(code: code)
        return true
    }

    /// 重启之后回到「在跑」（同一个页签换了一条命，id 与名字都留着）。
    @discardableResult
    public mutating func markLive(id: Int) -> Bool {
        guard let index = index(of: id) else { return false }
        tabs[index].state = .live
        return true
    }

    // MARK: 关闭

    /// 关这个页签要不要先问一句（**只判，不改**：确认对话框在界面侧）。
    public func closeDecision(for id: Int) -> TerminalTabCloseDecision {
        guard let tab = tab(id: id) else { return .refuse(.unknownTab) }
        guard tabs.count > 1 else { return .refuse(.lastTab) }
        // 会话已经退出：里面没有东西可丢，直接关（哪怕前台进程名还没被清掉）。
        if tab.isExited { return .canClose }
        return tab.isShellInForeground ? .canClose : .needsConfirmation
    }

    /// 关闭页签（界面在 `closeDecision` 允许 / 用户确认之后调）。
    /// 关掉的若是当前页签，**右邻居接管**、没有右邻居则左邻居接管；
    /// 关不掉（最后一个 / id 不存在）时**集合一个字节都不动**并返回 false。
    @discardableResult
    public mutating func close(id: Int) -> Bool {
        guard case .canClose = closeDecision(for: id) else { return false }
        guard let index = index(of: id) else { return false }
        tabs.remove(at: index)
        if id == activeID {
            let next = min(index, tabs.count - 1)
            activeID = tabs[next].id
        }
        return true
    }
}
