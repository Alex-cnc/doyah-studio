import XCTest
@testable import DoyahCore

/// **工具并行与保序 · 循环级接线**（`FR-AGT-CORE-LOOP-012`）。
///
/// 上面那一组判的是批次组件本身；这一组判**主循环真的这么跑** ——
/// 组件写对了但没接进循环，等于没做。
final class AgentToolBatchLoopTests: XCTestCase {

    /// 一拍里吐 N 条工具调用，下一拍给正文。
    private final class MultiCallClient: LLMStreamingClient, @unchecked Sendable {
        private let lock = NSLock()
        private var hops = 0
        private let calls: [(name: String, arguments: String)]
        init(calls: [(name: String, arguments: String)]) { self.calls = calls }

        func stream(_ request: LLMRequest) async throws -> AsyncThrowingStream<LLMStreamEvent, Error> {
            lock.lock(); hops += 1; let hop = hops; lock.unlock()
            return AsyncThrowingStream { continuation in
                if hop == 1 {
                    for (index, call) in self.calls.enumerated() {
                        continuation.yield(.toolCallDelta(index: index, id: "call-\(index)",
                                                          name: call.name, argumentsFragment: call.arguments))
                    }
                    continuation.yield(.done)
                } else {
                    continuation.yield(.textDelta("结论：三条都读过了。"))
                    continuation.yield(.done)
                }
                continuation.finish()
            }
        }
    }

    private actor ConcurrencyProbe {
        private var inFlight = 0
        private(set) var peak = 0
        func enter() { inFlight += 1; peak = max(peak, inFlight) }
        func leave() { inFlight -= 1 }
    }

    /// 记录并发度；只读故意慢（100ms），好让峰值暴露出来。
    private final class ProbeDispatcher: AgentToolDispatcher, @unchecked Sendable {
        let probe = ConcurrencyProbe()
        private let lock = NSLock()
        private(set) var executedNames: [String] = []
        private let delayNanos: UInt64
        init(delayNanos: UInt64 = 100_000_000) { self.delayNanos = delayNanos }

        func dispatch(_ invocation: AgentToolInvocation, approvals: Set<String>) -> AgentToolOutcome {
            lock.lock(); executedNames.append(invocation.name); lock.unlock()
            if invocation.name == "write_file" {
                return .needsApproval(AgentApprovalRequest(toolName: invocation.name,
                                                           fingerprint: "fp-\(invocation.argumentsJSON)",
                                                           payload: invocation.argumentsJSON,
                                                           baseDigest: "",
                                                           scope: ""))
            }
            return .file(AgentToolFileOutput(path: invocation.name, text: "ok",
                                             truncated: false, totalBytes: 2))
        }

        func dispatchAsync(_ invocation: AgentToolInvocation, approvals: Set<String>) async -> AgentToolOutcome {
            await probe.enter()
            try? await Task.sleep(nanoseconds: delayNanos)
            await probe.leave()
            return dispatch(invocation, approvals: approvals)
        }
    }

    private final class RecordingObserver: AgentLoopObserver, @unchecked Sendable {
        private let lock = NSLock()
        private(set) var started: [String] = []
        private(set) var finished: [(String, String)] = []

        func observe(_ event: AgentLoopEvent) async {
            if case .toolStarted(let name, _) = event { lock.lock(); started.append(name); lock.unlock() }
            if case .toolFinished(let name, let outcome, _) = event {
                lock.lock(); finished.append((name, outcome)); lock.unlock()
            }
        }
    }

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-batch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func run(calls: [(name: String, arguments: String)],
                     dispatcher: ProbeDispatcher,
                     observer: RecordingObserver) async -> AgentLoopResult {
        let loop = AgentLoop(client: MultiCallClient(calls: calls), dispatcher: dispatcher,
                             sessionStore: AgentSessionStore(directory: directory),
                             observer: observer)
        let context = AgentLoopContext(systemPrompt: "s", userPrompt: "读三个文件",
                                       baseRequest: LLMRequest(endpoint: URL(string: "http://127.0.0.1:11434/v1")!,
                                                               model: "m", systemPrompt: "", userPrompt: ""),
                                       sessionID: UUID().uuidString, workspace: directory.path)
        return await loop.run(context: context)
    }

    /// 判据 ①③：三条只读**同批并发**，且回灌顺序 = 调用顺序。
    func testThreeReadCallsRunConcurrentlyInCallOrder() async {
        for name in ["a.txt", "b.txt", "c.txt"] {
            try? "x".write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        let dispatcher = ProbeDispatcher()
        let observer = RecordingObserver()
        let result = await run(calls: [
            ("read_file", #"{"path":"a.txt"}"#),
            ("read_file", #"{"path":"b.txt"}"#),
            ("read_file", #"{"path":"c.txt"}"#),
        ], dispatcher: dispatcher, observer: observer)

        let peak = await dispatcher.probe.peak
        XCTAssertEqual(peak, 3, "三条只读必须同时在飞（峰值并发 \(peak)）——组件通了但循环没接线就会是 1")
        XCTAssertEqual(result.executedTools.compactMap { $0.argumentsJSON.contains("a.txt") ? "a" : $0.argumentsJSON.contains("b.txt") ? "b" : "c" },
                       ["a", "b", "c"], "回灌顺序必须等于调用顺序")
        XCTAssertEqual(observer.started.count, 3, "过程行三条，顺序即调用顺序")
        XCTAssertTrue(result.text.contains("结论"), "正文照常收尾：\(result.text)")
    }

    /// 判据 ②：写类不并行 —— `[读, 写, 读]` 分三段跑，峰值并发只能是 1。
    func testWriteCallSplitsTheBatchAndRunsSerially() async {
        try? "x".write(to: directory.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try? "x".write(to: directory.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        let dispatcher = ProbeDispatcher()
        let observer = RecordingObserver()
        _ = await run(calls: [
            ("read_file", #"{"path":"a.txt"}"#),
            ("write_file", #"{"path":"out.txt","content":"hi"}"#),
            ("read_file", #"{"path":"b.txt"}"#),
        ], dispatcher: dispatcher, observer: observer)

        let peak = await dispatcher.probe.peak
        XCTAssertEqual(peak, 1, "写类必须把批切开：峰值并发 \(peak) > 1 就意味着写与读同时飞了")
        let names = await dispatcher.executedNames
        XCTAssertEqual(names, ["read_file", "write_file", "read_file"], "执行顺序必须与调用顺序一致")
    }
}
