import XCTest
@testable import DoyahCore

/// `NFR-AI-08` ③（**压缩半**）的机械判据 —— 「有损但**如实**」逐条落到断言上。
///
/// 契约只钉两件事：① 超限要压（不能把超限正文照发）；② 压了要**数得出来、说得出丢了哪些**
/// （`R-63` ③ 的负例：压缩后既不报、又答不上「丢了哪些」）。
/// 压缩算法与阈值是**参数**，所以这里用小预算把每条分支都逼出来，不去假定某个具体算法。
final class AgentContextCompressionTests: XCTestCase {

    // MARK: - ① 没超预算：一条都不动（不虚报）

    func testLeavesEverythingAloneWhenItFitsTheBudget() {
        let entries = ["read_file: file:a.txt:6", "search: 2:1"]
        let budget = AgentContextCompressionBudget(maxPromptCharacters: 10_000)

        let result = AgentContextCompressor.compress(entries: entries, baseCharacters: 100, budget: budget)

        XCTAssertEqual(result.entries, entries, "没超限就该逐字不动")
        XCTAssertFalse(result.report.didCompress)
        XCTAssertEqual(result.report.compressedEntries, 0)
        XCTAssertEqual(result.report.estimatedTokensSaved, 0)
        XCTAssertTrue(result.report.droppedDigests.isEmpty, "没压就没有「丢了哪些」")
        XCTAssertNil(result.report.marker, "没压就不许插 marker（插了模型会以为丢过东西）")
        XCTAssertEqual(result.report.promptCharactersAfter, result.report.promptCharactersBefore)
    }

    // MARK: - ② 超预算：压掉最老的、留住最近的

    func testCompressesTheOldestEntriesAndKeepsTheRecentOnesVerbatim() {
        // 条目按**真实体量**造（工具返回一行就有几十上百字）：marker 只有一行，
        // 用小预算 + 超短条目会让「压完变短」这条断言失真 —— 那是判据自己的毛病，不是实现的。
        let entries = (1...8).map { index in
            "tool\(index): file:f\(index).txt:" + String(repeating: "x", count: 300)
        }
        let budget = AgentContextCompressionBudget(maxPromptCharacters: 1_000,
                                                   keepRecentEntries: 3,
                                                   minimumEntries: 4)

        let result = AgentContextCompressor.compress(entries: entries, baseCharacters: 40, budget: budget)

        XCTAssertTrue(result.report.didCompress)
        XCTAssertEqual(result.report.keptEntries, 3, "保留区条数 = keepRecentEntries")
        XCTAssertEqual(result.report.compressedEntries + result.report.keptEntries, entries.count,
                       "压掉的 + 留住的 = 原来那些（不许悄悄多丢一条）")
        XCTAssertEqual(Array(result.entries.dropFirst()), Array(entries.suffix(3)),
                       "留住的必须是**最近的**三条，且逐字不改")
        XCTAssertEqual(result.entries.first, result.report.marker, "首条是 marker（模型要知道折过）")
        XCTAssertLessThan(result.report.promptCharactersAfter, result.report.promptCharactersBefore,
                          "压完必须真的变短")
        XCTAssertEqual(result.report.estimatedTokensSaved,
                       AgentContextCompressor.estimatedTokens(characters: result.report.droppedCharacters))
    }

    // MARK: - ③ 负例（`R-63` ③）：压了就必须说得出「丢了哪些」

    func testCompressedRunCanAlwaysNameWhatItDropped() {
        let entries = ["alpha: file:a.txt:1", "beta: search:3:0", "gamma: command:0",
                       "delta: file:d.txt:4", "epsilon: file:e.txt:5", "zeta: file:z.txt:6"]
            .map { $0 + String(repeating: "y", count: 200) }
        let budget = AgentContextCompressionBudget(maxPromptCharacters: 800,
                                                   keepRecentEntries: 2,
                                                   minimumEntries: 3)

        let result = AgentContextCompressor.compress(entries: entries, baseCharacters: 30, budget: budget)

        XCTAssertTrue(result.report.didCompress)
        XCTAssertEqual(result.report.droppedDigests.count, result.report.compressedEntries,
                       "压掉几条就要有几条摘要 —— 数不出「丢了哪些」就是静默压缩")
        // 每条摘要是**原文**的前缀（不是另编的一句话）
        for (index, digest) in result.report.droppedDigests.enumerated() {
            XCTAssertTrue(entries[index].hasPrefix(digest),
                          "第 \(index + 1) 条摘要要能对回原文：\(digest)")
        }
        let marker = try? XCTUnwrap(result.report.marker)
        XCTAssertTrue((marker ?? "").contains("\(result.report.compressedEntries)"),
                      "marker 里要带得出压了几条（读数是给人看的，marker 是给模型看的）")
    }

