import SwiftUI
import DoyahCore

/// 输入框上方的「任务清单」= 执行步骤详单（人类主人 2026-10-17：「DSH-tui 那个任务清单也挺好，
/// 用户可以看到你正在执行到哪一步了」）。
///
/// ## 为什么单拎成一个视图（2026-11-04 真机事故的回归面）
///
/// 旧实现把步骤行**直接摊进对话页的 `VStack`**：既没有高度上限、也没有内部滚动。
/// 跑满几百跳之后这一块把对话区与输入框整体顶出可视区 —— 人类主人的原话是
/// 「点击了一下这个地方，界面全被执行步骤详单给撑爆了」（截图里整块工作区只剩一串
/// `search · search · list_dir · read_file…`）。
///
/// ## 2026-11-06 第二轮（真机仍在长高）
///
/// 数字上限（168pt ≈ 12 行）只挡住了「几百步」，没挡住**设计要求**：这一块按设计
/// **最多 2 行**（`collapsedRows`）。上一版的收起态也还在按「跑着就铺行」长到 12 行，
/// 于是对话区（thinking / 正文）的可视高度随着步数一路缩水
/// （人类主人：「This task 这个区域的高度越来越高，按设计是只能保持最多 2 行」）。
///
/// 现在的分工写死在这里：
/// · **表头一行** + **收起态最多 `collapsedRows`（=2）行**，整块高度是**常量**
///   `collapsedHeight`（≈ 68pt）—— 步数 3 与 300 量出来逐点相同，探针拿它当判据；
/// · **展开**才给全量，且行体在 `ScrollView` 里、上限定死 `maxHeight`（168pt），
///   再多的步数在内部滚 —— 所以「步数很多 / 展开」都不会改变这一块以外任何东西的尺寸；
/// · 收起态被截断时，表头右端给 `+N`（还有几步没画出来）+ `▸` 可点开，不静默吞掉；
/// · 计数器由 `AgentStepCounter` 给（分子 = 已完成步数、分母 = 固定预算），视图**不自己算数**。
struct AgentStepListPanel: View {

    /// 每行步骤行的**固定高度**（等宽一行）。行高是常量，所以「2 行」有确定的 pt 读数。
    static let rowHeight: CGFloat = Metrics.listRowHeight

    /// 表头那一行的高度（同样是一行等宽字）。
    static let headerHeight: CGFloat = Metrics.listRowHeight

    /// 收起态**最多**画几行（设计要求：最多 2 行）。
    static let collapsedRows = 2

    /// 展开时行体**最多**占的高度上限（约 12 行等宽步骤行）。超过就在内部滚。
    ///
    /// 是常量、不是「按屏高算」：这样「展开 / 收起」对外层只差一个**有界**的量，
    /// 而且探针可以拿它当判据（`AgentChatStepListProbeTests`）。
    static let maxHeight: CGFloat = 168

    /// 收起态行体的确定高度：2 行 + 行间那一格 `Spacing.hair`。
    static var collapsedRowsHeight: CGFloat {
        CGFloat(collapsedRows) * rowHeight + Spacing.hair
    }

    /// 收起态整块的**确定高度**：表头 + 间距 + 2 行行体 + 上下内边距（≈ 80pt）。
    ///
    /// 写在类型上而不是「让 SwiftUI 自己算」：判据要一个能逐点比对的数
    /// （`AgentChatCompactionProbeTests` 断言 3 步 / 50 步 / 300 步量出来都等于它）。
    static var collapsedHeight: CGFloat {
        headerHeight + Spacing.hair + collapsedRowsHeight + Spacing.s * 2
    }

    /// 展开态整块的高度上限：行体上限 + 表头 + 间距 + 内边距。
    static var expandedMaxHeight: CGFloat {
        headerHeight + Spacing.hair + maxHeight + Spacing.s * 2
    }

    let steps: [AgentChatStep]
    /// 表头读数（分子 / 分母都从 Core 来 —— 分母不随本次运行增长）。
    let counter: AgentStepCounter
    let isRunning: Bool
    let elapsedSeconds: Double?
    @Binding var expanded: Bool

    private static let font = Theme.font(.mono)

