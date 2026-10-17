import XCTest
@testable import DoyahCore

/// 授权粒度（`FR-AI-34`）：**任务范围内代签 · 受保护路径转人工 · 超上限转人工 · 可回到逐次批**。
///
/// 由头（人类主人 2026-10-17 原话）：「我说一句 Agent 执行一句，我被完全绑架了」。
final class AgentTaskScopeTests: XCTestCase {

    // MARK: - 纯判据

    func testScopeApprovesOrdinaryWriteInsideTask() {
        let verdict = AgentScopeGate.judge(tool: "write_file", preview: "Sources/a.swift",
                                           autoApprovedCount: 0, scope: .default)
        XCTAssertEqual(verdict, .autoApproved(reason: "task-scope:write_file"))
    }

    func testProtectedPathsAlwaysGoToHuman() {
        for preview in [".git/config", ".secrets/credentials.json", "Package.swift",
                        "Scripts/build-app.sh", ".doyah/soul-role.md"] {
            if case .needsHuman(let reason) = AgentScopeGate.judge(tool: "write_file", preview: preview,
                                                                  autoApprovedCount: 0, scope: .default) {
                XCTAssertTrue(reason.hasPrefix("protected:"), "受保护路径的理由要说清命中了哪条：\(reason)")
            } else {
                XCTFail("受保护路径必须转人工：\(preview)")
            }
        }
    }

    func testOverLimitGoesToHuman() {
        let scope = AgentTaskScope(mode: .taskScope, maxAutoApprovals: 3)
        XCTAssertEqual(AgentScopeGate.judge(tool: "write_file", preview: "a", autoApprovedCount: 2, scope: scope),
                       .autoApproved(reason: "task-scope:write_file"))
        XCTAssertEqual(AgentScopeGate.judge(tool: "write_file", preview: "a", autoApprovedCount: 3, scope: scope),
                       .needsHuman(reason: "over-auto-approval-limit"))
    }

    func testAskEachActionModeStillAsksEveryTime() {
        XCTAssertEqual(AgentScopeGate.judge(tool: "write_file", preview: "a", autoApprovedCount: 0, scope: .askEach),
                       .needsHuman(reason: "askEachAction"))
    }

    // MARK: - 与聊天状态机合起来（代签必须可见可审）

    func testChatStateAutoApprovesAndRecordsWhy() {
        var state = AgentChatState()
        state.taskScope = .default
        state.requestApproval(name: "write_file", fingerprint: "fp-1", preview: "Sources/a.swift")

        XCTAssertEqual(state.autoApprovals.count, 1, "代签要留一条记录")
        XCTAssertEqual(state.autoApprovals.first?.reason, "task-scope:write_file")
        XCTAssertTrue(state.grants.contains("fp-1"), "代签 = 按次授权已给（否则执行时会被拒）")
        guard let card = state.cards.last else { return XCTFail("卡片必须建出来（可见）") }
        if case .approved(let fingerprint, _) = card.outcome {
            XCTAssertEqual(fingerprint, "fp-1")
        } else {
            XCTFail("代签的卡片应直接是已批态，实际：\(card.outcome)")
        }
    }

    func testChatStateAsksHumanForProtectedPathAndDoesNotRecordAutoApproval() {
        var state = AgentChatState()
        state.taskScope = .default
        state.requestApproval(name: "write_file", fingerprint: "fp-2", preview: ".git/config")

        XCTAssertTrue(state.autoApprovals.isEmpty, "受保护路径不许代签")
        XCTAssertFalse(state.grants.contains("fp-2"))
        guard let card = state.cards.last else { return XCTFail("卡片必须建出来") }
        if case .pendingApproval = card.outcome {} else { XCTFail("应停在待批：\(card.outcome)") }
    }

    func testAskEachModeKeepsEveryActionPending() {
        var state = AgentChatState()
        state.taskScope = .askEach
        state.requestApproval(name: "run_command", fingerprint: "fp-3", preview: "npm test")
        XCTAssertTrue(state.autoApprovals.isEmpty)
        guard let card = state.cards.last else { return XCTFail("卡片必须建出来") }
        if case .pendingApproval = card.outcome {} else { XCTFail("逐次批模式下必须待批") }
    }
}