    // MARK: - ④ 只压到够用为止（不把保留区也压掉）

    func testStopsAsSoonAsThePromptFitsAgain() {
        let entries = (1...6).map { index in
            "tool\(index): file:f\(index).txt:" + String(repeating: "z", count: 300)
        }
        // 预算刚好比满额少一条（再留出 marker 的位置）⇒ 只该丢一条
        let full = entries.reduce(0) { $0 + $1.count } + (entries.count - 1)
        let budget = AgentContextCompressionBudget(maxPromptCharacters: full - 40,
                                                   keepRecentEntries: 1,
                                                   minimumEntries: 3)

        let result = AgentContextCompressor.compress(entries: entries, baseCharacters: 0, budget: budget)

        XCTAssertTrue(result.report.didCompress)
        XCTAssertEqual(result.report.compressedEntries, 1, "够用就停：多丢一条都是白丢")
        XCTAssertEqual(result.report.keptEntries, 5)
    }

    // MARK: - ⑤ 条目全在保留区 / 太少：一条都不压，但超预算要如实说

    func testReportsStillOverBudgetInsteadOfPretendingItFits() {
        let entries = ["a: 1", "b: 2"]
        let budget = AgentContextCompressionBudget(maxPromptCharacters: 5,
                                                   keepRecentEntries: 4,
                                                   minimumEntries: 6)

        let result = AgentContextCompressor.compress(entries: entries, baseCharacters: 100, budget: budget)

        XCTAssertFalse(result.report.didCompress)
        XCTAssertEqual(result.entries, entries)
        XCTAssertTrue(result.report.stillOverBudget, "压不动就说压不动，不许假装已经落进预算")
        XCTAssertEqual(result.report.compressedEntries, 0)
    }

    // MARK: - ⑥ 估算口径只有一个出处

    func testTokenEstimateIsCeilingOfOneQuarterOfCharacters() {
        XCTAssertEqual(AgentContextCompressor.estimatedTokens(characters: 0), 0)
        XCTAssertEqual(AgentContextCompressor.estimatedTokens(characters: 1), 1)
        XCTAssertEqual(AgentContextCompressor.estimatedTokens(characters: 4), 1)
        XCTAssertEqual(AgentContextCompressor.estimatedTokens(characters: 5), 2)
        XCTAssertEqual(AgentContextCompressor.estimatedTokens(characters: 400), 100)
    }

    // MARK: - ⑦ 循环接线：超限那一跳的请求真的变短了，读数也报得出来

    /// 按跳脚本吐事件的假模型（记录每次请求 —— 判据要按请求正文对拍）。
    private final class ScriptedClient: LLMStreamingClient, @unchecked Sendable {
        private let toolHops: Int
        private(set) var requests: [LLMRequest] = []

        init(toolHops: Int) { self.toolHops = toolHops }

        func stream(_ request: LLMRequest) async throws -> AsyncThrowingStream<LLMStreamEvent, Error> {
            requests.append(request)
            let events: [LLMStreamEvent]
            if requests.count <= toolHops {
                events = [.toolCallDelta(index: 0, id: "call-\(requests.count)",
                                         name: "read_file",
                                         argumentsFragment: #"{"path":"a.txt"}"#),
                          .finished(reason: "tool_calls"), .done]
            } else {
                events = [.textDelta("done"), .finished(reason: "stop"), .done]
            }
            return AsyncThrowingStream { continuation in
                for event in events { continuation.yield(event) }
                continuation.finish()
            }
        }
    }

    private final class StubDispatcher: AgentToolDispatcher, @unchecked Sendable {
        private let text: String
        init(text: String) { self.text = text }
        func dispatch(_ invocation: AgentToolInvocation, approvals: Set<String>) -> AgentToolOutcome {
            .file(AgentToolFileOutput(path: "a.txt", text: text, truncated: false, totalBytes: text.utf8.count))
        }
    }

    private final class EventRecorder: AgentLoopObserver, @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [AgentLoopEvent] = []
        var events: [AgentLoopEvent] { lock.lock(); defer { lock.unlock() }; return stored }
        func observe(_ event: AgentLoopEvent) async { lock.lock(); stored.append(event); lock.unlock() }
    }

