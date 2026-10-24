import XCTest
@testable import DoyahCore

/// `FR-AGT-PLAN-PLAN-006`（失败自恢复）的机械判据。
///
/// 台账两条要求：
///   ① 工具 / 模型失败**能换路就换路**（不可重试的先换个模型再说，并且当场说清从谁换到谁）；
///   ② **连续失败要停下来说明**，不许无限重来。
///
/// 这一批补的是 ①（此前只有「可重试的再试一次」，不可重试的直接判死）与 ②（此前只有告警，不停）。
/// 判据一律用脚本化假模型：不发真请求、不等真退避。

final class AgentLoopRecoveryTests: XCTestCase {

    /// 按脚本吐事件的假模型：可以按「模型名」决定成功还是失败。
    private final class RouteAwareClient: LLMStreamingClient, @unchecked Sendable {
        /// 只有这些模型名会成功；其余一律抛不可重试错误。
        let goodModels: Set<String>
        private(set) var requestedModels: [String] = []
        private(set) var attempts = 0

        init(goodModels: Set<String>) { self.goodModels = goodModels }

        func stream(_ request: LLMRequest) async throws -> AsyncThrowingStream<LLMStreamEvent, Error> {
            attempts += 1
            requestedModels.append(request.model)
            guard goodModels.contains(request.model) else {
                // `forbidden` = 不可重试（配置 / 权限类），正是「该换路」的那一档。
                throw LLMError.forbidden("model unavailable: \(request.model)")
            }
            return AsyncThrowingStream { continuation in
                continuation.yield(.textDelta("好了"))
                continuation.yield(.done)
                continuation.finish()
            }
        }
    }

    private final class NoopDispatcher: AgentToolDispatcher, @unchecked Sendable {
        func dispatch(_ invocation: AgentToolInvocation, approvals: Set<String>) -> AgentToolOutcome {
            .rows(AgentToolRowsOutput(columns: [], rowCount: 0, statementKind: "select"))
        }
    }

    private var directory: URL!
    private var store: AgentSessionStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-recovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = AgentSessionStore(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var context: AgentLoopContext {
        AgentLoopContext(systemPrompt: "你是助手。", userPrompt: "改一下 a.txt",
                         baseRequest: LLMRequest(endpoint: URL(string: "http://127.0.0.1:11434/v1")!,
                                                 model: "primary-model", systemPrompt: "", userPrompt: ""),
                         sessionID: "s-recovery", workspace: "ws-1")
    }

    // MARK: - ① 不可重试 ⇒ 换路

    func testNonRetryableFailureSwitchesToFallbackModelAndSucceeds() async {
        let client = RouteAwareClient(goodModels: ["fallback-model"])
        let loop = AgentLoop(client: client, dispatcher: NoopDispatcher(), sessionStore: store,
                             limits: AgentLoopLimits(fallbackModels: ["fallback-model"]))

        let result = await loop.run(context: context)

        guard case .finished(let text) = result.outcome else {
            return XCTFail("换路成功后应当正常完成，实际 \(result.outcome)")
        }
        XCTAssertEqual(text, "好了")
        XCTAssertEqual(client.requestedModels, ["primary-model", "fallback-model"],
                       "第一次用原模型、失败后换到备用的那个")
    }

    /// **换过的不回头**：备用模型也失败 ⇒ 不许在原模型与备用模型之间打乒乓。
    func testFallbackIsTriedOnceAndNotPingPonged() async {
        let client = RouteAwareClient(goodModels: [])
        let loop = AgentLoop(client: client, dispatcher: NoopDispatcher(), sessionStore: store,
                             limits: AgentLoopLimits(maxConsecutiveFailures: 9,
                                                     fallbackModels: ["fallback-model"]))

        let result = await loop.run(context: context)

        guard case .failed = result.outcome else { return XCTFail("都不可用就该如实失败") }
        XCTAssertEqual(client.requestedModels, ["primary-model", "fallback-model"],
                       "每个模型各试一次就够，不许来回换")
        XCTAssertEqual(Set(client.requestedModels).count, client.requestedModels.count,
                       "同一个模型不许被请求两次")
    }

    // MARK: - ② 连续失败 ⇒ 停

    func testConsecutiveFailuresStopAndSayHowMany() async {
        let client = RouteAwareClient(goodModels: [])
        let loop = AgentLoop(client: client, dispatcher: NoopDispatcher(), sessionStore: store,
                             limits: AgentLoopLimits(maxConsecutiveFailures: 2,
                                                     fallbackModels: ["a", "b", "c"]))

        let result = await loop.run(context: context)

        guard case .failed(let detail) = result.outcome else {
            return XCTFail("连续失败该停，实际 \(result.outcome)")
        }
        XCTAssertTrue(detail.contains("consecutiveFailures:"), "原因要能被机器认出来：\(detail)")
        XCTAssertTrue(detail.contains("2"), "要说清连了几次：\(detail)")
        XCTAssertLessThanOrEqual(client.attempts, 3,
                                 "到顶就停：2 次上限最多试 2 个模型，不许把备用表刷完")
    }

    /// 限额默认值：连续失败 3 次、备用模型为空（不配就没有换路，行为与旧版一致）。
    func testRecoveryDefaultsDoNotChangeOldBehaviour() {
        let limits = AgentLoopLimits()
        XCTAssertEqual(limits.maxConsecutiveFailures, 3)
        XCTAssertTrue(limits.fallbackModels.isEmpty, "默认不换路：换路要显式配")
    }
}
