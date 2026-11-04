import XCTest
@testable import DoyahCore

/// `FR-AGT-TOOL-SYS-002`（子任务委派）+ `FR-AGT-OPS-OBS-002`（并发上限执行面）的判据。
///
/// 三条验收要点各自落成机器可判：
/// ① 独立上下文与独立留痕 —— 子会话号可判且父子分得开；
/// ② 汇总标来源 —— 每条结果带 `标签#子任务ID`；
/// ③ 失败不影响其余 —— 一路失败 / 超时，其它照常完成。
final class AgentSubagentExecutionTests: XCTestCase {

    /// 假子代理：按 id 给结局、记录并发峰值与真实并发序。
    private final class FakeRunner: AgentSubtaskRunner, @unchecked Sendable {
        private let lock = NSLock()
        private(set) var inFlight = 0
        private(set) var peak = 0
        private(set) var started: [String] = []
        private(set) var budgets: [String: TimeInterval] = [:]

        var plan: [String: (delay: TimeInterval, status: AgentSubtaskResult.Status)] = [:]

        func run(_ spec: AgentSubtaskSpec, budgetSeconds: TimeInterval) async -> AgentSubtaskResult {
            lock.lock()
            inFlight += 1
            peak = max(peak, inFlight)
            started.append(spec.id)
            budgets[spec.id] = budgetSeconds
            let entry = plan[spec.id] ?? (delay: 0, status: .completed)
            lock.unlock()

            defer {
                lock.lock(); inFlight -= 1; lock.unlock()
            }
            if entry.delay > 0 { try? await Task.sleep(nanoseconds: UInt64(entry.delay * 1_000_000_000)) }
            return AgentSubtaskResult(subtaskID: spec.id, label: spec.label, status: entry.status,
                                      summary: "ok-\(spec.id)", artifacts: [], approvalFingerprint: nil)
        }
    }

    private func spec(_ id: String, budget: TimeInterval = 0) -> AgentSubtaskSpec {
        AgentSubtaskSpec(id: id, label: "L\(id)", prompt: "做 \(id)", budgetSeconds: budget)
    }

    private func executor(_ maxConcurrent: Int, _ runner: FakeRunner) -> AgentSubagentExecutor {
        AgentSubagentExecutor(policy: AgentSubagentPolicy(maxConcurrent: maxConcurrent), runner: runner)
    }

    // ① 空批：不假跑、报告为空
    func testEmptyBatchReportsNothing() async {
        let runner = FakeRunner()
        let report = await executor(3, runner).run([])
        XCTAssertTrue(report.results.isEmpty)
        XCTAssertTrue(runner.started.isEmpty)
    }

    // ② 报告顺序 = 传入顺序（哪怕慢的那一路先派、后回）
    func testReportKeepsInputOrder() async {
        let runner = FakeRunner()
        runner.plan = ["a": (delay: 0.15, status: .completed), "b": (delay: 0, status: .completed),
                       "c": (delay: 0, status: .completed)]
        let report = await executor(3, runner).run([spec("a"), spec("b"), spec("c")])
        XCTAssertEqual(report.results.map(\.subtaskID), ["a", "b", "c"])
    }

    // ③ 并发上限**真的**限制同时跑几路（6 路、上限 2）
    func testConcurrencyIsCapped() async {
        let runner = FakeRunner()
        let specs = (1...6).map { spec("t\($0)") }
        for s in specs { runner.plan[s.id] = (delay: 0.05, status: .completed) }
        _ = await executor(2, runner).run(specs)
        XCTAssertLessThanOrEqual(runner.peak, 2)
        XCTAssertEqual(runner.started.count, 6)
    }

    // ④ 上限来自配置快照：`maxConcurrentSubtasks = 1` ⇒ 真串行（面板 / `/config` 改完立即生效）
    func testLimitComesFromConfigSnapshot() async throws {
        var snapshot = AgentConfigSnapshot()
        snapshot.maxConcurrentSubtasks = 1
        let policy = AgentSubagentPolicy(snapshot: snapshot)
        XCTAssertEqual(policy.maxConcurrent, 1)

        let runner = FakeRunner()
        let specs = (1...3).map { spec("s\($0)") }
        for s in specs { runner.plan[s.id] = (delay: 0.03, status: .completed) }
        _ = await AgentSubagentExecutor(policy: policy, runner: runner).run(specs)
        XCTAssertEqual(runner.peak, 1)
    }

