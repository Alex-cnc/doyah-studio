import XCTest
@testable import DoyahCore

/// Q8 选 C 后的核心问题：**Markdown ⇄ span 投影到底有损在哪**。
/// 这些用例就是"有损在哪"的清单（而不是纸面讨论）。
final class NoteBodyTests: XCTestCase {

    func testMarkdownSubsetProjectsToSpans() {
        let body = NoteBody(markdown: "普通 **加粗** 与 *斜体* 还有 `code`")
        let projection = NoteBodyProjection.toSpans(body, language: .simplifiedChinese)
        XCTAssertEqual(projection.spans.map(\.text), ["普通 ", "加粗", " 与 ", "斜体", " 还有 ", "code"])
        XCTAssertEqual(projection.spans[1].styles, [.bold])
        XCTAssertEqual(projection.spans[3].styles, [.italic])
        XCTAssertEqual(projection.spans[5].styles, [.code])
        XCTAssertTrue(projection.degradations.isEmpty)
    }

    /// **语言由调用方给定**（队列 L-65）：同一处有损投影，中英各给一句 —— 此前这条降级说明
    /// 写死简体中文 ⇒ 英文界面上它**永远是中文**，而语言表里这 4 个键的英文译文不可达（死译文）。
    func testDegradationsFollowCallerLanguage() {
        let body = NoteBody(markdown: "改写后的新句子", sidecar: [NoteSidecarStyle(text: "原来的句子", color: "#1E88E5")])
        let zh = NoteBodyProjection.toSpans(body, language: .simplifiedChinese).degradations
        let en = NoteBodyProjection.toSpans(body, language: .english).degradations
        XCTAssertEqual(zh.count, 1)
        XCTAssertEqual(en.count, 1)
        XCTAssertNotEqual(zh[0], en[0], "两种语言必须给出不同的句子（否则英文译文不可达）")
        XCTAssertTrue(en[0].contains("Sidecar style"), "英文那份要真的是英文：\(en[0])")
        XCTAssertTrue(zh[0].contains("旁挂样式"), "中文那份要真的是中文：\(zh[0])")

        // 导出降级报告同理（颜色 / 字号 / 整句三个键）
        let exportBody = NoteBody(markdown: "正文", sidecar: [NoteSidecarStyle(text: "正文", color: "#E53935", size: 20)])
        let exportZH = NoteBodyProjection.exportMarkdown(exportBody, language: .simplifiedChinese).degradations
        let exportEN = NoteBodyProjection.exportMarkdown(exportBody, language: .english).degradations
        XCTAssertEqual(exportZH.count, 1)
        XCTAssertEqual(exportEN.count, 1)
        XCTAssertTrue(exportZH[0].contains("颜色") && exportZH[0].contains("字号"))
        XCTAssertTrue(exportEN[0].contains("color") && exportEN[0].contains("size"), "英文那份要真的是英文：\(exportEN[0])")
        XCTAssertNotEqual(exportZH[0], exportEN[0])
    }

    /// **Round-trip 无损**：编辑器里改过再存，粗体/斜体/代码不该变形。
    func testRoundTripKeepsMarkdownSubset() {
        let original = NoteBody(markdown: "a **b** c *d* e `f`")
        let restored = NoteBodyProjection.fromSpans(NoteBodyProjection.toSpans(original, language: .simplifiedChinese).spans)
        XCTAssertEqual(restored.markdown, original.markdown)
        XCTAssertTrue(restored.sidecar.isEmpty)
    }

    /// **有损的第一处**：行内颜色/字号 Markdown 表达不了 → 必须落**旁挂**，不能悄悄丢。
    func testColorAndSizeGoToSidecarNotIntoMarkdown() {
        let spans = [
            NoteSpan(text: "红色字", styles: [.color], color: "#E53935", size: 18),
            NoteSpan(text: "普通字")
        ]
        let body = NoteBodyProjection.fromSpans(spans)
        XCTAssertEqual(body.markdown, "红色字普通字", "颜色与字号不进 Markdown 正文")
        XCTAssertEqual(body.sidecar, [NoteSidecarStyle(text: "红色字", occurrence: 0, color: "#E53935", size: 18)])
        // 再投影回来，样式还在
        let back = NoteBodyProjection.toSpans(body, language: .simplifiedChinese)
        XCTAssertEqual(back.spans[0].color, "#E53935")
        XCTAssertEqual(back.spans[0].size, 18)
        XCTAssertTrue(back.degradations.isEmpty)
    }

