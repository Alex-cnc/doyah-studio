import SwiftUI
import DoyahCore

@main
struct DoyahStudioApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var localization = LocalizationManager.shared
    /// 终端会话放在 App 层而不是面板里：最大化 / 恢复、以及切换语言导致的整树重建
    /// 都不该把正在跑的 shell（比如一个 dsh 会话）杀掉。
    @StateObject private var terminal = TerminalModel()
    /// 强调色（FR-EDIT-33）：可配置，通过根视图 `.tint` 下发到所有系统控件。
    @StateObject private var accent = AccentManager.shared
    /// 主题（配色方案，FR-EDIT-33 扩写 / 队列 L-80）：一组令牌值 + 配套强调色；切主题要整树重建。
    @StateObject private var designTheme = DesignThemeManager.shared
    /// 工作区（FR-EDIT-32）：终端启动目录等既有占位都以它为准。
    @StateObject private var workspace = WorkspaceStore.shared
    /// 工作区页签（FR-EDIT-35 / 36）：与数据库页签**并列**的另一套页签。
    @StateObject private var workspaceTabs = WorkspaceTabsModel()

    init() {
        // **单实例保护**：同一个 bundle 通常只允许一个进程在跑。
        //
        // 但有一个例外必须放行：**重启时被旧实例主动拉起来的那一个**。
        // 否则就会变成"新实例把旧的激活、自己退出，旧的随后也退出" —— 用户点重启后
        // 什么都不会发生（这正是 R-36 第二版踩的坑）。
        // 接替启动优先判断：它会等旧实例真的退出，并把交接单消费掉。
        let isTakeover = AppRelauncher.claimHandoffIfPresent()
        if !isTakeover, let existing = Self.otherRunningInstance() {
            // **必须看 activate() 的返回值**：对方可能正在退出（我刚踩过 ——
            // "杀掉旧实例后立刻启动"会让新实例静默 exit(0)，表现就是"界面干脆不出来"：
            // 没有窗口、没有崩溃报告、进程也没了）。只有真的把它激活了，我才退出自己；
            // 激活失败就**继续运行**，宁可短暂多一个实例，也不能让用户看不到界面。
            if existing.activate() {
                StartupLog.write("检测到已在运行的实例 pid=\(existing.processIdentifier)，已激活它并退出自己")
                exit(0)
            }
            StartupLog.write(
                "检测到实例 pid=\(existing.processIdentifier) 但激活失败（可能正在退出）→ 继续启动自己"
            )
        }
        StartupLog.write("正常启动 pid=\(ProcessInfo.processInfo.processIdentifier)")
        // **图标按钮的"名字"必须即时出现**（2026-09-27 人工点验发现）。
        //
        // 工具条按口径只放图标、不写字（`FR-EXEC-13` / `FR-EDIT-08`），于是按钮叫什么**全靠 tooltip**。
        // 但 AppKit 的 tooltip 默认要等 **2 秒**（`NSInitialToolTipDelay` 的出厂值 2000，单位毫秒）——
        // 实测反馈原话：「工具栏上的按钮没有名称，鼠标放上去又没有tips，这太难用了」：
        // 等不到就等于没有，而图标不认识时用户只能猜。
        //
        // 所以在这里把它压到 150ms：**全 app 所有 `.help(...)` 一起变即时**，不必给每个按钮自绘提示。
        // 为什么用系统 tooltip 而不是自己画：它渲染在**独立窗口**里，不会像视图树内的 overlay 那样
        // 被后画的兄弟视图盖住（那正是 R-62）；自绘那条路只留给 tooltip 表达不了的东西（例如带条数的状态徽标）。
        UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 150])
        StartupLog.write(
            "tooltip 延迟 \(Int(UserDefaults.standard.double(forKey: "NSInitialToolTipDelay")))ms（出厂 2000ms）"
        )
        MainMenuLocalizer.start()
    }

    /// 找出**已经在本机运行的另一个自己**（不含当前进程）。
    ///
    /// 排除已终止的：`runningApplications` 里可能还留着**正在退出**的实例，
    /// 把它当"已有实例"会让新实例把自己退出掉 —— 用户看到的就是"界面不出来"。
    private static func otherRunningInstance() -> NSRunningApplication? {
        guard let bundleID = Bundle.main.bundleIdentifier else { return nil }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .first { $0.processIdentifier != currentPID && !$0.isTerminated }
    }



    var body: some Scene {
        WindowGroup {
            MainWindow()
                .environmentObject(appState)
                // 查询编辑器缓冲（队列 `L-148`）：**必须单独注入** —— 它刻意不是 `AppState`
                // 的 `@Published` 属性，就是为了让"每键写文本"只重算观测它的那一小块，
                // 而不是观测 `appState` 的整个窗口（5,000 行实测 31.74 ms/键）。
                .environmentObject(appState.editorBuffer)
                // 工作区浏览器页签（队列 `L-149` 剩余①）：与 `editorBuffer` 同一条口径 ——
                // **必须单独注入**。它刻意不是 `AppState` 的 `@Published` 属性，就是为了让
                // 引擎每回报一次标题 / 加载中只重算观测它自己的那一小块（工作区页签条 + 内容区），
                // 而不是观测 `appState` 的整个窗口。
                .environmentObject(appState.workspaceBrowser)
                .environmentObject(localization)
                .environmentObject(terminal)
                .environmentObject(accent)
                .environmentObject(designTheme)
                .environmentObject(workspace)
                .environmentObject(workspaceTabs)
                .task {
                    // 工作区 → 终端启动目录：把工作区路径交给终端（它只在启动那一刻读）。
                    workspace.onWorkspaceChanged = { [terminal, workspaceTabs] path in
                        terminal.workspacePath = path
                        // Home 的"最近工作区"跟着记一条（FR-EDIT-35）。
                        workspaceTabs.record(workspace: path)
                        // 归档目录跟随工作区（未单独指定时）—— 变了就重新判定一次状态
                        Task { await appState.refreshSQLArchiveStatus() }
                    }
                    appState.workspacePathProvider = { [workspace] in workspace.rootPath }
                    await workspace.load()
                }
                .tint(accent.accentColor)
                // 主题三态（FR-EDIT-26）：`nil` = 跟随系统；否则锁定浅 / 深。
                .preferredColorScheme(appState.appearanceMode.forcedDark.map { $0 ? .dark : .light })
                .frame(minWidth: 1_100, minHeight: 700)
                // 语言切换时整棵视图树重建，保证所有文案立即刷新。
                //
                // 2026-09-29（L-80 ㈠）：**主题也进这个 id** —— 令牌色是在各视图 body 里算出来的
                // （`Theme.surface(...)` 当场解析成 NSColor），只建一次的话切主题会出现
                // "一半新配色、一半旧配色"。重建的代价与切语言完全一样（终端会话在 App 层，不会被杀）。
                .id("\(localization.language.rawValue)-\(designTheme.theme.id)")
                // 许可证那一行是**装进 `licenseLoad` 的一句话**（在**装载那一刻**按当时的语言
                // 渲染的），所以切语言后要重新装载一次才整行一致 —— `.id` 只重建视图，不重读文件。
                // （队列 L-65：界面不再自己抄一份文案，代价是这句随装载体一起走。）
                .onChange(of: localization.language) { _, _ in appState.reloadLicense() }
        }
        .windowStyle(.titleBar)
        // 菜单栏命令放进 `DoyahStudioCommands`：`.commands {}` 闭包只在场景建立时求值一次，
        // 直接写在这里会让语言切换后**菜单栏不刷新**（见该文件注释与 NFR-I18N-03）。
        .commands {
            DoyahStudioCommands(appState: appState, workspaceBrowser: appState.workspaceBrowser)
        }
    }
}




/// 启动决策的留痕（写进应用数据目录的 `startup.log`，最多留最近 200 行）。
///
/// 为什么需要它：「启动后没有窗口」这类故障原本是**静默**的 —— 进程没了、没有崩溃报告，
/// 只能靠猜。留一行"为什么退出/为什么继续"，下次一看日志就知道。
enum StartupLog {
    private static let lock = NSLock()

    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base
            .appendingPathComponent(DoyahIdentity.applicationSupportDirectoryName, isDirectory: true)
            .appendingPathComponent("startup.log", isDirectory: false)
    }

    static func write(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        let formatter = ISO8601DateFormatter()
        let line = "\(formatter.string(from: Date())) \(message)\n"
        let url = fileURL
        var lines = (try? String(contentsOf: url, encoding: .utf8))?.split(separator: "\n").map(String.init) ?? []
        lines.append(line.trimmingCharacters(in: .newlines))
        if lines.count > 200 { lines.removeFirst(lines.count - 200) }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url, options: .atomic)
    }
}
