import XCTest
@testable import DoyahCore

/// `NFR-AI-08` ⑤（检查点半的 **App 侧接线**）—— 检查点按「哪一轮提问」分账。
///
/// 本族的**负例**是这一条的要害（`R-63` ③）：同一个会话里换一个提问，
/// **不许**接上一个问题的检查点（否则上一个问题的半截进展会被当成这一次的前情，
/// 已完成的跳还会被当成「不用重放」—— 看起来省了事，实际上跑错了别人的活）。
final class AgentTurnResumeTests: XCTestCase {

    // MARK: - 假模型 / 假分发器（与 `AgentLoopTests` 同一套形状）

    private final class ScriptedStreamingClient: LLMStreamingClient, @unchecked Sendable {
        var hops: [[LLMStreamEvent]]
        private(set) var requests: [LLMRequest] = []

        init(_ hops: [[LLMStreamEvent]]) { self.hops = hops }

        func stream(_ request: LLMRequest) async throws -> AsyncThrowingStream<LLMStreamEvent, Error> {
            requests.append(request)
            let events = hops.isEmpty ? [.textDelta("（脚本用尽）"), .done] : hops.removeFirst()
            return AsyncThrowingStream { continuation in
                for event in events { continuation.yield(event) }
                continuation.finish()
            }
        }
    }

    private final class RecordingDispatcher: AgentToolDispatcher, @unchecked Sendable {
        private(set) var invoked: [AgentToolInvocation] = []
        var outcome: AgentToolOutcome = .file(AgentToolFileOutput(path: "a.txt", text: "内容",
                                                                  truncated: false, totalBytes: 6))

        func dispatch(_ invocation: AgentToolInvocation, approvals: Set<String>) -> AgentToolOutcome {
            invoked.append(invocation)
            return outcome
        }
    }

    /// 事件记录（续跑那一行读数的来源必须是**循环报出来的**，不是界面猜的）。
    private final class EventRecorder: AgentLoopObserver, @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [AgentLoopEvent] = []

        func observe(_ event: AgentLoopEvent) async {
            lock.lock(); storage.append(event); lock.unlock()
        }

        var events: [AgentLoopEvent] {
            lock.lock(); defer { lock.unlock() }; return storage
        }

