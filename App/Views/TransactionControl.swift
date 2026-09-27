import SwiftUI
import DoyahCore

/// 事务控件（FR-EXEC-15）：自动提交 / 手工事务开关 + 提交 / 回滚 + **进行中状态**。
///
/// **为什么全是图标**（2026-09-27 人工点验整改）：本控件挂在查询工具栏上，而工具条的口径是
/// 「干干净净的一堆按钮，或者可选的下拉框对象」（`FR-EXEC-13` / `FR-EDIT-08`：图标按钮工具栏、
/// **不使用文字按钮**；需求提出者 2026-09-24 原话：「不应该在这里留一长串文本」）。
/// 本控件此前是一枚 `.segmented` 的**文字**选择器 + 两个**文字**按钮 + 一枚**文字**徽标 —— 三条都踩了。
/// 现在：模式改为「图标 + 下拉菜单」（下拉框属于允许的那一类），提交 / 回滚改为图标按钮，
/// 进行中状态改为「图标 + 条数」的小徽标（数字是数据，不是标签）；完整说明一律走提示 ——
/// 按钮用 `.help`，徽标用 `.hoverHint`（即时出现，见 `HoverHint`）。
/// **机械判据**：`Tests/QueryToolbarConventionTests.swift`。
///
/// 为什么要常显状态而不是只放两个按钮：手工事务最危险的状态是「有一个开着的事务，
/// 而用户已经忘了」。因此只要事务开着，这里就出现一枚带条数的徽标（失败时是红色警示），
/// 且**提交 / 回滚按钮一直可见** —— 忘了它就意味着忘了一次未提交的写入。
struct TransactionControl: View {
    @EnvironmentObject private var appState: AppState
    let tab: QueryTab

    private var session: TransactionSession? { appState.activeTransactionSession }

    var body: some View {
        if let session {
            HStack(spacing: Spacing.xs) {
                modeMenu(session.mode)

                if session.mode.isManual {
                    commitButton(session.phase)
                    rollbackButton(session.phase)
                    phaseBadge(session.phase)
                }
            }
        }
    }

    // MARK: - 模式（图标 + 下拉菜单）

    /// 模式切换做成**下拉菜单**而不是分段选择器：分段控件的每一段都必须写字，
    /// 而下拉菜单的标签可以是图标（菜单项里当然还是文字 —— 它在下拉里，不在工具条上）。
    private func modeMenu(_ mode: TransactionMode) -> some View {
        Menu {
            modeButton(L(.transactionModeAuto), target: .autoCommit, current: mode)
            modeButton(L(.transactionModeManual), target: .manual, current: mode)
        } label: {
            Image(systemName: mode.isManual ? "hand.raised" : "arrow.triangle.2.circlepath")
                .font(Theme.font(.icon)).fontWeight(.semibold)
                .foregroundStyle(mode.isManual ? Theme.status(.warning) : Theme.text(.secondary))
                .frame(width: Metrics.toolbarButtonWidth, height: Metrics.toolbarButtonHeight)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L(.transactionHelp))
    }

    private func modeButton(
        _ title: String,
        target: TransactionMode,
        current: TransactionMode
    ) -> some View {
        Button {
            Task { await appState.setTransactionMode(target, for: tab.id) }
        } label: {
            if current == target {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    // MARK: - 提交 / 回滚（图标按钮）

    private func commitButton(_ phase: TransactionPhase) -> some View {
        Button {
            Task { await appState.commitTransaction(for: tab.id) }
        } label: {
            transactionIcon(
                "checkmark.circle",
                tone: Theme.status(.success),
                enabled: isCommitAvailable(phase)
            )
        }
        .buttonStyle(.plain)
        .help(L(.transactionCommit))
        // 只有「事务开着且没失败」才谈得上提交。
        .disabled(!isCommitAvailable(phase))
    }

    private func rollbackButton(_ phase: TransactionPhase) -> some View {
        Button {
            Task { await appState.rollbackTransaction(for: tab.id) }
        } label: {
            transactionIcon("arrow.uturn.backward", tone: Theme.status(.danger), enabled: phase.isOpen)
        }
        .buttonStyle(.plain)
        .help(L(.transactionRollback))
        .disabled(!phase.isOpen)
    }

    private func isCommitAvailable(_ phase: TransactionPhase) -> Bool {
        if case .open = phase { return true }
        return false
    }

    private func transactionIcon(_ systemName: String, tone: Color, enabled: Bool) -> some View {
        Image(systemName: systemName)
            .font(Theme.font(.icon)).fontWeight(.semibold)
            .foregroundStyle(enabled ? tone : Theme.text(.disabled))
            .frame(width: Metrics.toolbarButtonWidth, height: Metrics.toolbarButtonHeight)
            .contentShape(Rectangle())
    }

    // MARK: - 进行中状态（图标 + 条数）

    @ViewBuilder
    private func phaseBadge(_ phase: TransactionPhase) -> some View {
        switch phase {
        case .idle:
            EmptyView()

        case .open(let statementCount):
            countBadge(
                count: statementCount,
                tone: Theme.status(.warning),
                symbol: "arrow.triangle.2.circlepath",
                hint: L(.transactionOpenBadge, statementCount)
            )

        case .aborted:
            // 失败的事务只接受回滚 —— 徽标用红色惊叹号，完整说明在即时提示里。
            countBadge(
                count: nil,
                tone: Theme.status(.danger),
                symbol: "exclamationmark.triangle.fill",
                hint: L(.transactionAbortedBadge)
            )
        }
    }

    private func countBadge(count: Int?, tone: Color, symbol: String, hint: String) -> some View {
        HStack(spacing: Spacing.hair) {
            Image(systemName: symbol)
            if let count {
                Text("\(count)")
                    .font(Theme.font(.caption))
                    .monospacedDigit()
            }
        }
        .font(Theme.font(.caption))
        .foregroundStyle(tone)
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.hair)
        .background(
            RoundedRectangle(cornerRadius: Radius.badge)
                .fill(tone.opacity(Theme.isDarkAppearance ? Overlay.Zebra.darkAlpha : Overlay.Zebra.lightAlpha))
        )
        .fixedSize()
        .hoverHint(hint)
    }
}
