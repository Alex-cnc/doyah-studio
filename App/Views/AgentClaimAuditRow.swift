import SwiftUI
import DoyahCore

/// 断言台账（claims）在对话区里的**一行摘要 + 可展开明细**
/// （2026-11-07 人类主人：「结论竟然折叠起来，却把 29 个 claims 全展开放屏幕上，
/// 而且我也不懂这些 claims 有什么用。hermes 最终的界面就是思考和其他对用户没用的信息
/// 都是默认折叠不占地方，只把用户的问题和结论呈现出来」）。
///
/// ## 它原来是什么
///
/// 每条断言是**审计台账**：「这句话我有没有依据」（`Core/AgentClaimTrace`：✓ 已验证 / ≈ 推断 /
/// ? 没验证，各带出处行）。落进消息流时是**一整块文本**（机器头 + 逐行），
/// 界面在 `noticeRow` 里把它原样铺开 ⇒ 29 条断言 + 每条下面的出处行，
/// 一屏几十行全是台账；而真正要读的结论被「长消息预览」折成首 2 末 2 行。
/// **优先级正好倒过来**：要看的折了，不该看的全展。
///
/// ## 现在（详设 §3.33「对话区展示优先级」）
///
/// · **默认一行**：高度 = `summaryHeight`（常量，探针可逐点判），29 条与 300 条**逐点同高**；
/// · 这一行本身承载「必须被看见」的那条信息：**有未核断言时**行首是 `⚠` + 橙字
///   「8 条断言没有依据（共 29 条）」，全部已核才是 `✓` + 灰字汇总 —— 不另起一行、不占第二行；
/// · 点开看明细：按档位**分组**（已验证 / 推断 / 没验证），整块上限定死 `detailMaxHeight`（240pt），
///   再多也在内部滚 —— 「多少条就铺多少行」这件事在这里被常量挡掉；
/// · 折叠行**刻意不用 `Button`**（与 `AgentAppliedSummaryRow` 同一条纪律：转写区里的折叠是
///   **内容里的一个折角**，不是工具条按钮；`Scripts/check-button-icon-only.py` 判据 C 会
///   把「水平 Button + 字符文案」算成 a 类），形态取「可点的正文行」+ 无障碍按钮语义。
struct AgentClaimAuditRow: View {

    /// 折叠那一行的高度（一行等宽字）。判据直接拿它当上限。
    static let summaryHeight: CGFloat = Metrics.listRowHeight

    /// 展开明细区的高度上限（240pt ≈ 12 行等宽明细 / 一堆出处行都装得下），超过在内部滚。
    ///
    /// 是常量、不是「按条数算」：这样「展开」对外层只多一个有界的量，
    /// 探针可以拿它当判据（`AgentChatAnswerPriorityProbeTests`）。
    static let detailMaxHeight: CGFloat = 240

    /// 一条明细行的高度（等宽一行；长结论截断，不换行长高）。
    static let lineHeight: CGFloat = Metrics.listRowHeight

    /// 展开态整块的高度上限：折叠行 + 间距 + 明细上限。
    static var expandedMaxHeight: CGFloat {
        summaryHeight + Spacing.hair + detailMaxHeight
    }

    let audit: AgentClaimAudit
    @Binding var expanded: Bool

    @Environment(\.colorScheme) private var colorScheme

    private static let font = Theme.font(.mono)

    // MARK: 那一行的**内容**（纯函数，探针与视图读同一份）

    /// 折叠行那块文案：**有未核断言就是告警**，全部已核才是汇总；后面跟展开入口。
    ///
    /// 写成静态纯函数而不是直接铺在 `body` 里：判据 ② 要断言
    /// 「8 条没依据时这一行说的是什么」「全部已核时这一行里不许出现「没依据」」——
    /// 那是**文案内容**的判定，不是几何；视图与探针读同一份，免得判据另写一套措辞。
    static func summaryText(for audit: AgentClaimAudit,
                            expanded: Bool,
                            language: AppLanguage) -> String {
        let head = audit.warning(language: language) ?? audit.headline(language: language)
        return head + " · " + audit.toggleHint(expanded: expanded, language: language)
    }

    /// 折叠行的行首字形：有未核断言 `⚠`，全部已核 `✓`。
    static func summaryGlyph(for audit: AgentClaimAudit) -> String {
        audit.hasUnverified ? "⚠" : "✓"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.hair) {
            summary
            if expanded { detail }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 折叠行（**一行**，未核告警就在这一行里）

    private var summary: some View {
        // 未核告警**只在有未核断言时**存在；有它就占这一行的主体，没有才是普通汇总。
        let warning = audit.warning(language: language)
        return HStack(spacing: Spacing.s) {
            // 字形：有未核断言 `⚠`（橙），全部已核 `✓`（绿）。
            Text(Self.summaryGlyph(for: audit))
                .font(Self.font)
                .foregroundStyle(audit.hasUnverified ? Theme.status(.warning) : Theme.status(.success))
            // 文案由 `summaryText` 给（探针判的就是它）：有未核断言时这一行**就是那条告警**。
            Text(Self.summaryText(for: audit, expanded: expanded, language: language))
                .font(Self.font)
                .foregroundStyle(warning == nil ? Theme.text(.secondary) : Theme.status(.warning))
                .lineLimit(1)
                .truncationMode(.tail)
            // 入口文案已经在 `summaryText` 里（`… · 展开看依据`），这里只留折角。
            Text(expanded ? "▾" : "▸")
                .font(Self.font)
                .foregroundStyle(Theme.accentColor)
            Spacer(minLength: 0)
        }
        // 命门：**一行就是这一行的高度**。去掉它，29 条断言换行往上长（真机就是那样）。
        .frame(height: Self.summaryHeight)
        .contentShape(Rectangle())
        .onTapGesture { expanded.toggle() }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text(audit.warning(language: language) ?? audit.headline(language: language)))
        .help(expanded ? L(.agentChatCollapse) : L(.agentChatExpand))
    }

    // MARK: 明细（分组 + 高度上限 + 内部滚动）

    private var detail: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: Spacing.hair) {
                ForEach(Array(audit.sections.enumerated()), id: \.offset) { _, section in
                    Text(audit.sectionTitle(section, language: language))
                        .font(Self.font)
                        .foregroundStyle(Theme.text(.secondary))
                        .frame(height: Self.lineHeight, alignment: .leading)
                    ForEach(Array(section.lines.enumerated()), id: \.offset) { _, line in
                        row(line)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // 命门：**这个上限**。去掉它，29 条断言有多少铺多少，把结论与输入框一起顶出屏幕。
        .frame(maxHeight: Self.detailMaxHeight)
    }

    /// 一条明细：断言行顶格、出处 / 备选行缩进一格（`block` 的缩进口径在这里变成视觉缩进）。
    private func row(_ line: AgentClaimAudit.Line) -> some View {
        HStack(spacing: 0) {
            Text(line.text)
                .font(Self.font)
                .foregroundStyle(line.status == nil ? Theme.text(.secondary) : Theme.text(.primary))
                .lineLimit(1)
                .truncationMode(.tail)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(.leading, line.status == nil ? Metrics.listIndent : 0)
        .frame(height: Self.lineHeight)
    }

    /// 当前界面语言（L-47：文案一律现算，不在类型里钉死一种语言）。
    private var language: AppLanguage { LocalizationManager.shared.effectiveLanguage }
}
