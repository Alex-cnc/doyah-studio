import Foundation

/// **Ultra 侧**的 AI 适配器：把诊断结论与维护计划映射成笔记草稿。
///
/// 为什么与 `AICapture` 分开（FR-NOTE-23 的解耦门禁）：
/// 这两个映射**天然引用 Ultra 才有的类型**（`DiagnosisContext` / `MaintenancePlanReview`），
/// 而 `Doyah Notes`（Windows / 移动）没有这些功能 —— 把它们留在 `AICapture` 里，
/// 整个笔记模块就没法在"只有笔记"的构建里独立存在。
/// 拆法：**笔记侧只收标题 / 正文 / 来源**（`AICapture.skillNote` / `sqlNote`，无 Ultra 依赖），
/// Ultra 侧（本文件）再放"诊断 / 维护 → 草稿"的适配器。调用点形状不变（同一个 `AICapture` 类型）。
///
/// **2026-09-26（L-04 插件链回归复核）**：上一轮拆分只搬了三个 `public` 映射函数，
/// 把两个 helper（`fingerprint(of:report:)` / `stateText(_:)`）留在了 `AICapture.swift` ——
/// 它们的**参数就是 Ultra 侧类型**，于是"笔记侧文件可独立构建"这句话当时并不成立。
/// 两个 helper 现在都在本文件；门禁把 Ultra 侧类型名列为禁用，搬回去会红。
extension AICapture {

    /// 诊断结果 → 一条笔记（**只收采纳的条目**；被拒绝的结论不进笔记，它们是过程不是结论）。
    public static func diagnosisNote(
        question: String,
        target: String,
        context: DiagnosisContext,
        report: DiagnosisAdviceReport,
        language: AppLanguage
    ) -> NoteDraft {
        var lines: [String] = []
        lines.append(t(.aiNoteGoal, target, language: language))
        lines.append(t(.aiNoteQuestion, question, language: language))
        lines.append("")
        for item in report.items {
            lines.append("## \(item.conclusion)")
            lines.append(t(.aiNoteEvidence, item.citations.joined(separator: ", "), language: language))
            if let sql = item.suggestedSQL {
                lines.append("")
                lines.append("```sql")
                lines.append(sql)
                lines.append("```")
            }
            lines.append("")
        }
        lines.append(t(.aiNoteEvidenceSection, language: language))
        for evidence in context.evidence {
            // **只写"取了什么、取没取到"，不写行数据** —— 行数据属于结果集，不属于笔记。
            lines.append(t(.aiNoteEvidenceLine, evidence.id, evidence.kind.displayName, evidence.note, language: language))
            lines.append(t(.aiNoteEvidenceSQL, evidence.sql, language: language))
        }
        return NoteDraft(
            title: question.isEmpty ? t(.aiNoteDiagnosisTitle, language: language) : question,
            body: lines.joined(separator: "\n"),
            tags: [t(.aiNoteTagDiagnosis, language: language)],
            source: NoteSource(
                kind: .diagnosis,
                connectionName: connectionName(from: target),
                fingerprint: fingerprint(of: context, report: report)
            )
        )
    }

    /// 维护计划 → 一条笔记（含逐条状态与理由：**为什么被拒也要记**，否则下次还会再提一遍）。
    public static func maintenanceNote(
        planText: String,
        review: MaintenancePlanReview,
        target: String,
        language: AppLanguage
    ) -> NoteDraft {
        var lines: [String] = []
        lines.append(t(.aiNoteGoal, target, language: language))
        lines.append("")
        lines.append("```")
        lines.append(planText.trimmingCharacters(in: .whitespacesAndNewlines))
        lines.append("```")
        lines.append("")
        lines.append(t(.aiNotePlanSection, language: language))
        for task in review.tasks {
            lines.append(t(.aiNotePlanLine, task.id, task.kind.rawValue, stateText(task.state, language: language), task.summary, language: language))
            for note in task.reviewNotes {
                lines.append(t(.aiNotePlanReason, note, language: language))
            }
        }
        if !review.unparsableLines.isEmpty {
            lines.append("")
            lines.append(t(.aiNoteUnparsableSection, language: language))
            for line in review.unparsableLines {
                lines.append(t(.aiNoteUnparsableLine, line, language: language))
            }
        }
        return NoteDraft(
            title: t(.aiNotePlanTitle, String(review.tasks.count), language: language),
            body: lines.joined(separator: "\n"),
            tags: [t(.aiNoteTagMaintenance, language: language)],
            source: NoteSource(
                kind: .maintenance,
                connectionName: connectionName(from: target),
                fingerprint: fingerprint(of: planText, review: review)
            )
        )
    }

