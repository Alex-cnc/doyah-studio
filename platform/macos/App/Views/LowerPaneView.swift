import SwiftUI
import DoyahCore

/// 查询窗口**下部**那一块 —— 与 VS Code 底部面板同构的多页签区域。
///
/// 它不是独立新增的区域：原来的 Result（结果表）区域就是这里，现在升成页签，
/// 与 问题 / 输出 / 终端 / 调试控制台 并列。终端页签用的 `TerminalModel` 挂在 App 层，
/// 所以切页签、最大化 / 恢复、乃至切换界面语言都不会把 shell 杀掉。
struct LowerPaneView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var terminal: TerminalModel

    /// **查询页签（可空）** —— 2026-09-30 需求提出者实测反馈：「带 terminal 的底部区域是在两个功能中共享的」
    /// ⇒ 这块面板从「只长在 SQL 查询界面里」搬到**段一级**（`MainWindow` 的 `sectionWithLowerPane`），
    /// 数据库段传当前查询页签，**工作区段没有查询上下文，传 nil**。
    ///
    /// 可空之后只有「问题 / 输出」两个页签会读到它（那两页本来就是 SQL 上下文的东西）：
    /// 没有页签时它们如实显示空态，而不是硬要造一个假页签出来。
    let tab: QueryTab?

    /// 折叠态：**只画标题栏**（页签条 + 向上的展开箭头），不画内容。
    ///
    /// 2026-09-24 需求提出者实测：「Terminal 所在那个区域，点击向下那个箭头竟然隐藏不见了，
    /// 所以也就没有办法让它恢复了，应该是折叠到底部，只保留它的标题栏，向上展开的箭头在」。
    /// 原来"收起"是把整块面板从视图树里拿掉 —— 于是连恢复的入口也一起没了（只剩 ⇧⌘J 菜单，
    /// 但那个入口不在这块区域里，看不见自然就想不起来）。现在折叠**只收起内容**，
    /// 标题栏留在底部，箭头翻成向上。
    var isCollapsed: Bool = false

    /// 实时语法诊断（Problem 页签一并展示）。
    ///
    /// 自己算而不是由编辑器传进来：最大化时编辑器整块被盖住，就没人为这里提供诊断了。
    private var diagnostics: [SQLDiagnostic] {
        guard let tab else { return [] }   // 工作区段没有查询上下文 ⇒ 没有诊断（空态如实显示）
        return QueryDiagnostics.analyze(tab: tab, in: appState)
    }

    var body: some View {
        VStack(spacing: 0) {
            // 工具条那一行是**独立视图**（`LowerPaneTabStrip`）：它要能被单独离屏渲染，
            // 而这一层（`LowerPaneView`）的内容半边挂着 `TerminalHostView`，一渲染就会真开 shell。
            LowerPaneTabStrip(tab: tab, diagnostics: diagnostics, isCollapsed: isCollapsed)
            if !isCollapsed {
                Divider()
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(minHeight: isCollapsed ? 0 : 90)
        // 折叠态按**内容自己的理想高度**（标题栏一行）显示：不要让它被拉伸，
        // 也不要写死一个高度 —— 字号 / 语言变了它会自己跟着变。
        .fixedSize(horizontal: false, vertical: isCollapsed)
        // **根底色走主题令牌 + 星云皮肤**（星空紫「星云皮肤」· 2026-10-01 需求提出者要的「皮肤」质感；派单 `T-20261001-031`／`T-20261001-037`；队列 `L-153`）：
        // 原先写的是系统 `.background` ⇒ 整个下方面板（含终端）的底与主题无关，切主题时它一个人不变。
        // 2026-10-01 需求提出者实测反馈：「我要的皮肤效果是整个界面，不是只有导航栏、工作编辑区，
        // **底部区域也要有**」⇒ 这里也铺星云（与侧栏 / 内容区同一套）。
        .background(
            ZStack {
                Theme.surface(.panel)
                NebulaBackground(layer: .panel)
            }
        )
        // 关页签前的**二次确认**（L-84 ㈡ 口径④）：前台还有别的程序在跑时先问一句。
        // 为什么挂在**这一层**而不是页签头上：折叠态 / 最大化时页签条可能不在视线里，
        // 而弹窗必须跟着命令走（判定在 Core 的 `closeDecision`，这里只负责问）。
        .alert(
            L(.terminalTabCloseConfirmTitle),
            isPresented: Binding(
                get: { terminal.pendingCloseTab != nil },
                set: { if !$0 { terminal.cancelClose() } }
            )
        ) {
            Button(L(.terminalTabCloseConfirmAction), role: .destructive) { terminal.confirmClose() }
            Button(L(.commonCancel), role: .cancel) { terminal.cancelClose() }
        } message: {
            Text(L(.terminalTabCloseConfirmMessage))
        }
        // 双击页签头 → 重命名（空着确定 = 清掉重命名，标题回落到前台进程名 —— 口径在 Core）。
        .alert(
            L(.terminalTabRename),
            isPresented: Binding(
                get: { terminal.renamingTab != nil },
                set: { if !$0 { terminal.renamingTab = nil } }
            )
        ) {
            TextField(L(.terminalTabRename), text: $terminal.renameDraft)
            Button(L(.commonOk)) {
                if let id = terminal.renamingTab { terminal.rename(id: id, to: terminal.renameDraft) }
            }
            Button(L(.commonCancel), role: .cancel) { terminal.renamingTab = nil }
        } message: {
            Text(L(.terminalTabRenameMessage))
        }
        // 终端**不在这里启动**：`onAppear` 时视图还没布局，只能拿模型默认的 80×24，
        // 于是全屏 TUI 的第一帧就按错的列数排（`dsh-tui` 的 13×40 欢迎鲸鱼会挤在一起）。
        // 启动挪到 `TerminalHostView.layout()`，那里拿得到真实几何。
    }

    // MARK: 内容

    @ViewBuilder
    private var content: some View {
        switch appState.lowerPaneTab {
        case .problem:
            problemsContent

        case .output:
            logList(
                tab?.outputLog ?? [],
                emptyText: L(.lowerPaneOutputEmpty)
            )

        case .terminal:
            VStack(spacing: 0) {
                // **每个页签一个自己的视图实例**（`.id` 挂在当前页签 id 上）：切页签 = 换一屏。
                // 换掉的那一屏并没有丢 —— 它的屏幕缓冲、回滚位置、选区都在自己的 `TerminalPane` 里，
                // 切回来原样还在。契约（L-84 ㈠）：折叠 / 最大化 / 隐藏 / 切语言 / 窗口重排
                // **不许重启会话** —— 会话活在这个 pane 上，不活在这个视图里。
                TerminalView(
                    model: terminal.activePane,
                    tabs: terminal,
                    appearance: appState.terminalAppearance,
                    fontSize: appState.terminalFontSize,
                    cursor: appState.terminalCursorPreference.appearance
                )
                .id(terminal.tabs.activeID)
                Divider()
                terminalShortcutBar
            }

        case .debugConsole:
            placeholder(
                symbol: "ladybug",
                text: L(.lowerPaneDebugPlaceholder)
            )
        }
    }

    /// 终端页签底部的**快捷键提示条**。
    ///
    /// 为什么必须摆在台面上：终端里"只能用键盘"对不熟快捷键的人是个死结 —— 实测反馈就是
    /// 「能粘贴，但不知道复制按什么，也没有右键菜单」。菜单里虽然带了快捷键显示，
    /// 但得先知道"右键能弹菜单"才看得到；所以把三件事直接写在终端下面：
    /// 复制 / 粘贴 / 全选，以及 ⌥（在接管鼠标的 TUI 里选字）与右键（菜单）。
    private var terminalShortcutBar: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "keyboard")
            Text(L(.terminalShortcutHint))
                .lineLimit(1)
                .truncationMode(.tail)
            // 页签快捷键也写在这里：⌘T / ⌘W / ⌘⇧[ ⌘⇧] / ⌘1…9 只在终端有焦点时生效
            // （所以不进菜单栏 —— 进了就会把系统的 ⌘W「关闭窗口」全局改掉），
            // 入口看不见就等于没有，于是把这一行摆在终端下面。
            Text("·").foregroundStyle(Theme.text(.tertiary))
            Text(L(.terminalTabShortcutHint))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .font(Theme.font(.caption))
        .foregroundStyle(Theme.text(.secondary))
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.xs)
        .help(L(.terminalShortcutHint))
    }

    private var problemsContent: some View {
        // 语法诊断（编辑器实时算出来的）+ 执行期错误，按时间先后合并展示。
        // **没有查询页签时（工作区段）**：这一页没有可诊断的对象 —— `diagnostics` 与 `problemLog` 都为空，
        // 于是走下面 `logList` 的空态文案，不硬造一个假页签。
        let problemLog = tab?.problemLog ?? []
        return VStack(alignment: .leading, spacing: 0) {
            // 超长跳过要显式说出来：否则空态读起来就是"检查过了，没问题"（欺骗性空态）。
            if QueryDiagnostics.isRealtimeAnalysisSkipped(sql: tab?.sql ?? "") {
                logRow(
                    severity: .warning,
                    timestamp: nil,
                    message: L(.lowerPaneProblemSkipped, "\(sqlRealtimeScanLimit)")
                )
                if !diagnostics.isEmpty || !problemLog.isEmpty { Divider() }
            }

            if !diagnostics.isEmpty {
                ForEach(diagnostics) { diagnostic in
                    logRow(
                        severity: diagnostic.severity == .error ? .error : .warning,
                        timestamp: nil,
                        message: "\(L(.lintLocation, diagnostic.line, diagnostic.column))：\(diagnostic.message)"
                    )
                }
                if !problemLog.isEmpty { Divider() }
            }

            logList(problemLog, emptyText: L(.lowerPaneProblemEmpty), showsEmpty: diagnostics.isEmpty)
        }
    }

    private func logList(
        _ entries: [TabLogEntry],
        emptyText: String,
        showsEmpty: Bool = true
    ) -> some View {
        Group {
            if entries.isEmpty, showsEmpty {
                placeholder(symbol: "checkmark.circle", text: emptyText)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(entries) { entry in
                            logRow(
                                severity: entry.severity,
                                timestamp: entry.timestamp,
                                message: entry.message
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func logRow(severity: TabLogEntry.Severity, timestamp: Date?, message: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            Image(systemName: symbol(for: severity))
                .font(Theme.font(.caption))
                .foregroundStyle(color(for: severity))
                .padding(.top, 1)

            if let timestamp {
                Text(Self.timeFormatter.string(from: timestamp))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.text(.tertiary))
            }

            Text(message)
                .font(Theme.font(.caption))
                .foregroundStyle(color(for: severity))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
    }

    private func symbol(for severity: TabLogEntry.Severity) -> String {
        switch severity {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    private func color(for severity: TabLogEntry.Severity) -> Color {
        switch severity {
        case .info: return .secondary
        case .warning: return .orange
        case .error: return .red
        }
    }

    private func placeholder(symbol: String, text: String) -> some View {
        VStack(spacing: Spacing.s) {
            Spacer(minLength: 12)
            Image(systemName: symbol)
                .font(Theme.font(.title))
                .foregroundStyle(Theme.text(.tertiary))
            Text(text)
                .font(Theme.font(.body))
                .foregroundStyle(Theme.text(.secondary))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 460)
            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
