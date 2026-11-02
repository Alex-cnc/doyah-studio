import SwiftUI
import DoyahCore

/// 智能体动作的**逐次审批单**（FR-AI-09）。
///
/// 为什么不复用 `SafeModeConfirmSheet`：那个拦的是「用户自己在编辑器里写的 SQL」，
/// 确认结果只影响本次执行；这个拦的是「**智能体发起的**动作」，无论批准还是拒绝
/// 都必须留下审计记录，而且必须能逐次拒绝。两者的语义与留痕要求不同，
/// 硬塞进一个弹窗会让「谁批准的、批了哪条」变得说不清。
///
/// 面板上把「为什么需要批准」摊开：风险等级、语句类别、护栏风险点、
/// 完整语句、将要使用的连接与库 —— 只说「有风险」等于什么都没说。
struct AgentApprovalSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    /// 待决策的审批单（由 `AppState.agentApprovalRequest` 驱动呈现）。
    let approval: AgentApproval

    @State private var note = ""
    @State private var isWorking = false
    /// 「预计影响行数」（§9.1.16 A4）：`nil` = 还没算（先显示「估算中…」）。
    @State private var planRows: AgentPlanRows.Estimate?
    /// 逐条形状的待审计划（`FR-STD-DB-TASK-002` 判据①：每条语句 + 目标库 + 各自影响面）。
    /// `nil` = 拆不出来（空脚本等）⇒ 退回「整段原文」那一种呈现。
    @State private var statementsPlan: HighRiskTaskApproval.Plan?

    private var record: AgentActionRecord { approval.record }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Label(L(.agentApprovalTitle), systemImage: "hand.raised.fill")
                .font(Theme.font(.title))
                .foregroundStyle(record.risk.tint)

            Text(L(.agentApprovalMessage))
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.text(.secondary))
                .fixedSize(horizontal: false, vertical: true)

            contextSection
            findingsSection
            statementSection

            TextField(L(.agentApprovalNote), text: $note)
                .textFieldStyle(.roundedBorder)

            Text(L(.agentApprovalDismissHint))
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.text(.secondary))

            // 两枚动作是**真 `NSButton`**（`AgentApprovalDecisionRow`）：离屏宿主里 SwiftUI 按钮
            // 不落 `NSButton` ⇒ 「点拒绝之后是不是一条都没发」此前只能靠人手点。
            decisionRow
        }
        .padding(Spacing.l)
        .frame(width: 620)
        // 估算在**出现时**跑一次：只要这一格给出的是「这一条会改多少行」，
        // 人就能拿它和「我看到的那几条」对一眼再决定。估不出来时这里会如实写原因。
        .task(id: record.id) {
            // 逐条列出：先把这段脚本拆成「每条语句一行」，再逐条问优化器。
            // 两条语句（`TRUNCATE` + `INSERT`）合成一坨时，「哪条打哪个库」「每条各影响多少」
            // 都答不出来 —— 那正是这张单最该说清楚的东西。
            if let plan = appState.highRiskPlan(for: record) {
                statementsPlan = await appState.estimateHighRiskPlan(plan)
            } else {
                statementsPlan = nil
            }
            planRows = await appState.estimateAgentPlanRows(for: record.sql)
        }
    }

    // MARK: - 上下文

    private var contextSection: some View {
        VStack(alignment: .leading, spacing: Spacing.hair) {
            row(L(.agentAuditColumnConnection), AgentAuditPresentation.connectionText(record))
            row(L(.agentAuditColumnModel), AgentAuditPresentation.modelText(record))
            row(L(.agentAuditColumnStatement), "\(record.statementKind.text) · \(record.risk.text)")
            // 整批一个「预计影响行数」只在**单条**语句时成立；多条时那是一个合计，
            // 而合计会把「其中一条扫全表」摊平 —— 那种情况下逐条各自的行数在下面那张单子里。
            if (statementsPlan?.count ?? 0) <= 1 {
                row(L(.agentApprovalRowsTitle), planRowsText)
            }
        }
        .font(Theme.font(.caption))
    }

    /// 「预计影响行数」那一格（§9.1.16 A4）。
    ///
    /// 三档都必须**说清楚**：给了数（`≈N 行`）/ 估不出来（原因）/ 还没算完（估算中…）——
    /// 空白的格子会被读成「0 行」，而那是完全不同的一件事。
    private var planRowsText: String {
        switch planRows {
        case .none:
            return L(.agentApprovalRowsEstimating)
        case .rows(let count):
            return "≈\(count) " + L(.agentApprovalRowsUnit)
        case .unavailable(let code):
            return L(.agentApprovalRowsUnavailablePrefix) + reasonText(code)
        }
    }

    /// 原因码 → 人话（码留在 `AgentPlanRows.Estimate` 里，翻在这里 —— Core 不做本地化）。
    private func reasonText(_ code: String) -> String {
        switch code {
        case "noConnection": return L(.agentApprovalRowsNoConnection)
        case "notDataChange": return L(.agentApprovalRowsNotDataChange)
        case "dialectUnsupported": return L(.agentApprovalRowsDialect)
        case "noAnswer", "parseFailed": return L(.agentApprovalRowsNoAnswer)
        default: return L(.agentApprovalRowsQueryFailed)
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .foregroundStyle(Theme.text(.secondary))
                .frame(width: 96, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 护栏结论（NFR-AI-12：为什么需要批准）

    private var findingsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(L(.agentAuditColumnGuard))
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.text(.secondary))

            if record.findings.isEmpty {
                Label(L(.agentAuditGuardNone), systemImage: "checkmark.shield")
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.secondary))
            } else {
                ForEach(record.findings, id: \.self) { finding in
                    Label(finding.message, systemImage: "exclamationmark.shield.fill")
                        .font(Theme.font(.caption))
                        .foregroundStyle(finding.risk.tint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - 语句

    /// 逐条列出（`FR-STD-DB-TASK-002` 判据①）：一条语句一行 —— 序号 · 类别、目标库、这条的预计影响行数，
    /// 下面跟这条的原文。**拆不出来时才退回整段原文**（并且仍然是原文，不是截断版）。
    private var statementSection: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            if let plan = statementsPlan {
                HStack {
                    Text(L(.agentApprovalStatementsTitle, plan.count))
                        .font(Theme.font(.caption))
                        .foregroundStyle(Theme.text(.secondary))
                    Spacer()
                    if plan.pendingImpactCount > 0 {
                        Text(L(.agentApprovalRowsEstimating))
                            .font(Theme.font(.caption))
                            .foregroundStyle(Theme.text(.secondary))
                    }
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.m) {
                        ForEach(plan.statements) { statement in
                            statementRow(statement)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }
                .frame(height: 170)
                .background(Theme.surface(.content))
                .clipShape(RoundedRectangle(cornerRadius: Radius.control))
            } else {
                ScrollView {
                    Text(record.sql)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(height: 150)
                .background(Theme.surface(.content))
                .clipShape(RoundedRectangle(cornerRadius: Radius.control))
            }
        }
    }

    /// 一条语句那一行：**目标库与影响面都必须逐条落在它自己身上**（不许共用整批那个数）。
    private func statementRow(_ statement: HighRiskTaskApproval.Statement) -> some View {
        VStack(alignment: .leading, spacing: Spacing.hair) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("#\(statement.index) · \(statement.kind)")
                    .font(.system(.caption, design: .monospaced).weight(.semibold))

                Text("\(L(.schemaDiffTarget)): \(statement.targetDatabase ?? L(.agentApprovalDatabaseNotSet))")
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.secondary))

                Spacer(minLength: 8)

                Text(impactText(statement.impact))
                    .font(Theme.font(.caption))
                    .foregroundStyle(impactTint(statement.impact))
            }

            Text(statement.sql)
                .font(.system(.caption2, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 单条的影响面文案（三档都必须**说清楚**：给了数 / 估不出来（原因）/ 还没算完）。
    private func impactText(_ impact: HighRiskTaskApproval.Impact) -> String {
        switch impact {
        case .pending:
            return L(.agentApprovalRowsEstimating)
        case .rows(let count):
            return "≈\(count) " + L(.agentApprovalRowsUnit)
        case .unavailable(let code):
            return L(.agentApprovalRowsUnavailablePrefix) + reasonText(code)
        }
    }

    private func impactTint(_ impact: HighRiskTaskApproval.Impact) -> Color {
        switch impact {
        case .rows: return .primary
        case .pending, .unavailable: return .secondary
        }
    }

    // MARK: - 决策

    /// 两枚动作（拒绝 / 批准并执行）：**接线只有一处** —— `AgentApprovalDecisionWiring.make`
    /// 与探针读的是同一份（各写一份的后果：按钮在、点了没反应，或探针量的是自己拼的一条假路）。
    ///
    /// 决策本身交给 `AppState`：状态机流转 + 执行 + 留痕都在那一处完成，
    /// 界面只负责收集「批准 / 拒绝」与备注、以及「落地之后要不要关窗」。
    private var decisionRow: some View {
        let actions = AgentApprovalDecisionWiring.make(
            appState: appState,
            approvalID: approval.id,
            note: { note },
            isWorking: { isWorking = $0 },
            onSettled: { settled in
                if settled { dismiss() }
            }
        )
        return actions.row(isWorking: isWorking)
    }
}
