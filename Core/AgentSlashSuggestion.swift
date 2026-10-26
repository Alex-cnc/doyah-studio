import Foundation

/// 斜杠命令的**候选提示**（`FR-AGT-UX-CONV-014` 的界面输入侧）。
///
/// 口径（跟解析器同一套，不另立规矩）：
/// ① 只在「敲命令名」这一段给候选 —— 一旦出现空格（进入参数区）就**不再猜参数**，返回空；
/// ② 匹配**大小写不敏感**（`/HE` 也能给出 `/help`），候选里的插入文本一律小写；
/// ③ **精确命中排第一**，其后按命令清单的固定顺序（不随字典序乱跳）；
/// ④ 别名 `/sessions` 与 `/search` 同指，候选里两个都出；
/// ⑤ 不是斜杠开头、或名前有空白 ⇒ 没候选（不猜）。
public struct AgentSlashSuggestion: Equatable, Sendable, Identifiable {

    /// 命令本体（`/sessions` 这种别名的 `kind` 仍是 `.search`，`name` 保留别名原文）。
    public let kind: AgentSlashCommandKind
    /// 写进输入框的名字（不带斜杠），如 `model` / `sessions`。
    public let name: String
    /// 一句话说明（界面副标题用）。
    public let detail: String
    /// 选中后填进输入框的文本：要参数的命令带一个尾随空格，省一次敲键。
    public let insertion: String

    public var id: String { insertion }

    public init(kind: AgentSlashCommandKind, name: String, detail: String, requiresArgument: Bool) {
        self.kind = kind
        self.name = name
        self.detail = detail
        self.insertion = "/" + name + (requiresArgument ? " " : "")
    }
}

public struct AgentSlashCompleter: Sendable {

    public init() {}

    /// 命令清单（顺序即候选顺序；别名紧跟在正主后面）。
    /// 命令清单（顺序即候选顺序；别名紧跟在正主后面）。
    ///
    /// 名字一律取自 `AgentSlashCommandKind.rawValue`，**不在这里写字面量** ——
    /// 工具名与命令名的字面量只许出现在注册表那一个文件里（`AgentToolRegistrySourceTests` 按源码扫）。
    static let catalogue: [(kind: AgentSlashCommandKind, name: String)] = {
        let order: [AgentSlashCommandKind] = [.help, .model, .clear, .compact, .search, .theme, .stop]
        var entries: [(kind: AgentSlashCommandKind, name: String)] = order.map { ($0, $0.rawValue) }
        // 别名 `/sessions`（与 search 同指），紧跟正主后面。
        entries.insert((kind: .search, name: "sessions"), at: 5)
        return entries
    }()

    /// 给一段输入，返回候选（可能是空数组 —— 空就是空，不拿"猜的"顶）。
    public func suggestions(for raw: String, limit: Int = 8) -> [AgentSlashSuggestion] {
        // **不 trim**：名前有空白（「 /help」）就不是命令；尾随空格（"/model "）表示已进入参数区。
        guard raw.hasPrefix("/") else { return [] }
        let body = raw.dropFirst()
        // 参数区：出现任何空白 ⇒ 不再给命令候选（参数不猜）。
        guard !body.contains(where: { $0.isWhitespace }) else { return [] }
        guard !body.isEmpty else {
            // 只敲了「/」⇒ 全清单，按固定顺序。
            return Self.catalogue.prefix(max(0, limit)).map(make)
        }
        let prefix = body.lowercased()
        let matches = Self.catalogue.filter { $0.name.hasPrefix(prefix) }
        guard !matches.isEmpty else { return [] }
        // 精确命中排第一（`/stop` 不该排在 `/sessions` 后面）。
        let ordered = matches.filter { $0.name == prefix } + matches.filter { $0.name != prefix }
        return ordered.prefix(max(0, limit)).map(make)
    }

    private func make(_ entry: (kind: AgentSlashCommandKind, name: String)) -> AgentSlashSuggestion {
        AgentSlashSuggestion(kind: entry.kind,
                             name: entry.name,
                             detail: Self.detail(for: entry.kind),
                             requiresArgument: entry.kind.requiresArgument)
    }

    static func detail(for kind: AgentSlashCommandKind, language: AppLanguage = .simplifiedChinese) -> String {
        switch (kind, language) {
        case (.help, .simplifiedChinese): return "列出可用命令"
        case (.help, .english): return "List available commands"
        case (.model, .simplifiedChinese): return "切换模型（改配置，走审批）"
        case (.model, .english): return "Switch model (config change, needs approval)"
        case (.clear, .simplifiedChinese): return "清空当前会话上下文"
        case (.clear, .english): return "Clear this session's context"
        case (.compact, .simplifiedChinese): return "压缩上下文，保留结论"
        case (.compact, .english): return "Compact context, keep conclusions"
        case (.search, .simplifiedChinese): return "搜索会话历史（要关键词）"
        case (.search, .english): return "Search session history (needs a keyword)"
        case (.theme, .simplifiedChinese): return "切换配色（改配置，走审批）"
        case (.theme, .english): return "Switch theme (config change, needs approval)"
        case (.stop, .simplifiedChinese): return "停止正在跑的一轮"
        case (.stop, .english): return "Stop the running turn"
        @unknown default: return kind.rawValue
        }
    }
}
