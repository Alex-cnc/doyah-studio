import Foundation

/// **及时刹停**（`FR-AGT-CORE-LOOP-007` / 本端计划 P2-3）：伤害性动作**前置**停止 —— 不建审批单、不执行。
///
/// 三类点名：**删库** / **覆盖** / **对外发布**。命令类的危害复用 `AgentHarmStop`（不另写一套表）。
public enum AgentPreAction: Equatable, Sendable {
    case sql(String)
    /// 写文件；`exists` = 目标已存在（覆盖既有内容）。
    case fileWrite(path: String, exists: Bool)
    case command(String)
    /// 对外发布（推到远端 / 发布包 / 发消息）。
    case externalPublish(channel: String)
}

public enum AgentStopReason: Equatable, Sendable {
    /// 删库 / 删 schema（整库级不可逆）。
    case dropDatabase
    case dropSchema
    /// 清空整表（无 `WHERE`）。
    case truncateAll
    case deleteWithoutWhere
    /// 覆盖已存在的文件（用户没说要新建）。
    case overwriteExistingFile(path: String)
    /// 对外发布。
    case externalPublish(channel: String)
    /// 命令类危害（复用 `AgentHarmStop` 的分类）。
    case commandHarm(AgentHarmCategory)
}

public struct AgentStopSignal: Equatable, Sendable {
    public var reason: AgentStopReason
    /// 命中的字面（ASCII，便于审计与判据）。
    public var marker: String

    public init(reason: AgentStopReason, marker: String) {
        self.reason = reason
        self.marker = marker
    }
}

public enum AgentPreActionGate {

    /// 纯函数：动作进、结论出。`nil` = 放行（放行不等于免审批，审批是另一层）。
    public static func inspect(_ action: AgentPreAction) -> AgentStopSignal? {
        switch action {
        case .sql(let sql):
            return inspectSQL(sql)
        case .fileWrite(let path, let exists):
            guard exists else { return nil }
            return AgentStopSignal(reason: .overwriteExistingFile(path: path), marker: "overwrite:\(path)")
        case .command(let command):
            guard let harm = AgentHarmStop.inspect(command: command) else { return nil }
            return AgentStopSignal(reason: .commandHarm(harm.category), marker: harm.marker)
        case .externalPublish(let channel):
            return AgentStopSignal(reason: .externalPublish(channel: channel), marker: "publish:\(channel)")
        }
    }

    /// SQL 侧的「删库 / 清表 / 无 WHERE 删除」。
    public static func inspectSQL(_ raw: String) -> AgentStopSignal? {
        let normalized = raw
            .uppercased()
            .split(whereSeparator: { $0.isWhitespace || $0 == "\n" })
            .joined(separator: " ")
        guard !normalized.isEmpty else { return nil }
        if normalized.contains("DROP DATABASE") {
            return AgentStopSignal(reason: .dropDatabase, marker: "DROP DATABASE")
        }
        if normalized.contains("DROP SCHEMA") {
            return AgentStopSignal(reason: .dropSchema, marker: "DROP SCHEMA")
        }
        if normalized.contains("TRUNCATE") {
            return AgentStopSignal(reason: .truncateAll, marker: "TRUNCATE")
        }
        if (normalized.hasPrefix("DELETE") || normalized.contains(" DELETE ")) && !normalized.contains(" WHERE ") {
            return AgentStopSignal(reason: .deleteWithoutWhere, marker: "DELETE without WHERE")
        }
        return nil
    }
}

/// 判据用的最小执行壳：**只记三件事** —— 是否刹停、有没有建审批单、有没有真执行。
/// 放行路径也不执行（本壳只测接线，不测业务）。
public struct AgentPreActionHarness: Sendable {
    public private(set) var approvalsCreated: Int = 0
    public private(set) var executed: Int = 0
    public private(set) var stops: [AgentStopSignal] = []

    public init() {}

    public enum Outcome: Equatable, Sendable {
        case stopped(AgentStopSignal)
        /// 放行：需要审批的动作会 +1 审批单；只读动作直接「执行」+1。
        case allowed(requiresApproval: Bool)
    }

    public mutating func attempt(_ action: AgentPreAction, requiresApproval: Bool) -> Outcome {
        if let signal = AgentPreActionGate.inspect(action) {
            stops.append(signal)
            return .stopped(signal)          // 不建审批单、不执行
        }
        if requiresApproval {
            approvalsCreated += 1
        } else {
            executed += 1
        }
        return .allowed(requiresApproval: requiresApproval)
    }
}
