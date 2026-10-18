import Foundation

/// 传输层失败（**机器码 + 细节**）：五种，都是「如实说，不假装」的形状。
///
/// 刻意不用「一句错误串」：界面要把「命令不存在」与「等服务超时」说成两句不同的话，
/// 而两者在用户那里要做的动作完全不同（前者改配置、后者重试）。
public enum MCPTransportFailure: Error, Equatable, Sendable {

    /// 起不来（命令不存在 / 没有执行权限 / 平台不支持）—— `detail` 里带系统原话。
    case spawnFailed(String)
    case writeFailed(String)
    /// 对端把管道关了（进程退出 / 崩了）。
    case closed
    /// 对端关掉管道**并且留了话**（stderr 尾巴）—— 与 `.closed` 分开：这条的原因在 `detail` 里，
    /// 用户要看到的就是它（`FR-AI-21` ⑤ 的负例：不存在的命令 / 脚本报错要含原因）。
    case exited(String)
    case timeout(seconds: Double)
    /// 对端回的不是一条能认的 JSON-RPC 报文。
    case protocolViolation(String)

    public var code: String {
        switch self {
        case .spawnFailed: return "spawnFailed"
        case .writeFailed: return "writeFailed"
        case .closed: return "closed"
        case .exited: return "exited"
        case .timeout: return "timeout"
        case .protocolViolation: return "protocolViolation"
        }
    }

    public var detail: String {
        switch self {
        case .spawnFailed(let detail): return detail
        case .writeFailed(let detail): return detail
        case .closed: return "eof"
        case .exited(let detail): return detail.isEmpty ? "eof" : detail
        case .timeout(let seconds): return "seconds:\(Int(seconds))"
        case .protocolViolation(let detail): return detail
        }
    }
}

/// 一行报文进、一行报文出（**同步**）。
///
/// 同步是刻意的：`AgentToolDispatcher.dispatch` 就是同步契约，传输层再包一层 async 只会
/// 在循环里多一次「主 actor 腾不出来」的机会（`FR-AI-20` 接线那条死锁教训）。
/// Core 只定协议；**真起进程**在 `App/MCPStdioTransport.swift`（`Process` 在 watchOS 上没有）。
public protocol MCPClientTransport: AnyObject {
    /// 起进程 / 建通道。`nil` = 成了。
    func open() -> MCPTransportFailure?
    func send(_ line: String) -> MCPTransportFailure?
    /// 读一行；对端关掉 / 超时都是**失败**（不是空串）。
    func receive() -> Result<String, MCPTransportFailure>
    func close()
}

/// 远端声明的一个工具（`tools/list` 的读数，**名字与 schema 原样留着**）。
public struct MCPClientRemoteTool: Equatable, Sendable {

    public var name: String
    public var description: String
    /// 远端给的 `inputSchema`（原样 JSON 文本；远端没给 ⇒ `nil`）。
    public var schemaJSON: String?

    public init(name: String, description: String, schemaJSON: String? = nil) {
        self.name = name
        self.description = description
        self.schemaJSON = schemaJSON
    }
}

/// 一个 server 的连接状态（**每一条配置都有状态**，包括关掉的与坏配置的 —— 不静默消失）。
public enum MCPClientServerState: Equatable, Sendable {
    /// `enabled = false`：**没有发起任何连接**（验收 ③）。
    case disabled
    /// 配置本身不成立（没名字 / 重名 / `stdio` 缺 command）。
    case notConnectable(code: String, detail: String)
    /// 本档不支持的传输（`http` / SSE，`FR-AI-21` ⑦）。
    case unsupported(code: String, detail: String)
    /// 起了但连不上 / 握手没过。
    case unreachable(code: String, detail: String)
    case connected(serverName: String, protocolVersion: String, tools: [MCPClientRemoteTool])

    public var code: String {
        switch self {
        case .disabled: return "disabled"
        case .notConnectable(let code, _): return code
        case .unsupported(let code, _): return code
        case .unreachable(let code, _): return code
        case .connected: return "connected"
        }
    }

    public var detail: String {
        switch self {
        case .disabled: return ""
        case .notConnectable(_, let detail): return detail
        case .unsupported(_, let detail): return detail
        case .unreachable(_, let detail): return detail
        case .connected(let name, let version, let tools):
            return "\(name)/\(version)/\(tools.count)"
        }
    }

