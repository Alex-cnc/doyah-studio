import XCTest
@testable import DoyahCore

/// `FR-AI-31` ②（完成判据 / Verifier）的机械判据。
///
/// 要害是**负例**：把「模型说做完了」当完成。所以每条「通过」的判据旁边都站一条「不通过」：
/// · 嘴上说完成、一行引用都没有 ⇒ `unverified:noEvidence`；
/// · 引用了**本次没发生过**的工具结果 ⇒ `unverified:claimNotInRun`；
/// · 引用得对不上**此刻的盘**（被改过 / 被删）⇒ `unverified:diskDiffers` / `unverified:unreadable`；
/// · 说「命令跑成功了」可实际退出码不是 0 ⇒ `unverified:commandFailed`。
/// 复核再读一次盘是刻意的：工具层那句「我写了」也只是一句话，只有盘上现状算复核。
final class AgentCompletionVerifierTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-verifier-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ text: String, to name: String) throws {
        try text.write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    private func verifier(reader: (@Sendable (URL) -> String?)? = nil) -> AgentCompletionVerifier {
        AgentCompletionVerifier(workspaceRoot: root, reader: reader)
    }

    private func writeEvidence(_ name: String, _ text: String, step: Int = 1) -> AgentCompletionEvidence {
        AgentCompletionEvidence(kind: .write, toolName: "write_file", path: name,
                                digest: AgentCompletionEvidence.digest(of: text), step: step)
    }

    // MARK: - ①② 自报完成不算完成（负例）

    func testCompletionClaimWithoutAnyCitationIsUnverified() {
        let report = verifier().verify(text: "已改好 a.txt，任务完成。", evidence: [
            writeEvidence("a.txt", "新内容"),
        ])
        XCTAssertEqual(report.status, .unverified)
        XCTAssertEqual(report.reason, "noEvidence", "嘴上说完成、一条引用都没有 ⇒ 如实说未验证")
        XCTAssertEqual(report.code, "unverified:noEvidence")
        XCTAssertFalse(report.isVerified)
    }

    func testPlainAnswerIsNotTreatedAsACompletionClaim() {
        // 只是回答问题（没有「完成」措辞）⇒ 不冤枉它，也不显示「已复核」。
        let report = verifier().verify(text: "a.txt 一共 3 行，第 2 行是空行。", evidence: [])
        XCTAssertEqual(report.status, .notClaimed)
        XCTAssertEqual(report.code, "notClaimed")
    }

    // MARK: - ③ 写盘证据：引用得对 + 盘上仍成立 ⇒ 复核通过

    func testWriteClaimIsVerifiedWhenDiskStillMatches() throws {
        try write("新内容", to: "a.txt")
        let report = verifier().verify(text: "改好了。\nEVIDENCE: write a.txt", evidence: [
            writeEvidence("a.txt", "新内容"),
        ])
        XCTAssertEqual(report.status, .verified, "detail=\(report.detail) reason=\(report.reason)")
        XCTAssertEqual(report.citations.count, 1)
        XCTAssertEqual(report.code, "verified:1")
    }

    func testClaimOfWriteThatNeverHappenedInThisRunIsRejected() {
        // 引用了本次没发生过的写（幻觉 / 记成上一轮）⇒ 拒。
        let report = verifier().verify(text: "已完成\nEVIDENCE: write b.txt", evidence: [
            writeEvidence("a.txt", "新内容"),
        ])
        XCTAssertEqual(report.status, .unverified)
        XCTAssertEqual(report.reason, "claimNotInRun")
    }

    func testWriteClaimRejectedWhenDiskChangedAfterTheWrite() throws {
        // 工具说写了「AAA」，可此刻盘上是「BBB」（被撤销 / 被别人改过）⇒ 复核不过。
        try write("BBB", to: "a.txt")
        let report = verifier().verify(text: "已完成\nEVIDENCE: write a.txt", evidence: [
            writeEvidence("a.txt", "AAA"),
        ])
        XCTAssertEqual(report.reason, "diskDiffers")
        XCTAssertFalse(report.isVerified)
    }

