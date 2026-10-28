import SwiftUI
import DoyahCore

/// 下方面板的「变更」页（`FR-STD-WS-VCS-001`）：**分支 / 改动清单 / 逐行差异**，只读。
///
/// 为什么摆在下方面板而不是侧栏：它与「问题 / 输出 / 终端」一样是**看**的东西，
/// 而侧栏是「去哪」（树 / 连接）。用户改完一个文件想核对「我到底改了什么」时，
/// 眼睛就在编辑区和这块面板之间来回 —— 把差异放到另一侧栏会让这个来回穿过整个窗口。
///
/// 三条口径（判据钉在 `Tests/GitWorktreePanelTests`）：
///   ① **只有一处取数**：状态与差异都来自 `GitChangesModel`（它再走 `GitWorktreeProbe`），
///      视图不自己跑 git；`-C <root>` 的根就是**工作区根**，与终端 / 智能体同一口径；
///   ② **四档空态各说各的话**：没工作区 / 不是仓库 / 没装 git / 超时 —— 不合并成一句「读不到」；
///   ③ **只读**：这一页没有提交、推送、暂存按钮（需求原话「不做提交 / 推送」）。
struct GitChangesPanel: View {

    @EnvironmentObject private var workspace: WorkspaceStore
    @Environment(\.colorScheme) private var scheme

    @StateObject private var model = GitChangesModel()
    /// 上一次取数用的根 —— 换工作区才重读（`onReceive` 会在别的发布事件上也可能走到）。
    @State private var loadedRoot: String?

