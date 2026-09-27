import SwiftUI
import DoyahCore

/// 执行计划面板（FR-DIAG-01）。
///
/// 三件事按需求来：
/// 1. **计划树**：按解析出的层级缩进展示节点、代价、估算行数、实际耗时与循环次数，
///    全表扫描（sequential scan）高亮 —— 一眼看出瓶颈在哪；
/// 2. **摘要**：节点数、规划 / 执行耗时、全表扫描处数、最慢节点（复用 Core 的 `summaryLines`）；
/// 3. **ANALYZE 的醒目提示**：它会**真正执行**语句（含写操作），所以开关旁边常驻警告，
///    而且默认关闭 —— 不能让人以为"看一眼计划"是只读操作。
///
/// **尺寸口径（2026-09-27 人工点验整改）**：需求提出者实测「Explain text 弹出对话框布局有问题，
/// 窗口特别高，上下两块很大的空白区域」。根因是这里写死了面板高 620、计划树 220、原始输出 110 ——
/// 内容只有几行时，两个框就是两大片空白，而窗口高度跟内容毫无关系。
/// 现在：**高度一律由内容算**（`行数 × 行高`，夹在 `Metrics.plan*Height` 的上下限内），
/// 超过上限才出现滚动；空态也不再用 `Spacer` 把面板顶高。宽度仍是定值（`Metrics.planPanelWidth`）。
struct ExecutionPlanPanel: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    let tabID: UUID

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            header
            options
            if appState.planRunAnalyze {
                Label(L(.planAnalyzeWarning), systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.status(.warning))
                    .fixedSize(horizontal: false, vertical: true)
            }
            content
        }
        .padding(Spacing.l)
        // **只定宽、不定高**：高度交给内容（内容少 ⇒ 面板矮），下限只是为了空态不太扁。
        .frame(width: Metrics.planPanelWidth)
        .frame(minHeight: Metrics.planPanelMinHeight)
    }

    // MARK: - 头部与选项

    private var header: some View {
        HStack(spacing: Spacing.s) {
            Text(L(.planTitle))
                .font(Theme.font(.title))

            if appState.executionPlanIsLoading {
                ProgressView().controlSize(.small)
            }

            Spacer()

            Button(L(.planRun)) {
                Task { await appState.runExecutionPlan(for: tabID) }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(appState.executionPlanIsLoading)

            Button(L(.commonClose)) { dismiss() }
        }
    }

    private var options: some View {
        HStack(spacing: Spacing.l) {
            Toggle(L(.planAnalyze), isOn: $appState.planRunAnalyze)
                .font(Theme.font(.caption))
            Toggle(L(.planBuffers), isOn: $appState.planIncludeBuffers)
                .font(Theme.font(.caption))
            Toggle(L(.planFormatJSON), isOn: $appState.planUseJSON)
                .font(Theme.font(.caption))
                .disabled(appState.selectedConnection?.dbType != .postgresql)
            Spacer()
        }
    }

    // MARK: - 内容

    @ViewBuilder
    private var content: some View {
        if let error = appState.executionPlanError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.status(.warning))
                .fixedSize(horizontal: false, vertical: true)
        }

        if let plan = appState.executionPlan, !plan.isEmpty {
            summarySection(plan)
            treeSection(plan)
            rawSection(plan)
        } else if !appState.executionPlanIsLoading && appState.executionPlanError == nil {
            // 空态**不放 `Spacer`**：那会把面板顶到最大高度，留下大片空白（就是这次被点出来的现象）。
            Text(L(.planEmpty))
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.text(.secondary))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func summarySection(_ plan: ExplainPlan) -> some View {
        VStack(alignment: .leading, spacing: Spacing.hair) {
            sectionTitle(L(.planSummary))

            ForEach(Array(plan.summaryLines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(Theme.font(.caption))
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func treeSection(_ plan: ExplainPlan) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            sectionTitle(L(.planTree))

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.hair) {
                    ForEach(plan.nodes) { node in
                        nodeRow(node)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.s)
            }
            .frame(height: clampedHeight(
                lines: plan.nodes.count,
                lineHeight: Metrics.listRowHeight,
                minimum: Metrics.planTreeMinHeight,
                maximum: Metrics.planTreeMaxHeight
            ))
            .background(Theme.surface(.content))
            .clipShape(RoundedRectangle(cornerRadius: Radius.control))
        }
    }

    private func nodeRow(_ node: ExplainPlanNode) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            Text(node.label)
                .font(Theme.font(.monoSmall))
                .fontWeight(node.depth == 0 ? .semibold : .regular)
                .foregroundStyle(node.isSequentialScan ? Theme.status(.warning) : Theme.text(.primary))

            if node.isSequentialScan {
                Text(L(.planSequentialScan))
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.status(.warning))
            }

            Text(node.displayDetail)
                .font(Theme.font(.monoSmall))
                .foregroundStyle(Theme.text(.secondary))
                .lineLimit(1)

            Spacer()
        }
        .padding(.leading, CGFloat(node.depth) * Metrics.listIndent)
    }

    private func rawSection(_ plan: ExplainPlan) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            sectionTitle(L(.planRaw))

            ScrollView {
                Text(plan.rawText)
                    .font(Theme.font(.monoSmall))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.s)
            }
            .frame(height: clampedHeight(
                lines: rawLineCount(plan),
                lineHeight: Metrics.planRawLineHeight,
                minimum: Metrics.planRawMinHeight,
                maximum: Metrics.planRawMaxHeight
            ))
            .background(Theme.surface(.content))
            .clipShape(RoundedRectangle(cornerRadius: Radius.control))
        }
    }

    // MARK: - 小工具

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(Theme.font(.caption))
            .foregroundStyle(Theme.text(.secondary))
    }

    /// **按内容算高度**：行数 × 行高，夹在上下限之间。
    /// 这样"内容只有两行"就只占两行的高度，而不是一整块 220pt 的空白。
    private func clampedHeight(lines: Int, lineHeight: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        // +Spacing.s：滚动区自己的内边距，别把最后一行压在边缘上。
        let wanted = CGFloat(max(lines, 1)) * lineHeight + Spacing.s
        return min(max(wanted, minimum), maximum)
    }

    private func rawLineCount(_ plan: ExplainPlan) -> Int {
        plan.rawText.split(separator: "\n", omittingEmptySubsequences: false).count
    }
}
