import XCTest
@testable import DoyahCore

/// 详设 §3.23 的三条用例：`T-3.23-01`（真实结束恰好一次）· `T-3.23-02`（钩子抛错不中断会话）·
/// `T-3.23-03`（回合内调 end 被拒）。外加「引擎未注册如实报」一条。
final class AgentContextEngineTests: XCTestCase {

    /// 记账引擎：每次钩子调用 +1，`throwOn` 指定哪个钩子抛错。
    private final class RecordingEngine: AgentContextEngine, @unchecked Sendable {
        var starts = 0
        var updates = 0
        var ends = 0
        var throwOn: String?
        var endOutcome: AgentHookOutcome = .ok

        func onSessionStart() throws -> AgentHookOutcome {
            starts += 1
            if throwOn == "start" { throw NSError(domain: "t", code: 1) }
            return .ok
        }

        func updateFromResponse(_ text: String) throws -> AgentHookOutcome {
            updates += 1
            return .ok
        }

        func shouldCompress() throws -> AgentHookOutcome { .ok }

        func compress() throws -> AgentHookOutcome { .ok }

        func onSessionEnd() throws -> AgentHookOutcome {
            ends += 1
            if throwOn == "end" { throw NSError(domain: "t", code: 2) }
            return endOutcome
        }
    }

    // MARK: T-3.23-01 真实结束恰好一次

    func testSessionEndFiresExactlyOnce() {
        let engine = RecordingEngine()
        var host = AgentContextEngineHost(sessionID: "S1", engine: engine)
        host.startSession()
        host.update("hi")
        XCTAssertEqual(engine.ends, 0, "会话还没结束，不许触发 onSessionEnd")

        _ = host.endSession(at: .cliExit)
        XCTAssertEqual(engine.ends, 1)
        // 网关过期与 CLI 退出同时到：幂等，不再触发
        _ = host.endSession(at: .gatewayExpiry)
        _ = host.endSession(at: .sessionReset)
        XCTAssertEqual(engine.ends, 1)
        XCTAssertEqual(host.callCount(of: .onSessionEnd), 1)
        XCTAssertEqual(host.log.last?.boundaryKind, .cliExit, "boundaryKind 记首次那一回的")
    }

    // MARK: T-3.23-02 钩子抛错不中断会话

    func testHookThrowIsDegradedNotFatal() {
        let engine = RecordingEngine()
        engine.throwOn = "start"
        var host = AgentContextEngineHost(sessionID: "S2", engine: engine)
        let outcome = host.startSession()
        XCTAssertTrue(outcome.isFailure)
        XCTAssertEqual(outcome, .failed(code: "thrown"))
        // 会话继续：后续钩子照跑
        XCTAssertEqual(host.update("still alive"), .ok)
        XCTAssertEqual(engine.updates, 1)
    }

    func testEndHookThrowStillReturnsOutcomeAndKeepsSessionUsable() {
        let engine = RecordingEngine()
        engine.throwOn = "end"
        var host = AgentContextEngineHost(sessionID: "S3", engine: engine)
        let result = host.endSession(at: .sessionReset)
        XCTAssertEqual(try? result.get(), .failed(code: "thrown"))
        XCTAssertEqual(engine.ends, 1)
    }

    // MARK: T-3.23-03 回合内调 end 被拒

    func testEndInTurnIsRefused() {
        let engine = RecordingEngine()
        var host = AgentContextEngineHost(sessionID: "S4", engine: engine)
        let result = host.endSession(at: .cliExit, sessionOpen: false)
        XCTAssertEqual(result, .failure(.notASessionBoundary))
        XCTAssertEqual(engine.ends, 0, "边界判定权在会话层，回合内不许触发引擎")
        XCTAssertEqual(host.callCount(of: .onSessionEnd), 0)
        // 拒绝之后真实结束时仍要触发一次
        _ = host.endSession(at: .cliExit)
        XCTAssertEqual(engine.ends, 1)
    }

    // MARK: 引擎未注册

    func testNoEngineIsReportedHonestly() {
        var host = AgentContextEngineHost(sessionID: "S5", engine: nil)
        XCTAssertEqual(host.startSession(), .skipped(reason: "noEngine"))
        XCTAssertEqual(host.compress(), .skipped(reason: "noEngine"))
        let end = host.endSession(at: .gatewayExpiry)
        XCTAssertEqual(try? end.get(), .skipped(reason: "noEngine"))
    }

    func testHookSetIsClosedAtFive() {
        XCTAssertEqual(AgentContextHook.allCases.count, 5)
        XCTAssertEqual(AgentContextHook.allCases.map(\.rawValue),
                       ["onSessionStart", "updateFromResponse", "shouldCompress", "compress", "onSessionEnd"])
    }
}
