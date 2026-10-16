import XCTest
@testable import DoyahCore

/// 注释切换（`FR-EDIT-51`）：⌘/ 按当前语言的注释符加 / 取消行注释。
///
/// 判据形态与配对那一族一致：「给『文本 + 选区 + 语言』要『期望文本 + 期望选区』」——
/// 这族最容易错的是**多行选区里空行的处置**与**取消注释时空格的去留**（`//  x` 去掉后该是 `x` 还是 ` x`），
/// 两者都只在界面上"看着别扭"，没有判据就会长期歪着。
final class CodeCommentToggleTests: XCTestCase {

    private func plan(_ text: String, range: NSRange, syntax: CodeSyntax) -> CodeCommentPlan? {
        CodeCommentToggling.plan(in: text, selection: range, syntax: syntax)
    }

    private func plan(_ text: String, caret: Int, syntax: CodeSyntax) -> CodeCommentPlan? {
        plan(text, range: NSRange(location: caret, length: 0), syntax: syntax)
    }

    private func apply(_ plan: CodeCommentPlan, to text: String) -> String {
        (text as NSString).replacingCharacters(in: plan.range, with: plan.replacement)
    }

    /// SQL 的注释符来自语言表（`--`），**不写死在本文件里**。
    private var sql: CodeSyntax { CodeLanguageRegistry.definition(of: .sql).syntax }

    // MARK: - 加注释

    /// 最日常的那一条：光标在没注释的行上 ⇒ 行首加 `-- `，缩进之后。
    func testAddsLineCommentAfterIndent() {
        let text = "    select 1"
        let plan = try! XCTUnwrap(plan(text, caret: 6, syntax: sql))
        XCTAssertEqual(apply(plan, to: text), "    -- select 1")
        XCTAssertEqual(plan.caret, 6 + 3, "光标随该行前缀一起右移（不是跳回行首）")
    }

    /// 多行选区 ⇒ **每行非空行**都加；**空行原地不动**（不写一个光秃秃的 `-- ` 上去）。
    func testAddsToEveryNonEmptySelectedLineButLeavesBlankLinesAlone() {
        let text = "select 1\n\nselect 2"
        let plan = try! XCTUnwrap(plan(text, range: NSRange(location: 0, length: (text as NSString).length), syntax: sql))
        XCTAssertEqual(apply(plan, to: text), "-- select 1\n\n-- select 2")
    }

    /// 混合态（一行有一行没有）⇒ **按下就是"全都加"**（主流行为：VS Code 同款）。
    ///
    /// 这条判据最初被我写反了（期望"只给缺失的加"），与 `CodeCommentToggling` 头顶的口径
    /// 「全注释才取消，否则一律加」自相矛盾 —— **红的是判据、不是代码**。留在这里做反面教材：
    /// 判据红了先分诊"代码错还是判据错"，别急着改代码去迎合一条写错的判据。
    func testMixedStateCommentsEveryNonEmptyLine() {
        let text = "-- select 1\nselect 2"
        let plan = try! XCTUnwrap(plan(text, range: NSRange(location: 0, length: (text as NSString).length), syntax: sql))
        XCTAssertEqual(apply(plan, to: text), "-- -- select 1\n-- select 2")
    }

    // MARK: - 取消注释

    /// 全注释 ⇒ 取消，**连我们加的那个空格一起去掉**（不然来回切会一点点往右挪）。
    func testRemovesCommentAndItsOwnSpace() {
        let text = "-- select 1"
        let plan = try! XCTUnwrap(plan(text, caret: 3, syntax: sql))
        XCTAssertEqual(apply(plan, to: text), "select 1")
    }

    /// 用户自己写的 `--select`（没空格）也能取消，且不会多删一个字符。
    func testRemovesCommentWithoutSpaceFallsBackToTokenOnly() {
        let text = "--select 1"
        let plan = try! XCTUnwrap(plan(text, caret: 2, syntax: sql))
        XCTAssertEqual(apply(plan, to: text), "select 1")
    }

    /// 缩进保持：`    -- x` ⇒ `    x`。
    func testRemovalKeepsIndent() {
        let text = "    -- x"
        let plan = try! XCTUnwrap(plan(text, caret: 8, syntax: sql))
        XCTAssertEqual(apply(plan, to: text), "    x")
    }

    // MARK: - 范围与边界

    /// 选区终点落在**行首** ⇒ 那一行不算进来（与主流一致）。
    func testSelectionEndingAtLineStartExcludesThatLine() {
        let text = "select 1\nselect 2"
        // 选到第二行的行首（offset 9）
        let plan = try! XCTUnwrap(plan(text, range: NSRange(location: 0, length: 9), syntax: sql))
        XCTAssertEqual(apply(plan, to: text), "-- select 1\nselect 2")
    }

    /// 整块全是空行 ⇒ `nil`（没什么可动的，按键交还系统）。
    func testAllBlankSelectionIsLeftToSystem() {
        XCTAssertNil(plan("\n\n", range: NSRange(location: 0, length: 2), syntax: sql))
    }

    /// **只登记了块注释的语言** ⇒ `nil`：宁可什么都不做，也不硬编一个注释符进去。
    func testBlockOnlyLanguageIsLeftToSystem() {
        let blockOnly = CodeSyntax(comments: [CodeCommentStyle(block: "/*", "*/")])
        XCTAssertNil(plan("x = 1", caret: 1, syntax: blockOnly))
    }

    /// 空文档 ⇒ `nil`。
    func testEmptyDocumentIsLeftToSystem() {
        XCTAssertNil(plan("", caret: 0, syntax: sql))
    }

    /// 返回值必须是**一次**替换（整块），不是多次 —— 否则 ⌘Z 要按好几下。
    func testPlanIsOneSingleBlockReplacement() {
        let text = "a\nb\nc"
        let plan = try! XCTUnwrap(plan(text, range: NSRange(location: 0, length: (text as NSString).length), syntax: sql))
        XCTAssertEqual(plan.range, NSRange(location: 0, length: (text as NSString).length))
        XCTAssertEqual(apply(plan, to: text), "-- a\n-- b\n-- c")
    }

    // MARK: - 接线判据（源码扫描：Core 有了，界面别掉链子）

    /// `FR-EDIT-51` 必须在编辑器里**真的在**：⌘/ 分支 + 唯一落点 + 注释符只从语言表来。
    func testEditorWiresCommentToggle() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("App/Views/CodeEditorView.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(source.contains("toggleLineComment()"), "要有 ⌘/ 的落点方法")
        XCTAssertTrue(source.contains("CodeCommentToggling.plan("), "要调 Core 的判定，不许在界面里另写一套")
        XCTAssertTrue(source.contains("CodeLanguageRegistry.definition(of: completionLanguage)"),
                      "注释符要从当前文档的语言来（不许写死）")
        XCTAssertTrue(source.contains("func applyEditPlan("), "要有唯一落点（撤销 / 着色 / 模型都由它带上）")
        XCTAssertTrue(source.contains("charactersIgnoringModifiers == \"/\""), "⌘/ 分支要在按键入口里")
    }
}
