import XCTest
@testable import DoyahCore

/// **空跳兜底**（2026-11-11 真机 · QQ 通道）。
///
/// 现场：主人从手机发一条测试消息，桌面面板上什么都没发生，回话是
/// 「Could not start this run: this run finished but produced no readable text
/// (the steps are on the desktop pane). No result to report.」
/// 日志同一时刻只留一行：`IM 跑一轮跑完但没有正文 步数=0`。
///
/// 根因：模型那一跳既没有正文、也没有工具调用（内容与思考分离的端点上见过：
/// `content` 空、`reasoning_content` 有料）。旧行为把它当成「答完了」直接收尾。
///
/// 判据三条（每条都配了会判红的负例形态）：
/// ① 第一次空跳 ⇒ **再要一次**，第二次给了正文就按正文收尾（步数 = 2）；
/// ② 连着空跳也只催一次，不许无限重来（第二次仍空 ⇒ 收尾，步数仍是 2）；
/// ③ 有正文的那一跳不受影响（不因为兜底多调一次模型）。
final class AgentLoopHollowTurnTests: XCTestCase {

    private final class ScriptedClient: LLMStreamingClient, @unchecked Sendable {
        private var hops: [[LLMStreamEvent]]
        private let lock = NSLock()
        private(set) var calls = 0
        init(_ hops: [[LLMStreamEvent]]) { self.hops = hops }
        func stream(_ request: LLMRequest) async throws -> AsyncThrowingStream<LLMStreamEvent, Error> {
            lock.lock()
            calls += 1
            let events = hops.isEmpty ? [.textDelta("（用尽）"), .done] : hops.removeFirst()
            lock.unlock()
            return AsyncThrowingStream { continuation in
                for event in events { continuation.yield(event) }
                continuation.finish()
            }
        }
    }

    private final class QuietDispatcher: AgentToolDispatcher, @unchecked Sendable {
        func dispatch(_ invocation: AgentToolInvocation, approvals: Set<String>) -> AgentToolOutcome {
            .file(AgentToolFileOutput(path: "a.txt", text: "", truncated: false, totalBytes: 0))
        }
    }

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-hollow-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func run(_ client: ScriptedClient) async -> AgentLoopResult {
        let loop = AgentLoop(client: client, dispatcher: QuietDispatcher(),
                             sessionStore: AgentSessionStore(directory: directory))
        let context = AgentLoopContext(systemPrompt: "s", userPrompt: "报个平安",
                                       baseRequest: LLMRequest(endpoint: URL(string: "http://127.0.0.1:11434/v1")!,
                                                               model: "m", systemPrompt: "", userPrompt: ""),
                                       sessionID: "s-hollow", workspace: "ws")
        return await loop.run(context: context)
    }

    /// ① 空一跳 → 补催一次 → 拿到正文
    func testEmptyHopIsRetriedOnceAndThenAnswers() async {
        let client = ScriptedClient([
            [.finished(reason: "stop"), .done],                       // 空跳：没有正文、没有工具
            [.textDelta("结论：一切正常。"), .finished(reason: "stop"), .done],
        ])
        let result = await run(client)
        XCTAssertEqual(result.text.trimmingCharacters(in: .whitespacesAndNewlines), "结论：一切正常。",
                       "补催之后应把正文收下来")
        XCTAssertEqual(result.steps, 2, "只许多出一跳：空跳 1 + 补催 1")
    }

    /// ② 连着空也只催一次（负例：无上限就会出现「模型一直不说话、程序一直重试」）
    func testTwoEmptyHopsDoNotLoopForever() async {
        let client = ScriptedClient([
            [.finished(reason: "stop"), .done],
            [.finished(reason: "stop"), .done],
            [.textDelta("第三次才说话"), .finished(reason: "stop"), .done],
        ])
        let result = await run(client)
        XCTAssertEqual(result.steps, 2, "催过一次仍空 ⇒ 收尾，不许再要第三次")
        XCTAssertEqual(result.text.trimmingCharacters(in: .whitespacesAndNewlines), "",
                       "没有正文就如实是空，不许拿上一跳的残留充数")
    }

    /// ③ 正常答复不该被兜底影响（不多调一次模型）
    func testNormalAnswerIsNotRetried() async {
        let client = ScriptedClient([
            [.textDelta("直接就有正文。"), .finished(reason: "stop"), .done],
        ])
        let result = await run(client)
        XCTAssertEqual(result.steps, 1)
        XCTAssertEqual(result.text, "直接就有正文。")
        XCTAssertEqual(client.calls, 1, "有正文时只调一次模型")
    }
}
