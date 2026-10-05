import SwiftUI
import DoyahCore

// MARK: - 终端面板（多会话）= 协调器

/// **整个下方面板**的终端状态：有几个页签、哪个是当前、每个页签的会话在哪。
///
/// 需求（队列 `L-84`，需求提出者 2026-09-29 提为刚需）原话：「底部 terminal 目前只支持单终端，
/// 其顶部工具条右侧是常见操作按钮，但**左侧应该是空白，可以实现 tab 头切换，支持多 terminal
/// 操作**。我经常遇到这种需求：一个 terminal 在执行 dsh-tui，遇到要执行命令只能去开系统终端，
/// **违背了我这个软件的初衷**」。
///
/// ## 这里放什么、不放什么
///
/// · **判定全在 Core**（`Core/TerminalTabs.swift`）：新页签插在哪、关掉当前谁接管、
///   `⌘1…9` 落到谁头上、标题怎么回落、最后一个能不能关、按键怎么解析成动作 —— 那边有 27+ 项单测；
/// · **本类只做三件事**：① 把判定结果变成真的会话（每页签一条 PTY）；
///   ② 让界面与按键有个统一入口；③ 把「Core 说不行」翻成人话（语言表）。
/// · **会话活在这里，不在视图里**（这是㈠ 定下的契约：折叠 / 最大化 / 切语言 / 窗口重排
///   **不许重启会话**）。切页签只改 `tabs.activeID`，`TerminalPane`（连同它的 `TerminalSession`）
///   一直在字典里 —— 视觉上换了一屏，进程一个没动。
///
/// ## 命名
///
/// 本类叫 `TerminalModel`（面板级），单个页签是 `TerminalPane`（`App/TerminalPane.swift`）。
/// 两个名字分开是有意的：**「切到第二个终端」这句话里，被切的不是模型，是当前页签**。
@MainActor
final class TerminalModel: ObservableObject {

    /// 页签集合（Core 的纯逻辑值类型；顺序 / 归属 / 关闭判定都在那边）。
    @Published private(set) var tabs: TerminalTabs

    /// 双击页签头进来的重命名目标（nil = 没在重命名）。
    @Published var renamingTab: Int?

    /// 重命名输入框的内容。
    ///
    /// 放在这里而不是视图的 `@State`：双击发生在**页签头**（`TerminalTabsBar`），
    /// 弹窗挂在 `LowerPaneView` 上 ——拼在模型里，两边就不用靠 `onChange` 传值。
    @Published var renameDraft: String = ""

    /// 关闭页签前的**二次确认**目标（nil = 没有待确认的关闭）。
    /// 界面（`LowerPaneView`）拿它弹一句「里面还有程序在跑」，确认后才真的关。
    @Published var pendingCloseTab: Int?

    /// 「这一步做不了」的说法（当前只有一种：最后一个页签不许关）。
    ///
    /// 为什么要有一句说法：`⌘W` 在最后一个页签上**什么都不会发生** —— 静默无反应会被读成
    /// 「这个软件的 ⌘W 坏了」。Core 那边只给出**枚举理由**（`TerminalTabCloseRefusal`），
    /// 人话在这里翻（R-45：Core 不出用户可见文案）。
    @Published private(set) var refusalHint: String?

    /// 每个页签自己的会话（页签 id → pane）。
    private var panes: [Int: TerminalPane]

    /// 前台进程名的轮询（页签标题的来源）。
    ///
    /// 为什么是轮询而不是事件：前台是谁**没有事件可订**（`psql` 起没起来、`dsh-tui` 退没退，
    /// 系统不会通知我们）。一秒一次、每个活着的页签两次系统调用（`tcgetpgrp` + `proc_pidpath`），
    /// 代价可以忽略；不轮询的话标题会一直停在「开页签那一刻」的样子。
    private var titleTimer: Timer?

