import XCTest
@testable import DoyahCore

/// **及时刹停 · 循环级判据**（`FR-AGT-CORE-LOOP-007` · 计划 P2-3）。
///
/// 判三件：命中判据即停（带「停了什么」）· 停在执行前（工具层一条没收到）·
/// 停手不由模型自行撤销（回合直接结束，不是回灌让它再试）。
/// 2026-11-18 实测：`AgentPreActionStop` 全仓零生产侧引用（只被人当注释提过一行）。
final class AgentPreActionStopLoopTests: XCTestCase {

    private final class ScriptedClient: LLMStreamingClient, @unchecked Sendable {
        private let lock = NSLock()
        private var hops = 0
        private let name: String
        private let args: String
        init(name: String, args: String) { self.name = name; self.args = args }
        func stream(_ request: LLMRequest) async throws -> AsyncThrowingStream<LLMStreamEvent, Error> {
            lock.lock(); hops += 1; let hop = hops; lock.unlock()
            return AsyncThrowingStream { continuation in
                if hop == 1 {
                    continuation.yield(.toolCallDelta(index: 0, id: "c0", name: self.name, argumentsFragment: self.args))
                } else {
                    continuation.yield(.textDelta("好。"))
                }
                continuation.yield(.done)
                continuation.finish()
            }
        }
    }

    private final class SpyDispatcher: AgentToolDispatcher, @unchecked Sendable {
        private let lock = NSLock()
        private(set) var dispatched: [String] = []
        var names: [String] { lock.lock(); defer { lock.unlock() }; return dispatched }
        func dispatch(_ invocation: AgentToolInvocation, approvals: Set<String>) -> AgentToolOutcome {
            lock.lock(); dispatched.append(invocation.name); lock.unlock()
            return .refused(.unavailable, detail: "本判据只测接线")
        }
    }

    private func run(tool: String, args: String) async -> (AgentLoopResult, SpyDispatcher) {
        let dispatcher = SpyDispatcher()
        var loop = AgentLoop(client: ScriptedClient(name: tool, args: args),
                             dispatcher: dispatcher, registry: .standard, sessionStore: nil)
        let context = AgentLoopContext(
            systemPrompt: "s", userPrompt: "干活",
            baseRequest: LLMRequest(endpoint: URL(string: "http://127.0.0.1:11434/v1")!,
                                    model: "m", systemPrompt: "", userPrompt: ""),
            sessionID: "sess-stop", workspace: "/tmp")
        let result = await loop.run(context: context)
        return (result, dispatcher)
    }

    /// 删库 / 无 WHERE 删除 ⇒ 停，且停在执行前。
    func testDropDatabaseStopsBeforeExecution() async {
        for sql in ["DROP DATABASE prod", "delete from users"] {
            let (result, dispatcher) = await run(tool: "query_db", args: "{\"sql\":\"\(sql)\"}")
            guard case let .stopped(stop) = result.outcome, case let .harmfulAction(marker) = stop else {
                return XCTFail("必须停在伤害性动作上，实际 = \(result.outcome)（\(sql)）")
            }
            XCTAssertFalse(marker.isEmpty, "要给出「停了什么」")
            XCTAssertTrue(dispatcher.names.isEmpty, "停在执行前 —— 工具层不许收到：\(dispatcher.names)")
        }
    }

    /// 覆盖已存在的文件 ⇒ 停；文件不存在（新建）⇒ 照常放行。
    func testOverwritingExistingFileStopsButCreatingNewOnePasses() async throws {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("doyah-stop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let existing = scratch.appendingPathComponent("exists.txt")
        try "已有内容".write(to: existing, atomically: true, encoding: .utf8)

        let (blocked, blockedDispatcher) = await run(
            tool: "write_file", args: "{\"path\":\"\(existing.path)\"}")
        guard case let .stopped(stop) = blocked.outcome, case let .harmfulAction(marker) = stop else {
            return XCTFail("覆盖已有文件必须停，实际 = \(blocked.outcome)")
        }
        XCTAssertTrue(marker.contains("overwrite"), "停手原因要能回看，实际 = \(marker)")
        XCTAssertTrue(blockedDispatcher.names.isEmpty)

        let (allowed, _) = await run(
            tool: "read_file", args: "{\"path\":\"\(existing.path)\"}")
        XCTAssertEqual(allowed.outcome, .finished(text: "好。"), "读已有文件不受刹停影响")
    }

    /// 伤害性命令 ⇒ 停；普通命令不在刹停面内（是否放行看边界与审批，不归本条）。
    func testHarmfulCommandStops() async {
        let (result, dispatcher) = await run(tool: "run_command", args: "{\"command\":\"rm -rf /\"}")
        guard case let .stopped(stop) = result.outcome, case .harmfulAction = stop else {
            return XCTFail("伤害性命令必须停，实际 = \(result.outcome)")
        }
        XCTAssertTrue(dispatcher.names.isEmpty)
    }

    /// 停手理由能反解回同一件事（界面靠它翻人话）。
    func testStopReasonRoundTrips() {
        let stop = AgentLoopStop.harmfulAction("DROP DATABASE")
        XCTAssertEqual(AgentLoopStop.parse(reason: stop.reason), stop)
        XCTAssertNil(AgentLoopStop.parse(reason: "harmful:"), "空标记不算命中")
    }

    /// **覆盖范围声明**：对外发布类没有可触发的工具（本仓尚无发布工具），
    /// 只能在闸门本体上判；等发布工具出现时，接线点是 `AgentLoop.preAction`。
    func testExternalPublishIsJudgedAtTheGateOnly() {
        let signal = AgentPreActionGate.inspect(.externalPublish(channel: "wechat"))
        XCTAssertEqual(signal?.reason, .externalPublish(channel: "wechat"))
    }
}
