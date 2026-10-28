import Foundation

/// 高危任务执行前的**逐条**审批计划（`FR-STD-DB-TASK-002`）。
///
/// 需求（《需求规格说明书》§3.4.28）要的是「**逐条**列出将要执行的语句、目标库、预估影响范围，
/// 等人工确认；确认才发送，拒绝即中止并留痕」。现实里要审的从来不是一条语句：
/// 数据任务的「覆盖写入」会编译成 `TRUNCATE` + `INSERT` 两条，手写脚本里可能更多。
/// 而既有的审批单只摊一份 `sql` 文本 + 一个总影响行数 —— 两条语句合成一坨时，
/// 「哪条打哪个库」「每条各影响多少行」都答不出来，人只能整体点「批准」。
///
/// 本类型把「要审的东西」拆成**可逐条读出**的形状：
/// - 一条语句一行（`index` 从 1 起、`sql` 原文、`kind` 首词、`targetDatabase`）；
/// - 影响面**逐条各存一份**（`Impact`），不是整批一个数 —— 合计会掩盖「其中一条扫全表」；
/// - `pending` / `rows` / `unavailable` 三档分开：**估不出来不许冒充 0 行**，
///   那是「一条都不命中」这个具体答案，与「不知道」是两件事。
///
/// 决策只经 `outcome(for:decision:)` 这一处：批准 ⇒ **整批按原顺序**交出；
/// 拒绝 ⇒ **一条都不给**（返回值里没有任何语句可发）。于是「未确认不发送任何语句」
/// 是结构性的，而不是靠调用方记得先判断。
public enum HighRiskTaskApproval {

    // MARK: - 影响面

    /// 单条语句的影响面。**没有**「不适用」这一档 —— 不适用是「这条不改数据」，由 `kind` 说。
    public enum Impact: Equatable, Sendable {
        /// 还没算（界面显示「估算中…」，不许显示成 0 行）。
        case pending
        /// 优化器给的预计行数。`0` 是合法答案（`WHERE` 一条都不命中）。
        case rows(Int)
        /// 估不出来 + 原因码（`notDataChange` / `noConnection` / `dialectUnsupported` /
        /// `noAnswer` / `parseFailed` / `queryFailed`）。原因码由调用方翻成人话。
        case unavailable(String)
    }

    // MARK: - 一条语句

    /// 审批单上的一行。
    public struct Statement: Identifiable, Equatable, Sendable {
        public let id: UUID
        /// 1 起。与拆分器给的序号一致，界面按它排序/编号。
        public let index: Int
        /// 语句原文（拆分器给的原样，不改写）。
        public let sql: String
        /// 这条语句要打哪台库。`nil` = 当前连接没指定库（界面如实写「未指定」，不编一个名字）。
        public let targetDatabase: String?
        /// 首词（大写，如 `TRUNCATE` / `INSERT` / `UPDATE`）。非 SQL 语句给 `OTHER`。
        public let kind: String
        public var impact: Impact

        public init(
            id: UUID = UUID(),
            index: Int,
            sql: String,
            targetDatabase: String?,
            kind: String,
            impact: Impact = .pending
        ) {
            self.id = id
            self.index = index
            self.sql = sql
            self.targetDatabase = targetDatabase
            self.kind = kind
            self.impact = impact
        }

        /// 影响面是否已经问过（`pending` = 没问过）。
        public var impactIsSettled: Bool {
            if case .pending = impact { return false }
            return true
        }
    }

    // MARK: - 计划

    public enum PlanError: Error, Equatable {
        /// 一句都没有 —— 没什么可审的，也不许造一张空审批单出来。
        case noStatements
        /// 第 `index` 条剥掉空白后为空（拆分器一般不会给，但调用方可以直接喂语句列表）。
        case blankStatement(index: Int)

        /// 机器码（界面翻人话，Core 不做本地化）。
        public var code: String {
            switch self {
            case .noStatements: return "noStatements"
            case .blankStatement: return "blankStatement"
            }
        }
    }

    /// 待审的整批。
    public struct Plan: Equatable, Sendable {
        public let targetDatabase: String?
        public private(set) var statements: [Statement]
        /// 整批的身份：目标库 + 每条语句原文派生的稳定串（同一批两次算出来逐字相同）；
        /// 它与审批单绑定 —— 参数换了一处就不再是同一张单。
        public let fingerprint: String

        public var count: Int { statements.count }

        /// 还没算影响面的条数。界面可以据此显示「还有 2 条在估算」。
        public var pendingImpactCount: Int {
            statements.filter { !$0.impactIsSettled }.count
        }

        /// 整批的语句原文（按顺序、以 `;` 换行拼接）。给「原样执行」那条老路用。
        public var scriptText: String {
            statements.map(\.sql).joined(separator: ";\n")
        }

