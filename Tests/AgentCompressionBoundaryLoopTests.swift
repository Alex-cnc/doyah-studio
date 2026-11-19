import XCTest
@testable import DoyahCore

/// **压缩只在会话边界发生 · 循环级判据**（详设 §3.21 · `FR-AGT-KNOW-CTX-002` · 计划 P1-9）。
///
/// 为什么另立一个文件而不是加进 `AgentCompressionAdmissionTests`：
/// 那边判的是 `admit(at:)` 这个**纯函数** —— 纯函数绿，不代表循环真的按它走。
/// 2026-11-18 实测：`AgentContextCompressor.compress` 全仓**只有一个调用点**，就在
/// `AgentLoop.makeRequest` 的每一跳里 ⇒ 回合内一直在压，正是 §3.21 明文禁止的那种。
/// 本文件的判据只看**循环实际发出去的请求**（不看返回值），所以它判的是真路径。
final class AgentCompressionBoundaryLoopTests: XCTestCase {

    /// 长正文：超过下面那条极小预算，压缩器一定会想动手。
    private static let longBody = String(repeating: "细节", count: 1_500)

    /// 记下每一次请求的提示词，hop 1 发一次读文件，hop 2 收尾。
    private final class RecordingClient: LLMStreamingClient, @unchecked Sendable {
        private let lock = NSLock()
        private var prompts: [String] = []
        private var hops = 0

        var captured: [String] { lock.lock(); defer { lock.unlock() }; return prompts }

        func stream(_ request: LLMRequest) async throws -> AsyncThrowingStream<LLMStreamEvent, Error> {
            lock.lock(); hops += 1; let hop = hops; prompts.append(request.userPrompt); lock.unlock()
            return AsyncThrowingStream { continuation in
                if hop == 1 {
                    continuation.yield(.toolCallDelta(index: 0, id: "c0", name: "read_file",
                                                     argumentsFragment: "{\"path\":\"big.txt\"}"))
                } else {
                    continuation.yield(.textDelta("看完了。"))
                }
                continuation.yield(.done)
                continuation.finish()
            }
        }
    }

    private final class LongBodyDispatcher: AgentToolDispatcher, @unchecked Sendable {
        let body: String
        init(body: String) { self.body = body }
        func dispatch(_ invocation: AgentToolInvocation, approvals: Set<String>) -> AgentToolOutcome {
            .file(AgentToolFileOutput(path: "big.txt", text: body, truncated: false,
                                      totalBytes: body.utf8.count))
        }
    }

    private func runLoop(budget: AgentContextCompressionBudget) async -> RecordingClient {
        let client = RecordingClient()
        let loop = AgentLoop(client: client,
                             dispatcher: LongBodyDispatcher(body: Self.longBody),
                             sessionStore: nil,
                             compressionBudget: budget,
                             observationDigest: nil,
                             limits: AgentLoopLimits(maxSteps: 4))
        let context = AgentLoopContext(
            systemPrompt: "s", userPrompt: "读一下 big.txt",
            baseRequest: LLMRequest(endpoint: URL(string: "http://127.0.0.1:11434/v1")!,
                                    model: "m", systemPrompt: "", userPrompt: ""),
            sessionID: "sess-compress", workspace: "/tmp")
        _ = await loop.run(context: context)
        return client
    }

    /// `T-3.21-01`：**回合内不压** —— 预算小到必超，那一跳的观察正文仍要原样进请求。
    ///
    /// 现状（修之前）：`makeRequest` 直接调压缩器 ⇒ 第二跳的提示词里正文本被换掉。
    func testInTurnNeverCompresses() async {
        let client = await runLoop(budget: AgentContextCompressionBudget(maxPromptCharacters: 200,
                                                                        keepRecentEntries: 0,
                                                                        minimumEntries: 0))
        let prompts = client.captured
        XCTAssertEqual(prompts.count, 2, "至少要两跳才看得出「回合内」")
        guard prompts.count == 2 else { return }
        XCTAssertTrue(prompts[1].contains("细节细节细节"),
                      "回合内把观察正文压掉了 —— 详设 §3.21 明文禁止 per-turn 压缩")
    }

    /// `T-3.21-02`：**边界才压，且保留决策** —— 同一个预算，走 `.userCompact` 边界就必须真压。
    func testBoundaryCompressesAndKeepsDecisions() {
        let admission = AgentContextCompression.compactAtBoundary(
            .userCompact,
            entries: [Self.longBody, "第二段"],
            budget: AgentContextCompressionBudget(maxPromptCharacters: 2_000,
                                                  keepRecentEntries: 0,
                                                  minimumEntries: 0),
            decisionsKept: ["必须在 macOS 上先验证", "不许动冻结件"])
        guard case let .runNow(boundary, product) = admission else {
            return XCTFail("边界上必须真压，实际 = \(admission)")
        }
        XCTAssertEqual(boundary, .userCompact)
        XCTAssertEqual(product.decisionsKept.count, 2, "压缩里不许丢掉用户显式要求保留的约束")
        XCTAssertLessThan(product.tokensAfter, product.tokensBefore)
        XCTAssertFalse(product.marker.isEmpty, "截断处必须有界面可见的标记")
    }

    /// `T-3.21-03`：**压完还是超 ⇒ 如实报**，不许静默截断。
    func testStillOverLimitIsRefusedNotTruncated() {
        let admission = AgentContextCompression.compactAtBoundary(
            .beforeSessionEnd,
            entries: [String(repeating: "字", count: 4_000)],
            budget: AgentContextCompressionBudget(maxPromptCharacters: 10,
                                                  keepRecentEntries: 2,
                                                  minimumEntries: 0))
        guard case let .refuse(reason) = admission else {
            return XCTFail("压完仍超上限必须 refuse，实际 = \(admission)")
        }
        if case let .stillOverLimit(before, after) = reason {
            XCTAssertGreaterThan(before, 0)
            XCTAssertGreaterThan(after, 10)
        } else {
            XCTFail("拒绝原因必须是 stillOverLimit")
        }
    }
}
