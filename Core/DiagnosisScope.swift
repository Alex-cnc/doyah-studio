import Foundation

/// 连接上下文里的诊断作用域（`FR-STD-DB-DIAG-006`）。
///
/// 需求原文一句话定了这一层的形状：「可从当前连接 / 库 / 对象唤起诊断，把连接、库、对象与
/// **最近一次执行的读数**一并带进上下文；结论必须能点回具体对象与统计读数。」
///
/// 拆成三件事：
///   ① **作用域**（本文件）：从对象树某个节点唤起时，那四样东西是一个值 —— 连接（不含口令）、
///      库、对象（类型 / 名字 / schema）、最近一次执行的读数。它是**纯值**，不连库、不取数。
///   ② **取证计划**：按对象类型给「该跑哪条统计查询」；**没有统计视图的对象要如实说没取到**，
///      而不是给一张空表（空表会被读成「这张表从来没被扫过」—— 那是编出来的结论）。
///   ③ **结论里的对象名**（`DiagnosisObjectLinks.swift`）：纯函数切段 + 可点 URL。
///
/// 为什么「最近一次执行的读数」要在 Core 里成型而不是界面自己拼：它的**来源只有一处**
/// 是页签上的 `ExecutionReceiptLog`，而「哪几种结局算真的执行过」是判决 ——
/// 被拒（`refused`）与未发出的那几条**没有跑过语句**，把它们当读数写进上下文，
/// 等于告诉模型「刚才跑过」，而实际上一条都没发出去。
public struct DiagnosisScope: Equatable, Sendable {

    /// 最近一次**真的执行过**的那一跑的读数。
    ///
    /// 只有 `succeeded` / `failed` 两种结局会构造出来：另两种（`cancelled` / `refused`）没有
    /// 服务端读数（取消的那一跑可能一行都没返回，被拒的那一跑一条语句都没发）——
    /// 那种情况下 `DiagnosisScope.lastExecution` 是 `nil`，面板读「未取到」。
    public struct LastExecution: Equatable, Sendable {

        public enum Outcome: String, Equatable, Sendable {
            case succeeded
            case failed
        }

        /// 那一跑的语句原文（**已由回执脱敏**；这里再取首行并夹到 140 字）。
        public var statement: String
        public var durationMilliseconds: Int
        public var rowCount: Int
        /// `nil` = 那一跑没报影响行数（不是 0 行）。
        public var affectedRows: Int?
        public var outcome: Outcome
        public var executedAt: Date

        public init(
            statement: String,
            durationMilliseconds: Int,
            rowCount: Int,
            affectedRows: Int? = nil,
            outcome: Outcome,
            executedAt: Date
        ) {
            self.statement = statement
            self.durationMilliseconds = max(0, durationMilliseconds)
            self.rowCount = max(0, rowCount)
            self.affectedRows = affectedRows
            self.outcome = outcome
            self.executedAt = executedAt
        }

        /// 从回执取读数；**没有真的执行过就返回 `nil`**（那一跑不许冒充读数）。
        public init?(receipt: ExecutionReceipt) {
            let outcome: Outcome
            switch receipt.outcome {
            case .succeeded: outcome = .succeeded
            case .failed: outcome = .failed
            case .cancelled, .refused: return nil
            }
            self.init(
                statement: LastExecution.firstLine(receipt.sql),
                durationMilliseconds: Int((receipt.duration * 1000).rounded()),
                rowCount: receipt.results.rowCount,
                affectedRows: receipt.affectedRows,
                outcome: outcome,
                executedAt: receipt.executedAt
            )
        }

        /// 首行 + 140 字上限：上下文里不需要一整篇脚本，但也不能只剩一个「…」。
        static func firstLine(_ sql: String) -> String {
            let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
            let first = trimmed.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
            let line = first.trimmingCharacters(in: .whitespaces)
            guard line.count > 140 else { return line }
            return String(line.prefix(140)) + "…"
        }

