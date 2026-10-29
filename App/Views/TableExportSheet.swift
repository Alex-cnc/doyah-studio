import SwiftUI
import DoyahCore

/// 导出小结（`FR-STD-DB-IO-002` 验收要点 ④「完成后报告行数与文件路径」的承载）。
///
/// 为什么单独一块面板：对象树上的动作**没有页签** —— 页签日志（`reportTabStatus`）要 tabID、
/// 全局状态栏的下读方又是页签的 outputLog，这条链上的成果原来无处可看。
///
/// 内容全部来自 `AppState.TableExportSummary.text`（由 `TableExport.Ledger.report` 生成，
/// 与 CLI 的打印同一套账），视图自己**不再拼一句**文案：两处各拼一份，迟早一处少一句话。
/// 整库导出（下一批）复用这一个面板，因此标题、状态行、关闭按钮都做成与业务无关的形状。
struct TableExportSheet: View {
    let summary: AppState.TableExportSummary
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(spacing: Spacing.s) {
                Image(systemName: iconName)
                    .foregroundStyle(tone)
                Text(summary.title)
                    .font(Theme.font(.title))
                Spacer(minLength: Spacing.s)
                if summary.phase == .running {
                    ProgressView().controlSize(.small)
                }
            }

            // 等宽可选：路径要能被复制走（用户下一步往往是去访达里找它）。
            ScrollView {
                Text(summary.text)
                    .font(Theme.font(.caption).monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.s)
            }
            .frame(minHeight: 110, maxHeight: 320)

            HStack {
                Spacer()
                // 进行中只有一个「关闭」（它不取消导出 —— 真正能停的那条路还没有，
                // 摆一个点了没反应的「取消」比不给更糟）；结束那一档让它吃回车。
                Button(L(.tableExportClose), role: .cancel, action: onClose)
                    .keyboardShortcut(summary.phase == .running ? .cancelAction : .defaultAction)
            }
        }
        .padding(Spacing.l)
        .frame(width: 560)
    }

    private var iconName: String {
        switch summary.phase {
        case .running: return "arrow.down.doc"
        case .done: return "checkmark.circle"
        case .failed: return "exclamationmark.triangle"
        }
    }

    private var tone: Color {
        switch summary.phase {
        case .running: return Theme.text(.secondary)
        case .done: return Theme.status(.success)
        case .failed: return Theme.status(.danger)
        }
    }
}
