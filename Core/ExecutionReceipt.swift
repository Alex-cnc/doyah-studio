import Foundation

// MARK: - 结局

/// 一次执行的**结局**（`FR-STD-DB-TASK-003`）。
///
/// **四档不是一个布尔**：
/// · `succeeded` / `failed` —— 真发出去了，成与不成；
/// · `cancelled` —— 用户按了停止。取消**不许**记成成功（R-31 的老账：取消落在「流正常结束」那一瞬时，
///   归档里留下一条假成功，而归档是审计依据 —— 假成功比失败更糟）；
/// · `refused` —— **一条语句都没发出去**（安全判定 / 任务定义 / 事务态拦下）。它与 `failed` 是两回事：
///   一个是「发了但错了」，一个是「根本没发」。压成一个布尔之后，审计里读不出
///   「有人试过一条 DELETE，被只读标记挡了」。
public enum ExecutionOutcome: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case succeeded
    case failed
    case cancelled
    case refused
}

// MARK: - 脱敏账

/// 一次脱敏的**账**（几处、哪一类）。回执上照实写：用户把回执贴给别人之前，
/// 得知道「里面那句 SQL 被抹过两个值」。
public struct RedactionReport: Equatable, Codable, Sendable {
    /// 口令子句（`PASSWORD '…'` / `IDENTIFIED BY '…'` / `TOKEN = '…'` …）被抹的处数。
    public var passwordLiterals: Int
    /// 连接串 `scheme://user:口令@host` 里被抹的口令处数。
    public var urlCredentials: Int

    public init(passwordLiterals: Int = 0, urlCredentials: Int = 0) {
        self.passwordLiterals = passwordLiterals
        self.urlCredentials = urlCredentials
    }

    public var total: Int { passwordLiterals + urlCredentials }
    public var isClean: Bool { total == 0 }
}

// MARK: - 脱敏

/// 把「不能进回执的字面量」换掉（`FR-STD-DB-TASK-003` ②：回执不含口令与敏感字面量）。
///
/// ## 口径
///
/// 抹的是**形状上就是凭据**的那几种，不是「所有字面量」：
/// ① 口令子句 —— `PASSWORD` / `PASSWD` / `PWD` / `SECRET` / `TOKEN` / `API_KEY` / `IDENTIFIED BY`
///    后面**引号里的那一段**（`ALTER USER bob PASSWORD 'hunter2'`）；
/// ② 等号 / 冒号式（不加引号那一档）—— `password=hunter2`、`token: abc`（DSN、URL 查询串、
///    `key=value` 配置文件行都是这个形状）；
/// ③ 命令行开关 —— `--password hunter2` / `--password=hunter2`（`--passwd` / `--pwd` 同形）；
/// ④ 连接串 userinfo —— `postgres://user:hunter2@host/db`。
///
/// **宁可多抹一处分不清的**：`insert into t(token) values ('…')` 里那个值也会被抹 ——
/// 少抹一次的代价（口令进了导出文件、被转发出去）远大于多抹一次的代价（回执里一个值成了 `***`）。
/// 反过来**不做**的事：不按「所有字符串字面量」一刀切 —— 那样回执就失去审计价值
/// （看不出这条语句到底改了什么）。这个取舍是**写死**的，改它要先改这条注释。
///
/// 纯函数、无状态、确定性：文本层面幂等（抹完再抹一遍逐字节相同 —— 已抹的 `***` 不会被二次匹配，
/// 各条规则的值类都排除了 `*` 与引号）。
public enum SensitiveTextRedactor {

    /// 抹掉之后留下的记号。选 `***` 而不是空串：读者要看得出「这里原来有个值」。
    public static let mask = "***"

