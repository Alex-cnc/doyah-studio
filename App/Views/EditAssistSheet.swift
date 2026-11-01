import SwiftUI
import DoyahCore

/// 编辑区 AI 辅助面板（`FR-STD-WS-AI-001` 的界面）：动作名 / 数据边界 / 模型与端点 /
/// 「将发送什么」/ 结果（回答或差异）/ 「应用」。
///
/// 三条硬规矩都写在界面上，而不是写在注释里：
/// ① 结果先给差异，**没有「应用」这个点击就一个字都不进文件**；
/// ② 模型与端点各占一行，取不到就说「未配置」—— 不许写死一个看起来像真的；
/// ③ 发出去多少先讲清（选中片段 / 整个文件 + 行数字数），默认只发选中。
struct EditAssistSheet: View {

    @ObservedObject var model: EditAssistModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            scope
            Divider()
            result
            Divider()
            footer
        }
        .frame(width: 620, height: 520, alignment: .topLeading)
    }

    // MARK: - 头（动作名 + 模型 + 端点）

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text(L(.editAssistSheetTitle)).font(Theme.font(.title))
                Text(L(model.action.titleKey))
                    .font(Theme.font(.body))
                    .foregroundStyle(Theme.text(TextTone.secondary))
                Spacer()
                Button(L(.commonClose), role: .cancel) { model.dismiss(); dismiss() }
            }
            // 契约 ②：说得出用的是哪个模型与端点（空 = 未配置，照实说，不编默认值）。
            Text(L(.editAssistModelLine, model.modelName.isEmpty ? L(.editAssistNotConfigured) : model.modelName))
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.text(TextTone.secondary))
            Text(L(.editAssistEndpointLine, model.endpointName.isEmpty ? L(.editAssistNotConfigured) : model.endpointName))
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.text(TextTone.secondary))
        }
        .padding(Spacing.m)
    }

    // MARK: - 数据边界与要求

    private var scope: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Picker(L(.editAssistSheetTitle), selection: Binding(
                get: { model.boundary },
                set: { model.boundary = $0 }
            )) {
                ForEach(EditAssist.Boundary.allCases, id: \.self) { boundary in
                    Text(L(boundary.titleKey)).tag(boundary)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if model.action.needsInstruction {
                TextField(L(.editAssistInstructionLabel), text: $model.instruction)
                    .textFieldStyle(.roundedBorder)
            }

            if let summary = model.outboundSummary {
                Text(L(summary.displayKey, summary.lineCount, summary.textLength))
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(TextTone.secondary))
            }
        }
        .padding(Spacing.m)
    }

    // MARK: - 结果

    @ViewBuilder
    private var result: some View {
        switch model.phase {
        case .idle:
            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
        case .sending:
            HStack(spacing: Spacing.s) {
                ProgressView().controlSize(.small)
                Text(L(.editAssistSending)).font(Theme.font(.body))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        case .refused(let refusal):
            Text(refusalMessage(refusal))
                .font(Theme.font(.body))
                .foregroundStyle(Theme.text(TextTone.secondary))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(Spacing.m)
        case .answer(let text):
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(L(.editAssistAnswerTitle)).font(Theme.font(.title))
                ScrollView {
                    Text(text)
                        .font(Theme.font(.mono))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(Spacing.m)
        case .proposal(let proposal):
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.s) {
                    Text(L(.editAssistDiffTitle)).font(Theme.font(.title))
                    Text("+\(proposal.summary.added) −\(proposal.summary.removed)")
                        .font(Theme.font(.caption))
                        .foregroundStyle(Theme.text(TextTone.secondary))
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(proposal.diff.enumerated()), id: \.offset) { _, line in
                            Text(prefix(line.kind) + line.text)
                                .font(Theme.font(.mono))
                                .foregroundStyle(tint(line.kind))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .padding(Spacing.m)
        }
    }

    private func prefix(_ kind: AgentTextDiff.Line.Kind) -> String {
        switch kind {
        case .context: return "  "
        case .added: return "+ "
        case .removed: return "− "
        }
    }

    private func tint(_ kind: AgentTextDiff.Line.Kind) -> Color {
        switch kind {
        case .context: return Theme.text(TextTone.primary)
        case .added: return Theme.status(.success)
        case .removed: return Theme.status(.danger)
        }
    }

    private func refusalMessage(_ refusal: EditAssist.Refusal) -> String {
        switch refusal {
        case .localCapabilityExists(let key): return L(key)
        case .unreachable(let detail): return L(refusal.messageKey, detail)
        default: return L(refusal.messageKey)
        }
    }

    // MARK: - 底（动作行：发送 / 应用走 DialogActionRow —— 纯文字按钮 + cancel 档）

    private var footer: some View {
        HStack(spacing: Spacing.s) {
            if let notice = model.appliedNotice {
                Text(notice).font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(TextTone.secondary))
            }
            Spacer(minLength: 0)
            DialogActionRow(
                actions: actions,
                dismissible: true,
                pushesTrailing: false
            ) { id in
                perform(id)
            }
        }
        .padding(Spacing.m)
    }

    private var actions: [DialogActionSpec] {
        var specs: [DialogActionSpec] = [
            DialogActionSpec(id: "cancel", title: L(.commonCancel), role: .cancel)
        ]
        if model.canApply {
            specs.append(DialogActionSpec(id: "apply", title: L(.editAssistApply), role: .primary))
        } else {
            specs.append(DialogActionSpec(id: "send", title: L(.editAssistRun),
                                          role: .primary, isEnabled: model.canSend))
        }
        return specs
    }

    private func perform(_ id: String) {
        switch id {
        case "send": model.send()
        case "apply": model.applyProposal()
        default: model.dismiss(); dismiss()
        }
    }
}
