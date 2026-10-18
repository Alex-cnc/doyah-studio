import Foundation

/// **界面那一侧的「一条 server 的可编辑行」**（`FR-AI-21` 的界面片）。
///
/// 为什么这一层在 Core 而不是视图里：面板上真正会出错的不是布局，而是**文本 ↔ 配置**的换算 ——
/// 参数表与 `KEY=VALUE` 环境变量两段文本得变成「原样」的 `[String]` / `[String:String]`，
/// 而「原样」是 `FR-AI-21` ② 的验收要点。把它放进视图，就没法离线单测（面板要跑起来才验得了）；
/// 放进 Core，它就是一个纯函数：同字节同结果。
///
/// 四条刻意的口径（都是验收要点落到类型上的结果）：
///
/// · **参数一行一个，空白行丢掉**（`argsText` ⇄ `[String]`）。不按空格切 —— 按空格切就得处理
///   引号与转义，那是 shell 的活，而 `plan(for:)` 明说不经过 shell；按空格切反而会把
///   `--root=/Users/a b` 这类真的带空格的参数切碎。行内空格原样保留。
/// · **环境变量一行一个 `KEY=VALUE`，按第一个 `=` 切**（值里可以有 `=`，例如 base64 / URL 查询串）。
///   键去空白后不能为空；**坏行不静默吞掉**，按 1 起的行号登记成 `envLine:<行号>`（机器码），
///   面板据此点名「第 3 行没有 `=`」。
/// · **重名 / 空名 / 缺命令 / 非 stdio 一律不在这一层判**：`MCPClientConfiguration.problems`
///   是唯一出处（`FR-AI-19` 的「一处声明」纪律），草稿只把它转发出来 —— 两处各判一遍正是
///   那种「改了一处另一处照旧」的病根。
/// · **`tools` 逐工具开关原样带走**：草稿里没动过的工具策略必须原封不动写回文件，
///   否则用户在面板上改一个 server 的命令，会把他此前对工具做的「必须审批」悄悄抹掉。
public struct MCPClientServerDraft: Equatable, Sendable {

    public var name: String
    public var transport: MCPClientTransportKind
    public var command: String
    /// 一行一个参数（面板里那个多行输入框的原文）。
    public var argsText: String
    /// 一行一个 `KEY=VALUE`。
    public var envText: String
    public var url: String
    public var headers: [String: String]
    public var enabled: Bool
    public var timeoutSeconds: Double
    public var tools: [String: MCPClientToolPolicy]

    /// 新增一行（面板上「加一条 server」按下去就是它）：全空、默认启用、`stdio`。
    public init(name: String = "",
                transport: MCPClientTransportKind = .stdio,
                command: String = "",
                argsText: String = "",
                envText: String = "",
                url: String = "",
                headers: [String: String] = [:],
                enabled: Bool = true,
                timeoutSeconds: Double = 20,
                tools: [String: MCPClientToolPolicy] = [:]) {
        self.name = name
        self.transport = transport
        self.command = command
        self.argsText = argsText
        self.envText = envText
        self.url = url
        self.headers = headers
        self.enabled = enabled
        self.timeoutSeconds = timeoutSeconds
        self.tools = tools
    }

    /// 从配置文件里的一条读出来（**字段一个不丢**：`url` / `headers` / `timeoutSeconds` 也带走，
    /// 哪怕本档只支持 `stdio` —— 用户手写的配置不该因为面板存一次就被清空）。
    public init(config: MCPClientServerConfig) {
        self.name = config.name
        self.transport = config.transport
        self.command = config.command
        self.argsText = Self.argsText(from: config.args)
        self.envText = Self.envText(from: config.env)
        self.url = config.url
        self.headers = config.headers
        self.enabled = config.enabled
        self.timeoutSeconds = config.timeoutSeconds
        self.tools = config.tools
    }

    /// 草稿 → 配置（**这一步就是「原样」的兑现处**）。
    public var config: MCPClientServerConfig {
        MCPClientServerConfig(name: name,
                             transport: transport,
                             command: command,
                             args: Self.arguments(from: argsText),
                             env: Self.environment(from: envText).values,
                             url: url,
                             headers: headers,
                             enabled: enabled,
                             timeoutSeconds: timeoutSeconds,
                             tools: tools)
    }

    /// 环境变量文本里写坏的行（1 起；机器码形态，人话由界面给）。
    public var malformedEnvironmentLines: [Int] {
        Self.environment(from: envText).badLines
    }

    // MARK: - 文本 ⇄ 值

