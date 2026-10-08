import SwiftUI
import DoyahCore

/// 下方面板的**工具条那一行**（队列 `L-84` ㈡ / `L-89` ㈡ ③）—— 从 `LowerPaneView` 里抽出来的**真视图**。
///
/// ## 为什么单独一个视图
///
/// 它原来长在 `LowerPaneView` 的 `tabStrip` 里。抽出来只有一个理由：**这一行必须能被单独渲染**。
/// 「待人工验收清单」里终端多会话那一行（`FR-EDIT-29`）要人肉确认的头两件事，恰恰全是这一行的**版面**：
///
/// ① **页签头在左侧**（需求原话：「顶部工具条右侧是常见操作按钮，但**左侧应该是空白**，可以实现
///    tab 头切换」）—— 而 `LowerPaneView` 整块**渲染不得**：它的内容那半边挂着 `TerminalHostView`，
///    离屏渲染会**真开一条 shell**（见 `TerminalView.layout()` 里那句启动）。于是「工具条长什么样」
///    一直只能靠读源码或让人点。
/// ② **右侧只剩窗口按钮**（最大化 / 恢复 / 折叠，折叠态换成向上的展开箭头）。2026-10-08：`T-1a`
///    把子终端那几件（终端页签条 / 状态小字「已停止 / 出错」/ 重启 shell / 清空日志）移出这一行，
///    `T-1b` 已把它们归位 —— 终端页签条、状态小字、`refusalHint` 进了终端自己的二级条
///    （`App/Views/TerminalSubToolbar.swift`），`trash` 进了问题 / 输出两页的内容顶部
///    （`App/Views/LowerPaneView.swift` 的 `logPaneToolbar`）。**这一行的右侧只剩窗口按钮。**
///
/// 抽出来之后，`TestsUISnapshot/TerminalTabsProbeTests` 能直接渲染**这一行**。
/// （页签头那半边的版面判据自 `T-1b` 起归**终端二级条**（`TerminalSubToolbar`）—— 页签头不在这一行了。）
///
/// ## 边界
///
/// 它是**搬过来的**，不是重画的：正文与 `LowerPaneView` 里那一段逐字相同（视图结构、口径注释、
/// 文案键都没动）。抽出来的只是「挂在哪棵树上」，不是「长什么样」。
struct LowerPaneTabStrip: View {

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var terminal: TerminalModel

    /// **查询页签（可空）** —— 与 `LowerPaneView` 同一条口径（2026-09-30：面板搬到段一级，
    /// 工作区段没有查询上下文）。只有「问题 / 输出」两页与清空按钮会读它。
    let tab: QueryTab?

    /// 实时语法诊断（只有「问题」页签的角标用得上）。
    /// 由 `LowerPaneView` 传进来而不是在这里再算一遍：同一帧里算两次是第二份真相的开头。
    var diagnostics: [SQLDiagnostic] = []

    /// 折叠态：只留标题栏时，右侧那排按钮换成向上的展开箭头。
    var isCollapsed: Bool = false