    public var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

/// 一条 server 的完整报告（状态 + 追加说明）。
///
/// `notes` 是**机器码**列表：`disabledTools:n`（工具级关掉几条）/ `nameConflict:名字`（与内置工具重名，
/// 没并进注册表）。这些都不许静默 —— 用户关掉一个工具与"这个 server 没有那个工具"是两件事。
public struct MCPClientServerReport: Equatable, Sendable {

    public var name: String
    public var state: MCPClientServerState
    public var notes: [String]

    public init(name: String, state: MCPClientServerState, notes: [String] = []) {
        self.name = name
        self.state = state
        self.notes = notes
    }
}

/// 远端工具 → 注册表声明的一处绑定（`FR-AI-21` ①：名字**原样**）。
public struct MCPClientToolBinding: Equatable, Sendable {

    public var server: String
    public var remoteName: String
    public var policy: MCPClientToolPolicy
    public var definition: AgentToolDefinition

    public init(server: String, remoteName: String, policy: MCPClientToolPolicy, definition: AgentToolDefinition) {
        self.server = server
        self.remoteName = remoteName
        self.policy = policy
        self.definition = definition
    }
}

/// 一次远端工具调用的结局（**结果两半**：正文 + 是不是错误）。
public struct MCPClientToolCall: Equatable, Sendable {

    public var server: String
    public var tool: String
    /// 远端回的正文（`content[].text` 拼接；图片等非文本按 `[type]` 如实标出）。
    public var text: String
    public var isError: Bool

    public init(server: String, tool: String, text: String, isError: Bool) {
        self.server = server
        self.tool = tool
        self.text = text
        self.isError = isError
    }
}

public enum MCPClientCallOutcome: Equatable, Sendable {
    case result(MCPClientToolCall)
    /// 调用没成（机器码 + 细节）：`unknownTool` / `notConnected` / 传输层四种。
    case failure(code: String, detail: String)
}

/// 分发器看的那一侧（`AgentStandardDispatcher.mcp`）：**只认工具名**，认不出就如实说。
public protocol MCPClientCalling: Sendable {
    func call(tool name: String, argumentsJSON: String) -> MCPClientCallOutcome
}

/// **MCP client 桥**（`FR-AI-21`）：发现 → 登记 → 调用 → 结果交回。
///
/// 这一层只做**协议与判定**：
///
/// · **发现**（`discover`）：对每个 `enabled` 的 server 起一次进程，握手 → `notifications/initialized`
///   → `tools/list`；每个 server **都产出状态**（连上与连不上都记）。
/// · **登记**：远端工具进**同一张**注册表（`AgentToolRegistry.merging`）—— 名字原样、schema 原样、
///   等级 / 审批取自「工具级开关」；与内置工具重名的条目**不并**（写成 `nameConflict:<名>` 说明）。
/// · **调用**（`call`）：`tools/call` 的 `name` / `arguments` **原样**发出（不改名、不改形状）。
///
/// `enabled = false` 的 server 在 `discover` 里连进程计划都不生成 —— 本类型不提供"起了再说"的入口。
public final class MCPClientBridge: MCPClientCalling, @unchecked Sendable {

    private let configuration: MCPClientConfiguration
    private let inheritedEnvironment: [String: String]
    private let transportFactory: (MCPClientServerConfig, MCPStdioPlan) -> MCPClientTransport

    private let lock = NSLock()
    private var transports: [String: MCPClientTransport] = [:]
    private var sessions: [String: MCPClientSession] = [:]
    private var reportList: [MCPClientServerReport] = []
    private var bindingList: [MCPClientToolBinding] = []
    private var discovered = false

    public init(configuration: MCPClientConfiguration,
                inheritedEnvironment: [String: String] = [:],
                transportFactory: @escaping (MCPClientServerConfig, MCPStdioPlan) -> MCPClientTransport) {
        self.configuration = configuration
        self.inheritedEnvironment = inheritedEnvironment
        self.transportFactory = transportFactory
    }

    /// 配置里有没有 server（**关掉的也算配置过**；一条都没有 ⇒ 界面说「未配置」）。
    public var isConfigured: Bool { !configuration.servers.isEmpty }

    public var reports: [MCPClientServerReport] {
        lock.lock(); defer { lock.unlock() }
        return reportList
    }

    /// 汇总读数（机器码）：`notConfigured` / `connected:n/m`。
    public var summary: String {
        let list = reports
        if list.isEmpty { return "notConfigured" }
        let connected = list.filter { $0.state.isConnected }.count
        return "connected:\(connected)/\(list.count)"
    }

