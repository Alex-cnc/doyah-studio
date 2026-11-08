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
        XCTAssertEqual(AgentJumpToBottom.stripHeight,
                       AgentJumpToBottom.topGap + AgentJumpToBottom.barHeight
                       + AgentJumpToBottom.bottomGap + AgentJumpToBottom.viewportInset,
                       "保留条 = 呼吸 + 入口高 + 底边间距 + 视口那 2pt，四段都得算进去")
        XCTAssertEqual(AgentJumpToBottom.topGap, 4, "入口与视口之间留 4pt 呼吸")
        XCTAssertEqual(AgentJumpToBottom.bottomGap, 12, "底边到对话区底边 = 块间距 Spacing.m = 12pt")
        // 条在**视口之外**：它比入口本身高，多出来的就是底边间距 ⇒ 入口不会落进视口里压正文。
        XCTAssertEqual(AgentJumpToBottom.stripHeight - AgentJumpToBottom.barHeight,
                       AgentJumpToBottom.bottomGap + AgentJumpToBottom.topGap
                       + AgentJumpToBottom.viewportInset,
                       "条减入口 = 上下两段间距 + 视口那 2pt（入口整体在视口之外）")
    }

    // MARK: - 保留条：出现时 40pt、不出现时 **0pt**（空间还给正文）

    /// 契约②：不出现时这一格**整个不存在** —— 高度 0，不是「留一条空带」。
    func testStripTakesNoSpaceWhenTheEntryIsHidden() {
        XCTAssertEqual(AgentJumpToBottom.reservedHeight(visible: false), 0,
                       "入口不在时必须占 0pt（恒留一条空带就是把正文的空间白让出去）")
        XCTAssertEqual(AgentJumpToBottom.reservedHeight(visible: true),
                       AgentJumpToBottom.stripHeight,
                       "入口出现时占的就是保留条那一条")
    }

    /// 契约② 的**反例**：入口不在还给 40pt ⇒ 同一套判据必须判红（判据没有牙齿就白写）。
    func testStripConstantBandWouldBeCaught() {
        XCTAssertNotEqual(AgentJumpToBottom.reservedHeight(visible: false),
                          AgentJumpToBottom.stripHeight,
                          "隐藏态占了一条条高 ⇒ 这就是「恒留空带」，判据要报红")
    }

    /// 条高 **≤** 出现门槛：入口出现那一拍视口矮一条，而出现要求「距底 > 40」
    /// ⇒ 视口缩短不需要夹紧偏移，**正文一行都不跳**。条高一旦超过门槛，出现就会把正文顶一下。
    func testStripFitsInsideTheAppearThreshold() {
        XCTAssertTrue(AgentJumpToBottom.appearsWithoutShiftingContent,
                      "保留条 \(AgentJumpToBottom.stripHeight)pt > 出现门槛 "
                      + "\(AgentJumpToBottom.appearDistance)pt ⇒ 入口一出现就会夹紧偏移、正文跳一条")
        XCTAssertGreaterThan(AgentJumpToBottom.appearDistance,
                             AgentJumpToBottom.reservedHeight(visible: false),
                             "出现门槛必须严格大于隐藏态占位（0pt）")
    }
}
