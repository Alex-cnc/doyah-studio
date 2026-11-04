import XCTest
@testable import DoyahCore
@testable import DoyahStudioApp

/// `FR-AGT-TOOL-SYS-002`（子任务委派）的**真机缺陷判据**。
///
/// 由头（2026-11-04 真机取证）：子任务真起了、真并行，但
/// ① 三路 token 逐字交错进主对话（`…Plug命中的ins是/ RetAppro//Sources…`），步数合并计数
///    27→41→79→93→153→193（已超 `maxSteps=150`，而主控只有 19 条审计）；
/// ② 4 批子任务 `completed=0 / failed=3(timedOut)` —— 预算收到却没接到子循环的截止时间上，
///    成果在超时那一刻整段丢掉（摘要只剩 `timeout`）；
/// ③ 同 id 重派沿用同一个子会话号 ⇒ 第二批接着上一批的上下文接着跑。
///
/// 下面四条各自都能**判红**（去掉修复后必红）：
/// ① 真跑一次委派：主 observer 的事件流里**一条**子路 token 都不许出现，主循环跳数 = 2（≤ `maxSteps`）；
/// ② 预算 3 秒的子任务 ≤5 秒返回，且状态 `partial`、摘要带正文（不是只有 `timeout`）；
/// ③ 连续两批同 id：两个不同的子会话号，第二批的会话文件里没有第一批的正文；
/// ④ 子路事件只进**它自己**那本账（`AgentSubtaskLedger`），正文在账里查得到。
final class AgentSubtaskIsolationTests: XCTestCase {

    // MARK: - 夹具

    /// 记事件流的观察口（就是真机上界面那一个口）。
    private final class RecordingObserver: AgentLoopObserver, @unchecked Sendable {
        private let lock = NSLock()
        private var events: [AgentLoopEvent] = []

        func observe(_ event: AgentLoopEvent) async {
            lock.lock(); events.append(event); lock.unlock()
        }

        var snapshot: [AgentLoopEvent] {
            lock.lock(); defer { lock.unlock() }; return events
        }

        /// 主口一共收到多少正文（子路混进来就会变长）。
        var deltaText: String {
            snapshot.compactMap { if case .delta(let piece) = $0 { return piece } else { return nil } }.joined()
        }

        var hopIndices: [Int] {
            snapshot.compactMap { if case .hopStarted(let index) = $0 { return index } else { return nil } }
        }
    }

    private final class RecordingAudit: AgentAuditSink, @unchecked Sendable {
        private let lock = NSLock()
        private var records: [AgentActionRecord] = []

        func record(_ record: AgentActionRecord) async {
            lock.lock(); records.append(record); lock.unlock()
        }

        var sessionIDs: [String] {
            lock.lock(); defer { lock.unlock() }; return records.compactMap(\.sessionID)
        }
    }

    /// 按提示词分脚本的假模型；`slowKeys` 里的那一路**先吐一句再睡 8 秒**（模拟翻目录翻到不计时）。
    private final class ScriptedClient: LLMStreamingClient, @unchecked Sendable {
        private let lock = NSLock()
        private var script: [String: [[LLMStreamEvent]]] = [:]
        private var slowKeys: Set<String> = []
        private var hopDelays: [String: TimeInterval] = [:]
        private var prompts: [String] = []

        func script(_ key: String, _ hops: [[LLMStreamEvent]]) {
            lock.lock(); script[key] = hops; lock.unlock()
        }

        func slow(_ key: String) {
            lock.lock(); slowKeys.insert(key); lock.unlock()
        }

        /// 每一跳先睡这么久再回话（模拟「真的在翻目录」的耗时）。
        func delay(_ key: String, _ seconds: TimeInterval) {
            lock.lock(); hopDelays[key] = seconds; lock.unlock()
        }

        func stream(_ request: LLMRequest) async throws -> AsyncThrowingStream<LLMStreamEvent, Error> {
            lock.lock()
            prompts.append(request.userPrompt)
            let key = script.keys.first { request.userPrompt.contains($0) } ?? request.userPrompt
            var hops = script[key] ?? [[.textDelta("OK"), .finished(reason: "stop")]]
            let events = hops.count > 1 ? hops.removeFirst() : hops[0]
            script[key] = hops
            let slow = slowKeys.contains(key)
            let hopDelay = hopDelays[key] ?? 0
            lock.unlock()

            if hopDelay > 0 { try? await Task.sleep(nanoseconds: UInt64(hopDelay * 1_000_000_000)) }

            return AsyncThrowingStream { continuation in
                Task {
                    for event in events { continuation.yield(event) }
                    if slow {
                        // 第一句已经吐出来了（= 已有成果），随后卡在「还在翻」上。
                        try? await Task.sleep(nanoseconds: 8_000_000_000)
                    }
                    continuation.yield(.finished(reason: "stop"))
                    continuation.finish()
                }
            }
        }

