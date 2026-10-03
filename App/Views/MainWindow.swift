import SwiftUI
import DoyahCore

/// 连接表单的展示模式。
/// 用 `.sheet(item:)` 而不是 `isPresented` + 可选值，
/// 避免「点编辑却弹出新建、字段为空」的状态捕获问题。
enum ConnectionFormMode: Identifiable {
    case new
    case edit(ConnectionConfig)

    var id: String {
        switch self {
        case .new:
            return "new"
        case .edit(let configuration):
            return configuration.id.uuidString
        }
    }

    var configuration: ConnectionConfig? {
        switch self {
        case .new:
            return nil
        case .edit(let configuration):
            return configuration
        }
    }

    var isNew: Bool {
        if case .new = self { return true }
        return false
    }
}

struct MainWindow: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var localization: LocalizationManager
    @EnvironmentObject private var workspace: WorkspaceStore
    @State private var contentWidth: CGFloat = 0
    @State private var formMode: ConnectionFormMode?

    /// 侧栏内容由活动栏决定（「看哪个视图」与「视图里看什么」分开）。
    @ViewBuilder
    private var sidebarContent: some View {
        // **星云皮肤**（星空紫「星云皮肤」· 2026-10-01 需求提出者要的「皮肤」质感；派单 `T-20261001-031`／`T-20261001-037`；队列 `L-153`）：侧栏是"星云"最该出现的地方（它是 chrome，不是阅读区），
        // 所以云气与星点都给满。`NebulaSurface` 先铺表面令牌色再叠星云 ——
        // 主题不是星空紫、或用户关了皮肤时，它**逐像素回到纯色表面**。
        NebulaSurface(surface: .sidebar, layer: .sidebar) {
            switch appState.selectedActivityItem {
            case .database:
                ConnectionListView(
                    onAdd: { formMode = .new },
                    onEdit: { configuration in formMode = .edit(configuration) }
                )
            case .workspace:
                WorkspaceExplorerView()
            case .notes:
                // 笔记的"看哪个视图"= 笔记栏，"视图里看什么" = 选哪一条笔记（列表在侧栏、编辑在右边）。
                NotesListView()
            }
        }
    }

    /// **窗口标题**（FR-EDIT-37）：`Doyah Studio - 数据库 / - 工作区 / - 笔记`。
    ///
    /// 由**活动栏项**派生（`ActivityBarItem.titleKey`）—— 以后 Retro 模块进活动栏，标题自动跟上；
    /// 品牌段与视图名都从语言表取（`appBrand` / 视图名），所以中英界面各出各的形状。
    private var windowTitle: String {
        WindowTitle.text(
            brand: L(.appBrand),
            suffix: L(appState.selectedActivityItem.titleKey)
        )
    }

    /// **下方面板（问题 / 输出 / 终端 / 调试控制台）在「工作区」与「数据库」两段之间共享**
    /// （2026-09-30 需求提出者实测反馈：「数据库客户端界面的底部栏怎么只在数据库界面出现，到了工作区
    /// 就没有了呢…要不然主工作区下方啥也没有，要打开 terminal 开始工作还要先点击 database 活动栏」）。
    ///
    /// 三条落法：
    ///  ① **只有一个实例** —— 终端会话活在 `TerminalModel` 上（L-84 ㈠ 的契约），
    ///     两段各画一份会让同一个会话被渲染两次（屏幕缓冲/选区就成两份了）；
    ///  ② **查询页签可空** —— 数据库段传当前页签（「问题 / 输出」有上下文），
    ///     工作区段传 nil（那两页如实显示空态，终端照常可用）；
    ///  ③ **最大化仍覆盖整段** —— 判在段一级，所以两段行为一致。
    @ViewBuilder
    private func sectionWithLowerPane<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        // 折叠态的判定只在这里取一次，往下传给两处（面板自己 + 高度提示）——
        // 免得「谁折叠」有两处口径。
        let collapsed = !appState.isLowerPaneVisible
        VStack(spacing: 0) {
            if appState.isLowerPaneVisible, appState.isLowerPaneMaximized {
                LowerPaneView(tab: appState.selectedTab)
            } else {
                // **星云皮肤用显式叠层**：`.background()` 是铺在内容**下层**，
                // 只要内容里有任何一处不透明就会被整片盖住（2026-10-01 实测：侧栏能看到星云、
                // 内容区看不到，根因就是 `QueryWorkspaceView` 自己铺了 `.background(.content)`）。
                // 改成 `ZStack` 后**星云在下、内容在上**，且 `allowsHitTesting(false)` 不吃点击。
                ZStack {
                    Theme.surface(.content)
                    NebulaBackground(layer: .content)
                    content()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // 顶边**拖拽把手**（队列 `L-181`）：拖动改面板高度，拖出来的值持久化在 `AppState`。
                // 为什么不是回到 `VSplitView`：它的子视图数必须在构建时固定，显示/隐藏之间切换会
                // **重建编辑器子树**（`App/Views/SQLEditorView.swift:58` 有实测记录）—— 那会把正在
                // 编辑的滚动位置与撤销栈一起弄丢。这条把手只改面板自身的高度，**层级不变**。
                LowerPaneResizeHandle(
                    height: appState.lowerPaneHeight,
                    available: lowerPaneAvailableHeight
                ) { appState.lowerPaneHeight = $0 }
                LowerPaneView(tab: appState.selectedTab, isCollapsed: collapsed)
                    // 高度提示**由面板自己那一层算**（`LowerPaneSizing`）：
                    // 折叠态必须是「不设约束」，否则这里会留下一条比标题栏宽的空白带
                    // （2026-09-30 需求提出者实测缺陷，队列 `L-121`—— 原来这里写死
                    //  `.frame(minHeight: 90, idealHeight: 200)`，折叠后那 90pt 的框还在）。
                    .frame(
                        minHeight: LowerPaneSizing.minHeight(collapsed: collapsed),
                        idealHeight: lowerPaneIdealHeight(collapsed: collapsed)
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var body: some View {
        HStack(spacing: 0) {
            // 活动栏在 `NavigationSplitView` **外面**：它是应用级 chrome，不属于可调宽的侧栏
            // （与 VS Code 一致 —— 拖拽侧栏宽度时活动栏不动）。
            ActivityBarView()
            NavigationSplitView {
                sidebarContent
                    .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 380)
            } detail: {
            // 下方面板（结果 / 问题 / 输出 / 终端 / 调试控制台）已经并进工作区本身，
            // 所以这里不再另开一块区域。
            //
            // **右边也要跟着活动栏切**（FR-EDIT-35）：以前不管选哪个活动项都显示 SQL 查询界面 ——
            // 需求提出者的原话是「点击工作区时，不应该还在数据库 SQL 查询界面，应该是新的 Tab 界面」。
            switch appState.selectedActivityItem {
            case .database:
                sectionWithLowerPane { QueryWorkspaceView() }
            case .workspace:
                sectionWithLowerPane { WorkspaceAreaView() }
            case .notes:
                NotesEditorView()
            }
            }
            // **窗口标题跟着活动栏走**（FR-EDIT-37，2026-09-30 需求提出者）：
            // 原话「软件主界面的标题就是一个 Doyah Studio 太浪费了…标题要跟着变成
            // Doyah Studio - Workspace / - Database / - Notes 这种」。
            .navigationTitle(windowTitle)
            // **标题后面居中的搜索栏**（FR-EDIT-37）：位置仍是工具条的**正中**位，
            // 但宽度**不再由系统给** —— 系统给的是一个与窗口宽度无关的宽度，窗口一窄就压住标题
            // （需求提出者 2026-09-30 内测甲1：「不是全屏时搜索框没有同步缩小，遮住了
            // `Doyah Studio - Workspace` 标题」）。宽度改由 `TitleBarSearchLayout` 给：
            // 窗口变窄 ⇒ 收敛；窄到放不下 ⇒ 整条不显示（回车入口仍在 ⌘K / 命令面板）。
            .toolbar {
                ToolbarItem(placement: .principal) {
                    TitleBarSearchField(windowWidth: contentWidth, titleText: windowTitle)
                        .environmentObject(appState)
                }
            }
        }
        // **内容区宽度**（队列 `L-141`）：搜索栏的宽度策略要吃一个「窗口有多宽」，
        // 而标题栏与内容区同宽 ⇒ 在内容区量一次就够（工具条里的那一枚自己量不到窗口）。
        // 用 `preference` 而不是 `GeometryReader` 包住内容：后者会改掉内容的排布方式。
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: MainWindowContentWidthKey.self, value: proxy.size.width)
            }
        )
        .onPreferenceChange(MainWindowContentWidthKey.self) { width in
            contentWidth = width
        }
        // **启动就按「当前默认呈现的是哪个功能」对齐菜单项**（2026-10-02 需求提出者原话：
        // 「应用启动时就该检查当前默认呈现的是那个功能，来决定菜单项」）。`MainMenuLocalizer` 那一层
        // 不持有 `AppState`，所以由窗口把**权威值**（许可证解析之后的那个）喂给它 —— `AppState`
        // 自己发的广播也走同一条路，两条都留着：这条不依赖「观察者装好了没 / 菜单建好了没」的先后。
        .task {
            MainMenuLocalizer.syncAreaVisibility(appState.selectedActivityItem)
        }
        .onChange(of: appState.selectedActivityItem) { _, item in
            MainMenuLocalizer.syncAreaVisibility(item)
        }
        .sheet(item: $formMode) { mode in
            ConnectionFormView(
                configuration: mode.configuration,
                existingConnections: appState.connections,
                storedPassword: { mode.configuration.flatMap { appState.password(for: $0) } }
            ) { configuration, password, sshPassword in
                Task {
                    if mode.isNew {
                        await appState.addConnection(
                            configuration,
                            password: password,
                            sshPassword: sshPassword
                        )
                    } else {
                        await appState.updateConnection(
                            configuration,
                            password: password.isEmpty ? nil : password,
                            sshPassword: sshPassword
                        )
                    }
                    formMode = nil
                }
            }
        }
        // 命令面板（FR-EDIT-25）：⌘K 唤起。用隐藏按钮承载快捷键 ——
        // SwiftUI 里这是"不占用菜单项也能挂全局快捷键"的常规做法；
        // 面板自身的 ↑↓ / ↩ / esc 语义由 `CommandPaletteView` 处理。
        //
        // 说明：本轮的快捷键**没有**登记进 `AppShortcut`（帮助面板因此还看不到它），
        // 这条缺口写在需求行的"仍未做"里，不假装已完成。
        .background(
            Button("") { appState.presentCommandPalette() }
                .keyboardShortcut("k", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        )
        .sheet(isPresented: $appState.isCommandPalettePresented) {
            CommandPaletteView()
                .environmentObject(appState)
        }
        // 查询参数面板（FR-EXEC-17）：执行时若有占位符就弹出来填值。
        .sheet(isPresented: $appState.isQueryParameterSheetPresented) {
            QueryParameterSheet()
                .environmentObject(appState)
        }
        .sheet(isPresented: $appState.isAgentSettingsPresented) {
            AgentSettingsSheet()
        }
        .sheet(isPresented: $appState.isAppearancePresented) {
            AppearanceSheet()
                .environmentObject(appState)
        }
        // 连接设置（FR-CONN-20）：保活心跳的开关与间隔。
        .sheet(isPresented: $appState.isConnectionSettingsPresented) {
            ConnectionSettingsSheet()
                .environmentObject(appState)
        }
        // 数据库统计（FR-DIAG-04）：四类指标只读采集。
        .sheet(isPresented: $appState.isDatabaseStatsPresented) {
            DatabaseStatsPanel()
                .environmentObject(appState)
        }
        // 诊断这条查询（FR-AI-03）：先取证（真库跑 EXPLAIN / 锁查询），再解读模型回答。
        .sheet(isPresented: $appState.isDiagnosisPresented) {
            DiagnosisPanel()
                .environmentObject(appState)
        }
        // 维护任务编排（FR-AI-04）：审阅 → 逐条批准 / 拒绝 → 执行已批准的。
        .sheet(isPresented: $appState.isMaintenancePresented) {
            MaintenancePanel()
                .environmentObject(appState)
        }
        // 版本与许可证（FR-LIC-02）：活动栏上有哪几项由它决定，所以这一页必须能随时打开
        // （用户看到某个区不见了，第一反应就是找"为什么"）。
        .sheet(isPresented: $appState.isAboutLicensePresented) {
            AboutLicenseSheet()
                .environmentObject(appState)
        }
        // 外部调用审批（FR-AI-10 界面那一半）：外部智能体的写调用在这里等人点。
        .sheet(isPresented: $appState.isMCPApprovalPresented) {
            MCPApprovalPanel()
                .environmentObject(appState)
        }
        // Schema 对比与同步（FR-DDL-04）：两侧结构差异 + 同步脚本。
        .sheet(isPresented: $appState.isSchemaDiffPresented) {
            SchemaDiffPanel()
                .environmentObject(appState)
        }

        // ER 图 / 关系图（FR-DDL-05）：由外键元数据画的只读图。
        .sheet(isPresented: $appState.isERDiagramPresented) {
            ERDiagramPanel()
                .environmentObject(appState)
        }
        // 服务器级对象（FR-SESS-03）：角色 / 表空间 / 扩展的浏览与增删改。
        .sheet(isPresented: $appState.isServerObjectsPresented) {
            ServerObjectsPanel()
                .environmentObject(appState)
        }
        // 外键跳转目标选择（FR-DATA-06）：一列被多条外键引用时才出现。
        .sheet(item: $appState.pendingForeignKeyJump) { request in
            ForeignKeyJumpSheet(request: request)
                .environmentObject(appState)
        }
        .alert(
            L(.accountUndecidedTitle),
            isPresented: $appState.isAccountNoticePresented
        ) {
            Button(L(.commonOk), role: .cancel) {}
        } message: {
            Text(L(.accountUndecidedMessage))
        }
        .sheet(isPresented: $appState.isAgentSQLPresented) {
            AgentSQLPanel()
        }
        .sheet(isPresented: $appState.isAgentAuditPresented) {
            AgentAuditPanel()
        }
        .sheet(isPresented: $appState.isEgressLogPresented) {
            EgressLogSheet()
        }
        .sheet(isPresented: $appState.isDataTaskPresented) {
            DataTaskPanel()
        }
        .sheet(isPresented: $appState.isExecutionPlanPresented) {
            if let tab = appState.selectedTab {
                ExecutionPlanPanel(tabID: tab.id)
            }
        }
        .sheet(item: $appState.pendingExecution) { pending in
            SafeModeConfirmSheet(
                reasons: pending.reasons,
                statements: pending.statements,
                onConfirm: { Task { await appState.confirmPendingExecution(pending) } },
                onCancel: { appState.cancelPendingExecution() }
            )
        }
        .sheet(isPresented: $appState.isSQLArchivePresented) {
            SQLArchiveSheet()
        }
        // ⌘K 命令面板里这三条（帮助 / 切换连接 / 全库对象搜索）都挂在**窗口**上：
        // 工具栏按钮只在某个页签存在时才在，而命令面板是全局入口 ——
        // 挂在窗口上，无论当前在看哪个视图，命令都不会落空。
        .sheet(isPresented: $appState.isShortcutHelpCommandPresented) {
            // 与工具栏「?」气泡**同一份内容**（`ShortcutHelpContent`），只是呈现方式不同。
            ShortcutHelpContent()
                .frame(width: 420)
        }
        .sheet(isPresented: $appState.isConnectionSwitchPresented) {
            ConnectionSwitchSheet()
                .environmentObject(appState)
        }
        .sheet(isPresented: $appState.isObjectSearchPresented) {
            ObjectSearchPanel()
                .environmentObject(appState)
        }
        .sheet(isPresented: $appState.isRoutineCandidatesPresented) {
            RoutineCandidatesPanel()
                .environmentObject(appState)
        }
        .sheet(isPresented: $appState.isBackupRestorePresented) {
            BackupRestoreSheet()
                .environmentObject(appState)
        }
        // 导入数据（FR-IO-03）：挂在窗口上 —— 菜单与 ⌘K 都是全局入口，
        // 不依赖"当前视图里正好有对象树"。目标表默认取对象树选中项，没有也能手输。
        .sheet(isPresented: $appState.isImportPresented) {
            ImportPanel()
                .environmentObject(appState)
        }
        // 显式「重启应用」（R-36）。**换语言不再走这里** —— 语言是就地切换的，
        // 系统菜单由 `MainMenuLocalizer` 运行时改写；这条入口只服务"我就是想重开一个进程"。
        .sheet(isPresented: $localization.isRelaunchPromptPresented) {
            RelaunchPromptSheet()
        }
        .task {
            // 工作区（FR-EDIT-32）：读回授权书签并把路径交给终端作为启动目录。
            // 终端对象挂在 App 层，这里通过环境取不到它（它在 environment 里但需要 @EnvironmentObject）。
            // 因此工作区路径由 App 层直接订阅 —— 见 `DoyahStudioApp`。
            await workspace.load()
            await appState.loadAgentConfiguration()
            // 数据任务需要在客户端运行期间一直被调度（FR-AI-06）：
            // 启动时读一次任务与执行历史，然后由 App 侧的 tick 驱动 Core 的纯时间判定。
            await appState.loadDataTasks()
            appState.startDataTaskTicker()
            // 连接保活心跳（FR-CONN-20）：空闲连接按间隔发一条轻量查询
            appState.startKeepAliveTicker()
            // 归档目录状态与查询记忆索引（FR-AI-13 S2）：启动就读一次，
            // 否则要等用户打开归档面板之后补全才有记忆。
            await appState.refreshSQLArchiveStatus()
        }
        .alert(
            L(.alertErrorTitle),
            isPresented: Binding(
                get: { appState.errorMessage != nil },
                set: { if !$0 { appState.errorMessage = nil } }
            )
        ) {
            // 系统弹窗的正文**不能选中**，所以给一个复制按钮 —— 错误原文一长串，
            // 截图或手抄都会丢信息（用户实测反馈过这一条）。
            Button(L(.connectionFormCopyFullError)) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(appState.errorMessage ?? "", forType: .string)
            }
            Button(L(.commonOk), role: .cancel) {}
        } message: {
            Text(appState.errorMessage ?? "")
        }
    }
}

