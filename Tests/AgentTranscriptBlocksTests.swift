import XCTest
@testable import DoyahStudioApp

/// 转写区正文渲染的**分块判据**（`§7.9.10` 语汇下的两个缺口：围栏代码块 / 行内代码与链接）。
///
/// 这些用例守的是**不许吞字**：模型边写边流、围栏可能还没闭合，任何情况下原文都得在。
final class AgentTranscriptBlocksTests: XCTestCase {

    /// 没有围栏 ⇒ 整段是正文，一个字不少。
    func testPlainTextStaysWhole() {
        let blocks = AgentTranscriptText.blocks("第一行\n第二行")
        XCTAssertEqual(blocks, [.prose("第一行\n第二行")])
    }

    /// 成对围栏 ⇒ 中间成代码块，语言标记被摘出来（不当正文显示）。
    func testFencedBlockIsSplitOut() {
        let text = """
        看这段：
        ```swift
        let a = 1
        print(a)
        ```
        就这些。
        """
        let blocks = AgentTranscriptText.blocks(text)
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[1], .code(language: "swift", code: "let a = 1\nprint(a)"))
        // 围栏行本身不许漏进正文
        if case .prose(let head) = blocks[0] { XCTAssertEqual(head, "看这段：") }
        if case .prose(let tail) = blocks[2] { XCTAssertEqual(tail, "就这些。") }
    }

    /// **流式中途**：围栏没闭合也要按代码显示，内容不丢（这是最常见的真实场景）。
    func testUnclosedFenceKeepsCode() {
        let blocks = AgentTranscriptText.blocks("```bash\nls -la")
        XCTAssertEqual(blocks, [.code(language: "bash", code: "ls -la")])
    }

    /// 无语言标记的围栏：`language` 为 nil，但仍是代码块（不是正文）。
    func testFenceWithoutLanguage() {
        let blocks = AgentTranscriptText.blocks("```\nx\n```")
        XCTAssertEqual(blocks, [.code(language: nil, code: "x")])
    }

    /// 行内代码与链接：解析成属性串后，代码段是等宽、链接段保留 URL 属性。
    func testInlineCodeAndLinkAttributes() {
        let attributed = AgentTranscriptText.inlineAttributed(
            "用 `npm ci` 看 [文档](https://example.com)",
            font: .system(.callout, design: .monospaced)
        )
        var sawCode = false
        var sawLink = false
        for run in attributed.runs {
            if run.inlinePresentationIntent?.contains(.code) == true { sawCode = true }
            if run.link != nil { sawLink = true }
        }
        XCTAssertTrue(sawCode, "行内代码应带 inlinePresentationIntent.code")
        XCTAssertTrue(sawLink, "链接应带 link 属性（Text 才可点）")
    }

    /// Markdown 解析失败也不许吞字（比如落单的反引号、坏的方括号）。
    func testMalformedMarkdownFallsBackToRawText() {
        let raw = "这是 `没闭合的反引号 和 [半截链接("
        let attributed = AgentTranscriptText.inlineAttributed(raw, font: .body)
        XCTAssertEqual(String(attributed.characters).isEmpty, false)
        XCTAssertTrue(String(attributed.characters).contains("没闭合的反引号"))
    }
}