        var promptsSnapshot: [String] {
            lock.lock(); defer { lock.unlock() }; return prompts
        }
    }

    private final class NoopDispatcher: AgentToolDispatcher, @unchecked Sendable {
        func dispatch(_ invocation: AgentToolInvocation, approvals: Set<String>) -> AgentToolOutcome {
            .file(AgentToolFileOutput(path: invocation.name, text: "", truncated: false, totalBytes: 0))
        }
    }

    private func context(prompt: String) -> AgentLoopContext {
        AgentLoopContext(systemPrompt: "系统", userPrompt: prompt,
                         baseRequest: LLMRequest(endpoint: URL(string: "http://127.0.0.1:1/v1")!,
                                                 model: "fake", systemPrompt: "", userPrompt: ""),
                         sessionID: "parent-sess", workspace: "ws")
    }

    private func dispatchHop(_ entries: [(String, String, String)]) -> LLMStreamEvent {
        let array = entries.map { ["id": $0.0, "label": $0.1, "prompt": $0.2] }
        let inner = String(data: try! JSONSerialization.data(withJSONObject: array), encoding: .utf8)!
        let root = String(data: try! JSONSerialization.data(withJSONObject: ["tasks": inner]), encoding: .utf8)!
        return .toolCallDelta(index: 0, id: "c\(entries.map(\.0).joined())",
                              name: "dispatch_subtasks", argumentsFragment: root)
    }

    private func tempStore() throws -> AgentSessionStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("doyah-subtask-iso-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return AgentSessionStore(directory: dir)
    }

    // MARK: - ① 混流

    /// 真跑一次委派：主 observer 只许收到主循环的事件。
    ///
    /// 判红点：子路 `delta` / `hopStarted` 一旦灌进同一个 observer，下面的 `SUBA` / `SUBB` 断言就红。
    func testRealDispatchNeverLeaksSubtaskEventsIntoMainTranscript() async {
        let client = ScriptedClient()
        client.script("主任务", [[dispatchHop([("a", "La", "做 a"), ("b", "Lb", "做 b")]),
                                .finished(reason: "tool_calls")],
                               [.textDelta("都做完了"), .finished(reason: "stop")]])
        client.script("做 a", [[.textDelta("SUBA-结论"), .finished(reason: "stop")]])
        client.script("做 b", [[.textDelta("SUBB-结论"), .finished(reason: "stop")]])

        let mainObserver = RecordingObserver()
        var loop = AgentLoop(client: client, dispatcher: NoopDispatcher(), observer: mainObserver)
        loop.subagentPolicy = AgentSubagentPolicy(maxConcurrent: 2, defaultBudgetSeconds: 30)
        let result = await loop.run(context: context(prompt: "主任务"))

        XCTAssertEqual(result.outcome, .finished(text: "都做完了"))

        let delta = mainObserver.deltaText
        XCTAssertTrue(delta.contains("都做完了"), "主循环自己的增量要在主对话里：\(delta)")
        XCTAssertFalse(delta.contains("SUBA"), "子任务的 token 灌进了主对话：\(delta)")
        XCTAssertFalse(delta.contains("SUBB"), "子任务的 token 灌进了主对话：\(delta)")
        XCTAssertEqual(mainObserver.hopIndices, [0, 1], "主对话只该有主循环的两跳：\(mainObserver.hopIndices)")
        // ④ 步数计数不得因混流而涨过 `maxSteps`
        XCTAssertLessThanOrEqual(mainObserver.hopIndices.count, loop.limits.maxSteps)
        XCTAssertTrue(mainObserver.snapshot.allSatisfy { event in
            if case .toolStarted(let name, _) = event { return name != "__subtask_marker__" }
            return true
        })
    }

    // MARK: - ② 预算