        /// 一行读数（面板与提示词同一份）。
        public func readingLine(language: AppLanguage) -> String {
            let base = LocalizedStrings.format(
                .diagnosisLastExecutionLine,
                language: language,
                String(durationMilliseconds),
                String(rowCount)
            )
            switch outcome {
            case .succeeded:
                guard let affectedRows else { return base }
                return base + LocalizedStrings.format(
                    .diagnosisLastExecutionAffected,
                    language: language,
                    String(affectedRows)
                )
            case .failed:
                return LocalizedStrings.text(.diagnosisLastExecutionFailed, language: language)
            }
        }

        /// 证据行：语句 / 耗时 / 行数 / 影响行数 / 结局各一格 —— 模型看到的与面板看到的是同一份。
        public func evidenceRow(language: AppLanguage) -> [String] {
            [
                statement,
                "\(durationMilliseconds) ms",
                "\(rowCount)",
                affectedRows.map(String.init) ?? LocalizedStrings.text(.diagnosisReadingUnmeasured, language: language),
                LocalizedStrings.text(outcome == .succeeded ? .diagnosisOutcomeSucceeded : .diagnosisOutcomeFailed, language: language)
            ]
        }
    }

    /// 连接（`用户名@地址:端口`，**不含口令**）。
    public var connectionLabel: String
    public var database: String?
    public var objectKind: DatabaseObject.Kind
    public var objectName: String
    public var schema: String?
    public var lastExecution: LastExecution?

    public init(
        connectionLabel: String,
        database: String? = nil,
        objectKind: DatabaseObject.Kind,
        objectName: String,
        schema: String? = nil,
        lastExecution: LastExecution? = nil
    ) {
        self.connectionLabel = connectionLabel
        self.database = database
        self.objectKind = objectKind
        self.objectName = objectName
        self.schema = schema
        self.lastExecution = lastExecution
    }

    /// 从对象树的那个节点 + 当时页签上的回执簿成型。
    ///
    /// 库优先取节点自己记的那个（树上右键的节点知道它属于哪个库），再退回页签 / 连接配置 ——
    /// 反过来会在一棵浏览别的库的树上把「库」写成连接自己的那个。
    public init(
        object: DatabaseObject,
        connectionLabel: String,
        database: String?,
        lastExecution: ExecutionReceipt?
    ) {
        self.init(
            connectionLabel: connectionLabel,
            database: object.database ?? database,
            objectKind: object.kind,
            objectName: object.name,
            schema: object.schema,
            lastExecution: lastExecution.flatMap(LastExecution.init(receipt:))
        )
    }

    /// `schema.name` / `name`。
    public var qualifiedName: String {
        guard let schema, !schema.isEmpty else { return objectName }
        return "\(schema).\(objectName)"
    }

    /// 对象类型的人话（表 / 视图 / 库 …）。
    public func kindName(language: AppLanguage) -> String {
        LocalizedStrings.text(Self.kindKey(objectKind), language: language)
    }

    static func kindKey(_ kind: DatabaseObject.Kind) -> LKey {
        switch kind {
        case .server: return .diagnosisKindServer
        case .database: return .diagnosisKindDatabase
        case .schema: return .diagnosisKindSchema
        case .table: return .diagnosisKindTable
        case .view: return .diagnosisKindView
        case .column: return .diagnosisKindColumn
        case .function: return .diagnosisKindFunction
        case .sequence: return .diagnosisKindSequence
        }
    }

    /// 提示词里的「目标是谁」：连接 / 库 / 对象三段（**不含口令**）。
    ///
    /// 与面板头部那行分开：这里给模型看，字段间用 ` / ` 而不是本地化的标签 ——
    /// 模型读的是结构，不是界面文案（界面文案另有 `summary`）。
    public var promptTarget: String {
        var parts: [String] = [connectionLabel]
        if let database, !database.isEmpty { parts.append(database) }
        parts.append(qualifiedName)
        return parts.joined(separator: " / ")
    }

    /// 面板头部那一行「上下文自动带入了什么」。
    public func summary(language: AppLanguage) -> String {
        var parts: [String] = []
        parts.append(LocalizedStrings.format(.diagnosisScopeConnection, language: language, connectionLabel))
        if let database, !database.isEmpty {
            parts.append(LocalizedStrings.format(.diagnosisScopeDatabase, language: language, database))
        }
        parts.append(LocalizedStrings.format(
            .diagnosisScopeObject,
            language: language,
            kindName(language: language),
            qualifiedName
        ))
        return parts.joined(separator: " · ")
    }

