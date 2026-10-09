import Foundation
import XCTest
@testable import DoyahCore

/// 笔记正文的**权威源与投影**。
///
/// **片 `WY-1a` 起**：权威源从 v1 的「Markdown + 样式旁挂」切到 v2 的 `{version: 2, spans: [...]}`，
/// `body` / `markdown` 降为**单向投影**（由 `spans` 派生）。这些用例就是「投影到底有损在哪」
/// 与「1→2 迁移保不保真」的清单（而不是纸面讨论）。
final class NoteBodyTests: XCTestCase {

    // MARK: 行内子集 ↔ span 树

    func testMarkdownSubsetProjectsToSpans() {
        let body = NoteBody(markdown: "普通 **加粗** 与 *斜体* 还有 `code`")
        let projection = NoteBodyProjection.toSpans(body, language: .simplifiedChinese)
        XCTAssertEqual(projection.spans.map(\.text), ["普通 ", "加粗", " 与 ", "斜体", " 还有 ", "code"])
        XCTAssertEqual(projection.spans[1].styles, [.bold])
        XCTAssertEqual(projection.spans[3].styles, [.italic])
        XCTAssertEqual(projection.spans[5].styles, [.code])
        XCTAssertTrue(projection.degradations.isEmpty)
    }

    /// **权威源就是 spans**：`body` / `markdown` 是由 spans 派生出来的投影（单向、非存储字段）。
    func testBodyIsDerivedProjectionOfSpans() {
        let body = NoteBody(markdown: "a **b** c")
        XCTAssertEqual(body.spans, NoteBodyProjection.parseInline("a **b** c"), "构造时按 1→2 规则把 md 投影成 spans")
        XCTAssertEqual(body.body, "a **b** c", "`body` 是 spans 的投影")
        XCTAssertEqual(body.markdown, body.body, "`markdown` 是 `body` 的兼容别名")
    }

    /// **语言由调用方给定**（队列 L-65）：同一处有损投影，中英各给一句 —— 此前这条降级说明
    /// 写死简体中文 ⇒ 英文界面上它**永远是中文**，而语言表里这 4 个键的英文译文不可达（死译文）。
    /// v2 起降级发生在 **v1 投影**那一步（`project`），语言仍由调用方给。
    func testDegradationsFollowCallerLanguage() {
        let sidecar = [NoteSidecarStyle(text: "原来的句子", color: "#1E88E5")]
        let zh = NoteBodyProjection.project("改写后的新句子", sidecar: sidecar, language: .simplifiedChinese).degradations
        let en = NoteBodyProjection.project("改写后的新句子", sidecar: sidecar, language: .english).degradations
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
        XCTAssertEqual(restored.spans, original.spans)
    }

    /// **颜色 / 字号落在 span 上**（Markdown 表达不了）⇒ 不进正文投影，但**不许悄悄丢**。
    func testColorAndSizeStayOnTheSpanNotInMarkdown() {
        let spans = [
            NoteSpan(text: "红色字", styles: [.color], color: "#E53935", size: 18),
            NoteSpan(text: "普通字")
        ]
        let body = NoteBodyProjection.fromSpans(spans)
        XCTAssertEqual(body.markdown, "红色字普通字", "颜色与字号不进 Markdown 正文")
        XCTAssertEqual(body.spans, spans, "颜色 / 字号存在 span 上（权威源）")
        // 再投影回来，样式还在
        let back = NoteBodyProjection.toSpans(body, language: .simplifiedChinese)
        XCTAssertEqual(back.spans[0].color, "#E53935")
        XCTAssertEqual(back.spans[0].size, 18)
        XCTAssertTrue(back.degradations.isEmpty)
    }

    /// **有损的那一处（最要紧的一处）**：AI 改过正文之后，旁挂按「文本 + 次序」可能定位不到 ——
    /// 那时**如实降级**，不猜、不静默丢。
    func testSidecarDegradesWhenTextWasRewritten() {
        let sidecar = [NoteSidecarStyle(text: "原来的句子", color: "#1E88E5")]
        let projection = NoteBodyProjection.project("改写后的新句子", sidecar: sidecar, language: .simplifiedChinese)
        XCTAssertEqual(projection.spans.map(\.text), ["改写后的新句子"])
        XCTAssertNil(projection.spans[0].color)
        XCTAssertEqual(projection.degradations.count, 1)
        XCTAssertTrue(projection.degradations[0].contains("原来的句子"), "降级要说清是哪一段")
    }