    private func context(prompt: String = "读一下 a.txt") -> AgentLoopContext {
        AgentLoopContext(systemPrompt: "你是助手。",
                         userPrompt: prompt,
                         baseRequest: LLMRequest(endpoint: URL(string: "http://127.0.0.1:11434/v1")!,
                                                 model: "fake", systemPrompt: "", userPrompt: ""),
                         sessionID: "s-compress", workspace: "ws-c")
    }

    func testLoopCompressesWithinBudgetAndReportsTheNumbers() async {
        let client = ScriptedClient(toolHops: 6)
        let reader = EventRecorder()
        let loop = AgentLoop(client: client,
                             dispatcher: StubDispatcher(text: "内容"),
                             registry: .standard,
                             observer: reader,
                             compressionBudget: AgentContextCompressionBudget(maxPromptCharacters: 120,
                                                                              keepRecentEntries: 2,
                                                                              minimumEntries: 3))

        let result = await loop.run(context: context())

        XCTAssertEqual(result.outcome, .finished(text: "done"))
        XCTAssertGreaterThan(result.compressedEntries, 0, "六跳的观察段超了预算 ⇒ 必须真压过")
        XCTAssertEqual(result.compressedDigests.count, result.compressedEntries,
                       "丢了哪些要能逐条数出来")
        XCTAssertGreaterThan(result.estimatedTokensSaved, 0)

        // 压过的那一跳请求里带 marker（模型知道早期结果被折叠），且正文比「不压」时短
        let compressedRequest = try? XCTUnwrap(client.requests.last)
        XCTAssertTrue((compressedRequest?.userPrompt ?? "").contains("[context compressed:"),
                      "压过就要在提示词里留记号：\(compressedRequest?.userPrompt ?? "")")
        XCTAssertTrue((compressedRequest?.userPrompt ?? "").contains("上一次执行结果"),
                      "回灌段本身还在（压的是早期条目，不是整段）")

        // 事件面：压缩不许静默 —— 至少一条 `contextCompressed`，且数对得上
        let events = reader.events.compactMap { event -> (Int, Int)? in
            if case .contextCompressed(let entries, let saved, _, _) = event { return (entries, saved) }
            return nil
        }
        XCTAssertFalse(events.isEmpty, "压缩必须报事件（界面那一行吃的就是它）")
        XCTAssertEqual(events.reduce(0) { $0 + $1.0 }, result.compressedEntries,
                       "事件里的条数加起来 = 结果里的累计条数")
    }

    // MARK: - ⑧ 没给预算：旧行为逐字不变（回归判据）

    func testWithoutABudgetThePromptIsByteForByteTheSameAsBefore() async {
        let client = ScriptedClient(toolHops: 3)
        let loop = AgentLoop(client: client, dispatcher: StubDispatcher(text: "内容"), registry: .standard)

        let result = await loop.run(context: context())

        XCTAssertEqual(result.compressedEntries, 0)
        XCTAssertTrue(result.compressedDigests.isEmpty)
        XCTAssertFalse(client.requests.contains { $0.userPrompt.contains("[context compressed:") },
                       "没配预算就一个字都不许改（老判据按提示词逐字对拍）")
    }

    // MARK: - ⑨ 界面读数：跨轮累计，且带得出「最早被压掉的那条」

    func testChatStateAccumulatesTheCompressionReadingAcrossRuns() {
        var state = AgentChatState()
        XCTAssertNil(state.contextCompression, "一次没压过 ⇒ 那格不出现（不留空壳）")

        state.apply(.contextCompressed(entries: 3, estimatedTokensSaved: 120, kept: 4, earliest: "read_file: file:a.txt:6"))
        XCTAssertEqual(state.contextCompression?.entries, 3)
        XCTAssertEqual(state.contextCompression?.estimatedTokensSaved, 120)
        XCTAssertEqual(state.contextCompression?.kept, 4)
        XCTAssertEqual(state.contextCompression?.earliest, "read_file: file:a.txt:6")

        state.apply(.contextCompressed(entries: 2, estimatedTokensSaved: 40, kept: 4, earliest: "search: 2:1"))
        XCTAssertEqual(state.contextCompression?.entries, 5, "跨轮累计：3 + 2")
        XCTAssertEqual(state.contextCompression?.estimatedTokensSaved, 160)
        XCTAssertEqual(state.contextCompression?.earliest, "search: 2:1", "最近一次压掉的那条（人点开看的就是它）")
    }
}
