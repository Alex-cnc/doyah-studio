import XCTest
@testable import DoyahCore

/// 「哪一段算结论」的判据（详设 §3.33，2026-11-07 真机复验）。
///
/// 主人原话：「Doyah Agent 里输出的『我先读一下……再……』这是思考过程吗？」——是。
/// 模型把过程独白写进正文，界面照单全收铺成正文 ⇒ 要读的结论被挤到下面。
///
/// 这几条钉的是**规则本身**（`AgentAnswerClassifier` 的四条）与**轮内位置**
/// （`AgentChatTurnShape`）；端上的几何读数在
/// `TestsUISnapshot/AgentChatNarrationProbeTests`。
final class AgentAnswerSplitTests: XCTestCase {

    /// 真机那一轮的过程独白（模型写在正文里的自述）。
    private let narration = "我先读一下 Core/AgentChat.swift 和 Core/AgentDisplayPreferences.swift，"
        + "看看折叠是在哪一层做的，再决定改哪里。"

    /// 结论（30 行 + 一个代码块：被折了就必然切两半）。
    private var conclusion: String {
        var lines = (1...26).map { "第 \($0) 行：结论正文。" }
        lines.append("```swift")
        lines.append("let answer = 42")
        lines.append("```")
        return lines.joined(separator: "\n")
    }

    // MARK: - 规则 2 / 3：独白在前、结论在后

    func testMonologueParagraphIsFoldedAndConclusionStaysWhole() {
        let text = narration + "\n\n" + conclusion
        let split = AgentAnswerClassifier.split(text)
        XCTAssertEqual(split.narration, narration, "「我先读一下……再……」没有归进独白 ⇒ 它会被当正文铺")
        XCTAssertEqual(split.conclusion, conclusion, "结论被切走了：\(split.conclusion.prefix(40))…")
        XCTAssertTrue(split.hasNarration)
        XCTAssertFalse(split.isNarrationOnly)
        // 结论里那句独白一个字都不许留（否则它同时出现在折叠区与正文两处）。
        XCTAssertFalse(split.conclusion.contains("我先读一下"))
    }

    /// 多段连续独白 ⇒ 全部折；结论仍然是最后那一段。
    func testMultipleNarrationParagraphsAreAllFolded() {
        let text = narration + "\n\n我再看一下测试文件。\n\n" + conclusion
        let split = AgentAnswerClassifier.split(text)
        XCTAssertEqual(split.narration, narration + "\n\n我再看一下测试文件。")
        XCTAssertEqual(split.conclusion, conclusion)
    }

    /// 结论是**连续的末尾段**：中间的小标题 / 列表也属于结论，不许被当成独白切掉。
    func testTrailingBlocksAllBelongToConclusion() {
        let text = narration + "\n\n## 结论\n\n- 第一条\n- 第二条\n\n" + conclusion
        let split = AgentAnswerClassifier.split(text)
        XCTAssertEqual(split.narration, narration)
        XCTAssertTrue(split.conclusion.hasPrefix("## 结论"), split.conclusion)
        XCTAssertTrue(split.conclusion.hasSuffix("```"), "代码块被切掉了：\(split.conclusion)")
    }

    // MARK: - 规则 1：代码块永远不切开

    func testFencedCodeBlockIsNeverSplit() {
        let text = "先说结论：\n\n```swift\nlet a = 1\n\nlet b = 2\n```"
        let blocks = AgentAnswerClassifier.blocks(text)
        XCTAssertEqual(blocks.count, 2, "代码块里的空行被当成了分段点：\(blocks)")
        XCTAssertEqual(blocks[1], "```swift\nlet a = 1\n\nlet b = 2\n```")
    }

    /// 代码块里的 `...` / `then` 不算「续接式独白」（那是代码）。
    func testCodeBlockWithEllipsisIsNotNarration() {
        let text = "```js\nconst more = [...rest];\nthen(() => 1);\n```"
        XCTAssertFalse(AgentAnswerClassifier.isNarrationParagraph(text))
    }

    // MARK: - 规则 3 的兜底：末段自己是独白也不能折成 0

    func testTrailingNarrationStillKeepsSomethingVisible() {
        let text = "第 1 段结论：改了三处。\n\n我先再确认一下这次的读法。"
        let split = AgentAnswerClassifier.split(text)
        XCTAssertFalse(split.conclusion.isEmpty, "整条都被折进独白 ⇒ 正文区一个字都没有")
        XCTAssertTrue(split.conclusion.contains("第 1 段结论") || split.conclusion.contains("我先再确认"),
                      "兜底结论取错了：\(split.conclusion)")
    }

    // MARK: - 规则 4：段内再切一句

    func testLeadingNarrationSentenceInsideConclusionParagraph() {
        let text = "我先读一下配置。结论是折叠发生在 previewSplit。"
        let split = AgentAnswerClassifier.split(text)
        XCTAssertEqual(split.narration, "我先读一下配置。")
        XCTAssertEqual(split.conclusion, "结论是折叠发生在 previewSplit。")
    }

