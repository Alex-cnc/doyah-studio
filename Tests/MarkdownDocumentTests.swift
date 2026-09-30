import XCTest
@testable import DoyahCore

/// 工作区 Markdown 预览的**块级模型**用例（队列 `L-137` 第一片：解析层）。
///
/// 这些用例是「模型到底支持什么」的清单，也是**不支持什么**的清单 ——
/// 每一条「不支持」都有一个名字里带 NotSupported 的用例钉住它的实际行为
/// （原样当纯文本搬运），而不是让它悄悄通过。
final class MarkdownDocumentTests: XCTestCase {

    // MARK: 标题

    func testHeadingsByLevel() {
        let document = MarkdownDocument.parse("# 一级\n## 二级 ##\n###### 六级\n####### 七个井号")
        XCTAssertEqual(document.blocks.count, 4)
        XCTAssertEqual(document.blocks[0].kind, .heading(level: 1, spans: [NoteSpan(text: "一级")]))
        // 收尾井号被吃掉（CommonMark 的写法）
        XCTAssertEqual(document.blocks[1].kind, .heading(level: 2, spans: [NoteSpan(text: "二级")]))
        XCTAssertEqual(document.blocks[2].kind, .heading(level: 6, spans: [NoteSpan(text: "六级")]))
        // 七个井号**不是**标题（1~6 之外）⇒ 退回段落、原样搬运
        XCTAssertEqual(document.blocks[3].kind, .paragraph(spans: [NoteSpan(text: "####### 七个井号")]))
        XCTAssertEqual(document.blocks[0].headingLevel, 1)
        XCTAssertNil(document.blocks[3].headingLevel)
    }

    /// `#没有空格` 不是标题（CommonMark 要求井号后有空格）。
    func testHashWithoutSpaceIsNotAHeading() {
        let document = MarkdownDocument.parse("#没有空格")
        XCTAssertEqual(document.blocks.count, 1)
        XCTAssertEqual(document.blocks[0].kind, .paragraph(spans: [NoteSpan(text: "#没有空格")]))
    }

    // MARK: 段落

    /// 软换行**原样留下 `\n`**：给空格还是给断行是平台层的显示决定，模型不替它决定。
    func testParagraphKeepsSoftBreaksAndLineNumbers() {
        let document = MarkdownDocument.parse("第一行\n第二行\n\n第三段")
        XCTAssertEqual(document.blocks.count, 2)
        XCTAssertEqual(document.blocks[0].kind, .paragraph(spans: [NoteSpan(text: "第一行\n第二行")]))
        XCTAssertEqual(document.blocks[0].sourceLine, 1)
        XCTAssertEqual(document.blocks[1].kind, .paragraph(spans: [NoteSpan(text: "第三段")]))
        XCTAssertEqual(document.blocks[1].sourceLine, 4)
    }

    // MARK: 列表

