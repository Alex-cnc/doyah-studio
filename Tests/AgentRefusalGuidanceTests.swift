import XCTest
@testable import DoyahCore

/// **被拒之后给出路**（2026-11-11 打转复盘）。
///
/// 现场（一轮 56 跳 / 279 条审计）：
/// · 37 次被拒，全是同几种写法 —— `;` `>` `&` `bash`、`./Scripts/verify-all.sh`
/// · 8 次 `exit:124` 超时
/// · 回灌给模型的只有 `run_command => commandNotAllowed`：**detail 被丢掉，也没有一句改法**
///
/// 所以它不是「笨」，是**拿不到任何可用的负反馈**——只能把同一件事换个拼法再试。
/// 判据：每种被拒形态都要翻成一句「下一步照这么做」，且升级提醒要真的逐级加重。
final class AgentRefusalGuidanceTests: XCTestCase {

    func testSemicolonTellsItToSplitIntoCalls() {
        let text = AgentRefusalGuidance.message(detail: "control-character:;")
        XCTAssertTrue(text.contains("一条"), "要说清一次只能一条：\(text)")
        XCTAssertTrue(text.contains("拆成多次"), "要给出路：\(text)")
    }

    func testRedirectionPointsAtWriteFile() {
        let text = AgentRefusalGuidance.message(detail: "control-character:>")
        XCTAssertTrue(text.contains("write_file"), "重定向的出路是 write_file：\(text)")
    }

    func testPipeAndDollarGetTheirOwnAdvice() {
        XCTAssertTrue(AgentRefusalGuidance.message(detail: "control-character:|").contains("grep"))
        XCTAssertTrue(AgentRefusalGuidance.message(detail: "control-character:$").contains("变量"))
    }

    func testPathExecutableIsToldToUseAnInterpreter() {
        let text = AgentRefusalGuidance.message(detail: "executable-is-a-path:./Scripts/verify-all.sh")
        XCTAssertTrue(text.contains("python3"), "脚本要走解释器：\(text)")
        XCTAssertTrue(text.contains("verify-all.sh"), "要点名被拒的那一个：\(text)")
    }

    func testUnknownExecutableListsTheWhitelist() {
        let text = AgentRefusalGuidance.message(detail: "bash", allowed: ["git", "python3", "swift"])
        XCTAssertTrue(text.contains("bash"), "要点名被拒的命令：\(text)")
        XCTAssertTrue(text.contains("git"), "要把白名单亮出来：\(text)")
    }

    func testTooManyArgumentsIsActionable() {
        let text = AgentRefusalGuidance.message(detail: "too-many-arguments:40")
        XCTAssertTrue(text.contains("40"), "要带上是多少个：\(text)")
        XCTAssertTrue(text.contains("拆"), "要给出路：\(text)")
    }

    // MARK: - 连拒升级（光给改法不够：观察到的行为是看完又试同一句）

    func testFirstRefusalHasNoLecture() {
        XCTAssertNil(AgentRefusalGuidance.escalation(streak: 1), "第一次别唠叨，直接给改法")
    }

    func testSecondThenThirdRefusalEscalate() {
        let second = AgentRefusalGuidance.escalation(streak: 2) ?? ""
        let third = AgentRefusalGuidance.escalation(streak: 3) ?? ""
        XCTAssertTrue(second.contains("第二次"), "第二次要提醒：\(second)")
        XCTAssertTrue(third.contains("不要再试"), "第三次要明说别再试：\(third)")
        XCTAssertNotEqual(second, third, "升级必须逐级加重，不许两档同一句")
    }
}