    var body: some View {
        HStack(spacing: Spacing.hair) {
            // **只画这一档可见的那几枚**（`FR-EDIT-10` 段条件）—— 顺序 / 可见性都取自
            // `AppState.availableLowerPaneTabs`（唯一出处）：Database 段 = 问题 / 输出 / 终端 /
            // 调试控制台 / **历史**；工作区段 = 不含「历史」的那四枚（工作区没有查询上下文）。
            // 这一行**不再自己列举**页签：`ForEach(LowerPaneTab.allCases)` 会让工作区段也画出
            // 「历史」，而段条件写两遍正是它最容易被改坏的地方。
            ForEach(appState.availableLowerPaneTabs) { item in
                tabButton(item)
            }

            // 子终端项（页签条 / 状态小字 / 重启 shell / 清空日志）**不在这一行** ——
            // 它们归终端页签自己的二级工具条（`T-1b` 归位；本片 2026-10-08 先把它们移出外层条）。
            Spacer(minLength: 8)

            if isCollapsed {
                // 折叠态只留一个**向上**的箭头：这是"把它恢复出来"的入口，
                // 必须跟标题栏一起留在屏幕上。
                iconButton("chevron.up", help: L(.lowerPaneExpand)) {
                    appState.isLowerPaneVisible = true
                }
            } else {
                iconButton(
                    appState.isLowerPaneMaximized
                        ? "rectangle.compress.vertical"
                        : "rectangle.expand.vertical",
                    help: appState.isLowerPaneMaximized ? L(.lowerPaneRestore) : L(.lowerPaneMaximize)
                ) {
                    appState.isLowerPaneMaximized.toggle()
                }

                iconButton("chevron.down", help: L(.lowerPaneHide)) {
                    // 收起时同时取消最大化：下次打开回到常规分栏，而不是又占满编辑区。
                    appState.isLowerPaneMaximized = false
                    appState.isLowerPaneVisible = false
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        // **清空 / 单条删除的二次确认**（`DR-02`「可清空 / 单条删除」· 队列 `HIST-2`）。
        //
        // 为什么挂**这一层**（页签条）而不是历史页的内容里 / 也不是 `LowerPaneView`：
        //   · **两个入口都得够得着**：页签里的「清空」与每条右侧的「删除」在内容里，
        //     而工具条时钟菜单那一项（`QueryToolbar.historyMenu`）在**内容之外** ——
        //     挂进内容里，时钟菜单清空时就没有能弹框的宿主（点了没反应）。页签条在
        //     Database 段**始终挂着**（折叠态也只收内容，标题栏含这一行还在）。
        //   · **呈现通道不打架**：`LowerPaneView` 那一层已经挂着两条 `alert`（关页签 / 重命名），
        //     同一视图上再挤一条弹窗，SwiftUI 只保证最后挂的那个弹得出来（该文件里有实测留档）
        //     —— 换一层是这里唯一稳的做法（与终端「重启确认」当年挪进内容层同一个理由）。
        //
        // 动作与顺序由 Core `QueryHistoryRemovalPrompt` 给（**唯一出处**），标题 / 正文由
        // `AppState` 两处生成 —— 界面只负责画（别自己硬写两枚按钮，规则一改就有两处不一致）。
        .confirmationDialog(
            appState.pendingHistoryRemovalTitle ?? "",
            isPresented: Binding(
                get: { appState.pendingHistoryRemoval != nil },
                // 按 ESC / 点框外 = 「取消」：只收掉请求，库一个字节不动。
                set: { presented in if !presented { appState.cancelHistoryRemoval() } }
            ),
            titleVisibility: .visible,
            presenting: appState.pendingHistoryRemoval
        ) { request in
            ForEach(request.actions, id: \.self) { action in
                Button(role: action == .cancel ? .cancel : .destructive) {
                    if action == .cancel {
                        appState.cancelHistoryRemoval()
                    } else {
                        Task { await appState.confirmHistoryRemoval() }
                    }
                } label: {
                    Text(L(QueryHistoryRemovalPrompt.actionTitleKey(action)))
                }
                .help(L(QueryHistoryRemovalPrompt.actionTitleKey(action)))
            }
        } message: { _ in
            if let message = appState.pendingHistoryRemovalMessage { Text(message) }
        }
    }

    // MARK: 下方面板自己的页签（问题 / 输出 / 终端 / 调试控制台，Database 段另加「历史」）

    private func tabButton(_ item: LowerPaneTab) -> some View {
        let isSelected = appState.lowerPaneTab == item
        let badge = problemBadgeCount(for: item)

        return Button {
            appState.lowerPaneTab = item
            // 折叠态点页签 = 想看里面的内容 → 顺手展开（否则点了没反应，又是一次"点了没用"）。
            if isCollapsed { appState.isLowerPaneVisible = true }
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: item.symbolName)
                    .font(Theme.font(.caption))
                Text(L(item.textKey))
                    .font(Theme.font(.caption))
                if badge > 0 {
                    Text("\(badge)")
                        .font(Theme.font(.caption))
                        .padding(.horizontal, 5)  // token-ok：徽标胶囊的实测内边距，设计令牌表没有 5 这一档（加档会牵动全仓棘轮基线）；与抽取前逐字一致
                        .padding(.vertical, 1)  // token-ok：同上，1pt 是胶囊的最小内边距；Spacing 刻度从 2 起，取 2 会改像素
                        .background(Capsule().fill(Theme.status(.danger).opacity(0.85)))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fontWeight(isSelected ? .semibold : .regular)
        .help(L(item.textKey))
    }

    /// 这一行右侧按钮的**唯一画法**（口径①：它们一概不动；一个都不许少）。
    ///
    /// 本行现在画的是**窗口按钮**这一族（最大化 / 恢复 / 折叠，折叠态换成展开箭头），共 3 个调用点。
    /// `Scripts/check-terminal-tabs.py` 的登记表与这里**双向对账**：这里多画一个没登记的按钮，
    /// 或者登记过的按钮被顺手挪走，判据都会点名。子终端那几个动作按钮（清空日志 / 重启 shell）
    /// 随 `T-1a`（2026-10-08）移出本行 —— `T-1b` 已把登记表按**新层级**重算：本行四个窗口符号
    /// （3 个调用点），二级条那一侧另有一条判据（页签头必须在 `Spacer` 之前）。
    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(Theme.font(.caption))
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    /// Problem 页签上的角标：执行错误 + 语法诊断的条数。
    private func problemBadgeCount(for item: LowerPaneTab) -> Int {
        guard item == .problem else { return 0 }
        let errors = (tab?.problemLog ?? []).filter { $0.severity == .error }.count
        return errors + diagnostics.filter { $0.severity == .error }.count
    }
}

// MARK: - 当前页签的状态小字（已随二级条搬走）

/// 原来这里躺着 `TerminalPaneStatus`（「已停止 / 出错」两行小字）。`T-1b`（2026-10-08）把它
/// **搬进了终端页签自己的二级工具条**（`App/Views/TerminalSubToolbar.swift`）—— 它观察的是
/// **会话级**的 `TerminalPane`，「问题 / 输出」两页根本没有会话这回事，所以它不属于外层条。
/// 定义只剩一份（搬走的那一份），这里留个路标，免得下次有人在本文件里再找它。
