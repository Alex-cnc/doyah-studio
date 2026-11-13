import XCTest
@testable import DoyahCore

/// `T-3.25-11`：**正文可读** —— 富文本档 + 4000 字分块（需求 ⑪）。
///
/// 三条必须成立：① 超限切成多块、块序连续；② 拼回来逐字节等于原文（**不许静默截断**）；
/// ③ 围栏不切（每块自身围栏配对）；另外把「围栏没闭合不切」与「单行超长硬切」各钉一条。
final class AgentIMOutboundChunkerTests: XCTestCase {

    func testShortTextStaysOneChunkAndIsUnchanged() {
        let text = "第一段\n第二段\n"
        let chunks = AgentIMOutboundChunker.split(text)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].text, "第一段\n第二段")
    }

    func testLongTextSplitsAndJoinsBackWithoutLosingAByte() {
        // 每段 900 字 × 8 段 = 7200 字 > 4000 ⇒ 至少切两块
        let paragraph = String(repeating: "字", count: 900)
        let source = (0..<8).map { _ in paragraph }.joined(separator: "\n")
        let chunks = AgentIMOutboundChunker.split(source)
        XCTAssertGreaterThanOrEqual(chunks.count, 2, "超上限必须分块，不许整条硬发")
        for chunk in chunks {
            XCTAssertLessThanOrEqual(chunk.text.count, AgentIMOutboundChunker.platformLimit,
                                     "任何一块都不许超过平台上限")
        }
        XCTAssertTrue(AgentIMOutboundChunker.joinsToOriginal(chunks, original: source),
                      "拼回来必须等于原文 —— 少一个字就是静默截断")
    }

    func testCodeFenceIsNeverCutInHalf() {
        let fence = "```swift\n" + (0..<200).map { "let v\($0) = \($0)" }.joined(separator: "\n") + "\n```\n"
        let source = String(repeating: "前面的正文。\n", count: 400) + fence
        let chunks = AgentIMOutboundChunker.split(source)
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertTrue(AgentIMOutboundChunker.everyChunkHasBalancedFences(chunks),
                      "每块的围栏必须自身配对（否则客户端渲染出两个坏块）")
        for chunk in chunks {
            XCTAssertLessThanOrEqual(chunk.text.count, AgentIMOutboundChunker.platformLimit + 8)
        }
    }

    func testSingleHugeLineIsHardSplitNotDropped() {
        let source = String(repeating: "x", count: 9000)
        let chunks = AgentIMOutboundChunker.split(source)
        XCTAssertGreaterThanOrEqual(chunks.count, 3)
        XCTAssertEqual(chunks.map(\.text).joined(), source, "硬切也不许丢字")
    }

    func testEmptyTextProducesNoChunk() {
        XCTAssertTrue(AgentIMOutboundChunker.split("   \n ").isEmpty)
    }

    // MARK: - 正文载荷（`msg_type=2` + `markdown.content`）

    func testMarkdownBodyUsesTypeTwoAndMarkdownField() throws {
        let body = AgentIMQQMessageBody(content: "**粗**", markdown: "**粗**")
        let json = try XCTUnwrap(ProvisionerSupport.jsonObject(body.jsonString()))
        XCTAssertEqual(json["msg_type"] as? Int, 2)
        let markdown = try XCTUnwrap(json["markdown"] as? [String: Any])
        XCTAssertEqual(markdown["content"] as? String, "**粗**")
        XCTAssertEqual(json["content"] as? String, "", "富文本档不许把源码再塞进 content")
    }

    // MARK: - 媒体标签（需求 ⑫ 的出站入口）

    func testMediaTagIsExtractedAndStrippedFromText() {
        let text = "报表在这里：\nMEDIA:/tmp/报表.png\nMEDIA:/tmp/明细.xlsx\n以上。"
        let extracted = AgentIMMediaTag.extract(from: text)
        XCTAssertEqual(extracted.paths, ["/tmp/报表.png", "/tmp/明细.xlsx"])
        XCTAssertEqual(extracted.text, "报表在这里：\n以上。", "标签行整行摘掉，手机上不许出现 MEDIA:/…")
    }

    func testMediaWordInsideSentenceIsNotATag() {
        let extracted = AgentIMMediaTag.extract(from: "记一下 MEDIA:/tmp/a.png 这个写法")
        XCTAssertTrue(extracted.paths.isEmpty, "只认行首标签")
        XCTAssertEqual(extracted.text, "记一下 MEDIA:/tmp/a.png 这个写法")
    }

    func testTextWithOnlyMediaTagsBecomesEmpty() {
        let extracted = AgentIMMediaTag.extract(from: "MEDIA:/tmp/a.png")
        XCTAssertEqual(extracted.paths, ["/tmp/a.png"])
        XCTAssertEqual(extracted.text, "")
    }

    func testPlainBodyStaysTypeZero() throws {
        let body = AgentIMQQMessageBody(content: "纯文本")
        let json = try XCTUnwrap(ProvisionerSupport.jsonObject(body.jsonString()))
        XCTAssertEqual(json["msg_type"] as? Int, 0)
        XCTAssertNil(json["markdown"])
    }
}
