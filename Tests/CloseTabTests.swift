import XCTest
@testable import DoyahCore

/// 详设 `T-4.4-07`：执行中关闭页签 ⇒ 被拒并给理由（不是静默 return）。
final class CloseTabTests: XCTestCase {

    func testExecutingTabIsRefusedNotSilentlyIgnored() {
        XCTAssertEqual(
            TabClosePolicy.decide(isExecuting: true, isDirty: false, tabCount: 3),
            .refuseExecuting,
            "执行中必须给出「拒绝 + 理由」，不许静默 return"
        )
        // 脏 + 执行中：仍先拒绝关闭（停止优先于保存询问）
        XCTAssertEqual(
            TabClosePolicy.decide(isExecuting: true, isDirty: true, tabCount: 3),
            .refuseExecuting
        )
    }

    func testLastTabIsRefusedEvenIfDirty() {
        XCTAssertEqual(TabClosePolicy.decide(isExecuting: false, isDirty: true, tabCount: 1), .refuseLastTab)
        XCTAssertEqual(TabClosePolicy.decide(isExecuting: true, isDirty: false, tabCount: 1), .refuseLastTab,
                       "只剩一个页签时，拒绝理由优先说「不能关最后一个」，而不是「正在执行」")
    }

    func testCleanIdleTabCloses() {
        XCTAssertEqual(TabClosePolicy.decide(isExecuting: false, isDirty: false, tabCount: 2), .close)
    }

    func testDirtyTabNeedsConfirmation() {
        XCTAssertEqual(TabClosePolicy.decide(isExecuting: false, isDirty: true, tabCount: 2), .needsConfirmation)
    }
}
