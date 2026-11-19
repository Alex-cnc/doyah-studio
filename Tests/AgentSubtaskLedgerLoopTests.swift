import XCTest
@testable import DoyahCore

/// **子任务委派 · 台账判据**（`FR-AGT-TOOL-SYS-002` ② · 计划 P4-系统）。
///
/// 判的是「谁干的、标得出来吗」：同一趟循环以子任务身份跑时，步骤必须落到那个子任务名下，
/// 且能按 `index` 反查归属。**覆盖范围**：真并行子代理（独立上下文 / 失败隔离 /
/// 汇总回主任务）依赖 §3.20 编排，本仓尚未实现 —— 这条只判台账口径，不判并行。
final class AgentSubtaskLedgerLoopTests: XCTestCase {

    private final class ScriptedClient: LLMStreamingClient, @unchecked Sendable {
        private let lock = NSLock()
        private var hops = 0
        private let tools: [String]
        init(tools: [String]) { self.tools = tools }
        func stream(_ request: LLMRequest) async throws -> AsyncThrowingStream<LLMStreamEvent, Error> {
            lock.lock(); hops += 1; let hop = hops; lock.unlock()
            return AsyncThrowingStream { continuation in
                if hop <= self.tools.count {
                    continuation.yield(.toolCallDelta(index: 0, id: "c\(hop)", name: self.tools[hop - 1],
                                                     argumentsFragment: "{\"path\":\"f.txt\"}"))
                } else {
                    continuation.yield(.textDelta("完事。"))
                }
                continuation.yield(.done)
                continuation.finish()
            }
        }
    }

    private final class StubDispatcher: AgentToolDispatcher, @unchecked Sendable {
        func dispatch(_ invocation: AgentToolInvocation, approvals: Set<String>) -> AgentToolOutcome {
            .file(AgentToolFileOutput(path: "f.txt", text: "内容", truncated: false, totalBytes: 6))
        }
    }

    private func run(tools: [String], delegation: (id: String, goal: String, delegatedAtStep: Int)?)
        async -> AgentLoopResult {
        var loop = AgentLoop(client: ScriptedClient(tools: tools), dispatcher: StubDispatcher(),
                             registry: .standard, sessionStore: nil)
        loop.limits = AgentLoopLimits(maxSteps: 12, maxToolCallsPerHop: 1)
        loop.delegation = delegation
        let context = AgentLoopContext(
            systemPrompt: "s", userPrompt: "干活",
            baseRequest: LLMRequest(endpoint: URL(string: "http://127.0.0.1:11434/v1")!,
                                    model: "m", systemPrompt: "", userPrompt: ""),
            sessionID: "sess-subtask", workspace: "/tmp")
        return await loop.run(context: context)
    }

    /// 以子任务身份跑 ⇒ 每一步都挂在该子任务名下，且能反查归属。
    func testStepsAreAttributedToTheDelegatingSubtask() async {
        let result = await run(tools: ["read_file", "read_file"],
                               delegation: (id: "sub-1", goal: "读两个文件", delegatedAtStep: 3))
        guard let ledger = result.subtaskLedger, let entry = ledger.delegations.first else {
            return XCTFail("以子任务身份跑完必须有台账")
        }
        XCTAssertEqual(entry.id, "sub-1")
        XCTAssertEqual(entry.goal, "读两个文件")
        XCTAssertEqual(entry.origin, .subtask(id: "sub-1", delegatedAtStep: 3))
        XCTAssertEqual(entry.steps.records.count, result.steps, "子任务的每一步都要留痕（独立留痕）")
        for index in 1...result.steps {
            XCTAssertNotNil(ledger.origin(ofStep: index, inSubtask: "sub-1"),
                            "第 \(index) 步要能反查归属")
        }
        XCTAssertEqual(ledger.allStepsGrouped().first?.records.count, result.steps)
    }

    /// 主循环（不传委派）⇒ 不出台账，也不造空条目。
    func testMainLoopHasNoDelegationLedger() async {
        let result = await run(tools: ["read_file"], delegation: nil)
        XCTAssertNil(result.subtaskLedger, "主循环不该凭空生成委派台账")
        XCTAssertNotNil(result.stepTrace, "但过程可见照旧")
    }
}
