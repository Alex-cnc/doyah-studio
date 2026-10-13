import XCTest
@testable import DoyahCore

/// 标准分发器（**按能力把工具调用接到实现上**）的机械判据 —— 以及「循环 + 真工具」的第一条端到端链。
final class AgentStandardDispatcherTests: XCTestCase {

    private var directory: URL!
    private var workspaceURL: URL!
    private var tools: AgentWorkspaceTools!

    private final class RecordingRunner: AgentCommandRunner, @unchecked Sendable {
        private(set) var executables: [String] = []
        func run(executable: String, arguments: [String], workingDirectory: URL) -> AgentCommandResult {
            executables.append(executable)
            return AgentCommandResult(exitCode: 0, standardOutput: "ok", standardError: "")
        }
    }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-dispatch-\(UUID().uuidString)", isDirectory: true)
        workspaceURL = directory.appendingPathComponent("ws", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        try "第一行\n第二行\n".write(to: workspaceURL.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        tools = AgentWorkspaceTools(root: workspaceURL)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func invocation(_ name: String, _ json: String) -> AgentToolInvocation {
        AgentToolInvocation(name: name, argumentsJSON: json, callID: "c1")
    }

    // MARK: - 按能力分发（名字只在注册表里出现）

    func testReadOnlyCapabilitiesDispatchToTheRealTools() {
        let dispatcher = AgentStandardDispatcher(workspace: tools)

        guard case .file(let file) = dispatcher.dispatch(invocation("read_file", #"{"path":"a.txt"}"#),
                                                        approvals: []) else {
            return XCTFail("read_file 该落到工作区读文件上")
        }
        XCTAssertTrue(file.text.contains("第一行"))

        guard case .directory(let dir) = dispatcher.dispatch(invocation("list_dir", #"{"path":"."}"#),
                                                            approvals: []) else {
            return XCTFail("list_dir 该落到列目录上")
        }
        XCTAssertTrue(dir.entries.contains { $0.contains("a.txt") })

        guard case .search = dispatcher.dispatch(invocation("search", #"{"query":"第二行"}"#),
                                                approvals: []) else {
            return XCTFail("search 该落到搜索上")
        }
    }

    // MARK: - 写：先出单，**没批准就不落盘**

    func testWriteDispatchesToApprovalThenToTheRealWrite() throws {
        let dispatcher = AgentStandardDispatcher(workspace: tools)
        let call = invocation("write_file", #"{"path":"b.txt","content":"新内容\n"}"#)

        guard case .needsApproval(let request) = dispatcher.dispatch(call, approvals: []) else {
            return XCTFail("没批准 ⇒ 该出单")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspaceURL.appendingPathComponent("b.txt").path),
                       "**没批准就不许落盘**")
        XCTAssertTrue(request.fingerprint.isEmpty == false)

        // 拿**单上的**指纹去兑现（不是另算一个）
        guard case .wrote = dispatcher.dispatch(call, approvals: [request.fingerprint]) else {
            return XCTFail("按单上的指纹批准 ⇒ 该真写")
        }
        XCTAssertEqual(try String(contentsOf: workspaceURL.appendingPathComponent("b.txt"), encoding: .utf8),
                       "新内容\n")

        // 换参数 ⇒ 另一张单 ⇒ 旧批准兑不了
        let other = invocation("write_file", #"{"path":"b.txt","content":"又改了\n"}"#)
        guard case .needsApproval = dispatcher.dispatch(other, approvals: [request.fingerprint]) else {
            return XCTFail("换了参数旧批准不算数")
        }
    }

    func testCommandDispatchNeedsApprovalAndUsesTheInjectedRunner() {
        let runner = RecordingRunner()
        let dispatcher = AgentStandardDispatcher(workspace: tools, commandRunner: runner)
        let call = invocation("run_command", #"{"command":"ls -a"}"#)

        guard case .needsApproval(let request) = dispatcher.dispatch(call, approvals: []) else {
            return XCTFail("执行类要审批")
        }
        XCTAssertTrue(runner.executables.isEmpty, "**没批准就不许起进程**")

        guard case .command(let result) = dispatcher.dispatch(call, approvals: [request.fingerprint]) else {
            return XCTFail("批准后该真跑")
        }
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(runner.executables, ["ls"])
    }

    // MARK: - 拒的四档：未登记 / 参数取不出 / 第二批 / 这一侧没接实现

    func testRefusalsAreHonestInFourShapes() {
        let dispatcher = AgentStandardDispatcher(workspace: tools)

        if case .refused(let code, _) = dispatcher.dispatch(invocation("delete_everything", "{}"), approvals: []) {
            XCTAssertEqual(code, .unregistered)
        } else { XCTFail("未登记的名字要拒") }

        if case .refused(let code, _) = dispatcher.dispatch(invocation("read_file", "不是 JSON"), approvals: []) {
            XCTAssertEqual(code, .badArguments, "参数取不出就如实拒，不猜")
        } else { XCTFail("参数坏了要拒") }

        // 第二批（登记在册但未启用）
        if case .refused(let code, _) = dispatcher.dispatch(invocation("read_notes", #"{"path":"x"}"#), approvals: []) {
            XCTAssertEqual(code, .unregistered)
        } else { XCTFail("未启用的能力要拒") }

        // 这一侧没注入实现
        let bare = AgentStandardDispatcher(workspace: nil)
        if case .refused(let code, _) = bare.dispatch(invocation("read_file", #"{"path":"a.txt"}"#), approvals: []) {
            XCTAssertEqual(code, .unavailable, "没接实现就如实说，不假装能做")
        } else { XCTFail("没实现要拒") }
    }

    // MARK: - 端到端：**循环 + 标准分发器 + 真工作区工具**（第一回不靠假分发器）

    func testLoopWithTheStandardDispatcherActuallyReadsAFile() async {
        final class ScriptedClient: LLMStreamingClient, @unchecked Sendable {
            var hops: [[LLMStreamEvent]]
            private(set) var prompts: [String] = []
            init(_ hops: [[LLMStreamEvent]]) { self.hops = hops }
            func stream(_ request: LLMRequest) async throws -> AsyncThrowingStream<LLMStreamEvent, Error> {
                prompts.append(request.userPrompt)
                let events = hops.isEmpty ? [.textDelta("（用尽）"), .done] : hops.removeFirst()
                return AsyncThrowingStream { continuation in
                    for event in events { continuation.yield(event) }
                    continuation.finish()
                }
            }
        }

        let client = ScriptedClient([
            [.toolCallDelta(index: 0, id: "c1", name: "read_file", argumentsFragment: #"{"path":"a.txt"}"#),
             .finished(reason: "tool_calls"), .done],
            [.textDelta("文件里有「第一行」"), .finished(reason: "stop"), .done],
        ])
        let loop = AgentLoop(client: client, dispatcher: AgentStandardDispatcher(workspace: tools))
        let context = AgentLoopContext(systemPrompt: "你是助手。", userPrompt: "读 a.txt",
                                       baseRequest: LLMRequest(endpoint: URL(string: "http://127.0.0.1:11434/v1")!,
                                                               model: "fake", systemPrompt: "", userPrompt: ""),
                                       sessionID: "s-e2e", workspace: workspaceURL.path)

        let result = await loop.run(context: context)

        XCTAssertEqual(result.outcome, .finished(text: "文件里有「第一行」"))
        XCTAssertEqual(result.executedTools.map(\.name), ["read_file"], "工具真的执行了（不是被拒）")
        XCTAssertTrue(client.prompts[1].contains("a.txt"), "回灌给模型的第二跳里带着工具结果")
    }
}
