import XCTest
import DoyahCore
@testable import DoyahStudioApp

/// 对话页签**版式语汇**的判据（详设 `§5.3.8.1` ②④）。
///
/// 量的是两件最容易写歪、又最容易「看起来差不多」的事：
///   · 过程行 → `⏺ <工具名>("<参数摘要>") (<耗时>s)` 这一行的拆解（**认不出就 `nil`**，不许猜）；
///   · 状态行的**字段顺序**与「没读数整段不出现」。
final class AgentChatChromeTests: XCTestCase {

    // MARK: 过程行 → 工具条目

    /// 跑完的一条：名字 / 参数摘要 / 耗时 / 成功 —— 四段都在。
    func testFinishedToolLineSplitsIntoFourParts() {
        guard let line = AgentToolLines.parse("▸ read_file · Core/MarkdownDocument.swift  ✓ · 0.5s") else {
            return XCTFail("本进程自己的过程行必须认得出来")
        }
        XCTAssertEqual(line.name, "read_file")
        XCTAssertEqual(line.summary, "Core/MarkdownDocument.swift")
        XCTAssertEqual(line.elapsed, "0.5s")
        XCTAssertEqual(line.outcome, .success)
        XCTAssertEqual(AgentToolLines.callText(line), "read_file(\"Core/MarkdownDocument.swift\") (0.5s)")
    }

    /// 还在跑：没有标记、没有耗时 —— 不许编一个 `0.0s`。
    func testRunningToolLineHasNoElapsed() {
        guard let line = AgentToolLines.parse("▸ search · 关键词 foo") else { return XCTFail("跑着的行也要认得出") }
        XCTAssertEqual(line.outcome, .running)
        XCTAssertNil(line.elapsed)
        XCTAssertEqual(AgentToolLines.callText(line), "search(\"关键词 foo\")")
    }

    /// 被拒：原因原样留在条目上（界面按需翻人话，这里不吞）。
    func testDeniedToolLineKeepsReason() {
        guard let line = AgentToolLines.parse("▸ write_file · a.md  ✗ denied:writeConflict · 1.2s") else {
            return XCTFail("被拒的行必须认得出")
        }
        XCTAssertEqual(line.elapsed, "1.2s")
        XCTAssertEqual(line.outcome, .failure("denied:writeConflict"))
        XCTAssertEqual(AgentToolLines.callText(line), "write_file(\"a.md\") (1.2s)")
    }

    /// 没有参数摘要：`name()`（不画一对空引号）。
    func testToolLineWithoutSummary() {
        guard let line = AgentToolLines.parse("▸ list_dir  ✓ · 0.1s") else { return XCTFail("没有摘要也要认得出") }
        XCTAssertEqual(AgentToolLines.callText(line), "list_dir() (0.1s)")
    }

    /// 不是本进程写的那种行 ⇒ `nil`（界面按原文兜底画，**不猜**）。
    func testForeignLineIsNotParsed() {
        XCTAssertNil(AgentToolLines.parse("这段是模型写的正文，不是过程行"))
        XCTAssertNil(AgentToolLines.parse("⚡ 旧格式"))
    }

    /// 参数摘要超 60 字截断加 `…`（§5.3.8.1 ②）。
    func testLongSummaryIsTruncated() {
        let long = String(repeating: "a", count: 80)
        XCTAssertEqual(AgentToolLines.displaySummary(long).count, AgentToolLines.maxSummaryLength + 1)
        XCTAssertTrue(AgentToolLines.displaySummary(long).hasSuffix("…"))
        // 正好 60 字不截（边界不留一个多余的省略号）
        let exact = String(repeating: "b", count: AgentToolLines.maxSummaryLength)
        XCTAssertEqual(AgentToolLines.displaySummary(exact), exact)
    }

    // MARK: 状态行

    /// 进度条：6 格、四舍五入到格，夹在 0…100。
    func testProgressBarCells() {
        XCTAssertEqual(AgentChatProgressBar.bar(percent: 0), "[░░░░░░]")
        XCTAssertEqual(AgentChatProgressBar.bar(percent: 100), "[██████]")
        XCTAssertEqual(AgentChatProgressBar.bar(percent: 50), "[███░░░]")
        // 越界夹紧（不画出一条 7 格的条，也不出现负格）
        XCTAssertEqual(AgentChatProgressBar.bar(percent: 140), "[██████]")
        XCTAssertEqual(AgentChatProgressBar.bar(percent: -5), "[░░░░░░]")
    }

    /// 字段顺序 = 契约顺序，且**没读数的整段不出现**。
    func testStatusFieldsKeepContractOrderAndDropEmptyOnes() {
        let input = AgentChatStatusInput(
            isRunning: false,
            elapsed: nil,
            model: "deepseek-chat",
            contextUsed: 12_300,
            contextWindow: 131_072,
            contextPercent: 9.4,
            cachePercent: 96,
            tokensPerSecond: 23
        )
        let fields = AgentChatStatusLine.fields(input, extras: [])
        XCTAssertEqual(fields.count, 7)
        XCTAssertEqual(fields[0], L(.agentStatusReady))
        XCTAssertEqual(fields[1], "deepseek-chat")
        XCTAssertEqual(fields[2], AgentTokenShort.text(12_300) + "/" + AgentTokenShort.text(131_072))
        XCTAssertTrue(fields[3].hasPrefix("["))
        XCTAssertTrue(fields[3].hasSuffix("%"))
        XCTAssertEqual(fields[4], "⊙ " + AgentModelReadings.percentText(96))
        XCTAssertEqual(fields[5], "↑ 23 t/s")
        XCTAssertEqual(fields[6], L(.agentStatusVoiceOff))
    }

    /// 什么都没报 ⇒ 只剩首格与 `voice off`（不拿 `0` / `n/a` 填空）。
    func testStatusFieldsOmitMissingReadings() {
        let fields = AgentChatStatusLine.fields(AgentChatStatusInput(isRunning: false), extras: [])
        XCTAssertEqual(fields, [L(.agentStatusReady), L(.agentStatusVoiceOff)])
    }

    /// 运行中：首格换成「在算…」+ 已跑时长；额外读数**跟在固定七格之后**（顺序不乱）。
    func testRunningStatusPutsExtrasAfterTheFixedFields() {
        let input = AgentChatStatusInput(isRunning: true, elapsed: "3.4s")
        let fields = AgentChatStatusLine.fields(input, extras: ["压缩 1 段"])
        XCTAssertEqual(fields.first, L(.agentStatusComputing) + " 3.4s")
        XCTAssertEqual(fields.last, "压缩 1 段")
        XCTAssertEqual(fields[fields.count - 2], L(.agentStatusVoiceOff))
    }
}
