import Foundation

/// **用户自配 MCP server 的配置面**（`FR-AI-21`）。
///
/// 三条纪律都是验收要点落到类型上的结果，不是风格偏好：
///
/// · **传输只认 `stdio`**（`FR-AI-21` ⑦：HTTP / SSE 与 OAuth 后置）。`transport = "http"` 的条目
///   **不是"悄悄不生效"**：校验给一条 `unsupportedTransport`，连接状态给 `unsupported` ——
///   用户看得见「这条现在不支持」，而不是配了没反应。
/// · **`enabled = false` 的 server 不发起任何连接**（③）。落到实现上：`plan(for:)` 对它返回 `nil`，
///   连进程计划都不生成 —— 想「起了进程再当没连」这种半截状态在本层就不可能存在。
/// · **命令 / 参数 / 环境变量原样生效**（②）。本层只做一件事：把**继承环境**与配置里的 `env`
///   合并（**配置胜**），不改写命令、不重排参数、不吞空串参数。
///
/// 这一层**不碰 I/O**：起进程在 `App/MCPStdioTransport.swift`（`Process` 在 watchOS 上没有，
/// 与 `AgentLocalCommandRunner` 同一条理由）。于是整个配置面可以离线单测。
public enum MCPClientTransportKind: String, Codable, Equatable, Sendable {
    case stdio
    case http
}

/// 工具级开关（`FR-AI-21` ④）：同一个 server 里，按工具分别决定「问不问人」。
///
/// 默认 = `automatic`（只读 server 优先、发现即用）；置 `approval` ⇒ 该调用**入队等审批**，
/// 未批准不执行；置 `disabled` ⇒ 该工具**不注入模型、也不可调用**（与"没发现"分开：
/// 状态里如实登记成一条被关掉的工具，不静默消失）。
public enum MCPClientToolPolicy: String, Codable, Equatable, Sendable {
    case automatic
    case approval
    case disabled
}

/// 一个用户自配的 MCP server（`FR-AI-21` 的配置面）。
///
/// 字段与需求原文一一对应：`name` / `transport` / `command` + `args` + `env` 或 `url` + `headers`
/// / `enabled` / 逐 server 工具级开关（`tools`）。
public struct MCPClientServerConfig: Codable, Equatable, Sendable {

    public var name: String
    public var transport: MCPClientTransportKind
    /// `stdio` 的启动命令（**原样**起，不经过 shell）。
    public var command: String
    /// 参数表（**原样**、**保序**；空串参数也照发 —— 那是用户写的，不是我们可以替他省的）。
    public var args: [String]
    /// 追加 / 覆盖的环境变量（在继承环境之上，**配置胜**）。
    public var env: [String: String]
    /// `http` 传输用（本档不支持，仍保留字段以免用户配置被静默丢弃）。
    public var url: String
    public var headers: [String: String]
    /// 关掉的 server **一个连接都不发起**（验收 ③）。
    public var enabled: Bool
    /// 单次往返的超时（秒）。0 或负 ⇒ 用默认值。
    public var timeoutSeconds: Double
    /// 工具级开关：远端工具名 → 策略（没登记的按 `automatic`）。
    public var tools: [String: MCPClientToolPolicy]

    public init(name: String,
                transport: MCPClientTransportKind = .stdio,
                command: String = "",
                args: [String] = [],
                env: [String: String] = [:],
                url: String = "",
                headers: [String: String] = [:],
                enabled: Bool = true,
                timeoutSeconds: Double = 20,
                tools: [String: MCPClientToolPolicy] = [:]) {
        self.name = name
        self.transport = transport
        self.command = command
        self.args = args
        self.env = env
        self.url = url
        self.headers = headers
        self.enabled = enabled
        self.timeoutSeconds = timeoutSeconds
        self.tools = tools
    }

    /// 解码缺项时**用默认值**，不整条失败 —— 手写配置少写一个 `enabled` 不该让整份配置读不出来。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        transport = try container.decodeIfPresent(MCPClientTransportKind.self, forKey: .transport) ?? .stdio
        command = try container.decodeIfPresent(String.self, forKey: .command) ?? ""
        args = try container.decodeIfPresent([String].self, forKey: .args) ?? []
        env = try container.decodeIfPresent([String: String].self, forKey: .env) ?? [:]
        url = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
        headers = try container.decodeIfPresent([String: String].self, forKey: .headers) ?? [:]
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        timeoutSeconds = try container.decodeIfPresent(Double.self, forKey: .timeoutSeconds) ?? 20
        tools = try container.decodeIfPresent([String: MCPClientToolPolicy].self, forKey: .tools) ?? [:]
    }
}