        public func statement(at index: Int) -> Statement? {
            statements.first { $0.index == index }
        }

        /// 给某一条盖上影响面。序号不存在 ⇒ `false`（不静默新增行）。
        @discardableResult
        public mutating func setImpact(_ impact: Impact, forIndex index: Int) -> Bool {
            guard let position = statements.firstIndex(where: { $0.index == index }) else { return false }
            statements[position].impact = impact
            return true
        }

        init(targetDatabase: String?, statements: [Statement], fingerprint: String) {
            self.targetDatabase = targetDatabase
            self.statements = statements
            self.fingerprint = fingerprint
        }
    }

    // MARK: - 建计划

    /// 从一段脚本建计划（按方言拆句）。
    ///
    /// 拆句规则与执行侧**同一份**（`StatementSplitter`）—— 各写一份正则的话，
    /// 审批单上数的条数会与真正发下去的条数悄悄错开。
    public static func plan(
        sql: String,
        targetDatabase: String?,
        databaseType: DatabaseType = .postgresql
    ) throws -> Plan {
        let split = StatementSplitter(databaseType: databaseType).split(sql)
        return try plan(
            statements: split.sorted { $0.index < $1.index }.map(\.sql),
            targetDatabase: targetDatabase
        )
    }

    /// 从「已经拆好的语句列表」建计划（数据任务那条路：`DataTaskRunner.writeStatements`）。
    public static func plan(
        statements: [String],
        targetDatabase: String?
    ) throws -> Plan {
        guard !statements.isEmpty else { throw PlanError.noStatements }

        var lines: [Statement] = []
        for (offset, raw) in statements.enumerated() {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw PlanError.blankStatement(index: offset + 1) }
            lines.append(
                Statement(
                    index: offset + 1,
                    sql: raw,
                    targetDatabase: normalizedDatabase(targetDatabase),
                    kind: kind(of: trimmed)
                )
            )
        }

        let database = normalizedDatabase(targetDatabase)
        let fingerprint = fingerprint(database: database, statements: lines)
        return Plan(targetDatabase: database, statements: lines, fingerprint: fingerprint)
    }

    /// 首词（大写）。认不出（空、只有注释、只有符号）⇒ `OTHER` —— 不猜。
    public static func kind(of sql: String) -> String {
        let stripped = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty else { return "OTHER" }
        let first = stripped
            .split(whereSeparator: { $0.isWhitespace || $0 == "(" || $0 == ";" })
            .first
            .map(String.init) ?? ""
        // 只看字母：`--` 开头的注释行、`::` 之类的符号都不是语句类别。
        let letters = first.filter { $0.isLetter }
        guard !letters.isEmpty else { return "OTHER" }
        return letters.uppercased()
    }

    // MARK: - 决策

    public enum Decision: Equatable, Sendable {
        case approve
        case reject
    }

    public enum Outcome: Equatable, Sendable {
        /// 批准：**整批**交出，顺序与 `index` 一致（调用方不许自己再切一半去发）。
        case sendAll([Statement])
        /// 拒绝：一条都不发。`reason` 是机器码（`rejected` / `emptyPlan`）。
        case sendNothing(reason: String)

        public var statements: [Statement] {
            if case .sendAll(let statements) = self { return statements }
            return []
        }

        public var sendsAnything: Bool { !statements.isEmpty }
    }

    /// 唯一决策口：批准才交出语句，拒绝交出一张空表。
    ///
    /// 「按次」不在这里做 —— 一次批准只能兑现一次由审批单自己的状态机保证
    /// （`AgentApproval.approve` / `reject` 非法流转会抛错）。这里只管**同一批的原子性**：
    /// 要么整批发，要么一条都不发，没有「先发前两条看看」这一档。
    public static func outcome(for plan: Plan, decision: Decision) -> Outcome {
        guard !plan.statements.isEmpty else { return .sendNothing(reason: "emptyPlan") }
        switch decision {
        case .approve: return .sendAll(plan.statements)
        case .reject: return .sendNothing(reason: "rejected")
        }
    }

    // MARK: - 内部

    static func normalizedDatabase(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// FNV-1a 64（不引第三方、不吃 `Hasher` 的随机种子 ⇒ 同一批跨进程算出同一个串）。
    static func fingerprint(database: String?, statements: [Statement]) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        let seed = (database ?? "") + "\u{1}"
        for scalar in seed.utf8 { hash = (hash ^ UInt64(scalar)) &* 0x1000_0000_01b3 }
        for statement in statements {
            for scalar in statement.sql.utf8 { hash = (hash ^ UInt64(scalar)) &* 0x1000_0000_01b3 }
            // 语句之间用分隔符断开：`A;B` 与 `AB` 不许算成同一批。
            hash = (hash ^ 0x1f) &* 0x1000_0000_01b3
        }
        return String(hash, radix: 16)
    }
}
