import XCTest
@testable import DoyahCore

/// **超时之后的心跳**（2026-11-11 真机：「跑到这里就没了：This turn has been running for
/// 2m 40s and is still going… I will send the result when it lands」）。
///
/// 那句话承诺了「会接着报进度」，实际说完就再没动静 —— 一轮 40 分钟，手机那头 40 分钟死寂。
/// 判据四条（每条都配会判红的负例）：
/// ① 还在跑 ⇒ 到点就报（默认 6 分钟后第一条，之后每 5 分钟）；
/// ② 跑完了 ⇒ **一条都不许再报**（结论那条说话）；
/// ③ 封顶 6 条（跑一整夜也不刷屏）；
/// ④ 超时那一刻刚报过，6 分钟内不许重复。
final class AgentIMHeartbeatTests: XCTestCase {

    func testFirstHeartbeatAfterSixMinutes() {
        let policy = AgentIMHeartbeatPolicy()
        XCTAssertFalse(policy.shouldSend(sent: 0, elapsed: 300, isRunning: true),
                       "超时刚报过（2m40s），5 分钟时不许再来一条")
        XCTAssertTrue(policy.shouldSend(sent: 0, elapsed: 360, isRunning: true),
                      "到 6 分钟该吭一声：它还在跑")
    }

    func testSubsequentHeartbeatsAreFiveMinutesApart() {
        let policy = AgentIMHeartbeatPolicy()
        XCTAssertFalse(policy.shouldSend(sent: 1, elapsed: 600, isRunning: true),
                       "第一条在 6 分钟，第二条要等到 11 分钟")
        XCTAssertTrue(policy.shouldSend(sent: 1, elapsed: 660, isRunning: true))
    }

    func testStopsImmediatelyWhenTheRunEnds() {
        let policy = AgentIMHeartbeatPolicy()
        XCTAssertFalse(policy.shouldSend(sent: 2, elapsed: 9_999, isRunning: false),
                       "跑完了还发心跳 = 结论后面拖一条废话")
    }

    func testCapsAtSixPushes() {
        let policy = AgentIMHeartbeatPolicy()
        XCTAssertFalse(policy.shouldSend(sent: 6, elapsed: 99_999, isRunning: true),
                       "封顶 6 条：跑一整夜也不许刷屏")
    }

    func testHeartbeatLineNamesMinutesAndStep() {
        let text = LocalizedStrings.format(.agentIMHeartbeat, language: .simplifiedChinese,
                                           Int64(17), Int64(23))
        XCTAssertTrue(text.contains("17 分钟"), "要说清跑了多久：\(text)")
        XCTAssertTrue(text.contains("第 23 步"), "要说清走到哪儿了：\(text)")
    }
}