/// 内容区宽度的**唯一出处**（队列 `L-141`）：标题栏搜索栏的宽度策略吃这个数。
/// 取 `max` 归并 —— 窗口里有分栏时，几何读数会有多份，取最大的那份（= 整个内容区）才不会偏小。
private struct MainWindowContentWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// 「切换连接」的**最小可用**面板（⌘K → 切换连接）。
///
/// 为什么不复用现成的服务器选择器：它有两处（侧栏连接列表、查询上下文栏），
/// 但都要求"当前视图里正好有它"——上下文栏只在工作区顶部，命令面板不该依赖这个。
/// 所以这里给一个窄列表：点一行就切过去，别的不做（新建 / 编辑仍在侧栏，
/// 不在这里重复一套表单）。
struct ConnectionSwitchSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text(L(.commandSwitchConnection))
                .font(Theme.font(.title))

            if appState.connections.isEmpty {
                Text(L(.connectionListEmpty))
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.secondary))
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(appState.connections) { configuration in
                            row(configuration)
                        }
                    }
                }
                .frame(maxHeight: 320)
            }

            HStack(spacing: Spacing.s) {
                Spacer()
                Button(L(.commonClose)) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(Spacing.l)
        .frame(width: 380)
        .background(Theme.surface(.panel))
    }

    private func row(_ configuration: ConnectionConfig) -> some View {
        let isCurrent = configuration.id == appState.selectedConnectionID
        return HStack(spacing: Spacing.s) {
            // 环境徽标与侧栏 / 上下文栏是**同一个组件**：别处一眼能分辨生产库，这里也要能。
            ConnectionEnvironmentBadge(appearance: configuration.appearance, isCompact: true)

            VStack(alignment: .leading, spacing: Spacing.hair) {
                Text(configuration.displayTitle(untitled: L(.connectionUntitled)))
                    .font(Theme.font(.body))
                    .foregroundStyle(Theme.text(.primary))
                    .lineLimit(1)
                Text(configuration.endpointDescription)
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.tertiary))
                    .lineLimit(1)
            }

            Spacer()

            if isCurrent {
                Image(systemName: "checkmark")
                    .foregroundStyle(Theme.accentColor)
            }
        }
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.xs)
        .contentShape(Rectangle())
        .onTapGesture {
            appState.selectedConnectionID = configuration.id
            dismiss()
        }
    }
}