    /// 工作区路径（`FR-EDIT-32`）：终端启动目录以它为准。
    /// 说明：**只在启动那一刻读取**（与单终端时一致）—— 已经跑起来的 shell 不会被搬走。
    var workspacePath: String? {
        didSet {
            guard workspacePath != oldValue else { return }
            for pane in panes.values { pane.workspacePath = workspacePath }
        }
    }

    // MARK: 生命周期

    /// 首建：**一个页签、它就是当前页签**（= 需求口径⑥「首个页签 = 现状」）。
    init(columns: Int = 80, rows: Int = 24) {
        let shell = TerminalSession.defaultShell()
        let tabs = TerminalTabs(shellPath: shell)
        let first = TerminalPane(columns: columns, rows: rows)
        self.tabs = tabs
        self.panes = [tabs.activeID: first]
        wire(first, to: tabs.activeID)
        startTitlePolling()
    }

    /// 当前页签的会话（视图拿它画网格）。
    var activePane: TerminalPane { pane(for: tabs.activeID) }

    /// 某个页签的会话。
    ///
    /// 字典里没有就**现造一个**：界面可能拿到一个刚被别处关掉的 id（或单测 / 快照里
    /// 直接按 id 取），这时「给一个空会话」比崩掉好 —— 页签集合有 Core 兜着，
    /// 不变量不靠这里维持。
    func pane(for id: Int) -> TerminalPane {
        if let pane = panes[id] { return pane }
        let pane = TerminalPane()
        pane.workspacePath = workspacePath
        wire(pane, to: id)
        panes[id] = pane
        return pane
    }

    /// 把页签 id 与它自己的会话绑起来（谁退出、退到哪个页签上，只有这里知道）。
    private func wire(_ pane: TerminalPane, to id: Int) {
        pane.workspacePath = workspacePath
        pane.onExitDetected = { [weak self] code in
            self?.markExited(id: id, code: code)
        }
    }

