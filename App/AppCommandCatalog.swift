import SwiftUI
import DoyahCore

/// 命令面板的**命令清单**（FR-EDIT-25）。
///
/// 为什么清单在 App 侧而不是 Core：标题要本地化（`L(...)`），而 Core 不做本地化 ——
/// 与 `AppShortcut` / `MenuLocalization` 的处理方式一致。
///
/// 每条命令的 `id` 是**稳定标识**：`AppState.performPaletteCommand(_:)` 按它分派。
/// 不要用标题做标识 —— 改文案就会把动作改没（这条在别处踩过）。
enum AppCommandCatalog {

    /// 面板要列出的命令。顺序即"同分时的默认顺序"，因此把高频的放前面。
    static func all() -> [CommandPalette.Item] {
        [
            item("newQuery", .commandNewQuery, "new query nq 新建 查询", "new query nq", .paletteCategoryQuery),
            item("execute", .commandExecute, "execute run 执行 运行", "execute run", .paletteCategoryQuery),
            item("stop", .commandStop, "stop cancel 停止 取消", "stop cancel", .paletteCategoryQuery),
            item("check", .commandCheck, "check explain 语法 检查", "check explain", .paletteCategoryQuery),
            item("format", .commandFormat, "format fmt 格式化", "format fmt", .paletteCategoryQuery),
            item("executionPlan", .commandExecutionPlan, "explain plan 执行计划", "execution plan explain", .paletteCategoryQuery),
            item("find", .commandFind, "find 查找", "find", .paletteCategoryQuery),
            item("replace", .commandReplace, "replace 替换", "replace", .paletteCategoryQuery),
            item("goToLine", .commandGoToLine, "goto line 跳转 行", "go to line", .paletteCategoryQuery),
            item("exportCSV", .commandExportCSV, "export csv 导出", "export csv", .paletteCategoryResult),
            item("exportJSON", .commandExportJSON, "export json 导出", "export json", .paletteCategoryResult),
            item("browseRows", .commandBrowseRows, "browse rows 浏览 表", "browse rows", .paletteCategoryObject),
            // 导入数据（FR-IO-03）：目标表默认取对象树当前选中项，没有也能手输 ——
            // 所以这条命令**不需要对象上下文**，任何时候都能打开。
            item("importData", .importTitle, "import csv tsv json copy data file 导入 文件 批量 数据", "import data file", .paletteCategoryObject),
            item("tableDDL", .commandTableDDL, "ddl 查看 建表 结构", "view ddl", .paletteCategoryObject),
            // 全库对象搜索（FR-META-12）：与对象树工具条的放大镜打开同一个面板。
            item("backupRestore", .backupRestoreTitle, "backup restore dump 备份 恢复 导出", "backup restore", .paletteCategoryServer),
            item("connectionSettings", .connectionSettingsTitle, "keepalive heartbeat settings 保活 心跳 连接 设置 间隔", "keepalive connection settings", .paletteCategoryServer),
            item("databaseStats", .databaseStatsTitle, "stats statistics size index cache connections 统计 表大小 索引 缓存 连接数", "database stats size cache hit", .paletteCategoryServer),
            // 服务器级对象（FR-SESS-03）：与「显示」菜单里的同一项打开同一个面板。
            item("serverObjects", .serverObjectsTitle, "server objects roles tablespaces extensions 服务器级对象 角色 表空间 扩展 权限", "server objects roles tablespaces extensions", .paletteCategoryServer),
            item("schemaDiff", .schemaDiffTitle, "schema diff compare sync migration 对比 差异 同步 迁移 结构", "schema diff compare sync", .paletteCategoryObject),
            item("erDiagram", .menuERDiagram, "er diagram erd foreign key relationship 关系图 实体 外键 连线", "er diagram relationships", .paletteCategoryObject),
            item("routineCandidates", .routineCandidatesTitle, "routine 例行 候选 记忆 重复", "routine candidates", .paletteCategoryAgent),
            item("objectSearch", .objectSearchTitle, "search 搜索 找 对象 表 视图 列 函数", "search objects find", .paletteCategoryObject),
            item("sessions", .commandSessions, "sessions 会话", "server sessions", .paletteCategoryServer),
            item("locks", .commandLocks, "locks 锁 阻塞", "locks blocking", .paletteCategoryServer),
            item("switchConnection", .commandSwitchConnection, "connection conn 切换 连接", "switch connection", .paletteCategoryServer),
            item("agentSQL", .commandAgentSQL, "agent nl2sql 智能体 自然语言 生成 sql", "agent nl2sql", .paletteCategoryAgent),
            // 诊断这条查询（FR-AI-03）：取**当前页签**的 SQL，面板里先取证再看建议。
            item("diagnoseQuery", .diagnosisTitle, "diagnose explain plan slow lock 诊断 执行计划 慢查询 锁 阻塞", "diagnose explain plan lock", .paletteCategoryAgent),
            // 维护任务编排（FR-AI-04）：审阅 → 逐条批准 / 拒绝 → 执行已批准的。
            item("maintenanceTasks", .maintenanceTitle, "maintenance vacuum analyze reindex backup grant 维护 任务 编排 整理 索引 授权", "maintenance tasks vacuum analyze", .paletteCategoryAgent),
            // 外部调用审批（FR-AI-10 的界面那一半）：外部智能体的写调用在这里等人点。
            // 笔记（DOYAH-01/03）：与数据库、工作区并列的第三块。
            item("notes", .notesTitle, "notes note memo 笔记 记录 灵感", "notes memo", .paletteCategoryAgent),
            item("mcpApprovals", .mcpApprovalTitle, "mcp approval external agent 外部 调用 审批 允许 拒绝 智能体", "mcp approval external", .paletteCategoryAgent),
            item("syntheticData", .commandSyntheticData, "synthetic data 合成 测试数据", "synthetic data", .paletteCategoryAgent),
            item("egressLog", .commandEgressLog, "egress log 外发 日志", "egress log", .paletteCategoryAgent),
            item("help", .commandHelp, "help 帮助 快捷键", "help shortcuts", .paletteCategoryHelp),
        ]
    }

