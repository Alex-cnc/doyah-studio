import DoyahCore
import SwiftUI

/// 工作区面板（FR-EDIT-32）——活动栏里选「工作区」时显示在右侧。
///
/// 三件事：选目录（沙箱下是一次授权）、一层懒加载的文件树、**底部常显授权状态**。
/// 最后一条是这个面板存在感最强的地方：沙箱下书签会过期、目录会被移动，
/// 用户必须在界面上**当场看见**"现在到底能不能读写"，而不是打开文件才发现读不到。
struct WorkspaceExplorerView: View {

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var workspace: WorkspaceStore
    /// 工作区页签（FR-EDIT-36）：点文件开在**工作区**的编辑器里，而不是落进数据库的 SQL 页签。
    @EnvironmentObject private var workspaceTabs: WorkspaceTabsModel
    @EnvironmentObject private var accent: AccentManager
    @Environment(\.colorScheme) private var scheme

    @State private var selectedPath: String?
    @State private var hoveredPath: String?

    // MARK: 文件操作的行内状态（FR-EDIT-41 · 队列 L-114）
    /// 行内改名框里的字。
    @State private var renamingText = ""
    /// 这个字是给哪一行准备的（新建之后 store 直接置 `renamingPath`，靠它对上号）。
    @State private var renameTargetPath: String?
    @FocusState private var isRenameFieldFocused: Bool
    /// 待确认的删除（确认框里要写清「将删几项」）。
    @State private var pendingDeletion: WorkspaceEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if workspace.hasWorkspace {
                header
                pathLine
                tree
            } else {
                emptyState
                Spacer(minLength: 0)
            }
            // 文件操作的实话（成功也留一句：删除要说清「去哪儿了」）。
            if let notice = workspace.noticeText {
                noticeLine(notice)
            }
            statusFooter
        }
        // 删除确认：非空目录**必须先看见「将删几项」**（需求提出者 2026-09-30 定的形态）。
        .alert(
            L(.workspaceDeleteConfirmTitle),
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { entry in
            Button(L(.commonCancel), role: .cancel) { pendingDeletion = nil }
            Button(L(.workspaceDeleteConfirmAction), role: .destructive) {
                if workspace.delete(entry), selectedPath == entry.relativePath { selectedPath = nil }
                pendingDeletion = nil
            }
        } message: { entry in
            Text(deletionMessage(for: entry))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // 底色由父层 `NebulaSurface(.sidebar)` 统一给（这里再铺会盖住星云皮肤）
        .background(Color.clear)
    }

    // MARK: 头部

    /// 标头导航栏（文件树之上的那一行）：**搜索框 + 刷新 + 切换工作区**。
    ///
    /// 标题那格（原来印「工作区」两个字）让给了搜索框 —— 面板本身就叫工作区，
    /// 而下面一行已经写着当前工作区的名字与路径，再印一遍只是占地方（`FR-EDIT-44`）。
    private var header: some View {
        HStack(spacing: Spacing.xs) {
            WorkspaceHeaderSearch()
            iconButton("arrow.clockwise", help: L(.workspaceRefresh)) {
                Task { await workspace.refresh() }
            }
            iconButton("folder.badge.gearshape", help: L(.workspaceSwitch)) {
                Task { await workspace.pickAndChoose() }
            }
        }
        .padding(.horizontal, Spacing.m)
        .padding(.top, Spacing.m)
        .padding(.bottom, Spacing.xs)
    }

    /// 工作区名 + 切换入口（点击整行即可换目录）。
    private var pathLine: some View {
        VStack(alignment: .leading, spacing: Spacing.hair) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "folder.fill")
                    .font(Theme.font(.caption))
                    .foregroundStyle(accent.accentColor)
                Text(workspace.displayName)
                    .font(Theme.font(.bodyStrong))
                    .foregroundStyle(Theme.text(.primary))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            Text(workspace.rootPath ?? "")
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.text(.tertiary))
                .lineLimit(1)
                .truncationMode(.middle)   // 中间省略：只省略中间才不会把根目录吃掉
                .help(workspace.rootPath ?? "")
        }
        .padding(.horizontal, Spacing.m)
        .padding(.bottom, Spacing.s)
    }

    // MARK: 搜索
    //
    // 搜索的**界面入口在上面的标头**（`WorkspaceHeaderSearch`，`FR-EDIT-44`：文件名 + 内容两组），
    // 引擎与匹配口径在 `Core/WorkspaceSearch`。这里原来那套「只搜文件名」的输入框 + 扁平结果列表
    // 已被它取代（同一件事不留两个入口：两个框并排站，用户每次都要先想一下该敲哪个）。

    // MARK: 文件树

    private var tree: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                let rows = workspace.visibleRows()
                if rows.isEmpty {
                    Text(L(.workspaceTreeEmpty))
                        .font(Theme.font(.caption))
                        .foregroundStyle(Theme.text(.tertiary))
                        .padding(.horizontal, Spacing.m)
                        .padding(.vertical, Spacing.s)
                } else {
                    ForEach(rows) { row in
                        treeRow(row)
                    }
                }
            }
            .padding(.vertical, Spacing.xs)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .id(workspace.revision)   // 缓存变化（展开 / 刷新）时重建列表
    }

    private func treeRow(_ row: WorkspaceRow) -> some View {
        let entry = row.entry
        let isSelected = selectedPath == entry.relativePath
        let isHovered = hoveredPath == entry.relativePath

        return HStack(spacing: Spacing.xs) {
            // 展开箭头只给目录：符号链接不给（它不跟随，见 WorkspaceTree 的说明）
            if entry.isExpandable {
                Image(systemName: workspace.isExpanded(entry) ? "chevron.down" : "chevron.right")
                    .imageScale(.small)          // 用 imageScale 而不是裸字号：SF Symbol 的惯用做法
                    .foregroundStyle(Theme.text(.tertiary))
                    .frame(width: 10)
            } else {
                Spacer().frame(width: 10)
            }

            Image(systemName: symbol(for: entry))
                .font(Theme.font(.caption))
                .foregroundStyle(isSelected ? accent.accentColor : Theme.text(.tertiary))
                .frame(width: 14)

            if workspace.renamingPath == entry.relativePath {
                TextField(L(.workspaceRename), text: $renamingText)
                    .textFieldStyle(.plain)
                    .font(Theme.font(.body))
                    .foregroundStyle(Theme.text(.primary))
                    .focused($isRenameFieldFocused)
                    .onSubmit { commitRename(entry) }
                    .onExitCommand { cancelRename() }
                    .onAppear {
                        // 新建那条路是 store 直接置的 `renamingPath`：这里的字要从这一行取。
                        if renameTargetPath != entry.relativePath {
                            renameTargetPath = entry.relativePath
                            renamingText = entry.name
                        }
                        isRenameFieldFocused = true
                    }
                    .accessibilityIdentifier("workspace-rename-field-\(entry.relativePath)")
            } else {
                Text(entry.name)
                    .font(Theme.font(.body))
                    .foregroundStyle(isSelected ? Theme.text(.primary) : Theme.text(.secondary))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            // 悬浮才出现（不占常驻行宽 —— 常驻会把文件名挤成一截）；
            // 正在改名的这一行**始终**显示，免得鼠标一移开按钮就没了。
            if isHovered || workspace.renamingPath == entry.relativePath {
                rowActions(entry)
            }
        }
        .padding(.leading, Spacing.s + CGFloat(row.depth) * 14)
        .padding(.trailing, Spacing.m)
        .frame(height: Metrics.listRowHeight)
        .background(rowBackground(isSelected: isSelected, isHovered: isHovered))
        .contentShape(Rectangle())
        .onHover { hovering in
            hoveredPath = hovering ? entry.relativePath : (hoveredPath == entry.relativePath ? nil : hoveredPath)
        }
        .onTapGesture(count: 2) {
            // 双击：目录展开 / 收起；文件开进工作区页签（FR-EDIT-36）
            if entry.isExpandable {
                workspace.toggle(entry)
            } else if let url = workspace.url(for: entry) {
                workspaceTabs.openFile(at: url)
            }
        }
        .onTapGesture {
            selectedPath = entry.relativePath
            if entry.isExpandable { workspace.toggle(entry) }
        }
        .contextMenu {
            Button(L(.workspaceReveal)) { workspace.reveal(entry) }
        }
        // **整行不再挂 tip**（2026-10-02 需求提出者原话：「鼠标悬停到目录上的自带文件名 tip 取消，
        // 因为没用，且遮住了增删改工具条按钮」）：行的 tip 会盖住行内三枚图标的 tip ——
        // AppKit 只给光标下**最近的一层**提示，父层挂了，子层那三枚就永远看不到自己的名字。
        // 需要完整路径的地方仍有右键「在访达中显示」，不靠悬停。
        .accessibilityIdentifier("workspace-row-\(entry.relativePath)")
    }

    private func symbol(for entry: WorkspaceEntry) -> String {
        switch entry.kind {
        case .directory: return workspace.isExpanded(entry) ? "folder.fill" : "folder"
        case .symlink: return "arrowshape.turn.up.right"
        case .file:
            switch (entry.name as NSString).pathExtension.lowercased() {
            case "swift": return "swift"
            case "sql": return "cylinder"
            case "md": return "doc.text"
            case "json", "yml", "yaml", "toml": return "curlybraces"
            case "png", "jpg", "jpeg", "gif", "webp": return "photo"
            default: return "doc"
            }
        }
    }

    @ViewBuilder
    private func rowBackground(isSelected: Bool, isHovered: Bool) -> some View {
        if isSelected {
            ZStack(alignment: .leading) {
                accent.tint(scheme).opacity(0.9)
                Rectangle()
                    .fill(accent.accentColor)
                    .frame(width: Spacing.hair)
            }
        } else if isHovered {
            Theme.text(.primary).opacity(0.05)
        } else {
            Color.clear
        }
    }

    // MARK: 行内文件操作（FR-EDIT-41 · 队列 L-114）

    /// 行的右侧三枚（文件夹）/ 两枚（文件）：加号 = 新建（点开出两项菜单）、减号 = 删到废纸篓、铅笔 = 改名。
    /// 每枚都带即时名称提示（`.help`）—— 只有图标时「按名字找不到入口」，这正是内测清单 `#2` 的那条。
    @ViewBuilder
    private func rowActions(_ entry: WorkspaceEntry) -> some View {
        HStack(spacing: Spacing.hair) {
            if entry.isDirectory {
                Menu {
                    Button(L(.workspaceNewFile)) { workspace.createEntry(in: entry, asFile: true) }
                    Button(L(.workspaceNewFolder)) { workspace.createEntry(in: entry, asFile: false) }
                } label: {
                    rowActionIcon("plus", help: "\(L(.workspaceNewFile)) / \(L(.workspaceNewFolder))")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                // tip 也挂在 `Menu` 本体上：`.borderlessButton` 的 menu 只把 label 当绘制内容，
                // 挂在内层 label 上实测不一定起效（三枚里就这枚是 Menu 不是 Button）。
                .help("\(L(.workspaceNewFile)) / \(L(.workspaceNewFolder))")
                .accessibilityLabel(L(.workspaceNewFile))
                .accessibilityIdentifier("workspace-action-plus-\(entry.relativePath)")
            }

            Button {
                pendingDeletion = entry
            } label: {
                rowActionIcon("minus", help: L(.workspaceDeleteToTrash))
            }
            .buttonStyle(.plain)
            .help(L(.workspaceDeleteToTrash))
            .accessibilityLabel(L(.workspaceDeleteToTrash))
            .accessibilityIdentifier("workspace-action-minus-\(entry.relativePath)")

            Button {
                beginRename(entry)
            } label: {
                rowActionIcon("pencil", help: L(.workspaceRename))
            }
            .buttonStyle(.plain)
            .help(L(.workspaceRename))
            .accessibilityLabel(L(.workspaceRename))
            .accessibilityIdentifier("workspace-action-pencil-\(entry.relativePath)")
        }
    }

    private func rowActionIcon(_ symbol: String, help: String) -> some View {
        Image(systemName: symbol)
            .font(Theme.font(.caption))
            .foregroundStyle(Theme.text(.tertiary))
            .frame(width: 16, height: 16)
            .contentShape(Rectangle())
            .help(help)
    }

    private func beginRename(_ entry: WorkspaceEntry) {
        selectedPath = entry.relativePath
        renameTargetPath = entry.relativePath
        renamingText = entry.name
        workspace.renamingPath = entry.relativePath
        isRenameFieldFocused = true
    }

    private func cancelRename() {
        workspace.renamingPath = nil
        renameTargetPath = nil
        isRenameFieldFocused = false
    }

    /// 回车提交。**失败就留在改名态**（输入框收掉等于把用户敲的字扔了）。
    private func commitRename(_ entry: WorkspaceEntry) {
        let trimmed = renamingText.trimmingCharacters(in: .whitespaces)
        if workspace.rename(entry, to: trimmed) {
            if selectedPath == entry.relativePath { selectedPath = nil }  // 路径变了，选中态放掉
            renameTargetPath = nil
            isRenameFieldFocused = false
        }
    }

    /// 删之前那句实话：文件 = 1 项；文件夹要把**里面的数量**说出来（数到上限就写「N 项以上」）。
    private func deletionMessage(for entry: WorkspaceEntry) -> String {
        guard entry.isDirectory else { return L(.workspaceDeleteMessageFile, entry.name) }
        let summary = workspace.deletionSummary(for: entry)
        let inside = max(summary.items - 1, 0)
        if inside == 0 { return L(.workspaceDeleteMessageFile, entry.name) }
        return summary.truncated
            ? L(.workspaceDeleteMessageFolderTruncated, entry.name, inside)
            : L(.workspaceDeleteMessageFolder, entry.name, inside)
    }

    /// 操作结果那一行（在底部状态之上）。
    private func noticeLine(_ text: String) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "info.circle")
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.text(.tertiary))
            Text(text)
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.text(.secondary))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.m)
        .padding(.bottom, Spacing.s)
    }

    // MARK: 空状态

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(L(.workspaceEmptyTitle))
                .font(Theme.font(.bodyStrong))
                .foregroundStyle(Theme.text(.primary))
            Text(L(.workspaceEmptyHint))
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.text(.secondary))
                .fixedSize(horizontal: false, vertical: true)
            Button(L(.workspaceChoose)) {
                Task { await workspace.pickAndChoose() }
            }
            .padding(.top, Spacing.xs)
        }
        .padding(Spacing.m)
    }

    // MARK: 底部状态（授权是否有效，必须常显）

    private var statusFooter: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Theme.hairline(scheme))
                .frame(height: Metrics.hairline)
            HStack(spacing: Spacing.xs) {
                Circle()
                    .fill(statusTint)
                    .frame(width: 6, height: 6)
                Text(statusText)
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.tertiary))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.s)
        }
    }

    private var statusText: String {
        guard let status = workspace.status else { return L(.directoryStatusNotAuthorized) }
        return L(status.messageKey, status.messageArgument)
    }

    private var statusTint: Color {
        switch workspace.status {
        case .granted(_, let isStale):
            return isStale ? Theme.status(.warning) : Theme.status(.success)
        case .missing, .denied, .resolutionFailed:
            return Theme.status(.danger)
        case .notAuthorized, .none:
            return Theme.text(.tertiary)
        }
    }

    // MARK: 小组件

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.text(.tertiary))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}
