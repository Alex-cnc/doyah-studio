import XCTest
@testable import DoyahCore

/// 详设 §6 `SESS_KILL_DENIED`（概设 §4.9：终止需二次确认并说明后果）。
final class SessionKillTests: XCTestCase {

    func testDeniedCarriesServerReason() {
        let decision = SessionKillGuard.decide(
            isOwnSession: false, confirmed: true, canTerminate: false,
            serverReason: "must be superuser to terminate other sessions"
        )
        XCTAssertEqual(decision, .denied(reason: "must be superuser to terminate other sessions"))
        XCTAssertEqual(SessionKillGuard.errorCode(for: decision), "SESS_KILL_DENIED")
    }

    func testUnconfirmedIsRefused() {
        XCTAssertEqual(
            SessionKillGuard.decide(isOwnSession: false, confirmed: false, canTerminate: true),
            .confirmationRequired
        )
    }

    func testOwnSessionCannotBeKilled() {
        XCTAssertEqual(
            SessionKillGuard.decide(isOwnSession: true, confirmed: true, canTerminate: true),
            .selfSessionRefused,
            "终止自己的会话会让界面那条连接立刻自断"
        )
    }

    func testAllowedPath() {
        XCTAssertEqual(
            SessionKillGuard.decide(isOwnSession: false, confirmed: true, canTerminate: true),
            .allowed
        )
    }
}
