import Foundation

/// 一次 `tools/call` 的结果：**两半**（队列 L-66 ㈡，需求提出者 2026-09-28 拍板口径 ①）。
///
/// **为什么要一个类型而不是一个 `String`**：从前 `finish(_:text:isError:)` 收一个串，
/// 而那个串既进机器载荷（MCP 客户端 / 脚本）又打在用户眼前 —— **一份值两处消费**，
/// 于是「把失败说成人话」必然把机器载荷一起换成中文（可搜、可上报的口径就断了）。
/// 两半收在同一个值上之后，**取哪一半必须在渲染点显式写出来**（`.raw` / `.readable`），
/// 编译器与门禁都看得见。
public struct MCPToolResult: Equatable, Sendable {

    /// 机器那一半：**一字不变**的原始串（驱动 / 系统原话；可搜、可上报、口径稳定）。
    public let raw: String

    /// 人那一半：可读化入口渲染出来的人话（本机没有界面语境 ⇒ 简体中文）。
    public let readable: String

    public let isError: Bool

    public init(raw: String, readable: String, isError: Bool) {
        self.raw = raw
        self.readable = readable
        self.isError = isError
    }

    /// **本来就没有失败原串**的结果：成功载荷、以及「缺少参数」这类本地单语提示 ——
    /// 两半同一份内容，但这是**显式写出来的选择**，不是默认值。
    public static func single(_ text: String, isError: Bool = false) -> MCPToolResult {
        MCPToolResult(raw: text, readable: text, isError: isError)
    }
}

/// 我们**作为 MCP server** 的会话状态机（FR-AI-10 的 server 方向）。
///
/// 纯逻辑：给一行报文，回一行（或零行）报文 + 一条审计。**不读 stdin、不连数据库** ——
/// 真正的 I/O 与执行由调用方（CLI / 界面）注入，于是这一层可以离线测到每一条分支。
public struct MCPServerSession: Sendable {

    /// 当前会话能提供什么（由调用方从**当前连接**推导，不从外部请求里来 —— 这就是"继承当前会话"）。
    public struct Capabilities: Sendable {
        /// 当前是否有一个已连接的会话。
        public var hasConnection: Bool
        /// 当前连接是否只读。
        public var isReadOnly: Bool
        public var databaseType: DatabaseType
        /// 连接的自述（例如 `postgres@127.0.0.1:5432/analytics`）—— 只给"到哪儿去了"，不含口令。
        public var target: String
        /// **已获批的"具体调用"**（`MCPToolCatalog.callFingerprint`）——按次批准，不按工具名。
        /// 界面点过"这一次允许"就把这次调用的指纹放进来。
        public var approvedCalls: Set<String>

        public init(
            hasConnection: Bool,
            isReadOnly: Bool,
            databaseType: DatabaseType = .postgresql,
            target: String,
            approvedCalls: Set<String> = []
        ) {
            self.hasConnection = hasConnection
            self.isReadOnly = isReadOnly
            self.databaseType = databaseType
            self.target = target
            self.approvedCalls = approvedCalls
        }
    }

    /// 调用方要执行的一次工具调用（会话只**决定**，不执行）。
    public struct Invocation: Equatable, Sendable {
        public var tool: String
        public var arguments: MCPValue
        public var requestID: MCPMessage.MCPID?

        public init(tool: String, arguments: MCPValue, requestID: MCPMessage.MCPID?) {
            self.tool = tool
            self.arguments = arguments
            self.requestID = requestID
        }
    }

    public private(set) var isInitialized = false
    public private(set) var clientName = "unknown"
    public private(set) var audit: [MCPAuditEntry] = []
    public var capabilities: Capabilities

    /// 本会话说哪种语言（**由创建会话的调用方给定**，队列 L-65 第 3 批）。
    ///
    /// 为什么是会话属性而不是每个方法的形参：这几句话（`mcpInitialized` / `mcpToolNotExposed` /
    /// `mcpNoConnection` / 以及 `MCPToolCatalog.decision` 给出的拒绝理由）都挂在**同一次会话**上，
    /// 由同一个人启动（CLI 进程或界面）—— 语言是「谁在用这个 server」，不是「这一次调用」。
    /// 从前它在文件私有助手里被钉成简体中文 ⇒ 这些键的英文译文永远不可达。
    public let language: AppLanguage

