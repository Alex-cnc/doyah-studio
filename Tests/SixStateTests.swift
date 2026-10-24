import XCTest
@testable import DoyahCore

/// 详设 §5.3 六态（概设 §8.4 / 用例 `UI-5.3-01`）：六态齐、优先级固定、禁渲染项可判。
final class SixStateTests: XCTestCase {

    func testClosedSetHasExactlySixStates() {
        XCTAssertEqual(
            ViewState.closedSet,
            ["empty", "error", "loading", "partialFailure", "permissionDenied", "submitting"],
            "六态是闭集：多一个或少一个都要先改概设 §8.4"
        )
    }

    func testEachStateIsReachable() {
        XCTAssertEqual(ViewStatePolicy.decide(missingCapability: "cloudSync"), .permissionDenied)
        XCTAssertEqual(ViewStatePolicy.decide(isSubmitting: true), .submitting)
        XCTAssertEqual(ViewStatePolicy.decide(isLoading: true), .loading)
        XCTAssertEqual(ViewStatePolicy.decide(errorMessage: "连接超时"), .error)
        XCTAssertEqual(ViewStatePolicy.decide(partialFailure: (failed: 2, succeeded: 5)), .partialFailure)
        XCTAssertEqual(ViewStatePolicy.decide(hasData: false), .empty)
        XCTAssertNil(ViewStatePolicy.decide(hasData: true), "有数据且无异常 ⇒ 正常内容态，不属于六态")
    }

    func testPriorityIsFixed() {
        // 权限不足压过一切：缺位时不许先显示「加载中」或错误
        XCTAssertEqual(
            ViewStatePolicy.decide(missingCapability: "cloudSync", isSubmitting: true, errorMessage: "x"),
            .permissionDenied
        )
        // 提交中压过错误
        XCTAssertEqual(
            ViewStatePolicy.decide(isSubmitting: true, errorMessage: "上次失败"),
            .submitting
        )
        // 错误压过空态：有错误 + 无数据，显示错误而不是「空数据」
        XCTAssertEqual(
            ViewStatePolicy.decide(errorMessage: "无权限读取", hasData: false),
            .error
        )
    }

    func testForbiddenCompanionsAreDeclared() {
        XCTAssertTrue(ViewStatePolicy.forbiddenCompanions(for: .error).contains("emptyStateCopy"),
                      "错误态不许同时渲染「没有数据」的文案")
        XCTAssertTrue(ViewStatePolicy.forbiddenCompanions(for: .permissionDenied).contains("contentPreview"),
                      "权限不足不许先给内容预览（灰色诱导）")
        XCTAssertTrue(ViewStatePolicy.forbiddenCompanions(for: .loading).isEmpty)
    }
}