    /// 抹一遍。返回**抹之后**的文本与账。
    public static func redact(_ text: String) -> (text: String, report: RedactionReport) {
        guard !text.isEmpty else { return (text, RedactionReport()) }

        var working = text
        var report = RedactionReport()

        // ⓪ 连接串 userinfo 先跑：`scheme://user:口令@host` 的口令里可能含 `:` / `-`，
        //    先被别的规则切一刀会留下残片。
        working = replace(
            pattern: #"([A-Za-z][A-Za-z0-9+.\-]*://[^\s:/@]+):[^\s@/*]+@"#,
            in: working,
            template: "$1:" + mask + "@",
            count: &report.urlCredentials
        )

        // ① 口令子句：关键字（可带 `=` `:` `TO` `AS` `IS`）+ **引号里的那一段**。
        //    单双引号各一条；`(?!(?:\*\*\*)引号)` 让已抹过的值不二次计数。
        let clause = #"\b((?:password|passwd|pwd|secret|token|api[_-]?key|identified\s+by|identified\s+with)\b\s*(?:=|:|to|as|is)?\s*)"#
        working = replace(
            pattern: clause + #"(?!\*\*\*')'(?:[^']|'')*'"#,
            in: working,
            template: "$1'" + mask + "'",
            count: &report.passwordLiterals
        )
        working = replace(
            pattern: clause + #"(?!\*\*\*")"(?:[^"\\]|\\.)*""#,
            in: working,
            template: "$1\"" + mask + "\"",
            count: &report.passwordLiterals
        )

        // ③ 命令行开关先于 ②：否则 `--password=x` 会被 ② 先吃掉一半，两边各记一次。
        working = replace(
            pattern: #"(--?password|--?passwd|--?pwd)(\s+|=)(?!\*)[^\s'"]+"#,
            in: working,
            template: "$1$2" + mask,
            count: &report.passwordLiterals
        )

        // ② 等号 / 冒号式（不加引号的那一档）。
        working = replace(
            pattern: #"\b(password|passwd|pwd|secret|token|api[_-]?key)\s*[=:]\s*(?!\*)[^\s;&'"]+"#,
            in: working,
            template: "$1=" + mask,
            count: &report.passwordLiterals
        )

        return (working, report)
    }

    // MARK: 内部

    /// 跑一条正则，按 `template`（`$1` / `$2`）替换并数命中。逐条从后往前替换 ——
    /// 前面替换会移动后面命中的位置。
    private static func replace(
        pattern: String,
        in text: String,
        template: String,
        count: inout Int
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }
        let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
        guard !matches.isEmpty else { return text }

        var result = text
        for match in matches.reversed() {
            guard let full = Range(match.range, in: result) else { continue }
            var replacement = template
            let lastGroup = min(2, match.numberOfRanges - 1)
            if lastGroup >= 1 {
                for group in stride(from: lastGroup, through: 1, by: -1) {
                    guard match.range(at: group).location != NSNotFound,
                          let range = Range(match.range(at: group), in: result) else { continue }
                    replacement = replacement.replacingOccurrences(of: "$\(group)", with: String(result[range]))
                }
            }
            result.replaceSubrange(full, with: replacement)
            count += 1
        }
        return result
    }
}

// MARK: - 回执

/// 一次执行的**回执**（`FR-STD-DB-TASK-003`）。
///
/// 需求原文：「记录成功 / 失败、影响行数、耗时、错误原文与执行时刻，挂在会话上可作为审计依据；
/// 回执不含口令与敏感字面量」。验收三条：① 回执含四项读数与执行时刻；② 可复制 / 导出且已脱敏；
/// ③ 失败也有回执（不因报错丢失）。外加一句否定面：**不把「完成」当回执** ——
/// 「跑完了」不是一条回执，上面这些读数才是。
///
/// ## 为什么脱敏在 `init` 里做
///
/// 口令只要进过一次这个值，后面任何一次 `render()` / `exportData()` 都会把它带出去
/// （复制到剪贴板、写进给别人看的文件）。所以**原文根本不进这个结构**：入口只有这一个，
/// 先把 SQL 与错误原文过一遍 `SensitiveTextRedactor`，抹完才落字段。`init(from:)` 也走同一个入口
/// —— 一条回执文件被别的工具造出来（或被人手工改过）后再读回来，仍然只有抹过的形态。
public struct ExecutionReceipt: Identifiable, Equatable, Codable, Sendable {

    /// 结果集读数（验收 ① 的一半：这次到底返回了什么）。
    public struct ResultReading: Equatable, Codable, Sendable {
        public var resultSetCount: Int
        /// 各结果集行数之和。
        public var rowCount: Int
        /// 各结果集列数的最大值（列数逐语句不同时取最宽那一张 —— 报和没有意义）。
        public var columnCount: Int
        /// 其中被上限截断的结果集个数（「看到的不完整」必须是一等事实，R-33）。
        public var truncatedCount: Int

        public init(resultSetCount: Int = 0, rowCount: Int = 0, columnCount: Int = 0, truncatedCount: Int = 0) {
            self.resultSetCount = resultSetCount
            self.rowCount = rowCount
            self.columnCount = columnCount
            self.truncatedCount = truncatedCount
        }
    }

    public let id: UUID
    /// 执行时刻（**开始**那一刻 —— 审计问的是「什么时候动的」，不是「什么时候结束的」）。
    public let executedAt: Date
    public let duration: TimeInterval
    public let connectionName: String
    public let database: String
    /// 这一跑跑的是哪一段（选中片段 / 整篇）。
    public let scopeTitle: String
    public let statementCount: Int
    public let outcome: ExecutionOutcome
    /// 影响行数。`nil` = 这一跑**没有报过行数**（不是 0 行 ——「没读数」与「动了 0 行」是两条结论）。
    public let affectedRows: Int?
    public let results: ResultReading
    /// 语句原文 —— **已脱敏**。
    public let sql: String
    /// 失败 / 被拒的原文 —— **已脱敏**。成功时为 `nil`。
    public let errorText: String?
    /// 脱敏账。
    public let redaction: RedactionReport

