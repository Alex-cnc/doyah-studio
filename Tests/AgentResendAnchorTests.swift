import XCTest
@testable import DoyahCore

/// 「重发这一条」的锚点判定（§9.1.16 ③）。
///
/// 语义守则：重发 = **以那条助手消息对应的提问为锚再跑一轮**，旧轮保留。
/// 找错锚点等于改写了历史提问；找不到锚点就必须放弃，不许拿别的文本凑数。
final class AgentResendAnchorTests: XCTestCase {

    private func message(_ role: AgentChatRole, _ text: String) -> AgentChatMessage {
        AgentChatMessage(role: role, text: text)
    }

    func testFindsTheQuestionBehindAnAnswer() {
        let ask = message(.user, "看看上个月订单")
        let answer = message(.assistant, "好的。")
        let again = message(.assistant, "补充一句。")
        // 第二轮的那条助手消息，锚点仍应是**同一次提问**（两条回答共享一个提问）。
        XCTAssertEqual(AgentResendAnchor.userPrompt(before: again.id, in: [ask, answer, again]), "看看上个月订单")
        XCTAssertEqual(AgentResendAnchor.userPrompt(before: answer.id, in: [ask, answer, again]), "看看上个月订单")
    }

    func testPicksTheNearestQuestionNotTheFirstOne() {
        let first = message(.user, "第一问")
        let firstAnswer = message(.assistant, "第一答")
        let second = message(.user, "第二问")
        let secondAnswer = message(.assistant, "第二答")
        let all = [first, firstAnswer, second, secondAnswer]
        XCTAssertEqual(AgentResendAnchor.userPrompt(before: secondAnswer.id, in: all), "第二问")
        XCTAssertEqual(AgentResendAnchor.userPrompt(before: firstAnswer.id, in: all), "第一问")
    }

    func testNoAnchorWhenNothingWasAskedBefore() {
        let opening = message(.assistant, "有什么可以帮你？")
        XCTAssertNil(AgentResendAnchor.userPrompt(before: opening.id, in: [opening]),
                     "前面没有提问 ⇒ 必须放弃重发，不许编一个锚点")
    }

    func testUnknownMessageReturnsNil() {
        let other = message(.user, "问题")
        XCTAssertNil(AgentResendAnchor.userPrompt(before: message(.assistant, "x").id,
                                                  in: [other]))
    }

    func testToolMessagesAreNotMistakenForQuestions() {
        let ask = message(.user, "跑一下")
        let tool = message(.tool, "rows:3")
        let answer = message(.assistant, "跑完了")
        XCTAssertEqual(AgentResendAnchor.userPrompt(before: answer.id, in: [ask, tool, answer]), "跑一下")
    }
}
