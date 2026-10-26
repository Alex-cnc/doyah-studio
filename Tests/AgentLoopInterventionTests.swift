import XCTest
@testable import DoyahCore

/// `FR-AGT-UX-CONV-007` 的**循环级**判据：干预在当前步之后生效，且不丢已产生结果。
final class AgentLoopInterventionTests: XCTestCase {

    private final class ScriptedClient: LLMStreamingClient, @unchecked Sendable {
        var hops: [[LLMStreamEvent]]
        private(set) var requests: [LLMRequest] = []
        init(_ hops: [[LLMStreamEvent]]) { self.hops = hops }
        func stream(_ request: LLMRequest) async throws -> AsyncThrowingStream<LLMStreamEvent, Error> {
            requests.append(request)
            let events = hops.isEmpty ? [.textDelta("done"), .done] : hops.removeFirst()
            return AsyncThrowingStream { c in
                for e in events { c.yield(e) }
                c.finish()
            }
        }
    }

    private final class RecordingDispatcher: AgentToolDispatcher, @unchecked Sendable {
        private(set) var invoked: [AgentToolInvocation] = []
        func dispatch(_ invocation: AgentToolInvocation, approvals: Set<String>) -> AgentToolOutcome {
            invoked.append(invocation)
            return .file(AgentToolFileOutput(path: "a.txt", text: "内容", truncated: false, totalBytes: 6))
        }
    }

    private func context() -> AgentLoopContext {
        AgentLoopContext(systemPrompt: "你是助手。", userPrompt: "读 a.txt",
                         baseRequest: LLMRequest(endpoint: URL(string: "http://127.0.0.1:11434/v1")!,
                                                 model: "fake", systemPrompt: "", userPrompt: ""),
                         sessionID: "s-int", workspace: "ws")
    }

    private func toolHop(_ name: String) -> [LLMStreamEvent] {
        [.toolCallDelta(index: 0, id: "c-0", name: name, argumentsFragment: "{\"path\":\"a.txt\"}"),
         .finished(reason: "tool_calls"), .done]
    }

    func testStopInterventionHaltsAfterCurrentStepAndKeepsResults() async {
        let client = ScriptedClient([toolHop("read_file"), [.textDelta("不该走到这"), .done]])
        let dispatcher = RecordingDispatcher()
        let inbox = AgentInterventionInbox()
        var loop = AgentLoop(client: client, dispatcher: dispatcher)
        loop.interventionInbox = inbox
        inbox.enqueue(.stop(reason: "方向错了"), duringStep: 1)

        let result = await loop.run(context: context())
        XCTAssertEqual(result.outcome, .stopped(.cancelled))
        XCTAssertEqual(result.steps, 1, "停手后不许再起新跳")
        XCTAssertEqual(dispatcher.invoked.count, 1, "已完成的那一步结果不丢")
        XCTAssertEqual(client.requests.count, 1, "第二跳的请求不该发出去")
    }

    func testConstraintIsAppendedToNextHopSystemPrompt() async {
        let client = ScriptedClient([toolHop("read_file"), [.textDelta("好"), .done]])
        let dispatcher = RecordingDispatcher()
        let inbox = AgentInterventionInbox()
        var loop = AgentLoop(client: client, dispatcher: dispatcher)
        loop.interventionInbox = inbox
        inbox.enqueue(.constraint(text: "只读"), duringStep: 1)

        _ = await loop.run(context: context())
        XCTAssertEqual(client.requests.count, 2, "约束不打断循环")
        let second = client.requests[1]
        XCTAssertTrue(second.systemPrompt.contains("只读"), "追加约束必须进下一跳的 systemPrompt")
    }

    func testRedirectReplacesNextHopUserPrompt() async {
        let client = ScriptedClient([toolHop("read_file"), [.textDelta("好"), .done]])
        let dispatcher = RecordingDispatcher()
        let inbox = AgentInterventionInbox()
        var loop = AgentLoop(client: client, dispatcher: dispatcher)
        loop.interventionInbox = inbox
        inbox.enqueue(.redirect(instruction: "先看配置"), duringStep: 1)

        _ = await loop.run(context: context())
        XCTAssertEqual(client.requests.count, 2)
        XCTAssertTrue(client.requests[1].userPrompt.contains("先看配置"), "下一跳的 userPrompt 已换成新方向（会带上工具结果）")
    }
}
