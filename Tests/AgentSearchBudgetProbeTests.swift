import XCTest
@testable import DoyahCore

/// **近义词重复搜索的三条改法 + 四条判据**（2026-11-07 真机：
/// 一轮 26 步 / 149.6 秒、56 次工具调用；`search` 被 `会话时间太长` / `会话超时` / `会话时间` /
/// `会话` / `界面错误` / `界面` 这类**近义改写**刷了十几次，每次 1.4–1.8 秒全仓扇扫）。
///
/// 改法三件：
/// ① 一次调用收多个词（`queries` 数组，或 `query` 里用空白分隔）⇒ 一次扫盘、逐词分组；
/// ② 同一轮搜索缓存 ⇒ 同词 / 包含关系的词毫秒级命中（写 / 执行即作废）；
/// ③ 只读工具**每轮总量**预算（`search` 6 次 / `list_dir` 6 次，可配）⇒ 近义改写也绕不过去。
///
/// 判据（每条都能判红）：
/// ① 一次传 3 个词 ⇒ **一次**调用返回 3 组命中（三组共享同一个扫盘读数）；
/// ② `会话时间太长` → `会话时间` ⇒ 第二次 `cached=true` 且 < 50ms；
/// ③ 连调 `search` 7 次 ⇒ 第 7 次被预算拦下并回灌「先用已有结果给结论」；
/// ④ 反例：关缓存 ⇒ ② 的耗时不达标（判红）；预算设 0 ⇒ ③ 拦不住（判红）。
///
/// 读数（前 / 后）由 `testNearSynonymSequenceBeforeAndAfter` 打 `PROBE_SEARCH_COST`。
final class AgentSearchBudgetProbeTests: XCTestCase {

    /// 真机截图里那一串近义词（顺序也照原样：越搜越短）。
    private static let nearSynonyms = ["会话时间太长", "会话超时", "会话时间", "会话", "界面错误", "界面"]

    private var workspaceRoot: URL!