        var resumed: [(fromStep: Int, skippedSteps: Int, skippedLines: Int)] {
            events.compactMap { event in
                guard case .resumed(let from, let skipped, let lines) = event else { return nil }
                return (from, skipped, lines)
            }
        }
    }

    private var directory: URL!
    private var store: AgentSessionStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-turn-resume-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = AgentSessionStore(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - 夹具

    private func context(scope: String?) -> AgentLoopContext {
        AgentLoopContext(systemPrompt: "你是助手。", userPrompt: "读一下 a.txt",
                         baseRequest: LLMRequest(endpoint: URL(string: "http://127.0.0.1:11434/v1")!,
                                                 model: "fake", systemPrompt: "", userPrompt: ""),
                         sessionID: "s-session", workspace: "ws-1",
                         checkpointScopeID: scope)
    }

    private func toolEvent(name: String = "read_file", arguments: String = #"{"path":"a.txt"}"#) -> [LLMStreamEvent] {
        [.toolCallDelta(index: 0, id: "call-0", name: name, argumentsFragment: arguments),
         .finished(reason: "tool_calls"),
         .done]
    }

    private var answerEvent: [LLMStreamEvent] {
        [.textDelta("完成"), .finished(reason: "stop"), .done]
    }

    // MARK: - ① 规划：新提问 = 新的一轮 = 新分账号（看不见上一轮的检查点）

    func testNewQuestionGetsAFreshScopeThatCannotSeeThePreviousQuestion() {
        let first = AgentTurnPlanner.plan(sessionID: "s-1", previous: nil, intent: .newQuestion)
        XCTAssertEqual(first.turn, 1, "第一个提问是第 1 轮")
        XCTAssertEqual(first.checkpointScopeID, "s-1#turn-1")
        XCTAssertFalse(first.resumes)
        XCTAssertEqual(first.requestedStep, 0, "新一轮从第 0 跳跑")
        XCTAssertEqual(first.note, "freshTurn:1")

        let second = AgentTurnPlanner.plan(sessionID: "s-1",
                                           previous: AgentTurnRecord(turn: 1, lastStep: 4, unfinished: true),
                                           intent: .newQuestion)
        XCTAssertEqual(second.turn, 2)
        XCTAssertEqual(second.checkpointScopeID, "s-1#turn-2")
        XCTAssertNotEqual(second.checkpointScopeID, first.checkpointScopeID,
                          "**负例**：新提问的分账号必须与上一轮不同（否则会接上上一问的检查点）")
        XCTAssertFalse(second.resumes)
    }

    // MARK: - ② 规划：只有「继续上次」才沿用上一轮的分账号，并报出停在第几跳

    func testContinueUsesTheSameScopeAsTheUnfinishedTurn() {
        let previous = AgentTurnRecord(turn: 3, lastStep: 5, unfinished: true)
        let plan = AgentTurnPlanner.plan(sessionID: "s-1", previous: previous, intent: .continueLast)

        XCTAssertTrue(plan.resumes)
        XCTAssertEqual(plan.turn, 3, "续跑还是第 3 轮（不另起一轮）")
        XCTAssertEqual(plan.checkpointScopeID, AgentTurnPlanner.scopeID(sessionID: "s-1", turn: 3))
        XCTAssertEqual(plan.requestedStep, 5, "「以为自己停在第 5 跳」要如实交上去（回退跳数靠它算）")
        XCTAssertEqual(plan.note, "resume:t3:step5")
    }

    // MARK: - ③ 规划：上一轮已经走完 ⇒ **不冒充**能续（如实说，并落到新的一轮）

    func testContinueAfterFinishedTurnDoesNotPretendToResume() {
        let plan = AgentTurnPlanner.plan(sessionID: "s-1",
                                         previous: AgentTurnRecord(turn: 2, lastStep: 3, unfinished: false),
                                         intent: .continueLast)
        XCTAssertFalse(plan.resumes, "走完的轮次没有可续的东西 —— 不许假装续上")
        XCTAssertEqual(plan.turn, 3, "退化成新的一轮")
        XCTAssertEqual(plan.checkpointScopeID, "s-1#turn-3")
        XCTAssertEqual(plan.requestedStep, 0)
        XCTAssertEqual(plan.note, "previousFinished", "机器码要能让人看出「为什么没续」")
    }

    // MARK: - ④ 规划：压根没跑过 / 一跳都没跑完 ⇒ 也给机器码

    func testContinueWithNothingToResumeSaysSo() {
        let none = AgentTurnPlanner.plan(sessionID: "s-1", previous: nil, intent: .continueLast)
        XCTAssertFalse(none.resumes)
        XCTAssertEqual(none.note, "nothingToResume")
        XCTAssertEqual(none.turn, 1)

        // 上一轮被取消在第一跳之前（`lastStep == 0`）：同样没得续（没有任何「已完成」可跳过）。
        let zero = AgentTurnPlanner.plan(sessionID: "s-1",
                                         previous: AgentTurnRecord(turn: 1, lastStep: 0, unfinished: true),
                                         intent: .continueLast)
        XCTAssertFalse(zero.resumes)
        XCTAssertEqual(zero.note, "nothingToResume")
    }

    // MARK: - ⑤ 记账：只有 `.finished` 算走完（限额 / 取消 / 失败都能接着跑）

    func testOnlyFinishedOutcomeCountsAsComplete() {
        let finished = AgentTurnPlanner.record(
            turn: 1,
            result: AgentLoopResult(outcome: .finished(text: "好"), steps: 3,
                                    executedTools: [], rejectedTools: [], usage: .unknown, text: "好"))
        XCTAssertFalse(finished.unfinished)
        XCTAssertEqual(finished.lastStep, 3, "停在几跳要记下来（下一轮续跑靠它）")

        for outcome in [AgentLoopOutcome.stopped(.stepLimit(8)), .stopped(.cancelled), .failed("断流")] {
            let record = AgentTurnPlanner.record(
                turn: 1,
                result: AgentLoopResult(outcome: outcome, steps: 2,
                                        executedTools: [], rejectedTools: [], usage: .unknown, text: ""))
            XCTAssertTrue(record.unfinished, "\(outcome) 是没走完 —— 值得续")
        }
    }

    // MARK: - ⑥ **负例**（本轮的要害）：同一个会话换一个提问，不许接上一个问题的检查点

    func testNewQuestionDoesNotResumeThePreviousQuestionsCheckpoint() async {
        let checkpoints = AgentCheckpointStore(directory: directory)
        let turnOne = AgentTurnPlanner.plan(sessionID: "s-session", previous: nil, intent: .newQuestion)

        let first = ScriptedStreamingClient([toolEvent(), answerEvent])
        let loop1 = AgentLoop(client: first, dispatcher: RecordingDispatcher(), sessionStore: store,
                              checkpointStore: checkpoints, checkpointEvery: 1)
        let firstResult = await loop1.run(context: context(scope: turnOne.checkpointScopeID),
                                          requestedStep: turnOne.requestedStep)
        XCTAssertEqual(firstResult.steps, 2)
        XCTAssertNil(firstResult.resumedFromStep, "第一次跑不是续跑")
        XCTAssertNotNil(checkpoints.recover(sessionID: turnOne.checkpointScopeID, requestedStep: 2).checkpoint,
                        "第 1 轮确实落了检查点（否则下面那条负例没意义）")

        // **第 2 个提问**（上一轮其实已走完，但这里要证明的是「换提问就不接」）：
        let turnTwo = AgentTurnPlanner.plan(sessionID: "s-session",
                                            previous: AgentTurnPlanner.record(turn: 1, result: firstResult),
                                            intent: .newQuestion)
        let second = ScriptedStreamingClient([toolEvent(), answerEvent])
        let loop2 = AgentLoop(client: second, dispatcher: RecordingDispatcher(), sessionStore: store,
                              checkpointStore: checkpoints, checkpointEvery: 1)
        let secondResult = await loop2.run(context: context(scope: turnTwo.checkpointScopeID),
                                           requestedStep: turnTwo.requestedStep)

        XCTAssertNil(secondResult.resumedFromStep, "**新提问不许接上一个问题的检查点**（`R-63` ③ 同族负例）")
        XCTAssertEqual(secondResult.skippedSteps, 0, "从第 0 跳跑 ⇒ 没有「退了几跳」这回事")
        XCTAssertEqual(secondResult.steps, 2, "这一轮照自己的脚本跑满两跳")
        XCTAssertEqual(second.requests.count, 2, "两条请求都得真发（没有拿上一轮的进展顶替）")
    }

    // MARK: - ⑦ 显式「继续上次」：沿用上一条的分账号 ⇒ 已完成的跳**一个请求都不重发**

    func testContinueResumesFromTheTurnCheckpointWithoutReplayingHops() async {
        let checkpoints = AgentCheckpointStore(directory: directory)
        let plan = AgentTurnPlanner.plan(sessionID: "s-session", previous: nil, intent: .newQuestion)

        let first = ScriptedStreamingClient([toolEvent(), answerEvent])
        let loop1 = AgentLoop(client: first, dispatcher: RecordingDispatcher(), sessionStore: store,
                              checkpointStore: checkpoints, checkpointEvery: 1)
        let firstResult = await loop1.run(context: context(scope: plan.checkpointScopeID),
                                          requestedStep: 0)
        XCTAssertEqual(firstResult.steps, 2)

        // 重新算落账：上一轮「没走完」（这里用限额停模拟），于是「继续上次」能接上。
        let interrupted = AgentLoopResult(outcome: .stopped(.stepLimit(1)), steps: 2,
                                          executedTools: [], rejectedTools: [], usage: .unknown, text: "")
        let resumePlan = AgentTurnPlanner.plan(
            sessionID: "s-session",
            previous: AgentTurnPlanner.record(turn: plan.turn, result: interrupted),
            intent: .continueLast)
        XCTAssertTrue(resumePlan.resumes)

        let second = ScriptedStreamingClient([answerEvent])
        let loop2 = AgentLoop(client: second, dispatcher: RecordingDispatcher(), sessionStore: store,
                              checkpointStore: checkpoints, checkpointEvery: 1)
        let resumed = await loop2.run(context: context(scope: resumePlan.checkpointScopeID),
                                      requestedStep: resumePlan.requestedStep)

        XCTAssertEqual(resumed.resumedFromStep, 1, "从第 1 跳（0 起）接上")
        XCTAssertEqual(second.requests.count, 1, "已完成的跳不重放：只发接上之后那一条")
        XCTAssertEqual(resumed.steps, 3, "接着第 2 跳跑 ⇒ 跳数从 3 起")
        XCTAssertEqual(resumed.skippedSteps, 1, "以为自己停在 2、可用点是 1 ⇒ 实退 1 跳，如实报数")
    }

    // MARK: - ⑧ 键的口径：检查点落在**分账号**上（会话号那一格查不到东西）

    func testCheckpointsAreKeyedByTheTurnScopeNotTheSession() async {
        let checkpoints = AgentCheckpointStore(directory: directory)
        let plan = AgentTurnPlanner.plan(sessionID: "s-session", previous: nil, intent: .newQuestion)
        let client = ScriptedStreamingClient([toolEvent(), answerEvent])
        let loop = AgentLoop(client: client, dispatcher: RecordingDispatcher(), sessionStore: store,
                             checkpointStore: checkpoints, checkpointEvery: 1)
        _ = await loop.run(context: context(scope: plan.checkpointScopeID), requestedStep: 0)

        XCTAssertNotNil(checkpoints.recover(sessionID: plan.checkpointScopeID, requestedStep: 1).checkpoint)
        XCTAssertNil(checkpoints.recover(sessionID: "s-session", requestedStep: 1).checkpoint,
                     "会话号那一格不许有记录 —— 否则下一个提问按会话号回查就接上了")
    }

    // MARK: - ⑨ 事件：续跑的三个数**由循环报出来**（界面那行读数吃它，不许界面自己猜）

    func testResumedEventCarriesTheThreeNumbers() async {
        let checkpoints = AgentCheckpointStore(directory: directory)
        let plan = AgentTurnPlanner.plan(sessionID: "s-session", previous: nil, intent: .newQuestion)
        let first = ScriptedStreamingClient([toolEvent(), answerEvent])
        let loop1 = AgentLoop(client: first, dispatcher: RecordingDispatcher(), sessionStore: store,
                              checkpointStore: checkpoints, checkpointEvery: 1)
        _ = await loop1.run(context: context(scope: plan.checkpointScopeID), requestedStep: 0)

        let recorder = EventRecorder()
        let second = ScriptedStreamingClient([answerEvent])
        let loop2 = AgentLoop(client: second, dispatcher: RecordingDispatcher(), sessionStore: store,
                              observer: recorder, checkpointStore: checkpoints, checkpointEvery: 1)
        _ = await loop2.run(context: context(scope: plan.checkpointScopeID), requestedStep: 2)

        let resumed = recorder.resumed
        XCTAssertEqual(resumed.count, 1, "续跑要报**一次**（不重复报）")
        XCTAssertEqual(resumed.first?.fromStep, 1)
        XCTAssertEqual(resumed.first?.skippedSteps, 1)
        XCTAssertEqual(resumed.first?.skippedLines, 0)
    }

    // MARK: - ⑩ 不接线 / 不给分账号 ⇒ 旧行为逐字不变（按会话号，判据与老单测同口径）

    func testScopeDefaultsToTheSessionWhenNotProvided() async {
        let checkpoints = AgentCheckpointStore(directory: directory)
        let client = ScriptedStreamingClient([toolEvent(), answerEvent])
        let loop = AgentLoop(client: client, dispatcher: RecordingDispatcher(), sessionStore: store,
                             checkpointStore: checkpoints, checkpointEvery: 1)
        let result = await loop.run(context: context(scope: nil), requestedStep: 0)
        XCTAssertEqual(result.steps, 2)
        XCTAssertNotNil(checkpoints.recover(sessionID: "s-session", requestedStep: 1).checkpoint,
                        "没给分账号 ⇒ 按会话号落（旧行为）")
        XCTAssertEqual(context(scope: nil).checkpointKey, "s-session")
    }

    // MARK: - ⑪ 界面壳：读数只在**这一轮真续上**时出现（开跑就清，不许上一轮的读数冒充）

    func testChatStateShowsResumeReadingOnlyForTheRunThatResumed() {
        var state = AgentChatState(endpoint: .ready(model: "m", endpoint: "http://127.0.0.1:11434/v1"))
        state.beginRun(prompt: "读一下 a.txt")
        XCTAssertNil(state.resumeReading, "新开一轮：上一轮的续跑读数要清掉")

        state.apply(.resumed(fromStep: 3, skippedSteps: 1, skippedCheckpointLines: 2))
        XCTAssertEqual(state.resumeReading, AgentChatResumeReading(fromStep: 3, skippedSteps: 1,
                                                                   skippedCheckpointLines: 2))

        state.finishRun()
        // 继续上次：**不追加用户消息**（问的还是同一个问题），读数照样重清一次。
        let userMessagesBefore = state.messages.filter { $0.role == .user }.count
        state.beginResume()
        XCTAssertNil(state.resumeReading)
        XCTAssertEqual(state.messages.filter { $0.role == .user }.count, userMessagesBefore,
                       "续跑不许再塞一条用户消息（会让人以为问了第二遍）")
        XCTAssertTrue(state.isRunning)
    }
}
