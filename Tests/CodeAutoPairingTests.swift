import XCTest
@testable import DoyahCore

/// 编程助手基础能力（`FR-EDIT-49` 自动配对 / 跳引号 / 包选区 / 删整对 + `FR-EDIT-50` 括号匹配）。
///
/// 判据形态与 Markdown 那一族一致：「给『文本 + 光标 + 敲了哪个键』要『期望文本 + 期望光标』」——
/// 这类手感最容易错的就是**光标差半个字符**（`()` 里光标该在两括号**之间**，不是后面），
/// 所以每条都同时钉住「文本」与「光标」。
final class CodeAutoPairingTests: XCTestCase {

    // MARK: - 小工具

    private func plan(_ typed: String, _ text: String, caret: Int, family: CodeAutoPairing.LanguageFamily = .code) -> CodePairingPlan? {
        CodeAutoPairing.plan(typed: typed, in: text, selection: NSRange(location: caret, length: 0), family: family)
    }

    private func plan(_ typed: String, _ text: String, range: NSRange, family: CodeAutoPairing.LanguageFamily = .code) -> CodePairingPlan? {
        CodeAutoPairing.plan(typed: typed, in: text, selection: range, family: family)
    }

    /// 把计划落到文本上（宿主层做的就是这件事）。
    private func apply(_ plan: CodePairingPlan, to text: String) -> String {
        (text as NSString).replacingCharacters(in: plan.range, with: plan.replacement)
    }

    // MARK: - 配对（FR-EDIT-49）

    /// 最日常的那一条：打 `(` 得 `()`，光标停在**两括号之间**。
    func testOpenParenInsertsPairAndCaretGoesBetween() {
        let plan = try! XCTUnwrap(plan("(", "", caret: 0))
        XCTAssertEqual(plan.replacement, "()")
        XCTAssertEqual(plan.range, NSRange(location: 0, length: 0), "插入点在光标处（不吞已有内容）")
        XCTAssertEqual(apply(plan, to: ""), "()")
        XCTAssertEqual(plan.caret, 1, "光标在两括号之间 —— 停在后面就要多按一次方向键")
        XCTAssertEqual(plan.selectionLength, 0, "配对不该顺手选中什么")
    }

    /// 三种括号都配（`<` **不配**：泛型 / 比较里它更常是运算符）。
    func testThreeBracketsPairAndAngleDoesNot() {
        XCTAssertEqual(try! XCTUnwrap(plan("[", "", caret: 0)).replacement, "[]")
        XCTAssertEqual(try! XCTUnwrap(plan("{", "", caret: 0)).replacement, "{}")
        XCTAssertNil(plan("<", "", caret: 0), "尖括号不配 —— 配错比不配更烦")
    }

    /// 在词中间打括号照样配（`a(b` 是常见写法），但**引号贴着词不配**。
    func testBracketPairsNextToWordButQuoteDoesNot() {
        let text = "ab"
        XCTAssertNotNil(plan("(", text, caret: 1), "括号挨着词也配")

        let dont = "dont"
        XCTAssertNil(plan("'", dont, caret: 4), "`dont'` 里的那个 `'` 是撇号，不是引号的开头")
        XCTAssertNil(plan("'", dont, caret: 3), "左右都是字母 ⇒ 不配对")
        XCTAssertNotNil(plan("'", "where x = ", caret: 10), "空格之后打引号 ⇒ 该配对")
    }

    /// 引号按语言族分档：**散文族（Markdown）不配引号**，但括号照配。
    func testProseFamilyPairsBracketsButNotQuotes() {
        XCTAssertNil(plan("\"", "", caret: 0, family: .prose), "Markdown 里引号是文字，不自动补一半")
        XCTAssertNotNil(plan("(", "", caret: 0, family: .prose), "括号在散文里也要配（写注释 / 链接时天天用）")
    }

    /// 文件名判族：`.md` 一族进 prose，其余进 code。
    func testFamilyInferenceByFileName() {
        XCTAssertEqual(CodeAutoPairing.LanguageFamily.of(fileName: "notes.md"), .prose)
        XCTAssertEqual(CodeAutoPairing.LanguageFamily.of(fileName: "README.MARKDOWN"), .prose)
        XCTAssertEqual(CodeAutoPairing.LanguageFamily.of(fileName: "query.sql"), .code)
        XCTAssertEqual(CodeAutoPairing.LanguageFamily.of(fileName: "Package.swift"), .code)
    }