    public init(
        id: UUID = UUID(),
        executedAt: Date,
        duration: TimeInterval,
        connectionName: String,
        database: String,
        scopeTitle: String,
        statementCount: Int,
        outcome: ExecutionOutcome,
        affectedRows: Int? = nil,
        results: ResultReading = ResultReading(),
        sql: String,
        errorText: String? = nil
    ) {
        let cleanSQL = SensitiveTextRedactor.redact(sql)
        let cleanError = errorText.map { SensitiveTextRedactor.redact($0) }

        self.id = id
        self.executedAt = executedAt
        self.duration = duration
        self.connectionName = connectionName
        self.database = database
        self.scopeTitle = scopeTitle
        self.statementCount = statementCount
        self.outcome = outcome
        self.affectedRows = affectedRows
        self.results = results
        self.sql = cleanSQL.text
        self.errorText = cleanError?.text
        self.redaction = RedactionReport(
            passwordLiterals: cleanSQL.report.passwordLiterals + (cleanError?.report.passwordLiterals ?? 0),
            urlCredentials: cleanSQL.report.urlCredentials + (cleanError?.report.urlCredentials ?? 0)
        )
    }

    // MARK: 编解码

    private enum CodingKeys: String, CodingKey {
        case id, executedAt, duration, connectionName, database, scopeTitle, statementCount
        case outcome, affectedRows, results, sql, errorText, redaction
    }

