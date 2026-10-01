import SwiftUI
import AppKit
import DoyahCore

/// 工作区**自己的**编辑区（FR-EDIT-35 / 36）。
///
/// 与数据库那套的关系：活动栏切到「工作区」时，右边显示的就是这里 ——
/// 页签集与数据库的 SQL 页签**互不干扰**（"我在写代码"和"我在跑查询"是两种工作）。
struct WorkspaceAreaView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var workspace: WorkspaceStore
    @EnvironmentObject private var tabs: WorkspaceTabsModel
    /// 浏览器页签的状态所有者（队列 `L-149` 剩余①）—— 与 `WorkspaceTabsModel` 同一条口径。
    @EnvironmentObject private var browser: WorkspaceBrowserModel
    /// 预览的跟随滚动输入面（队列 `L-137`）：**独立对象**，光标每换一行只惊动预览那一侧。
    @StateObject private var previewCursor = MarkdownPreviewCursorModel()

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceTabStrip()
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            messageBar
        }
        // 底色由父层统一给（`sectionWithLowerPane` 的 `NebulaBackground`）——
    // 这里再铺不透明色会把星云皮肤**整片盖住**（2026-10-01 实测）。
    .background(Color.clear)
    }

    // MARK: 内容

    @ViewBuilder
    private var content: some View {
        if let page = browser.selectedBrowserPage {
            // 浏览器页签在工作区（`L-149`）：与 Home / 文件页签同一处呈现。
            BrowserTabView(page: page)
        } else if let tab = tabs.selectedTab {
            if tab.isHome {
                WorkspaceHomeView()
            } else {
                VStack(spacing: 0) {
                    editorArea(tab: tab)
                    Divider()
                    hintBar(tab: tab)
                }
            }
        }
    }

    /// 编辑器区：Markdown 文件（且预览开关打开）⇒ **编辑区 + 只读预览**分屏（队列 `L-137`）。
    ///
    /// 分屏器用 `HSplitView`：中间那条分隔线可以拖 —— "看预览"和"写代码"哪个要宽
    /// 是用户当下的事，不该由我们钉死比例。
    @ViewBuilder
    private func editorArea(tab: WorkspaceTab) -> some View {
        let editor = CodeEditorView(
            tabID: tab.id,
            text: tab.content,
            language: tab.language,
            pendingFormat: tabs.formatDelivery,
            pendingReveal: tabs.revealDelivery,
            onTextChange: { text in tabs.updateContent(text, for: tab.id) },
            onSave: { tabs.save(tab.id) },
            onFormat: { tabs.formatSelected() },
            onCursorLine: { line in previewCursor.report(line: line) }
        )
        if tab.language == .markdown && tabs.previewVisible {
            HSplitView {
                editor
                MarkdownPreviewView(
                    text: tab.content,
                    language: tab.language,
                    cursor: previewCursor,
                    // 预览里的链接**默认开在已内嵌的浏览器页签里**（契约 `FR-EDIT-45`）：
                    // 走的是**地址栏回车同一条路**（`openInBrowser` → `BrowserSession.parseAddress`
                    // → 引擎的策略裁决 + 统一外发日志）—— 预览自己**不判**能不能加载，
                    // 也不弹系统浏览器（`MarkdownPreviewView` 把 `openURL` 收在自己那一层）。
                    openLink: { target in browser.openInBrowser(target) }
                )
            }
        } else {
            editor
        }
    }

    /// 底部提示条：快捷键提示 + **Markdown 预览开关**（只有 Markdown 文件才给这个开关 ——
    /// 别的语言上它按下去不会有任何变化，那是"可点却无反应"）。
    private func hintBar(tab: WorkspaceTab) -> some View {
        HStack(spacing: Spacing.s) {
            Text(L(.workspaceEditorHint))
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.text(.tertiary))
                .lineLimit(1)
            Spacer(minLength: Spacing.s)
            if tab.language == .markdown {
                Button {
                    tabs.togglePreview()
                } label: {
                    Label(
                        L(.workspacePreviewToggle),
                        systemImage: tabs.previewVisible ? "sidebar.right" : "sidebar.squares.right"
                    )
                    .font(Theme.font(.caption))
                }
                .buttonStyle(.borderless)
                .help(L(.workspacePreviewToggle))
            }
        }
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.hair)
    }

    /// 底部消息条：错误优先，其次一次性提示。**不静默**——打不开、存不下都要说出来。
    @ViewBuilder
    private var messageBar: some View {
        if let error = tabs.errorText {
            messageRow(text: error, symbol: "exclamationmark.triangle.fill", tone: Theme.status(.danger)) {
                tabs.errorText = nil
            }
        } else if let notice = tabs.noticeText {
            messageRow(text: notice, symbol: "checkmark.circle", tone: Theme.status(.success)) {
                tabs.noticeText = nil
            }
        }
    }

    private func messageRow(text: String, symbol: String, tone: Color, dismiss: @escaping () -> Void) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: symbol)
                .font(Theme.font(.caption))
                .foregroundStyle(tone)
            Text(text)
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.text(.secondary))
                .lineLimit(2)
                .textSelection(.enabled)
            Spacer(minLength: Spacing.s)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(Theme.font(.caption))
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.xs)
        .background(tone.opacity(0.10))
    }

}

