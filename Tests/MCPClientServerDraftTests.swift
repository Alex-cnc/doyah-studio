import XCTest
@testable import DoyahCore

/// `FR-AI-21` 界面片（设置面板里加 / 删 / 开关 server + 逐工具开关）的**机械判据**。
///
/// 判的是「面板那句话存下去之后，配置文件里到底是什么」——
/// 也就是文本 ⇄ 配置的换算与位置纪律，全部离线可跑（不起进程、不碰界面）。
final class MCPClientServerDraftTests: XCTestCase {

    // MARK: - 字段原样

    func testDraftRoundTripsEveryField() {
        let original = MCPClientServerConfig(
            name: "filesystem",
            transport: .stdio,
            command: "/opt/homebrew/bin/mcp-fs",
            args: ["--root=/Users/alex/work space", "-v"],
            env: ["MCP_TOKEN": "a b=c", "DEBUG": "1"],
            url: "http://127.0.0.1:7777/mcp",
            headers: ["X-Trace": "on"],
            enabled: false,
            timeoutSeconds: 7.5,
            tools: ["read_file": .approval, "write_file": .disabled]
        )

        let draft = MCPClientServerDraft(config: original)

        XCTAssertEqual(draft.config, original, "草稿走一圈必须逐字段回到原样（含 url / headers / timeout / 逐工具开关）")
    }

    // MARK: - 参数文本

    func testArgumentsTextKeepsInteriorSpacesAndDropsBlankLines() {
        let text = """
        --root=/Users/alex/work space

          --flag value
        """
        XCTAssertEqual(MCPClientServerDraft.arguments(from: text),
                       ["--root=/Users/alex/work space", "  --flag value"],
                       "行内空格原样保留；空白行丢掉；不按空格切参数")
    }

    func testArgumentsTextToleratesCRLFAndTrailingNewline() {
        let text = "--a\r\n--b\r\n"
        XCTAssertEqual(MCPClientServerDraft.arguments(from: text), ["--a", "--b"],
                       "Windows 粘贴过来的行尾与结尾换行都不该多造一个空参数")
    }

    func testArgumentsTextRoundTripsThroughArray() {
        let arguments = ["one", "--two=2", "three words"]
        let text = MCPClientServerDraft.argsText(from: arguments)
        XCTAssertEqual(MCPClientServerDraft.arguments(from: text), arguments)
    }

    // MARK: - 环境变量文本

    func testEnvironmentSplitsAtFirstEquals() {
        let parsed = MCPClientServerDraft.environment(from: "URL=http://127.0.0.1:1/mcp?a=1\nTOKEN=abc")
        XCTAssertEqual(parsed.values, ["URL": "http://127.0.0.1:1/mcp?a=1", "TOKEN": "abc"],
                       "按第一个 = 切：值里可以有 =")
        XCTAssertEqual(parsed.badLines, [])
    }

    func testEnvironmentReportsBadLinesByOneBasedNumber() {
        let parsed = MCPClientServerDraft.environment(from: "OK=1\nno separator\n=missingKey\nTAIL=2")
        XCTAssertEqual(parsed.values, ["OK": "1", "TAIL": "2"], "坏行不参与取值")
        XCTAssertEqual(parsed.badLines, [2, 3], "坏行按 1 起的行号点名，且行号是原文行号（不是过滤后的序号）")
    }

    func testEnvironmentValueKeepsTrailingSpaces() {
        let parsed = MCPClientServerDraft.environment(from: "PATH=/opt/bin \n")
        XCTAssertEqual(parsed.values["PATH"], "/opt/bin ", "值不 trim —— 末尾空格可能是有意的")
    }

    func testEnvironmentTextIsSortedSoSavesAreStable() {
        let text = MCPClientServerDraft.envText(from: ["B": "2", "A": "1", "C": "3"])
        XCTAssertEqual(text, "A=1\nB=2\nC=3", "键序稳定 ⇒ 同样的配置每次存出来的字节一致，便于人工 diff")
    }

    func testEnvironmentRoundTripsThroughText() {
        let environment = ["A": "1", "B": "x=y", "C": ""]
        let text = MCPClientServerDraft.envText(from: environment)
        XCTAssertEqual(MCPClientServerDraft.environment(from: text).values, environment)
    }

    func testEnvironmentProblemsAreMachineCodesWithPosition() {
        var draft = MCPClientConfigurationDraft()
        let index = draft.addServer()
        draft.servers[index].name = "fs"
        draft.servers[index].command = "mcp-fs"
        draft.servers[index].envText = "OK=1\nbroken"
        XCTAssertEqual(draft.environmentProblems, ["envLine:0:2"])
        XCTAssertEqual(draft.problems, [], "坏一行环境变量 ≠ 这个 server 起不来（命令本身是对的）")
    }

    // MARK: - 满 / 空 / 删

    func testAddServerAppendsAnEmptyRowThatIsReportedAsEmptyName() {
        var draft = MCPClientConfigurationDraft()
        XCTAssertEqual(draft.servers.count, 0)
        let index = draft.addServer()
        XCTAssertEqual(index, 0)
        XCTAssertEqual(draft.problems.map(\.code), ["emptyName"], "新加的空行当场被点名（不静默）")
        XCTAssertEqual(draft.problems.first?.index, 0)
    }

