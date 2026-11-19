import XCTest
@testable import DoyahCore

/// **引擎生命周期钩子 · 循环级判据**（详设 §3.23 · `FR-AGT-CORE-CTX-001` / `OPS-OBS-001` · 计划 P1-11）。
///
/// 为什么在循环里判而不是只判 `AgentContextEngineHost`：
/// 宿主自己写对了不算数 —— 2026-11-18 实测，`AgentContextEngine` 全仓**零生产侧引用**，
/// 类写完、测试绿、主循环一次都没调过。本文件的判据只看**循环真跑过之后**的调用次数。
final class AgentContextHooksLoopTests: XCTestCase {

    /// 记调用次数、可指定「哪一跳抛错」。
    private final class RecordingEngine: AgentContextEngine, @unchecked Sendable {
        private let lock = NSLock()
        private(set) var starts = 0
        private(set) var updates = 0
        private(set) var ends = 0
        private(set) var compresses = 0
        private(set) var shouldCompressAsks = 0
        let throwOnUpdate: Bool

        init(throwOnUpdate: Bool = false) { self.throwOnUpdate = throwOnUpdate }

        func onSessionStart() throws -> AgentHookOutcome {
            lock.lock(); starts += 1; lock.unlock(); return .ok
        }
        func updateFromResponse(_ text: String) throws -> AgentHookOutcome {
            lock.lock(); updates += 1; lock.unlock()
            if throwOnUpdate { throw NSError(domain: "hook", code: 1) }
            return .ok
        }
        func shouldCompress() throws -> AgentHookOutcome {
            lock.lock(); shouldCompressAsks += 1; lock.unlock(); return .ok
        }
        func compress() throws -> AgentHookOutcome {
            lock.lock(); compresses += 1; lock.unlock(); return .ok
        }
        func onSessionEnd() throws -> AgentHookOutcome {
            lock.lock(); ends += 1; lock.unlock(); return .ok
        }
    }

    private final class OneToolClient: LLMStreamingClient, @unchecked Sendable {
        private let lock = NSLock()
        private var hops = 0
        func stream(_ request: LLMRequest) async throws -> AsyncThrowingStream<LLMStreamEvent, Error> {
            lock.lock(); hops += 1; let hop = hops; lock.unlock()
            return AsyncThrowingStream { continuation in
                if hop == 1 {
                    continuation.yield(.toolCallDelta(index: 0, id: "c0", name: "read_file",
                                                     argumentsFragment: "{\"path\":\"a.txt\"}"))
                } else {
                    continuation.yield(.textDelta("读完了。"))
                }
                continuation.yield(.done)
                continuation.finish()
            }
        }
    }

    private final class StubDispatcher: AgentToolDispatcher, @unchecked Sendable {
        func dispatch(_ invocation: AgentToolInvocation, approvals: Set<String>) -> AgentToolOutcome {
            .file(AgentToolFileOutput(path: "a.txt", text: "内容", truncated: false, totalBytes: 6))
        }
    }

    private func run(engine: (any AgentContextEngine)?,
                     journal: AgentHookJournal) async -> AgentLoopResult {
        var loop = AgentLoop(client: OneToolClient(), dispatcher: StubDispatcher(), sessionStore: nil)
        loop.contextEngine = engine
        loop.hookJournal = journal
        let context = AgentLoopContext(
            systemPrompt: "s", userPrompt: "读 a.txt",
            baseRequest: LLMRequest(endpoint: URL(string: "http://127.0.0.1:11434/v1")!,
                                    model: "m", systemPrompt: "", userPrompt: ""),
            sessionID: "sess-hooks", workspace: "/tmp")
        return await loop.run(context: context)
    }

    /// `T-3.23-01`：真实结束**恰好一次**；开始一次；`updateFromResponse` 每响应一次。
    func testRealEndFiresExactlyOnce() async {
        let engine = RecordingEngine()
        let journal = AgentHookJournal()
        let result = await run(engine: engine, journal: journal)

        XCTAssertEqual(result.outcome, .finished(text: "读完了。"))
        XCTAssertEqual(engine.starts, 1, "会话开始必须恰好一次")
        XCTAssertEqual(engine.ends, 1, "真实结束必须恰好一次（多一次就是 per-turn 触发）")
        XCTAssertEqual(engine.updates, 2, "两跳 ⇒ 每响应一次")
        XCTAssertEqual(journal.callCount(of: .onSessionEnd), 1, "日志里也必须是 1 条")

        let endEntry = journal.entries.first { $0.hook == .onSessionEnd }
        XCTAssertEqual(endEntry?.boundaryKind, .cliExit, "结束要记边界类型")
    }

    /// `T-3.23-02`：**钩子抛错不中断会话** —— 折成 `.failed`，主循环照旧跑完。
    func testHookThrowingDoesNotBreakTheSession() async {
        let engine = RecordingEngine(throwOnUpdate: true)
        let journal = AgentHookJournal()
        let result = await run(engine: engine, journal: journal)

        XCTAssertEqual(result.outcome, .finished(text: "读完了。"),
                       "钩子抛错被升格成会话错误 —— §3.23 明确禁止")
        XCTAssertEqual(engine.ends, 1, "抛错之后结束钩子仍要跑")
        let failed = journal.entries.filter { $0.outcome == .failed(code: "thrown") }
        XCTAssertFalse(failed.isEmpty, "抛错要留一条 failed 记录，不许静默")
    }

    /// `T-3.23-03`：未注册引擎 ⇒ 如实 `.skipped(.noEngine)`，不假装跑过。
    func testNoEngineSkipsHonestly() async {
        let journal = AgentHookJournal()
        let result = await run(engine: nil, journal: journal)

        XCTAssertEqual(result.outcome, .finished(text: "读完了。"))
        let outcomes = Set(journal.entries.map { "\($0.outcome)" })
        XCTAssertEqual(outcomes, ["skipped(reason: \"noEngine\")"],
                       "没有引擎时每个钩子都要如实报跳过，实际 = \(outcomes)")
    }

    /// `T-3.23-03`（宿主侧）：回合内调 `onSessionEnd` 直接拒；重复结束幂等返回首次结局。
    func testEndRefusedInsideTurnAndIdempotentAtBoundary() {
        let engine = RecordingEngine()
        var host = AgentContextEngineHost(sessionID: "s", engine: engine)

        let refused = host.endSession(at: .sessionReset, sessionOpen: false)
        XCTAssertEqual(refused, .failure(.notASessionBoundary), "回合内结束必须被拒")
        XCTAssertEqual(engine.ends, 0, "被拒时不许触发引擎钩子")

        let first = host.endSession(at: .gatewayExpiry)
        let second = host.endSession(at: .cliExit)
        XCTAssertEqual(first, second, "重复结束必须幂等返回首次结局")
        XCTAssertEqual(engine.ends, 1)
    }
}
