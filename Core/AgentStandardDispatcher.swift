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

    /// 取一个**字符串数组**参数（`queries`）—— 数组不是标量，`parse` 会跳过它，所以单取这一条。
    /// 模型三种写法都收：`["a","b"]`、`"a b"`（单个字符串，交给调用方按空白拆）、
    /// 以及标量混进数组的 `["a", 1]`（非字符串项丢掉，不猜）。
    public static func strings(_ json: String, _ key: String) -> [String] {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = trimmed.isEmpty ? "{}" : trimmed
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = object[key] else { return [] }
        switch value {
        case let list as [String]: return list
        case let list as [Any]: return list.compactMap { $0 as? String }
        case let single as String: return [single]
        default: return []
        }
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
    /// MCP 桥（用户自配 server 的调用面，`FR-AI-21`；不给 ⇒ MCP 工具如实拒 `mcpNotConfigured`）。
    public var mcp: MCPClientCalling?
    /// 联网两件（`FR-AGT-TOOL-INGEST-001/004`）：搜索 / 抓取。配置与传输都在这里，视图不碰。
    public var web: AgentWebTools
    /// 只读 / 写审批的策略（`FR-AI-23` ⑥：只读模式下写类**连单都建不出来**）。
    public var guardPolicy: AgentGuardPolicy
    /// **同一条只读调用不许一轮里反复做**（提示词第 5 条的机械落地）。
    /// `nil` = 不装闸（既有测试与 CLI 那条路一字不变）。
    public var repeatGuard: AgentRepeatGuard?

    public init(registry: AgentToolRegistry = .standard,
                workspace: AgentWorkspaceTools? = nil,
                database: AgentDatabaseTool? = nil,
                commandRunner: AgentCommandRunner? = nil,
                mcp: MCPClientCalling? = nil,
                web: AgentWebTools = AgentWebTools(),
                guardPolicy: AgentGuardPolicy = AgentGuardPolicy(readOnly: false,
                                                                 requireApprovalForHighRisk: true,
                                                                 requireApprovalForWrites: true),
                repeatGuard: AgentRepeatGuard? = nil) {
        self.registry = registry
        self.web = web
        self.workspace = workspace
        self.database = database
        self.commandRunner = commandRunner
        self.mcp = mcp
        self.guardPolicy = guardPolicy
        self.repeatGuard = repeatGuard
    }

    /// **异步入口**（生产路径走这条）：`run_command` 要 await 真 shell 里的执行，
    /// 不能像文件类工具那样同步返回。其余能力原样落到同步 `dispatch`。
    ///
    /// 为什么必须有它：`dispatch` 是同步契约，循环那边原先把整段丢进 `Task.detached` 里跑；
    /// 再在**池线程**上 `semaphore.wait()` 等内层任务 ⇒ 池被自己堵住、内层永远起不来
    ///（2026-10-31 实测：命令一步都不执行，模型看着「已批准」一直重试）。

    /// 联网两件的执行面（详设 §3.27）：搜索只给命中，抓取只给正文。
    ///
    /// **失败要分清楚**：`notConfigured` / `unavailable(原因)` / `noResults` / 被边界拦下 ——
    /// 四句不同的话原样回到模型，绝不在这一层糊成「搜索失败」。
    private func dispatchWeb(_ capability: AgentToolCapability,
                             _ invocation: AgentToolInvocation) async -> AgentToolOutcome {
        guard let arguments = AgentToolArguments.parse(invocation.argumentsJSON) else {
            return .refused(.badArguments, detail: invocation.name)
        }
        switch capability {
        case .webSearch:
            let query = (arguments["query"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return .refused(.emptyQuery, detail: invocation.name) }
            let limit = Int(arguments["limit"] ?? "") ?? 5
            switch await web.search(query: query, limit: limit) {
            case .success(let hits):
                return .web(AgentWebOutput(kind: .search, query: query, hits: hits))
            case .failure(let failure):
                return .refused(.unavailable, detail: failure.message)
            }
        case .fetchURL:
            let url = (arguments["url"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !url.isEmpty else { return .refused(.badArguments, detail: invocation.name) }
            switch await web.fetch(urlString: url) {
            case .success(let page):
                return .web(AgentWebOutput(kind: .page,
                                           text: page.text,
                                           finalURL: page.finalURL.absoluteString,
                                           totalBytes: page.totalBytes,
                                           truncated: page.truncated))
            case .failure(let failure):
                return .refused(.unavailable, detail: failure.message)
            }
        default:
            return .refused(.unavailable, detail: invocation.name)
        }
    }

    public func dispatchAsync(_ invocation: AgentToolInvocation,
                              approvals: Set<String>) async -> AgentToolOutcome {
        let capability = registry.definition(named: invocation.name)?.capability
        // 联网是要等的（真发请求），和 `run_command` 一样先在这里分流；其余照旧走同步。
        if capability == .webSearch || capability == .fetchURL {
            return await dispatchWeb(capability!, invocation)
        }
        guard capability == .runCommand else {
            return dispatch(invocation, approvals: approvals)
        }
        // 执行类会改磁盘：之前那些「读过了」的账本作废（写完再看一眼是正当行为）。
        _ = repeatGuard?.admit(capability: .runCommand, tool: invocation.name,
                               arguments: invocation.argumentsJSON)
        let definition = registry.definition(named: invocation.name)
        guard let workspace, let commandRunner else {
            return .refused(.unavailable, detail: invocation.name)
        }
        guard let arguments = AgentToolArguments.parse(invocation.argumentsJSON) else {
            return .refused(.badArguments, detail: invocation.name)
        }
        let prepared = workspace.prepareCommand(arguments["command"] ?? "",
                                                tool: definition,
                                                guardPolicy: guardPolicy)
        guard case .needsApproval(let request) = prepared else { return prepared }
        guard approvals.contains(request.fingerprint) else { return prepared }
        return await workspace.runCommand(arguments["command"] ?? "",
                                          tool: definition,
                                          guardPolicy: guardPolicy,
                                          fingerprint: request.fingerprint,
                                          granted: approvals,
                                          runner: commandRunner)
    }

    public func dispatch(_ invocation: AgentToolInvocation, approvals: Set<String>) -> AgentToolOutcome {
        guard let definition = registry.definition(named: invocation.name) else {
            return .refused(.unregistered, detail: invocation.name)
        }
        guard let arguments = AgentToolArguments.parse(invocation.argumentsJSON) else {
            return .refused(.badArguments, detail: invocation.name)
        }

        // **同一轮里同一条只读调用反复做**（真机：一个文件被读 18 次）：
        // 第 3 次开始不执行，回一句能照做的话（账本按 (工具, 参数) 记，写 / 执行会清账）。
        if let repeatGuard,
           let denial = repeatGuard.admit(capability: definition.capability,
                                          tool: invocation.name,
                                          arguments: invocation.argumentsJSON) {
            return .refused(.unavailable, detail: denial)
        }

        switch definition.capability {
        case .webSearch, .fetchURL:
            // 联网必须走 `dispatchAsync`（要等网络）；同步入口遇到就当没接上，如实说。
            return .refused(.unavailable, detail: "联网工具需要异步入口")
        case .readFile:
            guard let workspace else { return .refused(.unavailable, detail: definition.capability.rawValue) }
            let path = arguments["path"] ?? ""
            // **按行开窗**（`offset` 0 起 / `limit` 行数）：长文件读指定段，不必整篇重读。
            let offset = AgentToolArguments.int(arguments, "offset")
            let limit = AgentToolArguments.int(arguments, "limit")
            // 工作区内直接读；越界会回一张单（§3.26）—— 批了就带指纹再读一次。
            let read = workspace.readFile(path: path, offset: offset, limit: limit)
            guard case .needsApproval(let request) = read else { return read }
            guard approvals.contains(request.fingerprint) else { return read }
            return workspace.readFile(path: path, offset: offset, limit: limit,
                                      fingerprint: request.fingerprint, granted: approvals)

        case .listDirectory:
            guard let workspace else { return .refused(.unavailable, detail: definition.capability.rawValue) }
            let path = arguments["path"] ?? "."
            let listing = workspace.listDirectory(path: path)
            guard case .needsApproval(let request) = listing else { return listing }
            guard approvals.contains(request.fingerprint) else { return listing }
            return workspace.listDirectory(path: path, fingerprint: request.fingerprint, granted: approvals)

        case .search:
            guard let workspace else { return .refused(.unavailable, detail: definition.capability.rawValue) }
            let limit = AgentToolArguments.int(arguments, "limit") ?? 50
            // **一次给多个词**（`queries` 数组，2026-11-07）：一次调用拿到每个词各自的命中，
            // 模型就不用「一个词一次」地反复扇扫。
            let queries = AgentToolArguments.strings(invocation.argumentsJSON, "queries")
            if !queries.isEmpty { return workspace.search(queries: queries, limit: limit) }
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
            // `dispatch` 是**同步**契约（循环那边把它整段丢进 `Task.detached` 跑），
            // 而执行器自 2026-10-31 起是 async（命令要能进真 shell 里跑、不能钉住主 actor）。
            // 这里就地桥一次：**只允许在非主线程等**（主线程等会与 PTY 的回收互相卡死）。
            guard !Thread.isMainThread else {
                // 主线程上等会与 PTY 的回收互相卡死（Core 不认识宿主的日志设施，这里只用返回值说）。
                return .refused(.unavailable, detail: "runCommandOnMainThread")
            }
            let semaphore = DispatchSemaphore(value: 0)
            let box = OutcomeBox()
            let task = Task.detached(priority: .userInitiated) {
                let outcome = await workspace.runCommand(arguments["command"] ?? "",
                                                         tool: definition,
                                                         guardPolicy: guardPolicy,
                                                         fingerprint: request.fingerprint,
                                                         granted: approvals,
                                                         runner: commandRunner)
                box.set(outcome)
                semaphore.signal()
            }
            _ = task
            semaphore.wait()
            return box.get() ?? .refused(.unavailable, detail: "runCommandNoResult")

        case .queryDatabase:
            guard let database else { return .refused(.unavailable, detail: definition.capability.rawValue) }
            return database.run(sql: arguments["sql"] ?? "")

        case .readNotes, .fetchURL:
            // 第二批：**登记在册但未启用** —— 如实拒，不假装能做。
            return .refused(.unregistered, detail: definition.capability.rawValue)

        case .dispatchSubtasks:
            // 派子代理是**异步**的（要真起子循环），由 `AgentLoop` 自己认领；
            // 走到分发器来说明调用方绕过了循环 —— 如实拒，不假装派过。
            return .refused(.unavailable, detail: "handled-by-loop")

        case .mcpTool:
            // **`FR-AI-21`**：用户自配 server 上的工具。三件事按顺序：
            // ① 桥没接 ⇒ 如实说「未配置」（不假回退到内置工具去"顶一下"）；
            // ② 工具级开关置「必须审批」⇒ **先出单**（工具名 + 参数原文），没批准不执行；
            // ③ 名字与参数**原样**交给远端（不改名、不补参），远端的错原样带回来。
            guard let mcp else { return .refused(.mcpNotConfigured, detail: definition.name) }
            if definition.approval == .required {
                // 指纹按**次**算：工具名 + 参数原文（换参数 ⇒ 换指纹 ⇒ 重新批，`FR-AI-23` ④ 同口径）。
                let fingerprint = AgentFingerprint.hash([
                    definition.name, invocation.argumentsJSON, definition.level.rawValue,
                ].joined(separator: "|"))
                let request = AgentApprovalRequest(toolName: definition.name,
                                                   fingerprint: fingerprint,
                                                   payload: "\(definition.name)\n\(invocation.argumentsJSON)",
                                                   // 远端工具的参数字形不受我们约束 ⇒ 作用域 = 参数原文摘要
                                                   // （同一串参数才算同一档）；工具名 / 参数里的
                                                   // 发送、凭据字样把危险面拉高到「只此一次」。
                                                   scope: AgentApprovalScope.argumentDigest(invocation.argumentsJSON),
                                                   hazard: AgentApprovalHazardRules.merged(
                                                       AgentApprovalHazardRules.text(definition.name),
                                                       AgentApprovalHazardRules.text(invocation.argumentsJSON)))
                guard approvals.contains(fingerprint) else { return .needsApproval(request) }
            }
            switch mcp.call(tool: definition.name, argumentsJSON: invocation.argumentsJSON) {
            case .result(let call):
                return .mcp(call)
            case .failure(let code, let detail):
                switch code {
                case "badArguments": return .refused(.badArguments, detail: "\(code)/\(detail)")
                case "unknownTool": return .refused(.unregistered, detail: "\(code)/\(detail)")
                case "notConnected": return .refused(.mcpNotConfigured, detail: "\(code)/\(detail)")
                default: return .refused(.mcpUnreachable, detail: "\(code)/\(detail)")
                }
            }
        }
    }
}


/// 跨线程交一次结果的盒子（`dispatch` 的同步桥用；只在「写一次 / 读一次」的时序下使用）。
private final class OutcomeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: AgentToolOutcome?
    func set(_ outcome: AgentToolOutcome) {
        lock.lock(); value = outcome; lock.unlock()
    }
    func get() -> AgentToolOutcome? {
        lock.lock(); defer { lock.unlock() }; return value
    }
}