/// 配置面的一条毛病（**机器码 + 细节**；人话由界面那一侧给）。
///
/// 与 `AgentToolRefusal` 同族口径：Core 不写死人话，于是同一条毛病在中英两个界面里
/// 都说得准，而不是各写一半。
public enum MCPClientConfigProblem: Equatable, Sendable {

    case emptyName(index: Int)
    case duplicateName(index: Int, name: String)
    /// `stdio` 没写 command ⇒ 这条**不起进程**（"配了没反应"是被禁止的那种静默）。
    case stdioWithoutCommand(index: Int, name: String)
    /// 本档只支持 `stdio`（`FR-AI-21` ⑦）。
    case unsupportedTransport(index: Int, name: String, kind: MCPClientTransportKind)

    public var code: String {
        switch self {
        case .emptyName: return "emptyName"
        case .duplicateName: return "duplicateName"
        case .stdioWithoutCommand: return "stdioWithoutCommand"
        case .unsupportedTransport: return "unsupportedTransport"
        }
    }

    /// 细节串（**机器形态**：谁 / 哪个值）。
    public var detail: String {
        switch self {
        case .emptyName(let index): return "index:\(index)"
        case .duplicateName(let index, let name): return "\(index)/\(name)"
        case .stdioWithoutCommand(let index, let name): return "\(index)/\(name)"
        case .unsupportedTransport(let index, let name, let kind): return "\(index)/\(name)/\(kind.rawValue)"
        }
    }

    /// 出毛病的那一条在 `servers` 里的位置（按位置判「哪条不能起」，不按名字）。
    public var index: Int {
        switch self {
        case .emptyName(let index): return index
        case .duplicateName(let index, _): return index
        case .stdioWithoutCommand(let index, _): return index
        case .unsupportedTransport(let index, _, _): return index
        }
    }

    /// 这条毛病是否「整个 server 都不可用」。
    public var blocksServer: Bool {
        switch self {
        case .emptyName, .duplicateName, .stdioWithoutCommand, .unsupportedTransport:
            return true
        }
    }
}

/// 一次 `stdio` 起的进程计划（**纯数据**）：命令 / 参数 / 环境变量。
///
/// 「原样」在类型上就是原样 —— 没有 `shell`、没有引号处理、没有排序。
public struct MCPStdioPlan: Equatable, Sendable {

    public var executable: String
    public var arguments: [String]
    public var environment: [String: String]
    public var timeoutSeconds: Double

    public init(executable: String, arguments: [String], environment: [String: String], timeoutSeconds: Double) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.timeoutSeconds = timeoutSeconds
    }
}

/// 读配置时可能出的错（**整份**读不出来，与"某条不合规"分开）。
public enum MCPClientConfigurationError: Error, Equatable, Sendable {
    case malformed(String)
    case missing(String)

    public var detail: String {
        switch self {
        case .malformed(let detail): return detail
        case .missing(let path): return path
        }
    }
}

/// 整份配置：`servers` 列表 + 校验 + 进程计划 + 工具策略取值。
///
/// 顶层 JSON 既认 `{"servers": [...]}` 也认裸数组（用户手写时两种都常见）。
public struct MCPClientConfiguration: Equatable, Sendable {

    public var servers: [MCPClientServerConfig]

    public init(servers: [MCPClientServerConfig] = []) {
        self.servers = servers
    }

