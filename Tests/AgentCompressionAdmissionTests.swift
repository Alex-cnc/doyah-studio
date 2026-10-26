import XCTest
@testable import DoyahCore

/// 详设 §3.21 的三条用例：`T-3.21-01`（回合内不压）· `T-3.21-02`（边界压且保留决策）·
/// `T-3.21-03`（压完仍超限如实报）。外加错误契约与幂等两条。
final class AgentCompressionAdmissionTests: XCTestCase {

    // MARK: T-3.21-01 回合内不压

    func testInTurnOnlyDefers() {
        let admission = AgentContextCompression.admit(
            at: .userCompact, inTurn: true,
            tokensBefore: 300_000, tokenLimit: 262_144, estimatedAfter: 120_000,
            engineAvailable: true
        )
        guard case .deferToBoundary(let next, _) = admission else {
            return XCTFail("回合内必须是 deferToBoundary，实际 \(admission)")
        }
        XCTAssertEqual(next, .userCompact)
        XCTAssertNotEqual(admission, .runNow(boundary: .userCompact,
                                             product: AgentCompressionProduct(boundary: .userCompact,
                                                                              tokensBefore: 0, tokensAfter: 0,
                                                                              decisionsKept: [], droppedKinds: [],
                                                                              marker: "")))
    }

    func testInTurnCarriesBudgetReport() {
        let budget = AgentBudgetReport(kind: .tokens, limit: 262_144, steps: 40,
                                       executedToolCount: 61, rejectedToolCount: 2,
                                       tokensSpent: 262_144, tokenLimit: 262_144)
        let admission = AgentContextCompression.admit(
            at: nil, inTurn: true, tokensBefore: 262_144, tokenLimit: 262_144,
            estimatedAfter: nil, engineAvailable: true, budget: budget
        )
        guard case .deferToBoundary(_, let carried) = admission else {
            return XCTFail("回合内必须带预算报告")
        }
        XCTAssertEqual(carried, budget)
    }

    // MARK: T-3.21-02 边界压且保留决策

    func testBoundaryCompressionKeepsDecisions() {
        let admission = AgentContextCompression.admit(
            at: .beforeSessionEnd, inTurn: false,
            tokensBefore: 240_000, tokenLimit: 262_144, estimatedAfter: 90_000,
            engineAvailable: true,
            decisionsKept: ["只读模式", "不许改 Vendor/"],
            droppedKinds: [.verboseBody, .repeatedToolResults],
            marker: "[已压缩 2 类]"
        )
        guard case .runNow(let boundary, let product) = admission else {
            return XCTFail("边界上应当压缩，实际 \(admission)")
        }
        XCTAssertEqual(boundary, .beforeSessionEnd)
        XCTAssertEqual(product.decisionsKept, ["只读模式", "不许改 Vendor/"])
        XCTAssertEqual(product.droppedKinds, [.verboseBody, .repeatedToolResults])
        XCTAssertEqual(product.tokensBefore, 240_000)
        XCTAssertEqual(product.tokensAfter, 90_000)
        XCTAssertEqual(product.marker, "[已压缩 2 类]")
    }

    // MARK: T-3.21-03 压完仍超限如实报

    func testStillOverLimitIsRefusedNotTruncated() {
        let admission = AgentContextCompression.admit(
            at: .beforeSession, inTurn: false,
            tokensBefore: 400_000, tokenLimit: 262_144, estimatedAfter: 300_000,
            engineAvailable: true
        )
        XCTAssertEqual(admission, .refuse(reason: .stillOverLimit(before: 400_000, after: 300_000)))
    }

    // MARK: 错误契约

    func testNoEngineSkipsHonestly() {
        let admission = AgentContextCompression.admit(
            at: .beforeSession, inTurn: false, tokensBefore: 10, tokenLimit: 100,
            estimatedAfter: 5, engineAvailable: false
        )
        XCTAssertEqual(admission, .skip(reason: .noEngine))
    }

    func testUnknownBoundarySkips() {
        let admission = AgentContextCompression.admit(
            at: nil, inTurn: false, tokensBefore: 10, tokenLimit: 100, estimatedAfter: 5,
            engineAvailable: true
        )
        XCTAssertEqual(admission, .skip(reason: .boundaryUnknown))
    }

    func testNextBoundaryPrefersSessionEndWhenClosing() {
        XCTAssertEqual(AgentContextCompression.nextBoundary(after: .beforeSessionEnd), .beforeSessionEnd)
        XCTAssertEqual(AgentContextCompression.nextBoundary(after: .gatewayExpiry), .beforeSessionEnd)
        XCTAssertEqual(AgentContextCompression.nextBoundary(after: .beforeSession), .userCompact)
        XCTAssertEqual(AgentContextCompression.nextBoundary(after: nil), .userCompact)
    }

    // MARK: 幂等

    func testSameBoundaryIsIdempotent() {
        var ledger = AgentCompressionLedger()
        let first = AgentContextCompression.admit(at: .userCompact, inTurn: false,
                                                  tokensBefore: 100, tokenLimit: 1000,
                                                  estimatedAfter: 40, engineAvailable: true)
        let second = AgentContextCompression.admit(at: .userCompact, inTurn: false,
                                                   tokensBefore: 999, tokenLimit: 1000,
                                                   estimatedAfter: 900, engineAvailable: true)
        let recordedFirst = ledger.record(first, sessionID: "S", boundary: .userCompact)
        let recordedSecond = ledger.record(second, sessionID: "S", boundary: .userCompact)
        XCTAssertEqual(recordedFirst, first)
        XCTAssertEqual(recordedSecond, first, "同一 (session, boundary) 重复调用必须返回首次结局")
    }
}
