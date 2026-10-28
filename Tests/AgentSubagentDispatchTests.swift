import XCTest
@testable import DoyahCore

/// `FR-AGT-TOOL-SYS-002` 的**接线判据**：模型要派活 → 循环认领 → 子代理真跑 → 带来源回灌。
final class AgentSubagentDispatchTests: XCTestCase {

    /// 按提示词分脚本的假模型（父任务与每路子任务各说各的）。
    private final class ScriptedClient: LLMStreamingClient, @unchecked Sendable {
        private let lock = NSLock()
        private var script: [String: [[LLMStreamEvent]]] = [:]
        private(set) var calls: [String] = []
        private(set) var requests: [LLMRequest] = []

        func script(_ prompt: String, _ hops: [[LLMStreamEvent]]) {
            lock.lock(); script[prompt] = hops; lock.unlock()
        }

        func stream(_ request: LLMRequest) async throws -> AsyncThrowingStream<LLMStreamEvent, Error> {
            lock.lock()
            calls.append(request.userPrompt)
            requests.append(request)
            // 按**包含**匹配：父任务下一跳的 userPrompt 会被拼上观察，不再是原文
            let key = script.keys.first { request.userPrompt.contains($0) } ?? request.userPrompt
            var hops = script[key] ?? [[.textDelta("OK"), .finished(reason: "stop")]]
            let events = hops.count > 1 ? hops.removeFirst() : hops[0]
            script[key] = hops
            lock.unlock()
            return AsyncThrowingStream { continuation in
                for event in events { continuation.yield(event) }
                continuation.finish()
            }
        }

        var callCount: Int { lock.lock(); defer { lock.unlock() }; return calls.count }
        var callsSnapshot: [String] { lock.lock(); defer { lock.unlock() }; return calls }
    }

    /// 记一次调用就够：派子代理**不许**落到同步分发器上。
    private final class CountingDispatcher: AgentToolDispatcher, @unchecked Sendable {
        private let lock = NSLock()
        private(set) var dispatchCount = 0

        func dispatch(_ invocation: AgentToolInvocation, approvals: Set<String>) -> AgentToolOutcome {
            lock.lock(); dispatchCount += 1; lock.unlock()
            return .file(AgentToolFileOutput(path: invocation.name, text: "", truncated: false, totalBytes: 0))
        }
    }

    private func tasksJSON(_ entries: [(String, String, String)]) -> String {
        let array = entries.map { ["id": $0.0, "label": $0.1, "prompt": $0.2] }
        let inner = String(data: try! JSONSerialization.data(withJSONObject: array), encoding: .utf8)!
        let root = String(data: try! JSONSerialization.data(withJSONObject: ["tasks": inner]), encoding: .utf8)!
        return root
    }

    private func context(prompt: String, session: String = "parent-sess") -> AgentLoopContext {
        AgentLoopContext(systemPrompt: "系统", userPrompt: prompt,
                         baseRequest: LLMRequest(endpoint: URL(string: "http://127.0.0.1:1/v1")!,
                                                 model: "fake", systemPrompt: "", userPrompt: prompt),
                         sessionID: session, workspace: "ws")
    }

    // ① 登记在册（能力 / 等级 / 审批），且注入模型时只有一条
    func testRegistryCarriesTheCapability() {
        let registry = AgentToolRegistry.standard
        let definition = registry.definition(for: .dispatchSubtasks)
        XCTAssertEqual(definition?.name, "dispatch_subtasks")
        XCTAssertEqual(definition?.level, .executable)
        XCTAssertEqual(definition?.approval, .required)
        XCTAssertTrue(definition?.enabled ?? false)
        XCTAssertEqual(registry.enabledDefinitions.filter { $0.capability == .dispatchSubtasks }.count, 1)
    }

    // ② 宿主没给策略 ⇒ 如实拒 `unavailable`（不假装能派）
    func testWithoutPolicyItIsRefused() async {
        let client = ScriptedClient()
        client.script("主任务", [[
            .toolCallDelta(index: 0, id: "c1", name: "dispatch_subtasks",
                           argumentsFragment: tasksJSON([("a", "La", "做 a")])),
            .finished(reason: "tool_calls"),
        ], [.textDelta("停"), .finished(reason: "stop")]])
        let loop = AgentLoop(client: client, dispatcher: CountingDispatcher())
        let result = await loop.run(context: context(prompt: "主任务"))
        XCTAssertTrue(result.rejectedTools.contains { $0.1 == AgentToolRefusal.unavailable.rawValue })
    }

