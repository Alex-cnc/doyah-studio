import XCTest
@testable import DoyahCore

/// `FR-AGT-QUAL-VERIFY-003`（不确定性表达）+ `FR-AGT-QUAL-VERIFY-004`（断言可溯源）的机械判据。
///
/// 六条验收要点逐条落：003 ①②③（区分已验证/推断、低把握给替代、无法确认说「没验证」）
/// 与 004 ①②③（结论旁有出处、出处可复制、缺出处不得进交付物）。
final class AgentClaimProvenanceTests: XCTestCase {

    private let fileBasis = AgentClaimBasis.file(path: "Core/AgentSession.swift", line: 312)
    private let commandBasis = AgentClaimBasis.commandOutput(command: "swift test --filter AgentSessionTests",
                                                             exitCode: 0)

    // MARK: - 003 ① 结论里能区分「已验证」与「推断」

    func testVerifiedAndInferredRenderWithDifferentLabels() {
        let verified = AgentClaim(statement: "会话按工作区隔离", status: .verified,
                                  bases: [fileBasis], confidence: 0.98)
        let inferred = AgentClaim(statement: "归档面不会被列表扫到", status: .inferred,
                                  bases: [fileBasis], confidence: 0.7)
        let zhVerified = verified.rendered(language: .simplifiedChinese)
        let zhInferred = inferred.rendered(language: .simplifiedChinese)

        XCTAssertTrue(zhVerified.hasPrefix("[已验证]"), zhVerified)
        XCTAssertTrue(zhInferred.hasPrefix("[推断]"), zhInferred)
        XCTAssertNotEqual(zhVerified, zhInferred)
        // 标签不是默认值：状态不填就没有默认渲染这一说（类型上必填，这里锁死渲染面）
        XCTAssertFalse(zhInferred.contains("[已验证]"))
    }

    func testRenderedLabelFollowsLanguageParameter() {
        let claim = AgentClaim(statement: "ok", status: .verified, bases: [fileBasis], confidence: 1)
        let en = claim.rendered(language: .english)
        XCTAssertTrue(en.hasPrefix("[Verified]"), en)
        // 英文面不许漏中文（L-47：语言作形参传进来，不是装饰）
        XCTAssertFalse(en.contains("已验证"), en)
        XCTAssertTrue(en.contains("Core/AgentSession.swift:312"), en)
    }

    // MARK: - 003 ② 把握低时给替代方案

    func testLowConfidenceWithoutAlternativeIsDefect() {
        let claim = AgentClaim(statement: "可能是锁等待", status: .inferred,
                               bases: [fileBasis], confidence: 0.3)
        XCTAssertTrue(claim.needsAlternative)
        XCTAssertTrue(claim.defects.contains(.lowConfidenceWithoutAlternative))
    }

    func testLowConfidenceWithAlternativeIsClean() {
        let claim = AgentClaim(statement: "可能是锁等待", status: .inferred, bases: [fileBasis],
                               confidence: 0.3, alternatives: ["也可能是慢查询，先看 pg_stat_activity"])
        XCTAssertFalse(claim.defects.contains(.lowConfidenceWithoutAlternative))
        XCTAssertTrue(claim.defects.isEmpty)
        XCTAssertTrue(claim.rendered(language: .simplifiedChinese).contains("备选："))
    }

    func testHighConfidenceDoesNotNeedAlternative() {
        let claim = AgentClaim(statement: "这一行就是入口", status: .verified,
                               bases: [fileBasis], confidence: 0.9)
        XCTAssertFalse(claim.needsAlternative)
        XCTAssertTrue(claim.defects.isEmpty)
    }

    func testUnverifiedAlwaysNeedsAlternativeEvenAtHighConfidence() {
        // 「没验证」不能用高把握度混过去：没验就说没验，并给还能怎么走
        let claim = AgentClaim(statement: "生产库应该是 15", status: .unverified,
                               bases: [AgentClaimBasis.documentLink(url: "https://example.com/notes")],
                               confidence: 0.95)
        XCTAssertTrue(claim.needsAlternative)
        XCTAssertTrue(claim.defects.contains(.lowConfidenceWithoutAlternative))
    }

    // MARK: - 003 ③ 无法确认时明确说「没验证」

    func testUnverifiedClaimSaysSoInBothLanguages() {
        let claim = AgentClaim(statement: "没连过生产库", status: .unverified, bases: [], confidence: 0,
                               alternatives: ["先在 217 的 doyah_test 上跑一遍"])
        XCTAssertTrue(claim.rendered(language: .simplifiedChinese).contains("没验证"))
        XCTAssertTrue(claim.rendered(language: .english).contains("Unverified"))
    }

    // MARK: - 004 ① 关键结论旁有出处 / ③ 缺出处不得进交付物

