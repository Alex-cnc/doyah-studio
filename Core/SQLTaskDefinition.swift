import Foundation

/// 任务定义（概设 §5.3，`FR-STD-DB-TASK-001`）。
///
/// 为什么不复用 `SavedQuery`：那个类型是「一段 SQL 片段」= 书签，存下来只为下次贴回编辑器。
/// 本类型是**可执行任务** —— 它把「在哪个连接的哪个库上、只读还是可写、最多动多少行、
/// 要不要人点头」一起存下来；下次复用同一条定义时，执行前的判定（`SQLTaskGuard`）
/// 拿它当基准，「定义与实际执行参数不一致就拒绝执行」这句话才有落点。
///
/// 两个类型分两个文件存（`saved-queries.json` / `sql-tasks.json`）也是这个道理：
/// 一个任务被拒绝的理由是「与定义不符」，前提是那条定义不会被当片段随手改掉。
public struct SQLTaskDefinition: Codable, Equatable, Sendable, Identifiable {

    /// 读写模式。默认**只读**（概设 §5.3：读写模式 默认值 = 只读）。
    public enum AccessMode: String, Codable, Sendable, CaseIterable {
        case readOnly
        case writable

        public var displayName: String {
            switch self {
            case .readOnly: return "只读"
            case .writable: return "可写"
            }
        }
    }

    /// 定义不完整的一档。**一次列全**（改一处再点一次的表单最费人）。
    public enum Issue: Equatable, Sendable {
        case emptyName
        case emptySQL
        case emptyTargetDatabase
        case rowLimitNotPositive(Int)

        public var message: String {
            switch self {
            case .emptyName:
                return "任务名不能为空。"
            case .emptySQL:
                return "任务里没有语句 —— 空任务存下来也跑不出东西。"
            case .emptyTargetDatabase:
                return "任务没有目标库：定义要绑一个库，执行时才能核对是不是同一个库。"
            case .rowLimitNotPositive(let value):
                return "影响行数上限要写正整数（现在写的是 \(value)）。不限就留空。"
            }
        }
    }