    /// 纯结论（没有独白）⇒ 不许凭空造出一个折叠区。
    func testPureConclusionHasNoNarration() {
        let split = AgentAnswerClassifier.split(conclusion)
        XCTAssertNil(split.narration)
        XCTAssertEqual(split.conclusion, conclusion)
    }

    /// 英文的过程自述同样算独白（模型不一定说中文）。
    func testEnglishNarrationOpenerIsRecognized() {
        let text = "Let me first read the two files, then decide where the folding happens.\n\n"
            + "The conclusion: folding happens in `previewSplit`."
        let split = AgentAnswerClassifier.split(text)
        XCTAssertNotNil(split.narration, "英文的过程自述没被认出来 ⇒ 它会被当正文铺")
        XCTAssertTrue(split.conclusion.contains("The conclusion"))
    }

    /// **反例**：不做切分（改前的行为 = 整条当正文）时，独白就落在正文里。
    /// 这一条证明上面那些断言不是空的：差异确实存在，而且能被量出来。
    func testWithoutSplitTheMonologueLandsInBody() {
        let text = narration + "\n\n" + conclusion
        // 改前：`assistantBody` 直接把 `message.text` 交给 Markdown 正文。
        XCTAssertTrue(text.contains("我先读一下"), "夹具本身不含独白 ⇒ 反例是空的")
        // 改后：正文只拿结论。
        XCTAssertFalse(AgentAnswerClassifier.split(text).conclusion.contains("我先读一下"))
    }

    // MARK: - 轮内位置（哪一条助手消息是结论）

    func testOnlyLastAssistantMessageOfTurnIsConclusion() {
        var messages: [AgentChatMessage] = [
            .init(role: .user, text: "这一处为什么折了？"),
            .init(role: .assistant, text: "我先读一下两个文件。"),
            .init(role: .assistant, text: "我再看看测试。"),
            .init(role: .assistant, text: "结论：折叠在 previewSplit。"),
            .init(role: .user, text: "那改吧。"),
            .init(role: .assistant, text: "改好了，三处都改了。"),
        ]
        // 工具块与时间线事件不参与「哪条是结论」。插在第 3 位之后，原来那三条助手消息的
        // 下标各自后移 1（这是夹具的事实，不是判据的口径）。
        messages.insert(.init(role: .tool, text: "▸ read_file · Core/x.swift  ✓ · 0.1s"), at: 3)
        let finals = AgentChatTurnShape.finalAssistantIndices(in: messages)
        XCTAssertEqual(messages.count, 7)
        XCTAssertEqual(finals, [4, 6], "轮内最后一条助手消息才是结论，实际：\(finals.sorted())")
    }

    /// 没有助手消息的轮（只有提问 / 只有过程行）⇒ 空集，不许误判。
    func testTurnWithoutAssistantHasNoConclusion() {
        let messages: [AgentChatMessage] = [
            .init(role: .user, text: "只问不答"),
            .init(role: .tool, text: "▸ search · foo  ✓ · 0.1s"),
        ]
        XCTAssertTrue(AgentChatTurnShape.finalAssistantIndices(in: messages).isEmpty)
    }

    /// 流式中判断「最后一条」也成立（末条就是正在吐的那条）。
    func testStreamingLastMessageIsTheConclusion() {
        let messages: [AgentChatMessage] = [
            .init(role: .user, text: "问"),
            .init(role: .assistant, text: "我先看看。"),
            .init(role: .assistant, text: "正在写结论", isStreaming: true),
        ]
        XCTAssertEqual(AgentChatTurnShape.finalAssistantIndices(in: messages), [2])
    }

    /// 只有**最后一轮**才可能处于「运行中」（更早的轮次一律终态）。
    func testOnlyLastTurnIsLive() {
        let messages: [AgentChatMessage] = [
            .init(role: .user, text: "第一问"),
            .init(role: .assistant, text: "第一答"),
            .init(role: .user, text: "第二问"),
            .init(role: .assistant, text: "第二答"),
        ]
        XCTAssertFalse(AgentChatTurnShape.isInLastTurn(in: messages, at: 1))
        XCTAssertTrue(AgentChatTurnShape.isInLastTurn(in: messages, at: 3))
        XCTAssertTrue(AgentChatTurnShape.isInLastTurn(in: messages, at: 2), "提问本身也属最后一轮")
    }

    // MARK: - 思考区三态（主人 2026-11-07 拍的产品决策）

