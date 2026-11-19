import XCTest
@testable import DoyahCore

/// **运行时边界 · 循环级判据**（`FR-AGT-GUARD-PERM-003` · 计划 P2-2）。
///
/// 「任何执行都在受限环境内」—— 判的是**分发之前**有没有拦住，不是 `AgentSandboxBoundary`
/// 的返回值。2026-11-18 实测：`AgentSandboxBoundary` 全仓零生产侧引用（类+测试都有，没人调）。
final class AgentSandboxLoopTests: XCTestCase {

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

    /// 记下**真的被分发**的调用 —— 被拦的必须一条都不进来。
    private final class SpyDispatcher: AgentToolDispatcher, @unchecked Sendable {
        private let lock = NSLock()
        private(set) var dispatched: [String] = []
        var names: [String] { lock.lock(); defer { lock.unlock() }; return dispatched }
        func dispatch(_ invocation: AgentToolInvocation, approvals: Set<String>) -> AgentToolOutcome {
            lock.lock(); dispatched.append(invocation.name); lock.unlock()
            return .file(AgentToolFileOutput(path: "x", text: "内容", truncated: false, totalBytes: 6))
        }
    }

    private let root = "/tmp/sandbox-root"

    private func boundary(level: AgentPermissionLevel = .scoped,
                          allowsWrite: Bool = true) -> AgentSandboxBoundary {
        AgentSandboxBoundary(
            config: AgentPermissionConfig(level: level,
                                          roots: [AgentSandboxRoot(path: root, allowsWrite: allowsWrite)],
                                          commands: []),
            rootExists: { _ in true })   // 判据注入假根：本机没有这个目录也要能判
    }

    private func run(tool: String, args: String,
                     sandbox: AgentSandboxBoundary?) async -> (AgentLoopResult, SpyDispatcher) {
        let dispatcher = SpyDispatcher()
        var loop = AgentLoop(client: ScriptedClient(name: tool, args: args),
                             dispatcher: dispatcher, registry: .standard, sessionStore: nil)
        loop.sandbox = sandbox
        let context = AgentLoopContext(
            systemPrompt: "s", userPrompt: "干活",
            baseRequest: LLMRequest(endpoint: URL(string: "http://127.0.0.1:11434/v1")!,
                                    model: "m", systemPrompt: "", userPrompt: ""),
            sessionID: "sess-sandbox", workspace: root)
        let result = await loop.run(context: context)
        return (result, dispatcher)
    }

    /// 越界路径（含 `..` 逃逸）⇒ 分发前就拒，模型拿到的理由是「出界」。
    func testPathOutsideRootsIsRefusedBeforeDispatch() async {
        for escape in ["/etc/passwd", "\(root)/../../etc/passwd"] {
            let (result, dispatcher) = await run(
                tool: "read_file", args: "{\"path\":\"\(escape)\"}", sandbox: boundary())
            XCTAssertEqual(result.rejectedTools.first?.reason,
                           AgentToolRefusal.outsideWorkspace.rawValue,
                           "越界路径必须报「出界」：\(escape)")
            XCTAssertTrue(dispatcher.names.isEmpty,
                          "被拦的调用不许分发到工具层：\(escape) → \(dispatcher.names)")
        }
    }

    /// 只读根上写 ⇒ 拒，理由是「策略不许」（与「出界」是两条信息）。
    func testWriteOnReadOnlyRootIsRefusedByPolicy() async {
        let (result, dispatcher) = await run(
            tool: "write_file", args: "{\"path\":\"\(root)/a.txt\"}",
            sandbox: boundary(level: .readOnly, allowsWrite: false))
        XCTAssertEqual(result.rejectedTools.first?.reason,
                       AgentToolRefusal.deniedByPolicy.rawValue)
        XCTAssertTrue(dispatcher.names.isEmpty, "只读根上的写不许落到工具层")

        let (readResult, readDispatcher) = await run(
            tool: "read_file", args: "{\"path\":\"\(root)/a.txt\"}",
            sandbox: boundary(level: .readOnly, allowsWrite: false))
        XCTAssertTrue(readResult.rejectedTools.isEmpty, "只读根上**读**要照常放行")
        XCTAssertEqual(readDispatcher.names, ["read_file"])
    }

    /// 根内读写照常；不给边界 ⇒ 旧行为（不被拦）。
    func testInsideRootPassesAndNoSandboxKeepsOldBehaviour() async {
        // 根内**读**照常执行（写要走审批，审批不在本判据的判定面里 —— 只判「边界放不放行」）。
        let (inside, insideDispatcher) = await run(
            tool: "read_file", args: "{\"path\":\"\(root)/a.txt\"}", sandbox: boundary())
        XCTAssertTrue(inside.rejectedTools.isEmpty, "根内读取必须放行，实际 = \(inside.rejectedTools)")
        XCTAssertEqual(insideDispatcher.names, ["read_file"])

        let (legacy, legacyDispatcher) = await run(
            tool: "read_file", args: "{\"path\":\"/etc/passwd\"}", sandbox: nil)
        XCTAssertTrue(legacy.rejectedTools.isEmpty, "不给边界 = 旧行为逐字不变")
        XCTAssertEqual(legacyDispatcher.names, ["read_file"])
    }
}
