import XCTest
@testable import DoyahCore

/// `FR-AI-31` ①（工具 / 命令并发）的机械判据。
///
/// 要害是**负例**：同一文件两次并发写**不许静默覆盖**。
/// 三道闸各管一段，判据逐段咬：
/// · **租约**（`AgentWriteCoordinator`）—— 同时只许一个人写这个文件（拿不到就如实说「正在写」）；
/// · **基线**（`AgentWriteTargetState`）—— 审批之后目标被改过 ⇒ 这份审批过期，不拿旧审批盖新内容；
/// · **如实说** —— 拒因是机器码 + 可读路径，过程行与提示都拿得到（不是只写进日志）。
final class AgentWriteConcurrencyTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-write-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func fileURL(_ name: String) -> URL { root.appendingPathComponent(name) }
    private func write(_ text: String, to name: String) throws {
        try text.write(to: fileURL(name), atomically: true, encoding: .utf8)
    }
    private func read(_ name: String) -> String {
        (try? String(contentsOf: fileURL(name), encoding: .utf8)) ?? ""
    }

    /// 出单（拿到审批请求）——判据里反复用。
    private func request(_ tools: AgentWorkspaceTools, path: String, content: String,
                         file: StaticString = #filePath, line: UInt = #line) -> AgentApprovalRequest {
        guard case .needsApproval(let request) = tools.prepareWrite(path: path, content: content) else {
            XCTFail("应当出一张审判单", file: file, line: line)
            return AgentApprovalRequest(toolName: "", fingerprint: "", payload: "")
        }
        return request
    }

    // MARK: - ① 同一文件并发写：恰好一个成功，另一个如实说「有人正在写 / 审批过期」

    func testTwoConcurrentWritesToOneFileLandExactlyOneAndSayWhy() throws {
        try write("orig", to: "a.txt")
        // **两本不同的工具实例共用同一本账**（宿主每轮现造工具 —— 账若不共享，并发永远抓不到）。
        let coordinator = AgentWriteCoordinator()
        let toolsA = AgentWorkspaceTools(root: root, writes: coordinator)
        let toolsB = AgentWorkspaceTools(root: root, writes: coordinator)
        // 两次审批**都对着同一份基线**出单（真实场景：两轮/两个人几乎同时批）。
        let reqA = request(toolsA, path: "a.txt", content: "AAA")
        let reqB = request(toolsB, path: "a.txt", content: "BBB")
        XCTAssertEqual(reqA.baseDigest, reqB.baseDigest, "两次出单来自同一份基线")

        let start = DispatchSemaphore(value: 0)
        let group = DispatchGroup()
        let lock = NSLock()
        var outcomes: [AgentToolOutcome] = []
        for (tools, req, content) in [(toolsA, reqA, "AAA"), (toolsB, reqB, "BBB")] {
            group.enter()
            DispatchQueue.global().async {
                start.wait()
                let outcome = tools.writeFile(path: "a.txt", content: content,
                                              fingerprint: req.fingerprint,
                                              granted: [req.fingerprint],
                                              baseDigest: req.baseDigest)
                lock.lock(); outcomes.append(outcome); lock.unlock()
                group.leave()
            }
        }
        start.signal()
        start.signal()
        XCTAssertEqual(group.wait(timeout: .now() + 10), .success)

        let written = outcomes.compactMap { outcome -> AgentToolFileOutput? in
            if case .wrote(let output) = outcome { return output }
            return nil
        }
        XCTAssertEqual(written.count, 1, "恰好一个写成功（不许两个都成 = 静默覆盖）")
        let refusals = outcomes.compactMap { outcome -> (AgentToolRefusal, String)? in
            if case .refused(let code, let detail) = outcome { return (code, detail) }
            return nil
        }
        XCTAssertEqual(refusals.count, 1, "另一个必须被拒并说明原因")
        XCTAssertTrue([.writeConflict, .staleTarget].contains(refusals[0].0),
                      "拒因要么「正在写」要么「审批过期」，实际 = \(refusals[0].0)")
        XCTAssertEqual(refusals[0].1, "a.txt", "拒因里带**哪个文件**（可读，不是一串内部 id）")

        // **落盘内容逐字节等于其中一个写者**（负例：交错覆盖成第三种内容）。
        let landed = read("a.txt")
        XCTAssertEqual(landed, written[0].text, "盘上只能是中标那一位的完整内容")
        XCTAssertTrue(["AAA", "BBB"].contains(landed), "不许出现两段交错的第三种内容：\(landed)")
    }

    // MARK: - ② 租约：拿不到就如实说，且**只锁写**

    func testLeaseOnOneFileBlocksOnlyThatFilesWrite() throws {
        try write("orig", to: "a.txt")
        let coordinator = AgentWriteCoordinator()
        let tools = AgentWorkspaceTools(root: root, writes: coordinator)
        // 别人正握着 a.txt（模拟另一次写入在进行）。
        guard let held = coordinator.acquire(path: fileURL("a.txt").path) else {
            return XCTFail("第一次拿租约不该失败")
        }
        defer { coordinator.release(held) }

        let reqA = request(tools, path: "a.txt", content: "AAA")
        let blocked = tools.writeFile(path: "a.txt", content: "AAA",
                                      fingerprint: reqA.fingerprint, granted: [reqA.fingerprint])
        guard case .refused(let code, let detail) = blocked else {
            return XCTFail("同一文件有人在写 ⇒ 必须拒，实际 = \(blocked)")
        }
        XCTAssertEqual(code, .writeConflict)
        XCTAssertEqual(detail, "a.txt")
        XCTAssertEqual(read("a.txt"), "orig", "被拒时一个字节都不许动")

        // **不同文件互不影响**（按文件串行化，不是全局大锁）。
        let reqB = request(tools, path: "b.txt", content: "BBB")
        let other = tools.writeFile(path: "b.txt", content: "BBB",
                                    fingerprint: reqB.fingerprint, granted: [reqB.fingerprint])
        if case .wrote = other {} else { XCTFail("别的文件不该被连坐，实际 = \(other)") }
        XCTAssertEqual(read("b.txt"), "BBB")

        // **读完全不走租约**（并发读不受影响）。
        guard case .file(let snapshot) = tools.readFile(path: "a.txt") else {
            return XCTFail("有人在写也必须读得到")
        }
        XCTAssertEqual(snapshot.text, "orig")
    }

    // MARK: - ③ 租约只许持有者还

    func testLeaseCanOnlyBeReleasedByItsHolder() {
        let coordinator = AgentWriteCoordinator()
        let path = fileURL("a.txt").path
        guard let first = coordinator.acquire(path: path) else { return XCTFail("第一次拿租约不该失败") }
        XCTAssertNil(coordinator.acquire(path: path), "已经有人握着 ⇒ 第二个人拿不到")
        let intruder = AgentWriteLease(path: first.path, token: "someone-else")
        XCTAssertFalse(coordinator.release(intruder), "别人还不掉这份租约")
        XCTAssertTrue(coordinator.isWriting(path: path), "被别人「还」过之后仍然锁着")
        XCTAssertTrue(coordinator.release(first))
        XCTAssertFalse(coordinator.isWriting(path: path))
        XCTAssertEqual(coordinator.activePaths, [])
    }

    // MARK: - ④ 基线：批准之后目标被改过 ⇒ 不拿旧审批盖新内容

    func testWriteIsRefusedWhenTargetChangedAfterApproval() throws {
        try write("orig", to: "a.txt")
        let tools = AgentWorkspaceTools(root: root, writes: AgentWriteCoordinator())
        let req = request(tools, path: "a.txt", content: "AAA")

        // 审批之后、兑现之前：文件被（人 / 别的工具）改过。
        try write("edited by someone else", to: "a.txt")

        let outcome = tools.writeFile(path: "a.txt", content: "AAA",
                                      fingerprint: req.fingerprint, granted: [req.fingerprint],
                                      baseDigest: req.baseDigest)
        guard case .refused(let code, let detail) = outcome else {
            return XCTFail("基线过期 ⇒ 必须拒，实际 = \(outcome)")
        }
        XCTAssertEqual(code, .staleTarget)
        XCTAssertEqual(detail, "a.txt")
        XCTAssertEqual(read("a.txt"), "edited by someone else", "别人的改动没有被旧审批抹掉")
    }

    // MARK: - ⑤ 基线一致 ⇒ 正常落盘；新建文件的基线是「不存在」

    func testWriteLandsWhenBaseStillMatchesAndRecordsAbsentForNewFiles() throws {
        try write("orig", to: "a.txt")
        let tools = AgentWorkspaceTools(root: root, writes: AgentWriteCoordinator())
        let req = request(tools, path: "a.txt", content: "AAA")
        XCTAssertNotEqual(req.baseDigest, AgentWriteTargetState.absent)
        let outcome = tools.writeFile(path: "a.txt", content: "AAA",
                                      fingerprint: req.fingerprint, granted: [req.fingerprint],
                                      baseDigest: req.baseDigest)
        guard case .wrote(let output) = outcome else { return XCTFail("基线没变 ⇒ 应当写成，实际 = \(outcome)") }
        XCTAssertEqual(output.text, "AAA")
        XCTAssertEqual(read("a.txt"), "AAA")

        // 新建文件：基线 = absent（「不存在」是**一个确定的状态**，不是「没有基线」）。
        let fresh = request(tools, path: "fresh.txt", content: "new")
        XCTAssertEqual(fresh.baseDigest, AgentWriteTargetState.absent)
        let created = tools.writeFile(path: "fresh.txt", content: "new",
                                      fingerprint: fresh.fingerprint, granted: [fresh.fingerprint],
                                      baseDigest: fresh.baseDigest)
        if case .wrote = created {} else { XCTFail("新建应当写成，实际 = \(created)") }
        XCTAssertEqual(read("fresh.txt"), "new")
    }

    // MARK: - ⑥ 循环把审批单交给界面（要审批就真的能点）

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

    private final class FixedDispatcher: AgentToolDispatcher, @unchecked Sendable {
        var outcome: AgentToolOutcome
        init(_ outcome: AgentToolOutcome) { self.outcome = outcome }
        func dispatch(_ invocation: AgentToolInvocation, approvals: Set<String>) -> AgentToolOutcome { outcome }
    }

    private final class EventRecorder: AgentLoopObserver, @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [AgentLoopEvent] = []
        func observe(_ event: AgentLoopEvent) async { lock.lock(); storage.append(event); lock.unlock() }
        var events: [AgentLoopEvent] { lock.lock(); defer { lock.unlock() }; return storage }
    }

    private var loopContext: AgentLoopContext {
        AgentLoopContext(systemPrompt: "你是助手。", userPrompt: "改一下 a.txt",
                         baseRequest: LLMRequest(endpoint: URL(string: "http://127.0.0.1:11434/v1")!,
                                                 model: "fake", systemPrompt: "", userPrompt: ""),
                         sessionID: "s-write", workspace: "ws-1")
    }

    private func toolHop() -> [LLMStreamEvent] {
        [.toolCallDelta(index: 0, id: "call-0", name: "write_file",
                        argumentsFragment: #"{"path":"a.txt","content":"AAA"}"#),
         .finished(reason: "tool_calls"), .done]
    }

    func testLoopHandsTheApprovalTicketToTheHost() async {
        let request = AgentApprovalRequest(toolName: "write_file", fingerprint: "fp-1",
                                           payload: "- a\n+ b", baseDigest: "content:x")
        let recorder = EventRecorder()
        let loop = AgentLoop(client: ScriptedStreamingClient([toolHop(),
                                                              [.textDelta("等你批"), .finished(reason: "stop"), .done]]),
                             dispatcher: FixedDispatcher(.needsApproval(request)),
                             observer: recorder)
        _ = await loop.run(context: loopContext)

        let tickets = recorder.events.compactMap { event -> (String, String, String, String)? in
            guard case .approvalRequested(let name, let fingerprint, let preview, let baseDigest) = event else { return nil }
            return (name, fingerprint, preview, baseDigest)
        }
        XCTAssertEqual(tickets.count, 1, "要审批 ⇒ 必须给界面一张单（否则用户永远点不到「批准」）")
        XCTAssertEqual(tickets.first?.0, "write_file")
        XCTAssertEqual(tickets.first?.1, "fp-1")
        XCTAssertEqual(tickets.first?.2, "- a\n+ b", "批准之前要能看见要改什么")
        XCTAssertEqual(tickets.first?.3, "content:x", "基线跟单走（兑现时复核）")
    }

    // MARK: - ⑦ 拒因带机器码 + 聊天侧出可读提示

    func testRefusalCodeReachesTheLoopEventAndTheChatNotice() async {
        let recorder = EventRecorder()
        let loop = AgentLoop(client: ScriptedStreamingClient([toolHop(),
                                                              [.textDelta("写不了"), .finished(reason: "stop"), .done]]),
                             dispatcher: FixedDispatcher(.refused(.writeConflict, detail: "a.txt")),
                             observer: recorder)
        _ = await loop.run(context: loopContext)

        let marks = recorder.events.compactMap { event -> String? in
            guard case .toolFinished(_, let outcome, _) = event else { return nil }
            return outcome
        }
        XCTAssertTrue(marks.contains("denied:writeConflict"),
                      "过程行要带得住机器码（界面才好翻人话），实际 = \(marks)")
    }

    func testChatStateTurnsApprovalEventIntoACardAndConflictIntoANotice() {
        var state = AgentChatState()
        state.apply(.approvalRequested(name: "write_file", fingerprint: "fp-1",
                                       preview: "- a\n+ b", baseDigest: "content:x"))
        XCTAssertEqual(state.cards.count, 1, "要审批就真的出一张可点的单")
        XCTAssertEqual(state.cards[0].baseDigest, "content:x", "基线记在卡片上")
        if case .pendingApproval(let fingerprint, let preview) = state.cards[0].outcome {
            XCTAssertEqual(fingerprint, "fp-1")
            XCTAssertEqual(preview, "- a\n+ b")
        } else {
            XCTFail("逐次批模式下必须停在待批，实际 = \(state.cards[0].outcome)")
        }

        var other = AgentChatState()
        other.apply(.toolFinished(name: "write_file", outcome: "denied:writeConflict", millis: 3))
        let notices = other.messages.filter { $0.role == .notice }.map(\.text)
        XCTAssertEqual(notices, ["writeConflict"], "写冲突要另出一句可读提示，不许只躺在过程行的机器码里")

        var stale = AgentChatState()
        stale.apply(.toolFinished(name: "write_file", outcome: "denied:staleTarget", millis: 2))
        XCTAssertEqual(stale.messages.filter { $0.role == .notice }.map(\.text), ["staleTarget"])
    }
}
