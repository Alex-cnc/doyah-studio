import XCTest
@testable import DoyahCore

/// `FR-AGT-CORE-LOOP-009`（契约 §7 单次任务预算）的机械判据。
///
/// 三条点名判据：
///   ① 默认 **150 步 / 256K token（262,144）** —— 上限值本身就是契约条款，改了就是改契约；
///   ② 触顶后必须能说清「**停在哪、做完哪些**」（跳数 / 已完成工具 / 被拒工具 / 令牌）；
///   ③ **不许把预算用完报成任务完成** —— 不是预算停的（完成 / 取消 / 配额）不产出预算报告。
///
/// 令牌口径另外钉一条：报出来的合计 = 进来之前已花 + 这一轮花了（与上限同一量纲）。
/// 千分位是给人看的，`plainLine` 给判据 / 日志搜。

final class AgentBudgetReportTests: XCTestCase {

    // MARK: - ① 默认上限就是契约值

    func testDefaultLimitsAreContractValues() {
        let limits = AgentLoopLimits()
        XCTAssertEqual(limits.maxSteps, 150, "契约 §7：一次任务最多 150 步")
        XCTAssertEqual(limits.maxTotalTokens, 262_144, "契约 §7：256K token = 262,144")
        XCTAssertEqual(limits.tokensAlreadySpent, 0)
    }

    /// 负例方向：老口径（20 万）不许回来 —— 20 万 ≠ 256K，差 62,144。
    func testOldTwoHundredThousandDefaultIsGone() {
        XCTAssertNotEqual(AgentLoopLimits().maxTotalTokens, 200_000,
                          "20 万是 2026-10-24 之前的旧口径，改回来就等于改契约")
    }

    // MARK: - ② 「停在哪、做完哪些」的读数形状

    private func makeResult(outcome: AgentLoopOutcome, steps: Int,
                            executed: Int, rejected: Int, tokens: LLMUsage) -> AgentLoopResult {
        AgentLoopResult(
            outcome: outcome, steps: steps,
            executedTools: (0..<executed).map { index in
                AgentToolInvocation(name: "read_file", argumentsJSON: "{\"path\":\"a.txt\"}", callID: "c-\(index)")
            },
            rejectedTools: (0..<rejected).map { _ in (name: "bad_tool", reason: "未登记") },
            usage: tokens, text: ""
        )
    }

    func testStepLimitReportSaysWhereItStoppedAndWhatItDid() {
        let limits = AgentLoopLimits(maxSteps: 150, maxTotalTokens: 262_144)
        let result = makeResult(outcome: .stopped(.stepLimit(150)), steps: 150,
                                executed: 12, rejected: 2,
                                tokens: LLMUsage(promptTokens: 5_000, completionTokens: 1_000, totalTokens: 6_000))
        guard let report = result.budgetReport(limits: limits) else { return XCTFail("步数触顶要给报告") }
        XCTAssertEqual(report.kind, .steps)
        XCTAssertEqual(report.limit, 150)
        XCTAssertEqual(report.steps, 150)
        XCTAssertEqual(report.executedToolCount, 12)
        XCTAssertEqual(report.rejectedToolCount, 2)
        XCTAssertEqual(report.tokensSpent, limits.tokensAlreadySpent + result.usage.billableTokens)

        let plain = report.plainLine()
        XCTAssertTrue(plain.contains("步数 150/150"), plain)
        XCTAssertTrue(plain.contains("已跑 150 跳"), plain)
        XCTAssertTrue(plain.contains("完成 12 次工具调用"), plain)
        XCTAssertTrue(plain.contains("被拒 2 次"), plain)
        XCTAssertFalse(plain.contains("任务完成"), "触顶不许说成完成（契约 §7 ②）：\(plain)")
    }

    func testTokenLimitReportCountsCarriedOverSpend() {
        // 续跑场景：进来之前已经花掉 250,000，这一轮再花 12,500 ⇒ 合计正好顶到 262,500 ≥ 262,144。
        let limits = AgentLoopLimits(maxSteps: 150, maxTotalTokens: 262_144, tokensAlreadySpent: 250_000)
        let result = makeResult(outcome: .stopped(.tokenLimit(262_144)), steps: 40,
                                executed: 61, rejected: 0,
                                tokens: LLMUsage(promptTokens: 10_000, completionTokens: 2_500, totalTokens: 12_500))
        guard let report = result.budgetReport(limits: limits) else { return XCTFail("令牌触顶要给报告") }
        XCTAssertEqual(report.kind, .tokens)
        XCTAssertEqual(report.tokensSpent, 262_500, "必须含进来之前已花的 250,000")
        XCTAssertEqual(report.tokenLimit, 262_144)
        XCTAssertGreaterThanOrEqual(report.tokensSpent, report.tokenLimit, "触顶读数不该低于上限")

        let plain = report.plainLine()
        XCTAssertTrue(plain.contains("令牌 262500/262144"), plain)
        XCTAssertTrue(plain.contains("停在发送下一跳之前"), "要说明停的位置：\(plain)")
        XCTAssertFalse(plain.contains("任务完成"), plain)
    }

    /// 人话行给千分位，`plainLine` 抹掉 —— 两种形态都要能对上（判据不靠解析中文）。
    func testLineIsGroupedAndPlainLineIsNot() {
        let limits = AgentLoopLimits(maxTotalTokens: 262_144)
        let result = makeResult(outcome: .stopped(.tokenLimit(262_144)), steps: 1,
                                executed: 0, rejected: 0,
                                tokens: LLMUsage(promptTokens: 0, completionTokens: 0, totalTokens: 0))
        let report = result.budgetReport(limits: limits)
        XCTAssertTrue(report?.line().contains("262,144") ?? false, "人话行要有千分位：\(report?.line() ?? "nil")")
        XCTAssertFalse(report?.plainLine().contains(",") ?? true, "plainLine 不许留逗号")
    }

    // MARK: - ③ 非预算停不产出预算报告（不把别的事故套成预算故事）

    func testCompletedRunHasNoBudgetReport() {
        let result = makeResult(outcome: .finished(text: "做完了"), steps: 5, executed: 2, rejected: 0,
                                tokens: LLMUsage(promptTokens: 1, completionTokens: 1, totalTokens: 2))
        XCTAssertNil(result.budgetReport(limits: AgentLoopLimits()), "正常完成不该有「触顶」话术")
    }

    func testCancelledAndQuotaStopsHaveNoBudgetReport() {
        let cancelled = makeResult(outcome: .stopped(.cancelled), steps: 3, executed: 1, rejected: 0,
                                   tokens: LLMUsage(promptTokens: 0, completionTokens: 0, totalTokens: 0))
        XCTAssertNil(cancelled.budgetReport(limits: AgentLoopLimits()))

        // 配额有它自己那句可读原因 —— 不能再套一层「预算触顶」。
        let quota = makeResult(outcome: .stopped(.quotaLimit("requestLimit:3/3")),
                               steps: 3, executed: 3, rejected: 0,
                               tokens: LLMUsage(promptTokens: 0, completionTokens: 0, totalTokens: 0))
        XCTAssertNil(quota.budgetReport(limits: AgentLoopLimits()))
    }
}