    /// 面板右侧显示的快捷键提示（有就用同一份事实来源 `AppShortcut`，没有就留空）。
    static func shortcutHint(for id: String) -> String? {
        switch id {
        case "execute": return shortcutText(.execute)
        case "stop": return shortcutText(.stop)
        case "check": return shortcutText(.check)
        case "format": return shortcutText(.format)
        case "executionPlan": return shortcutText(.executionPlan)
        case "find": return shortcutText(.find)
        case "replace": return shortcutText(.replace)
        case "goToLine": return shortcutText(.goToLine)
        case "help": return shortcutText(.help)
        case "egressLog": return shortcutText(.egressLog)
        default: return nil
        }
    }

    private static func shortcutText(_ shortcut: AppShortcut) -> String {
        // 与 tooltip / 帮助面板共用同一份事实来源（`AppShortcut`），避免"改了键、提示没改"。
        shortcut.display
    }

    // MARK: - 当前工作区的文件（队列 `L-170`）

    /// 面板里那条「当前工作区的文件」项。
    ///
    /// **刻意不走上面那个 `item(...)` 辅助**：那个形状只服务**静态命令清单** ——
    /// 门禁 `Scripts/check-palette-wiring.py` 正是按它数「清单里有几条命令」，并要求
    /// 每一条都在 `performPaletteCommand` 里有 case。文件项是**动态**的（取决于当时开着
    /// 哪个工作区），混进那条路径会让门禁把文件命中当成命令。
    static func workspaceFileItem(_ entry: WorkspaceEntry) -> CommandPalette.Item {
        CommandPalette.Item(
            id: CommandPalette.FileID.make(relativePath: entry.relativePath),
            title: entry.name,
            // 相对路径也进关键词：搜 `Views` 要能找到 `App/Views/…` 下的那一批
            // （命中标题之外的那半 —— 引擎按名字命中，面板按名字 + 路径排序）。
            keywords: [entry.relativePath],
            category: L(.paletteCategoryWorkspaceFile),
            scope: .workspaceFile
        )
    }

    /// 把工作区的**文件名命中**接成面板的一组（队列 `L-170`）。
    ///
    /// **成员与顺序的唯一出处 = `WorkspaceSearch`**（引擎的 `Result` 已经按相对路径排好），
    /// 这里**不重新过滤**：再滤一遍必然与引擎的谓词分叉 —— `findFileNames` 认
    /// 「大小写 + 变音符号不敏感」，而 `CommandPalette.match` 只做小写化 ⇒ 只在变音符号上
    /// 命中的文件会在面板里**静默消失**。所以 `match` 给不出分值时**照样保留这一条**，
    /// 只是拿最低分（组间比高下时才用到它）。
    static func workspaceFileMatches(query: String, result: WorkspaceSearch.Result) -> [CommandPalette.Match] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        return result.entries.map { entry in
            let item = workspaceFileItem(entry)
            return CommandPalette.match(needle, item: item)
                ?? CommandPalette.Match(item: item, score: 0, highlighted: [])
        }
    }

    private static func item(
        _ id: String,
        _ titleKey: LKey,
        _ keywordText: String,
        _ englishKeywords: String,
        _ categoryKey: LKey
    ) -> CommandPalette.Item {
        CommandPalette.Item(
            id: id,
            title: L(titleKey),
            // 关键词同时收中文与英文：输入 `fmt` 或 `格式` 都要能命中。
            keywords: keywordText.split(separator: " ").map(String.init) + [englishKeywords],
            category: L(categoryKey)
        )
    }
}
