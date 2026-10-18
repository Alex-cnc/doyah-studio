import XCTest
@testable import DoyahCore

/// `FR-AI-31` ③（长跑监控 / Monitoring）的机械判据。
///
/// 要害是**负例**：跑飞了还一声不吭（卡住不动 / 原地空转 / 反复重试 / 配额烧到上限）。
/// 所以每一档都站一对：不到阈值**不报**（不冤枉）+ 越过阈值**报一次**（不静默）+ 再触发**不重复报**（不刷屏）。
final class AgentRunMonitorTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - ① 卡住（stalled）

    func testStallIsSilentBeforeThreshold() {
        var monitor = AgentRunMonitor(limits: AgentRunMonitorLimits(stallSeconds: 30), startedAt: t0)
        XCTAssertNil(monitor.checkStalled(now: t0.addingTimeInterval(29)), "差一秒都不许报")
        XCTAssertTrue(monitor.alerts.isEmpty)
    }

    func testStallReportedOnceAtThreshold() {
        var monitor = AgentRunMonitor(limits: AgentRunMonitorLimits(stallSeconds: 30), startedAt: t0)
        let alert = monitor.checkStalled(now: t0.addingTimeInterval(31))
        XCTAssertEqual(alert?.kind, .stalled)
        XCTAssertEqual(alert?.observed, 31, "报的是**实测秒数**，不是阈值本身")
        XCTAssertEqual(alert?.threshold, 30)
        XCTAssertEqual(alert?.code, "stalled:31/30")
        XCTAssertNil(monitor.checkStalled(now: t0.addingTimeInterval(600)), "同类只报一次（不刷屏）")
        XCTAssertEqual(monitor.alerts.count, 1)
    }

    func testProgressResetsTheStallClock() {
        var monitor = AgentRunMonitor(limits: AgentRunMonitorLimits(stallSeconds: 30), startedAt: t0)
        monitor.noteProgress(at: t0.addingTimeInterval(25))
        XCTAssertNil(monitor.checkStalled(now: t0.addingTimeInterval(40)), "有进展就不算卡住")
        XCTAssertNotNil(monitor.checkStalled(now: t0.addingTimeInterval(56)))
    }

    // MARK: - ② 空转（spinning）

    func testSpinningNeedsTheFullWindowAndReportsOnce() {
        var monitor = AgentRunMonitor(limits: AgentRunMonitorLimits(maxIdenticalHops: 3), startedAt: t0)
        XCTAssertNil(monitor.recordHop(signature: "tools:read_file#1"), "第 1 跳不报")
        XCTAssertNil(monitor.recordHop(signature: "tools:read_file#1"), "第 2 跳不报")
        let alert = monitor.recordHop(signature: "tools:read_file#1")
        XCTAssertEqual(alert?.kind, .spinning)
        XCTAssertEqual(alert?.observed, 3)
        XCTAssertNil(monitor.recordHop(signature: "tools:read_file#1"), "第 4 跳不再报")
        XCTAssertEqual(monitor.alerts.count, 1)
    }

    func testDifferentShapesAreNotSpinning() {
        var monitor = AgentRunMonitor(limits: AgentRunMonitorLimits(maxIdenticalHops: 3), startedAt: t0)
        XCTAssertNil(monitor.recordHop(signature: "tools:read_file#1"))
        XCTAssertNil(monitor.recordHop(signature: "tools:read_file#2"))
        XCTAssertNil(monitor.recordHop(signature: "tools:read_file#1"), "形态一变就不算原地打转")
    }

    /// 形态指纹：同样的工具 + 同样的参数 ⇒ 同一串；参数一变就不同（否则空转判据会误伤）。
    func testHopSignatureFollowsToolsAndArguments() {
        let a = AgentToolInvocation(name: "read_file", argumentsJSON: #"{"path":"a.txt"}"#)
        let b = AgentToolInvocation(name: "read_file", argumentsJSON: #"{"path":"b.txt"}"#)
        XCTAssertEqual(AgentLoop.hopSignature(invocations: [a], text: "x"),
                       AgentLoop.hopSignature(invocations: [a], text: "完全不同的答复"))
        XCTAssertNotEqual(AgentLoop.hopSignature(invocations: [a], text: ""),
                          AgentLoop.hopSignature(invocations: [b], text: ""))
        XCTAssertTrue(AgentLoop.hopSignature(invocations: [], text: "答完了").hasPrefix("text:"))
    }

    // MARK: - ③ 反复重试（retryStorm）

    func testRetryStormOnlyAfterThreshold() {
        var monitor = AgentRunMonitor(limits: AgentRunMonitorLimits(maxRetries: 2), startedAt: t0)
        XCTAssertNil(monitor.recordRetry())
        XCTAssertNil(monitor.recordRetry())
        let alert = monitor.recordRetry()
        XCTAssertEqual(alert?.kind, .retryStorm)
        XCTAssertEqual(alert?.observed, 3)
        XCTAssertEqual(alert?.threshold, 2)
        XCTAssertNil(monitor.recordRetry(), "已经报过就不再报")
    }

    // MARK: - ④ 预算（接 `AgentQuota` + `NFR-AI-04`）

    func testBudgetWarnsAtEightyPercentThenReportsExhaustion() {
        var monitor = AgentRunMonitor(startedAt: t0)
        let quota = AgentQuota(maxTotalTokens: 100)
        XCTAssertTrue(monitor.checkBudget(quota: quota, ledger: AgentQuotaLedger(totalTokens: 10)).isEmpty,
                      "用得一少就不吵")
        let warning = monitor.checkBudget(quota: quota, ledger: AgentQuotaLedger(totalTokens: 85))
        XCTAssertEqual(warning.map(\.kind), [.budgetApproaching])
        XCTAssertEqual(warning.first?.observed, 85)
        XCTAssertEqual(warning.first?.threshold, 100)
        // 见底：配额自己的判定会拦 ⇒ 报「用尽」（与「将尽」分开：处置不一样）。
        let out = monitor.checkBudget(quota: quota, ledger: AgentQuotaLedger(totalTokens: 100))
        XCTAssertEqual(out.map(\.kind), [.budgetExhausted])
    }

    func testUnlimitedQuotaNeverWarns() {
        var monitor = AgentRunMonitor(startedAt: t0)
        XCTAssertTrue(monitor.checkBudget(quota: AgentQuota(),
                                          ledger: AgentQuotaLedger(requestCount: 999, totalTokens: 999_999)).isEmpty,
                      "没配上限就不该凭空报警")
    }

    func testRequestCountWarnsToo() {
        var monitor = AgentRunMonitor(startedAt: t0)
        let quota = AgentQuota(maxRequestsPerSession: 10)
        let alerts = monitor.checkBudget(quota: quota, ledger: AgentQuotaLedger(requestCount: 9))
        XCTAssertEqual(alerts.map(\.kind), [.budgetApproaching], "次数那一档也要有预警")
    }

    // MARK: - ⑤ 循环接线：配额真的把请求拦在发送之前（负例：照发不误）

    private final class ScriptedClient: LLMStreamingClient, @unchecked Sendable {
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

    private final class EchoDispatcher: AgentToolDispatcher, @unchecked Sendable {
        func dispatch(_ invocation: AgentToolInvocation, approvals: Set<String>) -> AgentToolOutcome {
            .file(AgentToolFileOutput(path: "a.txt", text: "内容", truncated: false, totalBytes: 6))
        }
    }

    private final class Collector: AgentLoopObserver, @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [AgentLoopEvent] = []
        func observe(_ event: AgentLoopEvent) async {
            lock.lock(); storage.append(event); lock.unlock()
        }
        var events: [AgentLoopEvent] { lock.lock(); defer { lock.unlock() }; return storage }
        var monitorAlerts: [(kind: String, observed: Int, threshold: Int)] {
            events.compactMap {
                guard case .monitorAlert(let kind, let observed, let threshold) = $0 else { return nil }
                return (kind, observed, threshold)
            }
        }
    }

    private var context: AgentLoopContext {
        AgentLoopContext(systemPrompt: "你是助手。", userPrompt: "读一下 a.txt",
                         baseRequest: LLMRequest(endpoint: URL(string: "http://127.0.0.1:11434/v1")!,
                                                 model: "fake", systemPrompt: "", userPrompt: ""),
                         sessionID: "s-monitor", workspace: "ws-monitor")
    }

    private func toolHop(_ name: String = "read_file", _ arguments: String = #"{"path":"a.txt"}"#) -> [LLMStreamEvent] {
        [.toolCallDelta(index: 0, id: "call-0", name: name, argumentsFragment: arguments),
         .finished(reason: "tool_calls"), .done]
    }

    func testQuotaStopsBeforeAnyRequestIsSent() async {
        let client = ScriptedClient([toolHop()])
        let loop = AgentLoop(client: client, dispatcher: EchoDispatcher(),
                             quota: AgentQuota(maxRequestsPerSession: 2),
                             quotaLedger: AgentQuotaLedger(requestCount: 2))
        let result = await loop.run(context: context)

        guard case .stopped(.quotaLimit(let detail)) = result.outcome else {
            return XCTFail("应当是配额停：\(result.outcome)")
        }
        XCTAssertTrue(detail.contains("2"), "原因里要有上限值：\(detail)")
        XCTAssertEqual(client.requests.count, 0, "**一次请求都不许发**")
    }

    func testQuotaLedgerAccumulatesPerHopAndComesBack() async {
        let client = ScriptedClient([
            toolHop(),
            [.textDelta("读完了"), .finished(reason: "stop"), .done],
        ])
        let loop = AgentLoop(client: client, dispatcher: EchoDispatcher(),
                             quota: AgentQuota(maxRequestsPerSession: 10),
                             quotaLedger: AgentQuotaLedger(requestCount: 1))
        let result = await loop.run(context: context)

        XCTAssertEqual(result.quotaLedger?.requestCount, 3, "交进来 1 次 + 这一轮 2 跳 ⇒ 3")
        XCTAssertEqual(client.requests.count, 2)
    }

    func testSpinningAlertReachesTheObserver() async {
        let client = ScriptedClient((0..<5).map { _ in toolHop() })
        let collector = Collector()
        let loop = AgentLoop(client: client, dispatcher: EchoDispatcher(), observer: collector,
                             monitor: AgentRunMonitor(limits: AgentRunMonitorLimits(maxIdenticalHops: 3)),
                             limits: AgentLoopLimits(maxSteps: 4))
        _ = await loop.run(context: context)

        let alerts = collector.monitorAlerts
        XCTAssertEqual(alerts.count, 1, "同一形态只报一次：\(alerts)")
        XCTAssertEqual(alerts.first?.kind, "spinning")
        XCTAssertEqual(alerts.first?.observed, 3)
    }

    func testNoAlertsWhenMonitorIsNotWired() async {
        let client = ScriptedClient((0..<4).map { _ in toolHop() })
        let collector = Collector()
        let loop = AgentLoop(client: client, dispatcher: EchoDispatcher(), observer: collector,
                             limits: AgentLoopLimits(maxSteps: 3))
        _ = await loop.run(context: context)

        XCTAssertTrue(collector.monitorAlerts.isEmpty, "没接监控 ⇒ 一条告警都不许凭空出现")
    }

    // MARK: - ⑥ 界面状态：告警落成读数 + 一条可读提示（不静默）

    func testMonitorAlertBecomesReadingAndNotice() {
        var state = AgentChatState(endpoint: .ready(model: "m", endpoint: "http://127.0.0.1"))
        state.beginRun(prompt: "跑一下")
        state.apply(.monitorAlert(kind: "spinning", observed: 3, threshold: 3))

        XCTAssertEqual(state.monitorReading?.kind, "spinning")
        XCTAssertEqual(state.monitorReading?.observed, 3)
        XCTAssertEqual(state.monitorReading?.alerts, 1)
        XCTAssertTrue(state.messages.contains { $0.role == .notice && $0.text == "monitor:spinning" },
                      "读数之外还要一条可读提示（码由界面翻）")
    }

    func testStallWatchdogReportsOnceAndResetsEachRun() {
        var state = AgentChatState(endpoint: .ready(model: "m", endpoint: "http://127.0.0.1"))
        state.beginRun(prompt: "跑一下")
        let limits = AgentRunMonitorLimits(stallSeconds: 30)
        XCTAssertNil(state.checkStall(now: Date().addingTimeInterval(5), limits: limits), "刚开始跑不算卡住")
        let alert = state.checkStall(now: Date().addingTimeInterval(45), limits: limits)
        XCTAssertEqual(alert?.kind, .stalled)
        XCTAssertNil(state.checkStall(now: Date().addingTimeInterval(120), limits: limits), "同一轮不重复报")

        // 新一轮：上一轮的「已报过」不许带过来。
        state.finishRun()
        state.beginRun(prompt: "再跑一次")
        XCTAssertNil(state.monitorReading, "新一轮从零起算（上一轮的读数不许冒充）")
        XCTAssertNotNil(state.checkStall(now: Date().addingTimeInterval(45), limits: limits))
    }

    func testProgressKeepsTheWatchdogQuiet() {
        var state = AgentChatState(endpoint: .ready(model: "m", endpoint: "http://127.0.0.1"))
        state.beginRun(prompt: "跑一下")
        state.apply(.delta("还在出字"))
        XCTAssertNil(state.checkStall(now: Date().addingTimeInterval(5), limits: AgentRunMonitorLimits(stallSeconds: 30)))
        XCTAssertTrue(state.messages.allSatisfy { !$0.text.hasPrefix("monitor:") }, "有进展就不许喊卡住")
    }
}