    // ⑤ 一路失败不牵连其余（契约验收 ③）
    func testOneFailureDoesNotBreakTheRest() async {
        let runner = FakeRunner()
        runner.plan = ["x": (delay: 0, status: .failed), "y": (delay: 0, status: .completed),
                       "z": (delay: 0, status: .completed)]
        let report = await executor(3, runner).run([spec("x"), spec("y"), spec("z")])
        XCTAssertEqual(report.completedCount, 2)
        XCTAssertEqual(report.failures.map(\.subtaskID), ["x"])
    }

    // ⑥ 超时：这一路记 `.timedOut`，别路照常完成
    func testTimeoutIsIsolated() async {
        let runner = FakeRunner()
        runner.plan = ["slow": (delay: 5, status: .completed), "fast": (delay: 0, status: .completed)]
        let report = await executor(3, runner).run([spec("slow", budget: 0.1), spec("fast")])
        XCTAssertEqual(report.results.first { $0.subtaskID == "slow" }?.status, .timedOut)
        XCTAssertEqual(report.results.first { $0.subtaskID == "fast" }?.status, .completed)
    }

    // ⑦ 预算：子任务没写就用默认；写了就用它自己的
    func testBudgetFallsBackToPolicyDefault() async {
        let runner = FakeRunner()
        let executor = AgentSubagentExecutor(
            policy: AgentSubagentPolicy(maxConcurrent: 2, defaultBudgetSeconds: 42), runner: runner)
        _ = await executor.run([spec("d"), spec("e", budget: 7)])
        XCTAssertEqual(runner.budgets["d"], 42)
        XCTAssertEqual(runner.budgets["e"], 7)
    }

    // ⑧ 同批重复 id：后一条记 `.skipped`，只有第一条真跑（来源标注不许混）
    func testDuplicateIDsAreSkipped() async {
        let runner = FakeRunner()
        let report = await executor(3, runner).run([spec("dup"), spec("dup"), spec("other")])
        XCTAssertEqual(report.results.filter { $0.subtaskID == "dup" }.map(\.status), [.completed, .skipped])
        XCTAssertEqual(runner.started.filter { $0 == "dup" }.count, 1)
    }

    // ⑨ 汇总带来源，且失败 / 待批单独点出（验收 ②）
    func testMergedSummaryCarriesSource() async {
        let runner = FakeRunner()
        runner.plan = ["a": (delay: 0, status: .completed), "b": (delay: 0, status: .failed)]
        let report = await executor(2, runner).run([spec("a"), spec("b")])
        XCTAssertTrue(report.mergedSummary.contains("La#a"))
        XCTAssertTrue(report.mergedSummary.contains("Lb#b"))
    }

    // ⑩ 子会话号：父子分得开、非法字符被净化（独立留痕的落点）
    func testChildSessionIDIsDistinctAndSanitized() {
        let child = AgentSubagentExecutor.childSessionID(parent: "sess-1", subtaskID: "a/b#c")
        XCTAssertEqual(child, "sess-1#sub-a-b-c")
        XCTAssertNotEqual(child, AgentSubagentExecutor.childSessionID(parent: "sess-1", subtaskID: "a"))
    }

    // ⑪ 策略夹取：配置越界不放大并发（1…16）
    func testPolicyClampsConcurrency() {
        XCTAssertEqual(AgentSubagentPolicy(maxConcurrent: 0).maxConcurrent, 1)
        XCTAssertEqual(AgentSubagentPolicy(maxConcurrent: 99).maxConcurrent, 16)
        XCTAssertEqual(AgentSubagentPolicy(maxConcurrent: 4).limits.maxConcurrent, 4)
    }

