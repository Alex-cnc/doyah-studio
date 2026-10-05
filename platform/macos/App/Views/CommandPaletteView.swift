import SwiftUI
import DoyahCore

/// 命令面板（FR-EDIT-25）：⌘K 唤起，输入即筛，↑↓ 选择，↩ 执行。
///
/// 设计取舍：
/// - **命令清单在 App 侧**（`AppCommandCatalog`），Core 只做匹配排序 —— Core 不做本地化。
/// - 面板本身**不执行任何动作**，只把选中的项交回：命令走 `AppState.performPaletteCommand(_:)`，
///   工作区文件走 `WorkspaceTabsModel.openFile(at:line:)`；两边的动作实现仍留在它们原本的地方。
/// - 空查询时**把所有命令列出来**：面板的第一用途是"看看有什么能做"。
///
/// **搜索范围（队列 `L-170`，需求提出者 2026-10-03 定）**：只有两类 ——
/// ① **当前工作区里的文件**（`WorkspaceSearch` 的名字命中，引擎唯一出处）；
/// ② **Doyah Studio 自带的命令**（`AppCommandCatalog`）。
/// **不搜**对象树 / 笔记正文 / 全盘：范围收窄是定案，别顺手扩。
/// 两类项**分两组画**（哪一组在最前由 `CommandPalette.grouped` 按命中的硬软决定），
/// 但 ↑↓ 与回车走的**只有一条**扁平顺序（`rows`）—— 两份顺序迟早不一致，
/// 症状是"选中的行"与"高亮的行"不是同一条（`FR-EDIT-44` 标头搜索框栽过）。
struct CommandPaletteView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var workspace: WorkspaceStore
    @EnvironmentObject private var workspaceTabs: WorkspaceTabsModel
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var isSearchFocused: Bool

    /// 当前工作区的**文件名命中**（`L-170`）。异步 + 合并窗口：检索要遍历目录树。
    @State private var fileMatches: [CommandPalette.Match] = []
    @State private var isSearchingFiles = false
    @State private var filesTruncated = false
    @State private var pending: Task<Void, Never>?

    /// 连续输入的合并窗口（与 `FR-EDIT-44` 标头搜索框同一条口径）。
    private let fileSearchDebounce: UInt64 = 180_000_000

    private var commandMatches: [CommandPalette.Match] {
        CommandPalette.search(query, in: AppCommandCatalog.all(), limit: 40)
    }

    private var groups: [CommandPalette.Group] {
        CommandPalette.grouped(commands: commandMatches, files: fileMatches)
    }

    /// ↑↓ / 回车 / 滚动共用的**唯一**扁平顺序（= 渲染顺序）。
    private var rows: [CommandPalette.Match] { groups.flatMap(\.matches) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.s) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.text(.tertiary))
                TextField(L(.commandPalettePlaceholder), text: $query)
                    .textFieldStyle(.plain)
                    .font(Theme.font(.body))
                    .focused($isSearchFocused)
                    .onSubmit { run(selectedRow) }
                    .onChange(of: query) { _, _ in
                        selectedIndex = 0
                        scheduleFileSearch()
                    }
            }
            .padding(Spacing.m)

            HairlineView()

            if rows.isEmpty {
                Text(L(.commandPaletteNoMatch))
                    .font(Theme.font(.body))
                    .foregroundStyle(Theme.text(.secondary))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(groups, id: \.kind) { group in
                                groupHeader(group)
                                ForEach(group.matches, id: \.item.id) { match in
                                    row(match: match, isSelected: match.item.id == selectedRow?.item.id)
                                        .id(match.item.id)
                                }
                            }
                        }
                    }
                    .onChange(of: selectedIndex) { _, _ in
                        guard let id = selectedRow?.item.id else { return }
                        withAnimation(.linear(duration: 0.08)) { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }

            HairlineView()
            HStack(spacing: Spacing.s) {
                Text(L(.commandPaletteHint))
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.tertiary))
                Spacer()
                // 工作区那一组还在算的时候要说出来（"什么都没有"与"还没搜完"是两件事）。
                if isSearchingFiles && fileMatches.isEmpty {
                    Text(L(.paletteWorkspaceSearching))
                        .font(Theme.font(.caption))
                        .foregroundStyle(Theme.text(.tertiary))
                }
                if filesTruncated {
                    // 上限触发要如实报数（跳过 ≠ 通过）。
                    Text(L(.paletteWorkspaceFilesTruncated, "\(fileMatches.count)"))
                        .font(Theme.font(.caption))
                        .foregroundStyle(Theme.status(.warning))
                }
                Text("\(rows.count)")
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.tertiary))
            }
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.xs)
        }
        .frame(width: 560, height: 420)
        .background(Theme.surface(.panel))
        .onAppear {
            // 标题栏搜索栏带进来的词（FR-EDIT-37）：落在输入框里，之后就是普通的即时筛选。
            if let seed = appState.commandPaletteSeedQuery, !seed.isEmpty { query = seed }
            isSearchFocused = true
            scheduleFileSearch()
        }
        // 种子只生效一次：不在这里清掉的话，下一次用 ⌘K 打开会带着上一次的词。
        .onDisappear {
            appState.commandPaletteSeedQuery = nil
            pending?.cancel()
            pending = nil
        }
        // ↑↓ 与 Esc：面板自己的键盘语义，不走全局快捷键表。
        .onKeyPress(.downArrow) {
            selectedIndex = min(selectedIndex + 1, max(rows.count - 1, 0))
            return .handled
        }
        .onKeyPress(.upArrow) {
            selectedIndex = max(selectedIndex - 1, 0)
            return .handled
        }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
    }

    // MARK: 分组与行

    private func groupHeader(_ group: CommandPalette.Group) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: group.kind == .workspaceFiles ? "doc.text" : "command")
                .imageScale(.small)
                .foregroundStyle(Theme.text(.tertiary))
            Text(title(for: group.kind))
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.text(.secondary))
            Spacer(minLength: 0)
            Text("\(group.matches.count)")
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.text(.tertiary))
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.hair)
    }

    private func title(for kind: CommandPalette.Group.Kind) -> String {
        switch kind {
        case .commands: return L(.commandPaletteCommandsGroup)
        case .workspaceFiles: return L(.paletteCategoryWorkspaceFile)
        }
    }

    private func row(match: CommandPalette.Match, isSelected: Bool) -> some View {
        HStack(spacing: Spacing.s) {
            VStack(alignment: .leading, spacing: Spacing.hair) {
                Text(match.item.title)
                    .font(Theme.font(.body))
                    .foregroundStyle(Theme.text(.primary))
                if let detail = detail(for: match.item) {
                    Text(detail)
                        .font(Theme.font(.caption))
                        .foregroundStyle(Theme.text(.tertiary))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            if let shortcut = AppCommandCatalog.shortcutHint(for: match.item.id) {
                Text(shortcut)
                    .font(Theme.font(.monoSmall))
                    .foregroundStyle(Theme.text(.tertiary))
            }
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Theme.accentColor.opacity(Theme.isDarkAppearance ? Overlay.Selection.darkAlpha : Overlay.Selection.lightAlpha) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { run(match) }
    }

    /// 第二行的明细：文件项给**相对路径**（光给文件名，用户不知道是哪个目录下的那一个），
    /// 命令项给它的分组名（查询 / 结果 / 连接…）。
    private func detail(for item: CommandPalette.Item) -> String? {
        switch item.scope {
        case .workspaceFile:
            return CommandPalette.FileID.relativePath(from: item.id)
        case .command:
            return item.category
        }
    }

    // MARK: 行为

    private var selectedRow: CommandPalette.Match? {
        rows.indices.contains(selectedIndex) ? rows[selectedIndex] : nil
    }

    /// 选中的那一项：**命令走分派器、文件走打开**（两类的回车动作不是一回事）。
    private func run(_ match: CommandPalette.Match?) {
        guard let match else { return }
        dismiss()
        switch match.item.scope {
        case .command:
            appState.performPaletteCommand(match.item.id)
        case .workspaceFile:
            openWorkspaceFile(id: match.item.id)
        }
    }

    /// 打开工作区文件（`L-170`）。
    ///
    /// 相对路径 → **工作区根下解析**（`WorkspaceTree.resolve`，与文件树同一条口径）→
    /// `openFile(at:line:)`。文件名命中**没有行号**，所以 `line` 传 `nil`（打开即可）——
    /// 内容命中带行号，那是 `FR-EDIT-44` 标头搜索框那条路，本面板不做（范围定案）。
    private func openWorkspaceFile(id: String) {
        guard let relativePath = CommandPalette.FileID.relativePath(from: id),
              let root = workspace.rootURL,
              let url = WorkspaceTree.resolve(relativePath: relativePath, in: root) else { return }
        workspaceTabs.openFile(at: url, line: nil)
    }

    /// 排一次**工作区文件名**检索（`L-170`）。
    ///
    /// 与 `FR-EDIT-44` 标头搜索框同骨架：**异步 + 合并窗口**（在目录树上敲一个键扫一次
    /// 会把界面拖住），结果落 `fileMatches`，界面只读它。命中的**成员与顺序**来自
    /// `WorkspaceSearch.findFileNames`（引擎唯一出处，界面不写第二套 `contains`）。
    private func scheduleFileSearch() {
        pending?.cancel()
        pending = nil
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty, let root = workspace.rootURL else {
            fileMatches = []
            filesTruncated = false
            isSearchingFiles = false
            return
        }
        isSearchingFiles = true
        pending = Task {
            try? await Task.sleep(nanoseconds: fileSearchDebounce)
            if Task.isCancelled { return }
            let result = await Task.detached(priority: .userInitiated) {
                WorkspaceSearch.findFileNames(in: root, query: needle)
            }.value
            if Task.isCancelled { return }
            fileMatches = AppCommandCatalog.workspaceFileMatches(query: needle, result: result)
            filesTruncated = result.isTruncated
            isSearchingFiles = false
        }
    }
}