    /// 一行一个参数：**行内空格原样**，空白行丢掉，行尾 `\r` 去掉（Windows 粘贴过来的文本）。
    ///
    /// 切行用 `components(separatedBy:)` 而不是 `split(separator:)`：Swift 把 `\r\n` 当成
    /// **一个** Character，按字符切 `"\n"` 一行都切不开（实测踩过）—— 那是「看起来能跑、
    /// 实际整段当成一个参数」的静默错。
    public static func arguments(from text: String) -> [String] {
        text.components(separatedBy: "\n")
            .map { line -> String in
                var value = line
                if value.hasSuffix("\r") { value.removeLast() }
                return value
            }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// 参数表 → 文本（每行一个）。
    public static func argsText(from arguments: [String]) -> String {
        arguments.joined(separator: "\n")
    }

    /// 环境变量：按**第一个** `=` 切；键去空白后不能为空。
    ///
    /// 坏行（没有 `=` / 键为空）**不参与取值**，但**必须被点名** —— 静默丢掉一行环境变量，
    /// 症状是「明明配了却连不上」，最难查。
    public static func environment(from text: String) -> (values: [String: String], badLines: [Int]) {
        var values: [String: String] = [:]
        var badLines: [Int] = []
        for (offset, raw) in text.components(separatedBy: "\n").enumerated() {
            var line = raw
            if line.hasSuffix("\r") { line.removeLast() }
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            guard let separator = line.firstIndex(of: "=") else {
                badLines.append(offset + 1)
                continue
            }
            let key = String(line[line.startIndex..<separator]).trimmingCharacters(in: .whitespaces)
            if key.isEmpty {
                badLines.append(offset + 1)
                continue
            }
            // 值**不再 trim**：末尾空格可能就是用户要的（令牌 / 路径），我们没有资格替他省。
            values[key] = String(line[line.index(after: separator)...])
        }
        return (values, badLines)
    }

    /// 环境变量 → 文本（按键排序，便于人工 diff 与逐次保存结果一致）。
    public static func envText(from environment: [String: String]) -> String {
        environment.keys.sorted().map { "\($0)=\(environment[$0] ?? "")" }.joined(separator: "\n")
    }
}

/// **整份草稿**（面板上那一列 server）：加 / 删 / 逐工具开关 + 校验转发 + 落盘字节。
///
/// 位置纪律与 `MCPClientConfiguration.problems` 同一条：**按位置**认「哪一条不能起」，
/// 不按名字 —— 两个同名 server 各有各的位置，删掉一个不该把另一个的毛病一起带走。
public struct MCPClientConfigurationDraft: Equatable, Sendable {

    public var servers: [MCPClientServerDraft]

    public init(servers: [MCPClientServerDraft] = []) {
        self.servers = servers
    }

    public init(configuration: MCPClientConfiguration) {
        self.servers = configuration.servers.map(MCPClientServerDraft.init(config:))
    }

    /// 草稿 → 配置（校验与落盘都走这一份）。
    public var configuration: MCPClientConfiguration {
        MCPClientConfiguration(servers: servers.map(\.config))
    }

    /// 校验**转发**给唯一出处（`MCPClientConfiguration.problems`），不在这里重写一遍。
    public var problems: [MCPClientConfigProblem] {
        configuration.problems
    }

    /// 环境变量坏行（机器码 `envLine:<行号>`）—— 与上面那一族毛病**分开记**：
    /// 它是「这一行没读懂」，不等于「这个 server 起不来」（命令本身可能是对的）。
    public var environmentProblems: [String] {
        servers.enumerated().flatMap { index, server in
            server.malformedEnvironmentLines.map { "envLine:\(index):\($0)" }
        }
    }

    /// 这一条（按位置）的阻断性毛病（`nil` = 能起）。
    public func blockingProblem(at index: Int) -> MCPClientConfigProblem? {
        configuration.blockingProblem(at: index)
    }

    /// 加一条空行（返回它的位置；面板随即把光标给到名字框）。
    @discardableResult
    public mutating func addServer() -> Int {
        servers.append(MCPClientServerDraft())
        return servers.count - 1
    }

    /// 按位置删（越界是**无操作**，不崩：面板里连点两下删除不该让 App 挂掉）。
    public mutating func removeServer(at index: Int) {
        guard servers.indices.contains(index) else { return }
        servers.remove(at: index)
    }

    /// 逐工具开关的当前取值（没登记的按 `automatic`，与 `policy(server:tool:)` 同口径）。
    public func policy(server: String, tool: String) -> MCPClientToolPolicy {
        servers.first { $0.name == server }?.tools[tool] ?? .automatic
    }

    /// 改逐工具开关：只动**那一条** server 的那一个工具，别的原样。
    public mutating func setPolicy(_ policy: MCPClientToolPolicy, server: String, tool: String) {
        guard let index = servers.firstIndex(where: { $0.name == server }) else { return }
        servers[index].tools[tool] = policy
    }

    /// 落盘字节：与 `MCPClientConfiguration.encoded()` **同一处**（键序稳定、`servers` 顶层形状），
    /// 不另拼一份 JSON。
    public var encoded: Data? {
        configuration.encoded()
    }
}
