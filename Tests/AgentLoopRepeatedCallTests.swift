import XCTest
@testable import DoyahCore

/// **同一条调用不许无限重来**（2026-11-11 自测实录）。
///
/// 现场：派「执行 git status --short 看下有没有未提交的改动」，模型连做 3 次同一条命令，
/// 每跳正文都是空；监控已经报 `spinning:3/3`，但循环只报警不停 ——
/// 5 跳白烧，最后回话是「跑完了但没有可读正文」。
///
/// 判据：① 同一条 (工具, 参数) 最多执行 3 次；
/// ② 第 4 次起**不执行**（不是执行完再判），并回一句「已经做过 3 次，换手段或给结论」；
/// ③ 换了参数就是另一条，不该被上文那三次连累。
final class AgentLoopRepeatedCallTests: XCTestCase {

    private final class LoopingClient: LLMStreamingClient, @unchecked Sendable {
        private let lock = NSLock()
        private(set) var calls = 0
        /// 前 N 跳都发同一条工具调用，之后给正文。
        let toolHops: Int
        init(toolHops: Int) { self.toolHops = toolHops }

        func stream(_ request: LLMRequest) async throws -> AsyncThrowingStream<LLMStreamEvent, Error> {
            lock.lock()
            calls += 1
            let index = calls
            lock.unlock()
            if index <= toolHops {
                return AsyncThrowingStream { continuation in
                    continuation.yield(.toolCallDelta(index: 0, id: "call-\(index)", name: "read_file",
                                                      argumentsFragment: #"{"path":"a.txt"}"#))
                    continuation.yield(.done)
                    continuation.finish()
                }
            }
            return AsyncThrowingStream { continuation in
                continuation.yield(.textDelta("结论：工作区是干净的。"))
                continuation.yield(.done)
                continuation.finish()
            }
        }
    }

    private final class CountingDispatcher: AgentToolDispatcher, @unchecked Sendable {
        private let lock = NSLock()
        private(set) var executed = 0
        func dispatch(_ invocation: AgentToolInvocation, approvals: Set<String>) -> AgentToolOutcome {
            lock.lock(); executed += 1; lock.unlock()
            return .file(AgentToolFileOutput(path: "a.txt", text: "clean", truncated: false, totalBytes: 5))
        }
    }

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-repeat-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func run(hops: Int) async -> (AgentLoopResult, CountingDispatcher) {
        let dispatcher = CountingDispatcher()
        let loop = AgentLoop(client: LoopingClient(toolHops: hops), dispatcher: dispatcher,
                             sessionStore: AgentSessionStore(directory: directory))
        let context = AgentLoopContext(systemPrompt: "s", userPrompt: "看一眼",
                                       baseRequest: LLMRequest(endpoint: URL(string: "http://127.0.0.1:11434/v1")!,
                                                               model: "m", systemPrompt: "", userPrompt: ""),
                                       sessionID: UUID().uuidString, workspace: directory.path)
        let result = await loop.run(context: context)
        return (result, dispatcher)
    }

    func testSameCallIsExecutedThreeTimesAtMost() async {
        let (result, dispatcher) = await run(hops: 6)
        XCTAssertEqual(dispatcher.executed, AgentLoop.callRepeatCeiling,
                       "同一条调用最多执行 \(AgentLoop.callRepeatCeiling) 次，实际 \(dispatcher.executed)")
        XCTAssertTrue(result.text.contains("结论"), "到顶之后仍要能把结论说出来：\(result.text)")
    }

    /// 负例：没到顶之前照常执行（不能把「连做两次」也当打转）。
    func testTwoRepeatsAreStillAllowed() async {
        let (_, dispatcher) = await run(hops: 2)
        XCTAssertEqual(dispatcher.executed, 2, "两次相同调用是正常行为，不许提前掐")
    }
}
