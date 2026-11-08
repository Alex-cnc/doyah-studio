import XCTest

@testable import DoyahCore

/// **「回到消息底部」入口的判定**（详设 §3.39）—— 出现 / 消失 / 滞回 / 尺寸。
///
/// 这一族钉的是**纯函数**：视图只把这个结果画出来，判据与视图不各写一个阈值。
final class AgentJumpToBottomTests: XCTestCase {

    // MARK: - 出现：距底 > 40pt 且不在贴底态

    func testAppearsOnlyWhenScrolledUpBeyondAppearDistance() {
        // 上翻 100pt、读数说没贴底 ⇒ 出现。
        XCTAssertTrue(AgentJumpToBottom.isVisible(currently: false,
                                                  distanceToBottom: 100,
                                                  isPinnedToBottom: false))
        // 40pt 整：还不到（门槛是「超过」）。
        XCTAssertFalse(AgentJumpToBottom.isVisible(currently: false,
                                                   distanceToBottom: AgentJumpToBottom.appearDistance,
                                                   isPinnedToBottom: false))
        // 30pt：没到门槛。
        XCTAssertFalse(AgentJumpToBottom.isVisible(currently: false,
                                                   distanceToBottom: 30,
                                                   isPinnedToBottom: false))
    }

    /// **贴底态一律不出现**：那一档里距底也可能 > 40pt（内容刚长高、我们还没跟上），
    /// 但那是「我们自己落后」，不是人往上翻 —— 弹出入口等于催人往下点一下。
    func testNeverAppearsWhilePinned() {
        XCTAssertFalse(AgentJumpToBottom.isVisible(currently: false,
                                                   distanceToBottom: 400,
                                                   isPinnedToBottom: true))
        XCTAssertFalse(AgentJumpToBottom.isVisible(currently: true,
                                                   distanceToBottom: 400,
                                                   isPinnedToBottom: true))
    }

    // MARK: - 消失：距底 ≤ 4pt（与贴底同一容差）

    func testDisappearsAtTheBottomTolerance() {
        XCTAssertFalse(AgentJumpToBottom.isVisible(currently: true,
                                                   distanceToBottom: 3,
                                                   isPinnedToBottom: false))
        XCTAssertEqual(AgentJumpToBottom.disappearDistance, AgentScrollFollow.bottomTolerance,
                       "消失门槛必须与贴底容差同源（4pt），不许另立一个数")
    }

    // MARK: - 滞回：两档之间保持现状

    func testHysteresisKeepsStateBetweenTheTwoThresholds() {
        // 已在显示：距底 10pt（> 4、< 40）⇒ 仍显示（否则在 40pt 上下抖一像素就闪一次）。
        XCTAssertTrue(AgentJumpToBottom.isVisible(currently: true,
                                                  distanceToBottom: 10,
                                                  isPinnedToBottom: false))
        // 未显示：距底 10pt ⇒ 不出现。
        XCTAssertFalse(AgentJumpToBottom.isVisible(currently: false,
                                                   distanceToBottom: 10,
                                                   isPinnedToBottom: false))
    }

    // MARK: - 尺寸口径

    func testGeometryIsInsideTheDeclaredBand() {
        XCTAssertTrue((20...24).contains(AgentJumpToBottom.barHeight),
                      "入口高 \(AgentJumpToBottom.barHeight)pt 不在 20–24 的带里")
        XCTAssertEqual(AgentJumpToBottom.bandHeight,
                       AgentJumpToBottom.topGap + AgentJumpToBottom.barHeight
                       + AgentJumpToBottom.bottomGap + AgentJumpToBottom.viewportInset,
                       "恒留带 = 呼吸 + 入口高 + 底边间距 + 视口那 2pt，四段都得算进去")
        XCTAssertEqual(AgentJumpToBottom.topGap, 4, "入口与视口之间留 4pt 呼吸")
        XCTAssertEqual(AgentJumpToBottom.bottomGap, 12, "底边到对话区底边 = 块间距 Spacing.m = 12pt")
        // 带在**视口之外**：它比入口本身高，多出来的就是底边间距 ⇒ 入口不会落进视口里压正文。
        XCTAssertEqual(AgentJumpToBottom.bandHeight - AgentJumpToBottom.barHeight,
                       AgentJumpToBottom.bottomGap + AgentJumpToBottom.topGap
                       + AgentJumpToBottom.viewportInset,
                       "带减入口 = 上下两段间距 + 视口那 2pt（入口整体在视口之外）")
    }
}