    /// 左侧清单宽度。只是界面比例，不是设计令牌管辖的语义尺寸。
    private let listWidth: CGFloat = 268

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear {
            guard loadedRoot != workspace.rootPath else { return }
            loadedRoot = workspace.rootPath
            model.refresh(root: workspace.rootPath)
        }
        .onReceive(workspace.$rootURL) { url in
            let path = url?.path
            guard path != loadedRoot else { return }
            loadedRoot = path
            model.refresh(root: path)
        }
    }

    // MARK: 头部（分支 + ahead/behind + 刷新 + 只读说明）

    private var header: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "arrow.triangle.branch")
                .font(Theme.font(.icon))
                .foregroundStyle(Theme.text(.tertiary))
            if case .ready(let status) = model.state {
                Text(status.branch)
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.primary))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if status.ahead > 0 || status.behind > 0 {
                    Text(L(.gitAheadBehind, status.ahead, status.behind))
                        .font(Theme.font(.caption))
                        .foregroundStyle(Theme.text(.secondary))
                        .lineLimit(1)
                }
                if status.omitted > 0 {
                    Text(L(.gitOmittedEntries, status.omitted))
                        .font(Theme.font(.caption))
                        .foregroundStyle(Theme.text(.tertiary))
                        .lineLimit(1)
                }
            } else {
                Text(L(.gitBranchLabel))
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.tertiary))
            }
            Spacer(minLength: Spacing.s)
            // **只读这件事写在界面上**：不然「为什么点了不能提交」会变成一次提问。
            Text(L(.gitReadOnlyNote))
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.text(.tertiary))
                .lineLimit(1)
            Button {
                model.refresh(root: workspace.rootPath)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(Theme.font(.caption))
            }
            .buttonStyle(.borderless)
            .disabled(model.isRefreshing)
            .help(L(.gitRefresh))
            .accessibilityLabel(Text(L(.gitRefresh)))
        }
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.hair)
    }

    // MARK: 内容

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            HStack(spacing: Spacing.xs) {
                ProgressView().controlSize(.small)
                Text(L(.gitRefresh))
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.tertiary))
            }
            .padding(Spacing.s)

        case .failed(let failure):
            emptyState(symbol: symbol(for: failure), text: text(for: failure))

        case .ready(let status):
            if status.isClean {
                emptyState(symbol: "checkmark.circle", text: L(.gitClean))
            } else {
                HStack(spacing: 0) {
                    entryList(status)
                        .frame(width: listWidth)
                    Rectangle()
                        .fill(Theme.hairline(scheme))
                        .frame(width: Metrics.hairline)
                    diffPane
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
    }

    private func symbol(for failure: GitProbeFailure) -> String {
        switch failure {
        case .noWorkspace: return "folder.badge.questionmark"
        case .noGit: return "questionmark.square.dashed"
        case .notARepository: return "shippingbox"
        case .timeout: return "clock.badge.exclamationmark"
        case .exitCode: return "exclamationmark.triangle"
        }
    }

    private func text(for failure: GitProbeFailure) -> String {
        switch failure {
        case .noWorkspace: return L(.gitNoWorkspace)
        case .noGit: return L(.gitNoGit)
        case .notARepository: return L(.gitNotRepository)
        case .timeout: return L(.gitTimedOut)
        case .exitCode(let code): return L(.gitStatusFailed, Int(code))
        }
    }

    private func emptyState(symbol: String, text: String) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: symbol)
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.text(.tertiary))
            Text(text)
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.text(.secondary))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Spacing.s)
    }

    // MARK: 改动清单

    private func entryList(_ status: GitWorktreeStatus) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(status.entries) { entry in
                    entryRow(entry)
                }
            }
            .padding(.vertical, Spacing.hair)
        }
    }

    private func entryRow(_ entry: GitWorktreeEntry) -> some View {
        let isSelected = model.selection?.id == entry.id
        return Button {
            model.select(entry)
        } label: {
            HStack(spacing: Spacing.xs) {
                Text(entry.code)
                    .font(Theme.font(.monoSmall))
                    .foregroundStyle(color(for: entry.kind))
                    .frame(width: 22, alignment: .leading)
                VStack(alignment: .leading, spacing: 0) {
                    Text(entry.path)
                        .font(Theme.font(.caption))
                        .foregroundStyle(Theme.text(.primary))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let original = entry.originalPath {
                        Text(original)
                            .font(Theme.font(.caption))
                            .foregroundStyle(Theme.text(.tertiary))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 0)
                Text(L(entry.kind.labelKey))
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.tertiary))
                    .lineLimit(1)
            }
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
            .background(isSelected ? Theme.surface(.raised) : Color.clear)
        }
        .buttonStyle(.plain)
        .help(entry.path)
    }

    private func color(for kind: GitChangeKind) -> Color {
        switch kind {
        case .conflicted: return Theme.status(.danger)
        case .deleted: return Theme.status(.danger)
        case .added, .untracked: return Theme.status(.success)
        case .modified, .renamed, .copied, .typeChanged: return Theme.status(.warning)
        case .unknown: return Theme.text(.tertiary)
        }
    }

    // MARK: 差异

    @ViewBuilder
    private var diffPane: some View {
        if let failure = model.diffFailure {
            emptyState(symbol: symbol(for: failure), text: text(for: failure))
        } else if let entry = model.selection, let document = model.diff {
            VStack(spacing: 0) {
                diffToolbar(entry: entry)
                Divider()
                diffBody(document)
            }
        } else if model.selection != nil {
            HStack(spacing: Spacing.xs) {
                ProgressView().controlSize(.small)
            }
            .padding(Spacing.s)
        } else {
            emptyState(symbol: "text.alignleft", text: L(.gitPickFile))
        }
    }

    /// 同一个文件两侧都有改动时，给「看哪一侧」一个开关；只有一侧时不摆这个开关
    /// （摆了也只是两条一模一样的路）。
    @ViewBuilder
    private func diffToolbar(entry: GitWorktreeEntry) -> some View {
        if entry.isStaged && entry.isUnstaged && !entry.isUntracked {
            HStack(spacing: Spacing.xs) {
                sideButton(L(.gitDiffUnstaged), staged: false)
                sideButton(L(.gitDiffStaged), staged: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, 2)
        } else if entry.isStaged && !entry.isUnstaged {
            HStack(spacing: Spacing.xs) {
                Text(L(.gitDiffStaged))
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.tertiary))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, 2)
        }
    }

    private func sideButton(_ title: String, staged: Bool) -> some View {
        let isActive = model.diffIsStaged == staged
        return Button {
            if let entry = model.selection { model.loadDiff(entry: entry, staged: staged) }
        } label: {
            Text(title)
                .font(Theme.font(.caption))
                .foregroundStyle(isActive ? Theme.text(.primary) : Theme.text(.tertiary))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func diffBody(_ document: GitDiffDocument) -> some View {
        if document.isEmpty || (!document.hasBody && !document.hasBinary) {
            emptyState(symbol: "text.alignleft", text: L(.gitDiffEmptySide))
        } else {
            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(document.files.enumerated()), id: \.offset) { _, file in
                        fileHeader(file)
                        if file.isBinary {
                            Text(L(.gitDiffBinary))
                                .font(Theme.font(.caption))
                                .foregroundStyle(Theme.text(.tertiary))
                                .padding(.horizontal, Spacing.s)
                                .padding(.vertical, 2)
                        } else {
                            ForEach(Array(file.hunks.enumerated()), id: \.offset) { _, hunk in
                                hunkHeader(hunk)
                                ForEach(Array(hunk.lines.enumerated()), id: \.offset) { _, line in
                                    lineRow(line)
                                }
                            }
                        }
                        if file.truncated {
                            Text(L(.gitDiffTruncated, GitUnifiedDiff.defaultMaxLinesPerFile))
                                .font(Theme.font(.caption))
                                .foregroundStyle(Theme.status(.warning))
                                .padding(.horizontal, Spacing.s)
                                .padding(.vertical, 2)
                        }
                    }
                }
                .padding(.vertical, Spacing.hair)
            }
        }
    }

    private func fileHeader(_ file: GitDiffFile) -> some View {
        HStack(spacing: Spacing.xs) {
            Text(file.displayPath)
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.text(.primary))
            if file.addedCount > 0 {
                Text("+\(file.addedCount)")
                    .font(Theme.font(.monoSmall))
                    .foregroundStyle(Theme.status(.success))
            }
            if file.removedCount > 0 {
                Text("-\(file.removedCount)")
                    .font(Theme.font(.monoSmall))
                    .foregroundStyle(Theme.status(.danger))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, 2)
        .background(Theme.surface(.panel))
    }

    private func hunkHeader(_ hunk: GitDiffHunk) -> some View {
        Text(hunk.header)
            .font(Theme.font(.monoSmall))
            .foregroundStyle(Theme.text(.tertiary))
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, 1)
    }

    private func lineRow(_ line: GitDiffLine) -> some View {
        HStack(spacing: 0) {
            Text(line.oldNumber.map(String.init) ?? "")
                .font(Theme.font(.monoSmall))
                .foregroundStyle(Theme.text(.tertiary))
                .frame(width: 40, alignment: .trailing)
                .padding(.trailing, Spacing.xs)
            Text(line.newNumber.map(String.init) ?? "")
                .font(Theme.font(.monoSmall))
                .foregroundStyle(Theme.text(.tertiary))
                .frame(width: 40, alignment: .trailing)
                .padding(.trailing, Spacing.xs)
            Text(marker(line.kind))
                .font(Theme.font(.mono))
                .foregroundStyle(Theme.text(.tertiary))
                .frame(width: 10, alignment: .center)
            Text(line.text)
                .font(Theme.font(.mono))
                .foregroundStyle(Theme.text(.primary))
                .textSelection(.enabled)
            if line.noNewlineAtEnd {
                // git 的 `\ No newline at end of file`：它是**上一行的属性**，不是一行内容
                // ⇒ 画在这行尾巴上，不另占一行（另占一行会让行号与内容错开）。
                Text(L(.gitDiffNoNewline))
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.tertiary))
                    .padding(.leading, Spacing.xs)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
        .background(tint(line.kind))
    }

    private func marker(_ kind: GitDiffLine.Kind) -> String {
        switch kind {
        case .context: return " "
        case .added: return "+"
        case .removed: return "-"
        }
    }

    private func tint(_ kind: GitDiffLine.Kind) -> Color {
        switch kind {
        case .context: return .clear
        case .added: return Theme.status(.success).opacity(0.12)
        case .removed: return Theme.status(.danger).opacity(0.12)
        }
    }
}