    // MARK: - 跳引号 / 闭合符（FR-EDIT-49）

    /// 闭合符"该跳就跳"：右边正好是同一个闭合符 ⇒ 光标移过去，**不插入**（否则会打出 `))`）。
    func testTypingCloseWhenNextCharIsSameMovesCaretWithoutInserting() {
        let text = "()"
        let plan = try! XCTUnwrap(self.plan(")", text, caret: 1))
        XCTAssertEqual(plan.replacement, "", "跳引号不插入任何字符")
        XCTAssertEqual(plan.range, NSRange(location: 1, length: 0))
        XCTAssertEqual(apply(plan, to: text), text, "文本一个字符都不变")
        XCTAssertEqual(plan.caret, 2, "光标移到闭合符之后")
    }

    /// 右边**不是**那个闭合符 ⇒ 正常插入（用户可能真想再开一层）。
    func testTypingCloseWhenNextCharDiffersInsertsNormally() {
        XCTAssertNil(self.plan(")", "abc", caret: 1), "右边不是 `)` ⇒ 交还默认实现")
    }

    // MARK: - 选中再打 = 包住（FR-EDIT-49）

    /// 选中 `abc` 再打 `(` ⇒ `(abc)`，且 `abc` **保持选中**（下一步通常是接着打字或再包一层）。
    func testTypingOpenParenWithSelectionWrapsAndKeepsSelection() {
        let text = "abc"
        let plan = try! XCTUnwrap(self.plan("(", text, range: NSRange(location: 0, length: 3)))
        XCTAssertEqual(plan.replacement, "(abc)")
        XCTAssertEqual(apply(plan, to: text), "(abc)")
        XCTAssertEqual(plan.caret, 1, "选区起点 + 1（左括号之后）")
        XCTAssertEqual(plan.selectionLength, 3, "`abc` 保持选中")
    }

    /// 选中再打引号（代码族）⇒ 用一对引号包住。
    func testTypingQuoteWithSelectionWraps() {
        let text = "hello"
        let plan = try! XCTUnwrap(self.plan("\"", text, range: NSRange(location: 0, length: 5)))
        XCTAssertEqual(apply(plan, to: text), "\"hello\"")
        XCTAssertEqual(plan.selectionLength, 5)
    }

    // MARK: - 全角括号（中文输入法上屏的那一套 · T-20261018-205）

    /// 中文输入法（简体拼音·中文标点）下按 `(` 上屏的是 `（` —— 它必须和半角一样配。
    ///
    /// 由头：人类主人 2026-10-18 人工点验「按了没反应」。半角表里没有全角字 ⇒ Core 返回 `nil`
    /// ⇒ 视图交还默认实现 ⇒ **一个闭合符都不补**，现象与「没接线」一模一样。
    func testFullWidthBracketPairsInProseFamily() {
        let plan = try! XCTUnwrap(self.plan("（", "", caret: 0, family: .prose))
        XCTAssertEqual(apply(plan, to: ""), "（）")
        XCTAssertEqual(plan.caret, 1, "光标要在两个全角括号之间")
        XCTAssertEqual(try! XCTUnwrap(self.plan("［", "", caret: 0)).replacement, "［］")
        XCTAssertEqual(try! XCTUnwrap(self.plan("｛", "", caret: 0)).replacement, "｛｝")
    }

    /// 全角也认「跳」：光标右边已经是 `）` ⇒ 移过去，不再插一个。
    func testFullWidthClosingSkipsInsteadOfInserting() {
        let text = "（）"
        let plan = try! XCTUnwrap(self.plan("）", text, caret: 1))
        XCTAssertEqual(plan.replacement, "")
        XCTAssertEqual(plan.caret, 2, "该跳而不是插入")
    }

    /// 全角也认「删整对」：光标夹在空的 `（|）` 里 ⇒ 一次删两个。
    func testFullWidthBackspaceDeletesBoth() {
        let text = "（）"
        let plan = try! XCTUnwrap(CodeAutoPairing.backspacePlan(in: text, selection: NSRange(location: 1, length: 0)))
        XCTAssertEqual(apply(plan, to: text), "")
    }

    // MARK: - 退格删整对（FR-EDIT-49）

    /// 光标夹在**空的**一对里 ⇒ 一次删掉两个（不为自动补上的字符多按一次）。
    func testBackspaceInsideEmptyPairDeletesBoth() {
        let text = "()"
        let plan = try! XCTUnwrap(CodeAutoPairing.backspacePlan(in: text, selection: NSRange(location: 1, length: 0)))
        XCTAssertEqual(plan.range, NSRange(location: 0, length: 2))
        XCTAssertEqual(apply(plan, to: text), "")
        XCTAssertEqual(plan.caret, 0)
    }

