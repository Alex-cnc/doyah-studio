import Foundation

/// 斜杠命令（`FR-AGT-UX-CONV-014` / `FR-AGT-UX-CONV-015`）。
///
/// 口径：
/// ① **本地执行不进模型** —— 解析在 Core 完成，命中即返回命令，不构造模型请求；
/// ② **大小写不敏感**（`/Help` = `/help`），**可带参数**（`/model gpt-4o`、`/theme dark`）；
/// ③ **只留一行审计** —— `auditLine` 必定单行（参数里的换行折成空格），且不带正文内容；
/// ④ **改配置照走审批** —— `/model` `/theme` 这类会动持久配置的命令 `requiresApproval = true`，
///    由调用方送 `AgentApprovalGate`，不许命令自己落地；
/// ⑤ 未知命令**不猜**：返回 `.unknown`，附可用命令清单。
public enum AgentSlashCommandKind: String, Equatable, Sendable, CaseIterable {
    case help, model, clear, compact, search, theme, stop

    /// 会改持久配置、必须走审批的命令。
    public var mutatesConfiguration: Bool {
        switch self {
        case .model, .theme: return true
        case .help, .clear, .compact, .search, .stop: return false
        }
    }

    /// 是否需要参数（缺参数如实报，不拿默认值顶）。
    public var requiresArgument: Bool {
        switch self {
        case .model, .search, .theme: return true
        case .help, .clear, .compact, .stop: return false
        }
    }
}

public enum AgentSlashCommand: Equatable, Sendable {
    case parsed(kind: AgentSlashCommandKind, argument: String)
    case unknown(name: String)
    /// 命令需要参数但没给。
    case missingArgument(kind: AgentSlashCommandKind)
    /// 不是斜杠命令（普通对话）。
    case notACommand

    public var auditLine: String {
        switch self {
        case let .parsed(kind, argument):
            let args = argument.isEmpty ? "" : " arg=\(Self.singleLine(argument))"
            return "slash /\(kind.rawValue)\(args)"
        case let .unknown(name):
            return "slash /\(Self.singleLine(name)) unknown"
        case let .missingArgument(kind):
            return "slash /\(kind.rawValue) missing-argument"
        case .notACommand:
            return "slash none"
        }
    }

    /// 单行化：换行 / 制表折成空格，连续空白压成一个 —— 审计行永远一行。
    static func singleLine(_ text: String) -> String {
        text.split(whereSeparator: { $0.isNewline || $0 == "\t" || $0 == "\r" })
            .map(String.init)
            .joined(separator: " ")
            .split(separator: " ")
            .joined(separator: " ")
    }
}

public struct AgentSlashCommandParser: Sendable {
    public init() {}

    public func parse(_ raw: String) -> AgentSlashCommand {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return .notACommand }
        let body = trimmed.dropFirst()
        // `//` 或空白后的 `/` 不当命令
        guard let first = body.first, !first.isWhitespace else { return .notACommand }

        let name = String(body.prefix(while: { !$0.isWhitespace })).lowercased()
        let argument = AgentSlashCommand.singleLine(String(body.dropFirst(name.count)))

        if name == "sessions" {  // 别名：/sessions 与 /session 同指
            // 别名只换名字、**不换规矩**：`/sessions` 缺关键词与 `/search` 一样要拒收
            // （旧写法在别名处直接返回，绕过了下面的缺参判定 ⇒ `/sessions` 会去搜空串，
            //  那等于「匹配一切」，看着像有结果、其实什么也没问）。
            return argument.isEmpty ? .missingArgument(kind: .search) : .parsed(kind: .search, argument: argument)
        }
        guard let kind = AgentSlashCommandKind(rawValue: name) else {
            return .unknown(name: name)
        }
        if kind.requiresArgument, argument.isEmpty {
            return .missingArgument(kind: kind)
        }
        return .parsed(kind: kind, argument: argument)
    }

    /// 帮助文本（`/help` 的正文；也是命令面板的唯一真源）。
    public var helpText: [String] {
        [
            "/help —— 这份清单",
            "/model <名字> —— 切模型（改配置，走审批）",
            "/clear —— 清空本会话上下文（不动持久会话文件）",
            "/compact —— 请求压缩上下文（critical 段永不丢）",
            "/sessions <关键词> —— 检索历史会话",
            "/theme <浅色|深色|跟随系统> —— 切外观（改配置，走审批）",
            "/stop —— 中断当前这一跑",
        ]
    }
}