    /// 预算 3 秒：到点**带着已有正文收尾**（`partial`），不是杀掉后只回一句 `timeout`。
    func testThreeSecondBudgetReturnsPartialWithinFiveSeconds() async {
        let client = ScriptedClient()
        client.script("慢活", [[.textDelta("先给结论：预算内能拿到的这一句")]])
        client.slow("慢活")

        var loop = AgentLoop(client: client, dispatcher: NoopDispatcher())
        loop.subagentPolicy = AgentSubagentPolicy(maxConcurrent: 1, defaultBudgetSeconds: 3)
        let runner = AgentLoopSubtaskRunner(loop: loop, template: context(prompt: "主任务"))
        let executor = AgentSubagentExecutor(
            policy: AgentSubagentPolicy(maxConcurrent: 1, defaultBudgetSeconds: 3), runner: runner)
        let spec = AgentSubtaskSpec(id: "s1", label: "S1", prompt: "慢活", budgetSeconds: 3)

        let started = Date()
        let report = await executor.run([spec])
        let elapsed = Date().timeIntervalSince(started)

        let result = try! XCTUnwrap(report.results.first)
        XCTAssertLessThanOrEqual(elapsed, 5.0, "预算 3 秒的子任务必须在 5 秒内收尾（实测 \(elapsed)s）")
        XCTAssertEqual(result.status, .partial, "到点要交部分成果，不是判死：\(result.status)")
        XCTAssertNotEqual(result.summary, "timeout", "摘要不许只剩一个 timeout")
        XCTAssertTrue(result.summary.contains("先给结论"), "已有正文要带回来：\(result.summary)")
        // 子代理的提示词里得写明预算（否则它会一路翻到不看表）
        XCTAssertTrue(client.promptsSnapshot.contains { $0.contains("3 秒") },
                      "子代理提示词里没写预算：\(client.promptsSnapshot)")
    }

    // MARK: - ③ 重派

    /// 同一 id 连派两批：子会话号必须换（第二批不许接着第一批的上下文）。
    func testRerunGetsFreshChildSessionAndVoidsPriorContext() async throws {
        let client = ScriptedClient()
        client.script("主任务", [[dispatchHop([("a", "La", "做 a")]), .finished(reason: "tool_calls")],
                                [dispatchHop([("a", "La", "做 a")]), .finished(reason: "tool_calls")],
                                [.textDelta("收尾"), .finished(reason: "stop")]])
        client.script("做 a", [[.textDelta("第一轮结论FIRST"), .finished(reason: "stop")],
                               [.textDelta("第二轮结论SECOND"), .finished(reason: "stop")]])

        let store = try tempStore()
        let audit = RecordingAudit()
        var loop = AgentLoop(client: client, dispatcher: NoopDispatcher(),
                             sessionStore: store, audit: audit)
        loop.subagentPolicy = AgentSubagentPolicy(maxConcurrent: 1, defaultBudgetSeconds: 30)
        let result = await loop.run(context: context(prompt: "主任务"))
        XCTAssertEqual(result.outcome, .finished(text: "收尾"))

        let childIDs = audit.sessionIDs.filter { $0.contains("#sub-a") }
        XCTAssertEqual(childIDs.count, 2, "两批各一跳：\(childIDs)")
        XCTAssertEqual(Set(childIDs).count, 2,
                       "两批用了同一个子会话号 ⇒ 第二批接着第一批的上下文：\(childIDs)")

        let secondID = try XCTUnwrap(childIDs.last)
        let secondFile = try String(contentsOf: store.fileURL(sessionID: secondID), encoding: .utf8)
        XCTAssertFalse(secondFile.contains("第一轮结论FIRST"),
                       "第二批的子会话文件里带着第一批的历史：\(secondFile.prefix(300))")

        XCTAssertTrue(client.promptsSnapshot.contains { $0.contains("作废") },
                      "重派的提示词里没声明上一轮作废：\(client.promptsSnapshot.filter { $0.contains("做 a") })")
    }

    // MARK: - ②-循环层：截止时刻真的落在子循环上