/// 工作区的 **Home 欢迎页**（FR-EDIT-35）：欢迎语 / 版本与版权 / 最近打开。
struct WorkspaceHomeView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var workspace: WorkspaceStore
    @EnvironmentObject private var tabs: WorkspaceTabsModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                header
                actionRow
                HStack(alignment: .top, spacing: Spacing.l) {
                    recentFiles
                    recentWorkspaces
                    connections
                }
            }
            .padding(Spacing.xl)
            .frame(maxWidth: 1_100, alignment: .leading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(L(.workspaceHomeWelcome))
                .font(Theme.font(.title))
                .foregroundStyle(Theme.text(.primary))
            Text(L(.workspaceHomeSubtitle))
                .font(Theme.font(.body))
                .foregroundStyle(Theme.text(.secondary))
                .fixedSize(horizontal: false, vertical: true)
            Text(L(.workspaceHomeBuildLine, Self.appVersion, Self.appBuild))
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.text(.tertiary))
            Text(L(.workspaceHomeCopyright))
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.text(.tertiary))
        }
    }

    private var actionRow: some View {
        HStack(spacing: Spacing.s) {
            Button {
                openFileFromPanel()
            } label: {
                Label(L(.workspaceOpenFileButton), systemImage: "doc.text")
            }

            if workspace.rootURL == nil {
                Button {
                    Task { await workspace.pickAndChoose() }
                } label: {
                    Label(L(.workspaceChooseFolderButton), systemImage: "folder")
                }
            }
        }
    }

    private var recentFiles: some View {
        homeSection(title: L(.workspaceRecentFiles), empty: L(.workspaceRecentFilesEmpty), rows: tabs.history.files) { entry in
            Button {
                tabs.openFile(at: URL(fileURLWithPath: entry.path))
            } label: {
                homeRow(title: entry.displayName, detail: entry.path, symbol: "doc.text")
            }
            .buttonStyle(.plain)
            .help(entry.path)
        }
    }

    private var recentWorkspaces: some View {
        homeSection(title: L(.workspaceRecentWorkspaces), empty: L(.workspaceRecentWorkspacesEmpty), rows: tabs.history.workspaces) { entry in
            // 最近工作区**只展示**：重新切换要走目录授权（书签），不能拿一条历史路径冒充授权。
            homeRow(title: entry.displayName, detail: entry.path, symbol: "folder")
        }
    }

    private var connections: some View {
        homeSection(
            title: L(.workspaceConnections),
            empty: L(.workspaceConnectionEmpty),
            rows: appState.connections.map { WorkspaceHistoryEntry(path: $0.displayTitle(untitled: L(.connectionUntitled))) }
        ) { entry in
            Button {
                if let configuration = appState.connections.first(where: { $0.displayTitle(untitled: L(.connectionUntitled)) == entry.path }) {
                    appState.selectedConnectionID = configuration.id
                    // 走统一入口：工作区首页的"去数据库"也是能钻进未授权区的一条路，
                    // 当前档位不含数据库时它会照实说一句，而不是切到一个画不出来的视图。
                    appState.selectActivityItem(.database)
                }
            } label: {
                homeRow(title: entry.displayName, detail: entry.path, symbol: "cylinder.split.1x2")
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func homeSection<Row: View>(
        title: String,
        empty: String,
        rows: [WorkspaceHistoryEntry],
        @ViewBuilder row: @escaping (WorkspaceHistoryEntry) -> Row
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(Theme.font(.bodyStrong))
                .foregroundStyle(Theme.text(.primary))

            if rows.isEmpty {
                Text(empty)
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.tertiary))
            } else {
                ForEach(rows.prefix(8)) { entry in
                    row(entry)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func homeRow(title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: symbol)
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.text(.tertiary))
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.primary))
                    .lineLimit(1)
                Text(detail)
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.tertiary))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Spacing.hair)
        .contentShape(Rectangle())
    }

    private func openFileFromPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = L(.workspaceOpenFileButton)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        tabs.openFile(at: url)
    }

    private static var appVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "—"
    }

    private static var appBuild: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "—"
    }
}
