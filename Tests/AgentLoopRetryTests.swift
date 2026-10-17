import XCTest
@testable import DoyahCore

/// 重试接线（`FR-AI-30`）：**值得再试的才试 · 半截产出不重试 · 用尽如实停 · 不可重试的一次都不试**。
final class AgentLoopRetryTests: XCTestCase {

    /// 会按剧本失败的假客户端：前 `failures` 次抛错，之后正常回一段文本。
    private final class ScriptedClient: LLMStreamingClient, @unchecked Sendable {
        enum Mode { case failTimes(Int, LLMError), alwaysFail(LLMError), partialThenFail }
        private let mode: Mode
        private(set) var callCount = 0
        init(_ mode: Mode) { self.mode = mode }

        func stream(_ request: LLMRequest) async throws -> AsyncThrowingStream<LLMStreamEvent, Error> {
            callCount += 1
            switch mode {
            case .failTimes(let times, let error):
                if callCount <= times { throw error }
                return AsyncThrowingStream { c in
                    c.yield(.textDelta("ok")); c.yield(.usage(LLMUsage(promptTokens: 3, completionTokens: 2, totalTokens: 5), model: nil)); c.finish()
                }
            case .alwaysFail(let error):
                throw error
            case .partialThenFail:
                return AsyncThrowingStream { c in
                    c.yield(.textDelta("半截"))
                    c.finish(throwing: LLMError.transport("reset"))
                }
            }
        }
    }

    private func makeLoop(client: LLMStreamingClient, policy: LLMRetryPolicy) -> AgentLoop {
        let request = LLMRequest(endpoint: URL(string: "https://example.test/v1")!, model: "m", apiKey: "k",
                                 systemPrompt: "s", userPrompt: "u")
        var loop = AgentLoop(client: client,
                             dispatcher: StubDispatcher(),
                             registry: .standard)
        loop.retryPolicy = policy
        _ = request
        return loop
    }

    private var fastPolicy: LLMRetryPolicy { LLMRetryPolicy(maxAttempts: 3, delays: [0, 0]) }

    func testRetriesTransientTransportFailureThenSucceeds() async {
        let client = ScriptedClient(.failTimes(2, .transport("reset")))
        let loop = makeLoop(client: client, policy: fastPolicy)
        let context = AgentLoopContext(systemPrompt: "s", userPrompt: "u",
                                       baseRequest: LLMRequest(endpoint: URL(string: "https://example.test/v1")!, model: "m",
                                                               apiKey: "k", systemPrompt: "s", userPrompt: "u"),
                                       sessionID: "s1", workspace: "/tmp")
        let result = await loop.run(context: context)
        XCTAssertEqual(client.callCount, 3, "两次失败 + 一次成功 = 三次尝试")
        XCTAssertEqual(result.text, "ok")
    }

    func testDoesNotRetryUnretryableError() async {
        let client = ScriptedClient(.alwaysFail(.forbidden("gate")))
        let loop = makeLoop(client: client, policy: fastPolicy)
        let context = AgentLoopContext(systemPrompt: "s", userPrompt: "u",
                                       baseRequest: LLMRequest(endpoint: URL(string: "https://example.test/v1")!, model: "m",
                                                               apiKey: "k", systemPrompt: "s", userPrompt: "u"),
                                       sessionID: "s2", workspace: "/tmp")
        let result = await loop.run(context: context)
        XCTAssertEqual(client.callCount, 1, "forbidden 一次都不重试")
        if case .failed(let why) = result.outcome { XCTAssertTrue(why.contains("notRetryable"), "不可重试要说清：\(why)") } else { XCTFail("应当失败") }
    }

    func testNeverRetriesAfterPartialOutput() async {
        let client = ScriptedClient(.partialThenFail)
        let loop = makeLoop(client: client, policy: fastPolicy)
        let context = AgentLoopContext(systemPrompt: "s", userPrompt: "u",
                                       baseRequest: LLMRequest(endpoint: URL(string: "https://example.test/v1")!, model: "m",
                                                               apiKey: "k", systemPrompt: "s", userPrompt: "u"),
                                       sessionID: "s3", workspace: "/tmp")
        let result = await loop.run(context: context)
        XCTAssertEqual(client.callCount, 1, "已经吐出半截 ⇒ 不许重试（重试会重复前半段）")
        XCTAssertTrue(result.text.hasPrefix("半截"), "半截内容要如实留下，不静默丢掉")
    }

    func testExhaustsAfterMaxAttemptsAndSaysSo() async {
        let client = ScriptedClient(.alwaysFail(.transport("down")))
        let loop = makeLoop(client: client, policy: LLMRetryPolicy(maxAttempts: 2, delays: [0, 0]))
        let context = AgentLoopContext(systemPrompt: "s", userPrompt: "u",
                                       baseRequest: LLMRequest(endpoint: URL(string: "https://example.test/v1")!, model: "m",
                                                               apiKey: "k", systemPrompt: "s", userPrompt: "u"),
                                       sessionID: "s4", workspace: "/tmp")
        let result = await loop.run(context: context)
        XCTAssertEqual(client.callCount, 3, "1 初 + 2 重 = 3 次")
        if case .failed(let why) = result.outcome {
            XCTAssertTrue(why.contains("retriesExhausted"), "要说清是用尽而不是别的，实际：\(why)")
            XCTAssertTrue(why.contains("retries:2"))
        } else {
            XCTFail("应当如实失败：\(result.outcome)")
        }
    }

    func testRetryPolicyClassificationIsStable() {
        let policy = LLMRetryPolicy()
        XCTAssertTrue(policy.isRetryable(.transport("x")))
        XCTAssertTrue(policy.isRetryable(.httpStatus(code: 429, message: nil)))
        XCTAssertTrue(policy.isRetryable(.httpStatus(code: 503, message: nil)))
        XCTAssertFalse(policy.isRetryable(.httpStatus(code: 401, message: nil)))
        XCTAssertFalse(policy.isRetryable(.forbidden("gate")))
        XCTAssertFalse(policy.isRetryable(.quotaExceeded("q")))
        XCTAssertFalse(policy.isRetryable(.malformedResponse("bad")))
    }
}

/// 循环里用不到工具的桩（只测模型那一跳）。
private struct StubDispatcher: AgentToolDispatcher {
    func dispatch(_ invocation: AgentToolInvocation, approvals: Set<String>) -> AgentToolOutcome {
        .refused(.unregistered, detail: invocation.name)
    }
}