    /// **子循环自己**在截止时刻收尾（不只是执行器那一层的兜底）。
    ///
    /// 让子代理一直要工具（每跳都返回一次 `list_dir`）—— 只能靠 deadline 停：
    /// 去掉 `childLoop.deadline` 它就会一路跳到 `maxSteps`（150），结局是 `.failed` 而不是 `.partial`。
    func testChildLoopStopsAtItsDeadlineWithPartial() async {
        let client = ScriptedClient()
        client.script("翻目录", [[
            .toolCallDelta(index: 0, id: "t1", name: "list_dir", argumentsFragment: #"{"path":"."}"#),
            .finished(reason: "tool_calls"),
        ]])
        var loop = AgentLoop(client: client, dispatcher: NoopDispatcher())
        loop.subagentPolicy = AgentSubagentPolicy(maxConcurrent: 1, defaultBudgetSeconds: 1)
        let runner = AgentLoopSubtaskRunner(loop: loop, template: context(prompt: "主任务"))
        let spec = AgentSubtaskSpec(id: "loop", label: "Loop", prompt: "翻目录", budgetSeconds: 1)
        // 每一跳 0.15 秒 ⇒ 1 秒预算内只跑几跳，**不会先撞上 150 跳的步数上限**。
        client.delay("翻目录", 0.15)

        let started = Date()
        let result = await runner.run(spec, budgetSeconds: 1)
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertLessThanOrEqual(elapsed, 4, "1 秒预算的子循环不许跑到步数上限才停（实测 \(elapsed)s）")
        XCTAssertEqual(result.status, .partial, "到点收尾要交 partial：\(result)")
        XCTAssertGreaterThan(runner.events.hopCount(subtaskID: "loop"), 0, "它该真跑过几跳")
        let labels = runner.events.snapshot().delegations.first { $0.id == "loop" }?
            .steps.records.map(\.label) ?? []
        XCTAssertEqual(labels.last, "deadline", "停的那一档要如实记成 deadline：\(labels)")
    }

    // MARK: - ①-状态层：主对话的观测口

    /// 界面那一层（`AgentChatModel`）也按来源挡：子路事件不写正文、不进步数清单。
    ///
    /// 判红点：把 `observe(_:origin:)` 的来源判断去掉（转发给两参版本）⇒ 下面的三条断言全红。
    @MainActor
    func testChatTranscriptDropsSubtaskOriginEvents() async {
        let model = AgentChatModel(sessionID: "chat-isolation")
        await model.observe(.hopStarted(index: 0), origin: .mainLoop)
        await model.observe(.delta("主结论"), origin: .mainLoop)
        // 子路：跳号顶到 151（真机上就是这一路把计数顶过 150 的）
        await model.observe(.hopStarted(index: 151), origin: .subtask(id: "a", delegatedAtStep: 0))
        await model.observe(.delta("子路token"), origin: .subtask(id: "a", delegatedAtStep: 0))
        await model.observe(.toolStarted(name: "list_dir", summary: "全盘"),
                            origin: .subtask(id: "a", delegatedAtStep: 0))

        XCTAssertEqual(model.state.steps.count, 1, "子路的跳不许进主对话的步数清单")
        XCTAssertLessThanOrEqual(model.state.steps.count, model.state.stepBudget,
                                 "步数计数不得因混流涨过上限")
        let transcript = model.state.messages.map(\.text).joined()
        XCTAssertTrue(transcript.contains("主结论"))
        XCTAssertFalse(transcript.contains("子路token"), "子路正文进了主对话：\(transcript)")
        XCTAssertEqual(model.droppedSubtaskEvents, 3, "三条子路事件应当全部被挡在主对话外")
    }

    // MARK: - ①-账本层：子路事件有地方去

    /// 子路事件**只进它自己那一本账**（`AgentSubtaskLedger`），正文在账里查得到。
    func testSubtaskEventsLandInTheirOwnLedger() async {
        let store = AgentSubtaskEventStore()
        store.delegate(id: "a", goal: "做 a", atStep: 3)
        let observer = AgentSubtaskEventObserver(subtaskID: "a", store: store)

        await observer.observe(.hopStarted(index: 0))
        await observer.observe(.delta("子路正文"))
        await observer.observe(.toolStarted(name: "list_dir", summary: "ws"))
        await observer.observe(.stopped(.deadline))

        let ledger = store.snapshot()
        let delegation = ledger.delegations.first { $0.id == "a" }
        XCTAssertEqual(delegation?.origin, .subtask(id: "a", delegatedAtStep: 3))
        XCTAssertEqual(delegation?.steps.records.count, 3, "跳 / 工具 / 停各一条，正文不占步")
        XCTAssertEqual(store.hopCount(subtaskID: "a"), 1)
        XCTAssertEqual(store.partialText(subtaskID: "a"), "子路正文")
        XCTAssertNil(store.partialText(subtaskID: "没派过的"))
    }
}
