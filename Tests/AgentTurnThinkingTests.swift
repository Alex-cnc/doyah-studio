import XCTest
@testable import DoyahCore

/// **「一轮一个思考区」的聚合规约**（详设 §3.33.4）。
///
/// ## 主人原话（beta1.0.7 真机）
///
/// > 「多个步骤的思考应该是合一起的啊，现在是分成了一块一块的」
///
/// 改前 `AgentChatView` 在逐条消息的 `ForEach` 里实例化思考区 ⇒ 每个 step 一块。
/// 这一组钉的是**聚合本身**（谁归哪一轮、段序、段数、工具不进思考区）；
/// 端上的「页面上几个区 / 区多高 / 折一次折整轮」在
/// `TestsUISnapshot/AgentTurnThinkingZoneProbeTests`。
final class AgentTurnThinkingTests: XCTestCase {

    private func stepText(_ step: Int) -> String {
        "第 \(step) 步：我先读一下 Core/File\(step).swift，看看这一段落在哪一层，再决定改哪里。"
    }

    /// 一轮五步：每步一条过程叙述，步间夹一条工具消息（形状与 `Core/AgentChat` 写出来的一致）。
    private func round(steps: Int = 5, conclusion: Bool = true) -> [AgentChatMessage] {
        var messages: [AgentChatMessage] = [.init(role: .user, text: "把每步各自的思考块合并成一轮一个。")]
        for step in 1...steps {
            messages.append(.init(role: .assistant, text: stepText(step)))
            messages.append(.init(role: .tool, text: "▸ read_file · Core/File\(step).swift  ✓ · 0.5s"))
        }
        if conclusion {
            messages.append(.init(role: .assistant, text: "改完了：五个步骤的思考合成一个区，工具块没动。"))
        }
        return messages
    }

    /// 改前形态的聚合（反例用）：一条助手消息一块 ⇒ 步数 == 块数。
    ///
    /// 这不是猜的反例，是**改前那段代码的语义**：`AgentChatView` 在 `ForEach` 里逐条调
    /// `thinkingZone(message:)`，每块只管自己那一条消息的 `thinkingParts`。
    private func legacyPerStepZones(in messages: [AgentChatMessage]) -> [AgentThinkingSegment] {
        let finals = AgentChatTurnShape.finalAssistantIndices(in: messages)
        return messages.enumerated().compactMap { index, message in
            guard message.role == .assistant,
                  let text = AgentTurnThinking.segmentText(of: message,
                                                           isFinalAssistant: finals.contains(index),
                                                           includeReasoning: false) else { return nil }
            return AgentThinkingSegment(step: index, text: text)
        }
    }

    // MARK: - ① 一轮 = 一个区

    func testOneRoundYieldsExactlyOneZoneNoMatterHowManySteps() {
        let messages = round(steps: 5)
        let zones = AgentTurnThinking.zones(in: messages, includeReasoning: false)
        print("🧪 ① 五步一轮 ⇒ 思考区 \(zones.count) 个 / 段 \(zones.first?.segments.count ?? 0) 段"
              + " / 步数读数 \(zones.first?.stepCount ?? 0)")

        XCTAssertEqual(zones.count, 1,
                       "五步一轮聚出 \(zones.count) 个思考区 ⇒ 还是「一块一块」")
        XCTAssertEqual(zones.first?.segments.count, 5, "五步只聚出 \(zones.first?.segments.count ?? 0) 段")
        XCTAssertEqual(zones.first?.stepCount, 5, "折起来那一行会报错步数")

        // 反例：改前的「一条消息一块」在**同一份判据**下必须报红。
        let legacy = legacyPerStepZones(in: messages)
        print("🧪 ① 反例（按 step 分块的改前语义）⇒ \(legacy.count) 块"
              + (legacy.count > 1 ? " ⇒ 判红 ✅" : " ⇒ 假绿 ❌"))
        XCTAssertGreaterThan(legacy.count, 1, "反例只有 \(legacy.count) 块 ⇒ 判据量不到「一块一块」")
        XCTAssertNotEqual(legacy.count, zones.count,
                          "反例块数 \(legacy.count) 与新形态区数 \(zones.count) 相同 ⇒ 判据分不开两种形态")
    }

    /// 同一个 `ForEach` 口径：给逐条消息用的映射表**一条轮只命中一次**。
    func testZonesByAnchorIndexHitsOneMessagePerRound() {
        let messages = round(steps: 5)
        let byAnchor = AgentTurnThinking.zonesByAnchorIndex(in: messages, includeReasoning: false)
        let anchor = byAnchor.keys.first
        print("🧪 ① 挂区下标 \(byAnchor.keys.sorted()) ⇒ 命中 \(byAnchor.count) 条消息"
              + "（该条是本轮第一条助手消息：\(anchor.map { messages[$0].text.prefix(6) } ?? "无")）")
        XCTAssertEqual(byAnchor.count, 1, "一輪命中了 \(byAnchor.count) 条消息 ⇒ 页面上就是 \(byAnchor.count) 个区")
        if let anchor {
            XCTAssertEqual(messages[anchor].role, .assistant, "区挂在非助手消息上")
            XCTAssertTrue(messages[anchor].text.hasPrefix("第 1 步"), "区不是挂在第一段的位置")
        }
    }

