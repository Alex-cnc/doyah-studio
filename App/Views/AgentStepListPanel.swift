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
/// 现在这一块的分工写死在这里：
/// · **表头 + 行体**；行体在 `ScrollView` 里，展开时**最多 `maxHeight`**（约 12 行等宽步骤行），
///   再多的步数在内部滚 —— 所以「步数很多」不会改变这一块以外任何东西的尺寸；
/// · 展开 / 收起只换行体，**不改变外层布局**（行体的高度上限是常量，不是 `Spacer`/`GeometryReader`
///   现算的）；
/// · 计数器由 `AgentStepCounter` 给（分子 = 已完成步数、分母 = 固定预算），视图**不自己算数**。
struct AgentStepListPanel: View {

    /// 展开时行体**最多**占的高度上限（约 12 行等宽步骤行）。超过就在内部滚。
    ///
    /// 是常量、不是「按屏高算」：这样「展开 / 收起」对外层只差一个**有界**的量，
    /// 而且探针可以拿它当判据（`AgentChatStepListProbeTests`）。
    static let maxHeight: CGFloat = 168

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
                // **跑着**：只留最后 2 步（知道它此刻在干什么就够了）；**跑完**：收进折叠里。
                if expanded || isRunning {
                    rows
                }
            }
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
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
                // **`已完成/预算`**（不是 `已完成/已产生`）：分母是这一轮的固定上限。
                Text("(\(counter.text))")
                    .font(Self.font)
                    .foregroundStyle(Theme.text(.secondary))
                if let seconds = elapsedSeconds {
                    Text(L(.agentStatusElapsed, String(format: "%.1f", seconds)))
                        .font(Self.font)
                        .foregroundStyle(Theme.text(.secondary))
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: 行体（**有上限 + 内部滚动**）

    private var rows: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: Spacing.hair) {
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, step in
                    row(step, isLast: index == visible.count - 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // 命门：**这个上限**。去掉它，步数有多少这一块就长多高，把输入框顶出屏幕。
        .frame(maxHeight: Self.maxHeight)
    }

    /// 收着且在跑 ⇒ 只留最后两步；其余一律给全量（展开就是「我要看全部」）。
    private var visible: [AgentChatStep] {
        if isRunning && !expanded { return Array(steps.suffix(2)) }
        return steps
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
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.leading, Spacing.m)
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
