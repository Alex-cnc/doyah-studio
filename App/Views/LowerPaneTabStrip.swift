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
/// ② **右侧那排按钮一个不少**（最大化 / 恢复 / 收起 / 重启 shell，问题与输出态还有清空日志）。
///
/// 抽出来之后，`TestsUISnapshot/TerminalTabsProbeTests` 能直接渲染**这一行**：
/// 页签从 1 个变成 3 个时，**左半部分必须变、右半部分必须逐像素不变** ——
/// 这正是「页签头在左、右侧按钮位置不动」的机器判据（判据写在那个探针里）。
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
            ForEach(LowerPaneTab.allCases) { item in
                tabButton(item)
            }

            if appState.lowerPaneTab == .terminal {
                // 终端多会话（L-84 ㈡）：**页签头落在工具条左侧** ——
                // 四个下方面板页签之后、右侧那排按钮之前。
                // 需求原话（2026-09-29）：「其顶部工具条右侧是常见操作按钮，但**左侧应该是空白，
                // 可以实现 tab 头切换**，支持多 terminal 操作」⇒ 右侧那排按钮**一概不动**。
                Divider().frame(maxHeight: 14).padding(.horizontal, Spacing.xs)
                TerminalTabsBar(terminal: terminal)
            }

            Spacer(minLength: 8)

            if appState.lowerPaneTab == .problem || appState.lowerPaneTab == .output {
                iconButton("trash", help: L(.lowerPaneClear)) {
                    // 工作区段（无查询页签）没有可清的日志 —— 按钮如实无效，不假装清掉了什么。
                    if let tab { appState.clearLowerPaneLog(for: tab.id) }
                }
            }

            if appState.lowerPaneTab == .terminal {
                // 「这一步做不了」的说法（当前只有一种：**最后一个页签不许关**）。
                // 为什么要有这一行：⌘W 在最后一个页签上什么都不会发生 —— 静默无反应会被读成
                // 「这个软件的 ⌘W 坏了」（Core 只给枚举理由，人话在这里）。
                if let refusalHint = terminal.refusalHint {
                    Text(refusalHint)
                        .font(Theme.font(.caption))
                        .foregroundStyle(Theme.status(.warning))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 320, alignment: .trailing)
                        .help(refusalHint)
                }
                // 当前页签的「已停止 / 出错」两行小字。观察的是 **pane 自己**（会话级的
                // @Published），所以拆成一个小视图 —— 协调器不必把每个页签的字段都镜像一遍。
                TerminalPaneStatus(pane: terminal.activePane)
                iconButton("arrow.clockwise", help: L(.terminalRestart)) {
                    // **作用在当前页签上**：多会话之后「重启」不再指向唯一那个终端。
                    terminal.restart(
                        id: terminal.tabs.activeID,
                        columns: terminal.activePane.screen.columns,
                        rows: terminal.activePane.screen.rows
                    )
                }
            }

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
    }

    // MARK: 下方面板自己的四个页签

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

    /// 右侧那排按钮的**唯一画法**（口径①：它们一概不动；一个都不许少）。
    ///
    /// `Scripts/check-terminal-tabs.py` 的登记表与这里**双向对账**：这里多画一个没登记的按钮，
    /// 或者登记过的按钮被顺手挪走，判据都会点名 —— 「五个动作按钮一个不少」不是靠人眼看。
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

// MARK: - 当前页签的状态小字

/// 工具条右侧那两行小字：**已停止 / 出错**。
///
/// 为什么单独一个小视图：这两件事是**会话级**的（`TerminalPane` 自己的 `@Published`），
/// 而工具条观察的是面板级模型（`TerminalModel`）。用小视图直接把 pane 观察起来，
/// 协调器就不必把每个页签的 `isRunning` / `errorText` 再镜像一份 —— 镜像就是第二份真相。
///
/// 它与工具条同行，所以随工具条一起搬到这个文件（口径与版面都是一体的）。
struct TerminalPaneStatus: View {
    @ObservedObject var pane: TerminalPane

    var body: some View {
        HStack(spacing: Spacing.xs) {
            if !pane.isRunning {
                Text(L(.terminalStopped))
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.status(.warning))
            }
            if let errorText = pane.errorText {
                Text(errorText)
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.status(.danger))
                    .lineLimit(1)
            }
        }
    }
}