    func testRemoveServerShiftsPositions() {
        var draft = MCPClientConfigurationDraft(servers: [
            MCPClientServerDraft(name: "", command: "a"),
            MCPClientServerDraft(name: "keep", command: "b"),
        ])
        draft.removeServer(at: 0)
        XCTAssertEqual(draft.servers.map(\.name), ["keep"])
        XCTAssertEqual(draft.problems, [], "删掉坏的那条之后剩下的就是干净的（毛病按位置重算）")
    }

    func testRemoveOutOfBoundsIsNoOp() {
        var draft = MCPClientConfigurationDraft(servers: [MCPClientServerDraft(name: "one", command: "a")])
        draft.removeServer(at: 5)
        XCTAssertEqual(draft.servers.map(\.name), ["one"])
    }

    // MARK: - 重名按位置判

    func testDuplicateNameBlocksOnlyTheLaterOne() {
        let draft = MCPClientConfigurationDraft(servers: [
            MCPClientServerDraft(name: "fs", command: "a"),
            MCPClientServerDraft(name: "fs", command: "b"),
        ])
        XCTAssertEqual(draft.problems.map(\.code), ["duplicateName"])
        XCTAssertEqual(draft.problems.first?.index, 1, "重名的毛病落**后来**那条的位置")
        XCTAssertEqual(draft.configuration.connectableServers.map(\.command), ["a"], "前一条照常连")
    }

    func testRemovingFirstOfTwoSameNamesUnblocksTheSecond() {
        var draft = MCPClientConfigurationDraft(servers: [
            MCPClientServerDraft(name: "fs", command: "a"),
            MCPClientServerDraft(name: "fs", command: "b"),
        ])
        draft.removeServer(at: 0)
        XCTAssertEqual(draft.problems, [])
        XCTAssertEqual(draft.configuration.connectableServers.map(\.command), ["b"],
                       "按位置判的兑现：删掉前一条，后一条立刻成为唯一的那条")
    }

    // MARK: - 逐工具开关

    func testToolPolicyDefaultsToAutomaticAndSetTouchesOnlyThatServer() {
        var draft = MCPClientConfigurationDraft(servers: [
            MCPClientServerDraft(name: "fs", command: "a"),
            MCPClientServerDraft(name: "git", command: "b"),
        ])
        XCTAssertEqual(draft.policy(server: "fs", tool: "read_file"), .automatic)
        draft.setPolicy(.approval, server: "fs", tool: "read_file")
        draft.setPolicy(.disabled, server: "git", tool: "commit")
        XCTAssertEqual(draft.policy(server: "fs", tool: "read_file"), .approval)
        XCTAssertEqual(draft.policy(server: "fs", tool: "commit"), .automatic, "别的 server 的开关不许串味")
        XCTAssertEqual(draft.policy(server: "git", tool: "commit"), .disabled)
        XCTAssertEqual(draft.configuration.servers[0].tools, ["read_file": .approval])
    }

    func testPolicyForUnknownServerIsNoOp() {
        var draft = MCPClientConfigurationDraft(servers: [MCPClientServerDraft(name: "fs", command: "a")])
        draft.setPolicy(.disabled, server: "nope", tool: "x")
        XCTAssertEqual(draft.servers[0].tools, [:])
    }

    // MARK: - 一处校验 · 一处落盘

    func testProblemsComeFromTheSingleSource() {
        let draft = MCPClientConfigurationDraft(servers: [
            MCPClientServerDraft(name: "", command: ""),
            MCPClientServerDraft(name: "http-one", transport: .http, command: "x"),
            MCPClientServerDraft(name: "no-command", command: "  "),
        ])
        XCTAssertEqual(draft.problems.map(\.code),
                       draft.configuration.problems.map(\.code),
                       "草稿不重写校验：同一份配置判出来的毛病必须逐条相同")
        XCTAssertEqual(Set(draft.problems.map(\.index)), [0, 1, 2], "三条毛病各自点名（不因为第一条就停）")
    }

    func testHTTPDraftKeepsItsFieldsAndReportsUnsupportedTransport() {
        let draft = MCPClientServerDraft(name: "remote-http", transport: .http, url: "https://example.com/mcp",
                                        headers: ["Authorization": "Bearer x"])
        XCTAssertEqual(draft.config.url, "https://example.com/mcp")
        XCTAssertEqual(draft.config.headers["Authorization"], "Bearer x")
        let configuration = MCPClientConfigurationDraft(servers: [draft]).configuration
        XCTAssertEqual(configuration.problems.map(\.code), ["unsupportedTransport"])
        XCTAssertEqual(configuration.connectableServers.count, 0)
    }

    func testEncodedDraftDecodesBackToSameConfiguration() {
        let draft = MCPClientConfigurationDraft(servers: [
            MCPClientServerDraft(name: "fs", command: "/bin/mcp-fs", argsText: "--root=/tmp\n-v",
                                 envText: "TOKEN=x=y"),
        ])
        guard let data = draft.encoded else { return XCTFail("编码失败") }
        switch MCPClientConfiguration.decode(data) {
        case .success(let decoded):
            XCTAssertEqual(decoded, draft.configuration)
            XCTAssertEqual(decoded.servers.first?.args, ["--root=/tmp", "-v"])
            XCTAssertEqual(decoded.servers.first?.env, ["TOKEN": "x=y"])
        case .failure(let error):
            XCTFail("落盘字节读不回来：\(error.detail)")
        }
    }
}
