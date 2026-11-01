import DoyahCore
import SwiftUI

/// 「诊断这条查询」面板（FR-AI-03 的界面入口）。
///
/// 这个面板的形状直接来自需求原文的两条硬约束：
///   · 「结论须引用真实计划 / 统计 / 锁数据，不允许无依据断言」→ 面板**必须先展示证据**（带编号、
///     带取证 SQL、带"没取到"的原因），模型回答里没引用证据的结论会被**拒绝并显示在下面**；
///   · 「建议可转成 SQL 但须走审批」→ 每条建议显示安全裁决（可直接执行 / 需确认 / 被拒绝），
///     并且「放进编辑器」这个动作**只写文本、不执行** —— 执行仍然走用户自己那一步与那道闸门。
///
/// **没有模型端点怎么用**（本机现状）：面板把组装好的资料块显示出来，用户复制去问任意模型，
/// 再把回答粘回来解读。这不是权宜之计 —— 它让这条功能在"没有端点"的环境下**立刻可用**，
/// 而自动发问只是把这中间的两次复制替换成一个按钮（端点接上以后）。
struct DiagnosisPanel: View {

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var sql = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    scopeSection
                    questionSection
                    evidenceSection
                    promptSection
                    replySection
                    if let report = appState.diagnosisReport {
                        adviceSection(report)
                        if report.hasRejections {
                            rejectionSection(report)
                        }
                    }
                }
                .padding(Spacing.l)
            }
            Divider()
            footer
        }
        .frame(width: 760, height: 700)
        .onAppear {
            if sql.isEmpty { sql = appState.diagnosisTargetSQL }
        }
    }

    // MARK: 头部

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(L(.diagnosisTitle))
                    .font(Theme.font(.title))
                if let connection = appState.selectedConnection {
                    Text(connection.endpointDescription)
                        .font(Theme.font(.caption))
                        .foregroundStyle(Theme.text(.secondary))
                }
            }
            Spacer()
            DialogActionButton(systemName: "xmark", title: L(.commonClose)) { dismiss() }
        }
        .padding(Spacing.l)
    }

    private var footer: some View {
        HStack(spacing: Spacing.m) {
            Text(L(.diagnosisRunHint))
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.text(.secondary))
            Spacer()
            // 「没重复存」时给一条**跳过去**的路（队列 L-134 口径①）：只说一句「之前存过」，
            // 等于让用户自己去列表里翻。
            if appState.reusedCapturedNote != nil {
                DialogActionButton(systemName: "arrow.up.forward.app", title: L(.diagnosisOpenCaptured)) {
                    appState.revealReusedCapturedNote()
                    dismiss()
                }
            }
            if let message = appState.diagnosisMessage {
                Text(message)
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.status(.danger))
            }
        }
        .padding(Spacing.l)
    }

    // MARK: 诊断上下文（从对象树带进来）

    /// 连接 / 库 / 对象 / 最近一次执行的读数（`FR-STD-DB-DIAG-006` ①）。
    ///
    /// 只有「从对象树右键唤起」才有这一段：老入口（诊断编辑器里那条语句）的作用域是页签，
    /// 它已经把语句显示在下面了，再列一遍「对象」只会让人以为选错了东西。
    @ViewBuilder
    private var scopeSection: some View {
        if let scope = appState.objectDiagnosisScope {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(L(.diagnosisScopeSection))
                    .font(Theme.font(.title))
                Text(scope.summary(language: LocalizationManager.shared.effectiveLanguage))
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.secondary))
                    .textSelection(.enabled)
                lastExecutionRow(scope)
            }
            .padding(Spacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface(.raised))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    /// 最近一次执行的读数；**没有就说没有**（判据 ③：明说「未取到」，不编）。
    @ViewBuilder
    private func lastExecutionRow(_ scope: DiagnosisScope) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            Text(L(.diagnosisLastExecutionSection))
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.text(.secondary))
            if let reading = scope.lastExecution {
                Text(reading.statement)
                    .font(Theme.font(.mono))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(reading.readingLine(language: LocalizationManager.shared.effectiveLanguage))
                    .font(Theme.font(.caption))
                    .foregroundStyle(reading.outcome == .failed ? Theme.status(.warning) : Theme.text(.secondary))
            } else {
                Text(L(.diagnosisLastExecutionNone))
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.status(.warning))
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: 问题与语句

    private var questionSection: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(L(.diagnosisQuestionField))
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.text(.secondary))
            TextField("", text: $appState.diagnosisQuestion)
                .textFieldStyle(.roundedBorder)
            TextEditor(text: $sql)
                .font(Theme.font(.mono))
                .editorSurface()
                .frame(height: 72)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Theme.surface(.panel), lineWidth: 1)
                )
            HStack {
                DialogActionButton(
                    systemName: appState.diagnosisIsGathering ? "hourglass" : "stethoscope",
                    title: appState.diagnosisIsGathering ? L(.diagnosisGathering) : L(.diagnosisGather)
                ) {
                    Task { await appState.gatherDiagnosisEvidence(sql: sql) }
                }
                // 从对象树唤起时不需要语句（对象统计 + 最近一次执行的读数就够了）——
                // 老入口仍然要求先有一条语句。
                .disabled(
                    appState.diagnosisIsGathering
                        || (appState.objectDiagnosisScope == nil
                            && sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                )
                Spacer()
            }
        }
    }

    // MARK: 证据

    private var evidenceSection: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(L(.diagnosisEvidenceSection))
                .font(Theme.font(.title))
            if appState.diagnosisEvidence.isEmpty {
                Text(L(.diagnosisEmpty))
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.secondary))
            } else {
                ForEach(appState.diagnosisEvidence, id: \.id) { evidence in
                    evidenceRow(evidence)
                }
            }
        }
    }

    private func evidenceRow(_ evidence: DiagnosisEvidence) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.s) {
                Text(evidence.id)
                    .font(Theme.font(.mono))
                    .foregroundStyle(Theme.text(.secondary))
                Text(evidence.kind.displayName)
                    .font(Theme.font(.caption))
                if evidence.isAvailable {
                    Text(evidence.note)
                        .font(Theme.font(.caption))
                        .foregroundStyle(Theme.text(.secondary))
                } else {
                    // 取不到的证据**显式标红**：它不能作为依据，用户要一眼看出来。
                    Text(evidence.note)
                        .font(Theme.font(.caption))
                        .foregroundStyle(Theme.status(.danger))
                }
                Spacer()
            }
            if !evidence.rows.isEmpty {
                Text(evidence.rows.prefix(6).map { row in
                    row.map { $0 ?? "NULL" }.joined(separator: "  ")
                }.joined(separator: "\n"))
                .font(Theme.font(.mono))
                .foregroundStyle(Theme.text(.secondary))
                .lineLimit(6)
            }
        }
        .padding(Spacing.s)
        .background(Theme.surface(.raised))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: 资料块（复制去问模型）

    private var promptSection: some View {
        // 提示词的语言 = **当前界面语言**（宿主语境优先）：这段资料是给用户看的、也是
        // 他要粘去问模型的，跟着界面走才不出现「英文界面上贴一段中文资料」（队列 L-47）。
        let promptText = appState.diagnosisContext.boundedPromptText(
            language: LocalizationManager.shared.effectiveLanguage
        )
        return VStack(alignment: .leading, spacing: Spacing.s) {
            Text(L(.diagnosisPromptSection))
                .font(Theme.font(.title))
            Text(L(.diagnosisPromptHint))
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.text(.secondary))
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                DialogActionButton(systemName: "doc.on.doc", title: L(.commonCopy)) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(promptText, forType: .string)
                }
                .disabled(appState.diagnosisEvidence.isEmpty)
                Spacer()
            }
            Text(promptText)
                .font(Theme.font(.mono))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.s)
                .background(Theme.surface(.raised))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: 回答与解读

    private var replySection: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(L(.diagnosisReplySection))
                .font(Theme.font(.title))
            Text(L(.diagnosisNoEndpoint))
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.text(.secondary))
            TextEditor(text: $appState.diagnosisReply)
                .font(Theme.font(.mono))
                .editorSurface()
                .frame(height: 110)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Theme.surface(.panel), lineWidth: 1)
                )
            HStack {
                DialogActionButton(systemName: "wand.and.stars", title: L(.diagnosisParse)) { appState.parseDiagnosisReply() }
                    .disabled(appState.diagnosisReply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                // 存进笔记（DOYAH-10）：只存**采纳的结论 + 可复跑取证**，不含结果行数据。
                // 同一份产物默认**不重复存**（队列 L-134 / Q14=A）—— 判定与写库都在
                // `AICaptureIntake` 一处，这里只负责把结果说给人听。
                DialogActionButton(systemName: "square.and.arrow.down", title: L(.diagnosisSaveNote)) {
                    Task { await appState.saveDiagnosisNote() }
                }
                .disabled((appState.diagnosisReport?.items.isEmpty ?? true))
                // 逃生门（**显式**才存副本）：同一份产物确实要留第二份时走这颗，
                // 而不是把默认行为改回“每次都存”——那样又变回两条。
                DialogActionButton(systemName: "doc.on.doc", title: L(.diagnosisSaveNoteCopy)) {
                    Task { await appState.saveDiagnosisNote(forceNew: true) }
                }
                .disabled((appState.diagnosisReport?.items.isEmpty ?? true))
                Spacer()
            }
        }
    }

    private func adviceSection(_ report: DiagnosisAdviceReport) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(L(.diagnosisAdviceSection))
                .font(Theme.font(.title))
            // 这一批结论里出现了可点的对象名才提示 —— 没有链接时摆一句「可以点」等于骗人。
            if report.items.contains(where: {
                DiagnosisObjectLinker.hasLinks(in: $0.conclusion, targets: appState.diagnosisLinkTargets)
            }) {
                Text(L(.diagnosisLinkedHint))
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.secondary))
            }
            if report.items.isEmpty {
                Text(L(.diagnosisRejectionsSection))
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.secondary))
            }
            ForEach(Array(report.items.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack(spacing: Spacing.s) {
                        Text("●")
                            .foregroundStyle(decisionTone(item.decision))
                        // 结论里的对象名可点（`FR-STD-DB-DIAG-006` ②）：
                        // 点了发一次跳转请求、收起面板，树那边展开路径并选中。
                        DiagnosisLinkedText(
                            text: item.conclusion,
                            targets: appState.diagnosisLinkTargets,
                            onOpen: { appState.jumpToDiagnosisObject($0) }
                        )
                        Spacer(minLength: Spacing.s)
                        Text(decisionLabel(item.decision))
                            .font(Theme.font(.caption))
                            .foregroundStyle(decisionTone(item.decision))
                    }
                    Text(L(.diagnosisEvidenceSection) + "：" + item.citations.joined(separator: ", "))
                        .font(Theme.font(.caption))
                        .foregroundStyle(Theme.text(.secondary))
                    if let suggested = item.suggestedSQL {
                        Text(suggested)
                            .font(Theme.font(.mono))
                            .textSelection(.enabled)
                        HStack {
                            DialogActionButton(systemName: "plus", title: L(.diagnosisInsertSQL)) {
                                appState.putDiagnosisSQLInEditor(suggested)
                            }
                        }
                    }
                }
                .padding(Spacing.s)
                .background(Theme.surface(.raised))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private func rejectionSection(_ report: DiagnosisAdviceReport) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(L(.diagnosisRejectionsSection))
                .font(Theme.font(.title))
            ForEach(Array(report.rejections.enumerated()), id: \.offset) { _, rejection in
                VStack(alignment: .leading, spacing: 2) {
                    Text(rejection.line)
                        .font(Theme.font(.body))
                    Text(reasonText(rejection.reason))
                        .font(Theme.font(.caption))
                        .foregroundStyle(Theme.status(.danger))
                }
            }
        }
    }

    private func reasonText(_ reason: DiagnosisAdviceReport.Rejection.Reason) -> String {
        switch reason {
        case .missingCitations: return L(.diagnosisRejectedMissing)
        case .unknownCitation(let id): return L(.diagnosisRejectedUnknown, id)
        case .unparsable: return L(.diagnosisRejectedUnparsable)
        }
    }

    private func decisionLabel(_ decision: ExecutionSafety.Decision?) -> String {
        switch decision {
        case .allow: return L(.diagnosisDecisionAllow)
        case .needsConfirmation: return L(.diagnosisDecisionConfirm)
        case .refused: return L(.diagnosisDecisionRefused)
        case nil: return ""
        }
    }

    private func decisionTone(_ decision: ExecutionSafety.Decision?) -> Color {
        switch decision {
        case .allow: return Theme.status(.success)
        case .needsConfirmation: return Theme.status(.warning)
        case .refused: return Theme.status(.danger)
        case nil: return Theme.text(.secondary)
        }
    }
}
