import SwiftUI
import DoyahCore

/// 工作区**标头搜索框**（`FR-EDIT-44`）：文件名与内容关键字一次搜，↑↓ 选择、回车打开并跳到命中行。
///
/// 三条口径全部收在这一个文件里：
///   · **引擎唯一出处** —— 匹配谓词 / 查询归一化 / 忽略名单 / 有界遍历都在 `Core/WorkspaceSearch`
///     （`headerResults` 一次给两组结果）；界面**不写第二套 `contains`**，也不自己数行号；
///   · **顺序唯一出处** —— ↑↓ 走的 `results.rows` 就是渲染用的那一份
///     （两份顺序迟早不一致，症状 = "选中的行"与"高亮的行"不是同一条）；
///   · **如实报数** —— 跳过（二进制 / 过大 / 读不出）与上限都摆在面板上，**跳过 ≠ 通过**。
///
/// 与标题栏那个搜索栏（`FR-EDIT-37`）的分工**写死**：本框只搜**当前工作区**（局部）、
/// 命中里**带内容命中**（文件名 + 逐行）；标题栏那个（队列 `L-170` 定案）管**当前工作区的文件名**
/// 与**自带命令**两类，**不搜内容**。两个框都只碰当前工作区，区别在"搜不搜内容"。
struct WorkspaceHeaderSearch: View {

    @EnvironmentObject private var workspace: WorkspaceStore
    @EnvironmentObject private var tabs: WorkspaceTabsModel
    @Environment(\.colorScheme) private var scheme

    /// 注入点（快照 / 探针）：给了初值就带着这个词开局 —— 与「面板级注入」同一套口径
    /// （只给初值，生产路径不传）。
    var initialQuery: String = ""

    @State private var query = ""
    /// 已经出过结果的那个词（空 = 没在搜，面板收起）。与 `query` 分开是因为
    /// 检索是**异步**的：不能用"输入框里有字"冒充"结果已经到"。
    @State private var searchedQuery = ""
    @State private var results: WorkspaceSearch.HeaderSearchResults = .empty
    @State private var selected = 0
    @State private var isRunning = false
    @State private var pending: Task<Void, Never>?

