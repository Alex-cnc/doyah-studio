import XCTest
@testable import DoyahCore
@testable import DoyahStudioApp

/// `FR-AGT-LINK-EXT-001` / `-002` 的**真对端**判据：拿一个**第三方** MCP server（真进程、不是本仓写的
/// python 假 server）把 host 方向与「用户自配 server 面」的端到端跑一遍。
///
/// 为什么默认跳过：真对端要 `npx` 当场拉包（联网、几十秒、随上游版本变）—— 默认套件必须离线、
/// 可重复，把联网依赖塞进默认路径等于让每个开发者天天红。**跳过 ≠ 通过**：没有这一族读数时，
/// 这两条需求只算「桩件通过」，不算「真对端通过」（判据要什么，`DOYAH_MCP_REAL_*` 三条环境变量说了算）：
///
/// ```
/// DOYAH_MCP_REAL_SERVER='npx -y @cloudbase/cloudbase-mcp@latest'      # 必给，空格分隔
/// DOYAH_MCP_REAL_TOOL='searchKnowledgeBase'                            # 可选，默认这条
/// DOYAH_MCP_REAL_ARGS='{"query":"数据库","mode":"docs","action":"searchDocs"}'  # 可选
/// DOYAH_MCP_REAL_EXPECT='CloudBase'                                     # 可选，结果里必须出现的原话
/// ```
///
/// 判据读的都是**对端回来的东西**（服务名 / 协议版本 / 工具名单 / 结果正文），不看本仓自述。
final class MCPRealServerTests: XCTestCase {

    // MARK: - 环境

    private func realServer() throws -> (command: String, args: [String]) {
        let raw = (ProcessInfo.processInfo.environment["DOYAH_MCP_REAL_SERVER"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        try XCTSkipIf(raw.isEmpty,
                      "未给 DOYAH_MCP_REAL_SERVER：真对端这一族默认跳过（跳过 ≠ 通过）")
        var parts = raw.split(separator: " ").map(String.init)
        guard let command = parts.first else {
            throw XCTSkip("DOYAH_MCP_REAL_SERVER 为空")
        }
        parts.removeFirst()
        return (command, parts)
    }

    private func toolName() -> String {
        let raw = (ProcessInfo.processInfo.environment["DOYAH_MCP_REAL_TOOL"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? "searchKnowledgeBase" : raw
    }

    private func toolArguments() -> String {
        let raw = (ProcessInfo.processInfo.environment["DOYAH_MCP_REAL_ARGS"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? #"{"query":"数据库","mode":"docs","action":"searchDocs"}"# : raw
    }

    private func bridge(for config: MCPClientServerConfig) -> MCPClientBridge {
        MCPClientBridge(configuration: MCPClientConfiguration(servers: [config]),
                        inheritedEnvironment: ProcessInfo.processInfo.environment) { _, plan in
            MCPStdioTransport(plan: plan)
        }
    }

    // MARK: - ① 握手 → 列工具（真进程、第三方 server）

    func testRealServerHandshakeAndToolList() throws {
        let server = try realServer()
        let config = MCPClientServerConfig(name: "third-party",
                                           command: server.command,
                                           args: server.args,
                                           timeoutSeconds: 120)
        let bridge = bridge(for: config)
        defer { bridge.shutdown() }

        let reports = bridge.discover()
        XCTAssertEqual(reports.count, 1)
        guard case .connected(let serverName, let protocolVersion, let tools) = reports[0].state else {
            return XCTFail("真对端没连上：\(reports[0].state)（detail=\(reports[0].state.detail)）")
        }
        XCTAssertFalse(serverName.isEmpty, "服务名来自对端 initialize 回包，不能是空串")
        XCTAssertFalse(protocolVersion.isEmpty, "协议版本来自对端 initialize 回包")
        XCTAssertGreaterThanOrEqual(tools.count, 5, "第三方 server 的工具名单要真的列出来：\(tools.count)")
        XCTAssertTrue(tools.allSatisfy { !$0.name.isEmpty }, "工具名原样，不许凭空捏")
        print("READING real-server=\(serverName) protocol=\(protocolVersion) tools=\(tools.count) "
              + "names=\(tools.prefix(6).map(\.name).joined(separator: ","))")
    }

    // MARK: - ② 调用 → 取结果（真对端回的正文，不是桩）

    func testRealServerToolCallReturnsPayload() throws {
        let server = try realServer()
        let config = MCPClientServerConfig(name: "third-party",
                                           command: server.command,
                                           args: server.args,
                                           timeoutSeconds: 120)
        let bridge = bridge(for: config)
        defer { bridge.shutdown() }

        let reports = bridge.discover()
        guard case .connected = reports[0].state else {
            return XCTFail("真对端没连上：\(reports[0].state)")
        }

        let name = toolName()
        let outcome = bridge.call(tool: name, argumentsJSON: toolArguments())
        guard case .result(let call) = outcome else {
            if case .failure(let code, let detail) = outcome {
                return XCTFail("真对端调用失败：\(code) \(detail)")
            }
            return XCTFail("真对端调用没有结果")
        }
        XCTAssertEqual(call.tool, name)
        XCTAssertFalse(call.isError, "对端回了 error：\(call.text.prefix(400))")
        XCTAssertFalse(call.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       "对端结果正文不能是空串")
        if let expect = ProcessInfo.processInfo.environment["DOYAH_MCP_REAL_EXPECT"], !expect.isEmpty {
            XCTAssertTrue(call.text.contains(expect),
                          "结果里应出现对端原话 `\(expect)`：\(call.text.prefix(400))")
        }
        print("READING real-server-call tool=\(name) bytes=\(call.text.utf8.count) "
              + "head=\(call.text.prefix(160).replacingOccurrences(of: "\n", with: " "))")
    }

    // MARK: - ③ 用户自配面：盘上那份 JSON 里的命令 / 参数原样起进程

    func testRealServerConfiguredThroughUserJSON() throws {
        let server = try realServer()
        let json: [String: Any] = [
            "servers": [[
                "name": "third-party",
                "transport": "stdio",
                "command": server.command,
                "args": server.args,
                "enabled": true,
                "timeoutSeconds": 120,
            ]],
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let configuration: MCPClientConfiguration
        switch MCPClientConfiguration.decode(data) {
        case .success(let decoded): configuration = decoded
        case .failure(let error): return XCTFail("用户这份配置读不出来：\(error.detail)")
        }
        let config = configuration.servers[0]
        // 「原样生效」：不经过 shell、不改写、不重排。
        XCTAssertEqual(config.command, server.command)
        XCTAssertEqual(config.args, server.args)

        let bridge = MCPClientBridge(configuration: configuration,
                                     inheritedEnvironment: ProcessInfo.processInfo.environment) { _, plan in
            MCPStdioTransport(plan: plan)
        }
        defer { bridge.shutdown() }
        let reports = bridge.discover()
        guard case .connected(let serverName, _, let tools) = reports[0].state else {
            return XCTFail("按用户配置没连上真对端：\(reports[0].state)")
        }
        XCTAssertFalse(tools.isEmpty)
        print("READING real-server-config server=\(serverName) tools=\(tools.count)")
    }
}
