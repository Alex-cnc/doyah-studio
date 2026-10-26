import XCTest
@testable import DoyahCore

/// `/steer`（插话纠偏）与 `/queue`（本轮后排发）—— `FR-AGT-UX-CONV-007` 的斜杠入口。
///
/// 判据重心：**两条都不许进模型、不许改配置、必须带参数**；审计行必须单行且带参数原文。
final class AgentSlashSteerQueueTests: XCTestCase {

    private let parser = AgentSlashCommandParser()
    private let runtime = AgentSlashCommandRuntime()

    // 解析：带参数照样认得出，参数原文（含空格）完整保留
    func testSteerParsesWithArgument() {
        guard case let .parsed(kind, argument) = parser.parse("/steer 先别动 Vendor/ 目录") else {
            return XCTFail("应当解析成 /steer")
        }
        XCTAssertEqual(kind, .steer)
        XCTAssertEqual(argument, "先别动 Vendor/ 目录")
    }

    func testQueueParsesWithArgument() {
        guard case let .parsed(kind, argument) = parser.parse("/queue 跑完把结果贴给我") else {
            return XCTFail("应当解析成 /queue")
        }
        XCTAssertEqual(kind, .queue)
        XCTAssertEqual(argument, "跑完把结果贴给我")
    }

    // 缺参数：如实报缺，不拿默认值顶
    func testBothRequireArgument() {
        XCTAssertEqual(parser.parse("/steer"), .missingArgument(kind: .steer))
        XCTAssertEqual(parser.parse("/queue"), .missingArgument(kind: .queue))
    }

    // 大写也认（与其余命令同一套大小写不敏感）
    func testCaseInsensitive() {
        guard case let .parsed(kind, _) = parser.parse("/STEER 慢点") else { return XCTFail("大写应认") }
        XCTAssertEqual(kind, .steer)
    }

    // 落地形状：steerRun / queuePrompt，都不是 configChange
    func testRuntimeEffects() {
        XCTAssertEqual(runtime.plan("/steer 换个思路"), .steerRun(instruction: "换个思路"))
        XCTAssertEqual(runtime.plan("/queue 下一件事"), .queuePrompt(text: "下一件事"))
    }

    // 两条都不改配置、都算「真做了一件本地事」
    func testNeitherMutatesConfigurationAndBothPerformedLocally() {
        for raw in ["/steer 换个思路", "/queue 下一件事"] {
            guard let effect = runtime.plan(raw) else { return XCTFail("\(raw) 没有 effect") }
            XCTAssertFalse(effect.mutatesConfiguration, "\(raw) 不许碰持久配置")
            XCTAssertTrue(effect.performedLocally, "\(raw) 是本地动作")
        }
    }

    // 审计行：单行、带参数、不带正文换行
    func testAuditLineIsSingleLine() {
        guard let effect = runtime.plan("/steer 第一行\n第二行") else { return XCTFail("没有 effect") }
        XCTAssertFalse(effect.auditLine.contains("\n"), "审计行必须单行")
        XCTAssertTrue(effect.auditLine.hasPrefix("slash /steer"))
        XCTAssertTrue(effect.auditLine.contains("第一行 第二行"))
    }

    // 候选提示：两条都出现在清单里，且插字带尾随空格（要参数）
    func testCompleterListsBothWithTrailingSpace() {
        let completer = AgentSlashCompleter()
        let all = completer.suggestions(for: "/", limit: 20)
        XCTAssertTrue(all.contains { $0.kind == .steer }, "候选里要有 /steer")
        XCTAssertTrue(all.contains { $0.kind == .queue }, "候选里要有 /queue")
        XCTAssertEqual(completer.suggestions(for: "/ste").first?.insertion, "/steer ")
        XCTAssertEqual(completer.suggestions(for: "/qu").first?.insertion, "/queue ")
    }

    // 帮助清单里两条都列了（清单是唯一真源，界面不另抄）
    func testHelpTextMentionsBoth() {
        let help = parser.helpText.joined(separator: "\n")
        XCTAssertTrue(help.contains("/steer"))
        XCTAssertTrue(help.contains("/queue"))
    }
}