    public var id: UUID
    /// 任务名。**唯一**（同名不同 id 在保存时被拒，见 `SQLTaskStore.save`）。
    public var name: String
    public var sql: String
    /// 定义落在哪个连接上（概设 §5.3「连接标识 / 目标库 执行时必须一致」）。
    public var connectionID: UUID?
    /// 连接的可读名，只用于界面与拒绝理由（连接改名后不跟着变，也不参与判定）。
    public var connectionName: String?
    public var targetDatabase: String
    public var accessMode: AccessMode
    /// 影响行数上限；`nil` = 不限（概设 §5.3「否填」）。
    public var rowLimit: Int?
    /// 执行前是否要人点头。默认**真**（概设 §5.3：高危默认需审批）。
    public var requiresApproval: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        sql: String,
        connectionID: UUID? = nil,
        connectionName: String? = nil,
        targetDatabase: String,
        accessMode: AccessMode = .readOnly,
        rowLimit: Int? = nil,
        requiresApproval: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.sql = sql
        self.connectionID = connectionID
        self.connectionName = connectionName
        self.targetDatabase = targetDatabase
        self.accessMode = accessMode
        self.rowLimit = rowLimit
        self.requiresApproval = requiresApproval
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public extension SQLTaskDefinition {

    /// 定义不完整之处（空表 = 完整）。保存与执行前各判一次：
    /// 存的时候判，是为了不让一条跑不动的定义进文件；执行前判，是因为文件可能被手改。
    func issues() -> [Issue] {
        var out: [Issue] = []
        if trimmed(name).isEmpty { out.append(.emptyName) }
        if trimmed(sql).isEmpty { out.append(.emptySQL) }
        if trimmed(targetDatabase).isEmpty { out.append(.emptyTargetDatabase) }
        if let rowLimit, rowLimit <= 0 { out.append(.rowLimitNotPositive(rowLimit)) }
        return out
    }

    var isValid: Bool { issues().isEmpty }

    /// 去首尾空白的副本（名称 / SQL / 目标库）。空名字仍是空名字 —— 判空交给 `issues()`，
    /// 这里不替它编一个默认名（编出来的名字会让「同名任务」变得莫名其妙）。
    func normalized() -> SQLTaskDefinition {
        var copy = self
        copy.name = trimmed(name)
        copy.sql = trimmed(sql)
        copy.targetDatabase = trimmed(targetDatabase)
        copy.connectionName = connectionName.map(trimmed)
        return copy
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// 任务定义的持久化（`sql-tasks.json`）。与连接配置、保存查询各存一个文件，理由见类型注释。
///
/// **唯一的写入口**：`issues()` 校验与「任务名唯一」都在 `save` 里 ——
/// 界面、命令行、以后的调度器都从这一处过。判定散到各调用点必漏一处，
/// 而漏掉的那一处正好是「同名任务被静默覆盖」。
public actor SQLTaskStore {
    public static let shared = SQLTaskStore()

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(directoryURL: URL? = nil) {
        let baseURL: URL
        if let directoryURL {
            baseURL = directoryURL
        } else {
            let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
            baseURL = applicationSupport.appendingPathComponent(DoyahIdentity.applicationSupportDirectoryName, isDirectory: true)
        }

        self.fileURL = baseURL.appendingPathComponent("sql-tasks.json", isDirectory: false)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func fileLocation() -> URL { fileURL }

    public func tasks() throws -> [SQLTaskDefinition] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            return try decoder.decode([SQLTaskDefinition].self, from: Data(contentsOf: fileURL))
        } catch {
            throw AppError.persistence(error.localizedDescription)
        }
    }
}

public extension SQLTaskStore {

    /// 新增或替换（按 `id` 匹配）一条任务定义。
    ///
    /// 三条拒绝：定义不完整（一次列出全部问题）· 任务名为空 · 同名不同 id。
    /// 同名**同 id** 是「原地改」，允许 —— 那正是复用一条定义时改目标库 / 上限的正常路径。
    @discardableResult
    func save(_ task: SQLTaskDefinition) throws -> SQLTaskDefinition {
        var stored = task.normalized()

        let issues = stored.issues()
        guard issues.isEmpty else {
            throw AppError.persistence(issues.map(\.message).joined(separator: " "))
        }

        var all = try tasks()
        let name = stored.name
        let clash = all.contains {
            $0.id != stored.id
                && $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == name.lowercased()
        }
        guard !clash else {
            throw AppError.persistence(
                "已有同名任务「\(name)」：任务名要唯一，先改名或删掉旧的。"
            )
        }

        stored.updatedAt = Date()
        if let index = all.firstIndex(where: { $0.id == stored.id }) {
            // 创建时刻跟第一次保存走：复用一条定义时改的是内容，不是它的来历。
            stored.createdAt = all[index].createdAt
            all[index] = stored
        } else {
            all.append(stored)
        }
        try write(all)
        return stored
    }

    func delete(id: UUID) throws {
        var all = try tasks()
        all.removeAll { $0.id == id }
        try write(all)
    }

    private func write(_ tasks: [SQLTaskDefinition]) throws {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try encoder.encode(tasks)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            throw AppError.persistence(error.localizedDescription)
        }
    }
}

/// 一次「按定义执行」的实际参数。
///
/// **定义是基准、实际是变量** —— 判定（`SQLTaskGuard.check`）逐项对：
/// 连接 / 目标库 / 读写模式 / 上限。对不上的那几档里，**收紧放行、放宽拒绝**：
/// 定义写着上限 100 而这次想跑 500，那不是「用户改主意了」，那是把护栏绕过去；
/// 反过来定义 500 而这次只想跑 100 是更严的要求，没有绕过的意思。
public struct SQLTaskExecution: Equatable, Sendable {
    public var connectionID: UUID?
    public var database: String?
    public var accessMode: SQLTaskDefinition.AccessMode
    /// 这次真打算用的上限；`nil` = 不限。
    public var rowLimit: Int?
    /// 这次真要跑的语句（复用之后用户可能又改过编辑器 —— 判定看的是**要跑的这一份**）。
    public var sql: String

    public init(
        connectionID: UUID? = nil,
        database: String?,
        accessMode: SQLTaskDefinition.AccessMode,
        rowLimit: Int?,
        sql: String
    ) {
        self.connectionID = connectionID
        self.database = database
        self.accessMode = accessMode
        self.rowLimit = rowLimit
        self.sql = sql
    }
}

/// 任务执行前的判定结论。三档与 `ExecutionSafety.Decision` 同构（放行 / 需审批 / 拒绝），
/// 但**不许混用一个类型**：那个类型说的是「这条语句看起来危险」，这个说的是「与任务定义不符」。
/// 两句话在界面上要分开说 —— 用户看到「与定义不符」才会去改定义或换库，
/// 看到「有风险」只会学会闭眼点「仍然执行」。
public enum SQLTaskVerdict: Equatable, Sendable {
    case allow
    case needsApproval(reasons: [String], statements: [String])
    case refused(reasons: [String], statements: [String])

