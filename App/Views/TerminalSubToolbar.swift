import SwiftUI
import DoyahCore

/// 终端页签**自己**的二级工具条（人类主人 2026-10-08 原话）——
/// 「terminal 页签自己的，也就是在 terminal 页签下再来一个工具条，**左侧是每个细分 terminal 的
/// title**，右侧是常用的工具按钮，比如一键启动 `dsh-tui`、Hermes，清除终端会话窗口内容，重启终端」。
///
/// ## 层级（T-1a → T-1b）
///
/// · **外层**页签条（`LowerPaneTabStrip`）：四个下方面板页签 + **只剩窗口按钮**（最大化 / 恢复 /
///   折叠，折叠态换成向上的展开箭头）。子终端那几件（终端页签条 / 状态小字 / 重启 shell /
///   清空日志）由 `T-1a`（2026-10-08）移出，**本片不再让它们回到这一行**。
/// · **二级**条（本视图）：挂在终端内容**顶部**。左侧 = 每个细分 terminal 的 title
///   （`TerminalTabsBar`，原有视图，本片只是搬家）；右侧 = 终端自己的动作按钮位 + 当前页签的
///   状态小字。动作按钮由 `T-2` 填（一键 `dsh-tui` / 一键 Hermes / 清除会话内容 / 重启终端）。
///
/// ## 为什么单独一个视图
///
/// 与 `LowerPaneTabStrip`（第 96 轮）/ `ObjectTreeToolbar`（第 101 轮）**同一个理由**：
/// **能单独离屏渲染**。它长在 `LowerPaneView` 的 `.terminal` 内容顶部，而 `LowerPaneView` 整块
/// 渲染不得 —— 内容那半边挂着 `TerminalHostView`，一渲染就**真开一条 shell**。
/// 所以「二级条长什么样」只能靠这个独立视图拍（判据 `check-terminal-tabs.py` 的锚点也随之落到这里）。
///
/// ## 边界
///
/// **不动 PTY / 屏幕模型，也不另开窗口**：这一条是**搬过来的**，会话仍旧活在 `TerminalPane` 上，
/// 切页签 / 折叠 / 最大化都不重启它（`TerminalView` 那一侧的口径一条没动）。
struct TerminalSubToolbar: View {

    @EnvironmentObject private var terminal: TerminalModel

    var body: some View {
        HStack(spacing: Spacing.hair) {
            // **左侧**：每个细分 terminal 的 title（页签头 + `+` 新建）。
            // 位置是这一片的判据：页签头必须排在 `Spacer` **之前**（在右半边 = 挂到动作按钮那侧了）。
            TerminalTabsBar(terminal: terminal)

            Spacer(minLength: 8)

            // ── 右侧：终端自己的动作按钮位 ───────────────────────────────────────────
            // `T-2` 在这里补四枚（一键 `dsh-tui` / 一键 Hermes / 清除终端会话窗口内容 / 重启终端）。
            // **不许静默消失**（`T-1a` 移出的五件里，本片负责交代它们的去向）：
            //   · 终端页签条 `TerminalTabsBar` → 本行左侧（本片已归位）；
            //   · 状态小字 `TerminalPaneStatus` 与 `terminal.refusalHint` → 本行右侧（本片已归位，见下）；
            //   · `arrow.clockwise`（重启 shell）→ `T-2` 的四枚之一（重启终端），本片留位；
            //   · `trash`（清空日志）→ **不属于终端**：它作用在问题 / 输出两页的日志上，
            //     已归位到那两页的**内容顶部**（`LowerPaneView.logPaneToolbar`）。
            if let refusalHint = terminal.refusalHint {
                // 「这一步做不了」的说法（当前只有一种：**最后一个页签不许关**）——
                // ⌘W 在最后一个页签上什么都不会发生，静默无反应会被读成「⌘W 坏了」。
                Text(refusalHint)
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.status(.warning))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 320, alignment: .trailing)
                    .help(refusalHint)
            }
            // 当前页签的「已停止 / 出错」两行小字（观察的是 **pane 自己**的 `@Published`）。
            TerminalPaneStatus(pane: terminal.activePane)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

// MARK: - 当前页签的状态小字

/// 终端二级条右侧那两行小字：**已停止 / 出错**。
///
/// 为什么单独一个小视图：这两件事是**会话级**的（`TerminalPane` 自己的 `@Published`），
/// 而工具条观察的是面板级模型（`TerminalModel`）。用小视图直接把 pane 观察起来，
/// 协调器就不必把每个页签的 `isRunning` / `errorText` 再镜像一份 —— 镜像就是第二份真相。
///
/// 它随这一条一起从 `LowerPaneTabStrip.swift` 搬来（`T-1b`，2026-10-08）：口径与版面是一体的，
/// 从前它在**外层**条上，现在它只属于终端页签的二级条（问题 / 输出两页没有「会话」这件事）。
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
