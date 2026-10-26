import XCTest
@testable import DoyahCore

/// `FR-AGT-QUAL-VERIFY-003`（不确定性表达）/ `FR-AGT-QUAL-VERIFY-004`（断言可溯源）的**接线判据**。
///
/// 与 `AgentClaimProvenanceTests` 的分工：那边判**契约**（一条结论长什么样、什么算合格），
/// 这边判**真用上**——答复怎么切成结论、出处从哪来、缺出处的结论有没有真的被摘出交付物、
/// 循环收口有没有真的把账挂到结果上。契约绿而这一层空着，`isDeliverable` 就永远没人填。
final class AgentAnswerAuditTests: XCTestCase {

    // MARK: - 夹具

    private func evidence(path: String) -> AgentAnswerEvidence {
        AgentAnswerEvidence(basis: .file(path: path, line: nil),
                            aliases: [path, path.split(separator: "/").last.map(String.init) ?? path])
    }

    private func readInvocation(_ path: String) -> AgentToolInvocation {
        AgentToolInvocation(name: "read_file", argumentsJSON: #"{"path":"\#(path)"}"#)
    }

    // MARK: - 003 ③ / 004 ③ 正常路径：都指得到出处 ⇒ 可交付

    func testFullyCitedAnswerIsDeliverableAndAllVerified() {
        let ledger = [evidence(path: "Core/AgentSession.swift")]
        let answer = """
        会话按工作区隔离，落盘在 Core/AgentSession.swift 里。
        归档面不会被列表扫到，见 Core/AgentSession.swift。
        """
        let provenance = AgentAnswerAuditor.audit(answer: answer, evidence: ledger)
        let decision = AgentDeliverableDecision(provenance: provenance, language: .simplifiedChinese)

        XCTAssertEqual(provenance.claims.count, 2)
        XCTAssertEqual(provenance.verifiedCount, 2, "完整路径命中 ⇒ 已验证")
        XCTAssertEqual(provenance.unverifiedCount, 0)
        XCTAssertTrue(provenance.isDeliverable)
        XCTAssertEqual(decision.outcome, .deliverable)
        XCTAssertTrue(decision.withheld.isEmpty)
        XCTAssertNil(decision.notice(language: .simplifiedChinese), "全合格不出提示条")
        XCTAssertTrue(decision.deliverableText.contains("Core/AgentSession.swift"))
    }

    // MARK: - 004 ③ 该拒：没出处的结论不进交付物，但要被点名

    func testUncitedClaimIsWithheldAndNamedInNotice() {
        let ledger = [evidence(path: "Core/AgentSession.swift")]
        let answer = """
        会话按工作区隔离，见 Core/AgentSession.swift。
        顺便说一下，那个并发上限已经实现完了。
        """
        let provenance = AgentAnswerAuditor.audit(answer: answer, evidence: ledger)
        let decision = AgentDeliverableDecision(provenance: provenance, language: .simplifiedChinese)

        XCTAssertEqual(provenance.claims.count, 2)
        XCTAssertEqual(decision.outcome, .partiallyWithheld(count: 1))
        XCTAssertEqual(decision.withheld.count, 1)
        XCTAssertTrue(decision.withheld[0].statement.contains("并发上限"))
        XCTAssertTrue(decision.withheld[0].defects.contains(.missingBasis))
        XCTAssertFalse(decision.deliverableText.contains("并发上限"),
                       "缺出处的结论不许写入交付内容（004 ③）")
        XCTAssertTrue(decision.deliverableText.contains("Core/AgentSession.swift"))

        let notice = decision.notice(language: .simplifiedChinese)
        XCTAssertNotNil(notice)
        XCTAssertTrue(notice?.body.contains("1") ?? false, "拦下几条要点名")
        XCTAssertEqual(notice?.mustInterrupt, false)
    }

    func testAllUncitedAnswerHasNothingDeliverable() {
        let answer = "这个方案肯定没问题。性能至少翻三倍。"
        let provenance = AgentAnswerAuditor.audit(answer: answer, evidence: [])
        let decision = AgentDeliverableDecision(provenance: provenance, language: .simplifiedChinese)

        XCTAssertEqual(provenance.unverifiedCount, 2)
        XCTAssertEqual(decision.outcome, .nothing)
        XCTAssertTrue(decision.deliverableText.isEmpty)
        // 「没验证」那一档必须被要求给替代方案（003 ②）
        XCTAssertTrue(provenance.claims.allSatisfy { $0.defects.contains(.lowConfidenceWithoutAlternative) })
    }

    // MARK: - 出处的唯一合法来源：本轮真做过的动作

    func testPathNeverTouchedThisRunIsNotABasis() {
        let ledger = [evidence(path: "Core/AgentSession.swift")]
        let answer = "配置写在 Core/AgentLoop.swift 里。"
        let provenance = AgentAnswerAuditor.audit(answer: answer, evidence: ledger)

        XCTAssertEqual(provenance.claims.count, 1)
        XCTAssertEqual(provenance.claims[0].status, .unverified, "没读过的路径不算出处")
        XCTAssertTrue(provenance.claims[0].bases.isEmpty)
    }

    func testBasenameOnlyMatchIsInferredNotVerified() {
        let ledger = [evidence(path: "Core/AgentSession.swift")]
        let answer = "这一步在 AgentSession.swift 里做的。"
        let provenance = AgentAnswerAuditor.audit(answer: answer, evidence: ledger)

        XCTAssertEqual(provenance.claims[0].status, .inferred, "只给了末段 ⇒ 只能算推断")
        XCTAssertEqual(provenance.claims[0].uniqueBases.count, 1)
        XCTAssertTrue(provenance.isDeliverable, "推断有出处 ⇒ 可交付（只是不许标成已验证）")
    }

    func testCommandBasisIsInferredBecauseExitCodeIsUnknown() {
        let invocation = AgentToolInvocation(name: "run_command",
                                            argumentsJSON: #"{"command":"swift test --filter AgentLoopTests"}"#)
        let ledger = AgentEvidenceLedger.collect(executedTools: [invocation])
        XCTAssertEqual(ledger.count, 1)
        XCTAssertEqual(ledger[0].basis, .commandOutput(command: "swift test --filter AgentLoopTests", exitCode: nil))

        let answer = "判据跑过了：swift test --filter AgentLoopTests。"
        let provenance = AgentAnswerAuditor.audit(answer: answer, evidence: ledger)
        XCTAssertEqual(provenance.claims[0].status, .inferred,
                       "退出码没随结果带出来 ⇒ 不许冒充「已验证」")
        XCTAssertEqual(provenance.claims[0].uniqueBases.count, 1)
    }

    // MARK: - 边界：什么不算结论、什么不算出处

    func testHeadingsCodeFencesAndQuestionsAreNotClaims() {
        let answer = """
        ## 结论
        要我接着做下一批吗？
        ```
        let x = 1
        ```
        - Core/AgentSession.swift 里的行为没变。
        """
        let statements = AgentAnswerAuditor.statements(in: answer)
        XCTAssertEqual(statements.count, 1, "标题 / 提问 / 代码块都不算断言：\(statements)")
        XCTAssertTrue(statements[0].hasPrefix("Core/AgentSession.swift"))
    }

    func testOrderedListMarkerIsStripped() {
        let statements = AgentAnswerAuditor.statements(in: "1. Core/AgentSession.swift 未改动。")
        XCTAssertEqual(statements, ["Core/AgentSession.swift 未改动。"])
    }

    func testSamePathTwiceInOneSentenceAttachesOneBasis() {
        let ledger = [evidence(path: "Core/AgentSession.swift")]
        let answer = "Core/AgentSession.swift 与 Core/AgentSession.swift 是同一处。"
        let provenance = AgentAnswerAuditor.audit(answer: answer, evidence: ledger)
        XCTAssertEqual(provenance.claims[0].uniqueBases.count, 1, "同一出处只标一次")
    }

    func testNonPathArgumentsProduceNoEvidence() {
        let search = AgentToolInvocation(name: "search", argumentsJSON: #"{"pattern":"checkpoint"}"#)
        let list = AgentToolInvocation(name: "list_dir", argumentsJSON: #"{"dir":"Core"}"#)
        XCTAssertTrue(AgentEvidenceLedger.collect(executedTools: [search]).isEmpty,
                      "「查过什么词」不能当任何结论的出处")
        XCTAssertEqual(AgentEvidenceLedger.collect(executedTools: [list]).count, 1)
    }

    func testRepeatedInvocationsOfSameFileCollapseToOneEvidence() {
        let ledger = AgentEvidenceLedger.collect(executedTools: [
            readInvocation("Core/AgentSession.swift"),
            readInvocation("Core/AgentSession.swift"),
            readInvocation("Core/AgentLoop.swift"),
        ])
        XCTAssertEqual(ledger.count, 2)
    }

    func testEmptyAnswerHasNoClaimsAndNoDecisionNoise() {
        let provenance = AgentAnswerAuditor.audit(answer: "   \n\n", evidence: [])
        XCTAssertTrue(provenance.claims.isEmpty)
        let decision = AgentDeliverableDecision(provenance: provenance, language: .simplifiedChinese)
        XCTAssertEqual(decision.outcome, .nothing)
        XCTAssertNil(decision.notice(language: .simplifiedChinese))
    }

    func testEnglishNoticeHasNoChineseCharacters() {
        let provenance = AgentAnswerAuditor.audit(answer: "这一步没出处。", evidence: [])
        let decision = AgentDeliverableDecision(provenance: provenance, language: .english)
        let notice = decision.notice(language: .english)
        XCTAssertNotNil(notice)
        let text = (notice?.title ?? "") + (notice?.body ?? "")
        XCTAssertFalse(text.contains(where: { $0.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) } }),
                       "英文界面不许漏汉字：\(text)")
    }

    // MARK: - 循环收口：账真的挂到了结果上

    /// 按跳吐事件的假模型。
    ///
    /// 坑（本批实测踩过一次）：把 `hops` 拷成 `var queue = hops` 再 `removeFirst()`，
    /// 每次都从**第一跳**开始 ⇒ 循环永远停在「还在要工具」，`text` 永远为空，
    /// 于是「出处账」看起来怎么都不挂 —— 那是夹具的错，不是产品的错。
    private final class OneAnswerClient: LLMStreamingClient, @unchecked Sendable {
        private var hops: [[LLMStreamEvent]]
        private let lock = NSLock()
        init(_ hops: [[LLMStreamEvent]]) { self.hops = hops }
        func stream(_ request: LLMRequest) async throws -> AsyncThrowingStream<LLMStreamEvent, Error> {
            lock.lock()
            let events = hops.isEmpty ? [LLMStreamEvent.textDelta("x"), .done] : hops.removeFirst()
            lock.unlock()
            return AsyncThrowingStream { continuation in
                for event in events { continuation.yield(event) }
                continuation.finish()
            }
        }
    }

    private final class SilentDispatcher: AgentToolDispatcher, @unchecked Sendable {
        func dispatch(_ invocation: AgentToolInvocation, approvals: Set<String>) -> AgentToolOutcome {
            .file(AgentToolFileOutput(path: "a.txt", text: "内容", truncated: false, totalBytes: 6))
        }
    }

    private func runLoop(answer: String) async -> AgentLoopResult {
        let client = OneAnswerClient([
            [.toolCallDelta(index: 0, id: "call-0", name: "read_file", argumentsFragment: #"{"path":"a.txt"}"#),
             .finished(reason: "tool_calls"), .done],
            [.textDelta(answer), .finished(reason: "stop"), .done],
        ])
        let loop = AgentLoop(client: client, dispatcher: SilentDispatcher())
        let context = AgentLoopContext(
            systemPrompt: "你是助手。", userPrompt: "读 a.txt",
            baseRequest: LLMRequest(endpoint: URL(string: "http://127.0.0.1:11434/v1")!,
                                    model: "fake", systemPrompt: "", userPrompt: ""),
            sessionID: "s-audit", workspace: "ws-audit")
        return await loop.run(context: context)
    }

    func testLoopSealsAnswerProvenanceFromExecutedTools() async {
        let result = await runLoop(answer: "a.txt 里只有一行内容。")
        let provenance = try? XCTUnwrap(result.answerProvenance)
        XCTAssertNotNil(provenance, "成文答复要随结果带出处账")
        XCTAssertEqual(provenance?.claims.count, 1)
        XCTAssertEqual(provenance?.verifiedCount, 1, "本轮真读过 a.txt ⇒ 这条指得到出处")
    }

    func testLoopWithholdsUncitedAnswer() async {
        let result = await runLoop(answer: "数据库索引也顺手优化了。")
        let provenance = try? XCTUnwrap(result.answerProvenance)
        XCTAssertEqual(provenance?.unverifiedCount, 1)
        let decision = AgentDeliverableDecision(provenance: provenance ?? AgentAnswerProvenance(claims: []),
                                                language: .simplifiedChinese)
        XCTAssertEqual(decision.outcome, .nothing)
        XCTAssertNotNil(decision.notice(language: .simplifiedChinese), "拦下了就要说一声")
    }
}