    override func setUpWithError() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-search-probe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        // 真文件的临时副本（真文件数 / 真体积 ⇒ 扫盘耗时不是玩具量级），不碰活仓。
        for folder in ["Core", "App"] {
            let source = repo.appendingPathComponent(folder)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            try? FileManager.default.copyItem(at: source,
                                              to: destination.appendingPathComponent(folder))
        }
        workspaceRoot = destination
    }

    override func tearDownWithError() throws {
        if let workspaceRoot { try? FileManager.default.removeItem(at: workspaceRoot) }
    }

    // MARK: - 装置

    private func makeTools(cache: Bool) -> AgentWorkspaceTools {
        AgentWorkspaceTools(root: workspaceRoot, searchCache: cache ? AgentSearchCache() : nil)
    }

    private func makeDispatcher(_ tools: AgentWorkspaceTools,
                                guard guardrail: AgentRepeatGuard?) -> AgentStandardDispatcher {
        AgentStandardDispatcher(registry: .standard, workspace: tools, repeatGuard: guardrail)
    }

    /// 一条 `search` 调用（`queries` 数组形状）。
    private func searchCall(_ queries: [String], limit: Int = 20) -> AgentToolInvocation {
        let list = queries.map { "\"\($0)\"" }.joined(separator: ",")
        return AgentToolInvocation(name: AgentToolRegistry.searchToolName,
                                   argumentsJSON: "{\"queries\":[\(list)],\"limit\":\(limit)}")
    }

    /// 一条 `search` 调用（旧的单数 `query` 形状）。
    private func searchCall(query: String, limit: Int = 20) -> AgentToolInvocation {
        AgentToolInvocation(name: AgentToolRegistry.searchToolName,
                            argumentsJSON: "{\"query\":\"\(query)\",\"limit\":\(limit)}")
    }

    private func searchOutput(_ outcome: AgentToolOutcome,
                              file: StaticString = #filePath, line: UInt = #line) -> AgentToolSearchOutput? {
        guard case .search(let output) = outcome else {
            XCTFail("应当是搜索结果：\(outcome)", file: file, line: line)
            return nil
        }
        return output
    }

    // MARK: - 判据 ① 一次调用、多个词、逐词分组

    func testOneCallWithThreeWordsReturnsThreeGroups() throws {
        let tools = makeTools(cache: true)
        let dispatcher = makeDispatcher(tools, guard: AgentRepeatGuard())
        let words = ["会话时间太长", "会话超时", "会话时间"]

        let started = Date()
        let outcome = dispatcher.dispatch(searchCall(words), approvals: [])
        let elapsed = Int(Date().timeIntervalSince(started) * 1000)

        let output = try XCTUnwrap(searchOutput(outcome))
        XCTAssertEqual(output.groups.count, 3, "一次调用要回 3 组（不是 3 次调用）")
        XCTAssertEqual(output.groups.map(\.query), words, "组的顺序 = 词的顺序")
        XCTAssertEqual(output.queries, words, "回灌要说清「本次已搜过这 3 个词」")
        XCTAssertGreaterThan(output.contentHits.count, 0, "三个词都得真命中（否则这条判据是空转）")
        output.groups.forEach { XCTAssertFalse($0.cached, "第一次搜，不该有缓存") }

        // **一次扫盘**的证据：三组的扫盘读数完全相同（分开扫会是三个不同的数）。
        let scans = Set(output.groups.map(\.elapsedMillis))
        XCTAssertEqual(scans.count, 1, "3 个词共享一次扫盘，实际：\(output.groups.map(\.elapsedMillis))")
        XCTAssertNotNil(scans.first)

        // 回灌给模型的那一段：必须逐词分组 + 明说「本次已搜过这 N 个词」（否则它下一步还会逐词重搜）。
        let rendered = AgentLoop.summary(of: outcome)
        XCTAssertTrue(rendered.contains("本次已搜过这 3 个词"), "回灌要有一句「本次已搜过这 3 个词」：\(rendered.prefix(160))")
        for word in words {
            XCTAssertTrue(rendered.contains("· 词「\(word)」"), "每个词都要有自己的一组：\(word)")
        }

        print("PROBE_SEARCH_MULTI {\"words\":\(words.count),\"groups\":\(output.groups.count),"
              + "\"calls\":1,\"millis\":\(elapsed),"
              + "\"groupMillis\":\(output.groups.first?.elapsedMillis ?? -1),"
              + "\"contentHits\":\(output.contentHits.count),"
              + "\"noteSearched\":\(rendered.contains("本次已搜过这 3 个词"))}")
    }

    // MARK: - 判据 ② 包含关系的词吃缓存

    func testContainedWordHitsCache() throws {
        let tools = makeTools(cache: true)

        let first = try XCTUnwrap(searchOutput(tools.search(query: "会话时间太长", limit: 20)))
        XCTAssertFalse(first.groups.first?.cached ?? true)

        let started = Date()
        let second = try XCTUnwrap(searchOutput(tools.search(query: "会话时间", limit: 20)))
        let elapsed = Int(Date().timeIntervalSince(started) * 1000)

        let group = try XCTUnwrap(second.groups.first)
        XCTAssertTrue(group.cached, "已搜过「会话时间太长」，再搜「会话时间」要命中缓存")
        XCTAssertTrue(group.partial, "来自别的词 ⇒ 覆盖不全，必须标出来")
        XCTAssertEqual(group.source, "会话时间太长")
        XCTAssertGreaterThan(group.contentHits.count, 0, "缓存里要真挑得出含这个词的行")
        XCTAssertLessThan(elapsed, 50, "缓存命中要毫秒级（实测 \(elapsed)ms；不达标 ⇒ 判红）")
        print("PROBE_SEARCH_CACHE {\"firstMillis\":\(first.elapsedMillis),"
              + "\"secondMillis\":\(elapsed),\"cached\":\(group.cached),"
              + "\"partial\":\(group.partial),\"hits\":\(group.contentHits.count)}")
    }

    // MARK: - 判据 ③ 第七次 search 被每轮预算拦下

    func testSeventhSearchIsStoppedByTurnBudget() throws {
        let tools = makeTools(cache: false)          // 缓存关掉：确保 7 次都真的走到预算那一段
        let guardrail = AgentRepeatGuard()           // 默认 search 6 次 / 轮
        let dispatcher = makeDispatcher(tools, guard: guardrail)
        let words = ["会话超时", "会话时间", "会话记录", "会话状态", "界面错误", "界面提示", "会话恢复"]

        var executed = 0
        var denial: String?
        for (index, word) in words.enumerated() {
            let outcome = dispatcher.dispatch(searchCall(query: word, limit: 5), approvals: [])
            switch outcome {
            case .search: executed += 1
            case .refused(_, let detail):
                if index == words.count - 1 { denial = detail }
            default: break
            }
        }

        XCTAssertEqual(executed, 6, "前 6 次照常执行")
        let reason = try XCTUnwrap(denial, "第 7 次必须被拦下")
        XCTAssertTrue(reason.contains("tool-budget"), "拒因要带机器码：\(reason)")
        XCTAssertTrue(reason.contains("先用已有结果给结论"), "回灌的话要能照着做：\(reason)")
        XCTAssertTrue(reason.contains("queries"), "还要告诉它「多个词一次给」：\(reason)")
        XCTAssertEqual(guardrail.used(.search), 7, "被拦的那一次也记进读数（不然读数会骗人）")
        print("PROBE_SEARCH_BUDGET {\"executed\":\(executed),\"deniedAt\":7,"
              + "\"used\":\(guardrail.used(.search)),\"reason\":\"\(reason.prefix(40))\"}")
    }

    // MARK: - 判据 ④ 两条反例（判据本身要能判红）

    /// 反例 A：把缓存关掉 ⇒ ② 的耗时不达标。若这里「也很快」，说明 ② 量的不是缓存。
    func testCounterexampleWithoutCacheSecondSearchStillScans() throws {
        let tools = makeTools(cache: false)

        let first = try XCTUnwrap(searchOutput(tools.search(query: "会话时间太长", limit: 20)))
        let started = Date()
        let second = try XCTUnwrap(searchOutput(tools.search(query: "会话时间", limit: 20)))
        let elapsed = Int(Date().timeIntervalSince(started) * 1000)

        let group = try XCTUnwrap(second.groups.first)
        XCTAssertFalse(group.cached, "关掉缓存就不该有 cached")
        XCTAssertGreaterThanOrEqual(elapsed, 50,
                                    "反例：关缓存后第二次仍要全仓扫（实测 \(elapsed)ms）"
                                    + "—— 若 < 50ms，说明 ② 的耗时判据在空转")
        print("PROBE_SEARCH_CACHE_OFF {\"firstMillis\":\(first.elapsedMillis),"
              + "\"secondMillis\":\(elapsed),\"cached\":\(group.cached)}")
    }

    /// 反例 B：预算设 0（= 不限）⇒ ③ 拦不住。若这里也被拦，说明 ③ 量的不是预算。
    func testCounterexampleWithoutBudgetSeventhSearchIsAllowed() throws {
        let tools = makeTools(cache: false)
        let guardrail = AgentRepeatGuard(policy: .init(turnBudget: [:]))
        let dispatcher = makeDispatcher(tools, guard: guardrail)
        let words = ["会话超时", "会话时间", "会话记录", "会话状态", "界面错误", "界面提示", "会话恢复"]

        var executed = 0
        for word in words {
            if case .search = dispatcher.dispatch(searchCall(query: word, limit: 5), approvals: []) {
                executed += 1
            }
        }
        XCTAssertEqual(executed, 7, "预算关掉时 7 次都该执行（否则 ③ 判不出东西）")
        print("PROBE_SEARCH_BUDGET_OFF {\"executed\":\(executed)}")
    }

    // MARK: - 前后耗时对照（同一种「近义词连搜」场景，同一份真工作区）

    /// 同一个任务的三种跑法，**6 个近义词**（真机截图里那一串）：
    ///
    /// · 改前：一个词一条调用（6 次调用 / 6 次全仓扫盘 / 6 次模型往返 —— 模型往返约 9 秒/次，这里只量工具侧）；
    /// · 改后（两批）：两个词三个一组（2 次调用 / 2 次扫盘，「会话」吃缓存）；
    /// · 改后（一把）：6 个词一次给（1 次调用 / 1 次扫盘）。
    func testNearSynonymSequenceBeforeAndAfter() throws {
        // —— 改前 ——
        let legacyTools = makeTools(cache: false)
        let legacyDispatcher = makeDispatcher(legacyTools,
                                              guard: AgentRepeatGuard(policy: .init(turnBudget: [:])))
        let legacyStart = Date()
        var legacyCalls = 0
        var legacyScans = 0
        for word in Self.nearSynonyms {
            let output = try XCTUnwrap(
                searchOutput(legacyDispatcher.dispatch(searchCall(query: word), approvals: [])))
            legacyCalls += 1
            if output.groups.contains(where: { !$0.cached }) { legacyScans += 1 }
        }
        let legacyMillis = Int(Date().timeIntervalSince(legacyStart) * 1000)

        // —— 改后（两批）——
        let tools = makeTools(cache: true)
        let dispatcher = makeDispatcher(tools, guard: AgentRepeatGuard())
        let modernStart = Date()
        var modernCalls = 0
        var modernScans = 0
        var cachedGroups = 0
        for batch in [Array(Self.nearSynonyms.prefix(3)), Array(Self.nearSynonyms.suffix(3))] {
            let output = try XCTUnwrap(searchOutput(dispatcher.dispatch(searchCall(batch), approvals: [])))
            modernCalls += 1
            cachedGroups += output.groups.filter(\.cached).count
            if output.groups.contains(where: { !$0.cached }) { modernScans += 1 }
        }
        let modernMillis = Int(Date().timeIntervalSince(modernStart) * 1000)

        // —— 改后（一把全给）——
        let oneShotTools = makeTools(cache: true)
        let oneShotDispatcher = makeDispatcher(oneShotTools, guard: AgentRepeatGuard())
        let oneShotStart = Date()
        let oneShotOutput = try XCTUnwrap(searchOutput(
            oneShotDispatcher.dispatch(searchCall(Self.nearSynonyms), approvals: [])))
        let oneShotMillis = Int(Date().timeIntervalSince(oneShotStart) * 1000)
        let oneShotScans = oneShotOutput.groups.contains(where: { !$0.cached }) ? 1 : 0

        print("PROBE_SEARCH_COST {\"words\":\(Self.nearSynonyms.count),"
              + "\"legacy\":{\"calls\":\(legacyCalls),\"scans\":\(legacyScans),\"millis\":\(legacyMillis)},"
              + "\"batched\":{\"calls\":\(modernCalls),\"scans\":\(modernScans),"
              + "\"cachedGroups\":\(cachedGroups),\"millis\":\(modernMillis)},"
              + "\"oneShot\":{\"calls\":1,\"scans\":\(oneShotScans),"
              + "\"groups\":\(oneShotOutput.groups.count),\"millis\":\(oneShotMillis)}}")

        XCTAssertEqual(legacyCalls, 6)
        XCTAssertEqual(legacyScans, 6, "改前：6 个词 = 6 次全仓扫")
        XCTAssertEqual(modernCalls, 2, "改后：6 个词 = 2 次调用")
        XCTAssertEqual(modernScans, 2, "改后：6 个词 = 2 次扫盘（「会话」吃缓存）")
        XCTAssertGreaterThan(cachedGroups, 0)
        XCTAssertEqual(oneShotOutput.groups.count, 6, "一把给 6 个词 ⇒ 回 6 组")
        XCTAssertEqual(oneShotScans, 1, "一把给 6 个词 ⇒ 只扫一次盘")
        XCTAssertLessThan(modernMillis, legacyMillis,
                          "改后要比改前快：\(modernMillis)ms vs \(legacyMillis)ms")
        XCTAssertLessThan(oneShotMillis, legacyMillis,
                          "一把给比逐词搜快：\(oneShotMillis)ms vs \(legacyMillis)ms")
    }
}
