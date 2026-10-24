import Foundation

/// 上下文的**六类引用**（`FR-AI-22`）。
///
/// **结构上没有任何承载结果集行数据的形态** —— 不是靠调用方自觉，而是这里根本没有那种 case
/// （同 `LLMRequest` / `NFR-AI-01` 的做法：先让类型层面没有入口，再谈过滤）。
public enum AgentContextReference: Equatable, Sendable {

    public struct Table: Equatable, Sendable {
        public var schema: String
        public var name: String
        public var columns: [String]

        public init(schema: String = "", name: String, columns: [String] = []) {
            self.schema = schema
            self.name = name
            self.columns = columns
        }
    }

    /// `@文件`。
    case file(path: String, text: String)
    /// `@目录`。
    case directory(path: String, entries: [String])
    /// 选中代码（带起始行号，便于对回原文）。
    case selection(path: String, text: String, firstLine: Int?)
    /// 当前页签（只带标题与类型 —— 不带内容）。
    case activeTab(title: String, kind: String)
    /// 终端尾部。
    case terminalTail(text: String)
    /// DB schema 摘要（**只带表名与列名**，不带任何行数据）。
    case schemaSummary(database: String, tables: [Table])
    /// **项目上下文三样之二**（`FR-AGT-KNOW-CTX-001`）：当前分支 + 未提交改动 + 与上游的差距。
    ///
    /// 只带**摘要**（分支名、改了几个文件、ahead/behind），不带 diff 正文 —— diff 会让上下文
    /// 在开会话的第一秒就爆掉，而模型真正需要的是「我现在站在哪儿、有没有脏东西」。
    case gitState(branch: String, changed: [String], ahead: Int, behind: Int)
}

/// 上限（`FR-AI-22` ③④；沿用既有纪律：schema 摘要 ≤ 60 表 / ≤ 400 列）。
public struct AgentContextLimits: Equatable, Sendable {
    public var maxTables: Int
    public var maxColumns: Int
    public var maxTerminalCharacters: Int
    public var maxSelectionCharacters: Int
    public var maxFileCharacters: Int

    public init(maxTables: Int = 60, maxColumns: Int = 400,
                maxTerminalCharacters: Int = 4_000,
                maxSelectionCharacters: Int = 4_000,
                maxFileCharacters: Int = 20_000) {
        self.maxTables = maxTables
        self.maxColumns = maxColumns
        self.maxTerminalCharacters = maxTerminalCharacters
        self.maxSelectionCharacters = maxSelectionCharacters
        self.maxFileCharacters = maxFileCharacters
    }
}

/// 一段组装好的上下文。
public struct AgentContextSection: Equatable, Sendable {
    public var title: String
    public var body: String
    /// 这一段被截断了（**如实标注**，不静默）。
    public var truncated: Bool
    /// 这一段里被挡掉的行数 / 密钥片段数（**计数可断言**）。
    public var redactedRows: Int
    public var redactedSecrets: Int

    /// 发给模型的正文形态（截断标记就在这里）。
    public var outgoing: String {
        truncated ? body + "\n[truncated]\n" : body
    }
}

/// 组装结果：**外发正文与预览是同一份**（`text` 是唯一来源，`preview` 只是它的别名）。
public struct AgentContextPayload: Equatable, Sendable {
    public var sections: [AgentContextSection]

    /// 唯一来源：模型看到的、以及预览里显示的，都是这一份。
    public var text: String {
        sections.map { "### \($0.title)\n\($0.outgoing)" }.joined(separator: "\n\n")
    }

    /// 发送前的**外发预览** —— 刻意就是 `text` 本身（判据要的就是「改一处两处都变」）。
    public var preview: String { text }

    public var truncatedSections: [String] { sections.filter(\.truncated).map(\.title) }
    public var totalRedactedRows: Int { sections.reduce(0) { $0 + $1.redactedRows } }
    public var totalRedactedSecrets: Int { sections.reduce(0) { $0 + $1.redactedSecrets } }

    /// `AgentLoop` 的回灌段/用户提示就是吃这个（循环那条通道不必自己拼上下文）。
    public var promptFragment: String { text }
}

