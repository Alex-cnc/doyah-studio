import XCTest
@testable import DoyahCore

/// **计划先获准 · 循环级接线**（`FR-AGT-PLAN-PLAN-007`）。
/// 状态机自己会拦不算数 —— 主循环里真的没把它放过去，才算落地。
final class AgentPlanModeLoopTests: XCTestCase {

    private final class OneCallClient: LLMStreamingClient, @unchecked Sendable {
        private let lock = NSLock()
        private var hops = 0
        private let name: String
        private let arguments: String
        init(name: String, arguments: String) { self.name = name; self.arguments = arguments }

        func stream(_ request: LLMRequest) async throws -> AsyncThrowingStream<LLMStreamEvent, Error> {
            lock.lock(); hops += 1; let hop = hops; lock.unlock()
            return AsyncThrowingStream { continuation in
                if hop == 1 {
                    continuation.yield(.toolCallDelta(index: 0, id: "c0", name: self.name, argumentsFragment: self.arguments))
                } else {
                    continuation.yield(.textDelta("收到。"))
                }
                continuation.yield(.done)
                continuation.finish()
            }
        }
    }

    private final class CountingDispatcher: AgentToolDispatcher, @unchecked Sendable {
        private let lock = NSLock()
        private(set) var dispatched: [String] = []
        func dispatch(_ invocation: AgentToolInvocation, approvals: Set<String>) -> AgentToolOutcome {
            lock.lock(); dispatched.append(invocation.name); lock.unlock()
            if invocation.name == "read_file" {
                return .file(AgentToolFileOutput(path: "a.txt", text: "内容", truncated: false, totalBytes: 6))
            }
            return .file(AgentToolFileOutput(path: invocation.name, text: "已写", truncated: false, totalBytes: 6))
        }
    }

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("plan-mode-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "x".write(to: directory.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func run(name: String, arguments: String, plan: AgentPlanState) async -> (AgentLoopResult, CountingDispatcher) {
        let dispatcher = CountingDispatcher()
        let loop = AgentLoop(client: OneCallClient(name: name, arguments: arguments), dispatcher: dispatcher,
                             sessionStore: AgentSessionStore(directory: directory))
        var context = AgentLoopContext(systemPrompt: "s", userPrompt: "干活",
                                       baseRequest: LLMRequest(endpoint: URL(string: "http://127.0.0.1:11434/v1")!,
                                                               model: "m", systemPrompt: "", userPrompt: ""),
                                       sessionID: UUID().uuidString, workspace: directory.path)
        context.planState = plan
        return (await loop.run(context: context), dispatcher)
    }

    /// 判据 ①：未批准的写操作在**主循环里**被拒，且没到分发器。
    func testUnapprovedWriteNeverReachesDispatcher() async {
        var plan = AgentPlanState()
        plan.submit("1. 读 a.txt\n2. 写 out.txt")
        let (result, dispatcher) = await run(name: "write_file",
                                             arguments: #"{"path":"out.txt","content":"hi"}"#, plan: plan)

        XCTAssertTrue(dispatcher.dispatched.isEmpty, "写类没批准就分发 = 判据 ① 形同没有")
        XCTAssertEqual(result.executedTools.count, 0)
        XCTAssertTrue(result.rejectedTools.contains { $0.name == "write_file" && $0.reason.hasPrefix("plan-awaiting-approval") },
                      "拒绝理由必须点名「等批准」，实际：\(result.rejectedTools)")
    }

    /// 判据 ①：只读在计划模式下照旧放行（探索与设计靠它）。
    func testReadStillWorksWhileAwaitingApproval() async {
        var plan = AgentPlanState()
        plan.submit("先读")
        let (result, dispatcher) = await run(name: "read_file", arguments: #"{"path":"a.txt"}"#, plan: plan)

        XCTAssertEqual(dispatcher.dispatched, ["read_file"], "只读必须照旧执行")
        XCTAssertEqual(result.executedTools.map(\.name), ["read_file"])
    }

    /// 判据 ②：批准之后同一个写操作放行。
    func testApprovedPlanLetsTheWriteThrough() async {
        var plan = AgentPlanState()
        plan.submit("1. 读 a.txt\n2. 写 out.txt")
        plan.approve()
        let (result, dispatcher) = await run(name: "write_file",
                                             arguments: #"{"path":"out.txt","content":"hi"}"#, plan: plan)

        XCTAssertEqual(dispatcher.dispatched, ["write_file"], "批准之后必须真的执行")
        XCTAssertEqual(result.executedTools.map(\.name), ["write_file"])
    }

    /// 判据 ② 的反面：批准后正文被改 ⇒ 在主循环里同样被拦。
    func testChangedPlanBlocksExecutionInTheLoop() async {
        var plan = AgentPlanState()
        plan.submit("原计划")
        plan.approve()
        plan.body = "悄悄加一步"
        let (_, dispatcher) = await run(name: "write_file",
                                        arguments: #"{"path":"out.txt","content":"hi"}"#, plan: plan)
        XCTAssertTrue(dispatcher.dispatched.isEmpty, "批准后改动计划内容仍放行 = 批准了一张空白支票")
    }
}
