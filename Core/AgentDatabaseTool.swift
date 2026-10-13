import Foundation

/// 执行器的**注入口**（`FR-AI-20` ⑤）。两种执行各一个入口 —— 只读与写在**调用点**就分开，
/// 不靠字符串再判一次。
///
/// **结果里没有行数据的落点**：只回列名与行数 / 影响行数（`NFR-AI-01` 的口径，与 `AgentObservation` 同办）。
public protocol AgentQueryExecutor: Sendable {
    func executeReadOnly(sql: String) -> AgentQueryExecution
    func executeWrite(sql: String) -> AgentQueryExecution
}

public struct AgentQueryExecution: Equatable, Sendable {
    public var columns: [String]
    public var affectedRows: Int
    public var statementKind: String
    /// 失败时给可读原因（脱敏由执行器一侧保证，照 `AgentAudit.redacted` 同族口径）。
    public var errorMessage: String?

    public init(columns: [String] = [], affectedRows: Int = 0,
                statementKind: String = "", errorMessage: String? = nil) {
        self.columns = columns
        self.affectedRows = affectedRows
        self.statementKind = statementKind
        self.errorMessage = errorMessage
    }
}

/// `query_db` 工具（`FR-AI-20` ①⑤）：**只读语句不经审批直接跑**；写语句按次指纹入审批，未批准不执行；
/// 只读模式下连审批单都建不出来（沿用既有 `AgentGuardrail` —— 不另立第二套判定）。
public struct AgentDatabaseTool: Sendable {

    public var registry: AgentToolRegistry
    public var policy: AgentGuardPolicy
    public var databaseType: DatabaseType
    public var executor: AgentQueryExecutor

    public init(registry: AgentToolRegistry = .standard,
                // 默认 = **写操作逐次批准**（`FR-AI-09` 口径）。注意 `AgentGuardPolicy()` 的默认是**只读模式**
                // （`readOnlyDefault`），拿它当默认会让写语句连审批单都建不出来 —— 那是「只读」那一档，不是这一档。
                policy: AgentGuardPolicy = AgentGuardPolicy(readOnly: false,
                                                            requireApprovalForHighRisk: true,
                                                            requireApprovalForWrites: true),
                databaseType: DatabaseType = .postgresql,
                executor: AgentQueryExecutor) {
        self.registry = registry
        self.policy = policy
        self.databaseType = databaseType
        self.executor = executor
    }

    /// 备一次查询的结果（**没有副作用**：只判定，不执行）。
    public enum Plan: Equatable, Sendable {
        /// 只读 ⇒ 可直接跑（不经审批）。
        case runReadOnly(kind: AgentStatementKind)
        /// 要审批（写语句 / 高危语句）。
        case needsApproval(AgentApprovalRequest)
        /// 被策略拒（只读模式下的写语句等）。
        case refused(AgentToolRefusal, detail: String)
    }

    public func plan(sql: String, tool: AgentToolDefinition? = nil) -> Plan {
        guard let tool = tool ?? registry.definition(for: .queryDatabase) else {
            return .refused(.unregistered, detail: AgentToolLevel.readOnly.rawValue)
        }
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .refused(.emptyQuery, detail: sql) }

        let assessment = AgentGuardrail.evaluate(sql: trimmed, databaseType: databaseType, policy: policy)
        switch assessment.verdict {
        case .deny(let denial):
            return .refused(.deniedByPolicy, detail: Self.detail(for: denial))

        case .allow:
            // 全是只读语句才允许直接跑 —— 有任何一条不是，就得走审批（判定权在护栏，不在这里重判）。
            let allReadOnly = !assessment.statements.isEmpty && assessment.statements.allSatisfy { $0.kind.isReadOnly }
            guard allReadOnly else { return .needsApproval(request(sql: trimmed, tool: tool, findings: [])) }
            let kind = assessment.statements.first?.kind ?? .unknown
            return .runReadOnly(kind: kind)

        case .requireApproval(let findings):
            return .needsApproval(request(sql: trimmed, tool: tool, findings: findings))
        }
    }

    /// 跑。**只读直跑；写要指纹一致且在已批准集合里**（`FR-AI-20` ⑤ 的负例方向就在这里）。
    public func run(sql: String, tool: AgentToolDefinition? = nil,
                    fingerprint: String? = nil, granted: Set<String> = []) -> AgentToolOutcome {
        switch plan(sql: sql, tool: tool) {
        case .refused(let code, let detail):
            return .refused(code, detail: detail)

        case .runReadOnly(let kind):
            return outcome(from: executor.executeReadOnly(sql: sql), kind: kind)

        case .needsApproval(let request):
            guard let fingerprint, fingerprint == request.fingerprint, granted.contains(fingerprint) else {
                return .refused(.approvalRequired, detail: request.fingerprint)
            }
            let kind = AgentGuardrail.evaluate(sql: sql, databaseType: databaseType, policy: policy)
                .statements.first?.kind ?? .unknown
            return outcome(from: executor.executeWrite(sql: sql), kind: kind)
        }
    }

    // MARK: - 内部

    private func request(sql: String, tool: AgentToolDefinition, findings: [AgentGuardFinding]) -> AgentApprovalRequest {
        // 指纹按**次**：同一条 SQL 再批一次仍然只有一次有效，换了 SQL 指纹就变。
        let material = [tool.name, sql, databaseType.rawValue].joined(separator: "|")
        let payload = findings.isEmpty ? sql : sql + "\n" + findings.map(\.rawValue).joined(separator: " ")
        return AgentApprovalRequest(toolName: tool.name,
                                    fingerprint: AgentFingerprint.hash(material),
                                    payload: payload)
    }

    private func outcome(from execution: AgentQueryExecution, kind: AgentStatementKind) -> AgentToolOutcome {
        .rows(AgentToolRowsOutput(columns: execution.columns,
                                  rowCount: execution.affectedRows,
                                  statementKind: execution.statementKind.isEmpty ? kind.rawValue : execution.statementKind,
                                  errorMessage: execution.errorMessage))
    }

    private static func detail(for denial: AgentGuardDenial) -> String {
        switch denial {
        case .readOnlyMode(let kind): return kind.rawValue
        case .policyDenied(let findings): return findings.map(\.rawValue).joined(separator: " ")
        }
    }
}
