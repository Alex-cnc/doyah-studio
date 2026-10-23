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

    private var record: AgentActionRecord { approval.record }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L(.agentApprovalTitle), systemImage: "hand.raised.fill")
                .font(.headline)
                .foregroundStyle(record.risk.tint)

            Text(L(.agentApprovalMessage))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            contextSection
            findingsSection
            statementSection

            TextField(L(.agentApprovalNote), text: $note)
                .textFieldStyle(.roundedBorder)

            Text(L(.agentApprovalDismissHint))
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()

                DialogActionButton(systemName: "xmark.circle", title: L(.agentApprovalReject), role: .destructive) {
                    decide(approve: false)
                }
                .disabled(isWorking)

                DialogActionButton(systemName: "checkmark.circle", title: L(.agentApprovalApprove)) {
                    decide(approve: true)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isWorking)
            }
        }
        .padding(20)
        .frame(width: 620)
        // 估算在**出现时**跑一次：只要这一格给出的是「这一条会改多少行」，
        // 人就能拿它和「我看到的那几条」对一眼再决定。估不出来时这里会如实写原因。
        .task(id: record.id) {
            planRows = await appState.estimateAgentPlanRows(for: record.sql)
        }
    }

    // MARK: - 上下文

    private var contextSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            row(L(.agentAuditColumnConnection), AgentAuditPresentation.connectionText(record))
            row(L(.agentAuditColumnModel), AgentAuditPresentation.modelText(record))
            row(L(.agentAuditColumnStatement), "\(record.statementKind.text) · \(record.risk.text)")
            row(L(.agentApprovalRowsTitle), planRowsText)
        }
        .font(.caption)
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
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 护栏结论（NFR-AI-12：为什么需要批准）

    private var findingsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L(.agentAuditColumnGuard))
                .font(.caption)
                .foregroundStyle(.secondary)

            if record.findings.isEmpty {
                Label(L(.agentAuditGuardNone), systemImage: "checkmark.shield")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(record.findings, id: \.self) { finding in
                    Label(finding.message, systemImage: "exclamationmark.shield.fill")
                        .font(.caption2)
                        .foregroundStyle(finding.risk.tint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - 语句

    private var statementSection: some View {
        ScrollView {
            Text(record.sql)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        }
        .frame(height: 150)
        .background(Theme.surface(.content))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - 决策

    /// 决策交给 `AppState`：状态机流转 + 执行 + 留痕都在那一处完成，
    /// 界面只负责收集「批准 / 拒绝」与备注。
    private func decide(approve: Bool) {
        guard !isWorking else { return }
        isWorking = true
        let id = approval.id
        let decisionNote = note

        Task {
            if approve {
                await appState.approveAgentAction(id: id, note: decisionNote)
            } else {
                await appState.rejectAgentAction(id: id, note: decisionNote)
            }
            isWorking = false
            // 只有这条审批单真的离开待审批队列才关窗：流转失败时留在原处，
            // 让用户看到错误（而不是「点了没反应、窗口却关了」）。
            if !appState.pendingAgentApprovals.contains(where: { $0.id == id }) {
                dismiss()
            }
        }
    }
}