/// 边界过滤（`FR-AI-22` ②）—— **纯函数**，可单测。
///
/// 挡两类：
/// 1. **结果集行数据**（判据点名）：管道表行 · 制表符分隔 ≥3 字段的行 · ≥3 字段且带数字的逗号分隔行；
/// 2. **密钥 / 令牌片段**：`sk-…` · `Bearer …` · `AKIA…` · `password=…` · 长的十六进制 / base64 串。
///
/// 被挡掉的内容**计数报出**（不静默），占位符是机器形态（`[row]` / `[secret]`）。
public enum AgentContextBoundary {

    public struct Result: Equatable, Sendable {
        public var text: String
        public var redactedRows: Int
        public var redactedSecrets: Int
    }

    static let secretPatterns: [String] = [
        #"sk-[A-Za-z0-9_\-]{16,}"#,
        #"(?i)bearer\s+[A-Za-z0-9._\-]{16,}"#,
        #"AKIA[0-9A-Z]{12,}"#,
        #"(?i)(password|passwd|pwd|token|apikey|api_key)\s*[=:]\s*\S+"#,
        #"\b[0-9a-fA-F]{32,}\b"#,
    ]

    /// 只挡密钥（**不跑行数据启发式**）。
    ///
    /// 用在**由声明拼出来**的段（schema 摘要）上：那里的每一行都来自表名 / 列名，结构上不可能有结果集行数据，
    /// 而行数据启发式会把「列很多的表」那种合法行误判成数据行（判据当场抓过：`wide (c0, c1, …, c9)` 被吃掉）。
    public static func filterSecretsOnly(_ text: String) -> Result {
        var redactedSecrets = 0
        var output: [String] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            var working = line
            for pattern in secretPatterns {
                guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
                let range = NSRange(working.startIndex..<working.endIndex, in: working)
                let matches = regex.numberOfMatches(in: working, range: range)
                if matches > 0 {
                    redactedSecrets += matches
                    working = regex.stringByReplacingMatches(in: working, range: range, withTemplate: "[secret]")
                }
            }
            output.append(working)
        }
        return Result(text: output.joined(separator: "\n"), redactedRows: 0, redactedSecrets: redactedSecrets)
    }

    public static func filter(_ text: String) -> Result {
        var redactedRows = 0
        var redactedSecrets = 0
        var output: [String] = []

        for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if looksLikeDataRow(line) {
                redactedRows += 1
                output.append("[row]")
                continue
            }
            var working = line
            for pattern in secretPatterns {
                guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
                let range = NSRange(working.startIndex..<working.endIndex, in: working)
                let matches = regex.numberOfMatches(in: working, range: range)
                if matches > 0 {
                    redactedSecrets += matches
                    working = regex.stringByReplacingMatches(in: working, range: range, withTemplate: "[secret]")
                }
            }
            output.append(working)
        }
        return Result(text: output.joined(separator: "\n"),
                      redactedRows: redactedRows, redactedSecrets: redactedSecrets)
    }

    /// 行数据的形状判据（**保守**：宁可多挡一行，也不把结果集漏出去）。
    static func looksLikeDataRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }

        // 管道表行：`| 1 | alice |`（表头分隔行 `|---|---|` 也算）
        if trimmed.hasPrefix("|"), trimmed.filter({ $0 == "|" }).count >= 2 { return true }

        // 制表符分隔的 ≥3 字段
        let tabs = trimmed.split(separator: "\t", omittingEmptySubsequences: false)
        if tabs.count >= 3, tabs.filter({ !$0.isEmpty }).count >= 3 { return true }

        // 逗号分隔：≥3 字段且**带数字**（避免把一句带逗号的中文当行数据）
        let commas = trimmed.split(separator: ",", omittingEmptySubsequences: false)
        if commas.count >= 3, trimmed.rangeOfCharacter(from: .decimalDigits) != nil { return true }

        return false
    }
}

/// 上下文组装（`FR-AI-22` ①③④）：六类各产生一段，**上限与边界都在这一处**。
public enum AgentContextAssembler {

