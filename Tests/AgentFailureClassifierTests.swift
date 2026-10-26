import XCTest
@testable import DoyahCore

/// `FR-AGT-UX-CONV-004` 前半：失败三档（可重试 / 需人处理 / 不该重试）与各自处置。
final class AgentFailureClassifierTests: XCTestCase {
    private let classifier = AgentFailureClassifier()
    private let policy = LLMRetryPolicy(maxAttempts: 3, delays: [0.5, 2])

    func testTransportIsTransientWithBackoff() {
        let verdict = classifier.classify(.transport("connection reset"), attempt: 1, policy: policy)
        XCTAssertEqual(verdict.tier, .transient)
        XCTAssertEqual(verdict.waitSeconds, 0.5)
        XCTAssertNil(verdict.help)
        XCTAssertTrue(verdict.isRetryable)
    }

    func testRateLimitAndServerErrorsAreTransient() {
        for code in [408, 429, 500, 503, 599] {
            let verdict = classifier.classify(.httpStatus(code: code, message: nil), attempt: 2, policy: policy)
            XCTAssertEqual(verdict.tier, .transient, "HTTP \(code) 应可重试")
        }
    }

    func testAuthFailuresNeedHumanWithGrantRequest() {
        for code in [401, 403] {
            let verdict = classifier.classify(.httpStatus(code: code, message: "invalid key"), attempt: 1, policy: policy)
            XCTAssertEqual(verdict.tier, .needsHuman)
            XCTAssertEqual(verdict.help?.kind, .grant)
            XCTAssertTrue(verdict.help!.ask.contains("API Key"))
            XCTAssertTrue(verdict.help!.isActionable)
        }
    }

    func testQuotaAndDisabledNeedHuman() {
        XCTAssertEqual(classifier.classify(.quotaExceeded("配额用尽"), attempt: 1, policy: policy).tier, .needsHuman)
        XCTAssertEqual(classifier.classify(.disabled, attempt: 1, policy: policy).help?.kind, .information)
        XCTAssertEqual(classifier.classify(.forbidden("端点被禁"), attempt: 1, policy: policy).help?.kind, .grant)
    }

    func testMalformedAndEmptyAreTerminal() {
        XCTAssertEqual(classifier.classify(.malformedResponse("结构不对"), attempt: 1, policy: policy).tier, .terminal)
        XCTAssertEqual(classifier.classify(.emptyCompletion, attempt: 1, policy: policy).tier, .terminal)
        XCTAssertEqual(classifier.classify(.httpStatus(code: 400, message: "bad request"), attempt: 1, policy: policy).tier, .terminal)
    }

    func testUnknownErrorIsNeverAutoRetried() {
        let verdict = classifier.classifyUnknown("起进程失败")
        XCTAssertEqual(verdict.tier, .terminal)
        XCTAssertFalse(verdict.isRetryable)
        XCTAssertTrue(verdict.note.contains("不自动重试"))
    }

    func testBackoffGrowsAndCaps() {
        XCTAssertEqual(classifier.classify(.transport("x"), attempt: 1, policy: policy).waitSeconds, 0.5)
        XCTAssertEqual(classifier.classify(.transport("x"), attempt: 2, policy: policy).waitSeconds, 2)
        // 超出表长用表尾，不许无限增长
        XCTAssertEqual(classifier.classify(.transport("x"), attempt: 9, policy: policy).waitSeconds, 2)
    }
}