    public var isAllowed: Bool {
        if case .allow = self { return true }
        return false
    }

    public var isRefused: Bool {
        if case .refused = self { return true }
        return false
    }

    public var reasons: [String] {
        switch self {
        case .allow: return []
        case .needsApproval(let reasons, _), .refused(let reasons, _): return reasons
        }
    }

    public var statements: [String] {
        switch self {
        case .allow: return []
        case .needsApproval(_, let statements), .refused(_, let statements): return statements
        }
    }

    /// 面板 / 问题页签上的一句话（多条理由逐行，涉事语句跟在后面）。
    public var message: String {
        var lines = reasons
        if !statements.isEmpty {
            lines.append("")
            lines.append(contentsOf: statements.map { "· " + SQLTaskGuard.oneLine($0) })
        }
        return lines.joined(separator: "\n")
    }
}

/// 按定义执行时的**唯一判定口**（`FR-STD-DB-TASK-001` 的验收要点 ②③ 落在这里）。
///
/// 判定顺序是刻意的：**先判「定义本身能不能跑」，再判「这次参数对不对」，最后才判「要不要人点头」**。
/// 反过来先问审批，用户会为一个根本不会执行的请求去点确认。
public enum SQLTaskGuard {

    /// 逐项核对定义与实际参数。
    ///
    /// - Parameters:
    ///   - task: 保存下来的定义（这里不替它补默认值，缺什么就拒什么）。
    ///   - execution: 这次真要用的连接 / 库 / 模式 / 上限 / 语句。
    ///   - databaseType: 方言，决定「哪条语句算写」（与 `ExecutionSafety` 同一套词法）。
    public static func check(
        task: SQLTaskDefinition,
        execution: SQLTaskExecution,
        databaseType: DatabaseType = .postgresql
    ) -> SQLTaskVerdict {
        let definition = task.normalized()

        // ① 定义本身不完整：文件可能被手改过，执行前再判一次（不是重复，是另一层入口）。
        let issues = definition.issues()
        guard issues.isEmpty else {
            return .refused(
                reasons: ["任务定义不完整，已拒绝执行："] + issues.map(\.message),
                statements: []
            )
        }

        // ② 连接不符。
        if let defined = definition.connectionID,
           let actual = execution.connectionID,
           defined != actual {
            let name = definition.name
            let definedName = definition.connectionName ?? "定义里的那个连接"
            return .refused(
                reasons: [
                    "任务「\(name)」落在连接「\(definedName)」上，这次要在另一个连接上执行 —— 已拒绝。",
                    "同一条定义只绑一个连接：换连接请另存一条任务。"
                ],
                statements: []
            )
        }

        // ③ 目标库不符（概设 §5.3「执行时必须一致」）。
        let actualDatabase = execution.database?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard actualDatabase == definition.targetDatabase else {
            return .refused(
                reasons: [
                    "目标库与任务定义不符 —— 已拒绝。",
                    "定义：\(definition.targetDatabase)；这次要在：\(actualDatabase.isEmpty ? "（还没选定库）" : actualDatabase) 上执行。",
                    "确实要换库，就另存一条任务（改定义会让以前那些执行记录失去含义）。"
                ],
                statements: []
            )
        }

        // ④ 只读任务里出现写语句（验收要点 ③）。这一档**不可绕过**：
        //    只读是任务的属性，不是「要不要冒险」—— 与 `ExecutionSafetyPolicy.isReadOnly` 同一条道理。
        let writes = writeStatements(in: execution.sql, databaseType: databaseType)
        if definition.accessMode == .readOnly, !writes.isEmpty {
            return .refused(
                reasons: [
                    "任务「\(definition.name)」是**只读**任务：客户端拒绝执行写语句。",
                    "这是任务自己的属性，不是数据库权限 —— 要写请另存一条可写任务。"
                ],
                statements: writes
            )
        }

        // ⑤ 可写任务遇上只读连接：不是「放宽」，是根本跑不成，早说比到服务端报错好。
        if definition.accessMode == .writable, execution.accessMode == .readOnly {
            return .refused(
                reasons: [
                    "任务「\(definition.name)」是可写任务，但这次用的是只读连接 —— 已拒绝。",
                    "换一个可写连接，或把任务改成只读（改定义是人的决定，不由客户端代做）。"
                ],
                statements: []
            )
        }

        // ⑥ 影响行数上限：定义有上限时，这次必须带上限、且不许比定义更松。
        if let limit = definition.rowLimit {
            guard let actual = execution.rowLimit else {
                return .refused(
                    reasons: [
                        "任务「\(definition.name)」有影响行数上限 \(limit) 行，这次执行没有上限 —— 已拒绝（不许绕过上限）。"
                    ],
                    statements: []
                )
            }
            if actual > limit {
                return .refused(
                    reasons: [
                        "影响行数上限被放宽了：定义 \(limit) 行，这次 \(actual) 行 —— 已拒绝。",
                        "比定义更小是允许的（收紧不是绕过），放宽不是。"
                    ],
                    statements: []
                )
            }
        }

        // ⑦ 审批：只在**真会改东西**时才问人。纯读任务挂一条审批，只会让人学会闭眼点。
        if definition.requiresApproval, !writes.isEmpty {
            var reasons = [
                "任务「\(definition.name)」要求执行前审批：这次有 \(writes.count) 条语句会改数据或结构。",
                "目标库：\(definition.targetDatabase)。批准才发送。"
            ]
            if let limit = definition.rowLimit {
                reasons.append("影响行数上限：\(limit) 行（超过会被拦下）。")
            }
            return .needsApproval(reasons: reasons, statements: writes)
        }

        return .allow
    }