    /// **有损的第二处**：导出 .md 文件时颜色/字号必然丢 —— 必须给人一份降级报告。
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

    /// **往返**：链接是 Markdown 表达得了的 ⇒ 投影到 span 树再投影回文本必须原样。
    func testLinkRoundTripStaysInMarkdown() {
        let body = NoteBody(markdown: "见 [文档](https://example.com/a) 完")
        let projection = NoteBodyProjection.toSpans(body, language: .simplifiedChinese)
        XCTAssertTrue(projection.degradations.isEmpty)
        let restored = NoteBodyProjection.fromSpans(projection.spans)
        XCTAssertEqual(restored.markdown, body.markdown)
        XCTAssertEqual(restored.spans, body.spans)
    }

    // MARK: 片 `WY-1a` 的三条新判据（权威源切 spans）

    /// **判据 ①**：`spans → JSON → spans` **等价**（往返不丢语义）。
    func testSpansRoundTripThroughJSON() throws {
        let body = NoteBody(spans: [
            NoteSpan(text: "普通 "),
            NoteSpan(text: "粗", styles: [.bold]),
            NoteSpan(text: "键", link: "https://example.com/a"),
            NoteSpan(text: "红", styles: [.color], color: "#E53935", size: 18)
        ])
        let data = try JSONEncoder().encode(body)
        let back = try JSONDecoder().decode(NoteBody.self, from: data)
        XCTAssertEqual(back.version, NoteBodyFormat.currentVersion)
        XCTAssertEqual(back.spans, body.spans, "spans 往返不许丢语义")
        XCTAssertEqual(back.body, body.body, "投影由 spans 派生，往返后仍一致")
    }