    public init(capabilities: Capabilities, language: AppLanguage) {
        self.capabilities = capabilities
        self.language = language
    }

    /// 处理一行报文。返回：要写回去的报文（通知不必回）+ 需要调用方执行的调用（可能没有）。
    public struct Outcome: Sendable {
        public var replies: [MCPMessage]
        public var invocation: Invocation?
        public var error: String?
    }

    public mutating func handle(line: String) -> Outcome {
        switch MCPMessage.decode(line) {
        case .failure(let error):
            return Outcome(replies: [.error(id: nil, error: error)], invocation: nil, error: error.message)
        case .success(let message):
            return handle(message: message)
        }
    }

    public mutating func handle(message: MCPMessage) -> Outcome {
        switch message {
        case .request(let id, let method, let params):
            return handleRequest(id: id, method: method, params: params)
        case .notification(let method, let params):
            // `initialized`：对方确认握手完成。**不回包**（JSON-RPC 的通知不带 id）。
            if method == "notifications/initialized" || method == "initialized" {
                if let name = params["clientInfo"]?["name"]?.stringValue {
                    clientName = name
                }
            }
            return Outcome(replies: [], invocation: nil, error: nil)
        case .response, .error:
            // 我们是 server：收到响应型报文说明对端搞错了方向 —— 如实说，不要假装没收到。
            return Outcome(
                replies: [.error(id: nil, error: .invalidRequest)],
                invocation: nil,
                error: "unexpected response message"
            )
        }
    }

    private mutating func handleRequest(
        id: MCPMessage.MCPID,
        method: String,
        params: MCPValue
    ) -> Outcome {
        switch method {
        case "initialize":
            isInitialized = true
            if let name = params["clientInfo"]?["name"]?.stringValue {
                clientName = name
            }
            let requested = params["protocolVersion"]?.stringValue ?? "(none)"
            let result = MCPValue.object([
                "protocolVersion": .string(MCPProtocol.version),
                // 对方要的版本与我们不一致时**如实回报我们支持的版本**（协议要求由客户端决定是否继续）。
                "serverInfo": .object([
                    "name": .string("DoyahStudio"),
                    "version": .string("1.0"),
                ]),
                "capabilities": .object([
                    "tools": .object([:]),
                    "resources": .object([:]),
                    "experimental": .object([
                        "requestedProtocolVersion": .string(requested),
                    ]),
                ]),
                "instructions": .string(text(.mcpInitialized)),
            ])
            audit.append(
                MCPAuditEntry(
                    client: clientName,
                    tool: "initialize",
                    argumentsSummary: "protocol=\(requested)",
                    outcome: "ok"
                )
            )
            return Outcome(replies: [.response(id: id, result: result)], invocation: nil, error: nil)

        case "tools/list":
            let tools = MCPToolCatalog.all.map { $0.schemaJSON() }
            return Outcome(
                replies: [.response(id: id, result: .object(["tools": .array(tools)]))],
                invocation: nil,
                error: nil
            )

        case "resources/list":
            // 资源 = 当前会话的"目录"（连接自述 + 工具说明）。**不含口令**。
            let resources = MCPValue.array([
                .object([
                    "uri": .string("doyah://session"),
                    "name": .string("current-session"),
                    "description": .string(capabilities.target),
                    "mimeType": .string("application/json"),
                ])
            ])
            return Outcome(
                replies: [.response(id: id, result: .object(["resources": resources]))],
                invocation: nil,
                error: nil
            )

        case "ping":
            return Outcome(replies: [.response(id: id, result: .object([:]))], invocation: nil, error: nil)

        case "tools/call":
            return handleToolCall(id: id, params: params)

        default:
            return Outcome(
                replies: [.error(id: id, error: .methodNotFound)],
                invocation: nil,
                error: "method not found: \(method)"
            )
        }
    }