    /// 结论里可点的对象名：**先只放这一个**（就是被诊断的那个节点）。
    ///
    /// 为什么不把「结论里随便出现的一个名字」都拿去树上找：同名对象在不同 schema / 不同库里
    /// 都存在，猜一个跳过去，跳错的地方比不跳更坏。可点的集合必须是**已知身份**的那些，
    /// 所以本片只登记作用域里那一个；将来要把统计读数里的对象也变成可点的，得先给它们身份。
    public var linkTargets: [DiagnosisObjectLinker.Target] {
        guard objectKind != .column else { return [] }
        return [
            DiagnosisObjectLinker.Target(kind: objectKind, name: objectName, schema: schema)
        ]
    }

    // MARK: - 取证计划

    /// 计划里的一条：`sql` 非空 = 真去跑；为空 = **取不到**，`unavailableReason` 说明为什么。
    ///
    /// 为什么不用 `[String?]` 那种形状：`nil` 只说「没有」，说不出「为什么没有」，
    /// 而面板与提示词里那句「为什么」正是判据 ③ 要的。
    public struct Planned: Equatable, Sendable {
        public var kind: DiagnosisEvidence.Kind
        public var sql: String?
        public var unavailableReason: String?

        public init(kind: DiagnosisEvidence.Kind, sql: String?, unavailableReason: String? = nil) {
            self.kind = kind
            self.sql = sql
            self.unavailableReason = unavailableReason
        }
    }

    /// 这一级能跑的语句（表 / 视图才有：它们的「诊断」是从看这几行开始的）。
    public func targetSQL(dialect: any SQLDialect) -> String? {
        switch objectKind {
        case .table, .view:
            guard PrivilegeProbe.isValidIdentifier(objectName) else { return nil }
            if let schema, !schema.isEmpty, !PrivilegeProbe.isValidIdentifier(schema) { return nil }
            return SQLGenerator.selectRows(table: objectName, schema: schema, limit: 200, offset: 0, dialect: dialect)
        default:
            return nil
        }
    }

    /// 对象级统计查询。`nil` = 这个对象类型没有统计视图（**不是**「没有数据」）。
    ///
    /// 口径：只用 PG 12 起就有的视图（`pg_stat_user_tables` / `pg_stat_database` /
    /// `pg_stat_activity`），与统计面板（`FR-STD-DB-DIAG-004`）同一批 —— 升级到 16+ 才有
    /// 的 `pg_stat_io` 不许出现在这里。标识符先过 `PrivilegeProbe.isValidIdentifier`，
    /// 名字里有引号 / 空格一律不发查询（宁可说取不到，也不拼一条会被服务端报错的语句）。
    public func statisticsQuery(dialect: any SQLDialect) -> String? {
        guard dialect.databaseType == .postgresql else { return nil }
        guard PrivilegeProbe.isValidIdentifier(objectName) else { return nil }
        switch objectKind {
        case .table:
            let schemaFilter: String
            if let schema, !schema.isEmpty, PrivilegeProbe.isValidIdentifier(schema) {
                schemaFilter = " AND s.schemaname = \(Self.literal(schema))"
            } else {
                schemaFilter = ""
            }
            return """
            SELECT s.schemaname, s.relname, s.seq_scan, s.idx_scan, s.n_live_tup,
                   pg_total_relation_size(c.oid) AS bytes
              FROM pg_catalog.pg_stat_user_tables s
              JOIN pg_catalog.pg_class c ON c.oid = s.relid
             WHERE s.relname = \(Self.literal(objectName))\(schemaFilter)
            """
        case .schema:
            return """
            SELECT count(*) AS tables,
                   coalesce(sum(n_live_tup), 0) AS live_rows,
                   coalesce(sum(seq_scan), 0) AS seq_scans,
                   coalesce(sum(idx_scan), 0) AS idx_scans
              FROM pg_catalog.pg_stat_user_tables
             WHERE schemaname = \(Self.literal(objectName))
            """
        case .database:
            return """
            SELECT datname, numbackends, xact_commit, xact_rollback, blks_read, blks_hit
              FROM pg_catalog.pg_stat_database
             WHERE datname = \(Self.literal(objectName))
            """
        case .server:
            return """
            SELECT count(*) AS backends,
                   count(*) FILTER (WHERE state = 'active') AS active
              FROM pg_catalog.pg_stat_activity
             WHERE backend_type = 'client backend'
            """
        case .view, .function, .column, .sequence:
            return nil
        }
    }

