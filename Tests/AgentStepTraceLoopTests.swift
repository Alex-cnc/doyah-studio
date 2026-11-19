import XCTest
@testable import DoyahCore

/// **过程可见 · 循环级判据**（`FR-AGT-UX-CONV-006` · 计划 P1-7）。
///
/// 判的是**跑完之后交出来的那份轨迹**：一跳一条、`index` 与跳数同量纲、没有空标签的步。
/// 2026-11-18 实测：`AgentStepTrace` 全仓零生产侧引用（只在死类里当过字段类型）。
final class AgentStepTraceLoopTests: XCTestCase {

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

    private func run(tools: [String]) async -> AgentLoopResult {
        var loop = AgentLoop(client: ScriptedClient(tools: tools), dispatcher: StubDispatcher(),
                             registry: .standard, sessionStore: nil)
        loop.limits = AgentLoopLimits(maxSteps: 12, maxToolCallsPerHop: 1)
        let context = AgentLoopContext(
            systemPrompt: "s", userPrompt: "干活",
            baseRequest: LLMRequest(endpoint: URL(string: "http://127.0.0.1:11434/v1")!,
                                    model: "m", systemPrompt: "", userPrompt: ""),
            sessionID: "sess-trace", workspace: "/tmp")
        return await loop.run(context: context)
    }

    /// 三跳（两次读文件 + 一次收尾）⇒ 轨迹三条，**无静默步**，且每条的 index 与跳数对得上。
    func testEveryHopLeavesExactlyOneVisibleRecord() async {
        let result = await run(tools: ["read_file", "read_file"])
        let trace = result.stepTrace
        XCTAssertNotNil(trace, "跑完了必须有轨迹（没有 = 过程不可见）")
        XCTAssertEqual(trace?.records.count, result.steps, "声明的跳数与记录条数必须相等")
        XCTAssertTrue(trace?.isEveryStepVisible(declared: result.steps) ?? false, "不许有静默步")
        XCTAssertEqual(trace?.records.map(\.index), Array(1...result.steps), "index 从 1 连续到跳数")
        XCTAssertFalse(trace?.records.contains { $0.label.isEmpty } ?? true, "每条都要有一行摘要")
    }

    /// 文件动作与答复要能分开筛（界面「只看文件动作」靠这个）。
    func testKindsLetTheUIChangeTheSlice() async {
        let result = await run(tools: ["read_file"])
        guard let trace = result.stepTrace else { return XCTFail("没有轨迹") }
        XCTAssertEqual(trace.records(of: .file).count, 1, "读文件那一步应记成 file")
        XCTAssertEqual(trace.records(of: .decision).count, 1, "收尾那一步应记成 decision")
    }

    /// 一跑就失败（无轨迹内容）时如实为空，不造一条假记录。
    func testNoTraceWhenNoHopRecorded() async {
        let result = await run(tools: [])
        XCTAssertEqual(result.stepTrace?.records.count, result.steps,
                       "就算只有收尾一跳，也要有对应的一条")
    }
}