    public static func assemble(_ references: [AgentContextReference],
                               limits: AgentContextLimits = AgentContextLimits()) -> AgentContextPayload {
        AgentContextPayload(sections: references.map { section(for: $0, limits: limits) })
    }

    static func section(for reference: AgentContextReference, limits: AgentContextLimits) -> AgentContextSection {
        switch reference {
        case .file(let path, let text):
            return make(title: "file:\(path)", text: text, limit: limits.maxFileCharacters)

        case .directory(let path, let entries):
            return make(title: "dir:\(path)", text: entries.joined(separator: "\n"),
                        limit: limits.maxFileCharacters)

        case .selection(let path, let text, let firstLine):
            let head = firstLine.map { "\(path):\($0)" } ?? path
            return make(title: "selection:\(head)", text: text, limit: limits.maxSelectionCharacters)

        case .activeTab(let title, let kind):
            return make(title: "tab", text: "\(kind):\(title)", limit: limits.maxFileCharacters)

        case .terminalTail(let text):
            // 尾部：**留最后 N 个字符**（终端最有用的就是末尾），并如实标注截断
            return make(title: "terminal", text: text, limit: limits.maxTerminalCharacters, keepTail: true)

        case .gitState(let branch, let changed, let ahead, let behind):
            var lines = ["branch:\(branch)", "changed:\(changed.count)"]
            if !changed.isEmpty { lines.append(contentsOf: changed.map { "  " + $0 }) }
            if ahead > 0 || behind > 0 { lines.append("ahead:\(ahead) behind:\(behind)") }
            // 改动清单也要有上限，不然一个脏树能把这一段撑爆（如实标注截断）。
            return make(title: "git", text: lines.joined(separator: "\n"),
                        limit: limits.maxTerminalCharacters)        case .schemaSummary(let database, let tables):
            return schemaSection(database: database, tables: tables, limits: limits)
        }
    }

    /// ③ schema 摘要的上限：表数超限 ⇒ 后面的**只发表名**；列数超限 ⇒ 只列前 N 列。
    static func schemaSection(database: String, tables: [AgentContextReference.Table],
                              limits: AgentContextLimits) -> AgentContextSection {
        var lines: [String] = []
        var truncated = false
        var columnsUsed = 0

        for (index, table) in tables.enumerated() {
            let qualified = table.schema.isEmpty ? table.name : "\(table.schema).\(table.name)"
            if index >= limits.maxTables { truncated = true; continue }
            if table.columns.isEmpty {
                lines.append(qualified)
                continue
            }
            let remaining = max(0, limits.maxColumns - columnsUsed)
            if table.columns.count > remaining {
                truncated = true
                lines.append(qualified + " (" + table.columns.prefix(remaining).joined(separator: ", ") + ")")
                columnsUsed = limits.maxColumns
                continue
            }
            columnsUsed += table.columns.count
            lines.append(qualified + " (" + table.columns.joined(separator: ", ") + ")")
        }
        // 上限之外的表**只发表名**（③ 的口径），这里用一行汇总如实说明
        if tables.count > limits.maxTables {
            lines.append("more:" + String(tables.count - limits.maxTables))
        }

        // 这一段是由**声明名**拼出来的（结构上没有行数据）⇒ 只过密钥过滤，不跑行数据启发式。
        let boundary = AgentContextBoundary.filterSecretsOnly(lines.joined(separator: "\n"))
        return AgentContextSection(title: "schema:\(database)", body: boundary.text,
                                   truncated: truncated,
                                   redactedRows: boundary.redactedRows, redactedSecrets: boundary.redactedSecrets)
    }

    static func make(title: String, text: String, limit: Int, keepTail: Bool = false) -> AgentContextSection {
        let boundary = AgentContextBoundary.filter(text)
        let filtered = boundary.text
        var body = filtered
        var truncated = false

        if filtered.count > limit {
            truncated = true
            body = keepTail ? String(filtered.suffix(limit)) : String(filtered.prefix(limit))
        }
        return AgentContextSection(title: title, body: body, truncated: truncated,
                                   redactedRows: boundary.redactedRows, redactedSecrets: boundary.redactedSecrets)
    }
}
