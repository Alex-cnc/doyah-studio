import XCTest
@testable import DoyahCore

/// CLI 折行与用量账的判据（由头 = 人类主人 2026-10-17：「cli 对话框要能自动换行，还要加上模型信息、
/// 会话已消耗的 token 等信息」）。
final class TerminalWrapTests: XCTestCase {

    // MARK: - 宽度：中文按 2 列，不是 2 个字符

    func testWideCharactersCountTwoColumns() {
        XCTAssertEqual(TerminalTextWrap.displayWidth(of: "abc"), 3)
        XCTAssertEqual(TerminalTextWrap.displayWidth(of: "中文"), 4, "中文一个字 2 列 —— 按字符数算会低估一半")
        XCTAssertEqual(TerminalTextWrap.displayWidth(of: "中a"), 3)
        XCTAssertEqual(TerminalTextWrap.displayWidth(of: "），"), 4, "全角标点同样是 2 列")
    }

    // MARK: - 折行：每行不超宽，且不把词/字切坏

    func testEveryEmittedLineFitsTheColumnBudget() {
        var wrapper = TerminalTextWrapper(columns: 40)
        let text = String(repeating: "alpha beta gamma delta epsilon zeta ", count: 12)
        let out = wrapper.feed(text) + wrapper.flush()
        let lines = out.components(separatedBy: "\n").filter { !$0.isEmpty }
        XCTAssertGreaterThan(lines.count, 3, "长文本必须真的折了行")
        for line in lines {
            XCTAssertLessThanOrEqual(TerminalTextWrap.displayWidth(of: line), 40, "超宽行：\(line)")
        }
        // 不许把词切坏：原文里的每个词都还能在折行结果里整词找到
        for word in ["alpha", "beta", "gamma", "delta", "epsilon", "zeta"] {
            XCTAssertTrue(lines.contains { $0.contains(word) }, "词被切坏：\(word)")
        }
    }

    func testChineseWrapsByColumnNotByCharacterCount() {
        var wrapper = TerminalTextWrapper(columns: 20)
        let text = String(repeating: "中文折行", count: 20)   // 4 字 = 8 列
        let out = wrapper.feed(text) + wrapper.flush()
        let lines = out.components(separatedBy: "\n").filter { !$0.isEmpty }
        XCTAssertGreaterThan(lines.count, 1)
        for line in lines {
            XCTAssertLessThanOrEqual(TerminalTextWrap.displayWidth(of: line), 20, "超宽行：\(line)")
        }
        XCTAssertEqual(out.filter { $0 != "\n" }.count, text.count, "折行不许丢字也不许加字")
    }

    func testExplicitNewlinesArePreservedAndLongWordIsHardBroken() {
        var wrapper = TerminalTextWrapper(columns: 20)
        let out = wrapper.feed("第一行\n" + String(repeating: "x", count: 50)) + wrapper.flush()
        let lines = out.components(separatedBy: "\n")
        XCTAssertEqual(lines.first, "第一行", "显式换行原样保留")
        for line in lines {
            XCTAssertLessThanOrEqual(TerminalTextWrap.displayWidth(of: line), 20, "无空格长串也要硬断：\(line)")
        }
        XCTAssertEqual(out.filter { $0 == "x" }.count, 50, "硬断不许丢字符")
    }

    func testShortTextStaysPendingUntilFlush() {
        var wrapper = TerminalTextWrapper(columns: 40)
        XCTAssertEqual(wrapper.feed("短句"), "", "不满一行 ⇒ 先攒着（终端不能回退，只能等断点）")
        XCTAssertEqual(wrapper.flush(), "短句", "收尾必须吐出来，不许吞")
    }

    // MARK: - 会话 token 账

    func testSessionUsageAccumulatesAndNeverTreatsMissingAsZero() {
        var usage = CLITokenUsage()
        XCTAssertFalse(usage.add(prompt: 100, completion: 20))
        XCTAssertFalse(usage.add(prompt: 200, completion: 30))
        XCTAssertEqual(usage.requests, 2)
        XCTAssertEqual(usage.promptTokens, 300)
        XCTAssertEqual(usage.completionTokens, 50)
        XCTAssertEqual(usage.totalTokens, 350)
        XCTAssertEqual(usage.responsesWithoutUsage, 0)

        XCTAssertTrue(usage.add(prompt: nil, completion: nil), "端点没回用量 ⇒ 如实标一次缺值")
        XCTAssertEqual(usage.responsesWithoutUsage, 1)
        XCTAssertEqual(usage.totalTokens, 350, "缺值不当 0 累加，也不许把已有读数改小")
        XCTAssertEqual(usage.requests, 3, "请求次数照数（那次确实发过）")
    }
}