    /// 统计读不到时那句人话（判据 ③：**明说「未取到」，不编**）。
    ///
    /// 每种对象类型的原因不一样，混成一句「不支持」的话，用户会以为是自己没权限：
    ///   · 视图没有自己的统计 —— 它的开销记在底层表上（不是「没数据」）；
    ///   · 列 / 函数根本没有统计视图；
    ///   · 非 PG 方言没有这几个视图。
    public func statisticsUnavailableReason(language: AppLanguage, dialect: any SQLDialect) -> String? {
        guard statisticsQuery(dialect: dialect) == nil else { return nil }
        if dialect.databaseType != .postgresql {
            return LocalizedStrings.text(.diagnosisStatsNoDialect, language: language)
        }
        if !PrivilegeProbe.isValidIdentifier(objectName) {
            return LocalizedStrings.text(.diagnosisStatsBadName, language: language)
        }
        switch objectKind {
        case .view: return LocalizedStrings.text(.diagnosisStatsView, language: language)
        case .function: return LocalizedStrings.text(.diagnosisStatsFunction, language: language)
        case .column: return LocalizedStrings.text(.diagnosisStatsColumn, language: language)
        case .sequence: return LocalizedStrings.text(.diagnosisStatsSequence, language: language)
        default: return LocalizedStrings.text(.diagnosisStatsNoDialect, language: language)
        }
    }

    /// 取证计划（顺序即证据编号顺序，与全局面同一口径：先看语句与计划，再看历史统计，最后才是读数）。
    ///
    /// **锁不在这份计划里**：`pg_locks` 那条查询是整个实例的，把它挂在「这张表」的诊断下，
    /// 读起来像「这张表在等锁」—— 而实际可能等的是别的库别的表。锁归会话面（`FR-STD-DB-DIAG-005`）。
    public func plannedEvidence(dialect: any SQLDialect, language: AppLanguage) -> [Planned] {
        var plan: [Planned] = []

        if let target = targetSQL(dialect: dialect) {
            plan.append(Planned(kind: .statement, sql: target))
            plan.append(Planned(
                kind: .executionPlan,
                sql: DiagnosisEvidenceQueries.executionPlan(for: target, dialect: dialect)
            ))
        }

        plan.append(Planned(
            kind: .objectStats,
            sql: statisticsQuery(dialect: dialect),
            unavailableReason: statisticsUnavailableReason(language: language, dialect: dialect)
        ))

        // 最近一次执行的读数：有就是一条证据，没有就**明说没取到**（判据 ③）。
        plan.append(Planned(
            kind: .lastExecution,
            sql: lastExecution?.statement,
            unavailableReason: lastExecution == nil
                ? LocalizedStrings.text(.diagnosisLastExecutionNone, language: language)
                : nil
        ))

        return plan
    }

    /// SQL 字面量：单引号自己翻倍。名字已经在上面过了标识符校验，这里只防引号。
    static func literal(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "''") + "'"
    }
}

/// 结论里点对象名 → 跳到树上那个节点：**请求本身就是一个值**（`FR-STD-DB-DIAG-006` ②）。
///
/// 为什么不直接在面板里 `selectTreeObject`：展开状态是**树视图本地**的（`ObjectTreeView.expandedIDs`），
/// 面板够不到。所以面板只发一个请求，树在它自己的 `onChange` 里展开路径并选中 ——
/// 请求里带的是**身份**（类型 / 名字 / schema / 库），不是视图对象。
public struct ObjectTreeJumpRequest: Equatable, Sendable, Identifiable {

    public var kind: DatabaseObject.Kind
    public var name: String
    public var schema: String?
    public var database: String?

    public init(kind: DatabaseObject.Kind, name: String, schema: String? = nil, database: String? = nil) {
        self.kind = kind
        self.name = name
        self.schema = schema
        self.database = database
    }

    public var id: String {
        "\(kind.rawValue)|\(database ?? "")|\(schema ?? "")|\(name)"
    }
}
