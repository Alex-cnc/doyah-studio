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
    /// **「一键启动」带出来的名字**（nil = 这个页签不是一键启动建的）。
    ///
    /// 为什么要有它（2026-10-08 实测）：二级条那两枚「一键启动」跑的是 `dsh-tui` / `hermes`，
    /// 而这两个都是**解释器启动器**（`#!/usr/bin/env node` / `exec … python3`）——
    /// 前台进程组的可执行路径查到的是 `node` / `python3`，照它推出来的标题是 `node`。
    /// 用户点那枚按钮是为了跑 `dsh-tui`，页签上写着 `node` 是**错误的名字**。
    /// 所以名字由**点的哪一枚**决定，而不是等前台进程猜。
    /// 它与 `customTitle` 是两件事：用户改名仍然优先（那是他自己起的名字）。
    public internal(set) var launchTitle: String?
    /// 前台进程的**可执行路径**（由 PTY 侧查询后回填；查不到就是 nil）。
    public internal(set) var foregroundProcess: String?
    /// 会话状态。
    public internal(set) var state: State

    public init(
        id: Int,
        shellPath: String,
        foregroundProcess: String? = nil,
        customTitle: String? = nil,
        launchTitle: String? = nil,
        state: State = .live
    ) {
        self.id = id
        self.shellPath = shellPath
        self.foregroundProcess = foregroundProcess
        self.customTitle = customTitle
        self.launchTitle = launchTitle
        self.state = state
    }

    /// 页签上显示的名字：用户重命名 ＞ 一键启动的名字 ＞ 前台进程名 ＞ shell 名；都没有就是 nil
    /// （界面用语言表里的兜底词，Core 不出用户可见文案）。
    public var title: String? {
        customTitle
            ?? launchTitle
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

/// **「一键启动」的两个预设**（人类主人 2026-10-08 原话：「右侧是常用的工具按钮，比如一键启动
/// dsh-tui、Hermes」）。
///
/// 为什么这两个名字在 Core 而不在视图里：它们同时是**要敲进 shell 的那一行**、**新页签的标题**
/// 与**门禁 / 探针要核对的字面量** —— 三处各写一遍，其中一处改了名（`dsh-tui` → `dshtui`）
/// 另外两处照样是绿的，而按钮点下去就开始报「command not found」。判定与字面量放在一起，
/// 与页签的其它口径同一个理由：能穷举的东西不留两层。
public enum TerminalLaunchCommand: String, CaseIterable, Sendable {
    /// 一键启动 `dsh-tui`（鲸鱼 TUI）。
    case dshTUI = "dsh-tui"
    /// 一键启动 `hermes`（Hermes Agent CLI）。
    case hermes = "hermes"

    /// 送进 shell 的那一行：命令 + 一个换行（= 用户在提示符上敲完回车）。
    public var inputLine: String { rawValue + "\n" }

    /// 新页签的标题 —— **预设名直接给**。
    ///
    /// 为什么不等前台进程名（本机实测，2026-10-08）：`dsh-tui` 与 `hermes` 都是**解释器启动器**
    /// （`dsh-tui` 是 `#!/usr/bin/env node`、`hermes` 是 `exec … python3`），
    /// 真跑起来之后前台进程组的可执行路径查到的是 `node` / `python3` ——
    /// 照它推标题，页签上写的就是 `node`。名字见 `TerminalTab.launchTitle`。
    public var tabTitle: String { rawValue }
}

/// 重启页签的判定 —— 界面拿它决定「直接重启」还是「先问一句」。
public enum TerminalTabRestartDecision: Equatable, Sendable {
    /// 会话已经退出（或页签已经不在）→ 里面没有东西可丢，直接重启。
    case canRestart
    /// 会话在跑 → 重启要 SIGHUP 整条进程组 ⇒ **先问一句**（人类主人 2026-10-08 口径：
    /// 不许把「重启终端」做成静默杀进程）。
    case needsConfirmation
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

/// 一次按键解析出来的**页签动作**（队列 L-84 ㈡ 的口径②：「新建 ⌘T / 关闭 ⌘W /
/// 切换（点击 · ⌘⇧[ ⌘⇧] · ⌘1…9）」）。
///
/// 为什么连「按键 → 动作」也放 Core：界面里的 `keyDown` 只拿得到一堆标志位
/// （`charactersIgnoringModifiers` + `shift`），而**哪个组合算哪个动作**是纯逻辑 ——
/// 里面还埋着一个真坑：**⇧⌘[ 在美式键盘上给的是 `{`**（`charactersIgnoringModifiers`
/// 会把 ⇧ 一起作用到字符上），照 `[` 去比就永远不匹配。这类判断写在视图里就只能靠手按，
/// 放在这里可以被单测穷举（`Tests/TerminalTabsTests.swift` 的「按键映射」组）。
public enum TerminalTabCommand: Equatable, Sendable {
    /// ⌘T：新建页签（插在当前页签右侧并激活）。
    case newTab
    /// ⌘W：关闭当前页签（最后一个页签不许关 —— 判定在 `closeDecision`）。
    case closeTab
    /// ⌘1…9：按显示顺序直选（1 基；越界不动）。
    case selectTab(number: Int)
    /// ⌘⇧]：下一个（环绕）。
    case nextTab
    /// ⌘⇧[：上一个（环绕）。
    case previousTab
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
    /// `launchTitle` 给「一键启动」那两枚用（名字由点的哪一枚决定，见 `TerminalTab.launchTitle`）。
    @discardableResult
    public mutating func newTab(
        shellPath: String? = nil,
        foregroundProcess: String? = nil,
        launchTitle: String? = nil
    ) -> Int {
        let id = nextID
        nextID += 1
        let tab = TerminalTab(
            id: id,
            shellPath: shellPath ?? activeTab.shellPath,
            foregroundProcess: foregroundProcess,
            launchTitle: launchTitle
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

    // MARK: 按键 → 动作（㈡ 的界面接线只负责把按键交进来）

    /// 把一次按键解析成页签动作；**认不出返回 nil**（键继续往下走，交给前台程序）。
    ///
    /// 口径（逐条有单测）：
    /// · **必须按住 ⌘**，且**不许带 ⌥ / ⌃** —— 终端里的 ⌥ 是「把鼠标还给本机」那一族、
    ///   ⌃ 是控制键（⌃W 要原样发给 shell 删词），被页签抢走就是坏功能；
    /// · ⇧ 只与 `[` `]` 组合：**同时认 `{` `}`**（美式键盘上 ⇧⌘[ 实际给的是 `{`，
    ///   这是实测过的坑，见 `TerminalTabCommand` 的说明）；
    /// · ⇧ + 其它键（⇧⌘T / ⇧⌘W / ⇧⌘1）**一律不认** —— ⇧⌘T 已经归「数据任务」，
    ///   页签不许偷别人的键；
    /// · 数字只认 1…9（⌘0 不动、⌘⇧3 这类截图键更不许碰）。
    public static func command(
        key: String,
        command: Bool,
        shift: Bool,
        option: Bool = false,
        control: Bool = false
    ) -> TerminalTabCommand? {
        guard command, !option, !control else { return nil }
        if shift {
            switch key {
            case "]", "}": return .nextTab
            case "[", "{": return .previousTab
            default: return nil
            }
        }
        switch key {
        case "t": return .newTab
        case "w": return .closeTab
        default:
            guard let number = Int(key), (1...9).contains(number) else { return nil }
            return .selectTab(number: number)
        }
    }

    /// 执行一个动作（界面把按键 / 菜单 / 点击都收敛到这里）。
    ///
    /// **只做「判定已经允许」的那一步**：`closeTab` 走的是 `close(id:)` ——
    /// 前台还有程序在跑时它**什么都不做并返回 false**（先问一句是界面的事，
    /// 判定与确认的入口是 `closeDecision(for:)`）；最后一个页签同样返回 false，
    /// 界面据此给用户一句说法，不许静默无反应。
    @discardableResult
    public mutating func perform(_ command: TerminalTabCommand) -> Bool {
        switch command {
        case .newTab:
            newTab()
            return true
        case .closeTab:
            return close(id: activeID)
        case .selectTab(let number):
            return select(numbered: number)
        case .nextTab:
            return selectNext()
        case .previousTab:
            return selectPrevious()
        }
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

    // MARK: 重启

    /// 重启这个页签要不要先问一句（**只判，不改**：确认对话框在界面侧）。
    ///
    /// 口径（与 `closeDecision` 同一个形状，但**没有** `force:` 那一套）：重启不是「销毁会话」——
    /// 页签 id / 名字 / 位置都留着，用户确认一次就够，不需要第二条判定；
    /// 会话**已经退出**时也不用问（里面没有东西可丢）。
    public func restartDecision(for id: Int) -> TerminalTabRestartDecision {
        guard let tab = tab(id: id) else { return .canRestart }
        return tab.isExited ? .canRestart : .needsConfirmation
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
    ///
    /// - Parameter force: **用户已经在确认框里点过「关闭页签」**。
    ///
    ///   为什么必须有这个形参（第 82 轮 App 侧探针实测出来的缺口）：㈠ 只建模了**判定**
    ///   （`needsConfirmation`），没建模「确认之后怎么走」—— 于是接线时 `confirmClose()`
    ///   再调一次 `close(id:)`，判定**依旧**是要确认 ⇒ 用户点了「关闭页签」而页签**关不掉**
    ///   （探针当场判红：`pendingCloseTab` 清掉了、集合里那一个还在）。
    ///   一个布尔就够：它把「问过了、答案是关」这件事带进核心。
    ///
    ///   注意 `force` **不是万能钥匙**：最后一个页签、不存在的 id 仍然关不掉 ——
    ///   那不是「确认一下就能解决」的事（前者要的是「收起面板」这个入口）。
    @discardableResult
    public mutating func close(id: Int, force: Bool = false) -> Bool {
        switch closeDecision(for: id) {
        case .canClose:
            break
        case .needsConfirmation where force:
            break
        case .needsConfirmation, .refuse:
            return false
        }
        guard let index = index(of: id) else { return false }
        tabs.remove(at: index)
        if id == activeID {
            let next = min(index, tabs.count - 1)
            activeID = tabs[next].id
        }
        return true
    }
}
