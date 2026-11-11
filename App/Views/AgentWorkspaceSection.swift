import SwiftUI
import DoyahCore

/// 「智能体工作区」那一格（`FR-STD-WS-FS-011` ⑤）：**当前根 + 来源 + 恢复默认**。
///
/// 为什么要有它：工作区根决定了 Agent 的读写边界，而它以前在界面上**一个字都不显示** ——
/// 用户看不见「Agent 现在能在哪儿动文件」，也看不见「这个目录是他自己选的还是继承来的」。
///
/// 三样必须同时在场：
///   ① 绝对路径（照原样显示，可选中复制）；
///   ② 来源（`默认` / `用户打开`）—— 只有两态，别处推出来的目录不构成来源；
///   ③ 「恢复默认（~/.doyah）」按钮 —— 用户能从任何状态一键回到默认根。
///
/// 迁移提示（`workspace.originNotice`）画在同一格的最上面：旧数据被换成默认根这件事
/// **不许静默**（用户下次开设置就该看见）。
struct AgentWorkspaceSection: View {

    @EnvironmentObject private var workspace: WorkspaceStore
    @ObservedObject private var localization = LocalizationManager.shared

    private var language: AppLanguage { LocalizationManager.shared.effectiveLanguage }

    /// 现在是不是已经停在默认根（按钮据此变灰：点了也没变化的那一下不该可点）。
    private var isAtDefaultRoot: Bool {
        workspace.rootOrigin == .defaultRoot
            && workspace.rootPath == workspace.defaultRootURL.path
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(WorkspaceRootCopy.title(language))
                .font(Theme.font(.bodyStrong))
                .foregroundStyle(Theme.text(.primary))

            if let notice = workspace.originNotice {
                Text(notice)
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.status(.warning))
                    .fixedSize(horizontal: false, vertical: true)
                    // 提示行是判据要断言的**可见**证据：标识与文案都挂上，读屏也读得到。
                    .accessibilityIdentifier("agentWorkspaceOriginNotice")
                    .accessibilityLabel(notice)
            }

            row(
                label: WorkspaceRootCopy.rootLabel(language),
                value: workspace.rootPath ?? "—",
                identifier: "agentWorkspaceRootPath"
            )
            row(
                label: WorkspaceRootCopy.originLabel(language),
                value: WorkspaceRootCopy.originText(
                    workspace.rootOrigin,
                    defaultPath: workspace.defaultRootURL.path,
                    language
                ),
                identifier: "agentWorkspaceOriginValue"
            )

            HStack(spacing: Spacing.s) {
                Button {
                    Task { await workspace.pickAndChoose() }
                } label: {
                    Image(systemName: "folder")
                }
                .help(WorkspaceRootCopy.openFolderButton(language))
                .accessibilityLabel(WorkspaceRootCopy.openFolderButton(language))
                Button {
                    Task { await workspace.restoreDefaultRoot() }
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .help(WorkspaceRootCopy.restoreDefaultButton(language))
                .accessibilityLabel(WorkspaceRootCopy.restoreDefaultButton(language))
                .disabled(isAtDefaultRoot)
                .accessibilityIdentifier("agentWorkspaceRestoreDefault")
                Spacer(minLength: 0)
            }
            .font(Theme.font(.caption))
        }
        .accessibilityIdentifier("agentWorkspaceSection")
    }

    /// 一行「标签 + 值」：值可选中复制（路径要能原样贴到终端里）。
    private func row(label: String, value: String, identifier: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            Text(label)
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.text(.secondary))
                .frame(width: AgentWorkspaceSection.labelWidth, alignment: .leading)
            Text(value)
                .font(Theme.font(.monoSmall))
                .foregroundStyle(Theme.text(.primary))
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
                .help(value)
                .accessibilityIdentifier(identifier)
                .accessibilityLabel(value)
        }
    }

    private static let labelWidth: CGFloat = 64
}