    public var bindings: [MCPClientToolBinding] {
        lock.lock(); defer { lock.unlock() }
        return bindingList
    }

    /// 发现全部 `enabled` 的 server。重复调用是幂等的（已连上的不重起进程）。
    @discardableResult
    public func discover() -> [MCPClientServerReport] {
        lock.lock()
        let already = discovered
        lock.unlock()
        if already { return reports }

        var newReports: [MCPClientServerReport] = []
        var newBindings: [MCPClientToolBinding] = []
        var usedNames = Set(AgentToolRegistry.standard.definitions.map(\.name))

        for (index, server) in configuration.servers.enumerated() {
            let name = server.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !server.enabled {
                // 验收 ③：**不生成计划、不起进程** —— 这里唯一允许做的事就是记一条状态。
                newReports.append(MCPClientServerReport(name: name, state: .disabled, notes: []))
                continue
            }
            if let problem = configuration.blockingProblem(at: index) {
                let state: MCPClientServerState = problem.code == "unsupportedTransport"
                    ? .unsupported(code: problem.code, detail: problem.detail)
                    : .notConnectable(code: problem.code, detail: problem.detail)
                newReports.append(MCPClientServerReport(name: name, state: state, notes: []))
                continue
            }
            guard let plan = configuration.plan(for: server, inheritedEnvironment: inheritedEnvironment, at: index) else {
                newReports.append(MCPClientServerReport(name: name,
                                                        state: .notConnectable(code: "stdioWithoutCommand", detail: name),
                                                        notes: []))
                continue
            }

            let transport = transportFactory(server, plan)
            if let failure = transport.open() {
                transport.close()
                newReports.append(MCPClientServerReport(name: name,
                                                        state: .unreachable(code: failure.code, detail: failure.detail),
                                                        notes: []))
                continue
            }

            var session = MCPClientSession()
            switch handshake(transport: transport, session: &session, timeout: plan.timeoutSeconds) {
            case .failure(let failure):
                transport.close()
                newReports.append(MCPClientServerReport(name: name,
                                                        state: .unreachable(code: failure.code, detail: failure.detail),
                                                        notes: []))
                continue
            case .success:
                break
            }

            let remoteTools = session.tools.map { remote -> MCPClientRemoteTool in
                MCPClientRemoteTool(name: remote.name, description: remote.description, schemaJSON: remote.schemaJSON)
            }
            var notes: [String] = []
            var disabledTools = 0
            for remote in remoteTools {
                let policy = configuration.policy(server: name, tool: remote.name)
                if policy == .disabled {
                    disabledTools += 1
                    continue
                }
                if usedNames.contains(remote.name) {
                    notes.append("nameConflict:\(remote.name)")
                    continue
                }
                usedNames.insert(remote.name)
                let definition = Self.definition(for: remote, policy: policy)
                newBindings.append(MCPClientToolBinding(server: name, remoteName: remote.name,
                                                        policy: policy, definition: definition))
            }
            if disabledTools > 0 { notes.append("disabledTools:\(disabledTools)") }

            lock.lock()
            transports[name] = transport
            sessions[name] = session
            lock.unlock()
            newReports.append(MCPClientServerReport(
                name: name,
                state: .connected(serverName: session.serverName,
                                  protocolVersion: session.protocolVersion,
                                  tools: remoteTools),
                notes: notes))
        }

        lock.lock()
        reportList = newReports
        bindingList = newBindings
        discovered = true
        lock.unlock()
        return newReports
    }

    /// 发现到的工具（交给 `AgentToolRegistry.merging`）。
    public func discoveredDefinitions() -> [AgentToolDefinition] {
        bindings.map(\.definition)
    }

    public func call(tool name: String, argumentsJSON: String) -> MCPClientCallOutcome {
        lock.lock()
        let binding = bindingList.first { $0.definition.name == name }
        let transport = binding.flatMap { transports[$0.server] }
        var session = binding.flatMap { sessions[$0.server] }
        lock.unlock()

        guard let binding else {
            return .failure(code: "unknownTool", detail: name)
        }
        guard let transport, var session else {
            return .failure(code: "notConnected", detail: binding.server)
        }

        // 参数**原样透传**：只把 JSON 文本解成一个值，不改键名、不补默认值、不裁字段。
        let trimmed = argumentsJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = trimmed.isEmpty ? "{}" : trimmed
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(code: "badArguments", detail: binding.remoteName)
        }
        let arguments = MCPValue(any: object)

