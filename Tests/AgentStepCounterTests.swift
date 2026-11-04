import XCTest
@testable import DoyahCore

/// 对话页「任务清单」表头上那个步数计数器（`N/M`）的判据（`FR-AI-18` ②③ 的界面读数）。
///
/// ## 这一条为什么必须钉住
///
/// 2026-11-04 真机：分母写成了 **`model.steps.count`（本次运行已经产生的步数）** ⇒ 屏幕上是
/// `1/1`、`2/2`、`3/3`…一个**永远等于 100% 的假进度**，人类主人的原话是「step 计数更新的地方不对，
/// 应该是 95/150，而不是一直更新后面这个数字」。
///
/// 判据只认两件事：
/// ① **分母是常量**（一轮之内不随步数变）—— 连跑 5 跳，分母恒为预算；
/// ② **分子只会涨**，且等于「已执行步数」（当前还在跑的那一步不算）。
///
/// 分母的取值只有一个来源：`AgentLoopLimits` 的默认上限（`defaultMaxSteps`，150）—— 与循环真正
/// 执行的那一份是**同一个常量**，不另写一个 150。
final class AgentStepCounterTests: XCTestCase {

    private func runningState(budget: Int? = nil) -> AgentChatState {
        var state = AgentChatState(endpoint: .ready(model: "deepseek-v4-flash", endpoint: "api.deepseek.com"))
        if let budget { state.pinStepBudget(budget) }
        state.beginRun(prompt: "把 README 读一遍，再改掉那处拼写。")
        return state
    }

    /// ① 连跑 5 跳：**分母恒定**，分子 0 → 4（当前在跑的那一步不算「已执行」）。
    func testDenominatorStaysConstantAcrossFiveHops() {
        var state = runningState()
        var texts: [String] = []
        var budgets: Set<Int> = []
        for hop in 0..<5 {
            state.apply(.hopStarted(index: hop))
            texts.append(state.stepCounter.text)
            budgets.insert(state.stepCounter.budget)
        }

        XCTAssertEqual(texts, ["0/150", "1/150", "2/150", "3/150", "4/150"],
                       "计数器的形态应当是 `已执行/预算`，且只有分子在涨（实际：\(texts)）")
        XCTAssertEqual(budgets.count, 1, "连跑 5 跳，分母变了 \(budgets.count) 种 —— 分母在跟着步数长（缺陷复现）")
        print("🧪 连跑 5 跳读数：\(texts)")
    }

    /// ② 文本形态就是 `N/M`（两段整数，中间一个斜杠）—— 界面直接印它。
    func testCounterTextIsTwoIntegersSeparatedByASlash() {
        var state = runningState()
        for hop in 0..<3 { state.apply(.hopStarted(index: hop)) }
        let text = state.stepCounter.text
        let parts = text.split(separator: "/", omittingEmptySubsequences: false)
        XCTAssertEqual(parts.count, 2, "计数器不是 `N/M` 形态：\(text)")
        XCTAssertNotNil(Int(parts[0]), "分子不是整数：\(text)")
        XCTAssertEqual(Int(parts[1]), AgentLoopLimits.defaultMaxSteps,
                       "分母不是循环的默认步数上限（\(AgentLoopLimits.defaultMaxSteps)）：\(text)")
    }

    /// ③ 分母与循环的默认上限是**同一个数**（不各写一个 150 —— 那是最难查的那种假绿）。
    func testBudgetComesFromTheLoopLimitsDefault() {
        XCTAssertEqual(AgentChatState().stepBudget, AgentLoopLimits().maxSteps,
                       "界面的分母与循环的步数上限不是同一个数 —— 迟早会各说各话")
        XCTAssertEqual(AgentLoopLimits().maxSteps, AgentLoopLimits.defaultMaxSteps,
                       "循环的默认上限与它自己的常量不一致")
        print("🧪 分母来源：state=\(AgentChatState().stepBudget) / loop=\(AgentLoopLimits().maxSteps)")
    }

    /// ④ 一轮跑完：最后一步被标成 `done`，分子 = 步数，分母不变。
    func testFinishingTheRunOnlyMovesTheNumerator() {
        var state = runningState()
        for hop in 0..<5 { state.apply(.hopStarted(index: hop)) }
        let running = state.stepCounter
        state.finishRun()
        let finished = state.stepCounter

        XCTAssertEqual(running.budget, finished.budget, "收尾把分母也改了 —— 分母必须一轮之内恒定")
        XCTAssertEqual(finished.executed, 5, "收尾后应当是 5 步全执行（实际 \(finished.executed)）")
        XCTAssertEqual(finished.text, "5/150")
        print("🧪 收尾前后：\(running.text) → \(finished.text)")
    }

    /// ⑤ 宿主钉进来的上限（将来「上限可配」的口）：分母跟着它走，且**仍然不随步数变**。
    func testPinnedBudgetIsTheDenominatorAndStillConstant() {
        var state = runningState(budget: 40)
        var budgets: Set<Int> = []
        for hop in 0..<5 {
            state.apply(.hopStarted(index: hop))
            budgets.insert(state.stepCounter.budget)
        }
        XCTAssertEqual(budgets, [40], "钉进来的上限没成为分母（实际 \(budgets)）")
        XCTAssertEqual(state.stepCounter.text, "4/40")
    }

    /// ⑥ 极端输入：预算 0 / 负数不许印出 `N/0`（分母最小按 1）。
    func testBudgetNeverCollapsesToZero() {
        XCTAssertEqual(AgentStepCounter(executed: 3, budget: 0).text, "3/1")
        XCTAssertEqual(AgentStepCounter(executed: -2, budget: -9).text, "0/1")
    }

    /// ⑦ 新一轮（`beginRun`）**不把分母清零**，也不把它改成上一轮的步数。
    func testNewRunKeepsTheSameDenominator() {
        var state = runningState()
        for hop in 0..<7 { state.apply(.hopStarted(index: hop)) }
        state.finishRun()
        XCTAssertEqual(state.stepCounter.text, "7/150")

        state.beginRun(prompt: "再改一处")
        XCTAssertEqual(state.stepCounter.text, "0/150", "新一轮的分母/分子没有回到 (0, 预算)")
    }
}