    var body: some View {
        if !steps.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.hair) {
                header
                // **收起 = 最多 2 行**（跑着也一样：跑着不看全过程，只看跑到哪）；展开 = 全量在内部滚。
                if expanded {
                    expandedRows
                } else {
                    collapsedRowsView
                }
            }
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            // 命门：**整块高度不随步数变**。收起态钉在 `collapsedHeight`，
            // 展开态由 `expandedRows` 的 `maxHeight` 钉住（这里只兜底一层上限）。
            .frame(maxHeight: expanded ? Self.expandedMaxHeight : Self.collapsedHeight)
        }
    }

    // MARK: 表头（`▸ 任务清单 · N 步 (95/150)`）

    private var header: some View {
        Button {
            expanded.toggle()
        } label: {
            HStack(spacing: Spacing.s) {
                Text(expanded ? "▾" : "▸")
                    .font(Self.font)
                    .foregroundStyle(Theme.accentColor)
                Text(L(.agentChatStepsTitle, "\(steps.count)"))
                    .font(Self.font)
                    .lineLimit(1)
                // **`已完成/预算`**（不是 `已完成/已产生`）：分母是这一轮的固定上限。
                Text("(\(counter.text))")
                    .font(Self.font)
                    .foregroundStyle(Theme.text(.secondary))
                    .lineLimit(1)
                if let seconds = elapsedSeconds {
                    Text(L(.agentStatusElapsed, String(format: "%.1f", seconds)))
                        .font(Self.font)
                        .foregroundStyle(Theme.text(.secondary))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                // 收起态被截断 ⇒ 如实说还有几步没画（不静默吞）。
                if !expanded, steps.count > Self.collapsedRows {
                    Text("+\(steps.count - Self.collapsedRows)")
                        .font(Self.font)
                        .foregroundStyle(Theme.text(.tertiary))
                        .lineLimit(1)
                }
            }
            .frame(height: Self.headerHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(expanded ? L(.agentChatCollapse) : L(.agentChatExpand))
    }

    // MARK: 收起态（**最多 2 行**，高度是常量）

    private var collapsedRowsView: some View {
        // 收着看**最后两步**：知道它此刻在干什么就够了（跑完也保持同一个形状，不跳高度）。
        let shown = Array(steps.suffix(Self.collapsedRows))
        return VStack(alignment: .leading, spacing: Spacing.hair) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, step in
                row(step, isLast: index == shown.count - 1)
            }
        }
        .frame(height: Self.collapsedRowsHeight,
               alignment: .topLeading)
        .clipped()
    }

    // MARK: 展开态（**有上限 + 内部滚动**）

    private var expandedRows: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: Spacing.hair) {
                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    row(step, isLast: index == steps.count - 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // 命门：**这个上限**。去掉它，步数有多少这一块就长多高，把输入框顶出屏幕。
        .frame(maxHeight: Self.maxHeight)
    }

    private func row(_ step: AgentChatStep, isLast: Bool) -> some View {
        HStack(spacing: Spacing.s) {
            // 树轨：TUI 的 `├─` / `└─`
            Text(isLast ? "└─" : "├─")
                .font(Self.font)
                .foregroundStyle(Theme.text(.tertiary))
            Text(mark(for: step))
                .font(Self.font)
                .foregroundStyle(tint(for: step))
            Text(step.tools.joined(separator: " · "))
                .font(Self.font)
                .foregroundStyle(Theme.text(.secondary))
                // 一行就是一行：内容再长也只吃这一行的高度（超出截断，不换行长高）。
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.leading, Spacing.m)
        // 行高固定 ⇒「2 行」= 2 × 20pt，可被探针逐点量到。
        .frame(height: Self.rowHeight)
    }

    /// 状态标记（文字，不用 SF Symbol —— §7.9.10 硬规则 ②：一律等宽）。
    private func mark(for step: AgentChatStep) -> String {
        switch step.status {
        case .running: return "◐"
        case .done: return "✓"
        case .failed: return "✗"
        }
    }

    private func tint(for step: AgentChatStep) -> Color {
        switch step.status {
        case .running: return Theme.accentColor
        case .done: return Theme.text(.secondary)
        case .failed: return Theme.status(.warning)
        }
    }
}
