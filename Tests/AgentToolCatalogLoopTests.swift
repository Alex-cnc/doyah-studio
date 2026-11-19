import XCTest
@testable import DoyahCore

/// **工具目录唯一真源 · 循环级判据**（详设 §3.22 · `FR-AGT-CORE-LOOP-005` / `-011` · 计划 P1-10）。
///
/// 判的是**循环实际发出去的请求**与**实际回灌的拒绝理由** —— 不是 `AgentToolCatalog` 的返回值。
/// 2026-11-18 实测：`AgentToolCatalogSnapshot` 全仓零生产侧引用（类写完、测试绿、没人调）。
final class AgentToolCatalogLoopTests: XCTestCase {

    /// 第一跳按脚本调用给定工具，第二跳收尾。
    private final class ScriptedClient: LLMStreamingClient, @unchecked Sendable {
        private let lock = NSLock()
        private var hops = 0
        private let toolName: String
        private(set) var seenTools: [[String]] = []

        init(toolName: String) { self.toolName = toolName }

        func stream(_ request: LLMRequest) async throws -> AsyncThrowingStream<LLMStreamEvent, Error> {
            lock.lock(); hops += 1; let hop = hops
            seenTools.append((request.tools ?? []).map { $0.name }); lock.unlock()
            return AsyncThrowingStream { continuation in
                if hop == 1 {
                    continuation.yield(.toolCallDelta(index: 0, id: "c0", name: self.toolName,
                                                     argumentsFragment: "{\"path\":\"a.txt\"}"))
                } else {
                    continuation.yield(.textDelta("好。"))
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

    private func makeCatalog(hidden: Set<String> = [],
                             visibleIn: AgentProfileKind = .terminalShell) throws -> AgentToolCatalog {
        try AgentToolCatalog(registry: .standard,
                             visibility: [visibleIn: Set(AgentToolRegistry.standard.enabledTools
                                                            .map(\.name)).subtracting(hidden)])
    }

    private func run(toolName: String,
                     catalog: AgentToolCatalog?,
                     profile: AgentProfileKind = .terminalShell) async -> (AgentLoopResult, ScriptedClient) {
        let client = ScriptedClient(toolName: toolName)
        var loop = AgentLoop(client: client, dispatcher: StubDispatcher(),
                             registry: .standard, sessionStore: nil)
        loop.toolCatalog = catalog
        loop.agentProfile = profile
        let context = AgentLoopContext(
            systemPrompt: "s", userPrompt: "读 a.txt",
            baseRequest: LLMRequest(endpoint: URL(string: "http://127.0.0.1:11434/v1")!,
                                    model: "m", systemPrompt: "", userPrompt: ""),
            sessionID: "sess-catalog", workspace: "/tmp")
        let result = await loop.run(context: context)
        return (result, client)
    }

    /// `T-3.22-02`：**不可见 ≠ 不存在** —— 两种拒绝理由必须不同，且请求里根本不该出现不可见的工具。
    func testHiddenToolIsNeitherAdvertisedNorConfusedWithUnknown() async throws {
        let catalog = try makeCatalog(hidden: ["read_file"])

        let (hiddenResult, hiddenClient) = await run(toolName: "read_file", catalog: catalog)
        XCTAssertFalse(hiddenClient.seenTools.first?.contains("read_file") ?? true,
                       "不可见的工具不该出现在请求的工具表里（§3.22：可见性由 profile 决定）")
        XCTAssertTrue(hiddenClient.seenTools.first?.contains("write_file") ?? false,
                      "可见的工具要照常带上（别把整张表都砍了）")
        XCTAssertEqual(hiddenResult.rejectedTools.first?.reason,
                       AgentToolRefusal.notVisibleInProfile.rawValue,
                       "已登记但不可见 ⇒ 必须报「不可见」，不是「没登记」")

        let (unknownResult, _) = await run(toolName: "no_such_tool", catalog: catalog)
        XCTAssertEqual(unknownResult.rejectedTools.first?.reason,
                       AgentToolRefusal.unregistered.rawValue,
                       "没登记 ⇒ 报「没登记」")
    }

    /// `T-3.22-01`（循环侧）：同名两处声明 ⇒ 装载期直接抛，不停在半装状态里跑。
    func testDuplicateDeclarationStopsLoading() throws {
        let doubled = AgentToolRegistry(definitions: AgentToolRegistry.standard.definitions
            + [AgentToolRegistry.standard.definitions[0]])
        XCTAssertThrowsError(try AgentToolCatalog(registry: doubled)) { error in
            guard case let AgentToolCatalogError.duplicateDeclaration(name) = error else {
                return XCTFail("必须是 duplicateDeclaration，实际 = \(error)")
            }
            XCTAssertEqual(name, AgentToolRegistry.standard.definitions[0].name)
        }
    }

    /// `T-3.22-03`：同一工具在两个壳里指向**同一实现**（指纹相同），只是可见性可能不同。
    func testSameToolPointsToSameImplementationAcrossShells() throws {
        let catalog = try makeCatalog()
        let terminal = try catalog.resolve("read_file", for: .terminalShell).get()
        let graphical = try catalog.resolve("read_file", for: .graphicalShell).get()
        XCTAssertEqual(terminal.fingerprint, graphical.fingerprint,
                       "两个壳必须指向同一份实现（壳只决定看得见，不决定能力）")
        XCTAssertTrue(catalog.sharesImplementation("read_file", .terminalShell, .graphicalShell))
    }
}