    func testClaimRejectedWhenTargetIsGone() throws {
        // 写完又被删掉 ⇒ 读不出来 = 复核不了（**不许**当通过）。
        try write("临时", to: "gone.txt")
        try FileManager.default.removeItem(at: root.appendingPathComponent("gone.txt"))
        let report = verifier().verify(text: "已完成\nEVIDENCE: edit gone.txt", evidence: [
            AgentCompletionEvidence(kind: .edit, toolName: "edit_file", path: "gone.txt",
                                    digest: AgentCompletionEvidence.digest(of: "临时"), step: 1),
        ])
        // 目标不存在 ⇒ 真读盘给 nil ⇒ unreadable（不是「内容一致」）。
        XCTAssertEqual(report.reason, "unreadable")
    }

    func testUnreadableIsReportedWhenReaderCannotRead() {
        let report = verifier(reader: { _ in nil }).verify(text: "已完成\nEVIDENCE: write a.txt",
                                                          evidence: [writeEvidence("a.txt", "x")])
        XCTAssertEqual(report.reason, "unreadable")
    }

    // MARK: - ④ 命令证据：退出码要对得上

    func testCommandClaimVerifiedWhenExitCodeMatches() {
        let evidence = AgentCompletionEvidence(kind: .command, toolName: "run_command",
                                               exitCode: 0, step: 1)
        let report = verifier().verify(text: "跑好了。\nEVIDENCE: command exit=0", evidence: [evidence])
        XCTAssertEqual(report.status, .verified, "detail=\(report.detail) reason=\(report.reason)")
    }

    func testCommandClaimRejectedWhenExitCodeDiffers() {
        let evidence = AgentCompletionEvidence(kind: .command, toolName: "run_command",
                                               exitCode: 2, step: 1)
        let report = verifier().verify(text: "跑好了。\nEVIDENCE: command exit=0", evidence: [evidence])
        XCTAssertEqual(report.reason, "commandFailed", "退出码不是 0 就不许说成功")
    }

    func testCommandClaimWithoutExitCodeCannotBeVerified() {
        // 只说「跑过了」等于什么都没说 —— 复核不了就不许算过。
        let evidence = AgentCompletionEvidence(kind: .command, toolName: "run_command",
                                               exitCode: 0, step: 1)
        let report = verifier().verify(text: "跑过了。\nEVIDENCE: command", evidence: [evidence])
        XCTAssertEqual(report.status, .unverified)
        XCTAssertEqual(report.reason, "claimNotInRun")
    }

    // MARK: - ⑤ 解析面：宽容读格式，不宽容内容

    func testIndentedBulletedAndBacktickedClaimsAreRecognised() throws {
        try write("正文", to: "a.txt")
        let text = """
        改好了：
          - EVIDENCE: write `a.txt`
        """
        let report = verifier().verify(text: text, evidence: [writeEvidence("a.txt", "正文")])
        XCTAssertEqual(report.status, .verified, "detail=\(report.detail) reason=\(report.reason)")
    }

    func testUnknownKindIsRejectedRatherThanSilentlyIgnored() {
        let report = verifier().verify(text: "已完成\nEVIDENCE: teleport a.txt", evidence: [
            writeEvidence("a.txt", "x"),
        ])
        XCTAssertEqual(report.status, .unverified, "认不出的引用 ⇒ 复核不了 ⇒ 不许当通过")
    }

    // MARK: - ⑥ 接进循环：证据来自**本次运行**，结论落到结果与过程面

    private final class ScriptedStreamingClient: LLMStreamingClient, @unchecked Sendable {
        var hops: [[LLMStreamEvent]]
        init(_ hops: [[LLMStreamEvent]]) { self.hops = hops }
        func stream(_ request: LLMRequest) async throws -> AsyncThrowingStream<LLMStreamEvent, Error> {
            let events = hops.isEmpty ? [.textDelta("（脚本用尽）"), .done] : hops.removeFirst()
            return AsyncThrowingStream { continuation in
                for event in events { continuation.yield(event) }
                continuation.finish()
            }
        }
    }

    /// 真的写盘的假分发器（写完把正文交回循环 —— 证据链与真实路径同形）。
    private final class WritingDispatcher: AgentToolDispatcher, @unchecked Sendable {
        let root: URL
        init(root: URL) { self.root = root }
        func dispatch(_ invocation: AgentToolInvocation, approvals: Set<String>) -> AgentToolOutcome {
            let text = "改好了的内容"
            try? text.write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
            return .wrote(AgentToolFileOutput(path: "a.txt", text: text, truncated: false,
                                             totalBytes: text.utf8.count))
        }
    }

