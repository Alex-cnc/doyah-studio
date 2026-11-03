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
    /// 待确认的删除（确认框里要写清「将删几项」）。
    @State private var pendingDeletion: WorkspaceEntry?
    /// 有东西正悬在「工作区根」那一行上（拖回根目录的落点高亮）。
    @State private var isRootDropTargeted = false

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
            // **必须是真按钮 + 看得见的文字**（2026-11-03 主人点验：原来这里用的是图标按钮
            // `ToolbarIconButton(systemName:)`，在 `.alert` 的 actions 里渲染不成「取消 / 删除」
            // 两个可选项，界面上只剩一个像 OK 的按钮，且点了也不走删除 —— 用户既选不了，
            // 也看不懂它在问什么)。取消在前、破坏性动作在后，与 macOS 系统习惯一致。
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
            // 切换工作区：已知的那几个直接在这里（列表与动作都在 `WorkspaceSwitchMenu` 里，
            // 与首页「最近打开的工作区」共用同一份 —— `FR-STD-WS-FS-010`）。
            WorkspaceSwitchMenu()
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
        // 拖到「工作区根」这一行 = 搬回根目录（树上没有根那一行，这是它唯一的落点）。
        .background(isRootDropTargeted ? accent.accentColor.opacity(0.18) : Color.clear)
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { items, _ in
            guard let first = items.first else { return false }
            let outcome = workspace.move(first, into: "")
            if let from = outcome.from, let to = outcome.to {
                workspaceTabs.retarget(from: from.path, to: to.path)
            }
            return outcome.accepted
        } isTargeted: { isRootDropTargeted = $0 }
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
        return WorkspaceTreeRow(
            entry: entry,
            depth: row.depth,
            isSelected: selectedPath == entry.relativePath,
            isHovered: hoveredPath == entry.relativePath,
            isRenaming: workspace.renamingPath == entry.relativePath,
            expanded: workspace.isExpanded(entry),
            renamingText: $renamingText,
            tint: accent.tint(scheme),
            accentColor: accent.accentColor,
            onOpen: {
                // 双击：目录展开 / 收起；文件开进工作区页签（FR-EDIT-36）
                if entry.isExpandable {
                    workspace.toggle(entry)
                } else if let url = workspace.url(for: entry) {
                    workspaceTabs.openFile(at: url)
                }
            },
            onSelect: {
                selectedPath = entry.relativePath
                if entry.isExpandable { workspace.toggle(entry) }
            },
            onHoverChange: { hovering in
                hoveredPath = hovering ? entry.relativePath : (hoveredPath == entry.relativePath ? nil : hoveredPath)
            },
            onCreate: { asFile in createEntry(in: entry, asFile: asFile) },
            onDelete: { pendingDeletion = entry },
            onBeginRename: { beginRename(entry) },
            onCommitRename: { commitRename(entry) },
            onCancelRename: { cancelRename() },
            onReveal: { workspace.reveal(entry) },
            onOpenInTerminal: { workspace.openInTerminal(entry) },
            // 「以源码打开」只给网页文件（判据在页签模型里 —— 登记表那一档只有一个消费者）。
            onOpenAsSource: workspaceTabs.supportsWebPagePreview(path: entry.relativePath)
                ? {
                    guard let url = workspace.url(for: entry) else { return }
                    workspaceTabs.openAsSource(at: url)
                }
                : nil,
            // 拖拽落地：判定与落地都在 store 那一侧（`WorkspaceFileMove.placement` 同一份口径）。
            onDropInto: { sourcePath in
                let outcome = workspace.move(sourcePath, into: entry.relativePath)
                // 搬成功 ⇒ 已打开的页签跟着走（与改名同一条路；目录搬动时整棵子树都跟）。
                if let from = outcome.from, let to = outcome.to {
                    workspaceTabs.retarget(from: from.path, to: to.path)
                }
                return outcome.accepted
            }
        )
        .accessibilityIdentifier("workspace-row-\(entry.relativePath)")
    }

    /// 新建（文件 / 文件夹）：建完**直接进改名态**（需求提出者 2026-09-30 定的形态）。
    ///
    /// 文件额外做一件事（`FR-STD-WS-FS-004` ③「新建后自动打开且光标在首行」）：
    /// 建出来就**开进页签并落在第 1 行** —— 用户点「新建文件」的意图是「我现在要写东西」，
    /// 让他再回到树上双击一次是把同一件事做两遍。文件夹没有「内容」可开，只进改名态。
    private func createEntry(in directory: WorkspaceEntry, asFile: Bool) {
        guard let created = workspace.createEntry(in: directory, asFile: asFile) else { return }
        guard asFile else { return }
        workspaceTabs.openFile(at: created, line: 1)
        // 新建的那一行是改名态（路径会跟着改），页签要跟着它走：
        // `commitRename` 里做同一步 —— 两处都做才不会出现「改了名，页签还叫未命名」。
    }

    /// 撤销按钮：撤完把页签也跟着收／跟着改（`FR-STD-WS-FS-005` ③ / `FS-006` ③）。
    private func undoLastFileOperation() {
        guard let undone = workspace.undoLastFileOperation() else { return }
        switch undone.kind {
        case .creation:
            // 新建的那份已进废纸篓 ⇒ 指向它的页签收掉（改过的页签留着，那是用户敲的字）。
            workspaceTabs.closeTabs(atPath: undone.currentURL.path)
            selectedPath = nil
        case .rename:
            // 改回原名 ⇒ 页签的路径与标题跟着回去。
            if let original = undone.originalURL {
                workspaceTabs.retarget(from: undone.currentURL.path, to: original.path)
            }
            selectedPath = nil
        case .deletion:
            // 页签本来就指着原路径，文件回到原处之后它自然又有效 —— 不需要搬任何东西。
            break
        case .move:
            // 撤销移动 = 搬回原目录 ⇒ 页签的路径与标题也跟着回去（目录搬回时它整棵子树都跟）。
            if let original = undone.originalURL {
                workspaceTabs.retarget(from: undone.currentURL.path, to: original.path)
            }
            selectedPath = nil
        }
    }

    private func beginRename(_ entry: WorkspaceEntry) {
        selectedPath = entry.relativePath
        renamingText = entry.name
        workspace.renamingPath = entry.relativePath
    }

    private func cancelRename() {
        workspace.renamingPath = nil
    }

    /// 回车提交。**失败就留在改名态**（输入框收掉等于把用户敲的字扔了）。
    private func commitRename(_ entry: WorkspaceEntry) {
        let trimmed = renamingText.trimmingCharacters(in: .whitespaces)
        let source = workspace.url(for: entry)
        if let renamed = workspace.rename(entry, to: trimmed) {
            if selectedPath == entry.relativePath { selectedPath = nil }  // 路径变了，选中态放掉
            // `FR-STD-WS-FS-005` ①：已打开的页签标题跟着改（目录改名时它整棵子树都跟）。
            if let source, source.standardizedFileURL != renamed.standardizedFileURL {
                workspaceTabs.retarget(from: source.path, to: renamed.path)
            }
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
    ///
    /// 「撤销」就长在**这一行**上（`FR-STD-WS-FS-005` ③ / `FS-006` ③）：文件操作的结果句
    /// 出现的那一刻，用户最后悔 —— 把撤销放在别处（菜单 / 空白处右键）等于让他先找一遍。
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
            if workspace.canUndoFileOperation {
                ToolbarIconButton(systemName: "arrow.uturn.backward", help: L(.workspaceUndo)) {
                    undoLastFileOperation()
                }
                .accessibilityIdentifier("workspace-undo")
            }
        }
        .padding(.horizontal, Spacing.m)
        .padding(.bottom, Spacing.s)
    }

    // MARK: 空状态

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            // **产品形象**（人类主人 2026-10-25：「把 AppIcon 放到 workspace 的 home 页里，
            // Doyah Studio 字前面出我们的产品形象大使」）。
            BrandMark(size: 44)
                .padding(.bottom, Spacing.s)
            Text(L(.workspaceEmptyTitle))
                .font(Theme.font(.bodyStrong))
                .foregroundStyle(Theme.text(.primary))
            Text(L(.workspaceEmptyHint))
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.text(.secondary))
                .fixedSize(horizontal: false, vertical: true)
            ToolbarIconButton(systemName: "folder", help: L(.workspaceChoose)) {
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

// MARK: - 文件树的一行（`FR-STD-WS-UI-013`：行内动作悬停出、常驻不占位）

/// 工作区文件树的**一行**。
///
/// 从 `WorkspaceExplorerView` 里抽出来的理由不是「拆小一点」，是**判据**：
/// 悬停状态本来住在父视图的 `@State` 里，而离屏宿主里**合成悬停不响应**
/// （SwiftUI 手势不吃 `window.sendEvent`，边界见 `NotesLayoutProbeTests` 头注释那三条）⇒
/// 凡按「整块面板 + 真鼠标」做的探针，只能量到「未悬停」那一档 —— 需求 ② 就永远没有读数。
/// 抽成「`isHovered` 是**输入**」的纯视图之后，探针能把**同一行**摆到两档各量一次像素，
/// 而产线仍只有**一个**写入口（父视图那一条 `.onHover`，见 `treeRow`）。
///
/// 哪几枚动作 / 画不画，唯一出处是 `RowActionPolicy`（Core）—— 视图不再自己写
/// `if entry.isDirectory` 与标识字符串：探针按同一份口径数簇。
struct WorkspaceTreeRow: View {

    let entry: WorkspaceEntry
    let depth: Int
    let isSelected: Bool
    let isHovered: Bool
    /// 正在行内改名（改名框长在这一行里）。
    let isRenaming: Bool
    /// 目录是否展开（父视图的 store 说了算；文件行传什么都不会画箭头）。
    let expanded: Bool
    @Binding var renamingText: String
    /// 选中行那一块底与左那一道竖线（由父视图从 `AccentManager` 取）。
    let tint: Color
    let accentColor: Color

    let onOpen: () -> Void
    let onSelect: () -> Void
    let onHoverChange: (Bool) -> Void
    /// 参数 = 是否建文件（false ⇒ 建目录）。
    let onCreate: (Bool) -> Void
    let onDelete: () -> Void
    let onBeginRename: () -> Void
    let onCommitRename: () -> Void
    let onCancelRename: () -> Void
    let onReveal: () -> Void
    let onOpenInTerminal: () -> Void
    /// 网页文件的「以源码打开」（`FR-STD-WS-WEB-003` ①）—— **只有网页文件才给这一枚**：
    /// 别的文件双击本就开在编辑器里，再给一个「以源码打开」是两枚做同一件事的按钮。
    let onOpenAsSource: (() -> Void)?
    /// 有东西被拖到这一行上（参数 = 被拖条目的相对路径）。返回是否接下这条拖拽。
    let onDropInto: (String) -> Bool

    @FocusState private var isRenameFieldFocused: Bool
    /// 有东西正悬在这一行上（拖拽落点高亮）—— 只在**目录行**会为 true。
    @State private var isDropTargeted = false
    /// 这个字是给哪一行准备的（父视图把 `renamingPath` 一置，下一跳这一行就成了改名态；
    /// 靠它对上号才把 `entry.name` 填进框里，否则每次重算都会把用户敲的字冲掉）。
    @State private var renameSeedPath: String?

    var body: some View {
        HStack(spacing: Spacing.xs) {
            // 展开箭头只给目录：符号链接不给（它不跟随，见 WorkspaceTree 的说明）
            if entry.isExpandable {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .imageScale(.small)          // 用 imageScale 而不是裸字号：SF Symbol 的惯用做法
                    .foregroundStyle(Theme.text(.tertiary))
                    .frame(width: 10)
            } else {
                Spacer().frame(width: 10)
            }

            Image(systemName: symbol)
                .font(Theme.font(.caption))
                .foregroundStyle(isSelected ? accentColor : Theme.text(.tertiary))
                .frame(width: 14)

            if isRenaming {
                TextField(L(.workspaceRename), text: $renamingText)
                    .textFieldStyle(.plain)
                    .font(Theme.font(.body))
                    .foregroundStyle(Theme.text(.primary))
                    .focused($isRenameFieldFocused)
                    .onSubmit { onCommitRename() }
                    .onExitCommand { onCancelRename() }
                    .onAppear {
                        // 新建那条路是 store 直接置的 `renamingPath`：这里的字要从这一行取。
                        if renameSeedPath != entry.relativePath {
                            renameSeedPath = entry.relativePath
                            renamingText = entry.name
                        }
                        isRenameFieldFocused = true
                    }
                    .accessibilityIdentifier("workspace-rename-field-\(entry.relativePath)")
            } else {
                Text(entry.name)
                    // **与 Agent 会话同一支等宽字**（`Theme.font(.mono)`）：那一支是用户选的代码字体，
                    // 会话里他看惯了。此前这里是 `Theme.font(.body)`（系统比例字 PingFang），
                    // 13pt 压在壁纸蒙版上显得又细又软，主人 2026-10-31 的原话是「看上去是宋体，不太好看」。
                    .font(Theme.font(.monoSmall))
                    .foregroundStyle(isSelected ? Theme.text(.primary) : Theme.text(.secondary))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            // **悬停才出现**（常驻会把文件名挤成一截）。哪几枚、画不画都在 `RowActionPolicy` 里。
            if RowActionPolicy.isVisible(isHovered: isHovered, isRenaming: isRenaming) {
                HStack(spacing: Spacing.hair) {
                    ForEach(RowActionPolicy.actions(isDirectory: entry.isDirectory), id: \.self) { action in
                        actionControl(action)
                            .accessibilityIdentifier(
                                RowActionPolicy.accessibilityIdentifier(action, path: entry.relativePath)
                            )
                    }
                }
            }
        }
        .padding(.leading, Spacing.s + CGFloat(depth) * 14)
        .padding(.trailing, Spacing.m)
        .frame(height: Metrics.listRowHeight)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onHover { onHoverChange($0) }
        .onTapGesture(count: 2) { onOpen() }
        .onTapGesture { onSelect() }
        // **拖拽移动**（`FR-STD-WS-FS-003`）：载荷是相对路径（与树里的 id 同一个口径），
        // 不用文件 URL —— 文件 URL 过沙箱边界要另带 bookmark，而这里只在自己那棵树里搬。
        .onDrag {
            NSItemProvider(object: entry.relativePath as NSString)
        }
        // 只有**目录行**接落点（文件行不是容器）；接不接由 store 的同一份判定说了算。
        .dropDestination(for: String.self) { items, _ in
            guard entry.isDirectory, let first = items.first else { return false }
            return onDropInto(first)
        } isTargeted: { targeted in
            isDropTargeted = entry.isDirectory && targeted
        }
        .contextMenu {
            Button(L(.workspaceReveal)) { onReveal() }
            Button(L(.workspaceOpenInTerminal)) { onOpenInTerminal() }
            if let onOpenAsSource {
                Button(L(.workspaceOpenAsSource)) { onOpenAsSource() }
            }
        }
        // **整行不挂 tip**（2026-10-02 需求提出者原话：「鼠标悬停到目录上的自带文件名 tip 取消，
        // 因为没用，且遮住了增删改工具条按钮」）：行的 tip 会盖住行内三枚图标的 tip ——
        // AppKit 只给光标下**最近的一层**提示，父层挂了，子层那三枚就永远看不到自己的名字。
        // 需要完整路径的地方仍有右键「在访达中显示」，不靠悬停。
    }

    private var symbol: String {
        switch entry.kind {
        case .directory: return expanded ? "folder.fill" : "folder"
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
    private var rowBackground: some View {
        if isSelected {
            ZStack(alignment: .leading) {
                tint.opacity(0.9)
                Rectangle()
                    .fill(accentColor)
                    .frame(width: Spacing.hair)
            }
        } else if isDropTargeted {
            // 落点高亮：拖到目录行上时给一块底（否则松手前完全看不出「会落到哪」）。
            accentColor.opacity(0.18)
        } else if isHovered {
            Theme.text(.primary).opacity(0.05)
        } else {
            Color.clear
        }
    }

    /// 一枚动作。形态照旧：加号 = 新建（点开出两项菜单）、减号 = 删到废纸篓、铅笔 = 改名；
    /// 每枚都带即时名称提示（`.help`）—— 只有图标时「按名字找不到入口」，这正是内测清单 `#2` 的那条。
    @ViewBuilder
    private func actionControl(_ action: RowAction) -> some View {
        switch action {
        case .create:
            Menu {
                Button(L(.workspaceNewFile)) { onCreate(true) }
                Button(L(.workspaceNewFolder)) { onCreate(false) }
            } label: {
                rowActionIcon(action.symbolName, help: "\(L(.workspaceNewFile)) / \(L(.workspaceNewFolder))")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            // tip 也挂在 `Menu` 本体上：`.borderlessButton` 的 menu 只把 label 当绘制内容，
            // 挂在内层 label 上实测不一定起效（三枚里就这枚是 Menu 不是 Button）。
            .help("\(L(.workspaceNewFile)) / \(L(.workspaceNewFolder))")
            .accessibilityLabel(L(.workspaceNewFile))
        case .delete:
            ToolbarIconButton(systemName: action.symbolName, help: L(.workspaceDeleteToTrash)) {
                onDelete()
            }
        case .rename:
            ToolbarIconButton(systemName: action.symbolName, help: L(.workspaceRename)) {
                onBeginRename()
            }
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
}
