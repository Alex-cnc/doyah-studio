import XCTest
@testable import DoyahStudioApp

/// 对话正文 Markdown 渲染的**排版判据**（详设 `§5.3.8`）。
///
/// 守的是这一条最容易写歪的规矩：**流式中途围栏没收口时不许猜着渲染**（原文照发），
/// 而**收尾之后**同一段字要按完整文档重排。这两个状态由 `AgentMarkdownBodyContent.layout`
/// 一个纯函数决定 —— 用例直接咬它，不去截屏看「看起来差不多」。
final class AgentMarkdownBodyTests: XCTestCase {

    /// 定稿（`isStreaming == false`）⇒ 一律整份文档，哪怕围栏真的没闭合
    /// （定稿内容按 CommonMark 跑到文末，那就是内容，照代码块画）。
    ///
    /// 注意这里**不**要求 `unclosedFenceLine == nil`：解析层如实报「源码里这段没闭合」，
    /// 「要不要因此原文照发」是**呈现**那一层的决定 —— 两层分工不能混。
    func testFinishedTextAlwaysRendersWholeDocument() {
        let markdown = "说明\n\n```swift\nlet a = 1"
        let layout = AgentMarkdownBodyContent.layout(text: markdown, isStreaming: false)
        guard case let .document(document) = layout else {
            return XCTFail("定稿正文必须是整份文档，实测 \(layout)")
        }
        XCTAssertEqual(document.unclosedFenceLine, 3)
        XCTAssertEqual(document.blocks.count, 2)
        XCTAssertEqual(document.blocks[1].kind, .codeBlock(language: "swift", lines: ["let a = 1"]))
    }

    /// 流式中且围栏没收口 ⇒ **围栏之前**照常渲染、从围栏那一行起原文照发。
    func testStreamingUnclosedFenceSplitsIntoPrefixAndRawTail() {
        let markdown = "先看结论：\n\n**这一条**要紧\n\n```swift\nlet a = 1"
        let layout = AgentMarkdownBodyContent.layout(text: markdown, isStreaming: true)
        guard case let .streaming(prefix, rawTail) = layout else {
            return XCTFail("未闭合围栏的流式正文必须走「前缀 + 原文尾巴」，实测 \(layout)")
        }
        // 前缀只到围栏前一行：三块（段落 / 段落），围栏本身不进前缀。
        XCTAssertEqual(prefix.blocks.count, 2)
        XCTAssertNil(prefix.unclosedFenceLine, "前缀里不该再有没收口的围栏")
        // 原文照发：**逐字**，含围栏自己的 ``` 与缩进，一个字都不改。
        XCTAssertEqual(rawTail, "```swift\nlet a = 1")
    }

    /// 围栏闭合（哪怕还在流式中）⇒ 不切分：闭合的块已经定稿，重排它才是抖动。
    func testStreamingClosedFenceRendersWholeDocument() {
        let markdown = "```swift\nlet a = 1\n```\n\n后面还会继续"
        let layout = AgentMarkdownBodyContent.layout(text: markdown, isStreaming: true)
        guard case let .document(document) = layout else {
            return XCTFail("闭合的围栏应当整份渲染，实测 \(layout)")
        }
        XCTAssertNil(document.unclosedFenceLine)
    }

    /// 正文一开始就是围栏、且还没收口 ⇒ 前缀为空、整段原文照发。
    func testStreamingFenceAtFirstLineYieldsEmptyPrefix() {
        let layout = AgentMarkdownBodyContent.layout(text: "```\n第一行", isStreaming: true)
        guard case let .streaming(prefix, rawTail) = layout else {
            return XCTFail("首行围栏未闭合也必须走原文照发，实测 \(layout)")
        }
        XCTAssertTrue(prefix.blocks.isEmpty)
        XCTAssertEqual(rawTail, "```\n第一行")
    }

    /// 没有围栏的流式正文 ⇒ 不切分（普通段落随增量长大，不会跳）。
    func testStreamingWithoutFenceRendersWholeDocument() {
        let layout = AgentMarkdownBodyContent.layout(text: "正在写的一句", isStreaming: true)
        guard case let .document(document) = layout else {
            return XCTFail("没有围栏就不该切分，实测 \(layout)")
        }
        XCTAssertEqual(document.blocks.count, 1)
    }

    /// 前缀 + 尾巴**必须逐字还原原文**（拼接不丢字 —— 切分最容易犯的错就是吃掉换行）。
    func testPrefixAndRawTailReassembleTheSource() {
        let markdown = "第一段\n\n- 一条\n- 两条\n\n```sh\necho hi"
        let layout = AgentMarkdownBodyContent.layout(text: markdown, isStreaming: true)
        guard case let .streaming(_, rawTail) = layout else {
            return XCTFail("未闭合围栏的流式正文必须走原文照发，实测 \(layout)")
        }
        XCTAssertTrue(markdown.hasSuffix(rawTail))
        // 尾巴从围栏那一行起 ⇒ 只剩围栏本身与那一行内容。
        XCTAssertEqual(rawTail, "```sh\necho hi")
    }
}
