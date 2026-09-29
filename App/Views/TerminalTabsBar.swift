import SwiftUI
import DoyahCore

/// 终端**页签头**（队列 `L-84` ㈡）—— 落在下方面板工具条的**左侧**。
///
/// 需求原话（2026-09-29）：「其顶部工具条右侧是常见操作按钮，但**左侧应该是空白，可以实现
/// tab 头切换，支持多 terminal 操作**」。所以这一条的位置是拍死的：
/// · **左侧**：四个下方面板页签（问题 / 输出 / 终端 / 调试控制台）之后、`+`（新建）；
/// · **右侧按钮一概不动**（最大化 / 恢复 / 收起 / 清空日志 / 重启 shell）。
///
/// 每个页签头画三样东西：
/// ① **名字** —— 用户重命名 ＞ 前台进程名（`dsh-tui` / `psql` / `zsh`）＞ shell 名 ＞ 兜底词。
///    名字的推导与清洗在 Core（`TerminalTab.title`），这里只管画；
/// ② **退出标记** —— 会话已退出的页签左侧一个警示图标 + 名字变淡，鼠标停上去给出退出码
///    （「已退出（代码 0）」）—— 「这个页签还活着吗」是切页签前最想知道的事；
/// ③ **关闭按钮** —— 前台还有程序在跑时点它会先弹一句确认（判定在 Core，弹窗在 `LowerPaneView`）；
///    **最后一个页签的这个按钮是灰的**（关掉它面板就成了没有内容的空壳，收起面板另有入口），
///    灰着的同时鼠标停上去说明为什么不给点。
///
/// 交互口径（与需求逐条对应）：**单击切换 / 双击重命名**（重名的页签允许 —— 两个 `psql`
/// 会话是两件事）/ **⌘T ⌘W ⌘⇧[ ⌘⇧] ⌘1…9** 走键盘（判定在 Core）。
struct TerminalTabsBar: View {

    @ObservedObject var terminal: TerminalModel

    var body: some View {
        HStack(spacing: Spacing.hair) {
            ForEach(terminal.tabs.tabs) { tab in
                header(tab)
            }
            newTabButton
        }
    }

    // MARK: 单个页签头

    private func header(_ tab: TerminalTab) -> some View {
        let isActive = tab.id == terminal.tabs.activeID
        let detail = terminal.exitedDetail(for: tab)

        return HStack(spacing: Spacing.xs) {
            if tab.isExited {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.status(.warning))
            }

            Text(terminal.title(for: tab))
                .font(Theme.font(.caption))
                .foregroundStyle(tab.isExited ? Theme.text(.secondary) : Theme.text(.primary))
                .lineLimit(1)
                .truncationMode(.middle)
                // 页签头是窄条，名字再长也不许把别的页签挤掉：给它一个宽度上限，
                // 超出的部分省略（完整名字在 tooltip 里）。
                .frame(maxWidth: 140, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)

            // **「已退出」是写出来的字，不是只换个颜色**（口径④：shell 已退出 → 标「已退出」
            // 并可重启）。只用一个图标的话，用户看到的就是「这个页签颜色有点怪」——
            // 读图（`terminal-tabs-bar`）实测过：第一版只有警示图标，看不出「它已经没了」。
            if tab.isExited {
                Text(L(.terminalTabExited))
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.status(.warning))
                    .lineLimit(1)
            }

            closeButton(tab)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? Color.accentColor.opacity(0.16) : Color.clear)
        )
        .contentShape(Rectangle())
        // **双击在前、单击在后**：顺序反了的话第一次点击就被单击手势吃掉，
        // 双击永远不会到达（重命名入口等于没有）。
        .onTapGesture(count: 2) { terminal.beginRename(id: tab.id) }
        .onTapGesture { terminal.select(id: tab.id) }
        .contextMenu {
            Button(L(.terminalTabRename)) { terminal.beginRename(id: tab.id) }
            Button(L(.terminalTabClose)) { terminal.requestClose(id: tab.id) }
        }
        .help(detail.map { "\(terminal.title(for: tab)) · \($0)" } ?? terminal.title(for: tab))
        .accessibilityLabel(tab.isExited ? "\(terminal.title(for: tab)) \(L(.terminalTabExited))" : terminal.title(for: tab))
    }

    private func closeButton(_ tab: TerminalTab) -> some View {
        // 「能不能关」由 Core 判定（`closeDecision`）—— 界面不自己算一遍，
        // 否则「灰着的按钮」与「⌘W 的实际行为」会各说各话。
        let isLast = terminal.tabs.closeDecision(for: tab.id) == .refuse(.lastTab)

        return Button {
            terminal.requestClose(id: tab.id)
        } label: {
            Image(systemName: "xmark")
                // 关页签的叉：与页签标题同字号（`caption`），不自己写死字号 ——
                // 字重交给令牌，避免裸 `.system(size:)`（设计令牌门禁会判红）。
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.text(isLast ? .tertiary : .secondary))
        }
        .buttonStyle(.borderless)
        .disabled(isLast)
        .help(isLast ? L(.terminalTabLastTabHint) : L(.terminalTabClose))
        .accessibilityLabel(L(.terminalTabClose))
    }

    private var newTabButton: some View {
        Button {
            terminal.newTab()
        } label: {
            Image(systemName: "plus")
                .font(Theme.font(.caption))
        }
        .buttonStyle(.borderless)
        .help("\(L(.terminalTabNew))（⌘T）")
        .accessibilityLabel(L(.terminalTabNew))
    }
}