    private mutating func handleToolCall(id: MCPMessage.MCPID, params: MCPValue) -> Outcome {
        guard isInitialized else {
            // 没握手就调工具：协议上说不过去，如实拒（不假装成功）。
            return Outcome(
                replies: [.error(id: id, error: .invalidRequest)],
                invocation: nil,
                error: "tools/call before initialize"
            )
        }
        guard let name = params["name"]?.stringValue else {
            return Outcome(
                replies: [.error(id: id, error: .invalidParams("missing tool name"))],
                invocation: nil,
                error: "missing tool name"
            )
        }
        guard let tool = MCPToolCatalog.tool(named: name) else {
            let reason = text(.mcpToolNotExposed, name)
            audit.append(MCPAuditEntry(client: clientName, tool: name, argumentsSummary: "—", outcome: "not-exposed"))
            return Outcome(
                replies: [.response(id: id, result: errorContent(reason))],
                invocation: nil,
                error: reason
            )
        }

        let arguments = params["arguments"] ?? .object([:])
        let sql = arguments["sql"]?.stringValue

        // **没有会话就不要动**：外部调用一律不另开连接（"不另开特权"的第一层含义）。
        if !capabilities.hasConnection, tool.access != .metadata {
            let reason = text(.mcpNoConnection)
            audit.append(MCPAuditEntry(client: clientName, tool: name, argumentsSummary: "—", outcome: "no-session"))
            return Outcome(replies: [.response(id: id, result: errorContent(reason))], invocation: nil, error: reason)
        }

        let decision = MCPToolCatalog.decision(
            for: tool,
            sql: sql,
            databaseType: capabilities.databaseType,
            isReadOnlyConnection: capabilities.isReadOnly,
            isApproved: capabilities.approvedCalls.contains(
                MCPToolCatalog.callFingerprint(tool: name, arguments: arguments)
            ),
            language: language
        )
        switch decision {
        case .refused(let reason):
            audit.append(
                MCPAuditEntry(client: clientName, tool: name, argumentsSummary: summarize(arguments), outcome: "refused")
            )
            return Outcome(replies: [.response(id: id, result: errorContent(reason))], invocation: nil, error: reason)
        case .needsApproval(let reason):
            audit.append(
                MCPAuditEntry(client: clientName, tool: name, argumentsSummary: summarize(arguments), outcome: "needs-approval")
            )
            return Outcome(replies: [.response(id: id, result: errorContent(reason))], invocation: nil, error: reason)
        case .allowed(let access, _):
            audit.append(
                MCPAuditEntry(
                    client: clientName,
                    tool: name,
                    argumentsSummary: summarize(arguments),
                    outcome: "allowed(\(access.rawValue))"
                )
            )
            return Outcome(
                replies: [],
                invocation: Invocation(tool: name, arguments: arguments, requestID: id),
                error: nil
            )
        }
    }

    /// 调用方执行完（或失败）之后，把结果包成 MCP 的 `tools/call` 结果。
    ///
    /// **载荷两半**（队列 L-66 ㈡）：同一条 text 内容里放**两个字段** —— `text` 取
    /// `result.raw`（原串，**一字不变**）、`textHuman` 取 `result.readable`（人话，供 MCP
    /// 客户端**可选**展示）。从前这里只有一个串，「让人话上屏」就必然把机器载荷一起换成中文；
    /// 现在**取哪一半必须在这一行显式写出来**。
    public mutating func finish(_ invocation: Invocation, result: MCPToolResult) -> MCPMessage? {
        guard let id = invocation.requestID else { return nil }
        if result.isError {
            audit.append(
                MCPAuditEntry(client: clientName, tool: invocation.tool, argumentsSummary: "—", outcome: "failed")
            )
        }
        let content = textContent(raw: result.raw, human: result.readable, isError: result.isError)
        return .response(id: id, result: content)
    }

    /// 载荷形状只写一份：**原串 + 人话成对**（`text` / `textHuman`）。
    ///
    /// 为什么把形状收进一个私有 helper：客户端要在两种载荷形状之间写两套代码是不可接受的
    /// （拒绝、未暴露、无会话这些答复也走同一条），而「哪一半对哪个字段」写两遍就会漂。
    private func textContent(raw: String, human: String, isError: Bool) -> MCPValue {
        .object([
            "content": .array([
                .object([
                    "type": .string("text"),
                    "text": .string(raw),
                    "textHuman": .string(human),
                ])
            ]),
            "isError": .bool(isError),
        ])
    }

    /// 拒绝 / 未暴露 / 无会话这类**本来就没有失败原串**的答复：文案本身就是人话，
    /// 两半同一份内容 —— 仍然显式写出来（形状统一，客户端不必分情况）。
    private func errorContent(_ message: String) -> MCPValue {
        textContent(raw: message, human: message, isError: true)
    }