    /// ① 运行中默认展开；② 终态默认折；③ 手动动过以用户为准。
    func testThinkingFoldFollowsPhaseUntilUserTouchesIt() {
        XCTAssertTrue(AgentThinkingFold.isExpanded(phase: .running, manual: nil),
                      "运行中默认折叠 ⇒ 「思考过程」看不见，主人第一眼只能看到一句摘要")
        XCTAssertFalse(AgentThinkingFold.isExpanded(phase: .finished, manual: nil),
                       "终态默认展开 ⇒ 过程信息把结论挤下去")
        XCTAssertTrue(AgentThinkingFold.isExpanded(phase: .finished, manual: true),
                      "终态手动展开被忽略 ⇒ 点不动")
        XCTAssertFalse(AgentThinkingFold.isExpanded(phase: .running, manual: false),
                       "运行中手动收起被忽略 ⇒ 点不动")
    }

    /// ③ sticky：同一轮内反复 register 不许把手动态清掉。
    func testManualStateIsStickyWithinTheTurn() {
        let turn = UUID()
        var state = AgentThinkingManualState()
        state.register(turnKey: turn)
        state.set(true)
        for _ in 0..<5 { state.register(turnKey: turn) }   // 每次重绘 / 新事件
        XCTAssertEqual(state.manual(for: turn), true, "同一轮内重绘把手动态清了 ⇒ 点一开就自己折回去")
    }

    /// ④ 新轮开始 ⇒ 回到「按阶段默认」（不沿用上一轮的选择）。
    func testManualStateResetsWhenTurnChanges() {
        let first = UUID()
        let second = UUID()
        var state = AgentThinkingManualState()
        state.register(turnKey: first)
        state.set(false)
        XCTAssertEqual(state.manual(for: first), false)

        state.register(turnKey: second)
        XCTAssertNil(state.manual(for: second), "新轮沿用了上一轮的手动态 ⇒ 等于没有默认形态")
        XCTAssertTrue(AgentThinkingFold.isExpanded(phase: .running, manual: state.manual(for: second)))
        XCTAssertNil(state.manual(for: first), "旧轮次的手动态不许再被读到")
    }
}

// MARK: - 结论不带标签壳（详设 §3.37 契约③）

/// 判据：给一段带壳的结论 ⇒ 渲染前的文本**不以**「结论 / Conclusion / 📌」开头；
/// 反例 = 壳没剥掉的原文，用**同一个**判定函数必须判红。
final class AgentAnswerLabelTests: XCTestCase {

    /// 判定函数：正文（去掉行首空白后）不许以这些壳开头。
    static let shells = ["结论", "Conclusion", "conclusion", "Answer", "回答", "📌", "🧾", "✅", "##"]

    static func shellViolations(_ rendered: String) -> [String] {
        let head = rendered.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let shell = shells.first(where: { head.hasPrefix($0) }) else { return [] }
        return ["渲染文本仍以「\(shell)」开头：\(head.prefix(24))"]
    }

    func testConclusionPrefixesAreStripped() {
        let cases: [(raw: String, expected: String)] = [
            ("结论：口令错了，先改连接配置。", "口令错了，先改连接配置。"),
            ("结论: 口令错了。", "口令错了。"),
            ("**结论**：口令错了。", "口令错了。"),
            ("## 结论\n\n口令错了。", "口令错了。"),
            ("Conclusion: the password is wrong.", "the password is wrong."),
            ("📌 结论：口令错了。", "口令错了。"),
            ("✅ 已改好：口令换成了新的。", "已改好：口令换成了新的。"),
        ]
        for item in cases {
            let rendered = AgentAnswerLabel.stripping(item.raw)
            let issues = Self.shellViolations(rendered)
            print("🧪 ③ 「\(item.raw.prefix(14))」⇒「\(rendered.prefix(20))」"
                  + (issues.isEmpty && rendered == item.expected ? " ✅" : " ⇒ \(issues)"))
            XCTAssertTrue(issues.isEmpty, issues.joined(separator: "；"))
            XCTAssertEqual(rendered, item.expected, "剥完的文本不对：\(item.raw)")
        }

        // 反例：不剥的原文喂同一套判定 ⇒ 必须判红（判据有牙齿）。
        let red = Self.shellViolations("结论：口令错了。")
        print("🧪 反例③（壳没剥）⇒ " + (red.isEmpty ? "假绿 ❌" : "判红 ✅"))
        XCTAssertFalse(red.isEmpty, "带壳的原文判据仍然绿 ⇒ ③ 没有牙齿")
    }

    /// 正文里的「结论」是内容，一个字都不许动；句子式「结论是：…」也不是壳。
    func testNonShellTextIsUntouched() {
        let untouched = [
            "这次排查的结论：索引缺失。",        // 不在行首
            "结论是：索引缺失。",                // 标签后面不是分隔符 ⇒ 不是壳
            "数据库连不上的原因：口令错。",       // 压根没有壳
        ]
        for text in untouched {
            XCTAssertEqual(AgentAnswerLabel.stripping(text), text, "把正文当成壳剥了：\(text)")
        }
        print("🧪 ③b 正文不动：\(untouched.count) 例原样返回 ✅")
    }
}