    /// **有损的第二处（也是最要紧的一处）**：AI 改过正文之后，旁挂按"文本+次序"可能定位不到 ——
    /// 那时**如实降级**，不猜、不静默丢。
    func testSidecarDegradesWhenTextWasRewritten() {
        let body = NoteBody(markdown: "改写后的新句子", sidecar: [NoteSidecarStyle(text: "原来的句子", color: "#1E88E5")])
        let projection = NoteBodyProjection.toSpans(body, language: .simplifiedChinese)
        XCTAssertEqual(projection.spans.map(\.text), ["改写后的新句子"])
        XCTAssertNil(projection.spans[0].color)
        XCTAssertEqual(projection.degradations.count, 1)
        XCTAssertTrue(projection.degradations[0].contains("原来的句子"), "降级要说清是哪一段")
    }

    /// **有损的第三处**：导出 .md 文件时颜色/字号必然丢 —— 必须给人一份降级报告。
    func testExportReportsWhatItLoses() {
        let body = NoteBody(markdown: "正文", sidecar: [NoteSidecarStyle(text: "正文", color: "#E53935", size: 20)])
        let export = NoteBodyProjection.exportMarkdown(body, language: .simplifiedChinese)
        XCTAssertEqual(export.markdown, "正文")
        XCTAssertEqual(export.degradations.count, 1)
        XCTAssertTrue(export.degradations[0].contains("颜色"))
        XCTAssertTrue(export.degradations[0].contains("字号"))
    }

    /// **不解析的语法原样搬运**：标题 / 列表这些我们不解析，但**不许破坏**（AI 写的排版不能被改坏）。
    ///
    /// **2026-10-01 第 146 轮起链接不在此列**（队列 `L-137` 剩余③：链接进 span 树 —— 契约
    /// 「默认开在已内嵌的浏览器页签里」）⇒ 这里换成一条**未闭合的**链接，继续钉「不解析的不破坏」。
    func testUnsupportedMarkdownIsPassedThroughUnchanged() {
        let markdown = "# 标题\n- 列表项\n[未闭合](https://example.com"
        let projection = NoteBodyProjection.toSpans(NoteBody(markdown: markdown), language: .simplifiedChinese)
        XCTAssertEqual(projection.spans.map(\.text).joined(), markdown)
        XCTAssertTrue(projection.degradations.isEmpty, "不解析不等于降级")
    }

    // MARK: 链接进 span 树（队列 `L-137` 剩余③）

    /// **链接进 span 树**（2026-10-01 人类主人答「#2，进」）：行内解析器续产**链接目标**。
    /// 目标**原样**保存 —— 是不是一个能加载的地址**不在这里判**（那是浏览器那条唯一入口的事）。
    func testInlineLinksCarryTheirTarget() {
        let spans = NoteBodyProjection.parseInline("见 [文档](https://example.com/a?b=1) 与 [相对](docs/x.md)")
        XCTAssertEqual(spans.map(\.text), ["见 ", "文档", " 与 ", "相对"])
        XCTAssertNil(spans[0].link)
        XCTAssertEqual(spans[1].link, "https://example.com/a?b=1")
        XCTAssertNil(spans[2].link)
        XCTAssertEqual(spans[3].link, "docs/x.md")
        XCTAssertTrue(spans[1].styles.isEmpty, "链接不是粗体那种样式：目标落在 link 上，不塞进 styles")
    }

