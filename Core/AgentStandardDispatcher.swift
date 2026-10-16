import Foundation

/// 工具参数的**取值**（纯函数）：从模型给的 JSON 里按声明取字符串 / 整数。
///
/// 与 `AgentToolSchemaValidator` 分工：那边判**合不合声明**，这边只**取值**（判过之后才走这里）。
public enum AgentToolArguments {

    /// 取不出来（不是对象 / 值类型不对）⇒ `nil`（调用点如实报 `badArguments`，不猜）。
    public static func parse(_ json: String) -> [String: String]? {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = trimmed.isEmpty ? "{}" : trimmed
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var result: [String: String] = [:]
        for (key, value) in object {
            switch value {
            case let string as String: result[key] = string
            case let number as Int: result[key] = String(number)
            case let number as Double: result[key] = String(Int(number))
            case let flag as Bool: result[key] = flag ? "true" : "false"
            default: continue
            }
        }
        return result
    }

    public static func int(_ arguments: [String: String], _ key: String) -> Int? {
        arguments[key].flatMap(Int.init)
    }
}

/// 标准分发器（`FR-AI-20` / `FR-AI-18` 的接头）：**按能力**把工具调用接到实现上。
///
/// 三条纪律：
/// - **按能力分发**，不认名字（名字只在注册表里出现一次 —— `FR-AI-19` 的源树判据守着）；
/// - **未登记 / 未启用的能力**（第二批那两件）⇒ 如实拒，不执行；
/// - 参数取不出来 ⇒ 如实拒（`badArguments`），**不猜**。
public struct AgentStandardDispatcher: AgentToolDispatcher {

    public var registry: AgentToolRegistry
    /// 工作区工具（`read_file` / `list_dir` / `search` / `write_file` / `run_command` 的实现）。
    public var workspace: AgentWorkspaceTools?
    /// 查库工具（`query_db` 的实现）。
    public var database: AgentDatabaseTool?
    /// 命令执行器（真起进程的那一侧在这里注入；不给 ⇒ 执行类如实拒）。
    public var commandRunner: AgentCommandRunner?
    /// 只读 / 写审批的策略（`FR-AI-23` ⑥：只读模式下写类**连单都建不出来**）。
    public var guardPolicy: AgentGuardPolicy

    public init(registry: AgentToolRegistry = .standard,
                workspace: AgentWorkspaceTools? = nil,
                database: AgentDatabaseTool? = nil,
                commandRunner: AgentCommandRunner? = nil,
                guardPolicy: AgentGuardPolicy = AgentGuardPolicy(readOnly: false,
                                                                 requireApprovalForHighRisk: true,
                                                                 requireApprovalForWrites: true)) {
        self.registry = registry
        self.workspace = workspace
        self.database = database
        self.commandRunner = commandRunner
        self.guardPolicy = guardPolicy
    }

    public func dispatch(_ invocation: AgentToolInvocation, approvals: Set<String>) -> AgentToolOutcome {
        guard let definition = registry.definition(named: invocation.name) else {
            return .refused(.unregistered, detail: invocation.name)
        }
        guard let arguments = AgentToolArguments.parse(invocation.argumentsJSON) else {
            return .refused(.badArguments, detail: invocation.name)
        }

        switch definition.capability {
        case .readFile:
            guard let workspace else { return .refused(.unavailable, detail: definition.capability.rawValue) }
            return workspace.readFile(path: arguments["path"] ?? "")

        case .listDirectory:
            guard let workspace else { return .refused(.unavailable, detail: definition.capability.rawValue) }
            return workspace.listDirectory(path: arguments["path"] ?? ".")

        case .search:
            guard let workspace else { return .refused(.unavailable, detail: definition.capability.rawValue) }
            let limit = AgentToolArguments.int(arguments, "limit") ?? 50
            return workspace.search(query: arguments["query"] ?? "", limit: limit)

        case .writeFile:
            guard let workspace else { return .refused(.unavailable, detail: definition.capability.rawValue) }
            // **先出单**（指纹由工具自己算 —— 不许这里另算一个，否则两边对不上、永远兑不了），
            // 再按单上的指纹看有没有批准。
            let prepared = workspace.prepareWrite(path: arguments["path"] ?? "",
                                                  content: arguments["content"] ?? "",
                                                  tool: definition,
                                                  guardPolicy: guardPolicy)
            guard case .needsApproval(let request) = prepared else { return prepared }
            guard approvals.contains(request.fingerprint) else { return prepared }
            return workspace.writeFile(path: arguments["path"] ?? "",
                                       content: arguments["content"] ?? "",
                                       tool: definition,
                                       guardPolicy: guardPolicy,
                                       fingerprint: request.fingerprint,
                                       granted: approvals)

        case .editFile:
            guard let workspace else { return .refused(.unavailable, detail: definition.capability.rawValue) }
            // 与 `writeFile` 同一口径：**先出单**（指纹由工具自己算），再按单上的指纹看有没有批准。
            let preparedEdit = workspace.prepareEdit(path: arguments["path"] ?? "",
                                                     oldString: arguments["old_string"] ?? "",
                                                     newString: arguments["new_string"] ?? "",
                                                     tool: definition,
                                                     guardPolicy: guardPolicy)
            guard case .needsApproval(let editRequest) = preparedEdit else { return preparedEdit }
            guard approvals.contains(editRequest.fingerprint) else { return preparedEdit }
            return workspace.editFile(path: arguments["path"] ?? "",
                                      oldString: arguments["old_string"] ?? "",
                                      newString: arguments["new_string"] ?? "",
                                      tool: definition,
                                      guardPolicy: guardPolicy,
                                      fingerprint: editRequest.fingerprint,
                                      granted: approvals)

        case .runCommand:
            guard let workspace, let commandRunner else {
                return .refused(.unavailable, detail: definition.capability.rawValue)
            }
            let prepared = workspace.prepareCommand(arguments["command"] ?? "",
                                                    tool: definition,
                                                    guardPolicy: guardPolicy)
            guard case .needsApproval(let request) = prepared else { return prepared }
            guard approvals.contains(request.fingerprint) else { return prepared }
            return workspace.runCommand(arguments["command"] ?? "",
                                        tool: definition,
                                        guardPolicy: guardPolicy,
                                        fingerprint: request.fingerprint,
                                        granted: approvals,
                                        runner: commandRunner)

        case .queryDatabase:
            guard let database else { return .refused(.unavailable, detail: definition.capability.rawValue) }
            return database.run(sql: arguments["sql"] ?? "")

        case .readNotes, .fetchURL:
            // 第二批：**登记在册但未启用** —— 如实拒，不假装能做。
            return .refused(.unregistered, detail: definition.capability.rawValue)
        }
    }
}
