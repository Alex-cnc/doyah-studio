import XCTest
@testable import DoyahCore
@testable import DoyahStudioApp

/// `FR-AI-21`（MCP client · 用户自配 server 面）的机械判据 —— 照 SRS 七条验收要点逐条落。
///
/// 两半判据：
/// · **协议半**（`FakeMCPTransport`）：脚本化假 server，不起进程 —— 握手 / `tools/list` / `tools/call`
///   的顺序、名字与参数的**原样透传**、审批位、坏配置，都在这一半上可断言；
/// · **进程半**（`ProcessMCPTransport` 用真 `Process` 起一个 python 假 server）：命令 / 参数 / env
///   原样生效、命令不存在时**报错含原因** —— 这一半是「假 server 侧真的收到了什么」的判据。
final class MCPClientTests: XCTestCase {

    // MARK: - 假传输（脚本化 server）

    /// 一条假 server：不碰进程，按方法名回包；**记下每一条发给它的报文**（判据要断言"发出去的是什么"）。
    final class FakeMCPTransport: MCPClientTransport, @unchecked Sendable {

        private(set) var sent: [String] = []
        private var queue: [String] = []
        private(set) var opened = false
        private(set) var closed = false
        /// 起不来时用它（`spawnFailed`）。
        var openFailure: MCPTransportFailure?
        var tools: [[String: Any]] = [
            ["name": "echo_tool", "description": "echo back",
             "inputSchema": ["type": "object", "properties": ["text": ["type": "string"]], "required": ["text"]]],
        ]
        /// 收到 `tools/call` 就记一笔（判据断言"名字与参数原样"）。
        private(set) var calls: [(name: String, arguments: String)] = []

        func open() -> MCPTransportFailure? {
            if let openFailure { return openFailure }
            opened = true
            return nil
        }