    private func summarize(_ arguments: MCPValue) -> String {
        // 审计里只留**参数摘要**：太长就截断（审计是给人看的，不是数据仓库）。
        let text = arguments.jsonText
        return text.count > 200 ? String(text.prefix(200)) + "…" : text
    }

    /// Core 侧文案（会话内使用；**语言取自会话属性 `language`**，由创建者给定，队列 L-65 第 3 批）。
    private func text(_ key: LKey, _ arguments: CVarArg...) -> String {
        if arguments.isEmpty {
            return LocalizedStrings.text(key, language: language)
        }
        return LocalizedStrings.format(key, language: language, arguments)
    }
}

/// 我们**作为 MCP host** 的会话状态机（FR-AI-10 的 host 方向）。
///
/// 只做到"握手 → 列工具 → 调工具 → 解析结果"这条最小闭环：多了会在没有真实 MCP 服务器的情况下
/// 变成一堆没验过的代码。外部服务器的**工具名与参数**原样透传（我们不做改名、不做参数补全），
/// 因为改名会让"同一个工具在两个客户端里名字不同"，那对互操作是负价值。
public struct MCPClientSession: Sendable {

    public struct RemoteTool: Equatable, Sendable {
        public var name: String
        public var description: String
    }

    public private(set) var isInitialized = false
    public private(set) var serverName = "unknown"
    public private(set) var protocolVersion = ""
    public private(set) var tools: [RemoteTool] = []
    public private(set) var lastResult: String?
    public private(set) var lastError: String?

    private var nextID = 1

    public init() {}

    /// 下一步该发什么（调用方写出去）。
    public mutating func initializeRequest() -> MCPMessage {
        let id = MCPMessage.MCPID.number(nextID)
        nextID += 1
        return .request(
            id: id,
            method: "initialize",
            params: .object([
                "protocolVersion": .string(MCPProtocol.version),
                "capabilities": .object([:]),
                "clientInfo": .object([
                    "name": .string("DoyahStudio"),
                    "version": .string("1.0"),
                ]),
            ])
        )
    }

    public mutating func toolsListRequest() -> MCPMessage {
        let id = MCPMessage.MCPID.number(nextID)
        nextID += 1
        return .request(id: id, method: "tools/list", params: .object([:]))
    }

    public mutating func toolsCallRequest(tool: String, arguments: MCPValue) -> MCPMessage {
        let id = MCPMessage.MCPID.number(nextID)
        nextID += 1
        return .request(
            id: id,
            method: "tools/call",
            params: .object(["name": .string(tool), "arguments": arguments])
        )
    }

    /// 收到一行（外部服务器的回复）后更新状态。
    @discardableResult
    public mutating func receive(line: String) -> Bool {
        switch MCPMessage.decode(line) {
        case .failure(let error):
            lastError = error.message
            return false
        case .success(let message):
            return receive(message: message)
        }
    }

    @discardableResult
    public mutating func receive(message: MCPMessage) -> Bool {
        switch message {
        case .error(_, let error):
            lastError = error.message
            return false
        case .response(_, let result):
            if let serverInfo = result["serverInfo"] {
                serverName = serverInfo["name"]?.stringValue ?? serverName
            }
            if let version = result["protocolVersion"]?.stringValue {
                protocolVersion = version
                isInitialized = true
            }
            if let list = result["tools"]?.arrayValue {
                tools = list.compactMap { item in
                    guard let name = item["name"]?.stringValue else { return nil }
                    return RemoteTool(name: name, description: item["description"]?.stringValue ?? "")
                }
            }
            // `tools/call` 的结果：把文本内容拼起来（图片等其它类型原样说明类型，不装作看不见）。
            if let content = result["content"]?.arrayValue {
                var parts: [String] = []
                for item in content {
                    if let textValue = item["text"]?.stringValue {
                        parts.append(textValue)
                    } else if let type = item["type"]?.stringValue {
                        parts.append("[\(type)]")
                    }
                }
                lastResult = parts.joined(separator: "\n")
            }
            if result["isError"]?.boolValue == true {
                lastError = lastResult
            }
            return true
        case .request, .notification:
            // 我们只是 host 的最小闭环：不处理服务器反向发起的请求。
            return false
        }
    }

    public func hasError() -> Bool { lastError != nil }
}