    // ⑫ 循环结局 → 子任务结局（四种停法逐档，摘要封顶 400 字）
    func testLoopOutcomeMapping() {
        func result(_ outcome: AgentLoopOutcome) -> AgentLoopResult {
            AgentLoopResult(outcome: outcome, steps: 0, executedTools: [], rejectedTools: [],
                            usage: .unknown, text: "")
        }
        let target = spec("k1")
        XCTAssertEqual(AgentLoopSubtaskRunner.map(result(.finished(text: "第一段\n\n第二段")),
                                                  spec: target, budgetSeconds: 1).summary, "第一段")
        XCTAssertEqual(AgentLoopSubtaskRunner.map(result(.failed("boom")),
                                                  spec: target, budgetSeconds: 1).status, .failed)
        XCTAssertEqual(AgentLoopSubtaskRunner.map(result(.stopped(.cancelled)),
                                                  spec: target, budgetSeconds: 1).status, .skipped)
        XCTAssertEqual(AgentLoopSubtaskRunner.map(result(.stopped(.stepLimit(3))),
                                                  spec: target, budgetSeconds: 1).status, .failed)
        let long = String(repeating: "字", count: 500)
        XCTAssertLessThanOrEqual(AgentLoopSubtaskRunner.summarized(long).count, 401)
    }

    // ⑬ **端到端**：主控派两路 → 真 `AgentLoop` 各跑一次 → 报告按来源汇总
    //    （假模型，不连网；两路各发一次请求 ⇒ 子代理确实是真跑循环，不是摆样子）
    func testEndToEndThroughRealLoop() async {
        let client = ScriptedStreamingClient(["做 a": "结论A", "做 b": "结论B"])
        let template = AgentLoopContext(
            systemPrompt: "系统", userPrompt: "主任务",
            baseRequest: LLMRequest(endpoint: URL(string: "http://127.0.0.1:1/v1")!,
                                    model: "fake", systemPrompt: "", userPrompt: ""),
            sessionID: "parent-sess", workspace: "ws")
        let loop = AgentLoop(client: client, dispatcher: NoopDispatcher())
        let executor = AgentSubagentExecutor(
            policy: AgentSubagentPolicy(maxConcurrent: 2),
            runner: AgentLoopSubtaskRunner(loop: loop, template: template))

        let report = await executor.run([spec("a"), spec("b")])
        XCTAssertEqual(report.results.map(\.status), [.completed, .completed])
        XCTAssertEqual(report.results.map(\.summary), ["结论A", "结论B"])
        XCTAssertTrue(report.mergedSummary.contains("La#a"))
        XCTAssertTrue(report.mergedSummary.contains("Lb#b"))
        XCTAssertEqual(client.requests.sorted().count, 2, "两路各发一次请求")
        XCTAssertTrue(client.requests.contains { $0.contains("做 a") })
        XCTAssertTrue(client.requests.contains { $0.contains("做 b") })
        // 子代理的提示词里必须写明预算（否则它会一路翻到被掐 —— 真机 4 批全 timedOut 的那条）
        XCTAssertTrue(client.requests.allSatisfy { $0.contains("你只有 300 秒") },
                      "子代理提示词缺预算：\(client.requests)")
    }
}

/// 按**提示词**回话的假模型（并行下不能靠队列顺序 —— 两路谁先发不确定）。
private final class ScriptedStreamingClient: LLMStreamingClient, @unchecked Sendable {
    private let replies: [String: String]
    private let lock = NSLock()
    private var seen: [String] = []

    init(_ replies: [String: String]) { self.replies = replies }

    func stream(_ request: LLMRequest) async throws -> AsyncThrowingStream<LLMStreamEvent, Error> {
        lock.lock()
        seen.append(request.userPrompt)
        // 按**包含**匹配：子代理的提示词前面带一行预算 / 批次头（`你只有 N 秒…`），
        // 不再是 `spec.prompt` 的逐字副本 ⇒ 精确字典查不到（2026-11-04 修预算那条时改的）。
        let key = replies.keys.first { request.userPrompt.contains($0) } ?? request.userPrompt
        let text = replies[key] ?? "（脚本用尽）"
        lock.unlock()
        return AsyncThrowingStream { continuation in
            continuation.yield(.textDelta(text))
            continuation.yield(.done)
            continuation.finish()
        }
    }

    var requests: [String] { lock.lock(); defer { lock.unlock() }; return seen }
}

private final class NoopDispatcher: AgentToolDispatcher, @unchecked Sendable {
    func dispatch(_ invocation: AgentToolInvocation, approvals: Set<String>) -> AgentToolOutcome {
        .file(AgentToolFileOutput(path: "none", text: "", truncated: false, totalBytes: 0))
    }
}
