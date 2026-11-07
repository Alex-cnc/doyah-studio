import XCTest

@testable import DoyahCore

/// 「当前轮用户问题吸顶」的纯判定（详设 §3.34）。
///
/// 判的是两件事：
/// ① **钉哪一条** —— 必须是一轮的轮首用户消息，且只能是**当前轮**（不是更早的轮次，
///    也不是「随便什么最后一条用户消息」）；
/// ② **钉不钉** —— 消息顶边是否已经越过视口顶（等号不算：贴顶时它还看得见）。
///
/// 端上几何读数在 `TestsUISnapshot/AgentChatStickyQuestionProbeTests.swift`；
/// 这里判的是那份读数背后的判定本身（不跑 UI 也能判红）。
final class AgentStickyQuestionTests: XCTestCase {

    private func user(_ text: String) -> AgentChatMessage {
        AgentChatMessage(role: .user, text: text)
    }

    private func assistant(_ text: String) -> AgentChatMessage {
        AgentChatMessage(role: .assistant, text: text)
    }

    // MARK: - ① 钉哪一条

    /// 三轮对话 ⇒ 钉**第三轮**那条提问（不是第一条，也不是最后一条消息）。
    func testCurrentTurnIsTheLastTurnsQuestion() {
        let first = user("第一轮：这条消息是什么？")
        let second = user("第二轮：把它改一下")
        let third = user("第三轮：用户发出的问题被滚动的输出冲掉了")
        let messages = [first, assistant("答一"), second, assistant("答二"), third, assistant("答三")]

        let current = AgentStickyQuestion.currentTurn(in: messages)
        XCTAssertEqual(current?.messageID, third.id, "当前轮取错了：应当钉第三轮那条提问")
        XCTAssertEqual(current?.index, 4, "下标不对：第三轮提问在 messages[4]")
        XCTAssertEqual(current?.text, third.text)

        // 反例口径：如果拿「最后一条消息」去钉（它是一条助手回复），钉的就不是用户的话。
        XCTAssertNotEqual(current?.messageID, messages.last?.id,
                          "钉到了最后一条消息（助手回复）⇒ 取数口径错了")
        XCTAssertNotEqual(current?.messageID, first.id, "钉到了第一轮 ⇒ 没有「当前轮」概念")
    }

    /// 新一轮开始 ⇒ 钉点跟着换（契约④「进入下一轮才换」）。
    func testNewTurnReplacesThePinnedQuestion() {
        let first = user("旧问题")
        let before = [first, assistant("旧回答")]
        XCTAssertEqual(AgentStickyQuestion.currentTurn(in: before)?.messageID, first.id)

        let second = user("新问题")
        let after = before + [second]
        XCTAssertEqual(AgentStickyQuestion.currentTurn(in: after)?.messageID, second.id,
                       "新一轮提问已经到了，钉的还是上一轮 ⇒ 换轮没生效")
    }

    /// 没有用户提问（空会话 / 只有助手消息）⇒ 没有可钉的东西。
    func testNoQuestionMeansNil() {
        XCTAssertNil(AgentStickyQuestion.currentTurn(in: []))
        XCTAssertNil(AgentStickyQuestion.currentTurn(in: [assistant("只有回复")]))
    }

    /// 轮次切分只有一处定义：`AgentChatTurnShape.turnStartIndices` 与「哪条是结论」同一套切分。
    func testTurnStartsComeFromTheSingleTurnDefinition() {
        let messages = [user("a"), assistant("1"), user("b"), assistant("2"), assistant("3")]
        XCTAssertEqual(AgentChatTurnShape.turnStartIndices(in: messages), [0, 2])
        // 最后一轮的结论 = 最后一条助手消息（下标 4）—— 与吸顶取的是同一份轮切分。
        XCTAssertEqual(AgentChatTurnShape.finalAssistantIndices(in: messages), [1, 4])
    }

    // MARK: - ② 钉不钉（几何判定）

    func testStickyOnlyAfterTheQuestionLeavesTheTop() {
        let questionTop: CGFloat = 200

        // 还看得见（视口顶在它上面）⇒ 不钉。
        XCTAssertFalse(AgentStickyQuestion.shouldStick(viewportTop: 0, questionTop: questionTop))
        XCTAssertFalse(AgentStickyQuestion.shouldStick(viewportTop: 199, questionTop: questionTop))
        // **恰好贴顶**：消息顶边与视口顶齐平 ⇒ 仍看得见 ⇒ 不钉（契约②「不重叠、不双显」）。
        XCTAssertFalse(AgentStickyQuestion.shouldStick(viewportTop: questionTop, questionTop: questionTop),
                       "贴顶就钉 ⇒ 同一条问题在屏幕上出现两次")
        // 差半个像素以内的抖动也不钉（容差）。
        XCTAssertFalse(AgentStickyQuestion.shouldStick(viewportTop: questionTop + 0.4,
                                                       questionTop: questionTop))
        // 真的滚出去了 ⇒ 钉。
        XCTAssertTrue(AgentStickyQuestion.shouldStick(viewportTop: questionTop + 1,
                                                      questionTop: questionTop))
        XCTAssertTrue(AgentStickyQuestion.shouldStick(viewportTop: 4000, questionTop: questionTop))
    }

    /// 判定**只与几何有关**：本轮结束与否、跑没跑完不进门（契约④ 本轮结束不立刻消失）。
    func testStickyDecisionHasNoStateArgument() {
        let questionTop: CGFloat = 120
        // 同一个几何读数 ⇒ 同一个答案；这里没有「isRunning」这类入参可传 —— 编译期即证明。
        XCTAssertEqual(AgentStickyQuestion.shouldStick(viewportTop: 500, questionTop: questionTop),
                       AgentStickyQuestion.shouldStick(viewportTop: 500, questionTop: questionTop))
    }

    // MARK: - ⑤ 一行化

    func testBarTextIsAlwaysOneLine() {
        let long = String(repeating: "用户发出的问题被滚动的输出冲掉了。", count: 12)   // > 200 字
        let multiLine = "第一行\n\n第二行   带\t空格\r\n第三行"
        let line = AgentStickyQuestion.lineText(multiLine)
        print("🧪 一行化：\(multiLine.debugDescription) ⇒ \(line.debugDescription)")
        XCTAssertEqual(line, "第一行 第二行 带 空格 第三行")
        XCTAssertFalse(AgentStickyQuestion.lineText(long).contains("\n"),
                       "长问题一行化之后还带换行 ⇒ 条会长成多行")
        XCTAssertEqual(AgentStickyQuestion.lineText("   "), "")
    }

    /// 条高必须 ≤ 28pt（契约①），且取的是「一行」那个常量。
    func testBarHeightIsOneLineAndWithinTheLimit() {
        print("🧪 吸顶条高 \(AgentStickyQuestion.barHeight)pt（上限 28pt）")
        XCTAssertLessThanOrEqual(AgentStickyQuestion.barHeight, 28)
        XCTAssertEqual(AgentStickyQuestion.barHeight, Metrics.listRowHeight, accuracy: 0.001,
                       "条高不是「一行」⇒ 折叠/展开档位之外又多了一个高度")
    }
}
