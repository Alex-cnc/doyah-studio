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
    /// 对话页签的状态所有者（`FR-AI-25`）—— 同上：独立模型，与工作区页签并列。
    @EnvironmentObject private var agentChat: AgentChatModel
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
        .onAppear { syncPreviewCursor() }
        // 编辑区 AI 辅助面板（`FR-STD-WS-AI-001`）：菜单「AI 辅助」那一组打开它。
        .sheet(isPresented: Binding(
            get: { appState.editAssist.isPresented },
            set: { appState.editAssist.isPresented = $0 }
        )) {
            EditAssistSheet(model: appState.editAssist)
        }
        .sheet(isPresented: $appState.isDebugPanelPresented) {
            DebugPanelView(model: appState.debugSession)
        }
        // 换页签 / 关页签都要过一遍：行号按页签各记一份（`FR-STD-WS-WEB-002` 收口片），
        // 否则切到另一篇时预览拿着上一份文档的行号去找落点。
        .onChange(of: tabs.selectedID) { _, _ in syncPreviewCursor() }
        .onChange(of: tabs.tabs.map(\.id)) { _, _ in syncPreviewCursor() }
        // 底色由父层统一给（`sectionWithLowerPane` 的 `NebulaBackground`）——
    // 这里再铺不透明色会把星云皮肤**整片盖住**（2026-10-01 实测）。
    .background(Color.clear)
    }

    /// 把预览的跟随输入面对齐到「当前选中的页签 + 还开着的页签集」。
    ///
    /// 两件事各有由头：**激活**换的是「跟哪一份文档」；**收**掉的是「已经关了的页签记下的位置」——
    /// 同一个文件再打开会得到新的页签标识，旧记录留着也没人再按那个号取。
    private func syncPreviewCursor() {
        previewCursor.retain(tabs: tabs.tabs.map(\.id))
        if let id = tabs.selectedID {
            previewCursor.activate(tab: id)
        }
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
            } else if tab.isAgentChat {
                // 对话页签：**就在 Home 区这一格里**呈现（不自带侧栏 / 分栏 —— `FR-AI-25` ①）。
                AgentChatView(model: agentChat)
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
            pendingAssist: tabs.assistDelivery,
            onTextChange: { text in tabs.updateContent(text, for: tab.id) },
            onSave: { tabs.save(tab.id) },
            onFormat: { tabs.formatSelected() },
            // 行内灰字的路径候选按工作区取表（`FR-EDIT-57` 最后一块）。
            workspaceRoot: workspace.rootURL,
            onCursorLine: { line in previewCursor.report(line: line, tab: tab.id) },
            // 会话恢复（`FR-EDIT-43` 第二片）：这一页上次退出时的插入点与滚动位置（取走即没）。
            takeCursorPlacement: { id in tabs.takeCursorPlacement(for: id) },
            // 现场读数上报 —— 退出时落快照的输入面（选区变化 / 滚动各报一次）。
            onCursorPosition: { id, caret, scroll in
                tabs.reportCursor(tabID: id, caretOffset: caret, scrollOffset: scroll)
            },
            // 缩进口径（`FR-STD-WS-EDIT-022`）：状态栏显示的那一格与这里读的是同一个值 ——
            // 按一次 Tab 插什么、回车继承几级，都跟状态栏上写的一致。
            indent: tabs.indentProfile(for: tab.id),
            // 代码折叠（`FR-STD-WS-EDIT-017`）：标记 + 该藏哪几段由模型算好；这里只把
            // 「点了标记 / 光标进了折起来的块 / 内容稳定了」三条事回投给模型。
            foldPresentation: tabs.foldPresentation(for: tab.id),
            onToggleFold: { line in tabs.toggleFold(tabID: tab.id, line: line) },
            onCaretEnteredFoldedBlock: { line in tabs.unfoldAroundCaret(tabID: tab.id, line: line) },
            onDocumentSettled: { tabs.refreshFolds(tabID: tab.id) }
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
        } else if webPageTab(tab) && tabs.previewVisible {
            // 网页文件（`FR-STD-WS-WEB-003`）：与 Markdown 预览**同一套交互** —— 左边源码、右边渲染，
            // 中间那条分隔线可拖。渲染由与浏览器页签**同一个引擎**做（策略 / 外发留痕 / 读权限一份口径），
            // 「要不要地址栏 / 后退 / 本地服务」那条出路交给浏览器页签（同一份文件的另一个页签）。
            HSplitView {
                editor
                HTMLPreviewView(
                    tabID: tab.id,
                    path: tab.path,
                    isDirty: tab.isDirty,
                    content: tab.content,
                    onOpenInBrowser: { url in browser.openFileInBrowser(url) }
                )
            }
        } else {
            editor
        }
    }

    /// 这个页签是不是「该由网页引擎渲染」的那一类（知识住在语言登记表，问的唯一入口在页签模型里）。
    private func webPageTab(_ tab: WorkspaceTab) -> Bool {
        tabs.supportsWebPagePreview(path: tab.path)
    }

    /// 底部提示条：快捷键提示 + **缩进口径**（`FR-STD-WS-EDIT-022`）+ **预览开关**
    /// （Markdown 与网页文件共用这一枚 —— 别的语言上它按下去不会有任何变化，那是"可点却无反应"）。
    private func hintBar(tab: WorkspaceTab) -> some View {
        HStack(spacing: Spacing.s) {
            Text(L(.workspaceEditorHint))
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.text(.tertiary))
                .lineLimit(1)
            Spacer(minLength: Spacing.s)
            formatMenu(tab: tab)
            indentMenu(tab: tab)
            if tab.language == .markdown || webPageTab(tab) {
                Button {
                    tabs.togglePreview()
                } label: {
                    Image(systemName: tabs.previewVisible ? "sidebar.right" : "sidebar.squares.right")
                        .font(Theme.font(.caption))
                }
                .buttonStyle(.borderless)
                .help(webPageTab(tab) ? L(.workspaceHTMLPreviewToggle) : L(.workspacePreviewToggle))
            }
        }
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.hair)
    }

    // MARK: 编码与换行那一格（`FR-STD-WS-EDIT-023`）
    //
    // 状态栏说、菜单改，两件事读同一格数据（`WorkspaceTab.format`）。说的必须是**这一页现在
    // 的形态**：用户切到 GB18030 之后那一格就该显示 GB18030（而不是盘上还是 UTF-8）——
    // 于是那格与页签的"未保存"标记一起说清"这个改动还没写下去"。

    /// 状态栏上那一格：`UTF-8 · CRLF`。
    private func formatLabel(_ format: TextFileFormat) -> String {
        format.displayName
    }

    /// 形态菜单：编码两档 + 换行两档 + 「按文件重新判定」。每一项都走页签模型那一个入口。
    @ViewBuilder
    private func formatMenu(tab: WorkspaceTab) -> some View {
        Menu {
            if tab.hasPendingFormatChange {
                Text(L(.workspaceFormatPendingSave))
                Divider()
            }
            Text(L(.workspaceFormatEncodingSection))
            ForEach(ResultExportEncoding.allCases, id: \.self) { encoding in
                Button {
                    tabs.chooseEncoding(tabID: tab.id, encoding: encoding)
                } label: {
                    indentMenuItem(encoding.shortName, checked: tab.format.encoding == encoding)
                }
            }
            Divider()
            Text(L(.workspaceFormatLineEndingSection))
            ForEach(LineEnding.selectable, id: \.self) { ending in
                Button {
                    tabs.chooseLineEnding(tabID: tab.id, lineEnding: ending)
                } label: {
                    indentMenuItem(ending.shortName, checked: tab.format.lineEnding == ending)
                }
            }
            // 混排是**判出来的事实**，不是可选口径：给一行只读的说明，别给一个点了没用的勾。
            if tab.format.lineEnding == .mixed {
                indentMenuItem(LineEnding.mixed.shortName, checked: true)
            }
            Divider()
            Button {
                tabs.redetectFormat(tabID: tab.id)
            } label: {
                Text(L(.workspaceFormatRedetect))
            }
        } label: {
            Text(formatLabel(tab.format))
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.text(.secondary))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(L(.workspaceFormatMenuHelp))
    }

    // MARK: 缩进口径那一格（`FR-STD-WS-EDIT-022`）
    //
    // **状态栏说、菜单改，两件事读同一格数据**（`WorkspaceTab.indent`）：说的是「按内容判出来的
    // 是什么」而不是「缺省是什么」—— 判不出证据时如实说「用的是缺省」，不冒充「按内容判定」。
    // 这些文案与「制表符 / 空格」这一档话全部走语言表（Core 里没有用户可见文案）。

    /// 状态栏上那一格：`空格 · 4` / `制表符 · 4`。
    private func indentLabel(_ profile: IndentProfile) -> String {
        // 实参写成 `String(...)` 的形式：门禁按形状认类型（裸标识符会被判成「类型不明」）。
        profile.style == .tabs
            ? L(.workspaceIndentTabsLabel, String(profile.width))
            : L(.workspaceIndentSpacesLabel, String(profile.width))
    }

    /// 这个口径是怎么来的（菜单第一行那句话）。
    private func indentOriginText(_ profile: IndentProfile) -> String {
        switch profile.origin {
        case .detected: return L(.workspaceIndentOriginDetected)
        case .chosen: return L(.workspaceIndentOriginChosen)
        case .fallback: return L(.workspaceIndentOriginFallback)
        }
    }

    /// 缩进菜单：软 / 硬两档 + 宽度四档 + 「按内容重新判定」，每项都走页签模型那一个入口。
    @ViewBuilder
    private func indentMenu(tab: WorkspaceTab) -> some View {
        let profile = tabs.indentProfile(for: tab.id)
        let widths = [2, 3, 4, 8]
        Menu {
            Text(indentOriginText(profile))
            if profile.conflictingLines > 0 {
                Text(L(.workspaceIndentMixed, String(profile.conflictingLines)))
            }
            Divider()
            Button {
                tabs.chooseIndent(tabID: tab.id, style: .spaces)
            } label: {
                indentMenuItem(L(.workspaceIndentUseSpaces), checked: profile.style == .spaces)
            }
            Button {
                tabs.chooseIndent(tabID: tab.id, style: .tabs)
            } label: {
                indentMenuItem(L(.workspaceIndentUseTabs), checked: profile.style == .tabs)
            }
            Divider()
            ForEach(widths, id: \.self) { width in
                Button {
                    tabs.chooseIndent(tabID: tab.id, width: width)
                } label: {
                    indentMenuItem(L(.workspaceIndentWidth, String(width)), checked: profile.width == width)
                }
            }
            Divider()
            Button {
                tabs.redetectIndent(tabID: tab.id)
            } label: {
                Text(L(.workspaceIndentRedetect))
            }
        } label: {
            Text(indentLabel(profile))
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.text(.secondary))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(L(.workspaceIndentMenuHelp))
    }

    /// 菜单项：勾选的那一档画一枚对勾，其余留一个等宽的空位（**不缩进错位**）。
    private func indentMenuItem(_ title: String, checked: Bool) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "checkmark")
                .font(Theme.font(.caption))
                .opacity(checked ? 1 : 0)
            Text(title)
        }
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
            .accessibilityLabel(Text(L(.commonClose)))
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
            Text(L(.workspaceHomeBuildLine, Self.appVersion, Self.buildStamp))
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
                Image(systemName: "doc.text")
            }
            .help(L(.workspaceOpenFileButton))

            if workspace.rootURL == nil {
                Button {
                    Task { await workspace.pickAndChoose() }
                } label: {
                    Image(systemName: "folder")
                }
                .help(L(.workspaceChooseFolderButton))
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
        // 来源与动作都与文件树标头那一枚**同一份**（`FR-STD-WS-FS-010`）：
        // 原来这里只展示、点不动 —— 首页看得见却用不上，而「切换」正是从这条清单出发的动作。
        // 也不再用页签历史里的工作区路径：那是「打开过哪些」的流水，不是「还能切到哪些」的授权表
        // （拿一条历史路径冒充授权，是沙箱下唯一会失败的那条路）。
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(L(.workspaceRecentWorkspaces))
                .font(Theme.font(.bodyStrong))
                .foregroundStyle(Theme.text(.primary))

            if workspace.knownWorkspaces.isEmpty {
                Text(L(.workspaceRecentWorkspacesEmpty))
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.tertiary))
            } else {
                ForEach(workspace.knownWorkspaces.prefix(8)) { item in
                    WorkspaceKnownRow(item: item)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        WorkspaceOpenFilePanel.present { tabs.openFile(at: $0) }
    }

    private static var appVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "—"
    }

    private static var appBuild: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "—"
    }

    /// 构建戳（`<提交数>.<sha7> · <时刻>`）：首页那行直接显示它，
    /// 一眼能分出装的是哪一版（发布标签 `beta1.0` 是不变的）。
    private static var buildStamp: String {
        (Bundle.main.object(forInfoDictionaryKey: "DoyahBuildStamp") as? String) ?? appBuild
    }
}
