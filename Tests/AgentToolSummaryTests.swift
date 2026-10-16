import XCTest
@testable import DoyahCore

/// 过程行摘要器（`AgentToolSummary`）的判据。
///
/// 由头：人类主人 2026-10-17 给了 Hermes CLI 的过程输出样板（`$ echo "..." + 10 commands 0.3s`、
/// `read pnpm-workspace.yaml 0.0s`）⇒ 我们那行也要能一眼看出「跑了什么、花了多久」。
final class AgentToolSummaryTests: XCTestCase {

    /// 白名单字段**按序**取第一个命中的（一次调用里最像"目标"的那个）。
    func testWhitelistedKeysArePickedInOrder() {
        XCTAssertEqual(AgentToolSummary.line(fromArgumentsJSON: #"{"command":"ls -la"}"#), "ls -la")
        XCTAssertEqual(AgentToolSummary.line(fromArgumentsJSON: #"{"sql":"select 1"}"#), "select 1")
        XCTAssertEqual(AgentToolSummary.line(fromArgumentsJSON: #"{"path":"Core/AgentLoop.swift"}"#),
                       "Core/AgentLoop.swift")
        XCTAssertEqual(AgentToolSummary.line(fromArgumentsJSON: #"{"pattern":"TODO","path":"a.md"}"#), "TODO",
                       "命令 / SQL 类在前，路径在后 —— 顺序是判据的一部分")
    }

    /// 没有白名单字段 ⇒ **压平 + 截断**，绝不把多行 JSON 塞进过程行。
    func testFallsBackToFlattenedTruncatedJSON() {
        let line = AgentToolSummary.line(fromArgumentsJSON: #"{"a":1,"b":"x\ny"}"#, limit: 10)
        XCTAssertFalse(line.contains("\n"), "过程行是一行：换行必须压掉")
        XCTAssertLessThanOrEqual(line.count, 11, "超长要截断（含省略号）")
        XCTAssertTrue(line.hasSuffix("…"))

        XCTAssertEqual(AgentToolSummary.line(fromArgumentsJSON: "   "), "", "空参数 ⇒ 空摘要（不编）")
        XCTAssertEqual(AgentToolSummary.line(fromArgumentsJSON: "{}"), "", "空对象 ⇒ 空摘要（不编）")
    }

    /// 耗时后缀：**没真跑的那一步不报耗时**（不许出现假的 `0.0s`）。
    func testDurationSuffixOnlyWhenMeasured() {
        XCTAssertEqual(AgentChatState.durationSuffix(320), " · 0.3s")
        XCTAssertEqual(AgentChatState.durationSuffix(15), " · 0.0s")
        XCTAssertEqual(AgentChatState.durationSuffix(nil), "", "当场被拒的（未登记 / 参数不合规）不报耗时")
    }
}