// MARK: - L-181：下方面板顶边的拖拽把手

/// 下方面板顶边的**拖拽把手**（队列 `L-181`）。
///
/// 形态：一条发丝线 + 一个 8pt 高的命中区（2pt 的线谁也点不着 —— 判据①「随时能拖」要真能拖）。
/// 拖动按**相对位移**算：按下那一刻的高度记在 `startHeight`，不记这个的话一按就跳。
struct LowerPaneResizeHandle: View {
    /// 当前高度（来自 `AppState`，持久化）。
    let height: CGFloat
    /// 可用高度：拿窗口内容高度当代理（`nil` ⇒ 由 Core 走兜底上限）。
    let available: CGFloat?
    /// 写回（已由 Core 夹过范围）。
    let commit: (CGFloat) -> Void

    @State private var startHeight: CGFloat?

    var body: some View {
        ZStack {
            Divider()
            Color.clear
                .frame(height: 8)
                .contentShape(Rectangle())
                .onHover { inside in
                    // 指针形状要跟着变，否则「这里能拖」用户看不出来。
                    if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
                }
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            let base = startHeight ?? height
                            if startHeight == nil { startHeight = base }
                            // 往上拖（translation.height < 0）＝ 面板更高。
                            commit(base - value.translation.height)
                        }
                        .onEnded { _ in startHeight = nil }
                )
        }
        .frame(height: 8)
    }
}

private extension MainWindow {
    /// 展开态的理想高度：**拖过就用拖出来的**（`AppState` 持久化），没拖过用默认口径（`L-181`）。
    func lowerPaneIdealHeight(collapsed: Bool) -> CGFloat? {
        guard !collapsed else { return LowerPaneSizing.idealHeight(collapsed: true) }
        return LowerPaneSizing.clamped(height: appState.lowerPaneHeight, available: lowerPaneAvailableHeight)
    }

    /// 可用高度：**窗口内容高度**当代理。
    /// 刻意不引 `GeometryReader` —— 那一层裹上去会动到编辑器所在子树的结构（见 `SQLEditorView.swift:58`）。
    var lowerPaneAvailableHeight: CGFloat? {
        (NSApp.keyWindow ?? NSApp.mainWindow)?.contentView?.frame.height
    }
}
