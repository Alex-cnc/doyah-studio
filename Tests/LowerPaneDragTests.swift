import XCTest
@testable import DoyahCore

/// `FR-STD-WS-TOOL-001` 的**拖动过程判据**（2026-11-03 真机点验：「拖分隔条时明显闪烁」）。
///
/// 要守的那条纪律只有一句：**拖动中只动临时值，模型与磁盘只在松手那一下碰一次**。
/// 60–120 帧/秒的 `onChanged` 里每帧写 `@Published`（`AppState.lowerPaneHeight`，`didSet` 还落盘）
/// ⇒ 整个窗口里所有观察 `AppState` 的视图每帧重算一遍，看上去就是闪。
///
/// 这里判的是 `LowerPaneDragSession` 这一层的口径（纯逻辑）：
/// ① 每一帧都给一个临时高度（拖动要连续）；② 只有 `end()` 给落点，且**只有一次**；
/// ③ 起点只认按下那一刻（否则越拖越跳）；④ 拖过下限停在最小高度、**松手才折叠**。
final class LowerPaneDragTests: XCTestCase {

    /// 60 帧连续拖动：帧帧有新高度，但**落点只有一个**，且等于最后一帧看到的那个。
    func testManyFramesYieldExactlyOneLandingSpot() {
        var session = LowerPaneDragSession()
        var seen: [CGFloat] = []
        for frame in 1...60 {
            let live = session.update(height: 200,
                                      translation: -CGFloat(frame) * 2,
                                      available: 900)
            if let live { seen.append(live) }
        }
        XCTAssertEqual(session.frames, 60, "每一帧都要过账（拖动是连续的，不能跳帧）")
        XCTAssertEqual(Set(seen).count, 60, "每一帧的高度都要跟着走：\(seen)")

        guard case let .commit(next) = session.end() else {
            return XCTFail("松手必须给一个落点 —— 不给落点就是把用户拖的高度丢了")
        }
        XCTAssertEqual(next, seen.last, "落点必须等于松手那一刻屏幕上显示的高度（松手不跳）")
        XCTAssertEqual(session.end(), .none, "同一场只落一次：再 end 一次不许再给落点（落盘只许一次）")
        XCTAssertNil(session.live, "收场之后临时值要清掉，否则下一场会拿旧值当起点")
    }

    /// 起点只认按下那一刻 —— 拖到一半即便有人把「当前高度」读成别的值，结果也不许跟着跳。
    func testTheStartHeightIsCapturedOnce() {
        var session = LowerPaneDragSession()
        _ = session.update(height: 200, translation: 0, available: 900)
        let later = session.update(height: 500, translation: -10, available: 900)
        XCTAssertEqual(later, 210, "起点是 200（按下那一刻），不是后来读到的 500 —— 否则拖动会跳")
    }

    /// 拖过下限：面板停在最小高度（看得见「再往下就是收起」），**松手才折叠**。
    func testDraggingPastTheFloorStopsAtTheMinimumAndCollapsesOnRelease() {
        var session = LowerPaneDragSession()
        _ = session.update(height: 120, translation: 0, available: 900)
        let live = session.update(height: 120, translation: 100, available: 900)   // raw = 20 < 90
        XCTAssertEqual(live, LowerPaneSizing.draggableMinHeight, "拖过下限时面板停在最小高度，不许塌成 0")
        XCTAssertTrue(session.pendingCollapse, "松手要折叠")
        XCTAssertEqual(session.end(), .collapse, "折叠只在松手时发生一次（拖动中折叠会让子树反复拆建）")
    }

    /// 拖过下限又拖回来 ⇒ 折叠作废，落点按最后的高度。
    func testDraggingBackUpCancelsTheCollapse() {
        var session = LowerPaneDragSession()
        _ = session.update(height: 120, translation: 0, available: 900)
        _ = session.update(height: 120, translation: 100, available: 900)
        XCTAssertTrue(session.pendingCollapse)
        let back = session.update(height: 120, translation: -60, available: 900)   // raw = 180
        XCTAssertEqual(back, 180)
        XCTAssertFalse(session.pendingCollapse, "拖回来就不该再折叠")
        XCTAssertEqual(session.end(), .commit(180))
    }

    /// 只点一下没位移 ⇒ 什么都不改（不许把面板高度写成一个奇怪的值）。
    func testAClickWithoutMovementLandsNowhere() {
        var session = LowerPaneDragSession()
        XCTAssertEqual(session.end(), .none)
        XCTAssertNil(session.live)
    }

    /// 上限按可用高度夹（`LowerPaneSizing.maxHeightRatio`），拖动中就要夹住 —— 不许先撑满再回弹。
    func testLiveHeightIsClampedWhileDragging() {
        var session = LowerPaneDragSession()
        let live = session.update(height: 200, translation: -5000, available: 800)
        XCTAssertEqual(live, 600, "800 × 0.75 = 600：拖动中就该停在 600，不能先冲出去再回弹")
    }
}
