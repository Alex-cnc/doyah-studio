import XCTest
@testable import DoyahCore

/// **优先级截断 · 循环级判据**（`FR-AGT-KNOW-CTX-001` · 计划 P3-2）。
///
/// 判的是**真发出去的提示词**：超预算时按优先级丢段（最近一条留、最老的先丢），预算内逐字不变。
/// 2026-11-18 实测：`AgentContextPriorityTruncator` 全仓零生产侧引用。
final class AgentContextPriorityTruncationLoopTests: XCTestCase {

    /// 每跳吐一条长工具调用（造出可观察的观察段），最后一跳收尾。
    private final class ChattyClient: LLMStreamingClient, @unchecked Sendable {
        private let lock = NSLock()
        private var hops = 0
        private(set) var prompts: [String] = []
        private let hopsWithTools: Int

        init(hopsWithTools: Int) { self.hopsWithTools = hopsWithTools }

        func stream(_ request: LLMRequest) async throws -> AsyncThrowingStream<LLMStreamEvent, Error> {
            lock.lock(); hops += 1; let hop = hops
            prompts.append(request.userPrompt); lock.unlock()
            return AsyncThrowingStream { continuation in
                if hop <= self.hopsWithTools {
                    continuation.yield(.toolCallDelta(index: 0, id: "c\(hop)", name: "read_file",
                                                     argumentsFragment: "{\"path\":\"f\(hop).txt\"}"))
                } else {
                    continuation.yield(.textDelta("收工。"))
                }
                continuation.yield(.done)
                continuation.finish()
            }
        }
    }

    /// 每次返回带唯一标记的长文本 —— 便于断言「哪一段被丢了」。
    private final class EchoDispatcher: AgentToolDispatcher, @unchecked Sendable {
        func dispatch(_ invocation: AgentToolInvocation, approvals: Set<String>) -> AgentToolOutcome {
            let tag = invocation.argumentsJSON
            let body = String(repeating: "长内容-", count: 120) + "TAG" + tag
            return .file(AgentToolFileOutput(path: "x", text: body, truncated: false, totalBytes: body.count))
        }
    }

    private func run(hopsWithTools: Int,
                     maxPromptCharacters: Int?) async -> ChattyClient {
        let client = ChattyClient(hopsWithTools: hopsWithTools)
        var loop = AgentLoop(client: client, dispatcher: EchoDispatcher(),
                             registry: .standard, sessionStore: nil)
        loop.compressionBudget = maxPromptCharacters.map {
            AgentContextCompressionBudget(maxPromptCharacters: $0)
        }
        loop.limits = AgentLoopLimits(maxSteps: 12, maxToolCallsPerHop: 1)
        let context = AgentLoopContext(
            systemPrompt: "s", userPrompt: "干活",
            baseRequest: LLMRequest(endpoint: URL(string: "http://127.0.0.1:11434/v1")!,
                                    model: "m", systemPrompt: "", userPrompt: ""),
            sessionID: "sess-trunc", workspace: "/tmp")
        _ = await loop.run(context: context)
        return client
    }

    /// 超预算 ⇒ 丢最老的、留最近的，并明说丢了哪几段。
    func testOverBudgetDropsOldestAndSaysWhatWasDropped() async {
        let client = await run(hopsWithTools: 4, maxPromptCharacters: 1_200)
        guard let last = client.prompts.last else { return XCTFail("没发出请求") }

        XCTAssertTrue(last.contains("TAG{\"path\":\"f4.txt\"}"), "最近一条观察必须留下（critical）")
        XCTAssertFalse(last.contains("TAG{\"path\":\"f1.txt\"}"), "最老那条应当被丢掉")
        XCTAssertTrue(last.contains("over context budget: dropped"), "丢段必须明说，不许静默：\n\(last.suffix(200))")
    }

    /// 预算内 ⇒ 提示词**逐字不变**（截断只在超预算时动手）。
    func testUnderBudgetKeepsThePromptByteForByte() async {
        let client = await run(hopsWithTools: 2, maxPromptCharacters: 200_000)
        guard let last = client.prompts.last else { return XCTFail("没发出请求") }
        XCTAssertFalse(last.contains("over context budget: dropped"), "预算内不许截断")
        XCTAssertTrue(last.contains("TAG{\"path\":\"f1.txt\"}"))
        XCTAssertTrue(last.contains("TAG{\"path\":\"f2.txt\"}"))
    }

    /// 不给预算 ⇒ 旧行为（不截断、无标记）。
    func testNoBudgetMeansNoTruncation() async {
        let client = await run(hopsWithTools: 3, maxPromptCharacters: nil)
        guard let last = client.prompts.last else { return XCTFail("没发出请求") }
        XCTAssertFalse(last.contains("over context budget: dropped"))
        XCTAssertTrue(last.contains("TAG{\"path\":\"f1.txt\"}"), "不给预算时不做任何丢弃")
    }
}
