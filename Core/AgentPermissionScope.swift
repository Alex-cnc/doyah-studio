import Foundation

/// 当前连接上「我们确实知道」的权限事实（`FR-AI-12` 的客户端半）。
///
/// 三条口径（队列 `L-125`，需求提出者 2026-09-30 拍板「加」）：
/// 1. **确知为否才拦**：只有本机明确知道某项能力不可用时才拦；`nil`（没探到 / 该方言不支持）
///    一律不拦 —— 这一层是**防御性冗余**，不许制造假阴性；
/// 2. **只读连接不可绕过**：与 `ExecutionSafety` 同一口径（`ConnectionConfig.isReadOnly`，`FR-CONN-17`）；
/// 3. **判定只看连接的属性**：事实来自连接配置与 `FR-META-11` 的探测，不来自模型说了什么。
public struct AgentConnectionPermissions: Codable, Equatable, Sendable {

    /// 连接是不是标了「只读连接」（`FR-CONN-17`）。
    public var isReadOnly: Bool

    /// 当前用户能否建库（`FR-META-11` 的探测结果）。`nil` = 没探到 / 该方言不支持。
    public var canCreateDatabase: Bool?

    public init(isReadOnly: Bool = false, canCreateDatabase: Bool? = nil) {
        self.isReadOnly = isReadOnly
        self.canCreateDatabase = canCreateDatabase
    }

    /// 「什么都不知道」= 什么都不拦。
    ///
    /// 它是 `AgentActionGate` 的缺省值：既有调用点（没传连接事实的那些）行为一字不变。
    public static let unknown = AgentConnectionPermissions()
}

/// 语句要求的那一项**连接能力**。
///
/// 只有本机真的探得到的能力才进这个枚举 —— 探不到的能力不在这里假装「有能力」（那种情况走
/// `AgentConnectionPermissions` 的 `nil` = 不拦）。
public enum AgentConnectionCapability: String, Codable, Equatable, Sendable, CaseIterable {
    /// 建 / 删 / 改库（`CREATE` / `DROP` / `ALTER DATABASE`）。
    case createDatabase
}

/// 客户端权限校验发现的越权（`FR-AI-12` 客户端半）。
public enum AgentPermissionFinding: Equatable, Sendable {

    /// 连接标了只读，而语句会改数据 / 结构 / 权限。
    case readOnlyConnection(statements: [String])

    /// 语句要的那项能力，本机探测结论是「没有」。
    case missingCapability(AgentConnectionCapability, statements: [String])

    /// 越权涉及的语句原文（如实报错时点名，不概括成「不安全」）。
    public var statements: [String] {
        switch self {
        case .readOnlyConnection(let statements): return statements
        case .missingCapability(_, let statements): return statements
        }
    }

    /// 对应哪一项连接能力；只读连接那一支不是能力问题 ⇒ `nil`。
    public var capability: AgentConnectionCapability? {
        if case .missingCapability(let capability, _) = self { return capability }
        return nil
    }
}

/// 客户端侧的连接权限校验（`FR-AI-12`「智能体不得超越当前连接权限」的客户端半）。
///
/// **位置 = 发起前**：`AgentActionGate` 在护栏判定之后、建审批单之前先过这一层 ⇒
/// 越权的请求**连审批单都建不出来**（更谈不上执行）。它与服务端约束**不互斥**：
/// 服务端仍然会拒（这一层是防御性冗余），口径从此不再是「只靠同连接 + 服务端拒绝」。
public enum AgentPermissionScope {

