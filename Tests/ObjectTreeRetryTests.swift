import XCTest
@testable import DoyahCore

/// 失败那一行的**重试判定**（`FR-STD-DB-META-006` ③「加载失败在该节点给可读错误并可重试」）。
///
/// 判据要钉的是「什么时候出、出了做什么、什么时候**不**出」三件事：
/// 出错了才出（空态旁边摆一枚重试会把正常状态读成故障）· 在途时不重复取数
/// （两发抢着落地 = 界面上是哪一份要碰运气）· 重试先清旧错误再取数
/// （反过来的话，点击到落地之间那一行还是上一轮的红字，用户以为没生效）。
final class ObjectTreeRetryTests: XCTestCase {

    private let failedRowInput = (nodeID: "db:doyah_manual_test", isExpanded: true, isLoading: false)

    // MARK: - 该出的时候

    /// 失败 + 展开 + 不在途 + 没缓存 ⇒ 出，且计划就是那两步。
    func testOffersRetryForAFailedExpandedNode() {
        let outcome = ObjectTreeRetry.evaluate(
            nodeID: failedRowInput.nodeID,
            isExpanded: true,
            isLoading: false,
            cachedCount: nil,
            error: "连不上 database \"doyah_manual_test\"：认证失败（28P01）"
        )
        XCTAssertTrue(outcome.affordsRetry, "失败且可重试的节点必须给入口")
        let plan = outcome.plan
        XCTAssertEqual(plan?.nodeID, failedRowInput.nodeID, "计划必须带上是哪一行 —— 视图据此核对「点的是这一行」")
    }

    /// **顺序口径**：先清旧错误，再取数。
    ///
    /// 反例就是「先取数」：从点击到结果落地之间那一行仍写着上一轮的失败原因，
    /// 而界面上没有任何「正在重试」的迹象 —— 用户能看见的唯一变化就是没有变化。
    func testClearsTheStaleErrorBeforeLoading() {
        let plan = ObjectTreeRetry.evaluate(
            nodeID: "tbl:public.orders",
            isExpanded: true,
            isLoading: false,
            cachedCount: nil,
            error: "该节点加载失败"
        ).plan
        XCTAssertEqual(plan?.steps, [.clearError, .loadChildren])
    }

    /// 重试只做这两件事：**不折叠、不清缓存、不改展开集合** —— 把「重试」实现成
    /// 「收起来再展开」会让树跳一下，而且用户看到的是同一个自己没做的动作。
    func testRetryDoesNotCollapseTheNode() {
        let plan = ObjectTreeRetry.evaluate(
            nodeID: "sch:public",
            isExpanded: true,
            isLoading: false,
            cachedCount: nil,
            error: "读取 schema 失败"
        ).plan
        XCTAssertEqual(plan?.steps.count, 2, "计划里只有「清错误」与「取数」两步")
        XCTAssertEqual(plan?.steps.contains(.clearError), true, "清错误必须在计划里")
    }

    // MARK: - 不该出的时候（每条都对应一种「出了会更糟」）

    /// 没失败（空态 / 正常态）⇒ 不出：在「该库下暂无表 / 视图」旁边摆一枚「重试」，
    /// 用户会把正常状态读成「刚才出错了」。
    func testDoesNotOfferRetryWithoutAFailure() {
        let outcome = ObjectTreeRetry.evaluate(
            nodeID: "db:empty_db",
            isExpanded: true,
            isLoading: false,
            cachedCount: 0,
            error: nil
        )
        XCTAssertFalse(outcome.affordsRetry)
        XCTAssertEqual(outcome, .skip(.noFailure))
    }

    /// 空白文案也不算失败（`ErrorPresenter` 不该给出空串，但界面不能因此摆一枚空按钮）。
    func testBlankErrorCountsAsNoFailure() {
        let outcome = ObjectTreeRetry.evaluate(
            nodeID: "db:x",
            isExpanded: true,
            isLoading: false,
            cachedCount: nil,
            error: "  \n\t "
        )
        XCTAssertEqual(outcome, .skip(.noFailure))
    }