    /// 结果面板的高度上限：它是"下拉结果"，不该把下面的文件树整片挤走。
    private let panelMaxHeight: CGFloat = 240
    /// 连续输入的合并窗口（读全工作区内容是要花时间的，敲一下扫一次会把界面拖住）。
    private let debounceNanoseconds: UInt64 = 220_000_000

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            field
            if isSearching {
                panel
            }
        }
        .onAppear {
            guard !initialQuery.isEmpty, query.isEmpty else { return }
            query = initialQuery
            schedule()
        }
        // ↑↓ 与 esc：输入框自己的键盘语义，不走全局快捷键表（与命令面板同一条纪律）。
        .onKeyPress(.downArrow) {
            move(1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            move(-1)
            return .handled
        }
        .onKeyPress(.escape) {
            clear()
            return .handled
        }
    }

    // MARK: 输入框

    private var field: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .imageScale(.small)
                .foregroundStyle(Theme.text(.tertiary))
            TextField(L(.workspaceHeaderSearchPlaceholder), text: $query)
                .textFieldStyle(.plain)
                .font(Theme.font(.caption))
                .onSubmit { activate(selectedRow) }
                .onChange(of: query) { _, _ in schedule() }
            if isSearching {
                Button {
                    clear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .imageScale(.small)
                        .foregroundStyle(Theme.text(.tertiary))
                }
                .buttonStyle(.plain)
                .help(L(.commonClose))
            }
        }
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(Theme.surface(.raised))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .strokeBorder(Theme.hairline(scheme), lineWidth: Metrics.hairline)
        )
    }

    // MARK: 结果面板

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isRunning && results.isEmpty {
                notice(L(.workspaceLoading), tone: Theme.text(.tertiary))
            } else if results.isEmpty {
                notice(L(.workspaceSearchEmpty), tone: Theme.text(.tertiary))
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(entries) { entry in
                                switch entry {
                                case .group(let title, let count, let symbol):
                                    groupHeader(title: title, count: count, symbol: symbol)
                                case .row(let row, let index):
                                    rowView(row, index: index)
                                        .id(index)
                                }
                            }
                        }
                        .padding(.vertical, Spacing.xs)
                    }
                    .frame(maxHeight: panelMaxHeight)
                    .onChange(of: selected) { _, newValue in
                        withAnimation(.linear(duration: 0.08)) { proxy.scrollTo(newValue, anchor: .center) }
                    }
                }
            }

            HairlineView()
            // 上限与跳过都要说出来（跳过 ≠ 通过）。
            if results.isTruncated {
                notice(L(.workspaceSearchTruncated), tone: Theme.status(.warning))
            }
            if !results.skips.isEmpty {
                notice(L(.workspaceHeaderSearchSkipped, "\(results.skips.total)"), tone: Theme.text(.tertiary))
            }
            notice(L(.workspaceHeaderSearchHint), tone: Theme.text(.tertiary))
        }
        .background(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(Theme.surface(.raised))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .strokeBorder(Theme.hairline(scheme), lineWidth: Metrics.hairline)
        )
        .padding(.top, Spacing.xs)
    }

    private func notice(_ text: String, tone: Color) -> some View {
        Text(text)
            .font(Theme.font(.caption))
            .foregroundStyle(tone)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.xs)
    }

    private func groupHeader(title: String, count: Int, symbol: String) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: symbol)
                .imageScale(.small)
                .foregroundStyle(Theme.text(.tertiary))
            Text(title)
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.text(.secondary))
            Spacer(minLength: 0)
            Text("\(count)")
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.text(.tertiary))
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.hair)
    }

    private func rowView(_ row: WorkspaceSearch.HeaderSearchResults.Row, index: Int) -> some View {
        HStack(alignment: .top, spacing: Spacing.xs) {
            Image(systemName: symbol(for: row))
                .imageScale(.small)
                .foregroundStyle(Theme.text(.tertiary))
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 0) {
                Text(title(for: row))
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.primary))
                    .lineLimit(1)
                Text(detail(for: row))
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.tertiary))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground(isSelected: index == selected))
        .contentShape(Rectangle())
        .onTapGesture {
            selected = index
            activate(row)
        }
        .help(detail(for: row))
    }

    @ViewBuilder
    private func rowBackground(isSelected: Bool) -> some View {
        if isSelected {
            Theme.accentColor.opacity(Theme.isDarkAppearance ? Overlay.Selection.darkAlpha : Overlay.Selection.lightAlpha)
        } else {
            Color.clear
        }
    }

    // MARK: 面板上的一行（**组标题不参与键盘行走**）

    private enum PanelEntry: Identifiable {
        /// 组标题（标题 / 条数 / 图标）
        case group(String, Int, String)
        /// 结果行 + 它在 `results.rows` 里的下标（↑↓ 走的就是这个下标）
        case row(WorkspaceSearch.HeaderSearchResults.Row, Int)

        var id: String {
            switch self {
            case .group(let title, _, let symbol): return "group\u{1}\(symbol)\u{1}\(title)"
            case .row(let row, _): return row.id
            }
        }
    }

    private var entries: [PanelEntry] {
        var out: [PanelEntry] = []
        if !results.files.isEmpty {
            out.append(.group(L(.workspaceHeaderSearchFilesGroup), results.files.count, "doc.text"))
            for index in results.files.indices {
                out.append(.row(results.rows[index], index))
            }
        }
        if results.contentHitCount > 0 {
            out.append(.group(L(.workspaceHeaderSearchContentGroup), results.contentHitCount, "doc.text.magnifyingglass"))
            for index in results.files.count..<results.rows.count {
                out.append(.row(results.rows[index], index))
            }
        }
        return out
    }

    private func symbol(for row: WorkspaceSearch.HeaderSearchResults.Row) -> String {
        switch row {
        case .file: return "doc.text"
        case .content: return "text.alignleft"
        }
    }

    private func title(for row: WorkspaceSearch.HeaderSearchResults.Row) -> String {
        switch row {
        case .file(let entry):
            return entry.name
        case .content(let hit):
            // 内容命中给「文件 + 行号」：光给摘要，用户不知道这是哪个文件的第几行。
            return "\(hit.entry.name) · \(L(.workspaceHeaderSearchLine, "\(hit.line)"))"
        }
    }

    private func detail(for row: WorkspaceSearch.HeaderSearchResults.Row) -> String {
        switch row {
        case .file(let entry):
            return entry.relativePath
        case .content(let hit):
            // 摘要原样来自引擎（**不改写原文**）。
            return "\(hit.entry.relativePath) · \(hit.snippet)"
        }
    }

    // MARK: 行为

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool {
        !searchedQuery.isEmpty || !trimmedQuery.isEmpty
    }

    private var selectedRow: WorkspaceSearch.HeaderSearchResults.Row? {
        results.rows.indices.contains(selected) ? results.rows[selected] : nil
    }

    private func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selected = results.moved(from: selected, by: delta)
    }

    private func clear() {
        pending?.cancel()
        pending = nil
        query = ""
        searchedQuery = ""
        results = .empty
        selected = 0
        isRunning = false
    }

    /// 打开选中的那一行：文件名命中只打开；内容命中**打开并跳到命中行**。
    private func activate(_ row: WorkspaceSearch.HeaderSearchResults.Row?) {
        guard let row, let url = workspace.url(for: row.entry) else { return }
        tabs.openFile(at: url, line: row.line)
    }

    /// 排一次检索。
    ///
    /// **异步 + 合并窗口**：内容检索要读整个工作区的文件 —— 放在主线程上敲一个键算一次，
    /// 大工作区上就是「输入框一顿一顿」。结果落在 `results`，界面只读它。
    private func schedule() {
        pending?.cancel()
        let needle = trimmedQuery
        guard !needle.isEmpty, let root = workspace.rootURL else {
            results = .empty
            searchedQuery = ""
            selected = 0
            isRunning = false
            return
        }
        isRunning = true
        pending = Task {
            try? await Task.sleep(nanoseconds: debounceNanoseconds)
            if Task.isCancelled { return }
            let computed = await Task.detached(priority: .userInitiated) {
                WorkspaceSearch.headerResults(in: root, query: needle)
            }.value
            if Task.isCancelled { return }
            results = computed
            searchedQuery = needle
            selected = 0
            isRunning = false
        }
    }
}