    /// 判一次：返回 `nil` = 放行（没有越权，或本机不知道）。
    public static func blockingFinding(
        assessment: AgentGuardAssessment,
        permissions: AgentConnectionPermissions
    ) -> AgentPermissionFinding? {

        // ① 只读连接：写 / 结构变更 / 权限变更一律拦 —— 与 `ExecutionSafety` 的
        //    `changesDataOrSchema` 同一条口径（只读查询与 `SET` 这类会话控制放行，它们不改库里的东西）。
        if permissions.isReadOnly {
            let offenders = assessment.statements
                .filter { $0.kind.changesDataOrSchema }
                .map(\.sql)
            if !offenders.isEmpty {
                return .readOnlyConnection(statements: offenders)
            }
        }

        // ② 探测结论为「不能建库」时，库级结构变更在发起前拦下。
        if permissions.canCreateDatabase == false {
            let offenders = assessment.statements
                .filter { requiresDatabaseCreation($0) }
                .map(\.sql)
            if !offenders.isEmpty {
                return .missingCapability(.createDatabase, statements: offenders)
            }
        }

        return nil
    }

    /// 这条语句是不是**库级**结构变更（`CREATE` / `DROP` / `ALTER DATABASE`）。
    ///
    /// 只看被护栏判成**结构变更**的那些语句 —— 数据变更语句里出现 `database` 这个词
    /// （列名、字符串字面量）不算；再只取语句开头的关键字序列 ⇒ 库名 / 表名里的同名子串不会命中。
    static func requiresDatabaseCreation(_ statement: AgentStatementAssessment) -> Bool {
        guard statement.kind == .schemaChange else { return false }
        let keywords = leadingKeywords(in: statement.sql)
        guard let first = keywords.first, ["CREATE", "ALTER", "DROP"].contains(first) else { return false }
        return keywords.dropFirst().contains("DATABASE")
    }

    /// 取语句开头的关键字序列（大写；跳过空白与首部注释；遇到非标识符字符即停）。
    ///
    /// 词里允许字母 / 数字 / `_` / `$`（标识符的常态，`app2` 读成 `APP2` 而不是 `APP`）；
    /// 首个字符不是字母 / `_`（数字、引号、`(` 等）⇒ 认不出首词，直接停。
    static func leadingKeywords(in sql: String, limit: Int = 3) -> [String] {
        var keywords: [String] = []
        var index = sql.startIndex

        while index < sql.endIndex, keywords.count < limit {
            if sql[index].isWhitespace {
                index = sql.index(after: index)
                continue
            }
            if sql[index...].hasPrefix("--") {
                while index < sql.endIndex, sql[index] != "\n" { index = sql.index(after: index) }
                continue
            }
            if sql[index...].hasPrefix("/*") {
                index = sql.index(index, offsetBy: 2)
                while index < sql.endIndex, !sql[index...].hasPrefix("*/") { index = sql.index(after: index) }
                if index < sql.endIndex { index = sql.index(index, offsetBy: 2) }
                continue
            }

            guard sql[index].isLetter || sql[index] == "_" else { break }

            var word = ""
            while index < sql.endIndex,
                  sql[index].isLetter || sql[index].isNumber || sql[index] == "_" || sql[index] == "$" {
                word.append(sql[index])
                index = sql.index(after: index)
            }
            keywords.append(word.uppercased())
        }

        return keywords
    }

    /// 越权时给用户看的那一句。**语言由调用方给**（Core 不写死语言；文案在语言表里）。
    public static func message(for finding: AgentPermissionFinding, language: AppLanguage) -> String {
        let statement = finding.statements.first ?? ""
        switch finding {
        case .readOnlyConnection:
            return LocalizedStrings.format(
                .agentPermissionReadOnlyConnection,
                language: language,
                statement
            )
        case .missingCapability(let capability, _):
            return LocalizedStrings.format(
                .agentPermissionMissingCapability,
                language: language,
                capabilityName(capability, language: language),
                statement
            )
        }
    }

    /// 能力名（说法在语言表里，不在这里手写一串中文）。`FR-AI-12` / `FR-META-11` 那条出口只此一处。
    public static func capabilityName(_ capability: AgentConnectionCapability, language: AppLanguage) -> String {
        switch capability {
        case .createDatabase:
            return LocalizedStrings.text(.agentPermissionCapabilityCreateDatabase, language: language)
        }
    }
}