    private final class RecordingObserver: AgentLoopObserver, @unchecked Sendable {
        private let lock = NSLock()
        private(set) var events: [AgentLoopEvent] = []
        func observe(_ event: AgentLoopEvent) async {
            lock.lock(); events.append(event); lock.unlock()
        }
        var completionCodes: [String] {
            lock.lock(); defer { lock.unlock() }
            return events.compactMap {
                if case .completionChecked(let code, _) = $0 { return code }
                return nil
            }
        }
    }

    private func loopContext() -> AgentLoopContext {
        AgentLoopContext(systemPrompt: "你是助手。", userPrompt: "改一下 a.txt",
                         baseRequest: LLMRequest(endpoint: URL(string: "http://127.0.0.1:11434/v1")!,
                                                 model: "fake", systemPrompt: "", userPrompt: ""),
                         sessionID: "s-verify", workspace: root.path)
    }

    func testLoopVerifiesCompletionFromThisRunsEvidence() async throws {
        let client = ScriptedStreamingClient([
            [.toolCallDelta(index: 0, id: "call-0", name: "write_file",
                            argumentsFragment: #"{"path":"a.txt","content":"改好了的内容"}"#),
             .finished(reason: "tool_calls"), .done],
            [.textDelta("改好了。\nEVIDENCE: write a.txt"), .finished(reason: "stop"), .done],
        ])
        let observer = RecordingObserver()
        let loop = AgentLoop(client: client,
                             dispatcher: WritingDispatcher(root: root),
                             observer: observer,
                             completionVerifier: AgentCompletionVerifier(workspaceRoot: root))
        let result = await loop.run(context: loopContext())

        XCTAssertEqual(result.completion?.status, .verified,
                       "detail=\(result.completion?.detail ?? "") reason=\(result.completion?.reason ?? "")")
        XCTAssertEqual(result.completion?.citations.count, 1)
        XCTAssertEqual(observer.completionCodes, ["verified:1"], "结论要交给过程面（不许静默）")
    }

    func testLoopSaysUnverifiedWhenModelClaimsCompletionWithoutEvidence() async throws {
        let client = ScriptedStreamingClient([
            [.toolCallDelta(index: 0, id: "call-0", name: "write_file",
                            argumentsFragment: #"{"path":"a.txt","content":"改好了的内容"}"#),
             .finished(reason: "tool_calls"), .done],
            // 工具**真跑过**，但模型不引用 ⇒ 依然算未验证（证据得被引到才算数）。
            [.textDelta("已经全部完成了。"), .finished(reason: "stop"), .done],
        ])
        let observer = RecordingObserver()
        let loop = AgentLoop(client: client,
                             dispatcher: WritingDispatcher(root: root),
                             observer: observer,
                             completionVerifier: AgentCompletionVerifier(workspaceRoot: root))
        let result = await loop.run(context: loopContext())

        XCTAssertEqual(result.completion?.reason, "noEvidence")
        XCTAssertEqual(observer.completionCodes, ["unverified:noEvidence"])
    }

    func testLoopWithoutVerifierKeepsOldBehaviour() async throws {
        let client = ScriptedStreamingClient([[.textDelta("已完成"), .finished(reason: "stop"), .done]])
        let loop = AgentLoop(client: client, dispatcher: WritingDispatcher(root: root))
        let result = await loop.run(context: loopContext())
        XCTAssertNil(result.completion, "没接验证器 ⇒ 旧行为逐字不变")
    }

    func testChatReadingCarriesTheVerdictToTheUI() {
        var state = AgentChatState(endpoint: .ready(model: "fake", endpoint: "http://127.0.0.1:11434/v1"))
        state.beginRun(prompt: "改一下 a.txt")
        state.apply(.completionChecked(code: "unverified:diskDiffers", citations: 1))
        XCTAssertEqual(state.completionReading?.isUnverified, true)
        XCTAssertEqual(state.completionReading?.reason, "diskDiffers")
        XCTAssertTrue(state.messages.contains { $0.role == .notice && $0.text == "completionUnverified" },
                      "未验证要有一条可读提示，不能只留在机器码里")
        // 新一轮不许继承上一轮的结论。
        state.finishRun()
        state.beginRun(prompt: "再改一次")
        XCTAssertNil(state.completionReading)
    }
}
