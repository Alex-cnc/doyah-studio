import XCTest
@testable import DoyahCore

/// 对话面板空态的显示判据（§9.1.16 ⑦）。
///
/// 守的是一句话：**空态只在真的空的时候出现**，别在流式开始后还赖着不走。
final class AgentChatEmptyStateGateTests: XCTestCase {

    func testShowsOnlyWhenTrulyEmpty() {
        XCTAssertTrue(AgentChatEmptyStateGate.shouldShow(messageCount: 0, cardCount: 0, isRunning: false))
    }

    func testHiddenOnceMessageExists() {
        XCTAssertFalse(AgentChatEmptyStateGate.shouldShow(messageCount: 1, cardCount: 0, isRunning: false))
    }

    func testHiddenWhenOnlyCardsExist() {
        // 工具卡先于消息出现（模型第一跳就调工具）：这时也不许再画起手话。
        XCTAssertFalse(AgentChatEmptyStateGate.shouldShow(messageCount: 0, cardCount: 1, isRunning: false))
    }

    func testHiddenWhileRunning() {
        XCTAssertFalse(AgentChatEmptyStateGate.shouldShow(messageCount: 0, cardCount: 0, isRunning: true))
    }
}