    // ③ **端到端**：父任务派两路 → 两路各自真跑 → 汇总带来源回灌 → 父任务收尾
    func testDispatchRunsSubtasksAndFeedsSummaryBack() async {
        let client = ScriptedClient()
        client.script("主任务", [[
            .toolCallDelta(index: 0, id: "c1", name: "dispatch_subtasks",
                           argumentsFragment: tasksJSON([("a", "La", "做 a"), ("b", "Lb", "做 b")])),
            .finished(reason: "tool_calls"),
        ], [.textDelta("都做完了"), .finished(reason: "stop")]])
        client.script("做 a", [[.textDelta("结论A"), .finished(reason: "stop")]])
        client.script("做 b", [[.textDelta("结论B"), .finished(reason: "stop")]])

        let dispatcher = CountingDispatcher()
        var loop = AgentLoop(client: client, dispatcher: dispatcher)
        loop.subagentPolicy = AgentSubagentPolicy(maxConcurrent: 2)
        let result = await loop.run(context: context(prompt: "主任务"))

        XCTAssertEqual(result.outcome, .finished(text: "都做完了"))
        XCTAssertEqual(result.executedTools.filter { $0.name == "dispatch_subtasks" }.count, 1)
        // 父 1 跳 + 两路各 1 跳 + 父收尾 1 跳 = 4 次请求（子代理是真跑循环，不是摆样子）
        XCTAssertEqual(client.callCount, 4)
        XCTAssertEqual(dispatcher.dispatchCount, 0, "派子代理不落同步分发器")
        // 汇总回到父任务的**下一跳请求**里：带人数与来源（模型真能看到）
        let lastPrompt = client.requests.last?.userPrompt ?? ""
        XCTAssertTrue(lastPrompt.contains("completed=2"), lastPrompt.suffix(200).description)
        XCTAssertTrue(lastPrompt.contains("La#a"), "来源标注要进回灌")
        XCTAssertTrue(lastPrompt.contains("Lb#b"), "两路都要标")
    }

    // ④ 深度只许一层：子会话里再派 ⇒ `subagentNesting`
    func testSubagentCannotDispatchAgain() async {
        let client = ScriptedClient()
        client.script("做 a", [[
            .toolCallDelta(index: 0, id: "c1", name: "dispatch_subtasks",
                           argumentsFragment: tasksJSON([("c", "Lc", "做 c")])),
            .finished(reason: "tool_calls"),
        ], [.textDelta("停"), .finished(reason: "stop")]])
        var loop = AgentLoop(client: client, dispatcher: CountingDispatcher())
        loop.subagentPolicy = AgentSubagentPolicy(maxConcurrent: 2)
        let result = await loop.run(context: context(prompt: "做 a", session: "parent-sess#sub-a"))
        XCTAssertTrue(result.rejectedTools.contains { $0.1 == AgentToolRefusal.subagentNesting.rawValue })
        XCTAssertEqual(client.callCount, 2, "只该有自己那两跳，不许真的派出第三路")
    }

    // ⑤ 参数解析不出来 ⇒ `badArguments`，不猜、不编提示词
    func testBadArgumentsAreRefused() async {
        let client = ScriptedClient()
        client.script("主任务", [[
            .toolCallDelta(index: 0, id: "c1", name: "dispatch_subtasks",
                           argumentsFragment: #"{"tasks":"不是 JSON"}"#),
            .finished(reason: "tool_calls"),
        ], [.textDelta("停"), .finished(reason: "stop")]])
        var loop = AgentLoop(client: client, dispatcher: CountingDispatcher())
        loop.subagentPolicy = AgentSubagentPolicy(maxConcurrent: 2)
        let result = await loop.run(context: context(prompt: "主任务"))
        XCTAssertTrue(result.rejectedTools.contains { $0.1 == AgentToolRefusal.badArguments.rawValue })
        XCTAssertEqual(client.callCount, 2, "拒了就停，不许再派")
    }
}