    // MARK: - ③ 顺序保真：段序 == 步序

    func testSegmentsKeepStepOrderAndTextSequence() {
        let messages = round(steps: 5)
        guard let zone = AgentTurnThinking.zones(in: messages, includeReasoning: false).first else {
            return XCTFail("没有聚出区 ⇒ 后面三条都没量到")
        }
        XCTAssertEqual(zone.segments.map(\.step), [1, 2, 3, 4, 5],
                       "段号 \(zone.segments.map(\.step)) ≠ 1…5 ⇒ 顺序丢了")

        // 文本顺序：每一段都必须出现在上一段之后（拼接保序，不是按字典/哈希重排）。
        var cursor = zone.text.startIndex
        var positions: [Int] = []
        for segment in zone.segments {
            guard let range = zone.text.range(of: segment.text, range: cursor..<zone.text.endIndex) else {
                return XCTFail("第 \(segment.step) 段不在上一段之后 ⇒ 拼接顺序乱了")
            }
            positions.append(zone.text.distance(from: zone.text.startIndex, to: range.lowerBound))
            cursor = range.upperBound
        }
        print("🧪 ③ 五段文本在整区里的起点 \(positions) / 段号 \(zone.segments.map(\.step))")
        XCTAssertEqual(positions, positions.sorted(), "文本起点 \(positions) 不是升序 ⇒ 读到的顺序与步序不一致")
        // 步序断言：第 N 段的第一句就是「第 N 步」。
        for segment in zone.segments {
            XCTAssertTrue(segment.text.hasPrefix("第 \(segment.step) 步"),
                          "第 \(segment.step) 段的开头是「\(segment.text.prefix(8))」⇒ 串段了")
        }
    }

    // MARK: - ⑤ 工具不进思考区；分轮不串

    func testToolsStayOutOfTheZoneAndRoundsDoNotMerge() {
        var messages = round(steps: 3)
        messages.append(.init(role: .user, text: "第二轮：再来一次。"))
        messages.append(.init(role: .assistant, text: "第二轮的过程独白。"))
        messages.append(.init(role: .assistant, text: "第二轮结论。"))

        let zones = AgentTurnThinking.zones(in: messages, includeReasoning: false)
        print("🧪 ⑤ 两轮 ⇒ 区 \(zones.count) 个 / 段数 \(zones.map(\.segments.count))")
        XCTAssertEqual(zones.count, 2, "两轮聚成 \(zones.count) 个区 ⇒ 跨轮串了（或同轮又分块了）")
        XCTAssertEqual(zones.map(\.segments.count), [3, 1], "每轮的段数不对 ⇒ 段落归属错了")

        for zone in zones {
            for segment in zone.segments {
                XCTAssertFalse(segment.text.contains("read_file"),
                               "工具行进了思考区：\(segment.text.prefix(20))")
            }
        }
        // 工具消息一条都不该产出段（它们是动作，另成块）。
        XCTAssertTrue(messages.filter { $0.role == .tool }
            .allSatisfy { AgentTurnThinking.segmentText(of: $0, isFinalAssistant: false, includeReasoning: true) == nil },
                      "工具消息被算成了思考段")
    }

    // MARK: - 空轮 / 思考段开关

    func testEmptyProcessProducesNoZoneAndReasoningFollowsTheSwitch() {
        let bare: [AgentChatMessage] = [
            .init(role: .user, text: "只有结论的一轮。"),
            .init(role: .assistant, text: "结论：一句话。"),
        ]
        XCTAssertTrue(AgentTurnThinking.zones(in: bare, includeReasoning: false).isEmpty,
                      "没有过程内容也聚出了区 ⇒ 空块占位（契约②：零占位）")

        let withReasoning: [AgentChatMessage] = [
            .init(role: .user, text: "思考段开着。"),
            .init(role: .assistant, text: "第 1 步：读一下。", thinking: "内部：先看目录结构。"),
            .init(role: .assistant, text: "第 2 步：改。", thinking: "内部：只动一处。"),
        ]
        let off = AgentTurnThinking.zones(in: withReasoning, includeReasoning: false)
        let on = AgentTurnThinking.zones(in: withReasoning, includeReasoning: true)
        print("🧪 思考段开关：关 ⇒ 段 \(off.first?.segments.count ?? 0) 段（仅独白）；"
              + "开 ⇒ 首段含思考段 \(on.first?.segments.first?.text.contains("内部：") ?? false)")
        XCTAssertEqual(off.count, 1, "关了思考段就不该有区（仍有叙述，区仍在）")
        XCTAssertFalse(off.first?.text.contains("内部：") ?? true, "开关关着，思考段还是画出来了")
        XCTAssertTrue(on.first?.segments.first?.text.hasPrefix("内部：") ?? false,
                      "开关打开时思考段没有排在本段最前")
    }
}