    /// 默认配置文件位置：与其余本机数据同一处（`Application Support/DoyahStudio/`）。
    public static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("DoyahStudio", isDirectory: true)
            .appendingPathComponent("mcp-servers.json")
    }

    /// 从磁盘读（文件不存在 ⇒ `nil` = **没配置**，不是错误 —— 界面据此说「未配置」）。
    public static func load(from url: URL = MCPClientConfiguration.defaultFileURL)
        -> Result<MCPClientConfiguration?, MCPClientConfigurationError> {
        guard FileManager.default.fileExists(atPath: url.path) else { return .success(nil) }
        guard let data = try? Data(contentsOf: url) else {
            return .failure(.malformed(url.lastPathComponent))
        }
        return decode(data).map { Optional($0) }
    }

    /// 解析（**纯函数**：同字节同结果，不读盘）。
    public static func decode(_ data: Data) -> Result<MCPClientConfiguration, MCPClientConfigurationError> {
        guard let raw = try? JSONSerialization.jsonObject(with: data) else {
            return .failure(.malformed("notJSON"))
        }
        let items: [Any]
        if let array = raw as? [Any] {
            items = array
        } else if let object = raw as? [String: Any], let array = object["servers"] as? [Any] {
            items = array
        } else {
            return .failure(.malformed("missingServers"))
        }
        var servers: [MCPClientServerConfig] = []
        for item in items {
            guard let object = item as? [String: Any],
                  let itemData = try? JSONSerialization.data(withJSONObject: object),
                  let server = try? JSONDecoder().decode(MCPClientServerConfig.self, from: itemData) else {
                return .failure(.malformed("serverShape"))
            }
            servers.append(server)
        }
        return .success(MCPClientConfiguration(servers: servers))
    }

    /// 编码成磁盘形态（写配置时用；**键序稳定**，便于人工 diff）。
    public func encoded() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(["servers": servers])
    }

    /// 校验：**每一条毛病都要点名**（不因为第一条就停 —— 用户一次改完比来回试快）。
    ///
    /// 每条毛病都带 `index`：判「哪一条不能起」必须按**位置**认，不能按名字认 ——
    /// 两个同名 server 的毛病相同，按名字判会把两条一起枪毙（用户改完一条仍连不上，很费解）。
    public var problems: [MCPClientConfigProblem] {
        var found: [MCPClientConfigProblem] = []
        var seen: Set<String> = []
        for (index, server) in servers.enumerated() {
            let trimmed = server.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                found.append(.emptyName(index: index))
                continue
            }
            if seen.contains(trimmed) {
                // 重名：**后来的**这条不能起（前一条照常连）—— 两条一起枪毙等于把好配置也废了。
                found.append(.duplicateName(index: index, name: trimmed))
                continue
            }
            seen.insert(trimmed)
            if server.transport == .http {
                found.append(.unsupportedTransport(index: index, name: trimmed, kind: .http))
                continue
            }
            if server.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                found.append(.stdioWithoutCommand(index: index, name: trimmed))
                continue
            }
        }
        return found
    }

    /// 这一条（按**位置**）能不能起（`nil` = 可以；否则是那条毛病）。
    public func blockingProblem(at index: Int) -> MCPClientConfigProblem? {
        problems.first { $0.index == index }
    }

    /// **要连的** server：`enabled` 且没有阻断性毛病。**关掉的一条都不在此列**（验收 ③）。
    public var connectableServers: [MCPClientServerConfig] {
        servers.enumerated()
            .filter { $0.element.enabled && blockingProblem(at: $0.offset) == nil }
            .map(\.element)
    }

    /// 工具级策略取值（没登记的按 `automatic`）。
    public func policy(server: String, tool: String) -> MCPClientToolPolicy {
        servers.first { $0.name == server }?.tools[tool] ?? .automatic
    }

    /// 起进程的计划。**关掉的 / 坏配置的 / 非 stdio 的一律 `nil`** —— 不生成计划就没有"悄悄起一下"。
    ///
    /// 环境变量 = 继承环境 ⊕ 配置 `env`（配置胜）。这是「原样生效」的唯一一处实现：
    /// 谁也别在调用点再拼一次环境变量。
    public func plan(for server: MCPClientServerConfig,
                     inheritedEnvironment: [String: String],
                     at index: Int? = nil) -> MCPStdioPlan? {
        // 位置给了就按位置判（同一份配置里两个同名 server 各算各的）；没给就按**第一次出现**判。
        let position = index ?? servers.firstIndex(of: server)
        if let position, blockingProblem(at: position) != nil { return nil }
        guard server.enabled, server.transport == .stdio else { return nil }
        var environment = inheritedEnvironment
        for (key, value) in server.env { environment[key] = value }
        let timeout = server.timeoutSeconds > 0 ? server.timeoutSeconds : 20
        return MCPStdioPlan(executable: server.command,
                            arguments: server.args,
                            environment: environment,
                            timeoutSeconds: timeout)
    }
}