    /// 中间有内容 ⇒ **只删一个**（那是用户自己敲的字，不能被连坐）。
    func testBackspaceWithContentInsideDeletesOnlyOne() {
        XCTAssertNil(CodeAutoPairing.backspacePlan(in: "(a)", selection: NSRange(location: 2, length: 0)))
    }

    /// 有选区时退格 = 删选区，不玩配对。
    func testBackspaceWithSelectionIsLeftToDefault() {
        XCTAssertNil(CodeAutoPairing.backspacePlan(in: "()", selection: NSRange(location: 0, length: 2)))
    }

    // MARK: - 括号匹配（FR-EDIT-50）

    /// 基本匹配：`(abc)` 里光标在 `(` 之后 ⇒ 配对者 = 另一个括号。
    func testMatchFindsPartner() {
        let text = "(abc)"
        let m = try! XCTUnwrap(CodeAutoPairing.match(in: text, caret: 1))
        XCTAssertEqual(m.bracket, 0)
        XCTAssertEqual(m.partner, 4)
        XCTAssertFalse(m.truncated)
    }

    /// 嵌套：`((a))` 里光标在**第一个** `(` 之后 ⇒ 配到**最外层**那个。
    func testMatchHandlesNesting() {
        let text = "((a))"
        let m = try! XCTUnwrap(CodeAutoPairing.match(in: text, caret: 1))
        XCTAssertEqual(m.partner, 4, "嵌套时配到最外层 —— 不是最近的那个")
        let inner = try! XCTUnwrap(CodeAutoPairing.match(in: text, caret: 2))
        XCTAssertEqual(inner.partner, 3, "里面的那对各自配")
    }

    /// 光标在闭合符前后都认（左边优先）。
    func testMatchAnchorsOnCloseBracket() {
        let text = "(abc)"
        let m = try! XCTUnwrap(CodeAutoPairing.match(in: text, caret: 4))
        XCTAssertEqual(m.bracket, 4)
        XCTAssertEqual(m.partner, 0, "闭合符向左找开括号")
    }

    /// 没配上 ⇒ `partner == nil` 且 **`truncated == false`**（界面据此给"不匹配"告警色，不是"太远"）。
    func testUnmatchedBracketReportsNoPartnerWithoutTruncation() {
        let m = try! XCTUnwrap(CodeAutoPairing.match(in: "(abc", caret: 1))
        XCTAssertNil(m.partner)
        XCTAssertFalse(m.truncated, "扫完了全篇 ⇒ 是「不匹配」，不是「太远」")
    }

    /// 光标旁边没有括号 ⇒ `nil`（界面不该亮任何东西）。
    func testMatchReturnsNilWhenNoBracketNearCaret() {
        XCTAssertNil(CodeAutoPairing.match(in: "abc", caret: 2))
        XCTAssertNil(CodeAutoPairing.match(in: "", caret: 0))
    }

    // MARK: - 接线判据（源码扫描：Core 有了，界面别掉链子）

    /// `FR-EDIT-49` 的两条通道与 `FR-EDIT-50` 的接线必须在编辑器里**真的在**：
    /// 只写 Core 不接界面 = "写好没接线"（本项目反复踩过的坑）。
    func testEditorWiresPairingChannelsAndHighlight() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("App/Views/CodeEditorView.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(source.contains("override func insertText(_ string: Any, replacementRange: NSRange)"),
                      "字符输入通道要接（配对 / 跳引号 / 包选区都走它）")
        XCTAssertTrue(source.contains("override func deleteBackward("), "退格通道要接（删整对）")
        XCTAssertTrue(source.contains("CodeAutoPairing.plan("), "要调 Core 的配对计划，不许在界面里另写一套判定")
        XCTAssertTrue(source.contains("CodeAutoPairing.backspacePlan("), "要调 Core 的退格计划")
        XCTAssertTrue(source.contains("func applyPairingPlan("), "要有落计划的唯一落点（撤销 / 着色 / 模型都由它带上）")
        XCTAssertTrue(source.contains("pairingFamily"), "语言族要从语言判定来，不许写死")
        XCTAssertTrue(source.contains("MarkdownEditingScope.applies(to: completionLanguage)"),
                      "散文族判定沿用既有那一个（不新开判定口径）")
    }
}