    /// 哪几条语句会改数据或结构。
    ///
    /// **复用 `AgentGuardrail` 的词法**，不另写一套判定：同一段 SQL 在「只读连接」那条路上
    /// 被拦、在「只读任务」这条路上被放行，是最容易出的两套口径。
    public static func writeStatements(
        in sql: String,
        databaseType: DatabaseType = .postgresql
    ) -> [String] {
        let policy = AgentGuardPolicy(
            readOnly: false,
            requireApprovalForHighRisk: false,
            requireApprovalForWrites: false
        )
        return StatementSplitter(databaseType: databaseType)
            .split(sql)
            .map(\.sql)
            .filter { statement in
                AgentGuardrail.evaluate(
                    sql: statement,
                    databaseType: databaseType,
                    policy: policy
                ).statements.contains { $0.kind.changesDataOrSchema }
            }
    }

    /// 压成单行，便于在拒绝理由 / 审批单里列语句。
    static func oneLine(_ sql: String, limit: Int = 120) -> String {
        let collapsed = sql
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return collapsed.count > limit ? String(collapsed.prefix(limit)) + "…" : collapsed
    }
}

/// 任务的上限在**执行之后**才量得到（影响行数由服务端回来）。
///
/// 四档分开是刻意的：`unmeasured` 与 `within(0)` 必须能区分 ——
/// 「没量到」写成「动了 0 行」就是拿一个编出来的读数去换绿灯。
public enum SQLTaskRowVerdict: Equatable, Sendable {
    /// 定义没写上限。
    case unlimited
    case within(limit: Int, actual: Int)
    case exceeded(limit: Int, actual: Int)
    /// 有上限但这次量不到影响行数（例如语句没有回执）。
    case unmeasured(limit: Int)

    public var isExceeded: Bool {
        if case .exceeded = self { return true }
        return false
    }

    /// 超限 / 量不到都要说出来；没超的不吭声（正常执行不该多一行噪音）。
    public var message: String {
        switch self {
        case .unlimited, .within:
            return ""
        case .exceeded(let limit, let actual):
            return "这次动了 \(actual) 行，超过任务定义的上限 \(limit) 行 —— 已经执行的那部分不会被撤销，请自行核对。"
        case .unmeasured(let limit):
            return "任务定义有上限 \(limit) 行，但这次拿不到影响行数 —— 「没有读数」不等于「没有超」。"
        }
    }
}

public extension SQLTaskGuard {

    /// 拿实测影响行数与定义上限比。`actual` 为 `nil` ⇒ `unmeasured`，不冒充 0。
    static func rowVerdict(limit: Int?, actual: Int?) -> SQLTaskRowVerdict {
        guard let limit else { return .unlimited }
        guard let actual else { return .unmeasured(limit: limit) }
        return actual > limit
            ? .exceeded(limit: limit, actual: actual)
            : .within(limit: limit, actual: actual)
    }
}