    /// 嵌套列表进 `children`，且**子块的行号是原文绝对行号**（跟随滚动的底稿）。
    func testBulletListWithNestedListKeepsAbsoluteLineNumbers() {
        let document = MarkdownDocument.parse("- 父项\n  - 子项\n- 第二项")
        XCTAssertEqual(document.blocks.count, 1)
        guard case let .bulletList(items) = document.blocks[0].kind else {
            return XCTFail("应当是列表，得到 \\(document.blocks[0].kind)")
        }
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].spans, [NoteSpan(text: "父项")])
        XCTAssertEqual(items[0].sourceLine, 1)
        XCTAssertEqual(items[0].children.count, 1)
        guard case let .bulletList(children) = items[0].children[0].kind else {
            return XCTFail("子项应当是列表")
        }
        XCTAssertEqual(children.count, 1)
        XCTAssertEqual(children[0].spans, [NoteSpan(text: "子项")])
        XCTAssertEqual(children[0].sourceLine, 2, "子块行号必须是原文第 2 行，不是子文本里的第 1 行")
        XCTAssertEqual(items[1].spans, [NoteSpan(text: "第二项")])
        XCTAssertEqual(items[1].sourceLine, 3)
    }

    /// 有序表**起点数字要留住**（`3.` 打头就不许从 1 重新数）。
    func testOrderedListKeepsStartNumber() {
        let document = MarkdownDocument.parse("3. 三\n4. 四\n5) 圆括号也算")
        guard case let .orderedList(start, items) = document.blocks[0].kind else {
            return XCTFail("应当是有序表")
        }
        XCTAssertEqual(start, 3)
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[2].spans, [NoteSpan(text: "圆括号也算")])
    }

    /// 松散列表：空行不切断同一段列表。
    func testLooseListSurvivesBlankLine() {
        let document = MarkdownDocument.parse("- 一\n\n- 二")
        guard case let .bulletList(items) = document.blocks[0].kind else {
            return XCTFail("应当是列表")
        }
        XCTAssertEqual(items.map { $0.spans.map(\.text) }, [["一"], ["二"]])
    }

    /// 条目续行算**同一条目的正文**（软换行），不是新块。
    func testListItemContinuationJoinsItemText() {
        let document = MarkdownDocument.parse("- 第一行\n  第二行")
        guard case let .bulletList(items) = document.blocks[0].kind else {
            return XCTFail("应当是列表")
        }
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].spans, [NoteSpan(text: "第一行\n第二行")])
        XCTAssertTrue(items[0].children.isEmpty)
    }

    // MARK: 任务列表

    func testTaskListStripsCheckbox() {
        let document = MarkdownDocument.parse("- [x] 做完\n- [ ] 没做\n- [X] 大写也行")
        guard case let .taskList(items) = document.blocks[0].kind else {
            return XCTFail("应当是任务列表")
        }
        XCTAssertEqual(items.map(\.isChecked), [true, false, true])
        XCTAssertEqual(items.map { $0.spans.map(\.text) }, [["做完"], ["没做"], ["大写也行"]])
        XCTAssertEqual(items[1].sourceLine, 2)
    }

    /// 只有一条不带复选框 ⇒ **整段按普通列表**，那串 `[x]` 原样留在正文里
    /// （摘一半会让界面出现两套写法：说不清哪种才算数）。
    func testMixedCheckboxListStaysPlainList() {
        let document = MarkdownDocument.parse("- [x] 一条\n- 普通条")
        guard case let .bulletList(items) = document.blocks[0].kind else {
            return XCTFail("应当是普通列表")
        }
        XCTAssertEqual(items.map { $0.spans.map(\.text) }, [["[x] 一条"], ["普通条"]])
    }

    /// `[x]` 后面没有空格 ⇒ 不算复选框（GFM 的写法）。
    func testCheckboxRequiresSpaceAfterBracket() {
        let document = MarkdownDocument.parse("- [x]没有空格")
        guard case let .bulletList(items) = document.blocks[0].kind else {
            return XCTFail("应当是普通列表")
        }
        XCTAssertEqual(items[0].spans.map(\.text), ["[x]没有空格"])
    }

    // MARK: 表格

    func testTableWithAlignmentsAndRaggedRows() {
        let markdown = "| 名称 | 值 | 备注 |\n| :--- | :---: | ---: |\n| a | 1 |\n| b | 2 | 3 | 4 |"
        let document = MarkdownDocument.parse(markdown)
        guard case let .table(header, alignments, rows) = document.blocks[0].kind else {
            return XCTFail("应当是表格")
        }
        XCTAssertEqual(header.map { $0.map(\.text).joined() }, ["名称", "值", "备注"])
        XCTAssertEqual(alignments, [.leading, .center, .trailing])
        XCTAssertEqual(rows.count, 2)
        // 短行**补齐**（渲染层不必自己防越界）
        XCTAssertEqual(rows[0].count, 3)
        XCTAssertEqual(rows[0].map { $0.map(\.text).joined() }, ["a", "1", ""])
        // 长行**不丢**（多出来的格子留着 —— 静默扔数据比多画一格糟）
        XCTAssertEqual(rows[1].count, 4)
        XCTAssertEqual(rows[1].map { $0.map(\.text).joined() }, ["b", "2", "3", "4"])
        XCTAssertEqual(document.blocks[0].sourceLine, 1)
    }

    func testEscapedPipeInTableCell() {
        let document = MarkdownDocument.parse("| 路径 |\n| --- |\n| a \\| b |")
        guard case let .table(_, _, rows) = document.blocks[0].kind else {
            return XCTFail("应当是表格")
        }
        XCTAssertEqual(rows[0].map { $0.map(\.text).joined() }, ["a | b"])
    }

    /// 分隔行格子数与表头不一致 ⇒ **不是表格**（GFM 的口径：整行退回段落）。
    func testDelimiterCountMismatchIsNotATable() {
        let document = MarkdownDocument.parse("| a | b |\n| --- |\n文字")
        XCTAssertEqual(document.blocks.count, 1)
        guard case .paragraph = document.blocks[0].kind else {
            return XCTFail("应当是段落，得到 \\(document.blocks[0].kind)")
        }
    }

    /// 没有分隔行 ⇒ 不是表格。
    func testTableWithoutDelimiterIsParagraph() {
        let document = MarkdownDocument.parse("| a | b |\n不是分隔行")
        guard case let .paragraph(spans) = document.blocks[0].kind else {
            return XCTFail("应当是段落")
        }
        XCTAssertEqual(spans.map(\.text), ["| a | b |\n不是分隔行"])
    }

    // MARK: 代码块

    func testFencedCodeBlockKeepsLanguageAndRawLines() {
        let document = MarkdownDocument.parse("```swift\nlet a = 1\n**不是粗体**\n```")
        guard case let .codeBlock(language, lines) = document.blocks[0].kind else {
            return XCTFail("应当是代码块")
        }
        XCTAssertEqual(language, "swift")
        // 代码块里的内容**不做行内解析**（星星就是星星）
        XCTAssertEqual(lines, ["let a = 1", "**不是粗体**"])
    }

    /// 未闭合的围栏跑到文末（CommonMark 口径）：不报错、不吞内容。
    func testUnterminatedFenceRunsToEndOfDocument() {
        let document = MarkdownDocument.parse("```\n没有收尾")
        guard case let .codeBlock(language, lines) = document.blocks[0].kind else {
            return XCTFail("应当是代码块")
        }
        XCTAssertNil(language, "没写语言就说 nil，不猜")
        XCTAssertEqual(lines, ["没有收尾"])
    }

    /// 波浪线围栏与更长的收尾围栏。
    func testTildeFenceAndLongerClosingFence() {
        let document = MarkdownDocument.parse("~~~\n一行\n~~~~~")
        guard case let .codeBlock(_, lines) = document.blocks[0].kind else {
            return XCTFail("应当是代码块")
        }
        XCTAssertEqual(lines, ["一行"])
    }

    // MARK: 引用与分隔线

    func testNestedQuote() {
        let document = MarkdownDocument.parse("> 引用一\n> > 内层")
        guard case let .quote(blocks) = document.blocks[0].kind else {
            return XCTFail("应当是引用")
        }
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0].kind, .paragraph(spans: [NoteSpan(text: "引用一")]))
        guard case let .quote(inner) = blocks[1].kind else {
            return XCTFail("第二块应当是内层引用")
        }
        XCTAssertEqual(inner[0].kind, .paragraph(spans: [NoteSpan(text: "内层")]))
    }

    /// 引用里的**惰性续行**（不带 `>`）不支持：那一行是新段落。写在注释里，也被用例钉住。
    func testQuoteLazyContinuationIsNotSupported() {
        let document = MarkdownDocument.parse("> 引用\n续行")
        XCTAssertEqual(document.blocks.count, 2)
        guard case .quote = document.blocks[0].kind else {
            return XCTFail("第一块应当是引用")
        }
        XCTAssertEqual(document.blocks[1].kind, .paragraph(spans: [NoteSpan(text: "续行")]))
    }

    func testThematicBreakVariants() {
        let document = MarkdownDocument.parse("- - -\n***\n___")
        XCTAssertEqual(document.blocks.count, 3)
        for block in document.blocks {
            XCTAssertEqual(block.kind, .thematicBreak)
        }
        XCTAssertEqual(document.blocks.map(\.sourceLine), [1, 2, 3])
    }

    // MARK: 不支持的部分（钉住实际行为，不让它悄悄通过）

    func testSetextHeadingAndIndentedCodeAreNotSupported() {
        let document = MarkdownDocument.parse("标题\n===\n\n    四空格代码")
        XCTAssertEqual(document.blocks.count, 2)
        // Setext 标题不支持 ⇒ `===` 原样跟着段落走（`---` 会被当分隔线，见上面那条用例）
        XCTAssertEqual(document.blocks[0].kind, .paragraph(spans: [NoteSpan(text: "标题\n===")]))
        // 缩进式代码块不支持 ⇒ 按段落文本搬运（行首缩进被段落口径吃掉）
        XCTAssertEqual(document.blocks[1].kind, .paragraph(spans: [NoteSpan(text: "四空格代码")]))
    }

    func testEmptyDocument() {
        let document = MarkdownDocument.parse("")
        XCTAssertTrue(document.blocks.isEmpty)
        XCTAssertEqual(document.lineCount, 1)
        XCTAssertFalse(document.report.isTruncated)
    }

    // MARK: 同源（判据 ① 的机械面：预览与笔记侧**同一个**行内函数）

    /// 块里的行内 span 必须**逐条等于**笔记侧那个函数的结果 ——
    /// 这条不等，就说明有人在预览侧写了第二套行内解析。
    func testInlineRunsComeFromTheNoteSideParser() {
        let samples = [
            "普通 **粗体** 与 *斜体* 还有 `code`",
            "**未闭合的粗体",
            "星号 * 单独出现",
            "``",
        ]
        for sample in samples {
            let document = MarkdownDocument.parse(sample)
            guard case let .paragraph(spans) = document.blocks[0].kind else {
                return XCTFail("应当是段落：\\(sample)")
            }
            XCTAssertEqual(spans, NoteBodyProjection.parseInline(sample), "样本：\\(sample)")
        }
        // 列表条目与标题同理
        let list = MarkdownDocument.parse("- **粗** 一条")
        guard case let .bulletList(items) = list.blocks[0].kind else {
            return XCTFail("应当是列表")
        }
        XCTAssertEqual(items[0].spans, NoteBodyProjection.parseInline("**粗** 一条"))
        let heading = MarkdownDocument.parse("# 带 `码` 的标题")
        guard case let .heading(_, headingSpans) = heading.blocks[0].kind else {
            return XCTFail("应当是标题")
        }
        XCTAssertEqual(headingSpans, NoteBodyProjection.parseInline("带 `码` 的标题"))
        // 笔记侧的投影走的正是同一个函数（`toSpans` 与 `parseInline` 不许分叉）
        let body = NoteBody(markdown: "a **b** c")
        XCTAssertEqual(
            NoteBodyProjection.toSpans(body, language: .simplifiedChinese).spans,
            NoteBodyProjection.parseInline("a **b** c")
        )
    }

    // MARK: 上限与如实的截断报告

    func testLineLimitReportsSkippedLines() {
        let markdown = "一\n二\n三\n四\n五\n六"
        let document = MarkdownDocument.parse(markdown, limits: MarkdownParseLimits(maxLines: 3, maxBlocks: 100))
        XCTAssertEqual(document.lineCount, 6)
        XCTAssertEqual(document.report.skippedLineCount, 3)
        XCTAssertEqual(document.report.unparsedLineCount, 0)
        XCTAssertTrue(document.report.isTruncated)
        // 只解析前 3 行（句内软换行 ⇒ 一个段落，文本是前三行）
        XCTAssertEqual(document.blocks.count, 1)
        guard case let .paragraph(spans) = document.blocks[0].kind else {
            return XCTFail("应当是段落")
        }
        XCTAssertEqual(spans.map(\.text), ["一\n二\n三"])
    }

    func testBlockLimitReportsUnparsedLines() {
        let document = MarkdownDocument.parse("# 一\n\n二\n三\n", limits: MarkdownParseLimits(maxLines: 100, maxBlocks: 1))
        XCTAssertEqual(document.blocks.count, 1)
        XCTAssertEqual(document.report.skippedLineCount, 0)
        XCTAssertEqual(document.report.unparsedLineCount, 4)
        XCTAssertTrue(document.report.isTruncated)
    }

    func testDefaultLimitsAreWide() {
        let limits = MarkdownParseLimits()
        XCTAssertEqual(limits.maxLines, 20_000)
        XCTAssertEqual(limits.maxBlocks, 5_000)
        let document = MarkdownDocument.parse("一\n二")
        XCTAssertFalse(document.report.isTruncated)
        XCTAssertEqual(document.lineCount, 2)
    }

    /// 解析是**纯函数**：同样输入两次，结果逐条相等（没有隐藏状态、没读环境）。
    func testParseIsPure() {
        let markdown = "# 标题\n\n- [x] 一\n- [ ] 二\n\n| a |\n| --- |\n| b |\n\n```\ncode\n```"
        XCTAssertEqual(MarkdownDocument.parse(markdown), MarkdownDocument.parse(markdown))
    }
}