    /// 收起时不出：入口画在展开后的那一行下面，收起时那一行根本没画出来。
    func testDoesNotOfferRetryWhileCollapsed() {
        let outcome = ObjectTreeRetry.evaluate(
            nodeID: "db:x",
            isExpanded: false,
            isLoading: false,
            cachedCount: nil,
            error: "认证失败"
        )
        XCTAssertEqual(outcome, .skip(.notExpanded))
    }

    /// **在途时不出**（单飞）：再点一次就是第二次取数，两发谁后落地谁说了算。
    /// 根节点刷新踩过同族的坑（`ObjectTreeRefreshGate` / 队列 `L-96`），节点这一层此前没有闸门。
    func testDoesNotOfferRetryWhileLoading() {
        let outcome = ObjectTreeRetry.evaluate(
            nodeID: "db:x",
            isExpanded: true,
            isLoading: true,
            cachedCount: nil,
            error: "认证失败"
        )
        XCTAssertEqual(outcome, .skip(.inFlight))
    }

    /// 在途优先于别的状态：即使同时有错误、有缓存，也只报「在途」（不许出入口）。
    func testInFlightWinsOverEveryOtherState() {
        let outcome = ObjectTreeRetry.evaluate(
            nodeID: "db:x",
            isExpanded: false,
            isLoading: true,
            cachedCount: 3,
            error: "认证失败"
        )
        XCTAssertEqual(outcome, .skip(.inFlight))
        XCTAssertFalse(outcome.affordsRetry)
    }

    /// 子节点已经在缓存里（这一次是成功的）⇒ 不出：残留的错误不该换来一枚重试。
    /// 注意 `cachedCount: 0`（加载过、但没有子节点）**也是**「已经有结果」—— 与 `nil` 不是一回事。
    func testDoesNotOfferRetryWhenChildrenAreAlreadyLoaded() {
        let loadedEmpty = ObjectTreeRetry.evaluate(
            nodeID: "db:x",
            isExpanded: true,
            isLoading: false,
            cachedCount: 0,
            error: "上一轮的旧错误"
        )
        XCTAssertEqual(loadedEmpty, .skip(.alreadyLoaded))

        let stillNothing = ObjectTreeRetry.evaluate(
            nodeID: "db:x",
            isExpanded: true,
            isLoading: false,
            cachedCount: nil,
            error: "这一轮的失败"
        )
        XCTAssertEqual(stillNothing.plan?.steps, [.clearError, .loadChildren], "`nil` = 从没加载过 ⇒ 该重试")
    }

    // MARK: - 确定性 / 不封印

    /// 同一份输入两遍必须给出同一份判定（界面会在每次重算时问一次，判定漂移就等于按钮闪烁）。
    func testEvaluationIsDeterministic() {
        let first = ObjectTreeRetry.evaluate(
            nodeID: "db:x", isExpanded: true, isLoading: false, cachedCount: nil, error: "失败"
        )
        let second = ObjectTreeRetry.evaluate(
            nodeID: "db:x", isExpanded: true, isLoading: false, cachedCount: nil, error: "失败"
        )
        XCTAssertEqual(first, second)
    }

    /// 这一发结束（在途解除）之后仍然可以再试 —— **不许**把一次重试变成永久封印。
    func testRetryIsAvailableAgainOnceTheLoadSettles() {
        let during = ObjectTreeRetry.evaluate(
            nodeID: "db:x", isExpanded: true, isLoading: true, cachedCount: nil, error: "失败"
        )
        let after = ObjectTreeRetry.evaluate(
            nodeID: "db:x", isExpanded: true, isLoading: false, cachedCount: nil, error: "失败"
        )
        XCTAssertEqual(during, .skip(.inFlight))
        XCTAssertTrue(after.affordsRetry, "在途结束后必须还能再试")
    }
}
