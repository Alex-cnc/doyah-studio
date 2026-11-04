import XCTest
@testable import DoyahCore

/// 「同一个查询不许一轮里反复做」的判据（`Core/AgentRepeatGuard.swift`）。
///
/// 由头（2026-11-04 真机 · QQ 派活那一轮）：13 分钟里 324 次工具调用，其中同一个文件被
/// `read_file` 读了 **18 次**、`list_dir Core` 14 次 —— 系统提示词第 5 条本来就写着
/// 「同一条不许重复第三次」（`Core/AgentSystemPrompt.swift:57`），但循环从不检查它。
final class AgentRepeatGuardTests: XCTestCase {

    func testThirdIdenticalReadIsRefusedAndTheReasonIsActionable() {
        let guardrail = AgentRepeatGuard()
        let t0 = Date()
        XCTAssertNil(guardrail.admit(capability: .readFile, tool: "read", arguments: #"{"path":"Core/A.swift"}"#, at: t0))
        XCTAssertNil(guardrail.admit(capability: .readFile, tool: "read", arguments: #"{"path":"Core/A.swift"}"#,
                                     at: t0.addingTimeInterval(5)))
        let denial = guardrail.admit(capability: .readFile, tool: "read", arguments: #"{"path":"Core/A.swift"}"#,
                                     at: t0.addingTimeInterval(9))
        let reason = try? XCTUnwrap(denial)
        XCTAssertNotNil(reason, "第三次必须拦下")
        XCTAssertTrue(reason?.contains("repeat-call") == true, reason ?? "-")
        XCTAssertTrue(reason?.contains("换个问法") == true, "回灌给模型的话要能照着做：\(reason ?? "-")")
    }

    func testSameToolWithDifferentArgumentsIsNotRepetition() {
        let guardrail = AgentRepeatGuard()
        let t0 = Date()
        XCTAssertNil(guardrail.admit(capability: .readFile, tool: "read", arguments: #"{"path":"A.swift"}"#, at: t0))
        XCTAssertNil(guardrail.admit(capability: .readFile, tool: "read", arguments: #"{"path":"B.swift"}"#, at: t0))
        XCTAssertNil(guardrail.admit(capability: .readFile, tool: "read", arguments: #"{"path":"C.swift"}"#, at: t0))
        XCTAssertNil(guardrail.admit(capability: .listDirectory, tool: "ls", arguments: #"{"path":"Core"}"#, at: t0))
    }

    func testArgumentKeyOrderAndWhitespaceDoNotHideRepetition() {
        let guardrail = AgentRepeatGuard()
        let t0 = Date()
        XCTAssertNil(guardrail.admit(capability: .search, tool: "find", arguments: #"{"query":"qq","limit":40}"#, at: t0))
        XCTAssertNil(guardrail.admit(capability: .search, tool: "find", arguments: #"{ "limit" : 40 , "query" : "qq" }"#,
                                     at: t0))
        XCTAssertNotNil(guardrail.admit(capability: .search, tool: "find", arguments: #"{"limit":40,"query":"qq"}"#, at: t0),
                        "同一条查询只是键序 / 空格不同 ⇒ 仍是同一条")
    }

    func testWritingClearsTheLedgerSoReadAfterWriteStillWorks() {
        let guardrail = AgentRepeatGuard()
        let t0 = Date()
        XCTAssertNil(guardrail.admit(capability: .readFile, tool: "read", arguments: #"{"path":"A.swift"}"#, at: t0))
        XCTAssertNil(guardrail.admit(capability: .readFile, tool: "read", arguments: #"{"path":"A.swift"}"#, at: t0))
        // 写完再看一眼是正当行为：写类出现即清账。
        XCTAssertNil(guardrail.admit(capability: .writeFile, tool: "write", arguments: #"{"path":"A.swift","content":"x"}"#,
                                     at: t0))
        XCTAssertNil(guardrail.admit(capability: .readFile, tool: "read", arguments: #"{"path":"A.swift"}"#, at: t0),
                     "写完再读不许被这道闸误挡")
        // `run_command` 一样清账（它可能改了磁盘）。
        XCTAssertNil(guardrail.admit(capability: .readFile, tool: "read", arguments: #"{"path":"A.swift"}"#, at: t0))
        XCTAssertNil(guardrail.admit(capability: .runCommand, tool: "run", arguments: #"{"command":"swift build"}"#, at: t0))
        XCTAssertNil(guardrail.admit(capability: .readFile, tool: "read", arguments: #"{"path":"A.swift"}"#, at: t0))
    }

    func testWindowExpiryResetsTheCount() {
        let guardrail = AgentRepeatGuard(policy: .init(window: 60, limit: 2))
        let t0 = Date()
        XCTAssertNil(guardrail.admit(capability: .listDirectory, tool: "ls", arguments: #"{"path":"."}"#, at: t0))
        XCTAssertNil(guardrail.admit(capability: .listDirectory, tool: "ls", arguments: #"{"path":"."}"#, at: t0.addingTimeInterval(10)))
        XCTAssertNotNil(guardrail.admit(capability: .listDirectory, tool: "ls", arguments: #"{"path":"."}"#, at: t0.addingTimeInterval(20)),
                        "窗口内第三次：拦")
        XCTAssertNil(guardrail.admit(capability: .listDirectory, tool: "ls", arguments: #"{"path":"."}"#,
                                     at: t0.addingTimeInterval(120)),
                     "过了窗口就是新的一次（不许永久禁用某个路径）")
    }

    func testOtherToolsAreNeverBlocked() {
        let guardrail = AgentRepeatGuard()
        let t0 = Date()
        for _ in 0..<5 {
            XCTAssertNil(guardrail.admit(capability: .dispatchSubtasks, tool: "fanout", arguments: "{}", at: t0))
        }
    }

    /// 接线锚点：分发器真的问了这道闸（只加类型不接上 = 一行都不生效）。
    func testDispatcherConsultsTheGuard() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let dispatcher = try String(contentsOf: root.appendingPathComponent("Core/AgentStandardDispatcher.swift"),
                                    encoding: .utf8)
        XCTAssertTrue(dispatcher.contains("repeatGuard.admit("), "分发器必须真问这道闸")
        let app = try String(contentsOf: root.appendingPathComponent("App/AppState.swift"), encoding: .utf8)
        XCTAssertTrue(app.contains("repeatGuard: AgentRepeatGuard()"),
                      "产品那条路要装上闸（每轮一份账本）")
    }
}