    /// **判据 ②**：v1 文档（`{version: 1, markdown, sidecar}`）`migrated()` 后**与旧 md 投影等价**，
    /// 且旁挂里的**颜色 / 字号不静默丢**。
    func testV1DocumentMigratesToSpansProjection() throws {
        let v1 = #"""
        {"version":1,"markdown":"a **b** c","sidecar":[{"text":"c","occurrence":0,"color":"#E53935","size":20}]}
        """#
        let legacy = try JSONDecoder().decode(NoteBody.self, from: Data(v1.utf8))
        XCTAssertEqual(legacy.version, 1, "v1 文档的解码面仍认得")
        XCTAssertEqual(legacy.body, "a **b** c", "投影出来就是原来那段 Markdown")

        let migrated = try legacy.migrated()
        XCTAssertEqual(migrated.version, NoteBodyFormat.currentVersion, "1 → 2")

        // 「与旧 md 投影等价」：迁移后的 spans == v1 投影（project）的 spans
        let oldProjection = NoteBodyProjection.project(
            "a **b** c",
            sidecar: [NoteSidecarStyle(text: "c", occurrence: 0, color: "#E53935", size: 20)],
            language: .simplifiedChinese
        )
        XCTAssertEqual(migrated.spans, oldProjection.spans)

        // 颜色 / 字号没被静默丢 —— 落在 span 上
        let styled = try XCTUnwrap(migrated.spans.first { $0.text == "c" })
        XCTAssertEqual(styled.color, "#E53935")
        XCTAssertEqual(styled.size, 20)
        XCTAssertTrue(styled.styles.contains(.color))
        XCTAssertTrue(styled.styles.contains(.size))
    }

    /// **判据 ③**：**未知 span 字段往返后仍在** —— 为契约 v1.27 的 `link` / `code` 留路
    /// （本片不新增那两个字段，但模型必须留得住不认识的东西）。
    func testUnknownSpanFieldsSurviveRoundTrip() throws {
        let json = #"""
        {"version":2,"spans":[{"text":"码","code":"swift","nested":{"k":[1,2]},"futureFlag":true}]}
        """#
        let body = try JSONDecoder().decode(NoteBody.self, from: Data(json.utf8))
        XCTAssertEqual(body.spans.count, 1)
        XCTAssertEqual(body.spans[0].text, "码")
        XCTAssertEqual(body.spans[0].unknownFields["code"], .string("swift"))
        XCTAssertEqual(body.spans[0].unknownFields["futureFlag"], .bool(true))
        XCTAssertEqual(body.spans[0].unknownFields["nested"], .object(["k": .array([.number(1), .number(2)])]))

        // 再写回、再读：未知字段还在
        let again = try JSONDecoder().decode(NoteBody.self, from: try JSONEncoder().encode(body))
        XCTAssertEqual(again.spans, body.spans)
        XCTAssertEqual(again.spans[0].unknownFields["code"], .string("swift"), "未知字段往返不许丢")
    }

    // MARK: 版本迁移 / 容错

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

    // MARK: 片 `WY-1b1`（编辑面富文本化 + 行内四枚）：`underline` / `backgroundColor` 两个新字段

    /// **判据 ①（本片的新增项）**：span 承载 `bold / italic / underline / backgroundColor` 时
    /// `spans → JSON → spans` **往返不丢** —— 四个字段各判一次（片 `WY-1b1` 加的是后两个）。
    func testUnderlineAndBackgroundSurviveRoundTrip() throws {
        let spans = [
            NoteSpan(text: "粗", styles: [.bold]),
            NoteSpan(text: "斜", styles: [.italic]),
            NoteSpan(text: "下", styles: [.underline]),
            NoteSpan(text: "划", styles: [.bold, .underline], backgroundColor: NoteHighlight.backgroundColorHex),
            NoteSpan(text: "普")
        ]
        let body = NoteBody(spans: spans)
        let back = try JSONDecoder().decode(NoteBody.self, from: try JSONEncoder().encode(body))
        XCTAssertEqual(back.spans, spans, "四样样式（粗 / 斜 / 下划线 / 底色）往返不许丢")
        XCTAssertEqual(back.spans[3].backgroundColor, NoteHighlight.backgroundColorHex)
        XCTAssertTrue(back.spans[3].styles.contains(.underline))
    }

    /// **下划线是「样式」（进 `styles` 集合，与 bold / italic 同形）**；底色是**独立字段**
    /// （与 `color` 同形，`#RRGGBB`）—— 两个字段的形状这轮就钉住，别下一个人再各写一套。
    func testUnderlineIsAStyleAndBackgroundIsAField() {
        let span = NoteSpan(text: "字", styles: [.underline], backgroundColor: "#FFF3B0")
        XCTAssertTrue(NoteSpan.Style.allCases.contains(.underline), "underline 进样式集合（CaseIterable 里有它）")
        XCTAssertEqual(span.backgroundColor, "#FFF3B0")
        XCTAssertNil(NoteSpan(text: "字").backgroundColor, "没铺底色的 span 是 nil（不是空串）")
    }

    /// **底色与下划线不进 Markdown 投影**（Markdown 表达不了）—— 正文里不许冒出标记，
    /// 也不许因为「表达不了」就改写 / 吞掉文字。落库那条路（span 直存）归片 `WY-2`。
    func testUnderlineAndBackgroundDoNotLeakIntoMarkdown() {
        let body = NoteBody(spans: [
            NoteSpan(text: "加粗", styles: [.bold]),
            NoteSpan(text: "带底色", styles: [.underline], backgroundColor: NoteHighlight.backgroundColorHex),
            NoteSpan(text: "普通")
        ])
        XCTAssertEqual(body.markdown, "**加粗**带底色普通", "下划线 / 底色不产出标记，粗体仍是 Markdown 那一档")
    }

    /// **淡黄底色的唯一出处**：数值形态与字符串形态**是同一个值** —— 谁改一个忘了另一个当场红。
    func testHighlightColorHasASingleSource() {
        let channels = Self.channels(ofHex: NoteHighlight.rgb)
        let hex = String(format: "#%02X%02X%02X", channels.red, channels.green, channels.blue)
        XCTAssertEqual(hex, NoteHighlight.backgroundColorHex, "NoteHighlight 的两个形态必须是同一个色值")
    }

    /// 把 `0xRRGGBB` 拆成三通道（Core 测试里没有 AppKit，自己拆一遍，口径与 `NoteHighlight.rgb` 对齐）。
    private static func channels(ofHex hex: UInt32) -> (red: Int, green: Int, blue: Int) {
        (red: Int((hex >> 16) & 0xFF), green: Int((hex >> 8) & 0xFF), blue: Int(hex & 0xFF))
    }
}