        func send(_ line: String) -> MCPTransportFailure? {
            sent.append(line)
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .writeFailed("badFrame")
            }
            let id = object["id"] as? Int
            let method = object["method"] as? String ?? ""
            switch method {
            case "initialize":
                queue.append(envelope(id: id, result: ["protocolVersion": "2024-11-05",
                                                     "serverInfo": ["name": "fake-server", "version": "1"]]))
            case "tools/list":
                queue.append(envelope(id: id, result: ["tools": tools]))
            case "tools/call":
                let params = object["params"] as? [String: Any] ?? [:]
                let name = params["name"] as? String ?? ""
                let arguments = params["arguments"] ?? [:]
                let argumentsText = (try? JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys]))
                    .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                calls.append((name: name, arguments: argumentsText))
                queue.append(envelope(id: id, result: ["content": [["type": "text", "text": "echoed:\(name):\(argumentsText)"]]]))
            default:
                // 通知（`notifications/initialized`）**不回包** —— JSON-RPC 的通知本来就没有响应。
                break
            }
            return nil
        }

        func receive() -> Result<String, MCPTransportFailure> {
            guard !queue.isEmpty else { return .failure(.closed) }
            return .success(queue.removeFirst())
        }

        func close() { closed = true }

        private func envelope(id: Int?, result: [String: Any]) -> String {
            var object: [String: Any] = ["jsonrpc": "2.0", "result": result]
            if let id { object["id"] = id }
            let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
            return String(decoding: data, as: UTF8.self)
        }
    }

    /// 工厂记账（验收 ③ 的负例：`enabled = false` ⇒ 连工厂都不该被叫）。
    private final class TransportFactory: @unchecked Sendable {
        private(set) var plans: [MCPStdioPlan] = []
        private(set) var transports: [FakeMCPTransport] = []
        var failure: MCPTransportFailure?

        func make(plan: MCPStdioPlan) -> FakeMCPTransport {
            plans.append(plan)
            let transport = FakeMCPTransport()
            transport.openFailure = failure
            transports.append(transport)
            return transport
        }

        func transport(at index: Int) -> FakeMCPTransport { transports[index] }
    }

    private func bridge(_ servers: [MCPClientServerConfig],
                        factory: TransportFactory) -> MCPClientBridge {
        MCPClientBridge(configuration: MCPClientConfiguration(servers: servers),
                        inheritedEnvironment: ["PATH": "/usr/bin", "HOME": "/tmp"]) { _, plan in
            factory.make(plan: plan)
        }
    }

    // MARK: - ① 握手 → tools/list → tools/call → 名字与参数原样

    func testHandshakeListsToolsAndCallsWithNamesAndArgumentsUnchanged() {
        let factory = TransportFactory()
        let bridge = bridge([MCPClientServerConfig(name: "fake", command: "/usr/bin/env", args: ["fake"])],
                            factory: factory)
        let reports = bridge.discover()

        XCTAssertEqual(reports.count, 1)
        guard case .connected(let serverName, let version, let tools) = reports[0].state else {
            return XCTFail("应当连上，实际 = \(reports[0].state)")
        }
        XCTAssertEqual(serverName, "fake-server")
        XCTAssertEqual(version, "2024-11-05")
        XCTAssertEqual(tools.map(\.name), ["echo_tool"], "远端工具名**原样**")
        XCTAssertEqual(tools.first?.schemaJSON?.contains("\"text\"") , true, "远端 schema 原样留着")

        // 注入面：远端工具进了同一张注册表，名字一个字母都没改。
        let merged = AgentToolRegistry.standard.merging(bridge.discoveredDefinitions())
        XCTAssertTrue(merged.registry.isRegistered("echo_tool"))
        XCTAssertEqual(merged.registry.definition(named: "echo_tool")?.capability, .mcpTool)
        XCTAssertEqual(merged.conflicts, [])

        // 调用：名字与参数**原样**到对端（不改名、不补参、不裁字段）。
        let outcome = bridge.call(tool: "echo_tool", argumentsJSON: #"{"text":"你好","extra":1}"#)
        guard case .result(let call) = outcome else { return XCTFail("应当调用成功，实际 = \(outcome)") }
        XCTAssertEqual(call.server, "fake")
        XCTAssertEqual(call.tool, "echo_tool")
        XCTAssertTrue(call.text.contains("echoed:echo_tool"))
        XCTAssertFalse(call.isError)

        // 对端收到的 `tools/call` 里：`name` 原样、`arguments` 原样（连未知字段 `extra` 都在）。
        let transport = factory.transport(at: 0)
        XCTAssertEqual(transport.calls.count, 1)
        XCTAssertEqual(transport.calls[0].name, "echo_tool")
        XCTAssertTrue(transport.calls[0].arguments.contains("\"extra\":1"), "参数要原样透传：\(transport.calls[0].arguments)")
        XCTAssertTrue(transport.sent.contains { $0.contains("notifications/initialized") },
                      "握手的通知要发出去")
    }

    /// 结果**回灌进模型**（走循环那一侧）：循环把远端正文原样写进观察段。
    func testRemoteResultIsFedBackIntoTheModel() async {
        let factory = TransportFactory()
        let bridge = bridge([MCPClientServerConfig(name: "fake", command: "/usr/bin/env", args: ["fake"])],
                            factory: factory)
        bridge.discover()
        let merged = AgentToolRegistry.standard.merging(bridge.discoveredDefinitions())
        let dispatcher = AgentStandardDispatcher(registry: merged.registry, mcp: bridge)

        let client = ScriptedClient([
            [.toolCallDelta(index: 0, id: "c1", name: "echo_tool", argumentsFragment: #"{"text":"甲"}"#),
             .finished(reason: "tool_calls"), .done],
            [.textDelta("远端回了 echoed"), .finished(reason: "stop"), .done],
        ])
        let loop = AgentLoop(client: client, dispatcher: dispatcher, registry: merged.registry)
        let context = AgentLoopContext(systemPrompt: "s", userPrompt: "u",
                                       baseRequest: LLMRequest(endpoint: URL(string: "http://127.0.0.1:1/v1")!,
                                                               model: "fake", systemPrompt: "", userPrompt: ""),
                                       sessionID: "s-mcp", workspace: "ws")
        let result = await loop.run(context: context)

        XCTAssertEqual(result.outcome, .finished(text: "远端回了 echoed"))
        XCTAssertEqual(result.executedTools.map(\.name), ["echo_tool"])
        // 第 2 跳的请求里要带远端正文（回灌），而不是一句"已执行"。
        let second = client.requests[1].userPrompt
        XCTAssertTrue(second.contains("echoed:echo_tool"), "远端结果要原样回灌：\(second)")
        // 注入的 tools 里也要有它（条数 = 内置 7 + 远端 1）。
        XCTAssertEqual(client.requests[0].tools?.count, 8)
    }

    /// 脚本化假模型（与 `AgentLoopTests` 同形，本文件自带一份，避免跨文件耦合）。
    private final class ScriptedClient: LLMStreamingClient, @unchecked Sendable {
        private var hops: [[LLMStreamEvent]]
        private(set) var requests: [LLMRequest] = []

        init(_ hops: [[LLMStreamEvent]]) { self.hops = hops }

        func stream(_ request: LLMRequest) async throws -> AsyncThrowingStream<LLMStreamEvent, Error> {
            requests.append(request)
            let events = hops.isEmpty ? [.textDelta("（脚本用尽）"), .done] : hops.removeFirst()
            return AsyncThrowingStream { continuation in
                for event in events { continuation.yield(event) }
                continuation.finish()
            }
        }
    }

    // MARK: - ② 命令 / 参数 / env 原样（配置面）

    func testStdioPlanKeepsCommandArgumentsAndMergesEnvironment() {
        let server = MCPClientServerConfig(name: "fake",
                                           command: "/usr/bin/env",
                                           args: ["python3", "/tmp/a b.py", ""],
                                           env: ["MCP_TOKEN": "s3cr3t", "PATH": "/custom/bin"])
        let configuration = MCPClientConfiguration(servers: [server])
        guard let plan = configuration.plan(for: server, inheritedEnvironment: ["PATH": "/usr/bin", "HOME": "/tmp"]) else {
            return XCTFail("合法配置应当能出计划")
        }
        XCTAssertEqual(plan.executable, "/usr/bin/env")
        XCTAssertEqual(plan.arguments, ["python3", "/tmp/a b.py", ""], "参数原样、保序、空串也不省")
        XCTAssertEqual(plan.environment["HOME"], "/tmp", "继承环境要在")
        XCTAssertEqual(plan.environment["MCP_TOKEN"], "s3cr3t", "配置的 env 要生效")
        XCTAssertEqual(plan.environment["PATH"], "/custom/bin", "配置压过继承（同一键）")
    }

    // MARK: - ③ enabled = false ⇒ 不发起任何连接

    func testDisabledServerNeverOpensATransport() {
        let factory = TransportFactory()
        let bridge = bridge([MCPClientServerConfig(name: "off", command: "/usr/bin/env", args: ["x"], enabled: false)],
                            factory: factory)
        let reports = bridge.discover()

        XCTAssertEqual(factory.plans.count, 0, "关掉的 server **连进程计划都不该生成**")
        XCTAssertEqual(reports.first?.state, .disabled)
        XCTAssertEqual(bridge.summary, "connected:0/1")
        XCTAssertEqual(bridge.discoveredDefinitions(), [])
    }

    // MARK: - ④ 工具级开关「必须审批」⇒ 入队等审批，未批准不执行

    func testApprovalPolicyQueuesTheCallAndDoesNotExecuteWithoutApproval() {
        let factory = TransportFactory()
        let bridge = bridge([MCPClientServerConfig(name: "fake", command: "/usr/bin/env", args: ["fake"],
                                                  tools: ["echo_tool": .approval])],
                            factory: factory)
        bridge.discover()
        let merged = AgentToolRegistry.standard.merging(bridge.discoveredDefinitions())
        XCTAssertEqual(merged.registry.definition(named: "echo_tool")?.approval, .required)
        XCTAssertEqual(merged.registry.definition(named: "echo_tool")?.level, .executable)

        let dispatcher = AgentStandardDispatcher(registry: merged.registry, mcp: bridge)
        let invocation = AgentToolInvocation(name: "echo_tool", argumentsJSON: #"{"text":"甲"}"#)

        guard case .needsApproval(let request) = dispatcher.dispatch(invocation, approvals: []) else {
            return XCTFail("必须审批的工具在没批准时要出单")
        }
        XCTAssertEqual(request.toolName, "echo_tool")
        XCTAssertTrue(request.payload.contains("echo_tool"))
        XCTAssertEqual(factory.transport(at: 0).calls.count, 0, "未批准 ⇒ **一次都不许执行**")

        // 批准这一次 ⇒ 才真的调；换参数 ⇒ 换指纹（重新批，不许变成给工具开总开关）。
        guard case .mcp = dispatcher.dispatch(invocation, approvals: [request.fingerprint]) else {
            return XCTFail("批准后应执行")
        }
        XCTAssertEqual(factory.transport(at: 0).calls.count, 1)
        let other = AgentToolInvocation(name: "echo_tool", argumentsJSON: #"{"text":"乙"}"#)
        guard case .needsApproval = dispatcher.dispatch(other, approvals: [request.fingerprint]) else {
            return XCTFail("换参数要重新审批")
        }
    }

    /// 工具级开关置 `disabled` ⇒ 不注入、状态里如实记一条（不静默消失）。
    func testDisabledToolIsNotInjectedButCounted() {
        let factory = TransportFactory()
        let bridge = bridge([MCPClientServerConfig(name: "fake", command: "/usr/bin/env", args: ["fake"],
                                                  tools: ["echo_tool": .disabled])],
                            factory: factory)
        let reports = bridge.discover()
        XCTAssertEqual(bridge.discoveredDefinitions(), [], "关掉的工具不注入模型")
        XCTAssertTrue(reports[0].notes.contains("disabledTools:1"), "关掉几条要如实记：\(reports[0].notes)")
    }

    // MARK: - ⑤ 未配置 / 连不上 ⇒ 如实报

    func testUnconfiguredBridgeRefusesHonestly() {
        let bridge = MCPClientBridge(configuration: MCPClientConfiguration(), transportFactory: { _, plan in
            TransportFactory().make(plan: plan)
        })
        XCTAssertEqual(bridge.summary, "notConfigured")
        XCTAssertEqual(bridge.discover(), [])

        // 注册表里**有**这条远端声明、但桥没接上（宿主没注入）⇒ 必须报 `mcpNotConfigured`，
        // 不能退化成 `unregistered`（那会让用户以为"工具不存在"，实际是"没配 server"）。
        let definition = MCPClientBridge.definition(for: MCPClientRemoteTool(name: "echo_tool", description: "d"),
                                                    policy: .automatic)
        let registry = AgentToolRegistry.standard.merging([definition]).registry
        let dispatcher = AgentStandardDispatcher(registry: registry)
        let outcome = dispatcher.dispatch(AgentToolInvocation(name: "echo_tool", argumentsJSON: "{}"), approvals: [])
        guard case .refused(let code, _) = outcome else { return XCTFail("未配置要如实拒，实际 = \(outcome)") }
        XCTAssertEqual(code, .mcpNotConfigured)
    }

    func testUnreachableServerReportsTheReason() {
        let factory = TransportFactory()
        factory.failure = .spawnFailed("/nope/mcp-server: No such file or directory")
        let bridge = bridge([MCPClientServerConfig(name: "fake", command: "/nope/mcp-server")], factory: factory)
        let reports = bridge.discover()

        guard case .unreachable(let code, let detail) = reports[0].state else {
            return XCTFail("应当如实报连不上，实际 = \(reports[0].state)")
        }
        XCTAssertEqual(code, "spawnFailed")
        XCTAssertTrue(detail.contains("/nope/mcp-server"), "原因里要有那条命令：\(detail)")
        XCTAssertEqual(bridge.summary, "connected:0/1")
    }

    /// **真起进程**：命令不存在 ⇒ 报错含原因（判据不看客户端自述，看 `Process` 真的起不来）。
    func testMissingCommandFailsWithAReason() {
        let bridge = MCPClientBridge(configuration: MCPClientConfiguration(servers: [
            MCPClientServerConfig(name: "ghost", command: "/nonexistent/mcp-server-xyz", timeoutSeconds: 3),
        ]), inheritedEnvironment: ProcessInfo.processInfo.environment) { _, plan in
            MCPStdioTransport(plan: plan)
        }
        let reports = bridge.discover()
        guard case .unreachable(let code, let detail) = reports[0].state else {
            return XCTFail("命令不存在必须如实报，实际 = \(reports[0].state)")
        }
        XCTAssertEqual(code, "spawnFailed")
        XCTAssertTrue(detail.contains("mcp-server-xyz"))
    }

    // MARK: - 真进程跑通一条假 MCP server（命令 / 参数 / env 原样生效）

    func testRealProcessFakeServerRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcp-client-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let script = directory.appendingPathComponent("fake-mcp-server.py")
        try Self.fakeServerScript.write(to: script, atomically: true, encoding: .utf8)
        let log = directory.appendingPathComponent("env.log")

        let bridge = MCPClientBridge(configuration: MCPClientConfiguration(servers: [
            MCPClientServerConfig(name: "fake",
                                  command: "/usr/bin/env",
                                  args: ["python3", script.path],
                                  env: ["MCP_TEST_LOG": log.path, "MCP_TEST_TOKEN": "s3cr3t-token"],
                                  timeoutSeconds: 20),
        ]), inheritedEnvironment: ProcessInfo.processInfo.environment) { _, plan in
            MCPStdioTransport(plan: plan)
        }
        defer { bridge.shutdown() }

        let reports = bridge.discover()
        guard case .connected(let serverName, _, let tools) = reports[0].state else {
            return XCTFail("真进程没连上：\(reports[0].state)")
        }
        XCTAssertEqual(serverName, "fake-python-server")
        XCTAssertEqual(tools.map(\.name), ["echo_tool", "write_file"], "远端工具名原样（含与内置重名的那条）")

        // env 原样生效：假 server 把 `MCP_TEST_TOKEN` 写进文件（判据读文件，不看客户端自述）。
        let token = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        XCTAssertEqual(token.trimmingCharacters(in: .whitespacesAndNewlines), "s3cr3t-token")

        // 与内置工具重名的一条**不并进注册表**，但状态里如实记（不静默丢）。
        let merged = AgentToolRegistry.standard.merging(bridge.discoveredDefinitions())
        XCTAssertEqual(merged.conflicts, [], "桥已先挡下重名（说明记在 notes 里，见下一条断言）")
        XCTAssertEqual(merged.registry.definition(named: "write_file")?.capability, .writeFile,
                       "内置声明不许被远端顶掉")
        XCTAssertTrue(reports[0].notes.contains("nameConflict:write_file"))

        // 调用：真进程回包 → 名字与参数原样。
        guard case .result(let call) = bridge.call(tool: "echo_tool", argumentsJSON: #"{"text":"甲","n":2}"#) else {
            return XCTFail("真进程调用失败")
        }
        XCTAssertTrue(call.text.contains("echoed:echo_tool"), call.text)
        XCTAssertTrue(call.text.contains(#""n": 2"#), "参数原样：\(call.text)")
    }

    // MARK: - ⑥ 与 FR-AI-10 的 server 方向分条、互不代偿

    func testClientDirectionDoesNotTouchTheServerDirection() {
        XCTAssertEqual(AgentToolRegistry.standard.enabledDefinitions.count, 7,
                       "内置七件一条不多、一条不少（远端工具另算）")
        XCTAssertNil(AgentToolRegistry.standard.definition(named: "echo_tool"))
        XCTAssertEqual(MCPToolCatalog.all.map(\.name).sorted(),
                       ["describe_table", "export_result", "list_objects", "query_sql"],
                       "server 方向那四个工具与本条无关（`FR-AI-10` 的账）")
    }

    // MARK: - 注册表合并：远端工具不许顶掉内置名字

    func testMergingRefusesToShadowBuiltins() {
        let extra = AgentToolDefinition(name: "write_file", summary: "shadow", capability: .mcpTool,
                                        level: .readOnly, approval: .none)
        let merged = AgentToolRegistry.standard.merging([extra])
        XCTAssertEqual(merged.conflicts, ["write_file"])
        XCTAssertEqual(merged.registry.definition(named: "write_file")?.capability, .writeFile,
                       "内置声明原样留着")
    }

    // MARK: - ⑦ HTTP / SSE 后置：如实登记，不静默

    func testHTTPTransportIsReportedAsUnsupported() {
        let factory = TransportFactory()
        let bridge = bridge([MCPClientServerConfig(name: "remote", transport: .http, url: "https://example.com/mcp")],
                            factory: factory)
        let reports = bridge.discover()
        guard case .unsupported(let code, _) = reports[0].state else {
            return XCTFail("http 应当如实报不支持，实际 = \(reports[0].state)")
        }
        XCTAssertEqual(code, "unsupportedTransport")
        XCTAssertEqual(factory.plans.count, 0, "不支持的传输不许起进程")
    }

    // MARK: - 坏配置：每一条都点名（不因为第一条就停）

    func testConfigurationProblemsAreAllReported() {
        let configuration = MCPClientConfiguration(servers: [
            MCPClientServerConfig(name: "", command: "/bin/echo"),
            MCPClientServerConfig(name: "dup", command: "/bin/echo"),
            MCPClientServerConfig(name: "dup", command: "/bin/echo"),
            MCPClientServerConfig(name: "noCommand"),
            MCPClientServerConfig(name: "web", transport: .http, url: "https://x"),
        ])
        XCTAssertEqual(configuration.problems.map(\.code),
                       ["emptyName", "duplicateName", "stdioWithoutCommand", "unsupportedTransport"])
        XCTAssertEqual(configuration.connectableServers.map(\.name), ["dup"], "第一条 dup 是好配置")
    }

    /// 配置文件解析：裸数组与 `{"servers": [...]}` 都认；坏 JSON 如实报。
    func testConfigurationDecodingAcceptsBothShapes() {
        let array = Data(#"[{"name":"a","command":"/bin/echo"}]"#.utf8)
        XCTAssertEqual(try? MCPClientConfiguration.decode(array).get().servers.map(\.name), ["a"])

        let object = Data(#"{"servers":[{"name":"b","command":"/bin/echo","enabled":false}]}"#.utf8)
        XCTAssertEqual(try? MCPClientConfiguration.decode(object).get().servers.first?.enabled, false)

        let broken = Data("{".utf8)
        guard case .failure(let error) = MCPClientConfiguration.decode(broken) else {
            return XCTFail("坏 JSON 要如实报")
        }
        XCTAssertEqual(error.detail, "notJSON")
    }

    // MARK: - 假 server 源码（真进程那一半用）

    private static let fakeServerScript = #"""
    #!/usr/bin/env python3
    import json
    import os
    import sys

    token = os.environ.get("MCP_TEST_TOKEN", "")
    log = os.environ.get("MCP_TEST_LOG", "")
    if log:
        with open(log, "w") as handle:
            handle.write(token)

    def send(payload):
        sys.stdout.write(json.dumps(payload) + "\n")
        sys.stdout.flush()

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        message = json.loads(line)
        mid = message.get("id")
        method = message.get("method", "")
        if method == "initialize":
            send({"jsonrpc": "2.0", "id": mid,
                  "result": {"protocolVersion": "2024-11-05",
                             "serverInfo": {"name": "fake-python-server", "version": "1"}}})
        elif method == "notifications/initialized":
            pass
        elif method == "tools/list":
            send({"jsonrpc": "2.0", "id": mid,
                  "result": {"tools": [
                      {"name": "echo_tool", "description": "echo back",
                       "inputSchema": {"type": "object", "properties": {"text": {"type": "string"}}}},
                      {"name": "write_file", "description": "collides with a builtin",
                       "inputSchema": {"type": "object"}}]}})
        elif method == "tools/call":
            params = message.get("params") or {}
            arguments = json.dumps(params.get("arguments"), sort_keys=True)
            send({"jsonrpc": "2.0", "id": mid,
                  "result": {"content": [{"type": "text",
                                          "text": "echoed:" + str(params.get("name")) + ":" + arguments}]}})
        else:
            send({"jsonrpc": "2.0", "id": mid, "error": {"code": -32601, "message": "method not found"}})
    """#
}