    /// 链接的**边界**（每一条都是「不猜、不改写」的落点）。
    func testInlineLinkBoundariesStayAsPlainText() {
        // 空文字 / 空目标 / 中间有空格 / 没有右半边 —— 一律退回普通文本（不吞字）
        for sample in ["[](https://a)", "[文字]()", "[文字] (https://a)", "[文字](https://a"] {
            XCTAssertEqual(
                NoteBodyProjection.parseInline(sample), [NoteSpan(text: sample)],
                "「\(sample)」不该被当成链接"
            )
        }
        // **目标里不成对的 `)`**：截到第一个 `)`（不做括号平衡 —— 多出来那个留在剩余文本里）
        let unbalanced = NoteBodyProjection.parseInline("[a](b(c))")
        XCTAssertEqual(unbalanced.map(\.text), ["a", ")"])
        XCTAssertEqual(unbalanced[0].link, "b(c")
        // **跨行不算链接**：一个 `](` 能跨过整篇把后面的文字吞进"链接文字"里 —— 那是"吞"，不许
        XCTAssertEqual(NoteBodyProjection.parseInline("[a\nb](c)"), [NoteSpan(text: "[a\nb](c)")])
        XCTAssertEqual(NoteBodyProjection.parseInline("[a](b\nc)"), [NoteSpan(text: "[a](b\nc)")])
    }

    /// 链接与其它标记**同一条「取最早出现的那个」**；**标记里的标记不再解析**（子集刻意很小）。
    func testLinksAndPairsShareTheEarliestWinsRule() {
        XCTAssertEqual(
            NoteBodyProjection.parseInline("**[a](b)**"),
            [NoteSpan(text: "[a](b)", styles: [.bold])],
            "粗体在前 ⇒ 先切粗体；粗体里的链接文字**不再解析**（原文搬运）"
        )
        let mixed = NoteBodyProjection.parseInline("`码` 与 [链接](https://a)")
        XCTAssertEqual(mixed.map(\.text), ["码", " 与 ", "链接"])
        XCTAssertEqual(mixed[0].styles, [.code])
        XCTAssertEqual(mixed[2].link, "https://a")
        // 同一条「先来后到」的反向：链接在前就先切链接
        let linkFirst = NoteBodyProjection.parseInline("[链接](https://a) 与 **粗**")
        XCTAssertEqual(linkFirst.map(\.text), ["链接", " 与 ", "粗"])
        XCTAssertEqual(linkFirst[0].link, "https://a")
        XCTAssertEqual(linkFirst[2].styles, [.bold])
    }

    /// **往返**：链接是 Markdown 表达得了的 ⇒ 从 span 树写回去必须原样，**不落旁挂**。
    func testLinkRoundTripStaysInMarkdown() {
        let body = NoteBody(markdown: "见 [文档](https://example.com/a) 完")
        let projection = NoteBodyProjection.toSpans(body, language: .simplifiedChinese)
        XCTAssertTrue(projection.degradations.isEmpty)
        let restored = NoteBodyProjection.fromSpans(projection.spans)
        XCTAssertEqual(restored.markdown, body.markdown)
        XCTAssertTrue(restored.sidecar.isEmpty, "链接不许落旁挂")
    }

    /// **版本迁移**：更高的版本如实拒绝（不猜、不静默降级），同版本/低版本正常。
    func testVersionMigrationRefusesFutureVersions() throws {
        XCTAssertEqual(try NoteBody(version: 0, markdown: "x").migrated().version, NoteBodyFormat.currentVersion)
        XCTAssertEqual(try NoteBody(markdown: "x").migrated().version, NoteBodyFormat.currentVersion)
        XCTAssertThrowsError(try NoteBody(version: NoteBodyFormat.currentVersion + 1, markdown: "x").migrated()) { error in
            XCTAssertEqual(error as? NoteBody.MigrationError, .fromFuture(NoteBodyFormat.currentVersion + 1))
        }
    }

    /// 空文档与坏数据都不要抛错（与富文本模型"容错"那条需求一致）。
    func testEmptyAndOddInputsAreTolerated() {
        XCTAssertEqual(NoteBodyProjection.toSpans(NoteBody(markdown: ""), language: .simplifiedChinese).spans.map(\.text), [])
        // 未闭合的标记：整段当纯文本，不吞字
        let odd = NoteBodyProjection.toSpans(NoteBody(markdown: "未闭合 **粗体"), language: .simplifiedChinese)
        XCTAssertEqual(odd.spans.map(\.text).joined(), "未闭合 **粗体")
        XCTAssertEqual(NoteBodyProjection.fromSpans([]).markdown, "")
    }
}