    func testVerifiedWithoutBasisIsTheMostDangerousDefect() {
        let claim = AgentClaim(statement: "这功能已经做完了", status: .verified, bases: [], confidence: 0.99)
        XCTAssertEqual(claim.defects, [.missingBasis, .verifiedWithoutBasis])
    }

    func testAnswerWithoutBasisIsNotDeliverable() {
        let good = AgentClaim(statement: "a", status: .verified, bases: [fileBasis], confidence: 0.9)
        let bad = AgentClaim(statement: "b", status: .inferred, bases: [], confidence: 0.8)

        XCTAssertTrue(AgentAnswerProvenance(claims: [good]).isDeliverable)
        let mixed = AgentAnswerProvenance(claims: [good, bad])
        XCTAssertFalse(mixed.isDeliverable)
        XCTAssertEqual(mixed.undeliverable.count, 1)
        XCTAssertEqual(mixed.undeliverable.first?.statement, "b")
    }

    func testEmptyStatementIsDefect() {
        let claim = AgentClaim(statement: "  ", status: .inferred, bases: [fileBasis], confidence: 0.8)
        XCTAssertTrue(claim.defects.contains(.emptyStatement))
    }

    // MARK: - 004 ② 出处可点击 / 可复制执行

    func testEveryBasisKindIsCopyableAndCarriesALocator() {
        let bases: [AgentClaimBasis] = [
            .file(path: "Core/AgentLoop.swift", line: 42),
            .file(path: "Core/AgentLoop.swift", line: nil),
            .commandOutput(command: "psql -c 'select 1'", exitCode: 1),
            .commandOutput(command: "psql -c 'select 1'", exitCode: nil),
            .log(path: "/tmp/gate.log", line: 7),
            .documentLink(url: "https://example.com/spec#3"),
        ]
        for basis in bases {
            XCTAssertTrue(basis.isCopyable, basis.reference)
            XCTAssertFalse(basis.copyableText.isEmpty, basis.reference)
        }
        // 文件带行号：复制出去能直接定位
        XCTAssertEqual(AgentClaimBasis.file(path: "a.swift", line: 9).copyableText, "a.swift:9")
        XCTAssertEqual(AgentClaimBasis.file(path: "a.swift", line: 9).reference, "a.swift:9")
        // 命令：复制出去就是那条命令，不夹带退出码
        XCTAssertEqual(AgentClaimBasis.commandOutput(command: "ls -1", exitCode: 2).copyableText, "ls -1")
        XCTAssertEqual(AgentClaimBasis.commandOutput(command: "ls -1", exitCode: 2).reference, "cmd:ls -1 exit=2")
    }

    // MARK: - 边界：把握度夹紧 / 同出处不重复 / 汇总计数

    func testConfidenceIsClampedIntoUnitRange() {
        let over = AgentClaim(statement: "x", status: .verified, bases: [fileBasis], confidence: 1.4)
        XCTAssertEqual(over.confidence, 1.0, accuracy: 0.0001)
        // 负值夹到 0 ⇒ 必然「把握低」⇒ 必须给替代方案
        let under = AgentClaim(statement: "x", status: .inferred, bases: [fileBasis], confidence: -0.2)
        XCTAssertEqual(under.confidence, 0.0, accuracy: 0.0001)
        XCTAssertTrue(under.needsAlternative)
    }

    func testSameBasisIsRenderedOnlyOnce() {
        let claim = AgentClaim(statement: "x", status: .verified,
                               bases: [fileBasis, fileBasis, commandBasis], confidence: 1)
        XCTAssertEqual(claim.uniqueBases.count, 2)
        let rendered = claim.rendered(language: .simplifiedChinese)
        let occurrences = rendered.components(separatedBy: "Core/AgentSession.swift:312").count - 1
        XCTAssertEqual(occurrences, 1, "同一条出处重复贴 = 噪音（SRS 004 反向口径）")
    }

    func testSummaryCountsEveryStatus() {
        let provenance = AgentAnswerProvenance(claims: [
            AgentClaim(statement: "a", status: .verified, bases: [fileBasis], confidence: 0.9),
            AgentClaim(statement: "b", status: .inferred, bases: [fileBasis], confidence: 0.7),
            AgentClaim(statement: "c", status: .unverified, bases: [commandBasis], confidence: 0.1,
                       alternatives: ["重跑一次"]),
        ])
        XCTAssertEqual(provenance.verifiedCount, 1)
        XCTAssertEqual(provenance.inferredCount, 1)
        XCTAssertEqual(provenance.unverifiedCount, 1)
        XCTAssertTrue(provenance.summary(language: .simplifiedChinese).contains("3 条结论"),
                      provenance.summary(language: .simplifiedChinese))
        XCTAssertTrue(provenance.summary(language: .english).contains("3 claims"),
                      provenance.summary(language: .english))
        // 三条都带出处、低把握那条也给了替代 ⇒ 可交付
        XCTAssertTrue(provenance.isDeliverable, "\(provenance.undeliverable)")
    }
}
