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

    /// 差异区顶部的取值开关（`FR-STD-WS-VCS-002`）：这一份差异「怎么取」。
    ///
    /// 为什么把「忽略空白」做成**重新取数**而不是本地过滤：`git diff -w` 是 git 自己算的差异，
    /// 本地按空白过滤等于我们另写一套差异算法 —— 两份结果迟早对不上（而界面上分不出哪份是真的）。
    @ViewBuilder
    private func diffToolbar(entry: GitWorktreeEntry) -> some View {
        HStack(spacing: Spacing.xs) {
            if entry.isStaged && entry.isUnstaged && !entry.isUntracked {
                sideButton(L(.gitDiffUnstaged), staged: false)
                sideButton(L(.gitDiffStaged), staged: true)
            } else if entry.isStaged && !entry.isUnstaged {
                Text(L(.gitDiffStaged))
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.tertiary))
            }
            Spacer(minLength: Spacing.s)
            Toggle(isOn: Binding(
                get: { model.request.ignoresWhitespace },
                set: { model.setIgnoresWhitespace($0) }
            )) {
                Text(L(.gitDiffIgnoreWhitespace))
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.secondary))
            }
            .toggleStyle(.checkbox)
            .controlSize(.small)
            contextMenu()
        }
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, 2)
    }

    /// 上下文档位（3 = git 缺省 / 12 / 40）：档位越大越要靠折叠把长段收起来。
    private func contextMenu() -> some View {
        Menu {
            ForEach(GitDiffRequest.contextSteps, id: \.self) { step in
                Button {
                    model.setContextLines(step)
                } label: {
                    Text(L(.gitDiffContextLines, step))
                }
            }
        } label: {
            Text(L(.gitDiffContextLines, model.request.contextLines))
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.text(.secondary))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(L(.gitDiffContextLines, model.request.contextLines))
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
            // 忽略空白之后「整份差异消失」是很常见的（只改了缩进）—— 那时说「这一侧没有差异」
            // 会让人以为文件没改；那句话要说清是**这个开关**造成的。
            emptyState(symbol: "text.alignleft",
                       text: model.request.ignoresWhitespace ? L(.gitDiffEmptyAfterWhitespace)
                                                             : L(.gitDiffEmptySide))
        } else {
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(document.files.enumerated()), id: \.offset) { _, file in
                        fileHeader(file)
                        if file.isBinary {
                            Text(L(.gitDiffBinary))
                                .font(Theme.font(.caption))
                                .foregroundStyle(Theme.text(.tertiary))
                                .padding(.horizontal, Spacing.s)
                                .padding(.vertical, 2)
                        } else {
                            rows(for: file)
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

    /// 一个文件的行：分段头 / 正文 / 折起来的上下文 / 「还有 N 行」。
    ///
    /// **一律走 `model.presentation`**：折叠与分页都不在视图里算 —— 视图每次 body 求值都会重算，
    /// 而折叠状态住在模型里（视图树重建不丢）。
    @ViewBuilder
    private func rows(for file: GitDiffFile) -> some View {
        let presentation = model.presentation(for: file)
        ForEach(Array(presentation.rows.enumerated()), id: \.offset) { _, row in
            switch row {
            case .hunkHeader(let header):
                hunkHeaderText(header)
            case .line(let line):
                lineRow(line)
            case .fold(let fold):
                foldRow(fold)
            case .more(let hidden):
                moreRow(hidden: hidden, file: file)
            }
        }
    }

    /// 折起来的一段未变行：点一下展开（再点折回去由展开后的编辑器路径不涉及 —— 展开后这一行就没了）。
    private func foldRow(_ fold: GitDiffFold) -> some View {
        // 一句文案只拼一次（三处提示共用同一个串 —— 也免得语言表对账把同一句记成三处调用点）。
        let hidden = L(.gitDiffFoldHidden, fold.hiddenCount)
        let hint = L(.gitDiffFoldExpand, fold.hiddenCount)
        return Button {
            model.toggleFold(fold)
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "chevron.down.circle")
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.tertiary))
                Text(hidden)
                    .font(Theme.font(.monoSmall))
                    .foregroundStyle(Theme.text(.tertiary))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, 1)
            .background(Theme.surface(.panel))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(hint)
        .accessibilityLabel(Text(hint))
    }

    /// 按需渲染：这一页之后还有多少行（点一次多一页，不是一次性全塞进视图）。
    private func moreRow(hidden: Int, file: GitDiffFile) -> some View {
        let title = L(.gitDiffShowMore, hidden)
        return Button {
            model.showMore(file: file)
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "ellipsis.circle")
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.tertiary))
                Text(title)
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.secondary))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(Text(title))
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

    private func hunkHeaderText(_ header: String) -> some View {
        Text(header)
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
