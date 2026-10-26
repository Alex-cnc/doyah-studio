import Foundation

/// 斜杠命令的**落地形状**（`FR-AGT-UX-CONV-014` / `FR-AGT-UX-CONV-015`）。
///
/// 解析在 `AgentSlashCommandParser`（同一批需求的另一件，判据 `AgentSlashCommandTests`）；
/// 本件回答的问题是「解析出来之后**要做什么**」，且**只做决定、不做动作**：
///
/// ① **本地执行不进模型** —— 任何一种 effect 都不构造模型请求；
/// ② **改配置的命令只出单、不落地** —— `/model` `/theme` 走 `.configChange`，
///    调用方必须先拿到审批（`AgentApproval`，与本产品其余审批同一套状态机），
///    批准之后才允许碰持久配置；命令自己不许改配置（`CONV-015` 的「照走审批」在这里落成类型）；
/// ③ **不认识就说不知道** —— `.rejected` 带原始命令，审计行照旧单行，不猜、不静默丢弃；
/// ④ `nil` = 不是斜杠命令（普通对话），调用方照原路发模型。
public enum AgentSlashCommandEffect: Equatable, Sendable {
    /// 帮助清单（正文取解析器里的唯一真源，不在这里另抄一份）。
    case help(lines: [String])
    /// 清空**本会话的对话上下文**（盘上的会话文件不动 —— 那是留痕，不是上下文）。
    case clearContext
    /// 请求压缩上下文（压缩口径与判据在 `AgentContextCompression`）。
    case compactContext
    /// 检索历史会话（关键词由用户给，不替它猜）。
    case searchSessions(query: String)
    /// 中断当前这一跑（没有在跑也算数：如实说「没在跑」，不假装停过）。
    case stopRun
    /// 给**正在跑的这一轮**插话纠偏（落到 `AgentIntervention.redirect`，当前步做完生效）。
    case steerRun(instruction: String)
    /// 把这条内容排到**本轮结束之后**再发（入的是待发队列，不是立刻发）。
    case queuePrompt(text: String)
    /// 改持久配置：**只出单**，落地归审批通过之后的调用方。
    case configChange(kind: AgentSlashCommandKind, argument: String)
    /// 不认识 / 缺参数：如实拒收（带原命令，界面据此说清是哪一条）。
    case rejected(command: AgentSlashCommand)

    /// 这条 effect 对应的**那一行审计**（与 `AgentSlashCommand.auditLine` 同源，不另写一套）。
    public var auditLine: String {
        switch self {
        case .help: return AgentSlashCommand.parsed(kind: .help, argument: "").auditLine
        case .clearContext: return AgentSlashCommand.parsed(kind: .clear, argument: "").auditLine
        case .compactContext: return AgentSlashCommand.parsed(kind: .compact, argument: "").auditLine
        case let .searchSessions(query):
            return AgentSlashCommand.parsed(kind: .search, argument: query).auditLine
        case .stopRun: return AgentSlashCommand.parsed(kind: .stop, argument: "").auditLine
        case let .steerRun(instruction):
            return AgentSlashCommand.parsed(kind: .steer, argument: instruction).auditLine
        case let .queuePrompt(text):
            return AgentSlashCommand.parsed(kind: .queue, argument: text).auditLine
        case let .configChange(kind, argument):
            return AgentSlashCommand.parsed(kind: kind, argument: argument).auditLine
        case let .rejected(command): return command.auditLine
        }
    }

    /// 会不会改持久配置（= 必须过审批）。判据钉住：只有 `.configChange` 为真。
    public var mutatesConfiguration: Bool {
        if case .configChange = self { return true }
        return false
    }

    /// 有没有真的做成一件本地事（拒收与「等审批」都不算）。
    public var performedLocally: Bool {
        switch self {
        case .help, .clearContext, .compactContext, .searchSessions, .stopRun, .steerRun, .queuePrompt: return true
        case .configChange, .rejected: return false
        }
    }
}

/// 把「解析结果」翻成「要做什么」的纯函数集合。
///
/// 刻意做成 `struct` + 无状态：同一个输入永远给同一个输出，界面与判据读的是同一份决定，
/// 免得「界面按 A 执行、判据按 B 断言」。
public struct AgentSlashCommandRuntime: Sendable {
    private let parser: AgentSlashCommandParser

    public init(parser: AgentSlashCommandParser = AgentSlashCommandParser()) {
        self.parser = parser
    }

    /// 审计里这一类动作统一挂在同一个工具名下（统计时好用，不散成七个名字）。
    public static let auditToolName = "slash"

    /// 原文 → effect。`nil` = 不是斜杠命令。
    public func plan(_ raw: String) -> AgentSlashCommandEffect? {
        effect(for: parser.parse(raw))
    }

    /// 解析结果 → effect。`nil` = 不是斜杠命令（普通对话）。
    public func effect(for command: AgentSlashCommand) -> AgentSlashCommandEffect? {
        switch command {
        case .notACommand:
            return nil
        case .unknown, .missingArgument:
            // 拒收也带原命令：界面要能说清「哪一条不认 / 缺什么参数」。
            return .rejected(command: command)
        case let .parsed(kind, argument):
            if kind.mutatesConfiguration {
                return .configChange(kind: kind, argument: argument)
            }
            switch kind {
            case .help: return .help(lines: parser.helpText)
            case .clear: return .clearContext
            case .compact: return .compactContext
            case .search: return .searchSessions(query: argument)
            case .stop: return .stopRun
            case .steer: return .steerRun(instruction: argument)
            case .queue: return .queuePrompt(text: argument)
            // 兜底：`mutatesConfiguration` 与这里必须覆盖同一组命令。
            // 走到这里说明登记表被改了 —— 按「改配置」处理（宁可多问一句，不可静默落地）。
            case .model, .theme: return .configChange(kind: kind, argument: argument)
            }
        }
    }

    /// 一条命令 = **一条**审计记录（走既有的 `makeToolCall` 通道，不另造日志面）。
    ///
    /// - Parameter outcome: 本地做成 ⇒ `.executed`；等审批 ⇒ `.pendingApproval`；拒收 ⇒ `.denied`。
    ///   调用方不许传一个「比事实好听」的值：没做成就别写 `.executed`。
    public func auditRecord(for effect: AgentSlashCommandEffect,
                            outcome: AgentActionRecord.Outcome,
                            sessionID: String? = nil,
                            at date: Date = Date()) -> AgentActionRecord {
        AgentActionRecord.makeToolCall(
            toolName: Self.auditToolName,
            argumentsSummary: effect.auditLine,
            outcome: outcome,
            sessionID: sessionID,
            at: date
        )
    }
}
