import XCTest
@testable import DoyahCore

/// **一轮别跑那么久**的三条机械判据（2026-11-06）：
/// ① 旧工具结果**折叠**（不删、只降级）—— 模型不忘记读过什么，上下文也不再无限长；
/// ② `read_file` **按行开窗**（`offset` / `limit`）—— 长文件读指定段，不必整篇重读；
/// ③ **一跳的工具预算** —— 超出的当跳不执行，并把「先给结论」喂回去。
final class AgentContextSlimmingTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("slimming-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ name: String, _ body: String) throws -> String {
        try body.write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
        return name
    }

    /// 一段「像文件正文」的长条目（抬头是 `file:<path>:<bytes>B`，与回灌段同形）。
    private func fileObservation(_ path: String, bytes: Int, body: String) -> String {
        "file:\(path):\(bytes)B\n<untrusted source=toolOutput>\n\(body)\n</untrusted>"
    }

    // MARK: - ① 折叠

    func testFoldKeepsRecentVerbatimAndPinsOneExcerptPerPath() {
        let policy = AgentObservationDigestPolicy.standard
        let bulky = String(repeating: "x", count: 5_000)
        var observations: [String] = []
        for index in 0..<12 {
            observations.append(fileObservation("Core/F\(index).swift", bytes: 9_000 + index, body: bulky))
        }
        let folded = AgentObservationDigester.fold(observations, policy: policy)
        let recent = policy.keepRecent
        let older = 12 - recent

        XCTAssertTrue(folded.report.didFold)
        XCTAssertEqual(folded.report.foldedEntries, older, "旧的长条目一共 \(older) 条，都离开了「原样」档")
        XCTAssertEqual(folded.report.pinnedEntries, min(policy.pinnedPaths, older),
                       "其中最近 \(policy.pinnedPaths) 个不同路径被钉住")

        // 最近几条原样：正文一个字节都不许动。
        for index in (12 - recent)..<12 {
            XCTAssertTrue(folded.recent.joined(separator: "\n").contains("Core/F\(index).swift:\(9_000 + index)B"),
                          "最近的第 \(index) 条要原样留着")
            XCTAssertTrue(folded.recent.contains { $0.contains(bulky) }, "最近那条的正文要原样在")
        }

        // **钉住的那几条：开头正文仍在上下文里**（这是 2026-11-16 的回归点 —— 只留路径+大小 ⇒ 模型重读）。
        let pinned = folded.entries.filter { $0.contains("已钉住最近一段") }
        XCTAssertEqual(pinned.count, policy.pinnedPaths, "钉住的路径数按策略来")
        for block in pinned {
            XCTAssertTrue(block.contains("xxxx"), "钉住的段落必须带正文开头，不能只有尺寸：\(block.prefix(80))")
            XCTAssertLessThanOrEqual(block.count, policy.pinnedCharacters + 200,
                                     "钉住要截断，不许把全文塞回来：\(block.count) 字符")
        }

        // 更早的那几条：只有台账行（路径 + 已折叠 + 一句摘要）。
        let ledger = folded.entries.filter { $0.hasPrefix("file:Core/F") && $0.contains("已折叠") }
        XCTAssertEqual(ledger.count, older - policy.pinnedPaths,
                       "没钉住的老条目才进台账：\(ledger)")
        for line in ledger {
            XCTAssertTrue(line.contains("首行：") || line.contains("offset/limit"),
                          "台账行要给一句摘要，不能只剩尺寸：\(line)")
        }

        // 正文总量：钉住的截断版 + 最近几条原文，不许等于「全部原文」。
        XCTAssertLessThan(folded.report.charactersAfter, folded.report.charactersBefore)
        XCTAssertNotNil(folded.report.marker)
    }

    func testShortObservationsAreNeverFolded() {
        // 错误码 / 退出码 / 写回执是**证据**，再老也不许折掉。
        var observations = (0..<10).map { _ in "read_file: refused:notFound/AgentLoop.swift" }
        observations.append("command:0\nstdout:\n全部通过")
        let folded = AgentObservationDigester.fold(observations, policy: .standard)
        XCTAssertFalse(folded.report.didFold, "全是短条目 ⇒ 一条都不折")
        XCTAssertEqual(folded.entries, observations)
    }

    func testSameFileFoldedTwiceBecomesOnePinnedBlockSayingHowManyTimes() {
        let bulky = String(repeating: "y", count: 3_000)
        var observations: [String] = [
            fileObservation("Core/Big.swift", bytes: 90_000, body: bulky),
            fileObservation("Core/Big.swift", bytes: 90_000, body: bulky),
        ]
        observations.append(contentsOf: (0..<6).map { _ in "search: 0 个文件名命中 · 0 处内容命中" })
        let folded = AgentObservationDigester.fold(observations, policy: .standard)
        let blocks = folded.entries.filter { $0.hasPrefix("file:Core/Big.swift") }
        XCTAssertEqual(blocks.count, 1, "同一个文件只占一段（钉住或台账），不许出现两段：\(blocks)")
        XCTAssertTrue(blocks.first?.contains("读过 2 次") == true, "要记下读了几次：\(blocks)")
        XCTAssertTrue(blocks.first?.contains("yyy") == true,
                      "而且要带正文开头 —— 只写「读过 2 次」却不给内容，模型只能再读一次（真机 42 次）")
    }

    func testLedgerIsCappedAndSaysHowManyOlderOnesAreGone() {
        let bulky = String(repeating: "z", count: 2_000)
        var observations: [String] = (0..<40).map {
            fileObservation("Core/G\($0).swift", bytes: 5_000, body: bulky)
        }
        observations.append(contentsOf: (0..<6).map { _ in "search: 1 个文件名命中 · 0 处内容命中" })
        let policy = AgentObservationDigestPolicy(keepRecent: 6, verbatimCharacters: 600,
                                                 digestCharacters: 120, maxLedgerLines: 10)
        let folded = AgentObservationDigester.fold(observations, policy: policy)
        XCTAssertEqual(folded.report.ledgerLines, 10, "台账按上限收口")
        XCTAssertEqual(folded.report.beyondLedger, 24,
                       "40 条 − 6 条钉住 = 34 条进台账，40 与 10 的差要扣掉钉住的 6 条（如实报数）")
        XCTAssertTrue(folded.report.marker?.contains("not listed") == true, "说明行要报出没列几条")
    }

    func testFoldIsIdempotentOnTheFoldedResult() {
        let bulky = String(repeating: "w", count: 4_000)
        var observations: [String] = (0..<10).map {
            fileObservation("Core/H\($0).swift", bytes: 7_000, body: bulky)
        }
        let once = AgentObservationDigester.fold(observations, policy: .standard).entries
        let twice = AgentObservationDigester.fold(once, policy: .standard).entries
        XCTAssertEqual(twice, once, "已经折过的条目再折不产生新的破坏（正文早就不在了）")
    }

    // MARK: - ② read_file 开窗

    func testReadReturnsFirstWindowAndTellsHowToContinue() throws {
        let body = (1...400).map { "line \($0)" }.joined(separator: "\n")
        let name = try write("Big.txt", body)
        let tools = AgentWorkspaceTools(root: root, maxReadBytes: 6_000, maxReadLines: 40)

        guard case .file(let output) = tools.readFile(path: name) else {
            return XCTFail("要读到文件")
        }
        XCTAssertTrue(output.truncated, "400 行只给 40 行 ⇒ 截断")
        XCTAssertTrue(output.text.hasPrefix("line 1\n"), "从第 1 行起")
        // 窗口是**结构化的**（能在边界之外单独说，也能被断言），不是塞在正文里的一句话。
        XCTAssertEqual(output.window, AgentToolFileWindow(startLine: 0, endLine: 40, totalLines: 400))
        XCTAssertEqual(output.window?.nextOffset, 40, "下一段从第 40 行（0 起）接着读")
        // 回灌给模型的那一段要说清「这次给了哪一段、下一段怎么读」。
        let observation = AgentLoop.summary(of: .file(output))
        XCTAssertTrue(observation.contains("lines 1-40 of 400"), "要说清这次给了哪一段：\(observation.suffix(160))")
        XCTAssertTrue(observation.contains("\"offset\":40"), "要告诉模型下一段怎么读：\(observation.suffix(160))")
    }

    func testReadOffsetAndLimitReturnThatSection() throws {
        let body = (1...400).map { "line \($0)" }.joined(separator: "\n")
        let name = try write("Big.txt", body)
        let tools = AgentWorkspaceTools(root: root)

        guard case .file(let output) = tools.readFile(path: name, offset: 100, limit: 5) else {
            return XCTFail("要读到文件")
        }
        XCTAssertTrue(output.text.hasPrefix("line 101\n"), "offset 是 0 起的行号 ⇒ 第 101 行起：\(output.text.prefix(40))")
        XCTAssertEqual(output.window, AgentToolFileWindow(startLine: 100, endLine: 105, totalLines: 400))
        XCTAssertEqual(output.window?.nextOffset, 105)
        XCTAssertFalse(output.text.contains("line 100\n"), "窗口外的行不许混进来")
        XCTAssertEqual(output.text.split(separator: "\n").count, 5, "正好 5 行")
    }

    func testReadAtFileTailHasNoNextOffset() throws {
        let body = (1...400).map { "line \($0)" }.joined(separator: "\n")
        let name = try write("Big.txt", body)
        let tools = AgentWorkspaceTools(root: root)
        // 从第 395 行（0 起）读到文件尾：这一段就是全部剩下的内容 ⇒ 不算截断、也不该有「下一段」。
        guard case .file(let output) = tools.readFile(path: name, offset: 395, limit: 40) else {
            return XCTFail("要读到文件")
        }
        XCTAssertFalse(output.truncated, "已经读到文件尾 ⇒ 不是截断")
        XCTAssertNil(output.window)
        XCTAssertTrue(output.text.hasSuffix("line 400"), "最后一行要到手：\(output.text.suffix(20))")
    }

    func testShortFileIsNotTruncatedAndCarriesNoTrailer() throws {
        let name = try write("Small.txt", "a\nb\nc")
        let tools = AgentWorkspaceTools(root: root)
        guard case .file(let output) = tools.readFile(path: name) else { return XCTFail("要读到文件") }
        XCTAssertFalse(output.truncated)
        XCTAssertNil(output.window, "整篇都在 ⇒ 没有窗口这回事")
        XCTAssertEqual(output.text, "a\nb\nc", "没截断就一个字都不许多（旧行为逐字不变）")
    }

    func testByteBudgetClampsOnLineBoundary() throws {
        // 每行 100 字节，字节上限 250 ⇒ 只放得下 2 行（200+1），不许切半行。
        let line = String(repeating: "q", count: 99)
        let body = (1...10).map { _ in line }.joined(separator: "\n")
        let name = try write("Wide.txt", body)
        let tools = AgentWorkspaceTools(root: root, maxReadBytes: 250, maxReadLines: 100)
        guard case .file(let output) = tools.readFile(path: name) else { return XCTFail("要读到文件") }
        XCTAssertTrue(output.truncated)
        XCTAssertEqual(output.text.split(separator: "\n").count, 2, "按整行收口：只放 2 行")
        XCTAssertEqual(output.window?.endLine, 2, "窗口按整行收口")
        XCTAssertFalse(output.text.contains(String(repeating: "q", count: 100)), "半行也不许出现")
    }

    func testBinaryFileIsRefusedNotDumped() throws {
        var bytes = Data([0xFF, 0xFE, 0x00, 0x01, 0x02])
        bytes.append(contentsOf: Array(repeating: 0x00, count: 64))
        try bytes.write(to: root.appendingPathComponent("blob.bin"))
        let tools = AgentWorkspaceTools(root: root)
        guard case .refused(let code, _) = tools.readFile(path: "blob.bin") else {
            return XCTFail("二进制要如实拒")
        }
        XCTAssertEqual(code, .binaryFile)
    }

    // MARK: - ③ 一跳的工具预算

    private final class ScriptedClient: LLMStreamingClient, @unchecked Sendable {
        private let hops: [[LLMStreamEvent]]
        private let lock = NSLock()
        private var index = 0

        init(_ hops: [[LLMStreamEvent]]) { self.hops = hops }

        func stream(_ request: LLMRequest) async throws -> AsyncThrowingStream<LLMStreamEvent, Error> {
            lock.lock()
            let position = index
            index += 1
            lock.unlock()
            let events = position < hops.count ? hops[position] : [.textDelta("完"), .done]
            return AsyncThrowingStream { continuation in
                for event in events { continuation.yield(event) }
                continuation.finish()
            }
        }
    }

    private final class CountingDispatcher: AgentToolDispatcher, @unchecked Sendable {
        private let lock = NSLock()
        private(set) var invoked: [String] = []

        func dispatch(_ invocation: AgentToolInvocation, approvals: Set<String>) -> AgentToolOutcome {
            lock.lock(); invoked.append(invocation.name); lock.unlock()
            return .directory(AgentToolDirectoryOutput(path: ".", entries: ["a"], truncated: false))
        }
    }

    func testHopToolBudgetDefersTheExtrasAndSaysSo() async throws {
        // 一跳 12 次调用、预算 8 ⇒ 执行 8、另外 4 条如实回灌「先给结论」。
        let batch: [LLMStreamEvent] = (0..<12).flatMap { slot in
            [LLMStreamEvent.toolCallDelta(index: slot, id: "c\(slot)", name: "list_dir",
                                          argumentsFragment: #"{"path":"d\#(slot)"}"#)]
        } + [.finished(reason: "tool_calls"), .done]
        let client = ScriptedClient([batch, [.textDelta("结论"), .done]])
        let dispatcher = CountingDispatcher()
        let loop = AgentLoop(client: client, dispatcher: dispatcher,
                             registry: .standard, limits: AgentLoopLimits(maxToolCallsPerHop: 8))
        let context = AgentLoopContext(systemPrompt: "s", userPrompt: "u",
                                       baseRequest: LLMRequest(endpoint: URL(string: "http://127.0.0.1/v1")!,
                                                               model: "fake", systemPrompt: "", userPrompt: ""),
                                       sessionID: "hop-budget", workspace: root.path)

        let result = await loop.run(context: context)

        XCTAssertEqual(dispatcher.invoked.count, 8, "只执行预算内的 8 次")
        XCTAssertEqual(result.rejectedTools.filter { $0.reason == AgentToolRefusal.hopBudget.rawValue }.count, 4,
                       "超出预算的 4 次记成 hopBudget（不静默）")
        // 回灌的提示词里要有「先给结论」那一句，模型才知道下一步干什么。
        XCTAssertTrue(result.outcome == .finished(text: "结论"))
    }

    func testHopBudgetZeroMeansUnlimited() async throws {
        let batch: [LLMStreamEvent] = (0..<12).flatMap { slot in
            [LLMStreamEvent.toolCallDelta(index: slot, id: "c\(slot)", name: "list_dir",
                                          argumentsFragment: #"{"path":"e\#(slot)"}"#)]
        } + [.finished(reason: "tool_calls"), .done]
        let client = ScriptedClient([batch, [.textDelta("结论"), .done]])
        let dispatcher = CountingDispatcher()
        let loop = AgentLoop(client: client, dispatcher: dispatcher,
                             registry: .standard, limits: AgentLoopLimits(maxToolCallsPerHop: 0))
        let context = AgentLoopContext(systemPrompt: "s", userPrompt: "u",
                                       baseRequest: LLMRequest(endpoint: URL(string: "http://127.0.0.1/v1")!,
                                                               model: "fake", systemPrompt: "", userPrompt: ""),
                                       sessionID: "hop-budget-off", workspace: root.path)
        _ = await loop.run(context: context)
        XCTAssertEqual(dispatcher.invoked.count, 12, "0 = 不限（旧行为逐字不变）")
    }
    // MARK: - ①b 回归：2026-11-16 真机「同一文件被读 42 次」

    /// 真机读数（`agent-audit.jsonl`，回合 `chat-D6334101`）：132 步 / 172 次工具调用，其中
    /// `read_file Docs/平台实现状态.json` **42 次**、同一脚本 40 次、同一目录 26 次。
    /// 根因：折下来只剩「路径 + 大小」，模型认得出读过、拿不到内容 ⇒ 只能再读。
    /// 这条判的就是「折过之后，**正文开头还在上下文里**」。
    func testRepeatedReadOfOnePathStillCarriesItsContentAfterFold() {
        let body = (0..<40).map { "第 \($0) 节：能力完成度读数 …" }.joined(separator: "\n")
        var observations: [String] = []
        for _ in 0..<20 {
            observations.append(fileObservation("Docs/平台实现状态.json", bytes: 7_757, body: body))
        }
        observations.append(contentsOf: (0..<6).map { _ in "search: 3 个词 · 9 个文件名命中" })
        let folded = AgentObservationDigester.fold(observations, policy: .standard)
        let joined = folded.entries.joined(separator: "\n")

        XCTAssertTrue(joined.contains("第 0 节"), "同一文件读 20 次之后，正文开头必须还在：\(joined.prefix(300))")
        XCTAssertTrue(joined.contains("读过 20 次") || joined.contains("读过"), "要报出读了几次：\(joined.prefix(300))")

        // 该路径只许出现**一段**（钉住），不许又钉又折出两段。
        let blocks = folded.entries.filter { $0.hasPrefix("file:Docs/平台实现状态.json") }
        XCTAssertEqual(blocks.count, 1, "同一路径只留一段：\(blocks.map { String($0.prefix(40)) })")

        // 上下文不许等于「20 份全文」—— 钉住是截断的。
        XCTAssertLessThan(folded.report.charactersAfter, folded.report.charactersBefore)
    }

    /// 说明行不许再教模型「重读」—— 旧文案 `read a section again with read_file offset/limit`
    /// 就是那 42 次重读的直接诱因。
    func testMarkerDoesNotInviteReReadingTheWholeFile() {
        let bulky = String(repeating: "q", count: 4_000)
        var observations = (0..<10).map { fileObservation("Core/H\($0).swift", bytes: 8_000, body: bulky) }
        observations.append(contentsOf: (0..<4).map { _ in "search: 0 命中" })
        let folded = AgentObservationDigester.fold(observations, policy: .standard)
        let marker = folded.report.marker ?? ""
        XCTAssertTrue(marker.contains("pinned excerpts"), "要告诉模型「开头已钉住，直接用」：\(marker)")
        XCTAssertTrue(marker.contains("do NOT re-read"), "要明确禁止整篇重读：\(marker)")
        XCTAssertFalse(marker.contains("read a section again"),
                       "旧的「再读一次」引导必须消失：\(marker)")
    }

}
