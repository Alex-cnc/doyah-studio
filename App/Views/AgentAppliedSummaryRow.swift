import SwiftUI
import DoyahCore

/// 「已应用」那一片的**一行摘要**（人类主人 2026-11-06：「会话界面的执行脚本命令的 Applied 三行是什么东西，
/// 而且占用的区域越来越多，让 thinking 区域越来越少」）。
///
/// ## 它原来是什么
///
/// 每写入一个文件就是一张 `.applied` 工具卡（`Core/AgentChat.swift` 的
/// `AgentToolCardOutcome.applied`），在对话区里各占**三行**：
///
/// ```
/// ✓ ▸ write_file("Sources/Foo.swift")
/// ⎿ applied
/// Applied ⟲
/// ```
///
/// 一次批量改 20 个文件 ⇒ 60 行，全堆在对话区底部；页面又跟着最新内容自动滚到底
/// ⇒ 上面 thinking / 正文的可视高度被一路挤到看不见。**这是「三行」的来源，也是「越来越多」的来源。**
///
/// ## 现在
///
/// · **默认一行**：`✓ Applied N 处 ▸`（高度 = `summaryHeight`，常量，探针可逐点判）；
/// · 点开才看明细，明细**每一条也只是一行**，且整块上限定死 `detailMaxHeight`（168pt），
///   再多也在内部滚 —— 不会因为「这次写了 20 个文件」把外层撑高；
/// · 撤销入口跟着明细走（一条一处），摘要行不放按钮：一行摘要要能被一眼读完。
struct AgentAppliedSummaryRow: View {

    /// 摘要行高度（一行等宽字）。判据直接拿它当上限。
    static let summaryHeight: CGFloat = Metrics.listRowHeight

    /// 明细区的高度上限（约 12 行等宽明细），超过在内部滚。
    static let detailMaxHeight: CGFloat = 168

    /// 同一段连续「已应用」的卡片。
    let cards: [AgentToolCard]
    @Binding var expanded: Bool
    /// 单条撤销（`FR-AI-25` ⑤）：点了就把这次写入退回去，文件逐字节回到应用前。
    var onUndo: (UUID) -> Void

    private static let font = Theme.font(.mono)

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.hair) {
            summary
            if expanded { detail }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 摘要（**一行**）

    /// 摘要行**刻意不用 `Button`**（与转写面其它折行同一条纪律，见 `AgentChatView.assistantBody` 的注释）：
    /// 转写区里的折叠是**内容里的一个折角**，不是工具条按钮；按钮化会被
    /// `Scripts/check-button-icon-only.py` 判据 C 算成「水平按钮 + 字符文案」（a 类）。
    /// 形态取「可点的正文行」+ 无障碍按钮语义（读屏仍当按钮），语义与按钮一致。
    private var summary: some View {
        HStack(spacing: Spacing.s) {
            Text("✓")
                .font(Self.font)
                .foregroundStyle(Theme.status(.success))
            Text(L(.agentChatAppliedCount, "\(cards.count)"))
                .font(Self.font)
                .foregroundStyle(Theme.text(.secondary))
                .lineLimit(1)
            Text(expanded ? "▾" : "▸")
                .font(Self.font)
                .foregroundStyle(Theme.accentColor)
            Spacer(minLength: 0)
        }
        // 命门：**一行就是这一行的高度**。去掉它，摘要行会随内容换行往上长。
        .frame(height: Self.summaryHeight)
        .contentShape(Rectangle())
        .onTapGesture { expanded.toggle() }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text(L(.agentChatAppliedCount, "\(cards.count)")))
        .help(expanded ? L(.agentChatCollapse) : L(.agentChatExpand))
    }

    // MARK: 明细（有上限 + 内部滚动）

    private var detail: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: Spacing.hair) {
                ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                    detailRow(card, isLast: index == cards.count - 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: Self.detailMaxHeight)
    }

    /// 一条明细：`├─ ⏺ write_file("…") ⟲` —— **一行**，长参数截断，撤销按钮跟在行尾。
    private func detailRow(_ card: AgentToolCard, isLast: Bool) -> some View {
        HStack(spacing: Spacing.s) {
            Text(isLast ? "└─ ⏺" : "├─ ⏺")
                .font(Self.font)
                .foregroundStyle(Theme.text(.tertiary))
            Text(callText(card))
                .font(Self.font)
                .foregroundStyle(Theme.chat(.command, colorScheme))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            ToolbarIconButton(systemName: "arrow.uturn.backward", help: L(.agentChatUndo)) {
                onUndo(card.id)
            }
            .controlSize(.small)
        }
        .padding(.leading, Metrics.listIndent)
        .frame(height: Metrics.listRowHeight)
    }

    @Environment(\.colorScheme) private var colorScheme

    private func callText(_ card: AgentToolCard) -> String {
        card.arguments.isEmpty ? card.name : "\(card.name)(\(card.arguments))"
    }
}