        let request = session.toolsCallRequest(tool: binding.remoteName, arguments: arguments)
        switch exchange(transport: transport, session: &session, request: request, timeout: 20) {
        case .failure(let failure):
            lock.lock(); sessions[binding.server] = session; lock.unlock()
            return .failure(code: failure.code, detail: failure.detail)
        case .success:
            lock.lock(); sessions[binding.server] = session; lock.unlock()
            let body = session.lastResult ?? ""
            let isError = session.hasError()
            return .result(MCPClientToolCall(server: binding.server, tool: binding.remoteName,
                                             text: body, isError: isError))
        }
    }

    /// 收摊：把还开着的进程关掉（退出 App / 关对话时调）。
    public func shutdown() {
        lock.lock()
        let open = transports
        transports = [:]
        discovered = false
        lock.unlock()
        for transport in open.values { transport.close() }
    }

    // MARK: - 协议细节

    /// 握手三步：`initialize` → `notifications/initialized` → `tools/list`。
    private func handshake(transport: MCPClientTransport,
                           session: inout MCPClientSession,
                           timeout: Double) -> Result<Void, MCPTransportFailure> {
        switch exchange(transport: transport, session: &session,
                        request: session.initializeRequest(), timeout: timeout) {
        case .failure(let failure): return .failure(failure)
        case .success:
            break
        }
        guard session.isInitialized else {
            // 回了包但没带 `protocolVersion` ⇒ 握手不算成（不猜「大概握上了」）。
            return .failure(.protocolViolation("initializeWithoutProtocolVersion"))
        }
        // 通知：只写不读（JSON-RPC 的通知没有回复）。
        if let failure = transport.send(MCPMessage.notification(method: "notifications/initialized",
                                                               params: .object([:])).encode()) {
            return .failure(failure)
        }
        switch exchange(transport: transport, session: &session,
                        request: session.toolsListRequest(), timeout: timeout) {
        case .failure(let failure): return .failure(failure)
        case .success: return .success(())
        }
    }

    /// 发一条请求、等**它那一条**回复（跳过中间的通知 / 服务器反向请求）。
    private func exchange(transport: MCPClientTransport,
                          session: inout MCPClientSession,
                          request: MCPMessage,
                          timeout: Double) -> Result<MCPMessage, MCPTransportFailure> {
        let expected: MCPMessage.MCPID?
        if case .request(let id, _, _) = request { expected = id } else { expected = nil }
        if let failure = transport.send(request.encode()) { return .failure(failure) }

        // 有界：对端刷一堆通知时不许无限等（真服务器不会发超过几条无关报文）。
        for _ in 0..<16 {
            switch transport.receive() {
            case .failure(let failure):
                return .failure(failure)
            case .success(let line):
                switch MCPMessage.decode(line) {
                case .failure:
                    return .failure(.protocolViolation("undecodableLine"))
                case .success(let message):
                    switch message {
                    case .notification:
                        continue
                    case .request:
                        // 反向请求：本片只做 host 的最小闭环，不回包（也不假装看见了）。
                        continue
                    case .response(let id, _):
                        // 只认**这一条**回复（别的 id 是上一轮的迟到包，不当本次结果）。
                        if let expected, id != expected { continue }
                        _ = session.receive(message: message)
                        return .success(message)
                    case .error(let id, _):
                        if let expected, id != expected { continue }
                        _ = session.receive(message: message)
                        return .success(message)
                    }
                }
            }
        }
        return .failure(.protocolViolation("noMatchingResponse"))
    }

    /// 远端工具 → 注册表声明（名字 / schema 原样；等级按策略）。
    static func definition(for remote: MCPClientRemoteTool, policy: MCPClientToolPolicy) -> AgentToolDefinition {
        AgentToolDefinition(
            name: remote.name,
            summary: remote.description,
            capability: .mcpTool,
            parameters: [:],
            required: [],
            // 只读优先（`FR-AI-21` ⑦「只读 server 优先」）：默认当只读；
            // 用户要更强的保护就把工具级开关置 `approval` —— 那时等级抬到「可执行」（可写可跑的那一档，
            // 语义是「这一件会动世界」，于是审批链与写 / 跑命令同一条）。
            level: policy == .approval ? .executable : .readOnly,
            approval: policy == .approval ? .required : .none,
            enabled: true,
            schemaOverride: remote.schemaJSON,
            passesArgumentsThrough: true)
    }
}
