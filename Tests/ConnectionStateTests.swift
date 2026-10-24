import XCTest
@testable import DoyahCore

/// 概设 §6.1 连接状态机（详设 §4.4 第一台）。
/// 详设 §9.2 缺口 T-4.4-01（正例）/ T-4.4-02（反例）在本文件补齐。
final class ConnectionStateTests: XCTestCase {

    // MARK: - 正例：未连接 → 连接中 → 已连接

    func testHappyPathTransitions() {
        var state = ConnectionState.idle
        for next in [ConnectionState.connecting, .connected] {
            let moved = state.transition(to: next)
            XCTAssertNotNil(moved, "\(state.rawValue) → \(next.rawValue) 必须合法")
            state = moved ?? state
        }
        XCTAssertEqual(state, .connected)

        // 连上之后可以断开，也可以因故障掉线
        XCTAssertNotNil(state.transition(to: .disconnected))
        XCTAssertNotNil(state.transition(to: .failed))
    }

    // MARK: - 反例：失败不可直跳已连接

    func testFailedCannotJumpToConnected() {
        XCTAssertFalse(ConnectionState.failed.canTransition(to: .connected),
                       "失败态必须重新经过 connecting —— 否则「重试」会把旧失败悄悄改成成功")
        XCTAssertNil(ConnectionState.failed.transition(to: .connected))
        // 但重试路径本身要通
        XCTAssertNotNil(ConnectionState.failed.transition(to: .connecting))
    }

    func testIdleCannotJumpToConnectedOrDisconnected() {
        XCTAssertFalse(ConnectionState.idle.canTransition(to: .connected))
        XCTAssertFalse(ConnectionState.idle.canTransition(to: .disconnected))
        XCTAssertFalse(ConnectionState.idle.canTransition(to: .failed))
    }

    // MARK: - 闭集

    func testClosedSetHasNoExtraStates() {
        XCTAssertEqual(
            ConnectionState.closedSet,
            ["connected", "connecting", "disconnected", "failed", "idle"],
            "状态是闭集：多一个或少一个都要先改概设 §6.1"
        )
        // 每个状态都在流转表里，不许有「没登记的孤儿状态」
        for state in ConnectionState.allCases {
            XCTAssertNotNil(ConnectionState.allowedTransitions[state],
                            "\(state.rawValue) 没在流转表里登记")
        }
    }
}