    // MARK: - Ultra 侧的辅助（**刻意留在这个文件**，别挪回 `AICapture.swift`）

    /// 稳定指纹：证据 SQL 集合 + 采纳的结论。不掺时间，于是"同一场景再存一次"能被识别。
    ///
    /// 为什么在本文件：参数是 `DiagnosisContext` / `DiagnosisAdviceReport` —— Ultra 才有的类型。
    /// 放在笔记侧的文件里，那个文件就没法在"只有笔记"的构建里独立存在
    /// （`Scripts/check-note-module-isolation.py` 现在把 Ultra 侧类型名也列为禁用，挪回去会红）。
    static func fingerprint(of context: DiagnosisContext, report: DiagnosisAdviceReport) -> String {
        let evidencePart = context.evidence.map(\.sql).joined(separator: "|")
        let advicePart = report.items.map { $0.conclusion + $0.citations.joined() }.joined(separator: "|")
        return stableHash(evidencePart + "#" + advicePart)
    }

    /// 状态在指纹里的**语言中立**写法。
    ///
    /// 界面那句 `stateText` 会随语言变（它是文案），**指纹不许跟着变** ——
    /// 否则界面切一种语言再存一次，同一份计划就被认成两份了。
    private static func stateToken(_ state: MaintenanceTask.State) -> String {
        switch state {
        case .pending: return "pending"
        case .approved: return "approved"
        case .rejected: return "rejected"
        case .executed: return "executed"
        case .failed(let note): return "failed:" + note.raw
        }
    }

    /// 维护计划的**稳定指纹**（队列 `L-138`；口径同 `Q14=A`「同一份 AI 产物只存一条」）。
    ///
    /// 为什么从前没有：`diagnosisNote` 一直给指纹，而 `maintenanceNote` 一个都没给 ——
    /// 于是「默认不重复存」这条口径对维护计划**结构上不适用**（不是漏判，是没有可判重的依据）。
    ///
    /// 两处刻意：
    ///   ① **逐条状态要算进去**：维护计划会随审批推进（待批 → 已批 / 已拒 → 已执行），
    ///      不掺状态的话「批准之后再存一次」会被判成同一份而**把新状态丢掉** —— 那比多存一条更糟；
    ///   ② **语言不进指纹**（见 `stateToken`）。
    /// 时间同样不掺（与诊断指纹同一条口径：同一份产物再存一次要能被识别出来）。
    static func fingerprint(of planText: String, review: MaintenancePlanReview) -> String {
        let planPart = planText.trimmingCharacters(in: .whitespacesAndNewlines)
        let taskPart = review.tasks.map { task in
            [
                task.id,
                task.kind.rawValue,
                stateToken(task.state),
                task.summary,
                task.reviewNotes.joined(separator: ",")
            ].joined(separator: "|")
        }.joined(separator: "|")
        return stableHash(planPart + "#" + taskPart)
    }

    /// 维护任务状态的人话（`MaintenanceTask.State` 同样是 Ultra 侧类型）。
    static func stateText(_ state: MaintenanceTask.State, language: AppLanguage) -> String {
        switch state {
        case .pending: return t(.aiNoteStatePending, language: language)
        case .approved: return t(.aiNoteStateApproved, language: language)
        case .rejected: return t(.aiNoteStateRejected, language: language)
        case .executed: return t(.aiNoteStateExecuted, language: language)
        case .failed(let note): return t(.aiNoteStateFailed, note.readable, language: language)
        }
    }
}

/// 本文件自用的文案取值（文件级私有，避免与 `AICapture.swift` 里的同名助手冲突）。
///
/// **语言由调用方给定**（R-45 / 队列 L-65）：这里写死一种语言，另一种语言的译文就永远不可达。
private func t(_ key: LKey, _ arguments: CVarArg..., language: AppLanguage) -> String {
    arguments.isEmpty
        ? LocalizedStrings.text(key, language: language)
        : LocalizedStrings.format(key, language: language, arguments)
}