    private func startTitlePolling() {
        guard titleTimer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            // 定时器挂在主运行循环上，这里就是主线程；`assumeIsolated` 把这件事告诉编译器
            // （而不是 `DispatchQueue.main.async` 那样再排一次队、白等一圈）。
            MainActor.assumeIsolated { self?.refreshForegroundProcesses() }
        }
        RunLoop.main.add(timer, forMode: .common)
        titleTimer = timer
    }

    /// 页签标题的唯一来源：问每个活着的会话「现在谁在前台」，回填给 Core。
    ///
    /// 查不到就回填 nil —— Core 那时不给标题、界面用语言表里的兜底词。
    /// **不编名字**：编出来的名字会让用户以为那个会话真的是它在跑。
    func refreshForegroundProcesses() {
        for tab in tabs.tabs where !tab.isExited {
            guard let pane = panes[tab.id] else { continue }
            let path = pane.foregroundProcessPath()
            if path != tab.foregroundProcess {
                _ = tabs.setForegroundProcess(path, for: tab.id)
            }
        }
    }

    // MARK: 页签操作（按键 / 菜单 / 点击都收敛到这里）

    /// 新建页签（`⌘T` 与页签条上的「+」）。
    @discardableResult
    func newTab() -> Int {
        let id = tabs.newTab()
        let pane = TerminalPane()
        wire(pane, to: id)
        panes[id] = pane
        refusalHint = nil
        return id
    }

    /// 切换（点击页签头 / `⌘1…9` / `⌘⇧[ ⌘⇧]`）。
    func select(id: Int) {
        guard tabs.select(id: id) else { return }
        refusalHint = nil
    }

    @discardableResult
    func select(numbered number: Int) -> Bool {
        let ok = tabs.select(numbered: number)
        if ok { refusalHint = nil }
        return ok
    }

    func selectNext() { _ = tabs.selectNext(); refusalHint = nil }

    func selectPrevious() { _ = tabs.selectPrevious(); refusalHint = nil }

    /// 执行一个动作（`TerminalHostView.keyDown` 把按键解析成动作后调进来）。
    func perform(_ command: TerminalTabCommand) {
        switch command {
        case .closeTab:
            // 关闭**先过判定**：前台还有程序在跑就先问一句（判定与确认都在下面两条里）。
            requestClose(id: tabs.activeID)
        case .newTab:
            newTab()
        default:
            _ = tabs.perform(command)
            refusalHint = nil
        }
    }

    // MARK: 关闭（判定 → 确认 → 收摊）

    /// 请求关闭某个页签：能关就关、要问就问、不许关就给一句说法。
    func requestClose(id: Int) {
        switch tabs.closeDecision(for: id) {
        case .canClose:
            close(id: id)
        case .needsConfirmation:
            refusalHint = nil
            pendingCloseTab = id
        case .refuse(let reason):
            pendingCloseTab = nil
            switch reason {
            case .lastTab:
                refusalHint = L(.terminalTabLastTabHint)
            case .unknownTab:
                // 页签已经不在了（用户点的是一个刚被别处关掉的 id）：
                // 页签条这一帧就没有它了 —— 界面本身就是反馈，不另编一句话。
                refusalHint = nil
            }
        }
    }

    /// 用户在确认框里点了「关闭页签」。
    ///
    /// `force: true` —— 他已经在那一句上点过「关闭页签」了，这一趟必须真的关
    /// （判定依旧要确认的话就会变成「点了没反应」，第 82 轮探针实测过这个坑）。
    func confirmClose() {
        guard let id = pendingCloseTab else { return }
        pendingCloseTab = nil
        close(id: id, force: true)
    }

    /// 用户在确认框里点了「取消」。
    func cancelClose() { pendingCloseTab = nil }

    /// 真的关：Core 允许之后才动手，并把这条会话收干净（`stop` 会 SIGHUP 整个进程组）。
    private func close(id: Int, force: Bool = false) {
        guard tabs.close(id: id, force: force) else { return }
        panes[id]?.stop()
        panes.removeValue(forKey: id)
        refusalHint = nil
    }

    /// 页签里的一条会话退出了（由 `TerminalPane.onExitDetected` 回调进来）。
    func markExited(id: Int, code: Int32?) {
        _ = tabs.markExited(id: id, code: code)
    }

    // MARK: 名字

    /// 双击页签头 → 进入重命名（**用当前名字预填**：不预填的话用户得先删掉旧名字）。
    func beginRename(id: Int) {
        guard let tab = tabs.tab(id: id) else { return }
        renameDraft = title(for: tab)
        renamingTab = id
    }

    /// 双击页签头 → 改完名。空串 = 清除重命名，标题回落到前台进程名（口径在 Core）。
    func rename(id: Int, to raw: String) {
        _ = tabs.rename(id: id, to: raw)
        renamingTab = nil
        refreshForegroundProcesses()
    }

    /// 页签头显示的名字：**用户重命名 ＞ 前台进程名 ＞ shell 名 ＞ 兜底词**。
    /// 前三级在 Core（可单测），最后一级是这里给人话（Core 不出用户可见文案）。
    func title(for tab: TerminalTab) -> String {
        tab.title ?? L(.terminalTabUntitled)
    }

    /// 退出码的说法（`已退出（代码 0）`）；会话在跑 = nil。
    func exitedDetail(for tab: TerminalTab) -> String? {
        guard case .exited(let code) = tab.state else { return nil }
        guard let code else { return L(.terminalTabExited) }
        return L(.terminalTabExitedCode, String(code))
    }

    // MARK: 重启（工具条右侧那个按钮，作用在**当前页签**上）

    /// 重启某个页签的 shell（同一个页签换一条命：id 与名字都留着）。
    func restart(id: Int, columns: Int, rows: Int) {
        pane(for: id).restart(columns: columns, rows: rows)
        _ = tabs.markLive(id: id)
        refusalHint = nil
    }
}