    /// **解码也过脱敏**（见类型注释最后一段）。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            executedAt: try container.decode(Date.self, forKey: .executedAt),
            duration: try container.decode(TimeInterval.self, forKey: .duration),
            connectionName: try container.decode(String.self, forKey: .connectionName),
            database: try container.decode(String.self, forKey: .database),
            scopeTitle: try container.decode(String.self, forKey: .scopeTitle),
            statementCount: try container.decode(Int.self, forKey: .statementCount),
            outcome: try container.decode(ExecutionOutcome.self, forKey: .outcome),
            affectedRows: try container.decodeIfPresent(Int.self, forKey: .affectedRows),
            results: try container.decodeIfPresent(ResultReading.self, forKey: .results) ?? ResultReading(),
            sql: try container.decode(String.self, forKey: .sql),
            errorText: try container.decodeIfPresent(String.self, forKey: .errorText)
        )
    }

    // MARK: 渲染（可复制的文本）

    /// 渲染要用的**文案**。由界面从语言表取好再传进来 —— Core 不留任何面向用户的字面量
    /// （`Scripts/check-core-localization.py` 的两条棘轮都扫这里）。
    public struct ReceiptLabels: Equatable, Sendable {
        public var title: String
        public var executedAt: String
        public var outcome: String
        public var duration: String
        /// 含 `%.3f` 的格式串。
        public var durationFormat: String
        public var affectedRows: String
        public var affectedRowsUnmeasured: String
        public var statements: String
        public var connection: String
        public var database: String
        public var scope: String
        public var results: String
        /// 含三个 `%d`（结果集数 · 行 · 列）。
        public var resultsFormat: String
        /// 含一个 `%d`（被截断的结果集个数）。
        public var resultsTruncated: String
        public var error: String
        public var sql: String
        /// 脱敏那一行的**标签**（"脱敏" / "Redacted"）。
        public var redaction: String
        /// 含三个 `%d`（总 · 口令 · 连接串）。
        public var redactionFormat: String
        /// 四档结局各自的说法。
        public var outcomes: [ExecutionOutcome: String]

        public init(
            title: String,
            executedAt: String,
            outcome: String,
            duration: String,
            durationFormat: String,
            affectedRows: String,
            affectedRowsUnmeasured: String,
            statements: String,
            connection: String,
            database: String,
            scope: String,
            results: String,
            resultsFormat: String,
            resultsTruncated: String,
            error: String,
            sql: String,
            redaction: String,
            redactionFormat: String,
            outcomes: [ExecutionOutcome: String]
        ) {
            self.title = title
            self.executedAt = executedAt
            self.outcome = outcome
            self.duration = duration
            self.durationFormat = durationFormat
            self.affectedRows = affectedRows
            self.affectedRowsUnmeasured = affectedRowsUnmeasured
            self.statements = statements
            self.connection = connection
            self.database = database
            self.scope = scope
            self.results = results
            self.resultsFormat = resultsFormat
            self.resultsTruncated = resultsTruncated
            self.error = error
            self.sql = sql
            self.redaction = redaction
            self.redactionFormat = redactionFormat
            self.outcomes = outcomes
        }
    }

    /// 时间戳（**确定性**：给定时区就逐字节相同）。
    public static func timestamp(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    /// 渲染成**可复制的一段文本**（验收 ②）。字段次序写死，便于人读与比对。
    public func render(labels: ReceiptLabels, timeZone: TimeZone = .current) -> String {
        var lines: [String] = []
        let stamp = Self.timestamp(executedAt, timeZone: timeZone)
        lines.append("\(labels.title) · \(stamp)")
        lines.append("\(labels.executedAt)：\(stamp)")
        lines.append("\(labels.outcome)：\(labels.outcomes[outcome] ?? outcome.rawValue)")
        lines.append("\(labels.duration)：\(String(format: labels.durationFormat, duration))")
        if let affectedRows {
            lines.append("\(labels.affectedRows)：\(affectedRows)")
        } else {
            lines.append("\(labels.affectedRows)：\(labels.affectedRowsUnmeasured)")
        }
        lines.append("\(labels.statements)：\(statementCount)")
        lines.append("\(labels.connection)：\(connectionName)")
        lines.append("\(labels.database)：\(database)")
        lines.append("\(labels.scope)：\(scopeTitle)")

        var resultLine = String(
            format: labels.resultsFormat,
            results.resultSetCount,
            results.rowCount,
            results.columnCount
        )
        if results.truncatedCount > 0 {
            resultLine += " · " + String(format: labels.resultsTruncated, results.truncatedCount)
        }
        lines.append("\(labels.results)：\(resultLine)")

        if let errorText, !errorText.isEmpty {
            lines.append("\(labels.error)：\(errorText)")
        }
        if !redaction.isClean {
            lines.append(
                "\(labels.redaction)："
                    + String(
                        format: labels.redactionFormat,
                        redaction.total,
                        redaction.passwordLiterals,
                        redaction.urlCredentials
                    )
            )
        }

        lines.append("\(labels.sql)：")
        for line in sql.split(separator: "\n", omittingEmptySubsequences: false) {
            lines.append("  " + line)
        }
        return lines.joined(separator: "\n")
    }

    /// 导出成 JSON（验收 ② 的另一半：可带走）。**已经脱敏** —— 编码的就是结构里那些字段。
    public func exportData() throws -> Data {
        let encoder = JSONEncoder()
        // 键序固定 + 时间用 ISO8601：同一份回执跑两遍逐字节相同（导出文件可以进版本库 / 比对）。
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}

// MARK: - 会话上的回执册

/// 挂在**会话（查询页签）**上的回执册（`FR-STD-DB-TASK-003` ①）。
///
/// 为什么是「页签上的一本册子」而不是一个全局数组：回执回答的是「我刚才那一跑发生了什么」，
/// 跨页签混在一起就答不出「哪一跑」；关掉页签它就该跟着走。
///
/// 容量只留最近 `capacity` 条（最旧先丢）：回执是**审计线索**而不是永久日志 ——
/// 长期留档那条路是查询归档（`Core/SQLArchive`，按天一个 `.sql`，已经在跑）；把无限增长的东西
/// 塞进内存，最后只会变成一次卡顿。
public struct ExecutionReceiptLog: Equatable, Sendable {
    public static let capacity = 200

    public private(set) var receipts: [ExecutionReceipt]

    public init(receipts: [ExecutionReceipt] = []) {
        self.receipts = Array(receipts.suffix(Self.capacity))
    }

    /// 追加一条。超容量时丢**最旧**的（数组按时间先后排）。
    public mutating func append(_ receipt: ExecutionReceipt) {
        receipts.append(receipt)
        if receipts.count > Self.capacity {
            receipts.removeFirst(receipts.count - Self.capacity)
        }
    }

    public var count: Int { receipts.count }
    public var isEmpty: Bool { receipts.isEmpty }

    /// 新的在前（界面上先看最近一跑）。
    public var newestFirst: [ExecutionReceipt] { receipts.reversed() }

    public mutating func removeAll() { receipts.removeAll() }

    /// 整本导出成文本（旧 → 新，`---` 分隔）—— 审计按时间读。
    public func exportText(labels: ExecutionReceipt.ReceiptLabels, timeZone: TimeZone = .current) -> String {
        receipts
            .map { $0.render(labels: labels, timeZone: timeZone) }
            .joined(separator: "\n\n---\n\n")
    }

    /// 整本导出成 JSON 数组。
    public func exportData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(receipts)
    }
}
