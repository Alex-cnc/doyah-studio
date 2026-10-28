import Foundation

/// 查询窗口下方面板的页签。
///
/// 这是「工作区下部那一块」的页签集合，与 VS Code 的底部面板同构：
/// 问题 / 输出 / 终端 / 调试控制台 / **历史**（`FR-EDIT-10` v3.326 扩写）。
///
/// **「历史」只在 Database 客户端段出现**（工作区段没有查询上下文）—— 段条件在
/// `AppState.availableLowerPaneTabs`，不在本枚举（见 `case history` 的注释）。
///
/// **刻意不含「结果」页签**：结果表是**数据**，属于查询自己的地盘（编辑器区 SQL 下方），
/// 而这个面板是**应用级**的通用面板。这样面板与产品未来无关 —— 不论以后只做数据库客户端、
/// 还是做成编程 IDE、或两者合集，这几个页签都成立。
public enum LowerPaneTab: String, CaseIterable, Identifiable, Sendable {
    /// 执行 SQL 的错误信息与语法诊断。
    case problem
    /// 执行 SQL 的任何输出（状态、影响行数、耗时、导出结果…）。
    case output
    /// 内嵌的本机 shell（FR-EDIT-29）。
    case terminal
    /// 占位：将来客户端具备编程 IDE 能力（断点 / 变量查看）时的调试控制台。
    case debugConsole
    /// **Git 变更**（`FR-STD-WS-VCS-001`）：当前工作区的分支 / 改动清单 / 逐行差异。
    ///
    /// **只读**：这一页不提交、不推送、不改暂存区 —— 它回答的是「我改了哪些、改成了什么」。
    /// 与「历史」不同，它**不按段隐藏**：仓库身份跟着工作区走，与用户在哪个活动栏项上无关；
    /// 没有工作区时这一页如实画空态（见 `App/Views/GitChangesPanel.swift`）。
    case changes
    /// **执行回执**（`FR-STD-DB-TASK-003`）：本查询页签上每一跑的四项读数 + 执行时刻，
    /// 可复制 / 导出，导出前已脱敏。
    ///
    /// 与「输出」的分工：输出是**过程流水**（每次执行清空重来），回执是**审计读数**
    /// （成功 / 失败 / 被拦下 / 取消各留一条，不随后一跑消失）。它**不按段隐藏** ——
    /// 与输出同一口径：工作区段没有查询页签时如实画空态。
    case receipts
    /// 本次会话执行过的 **SQL 与 DDL**（`FR-EDIT-10` v3.326 扩写 · `DR-02` · 队列 `HIST-2`）。
    ///
    /// **只在 Database 客户端段出现**（工作区段没有查询上下文）—— 序 = 问题 / 输出 / 终端 /
    /// 调试控制台 / **历史**。这条**段条件不写在这里**：`allCases` 就是全部页签，
    /// 「这一档可见哪几枚」的唯一出处是 `AppState.availableLowerPaneTabs`
    /// （页签条只画它给的那几枚）。视图里再写一遍 `if` 就是第二处口径。
    ///
    /// 记录的是**语句动作**（执行过的 SQL / DDL），不含导出 / 备份 / 连接管理这类非语句动作；
    /// 源与工具条时钟菜单**同一份**（`AppState.queryHistory` ← 门面 `QueryHistoryStore`）。
    case history

    public var id: String { rawValue }

    /// 页签标题的文案键。
    public var textKey: LKey {
        switch self {
        case .problem: return .lowerPaneProblem
        case .output: return .lowerPaneOutput
        case .terminal: return .lowerPaneTerminal
        case .debugConsole: return .lowerPaneDebugConsole
        case .changes: return .lowerPaneChanges
        case .receipts: return .lowerPaneReceipts
        case .history: return .lowerPaneHistory
        }
    }

    /// 页签图标。
    public var symbolName: String {
        switch self {
        case .problem: return "exclamationmark.triangle"
        case .output: return "text.alignleft"
        case .terminal: return "terminal"
        case .debugConsole: return "ladybug"
        case .changes: return "arrow.triangle.branch"
        case .receipts: return "doc.text.magnifyingglass"
        case .history: return "clock.arrow.circlepath"
        }
    }
}
