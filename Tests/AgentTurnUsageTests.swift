import XCTest
@testable import DoyahCore

/// **一轮三行汇总的读数规约**（详设 §3.33.4 契约六~八）。
///
/// 主人（beta1.0.7 收口）：
///
/// > 一轮结束时，页面上这类「过程信息」**只允许出现三行汇总**，顺序固定、默认全折：
/// > `▸ Thinking  ~308 tokens` / `▾ Tool calls (1)  ~16 tokens` / `Σ ~324 total`
///
/// 这一组钉的是**数**（口径、等式、分轮），端上的「几行 / 行高」在
/// `TestsUISnapshot/AgentTurnThinkingZoneProbeTests`。
final class AgentTurnUsageTests: XCTestCase {

    private func stepText(_ step: Int) -> String {
        "第 \(step) 步：我先读一下 Core/File\(step).swift，确认第 \(step) 段的落点，再决定改哪里。"
    }

    private func round(steps: Int = 5, tools: Int = 1, conclusion: String = "改完了：整轮一个思考区，工具块各自还在。") -> [AgentChatMessage] {
        var messages: [AgentChatMessage] = [.init(role: .user, text: "把思考合并成一轮一个。")]
        for step in 1...steps {
            messages.append(.init(role: .assistant, text: stepText(step)))
            if step <= tools {
                messages.append(.init(role: .tool, text: "▸ read_file · Core/File\(step).swift  ✓ · 0.5s"))
            }
        }
        messages.append(.init(role: .assistant, text: conclusion))
        return messages
    }

    // MARK: - ① Thinking 行 == 合并后那一个区

    func testThinkingTokensComeFromTheMergedZone() {
        let messages = round()
        guard let zone = AgentTurnThinking.zones(in: messages, includeReasoning: false).first,
              let usage = AgentTurnUsageReader.usage(in: messages, includeReasoning: false)[0] else {
            return XCTFail("没有聚出区 / 没有读数 ⇒ 后面几条都没量到")
        }
        let expected = AgentTokenEstimator.tokens(zone.text)
        print("🧪 Thinking 行 \(usage.thinkingTokens) tokens / 合并后的区 \(expected) tokens"
              + " / 输出段 \(usage.outputTokens) / 工具 \(usage.toolTokens)（\(usage.toolCallCount) 次）")

        XCTAssertEqual(usage.thinkingTokens, expected, "Thinking 行的数不是合并后那个区的 token 合计")
        XCTAssertGreaterThan(usage.thinkingTokens, 0, "Thinking 行是 0 ⇒ 读数没接上")
        XCTAssertNotEqual(usage.thinkingTokens, usage.outputTokens, "Thinking 行拿了输出段那份文本")
        // 五段都在里面：单调（段越多 token 越多）。
        let fewer = round(steps: 2)
        let fewerUsage = AgentTurnUsageReader.usage(in: fewer, includeReasoning: false)[0]
        XCTAssertLessThan(fewerUsage?.thinkingTokens ?? .max, usage.thinkingTokens,
                          "两步的思考不比五步少 ⇒ 累计算错了")
    }

    // MARK: - ③ Σ == thinking + tools + output

    func testTotalIsExactlyThinkingPlusToolsPlusOutput() {
        let messages = round(steps: 5, tools: 1)
        guard let usage = AgentTurnUsageReader.usage(in: messages, includeReasoning: false)[0] else {
            return XCTFail("没有读数")
        }
        print("🧪 Σ \(usage.totalTokens) = \(usage.thinkingTokens) + \(usage.toolTokens) + \(usage.outputTokens)")
        XCTAssertEqual(usage.totalTokens,
                       usage.thinkingTokens + usage.toolTokens + usage.outputTokens,
                       "Σ 不是三项之和 ⇒ 合计口径不对")
        XCTAssertGreaterThan(usage.toolTokens, 0, "工具段 0 tokens ⇒ 工具行没读数")
        XCTAssertGreaterThan(usage.outputTokens, 0, "输出段 0 tokens ⇒ 结论没算进去")

        // 反例：Σ 只算输出（把 total 换成 outputTokens）⇒ 同一套断言必须报红。
        let outputOnly = usage.outputTokens
        let red = outputOnly == usage.thinkingTokens + usage.toolTokens + usage.outputTokens
        print("🧪 反例（Σ 只算输出 \(outputOnly)）⇒ " + (red ? "假绿 ❌" : "判红 ✅"))
        XCTAssertFalse(red, "Σ 只算输出也能过 ⇒ 等式没有牙齿")
    }

    // MARK: - 工具次数 / 分轮 / 空轮

    func testToolCallCountAndTurnsStaySeparate() {
        var messages = round(steps: 3, tools: 2)
        messages.append(.init(role: .user, text: "第二轮：再来一次。"))
        messages.append(.init(role: .assistant, text: "第二轮的过程说明。"))
        messages.append(.init(role: .tool, text: "▸ read_file · Core/A.swift  ✓ · 0.1s"))
        messages.append(.init(role: .assistant, text: "第二轮结论。"))

        let usage = AgentTurnUsageReader.usage(in: messages, includeReasoning: false)
        let first = usage[0]
        let second = usage[usage.keys.max() ?? 0]
        print("🧪 两轮读数：第一轮 工具 \(first?.toolCallCount ?? -1) 次 / Σ \(first?.totalTokens ?? -1)；"
              + "第二轮 工具 \(second?.toolCallCount ?? -1) 次 / Σ \(second?.totalTokens ?? -1)")
        XCTAssertEqual(first?.toolCallCount, 2, "第一轮工具次数不对")
        XCTAssertEqual(second?.toolCallCount, 1, "第二轮工具次数不对（跨轮串了）")
        XCTAssertGreaterThan(second?.thinkingTokens ?? 0, 0, "第二轮的思考没算进来")
        XCTAssertNotEqual(first?.thinkingTokens, second?.thinkingTokens,
                          "两轮的 Thinking 数一样 ⇒ 分轮没分开")

        // 空轮（只有提问）：不产出任何数 —— 界面据此不画三行（零占位）。
        let empty = AgentTurnUsageReader.usage(in: [.init(role: .user, text: "还没有回复。")],
                                               includeReasoning: false)[0]
        XCTAssertEqual(empty?.isEmpty, true, "只有提问的轮也报了用量 ⇒ 会画出空壳三行")
    }

    /// 估算口径就是仓库既有那一个（不另立第二套）。
    func testEstimationUsesTheSharedEstimator() {
        let text = "abc汉字"
        print("🧪 估算口径：\"\(text)\" ⇒ \(AgentTokenEstimator.tokens(text)) tokens（汉字 1 字 1、其余 4 字符 1）")
        XCTAssertEqual(AgentTokenEstimator.tokens(text), 2 + 1, "估算口径变了（应 2 个汉字 + 3 个 ASCII 向上取整）")

        let usage = AgentTurnUsage(thinkingTokens: 1, toolCallCount: 1, toolTokens: 2, outputTokens: 3)
        XCTAssertTrue(usage.isEstimated, "默认就是估算 ⇒ 数字前要带 ~")
        XCTAssertEqual(usage.totalTokens, 6)
    }
}
