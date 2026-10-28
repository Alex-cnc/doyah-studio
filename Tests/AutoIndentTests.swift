import XCTest
@testable import DoyahCore

/// 自动缩进与智能粘贴（`FR-STD-WS-EDIT-021`）：回车继承上一行缩进 / `{ ( [` 之后多一级 /
/// 单独成行的 `} ) ]` 回退一级；粘贴多行文本按上下文重排缩进。
///
/// 判据形态与其余编辑动作族一致：「给『文本 + 选区』要『期望文本 + 期望光标』」。
/// 这一族最容易错的不是规则本身，是三件落点上的事，各自有判据钉住：
/// · **进 / 退的那一级取当前行的实际缩进**（制表符与空格不改写成对方、不规则缩进照原样带走）；
/// · **什么时候不动**（有选区 / 后面还有正文 / 顶格且无级可继承 ⇒ `nil`，交还系统默认回车）；
/// · **外来缩进不硬塞**（粘贴块先剥自己的公共缩进、再接上下文那一级；空白行不留尾随空格）。
final class AutoIndentTests: XCTestCase {

    private let unit = AutoIndent.unit

    private func caret(_ offset: Int) -> NSRange { NSRange(location: offset, length: 0) }

    private func newline(_ text: String, _ range: NSRange) -> AutoIndentPlan? {
        AutoIndent.newline(in: text, selection: range)
    }

    private func paste(_ clip: String, into text: String, _ range: NSRange) -> AutoIndentPlan? {
        AutoIndent.paste(clip, into: text, selection: range)
    }

    private func length(_ text: String) -> Int { (text as NSString).length }

    // MARK: - ① 回车继承上一行缩进

    /// 最日常的那一条：缩进 4 空格的行里回车 ⇒ 新行同样 4 空格，光标落在缩进之后。
    func testInheritsIndentOnEnter() {
        let text = "    foo"
        let plan = try! XCTUnwrap(newline(text, caret(length(text))))
        XCTAssertEqual(plan.applied(to: text), "    foo\n    ")
        XCTAssertEqual(plan.caret, length(text) + 1 + unit.count, "光标落在新行缩进之后（不是行首）")
    }

    /// 制表符缩进**原样带走** —— 不许在两行之间把「\t」改写成空格（用户的书写习惯不被我们改）。
    func testInheritsTabIndentWithoutRewriting() {
        let text = "\tfoo"
        let plan = try! XCTUnwrap(newline(text, caret(length(text))))
        XCTAssertEqual(plan.applied(to: text), "\tfoo\n\t")
    }

    /// 不规则缩进（2 空格 / 半级）照原样继承 —— 取的是**这一行的实际缩进**，不是按层级重算。
    func testInheritsIrregularIndent() {
        let text = "  foo"
        let plan = try! XCTUnwrap(newline(text, caret(length(text))))
        XCTAssertEqual(plan.applied(to: text), "  foo\n  ")
    }

    /// 深度缩进也照原样（8 空格里回车还是 8 空格）。
    func testInheritsDeepIndent() {
        let text = "        deep"
        let plan = try! XCTUnwrap(newline(text, caret(length(text))))
        XCTAssertEqual(plan.applied(to: text), "        deep\n        ")
    }

    // MARK: - ② `{` `(` `[` 之后回车多一级

    func testOpenBraceAddsOneLevel() {
        let text = "if x {"
        let plan = try! XCTUnwrap(newline(text, caret(length(text))))
        XCTAssertEqual(plan.applied(to: text), "if x {\n" + unit)
    }

    func testOpenParenAddsOneLevel() {
        let text = "call("
        let plan = try! XCTUnwrap(newline(text, caret(length(text))))
        XCTAssertEqual(plan.applied(to: text), "call(\n" + unit)
    }

    func testOpenBracketAddsOneLevelOnTopOfIndent() {
        let text = "    items = ["
        let plan = try! XCTUnwrap(newline(text, caret(length(text))))
        XCTAssertEqual(plan.applied(to: text), "    items = [\n" + unit + unit)
    }

    /// 光标后面只剩空白也照样按 ② 加一级；那串空白留在**上一行**（不替用户删字符）。
    func testOpenBraceWithTrailingSpacesStillAddsLevel() {
        let text = "if x {   "
        let plan = try! XCTUnwrap(newline(text, caret(6)))
        XCTAssertEqual(plan.applied(to: text), "if x {\n" + unit + "   ")
        XCTAssertEqual(plan.caret, 6 + 1 + unit.count, "光标落在新行缩进之后、残留空白之前")
    }

    // MARK: - ③ 单独成行的 `}` `)` `]` 回退一级

    func testCloserLineDedentsOneLevel() {
        let text = "        }"
        let plan = try! XCTUnwrap(newline(text, caret(length(text))))
        XCTAssertEqual(plan.applied(to: text), "        }\n" + unit, "闭合行回车回到上一级（8 → 4）")
    }

    func testNestedCloserDedentsOneLevel() {
        let text = "            )"
        let plan = try! XCTUnwrap(newline(text, caret(length(text))))
        XCTAssertEqual(plan.applied(to: text), "            )\n" + unit + unit, "12 → 8，只退一级")
    }

    /// ② ③ 同时成立（`} else {`）：先按 ③ 退一级、再按 ② 进一级 ⇒ 结果回到本行那一级。
    func testCloserElseBraceReturnsToLineLevel() {
        let text = "    } else {"
        let plan = try! XCTUnwrap(newline(text, caret(length(text))))
        XCTAssertEqual(plan.applied(to: text), "    } else {\n    ")
    }

    /// 闭合行本来就顶格：退无可退时**不造出负缩进**，也没有可继承的缩进 ⇒ `nil`（交还系统，
    /// 默认回车落出来的正好是同一条）。

    func testCloserLineAtColumnZeroReturnsNil() {
        let text = "    body\n}"
        XCTAssertNil(newline(text, caret(length(text))))
    }

    // MARK: - 光标夹在一对括号中间：把闭合符挪到下一行

    func testSplitsBetweenMatchedBrackets() {
        let text = "{}"
        let plan = try! XCTUnwrap(newline(text, caret(1)))
        XCTAssertEqual(plan.applied(to: text), "{\n" + unit + "\n}", "内层缩进一级、闭合符落在行首")
        XCTAssertEqual(plan.caret, 1 + 1 + unit.count, "光标停在内层缩进之后")
    }

    /// 括号配错对（`[}`）不拆 —— 只认真正成对的那一组，别的交还系统。
    func testDoesNotSplitMismatchedBrackets() {
        XCTAssertNil(newline("[}", caret(1)))
    }

    // MARK: - 什么时候不动（nil = 交还系统默认回车）

    /// 光标后面还有正文（`if x { return`）：不猜，交还系统。
    func testCaretBeforeContentReturnsNil() {
        XCTAssertNil(newline("if x { return", caret(6)))
    }

    /// 有选区：不猜「这段换成什么」，交还系统。
    func testSelectionReturnsNil() {
        XCTAssertNil(newline("    foo\n    bar", NSRange(location: 4, length: 3)))
    }

    /// 顶格的普通行：没有可继承的缩进 ⇒ `nil`（系统默认回车落出来的就是同一个结果）。
    func testTopLevelPlainLineReturnsNil() {
        XCTAssertNil(newline("let x = 1", caret(9)))
    }

    /// 空文档 ⇒ `nil`（不许凭一个不存在的行算缩进）。
    func testEmptyDocumentReturnsNil() {
        XCTAssertNil(newline("", caret(0)))
    }

    // MARK: - 行终止符跟文档走

    /// `\r\n` 文档里回车**不许插出一个裸 `\n`**（插进去会让同一个文件混两种行尾）。
    func testCRLFDocumentKeepsCRLF() {
        let text = "    foo\r\n    bar"
        let plan = try! XCTUnwrap(newline(text, caret(7)))
        XCTAssertEqual(plan.applied(to: text), "    foo\r\n    \r\n    bar")
        XCTAssertEqual(plan.caret, 7 + 2 + unit.count)
    }

    /// 最后一行没有终止符时，退到文档里第一个终止符（而不是硬编码 `\n`）。
    func testLastLineWithoutTerminatorUsesDocumentTerminator() {
        let text = "a {\r\n    b {"
        let plan = try! XCTUnwrap(newline(text, caret(length(text))))
        XCTAssertEqual(plan.applied(to: text), "a {\r\n    b {\r\n" + unit + unit)
    }

    // MARK: - ④ 智能粘贴：剥外来缩进 + 接上下文缩进

    func testPasteStripsForeignIndentAndAdoptsContext() {
        let text = "    if x {\n    "
        let clip = "        a\n        b"
        let plan = try! XCTUnwrap(paste(clip, into: text, caret(length(text))))
        XCTAssertEqual(plan.applied(to: text), "    if x {\n    a\n    b")
        XCTAssertEqual(plan.caret, length(plan.applied(to: text)), "光标落在粘进来的内容末尾")
    }

    /// 外来块本来就没缩进（顶格块粘进缩进上下文）：整块接到上下文那一级上。
    func testPasteFlatBlockAdoptsContextIndent() {
        let text = "    body\n    "
        let plan = try! XCTUnwrap(paste("x\ny", into: text, caret(length(text))))
        XCTAssertEqual(plan.applied(to: text), "    body\n    x\n    y")
    }

    /// 空白行保持空白 —— **不留尾随空格**（那会被 diff 当成改动）。
    func testPasteKeepsBlankLinesBlank() {
        let text = "    body\n    "
        let clip = "        a\n\n        b"
        let plan = try! XCTUnwrap(paste(clip, into: text, caret(length(text))))
        XCTAssertEqual(plan.applied(to: text), "    body\n    a\n\n    b")
    }

    /// 块内**公共**缩进才剥：逐行各不相同的相对缩进（嵌套结构）原样保留。
    func testPastePreservesRelativeIndentInsideBlock() {
        let text = "  \n  "
        let clip = "        if x {\n            y\n        }"
        let plan = try! XCTUnwrap(paste(clip, into: text, caret(length(text))))
        XCTAssertEqual(plan.applied(to: text), "  \n  if x {\n      y\n  }")
    }

    /// 外来块的行尾换成文档自己的（`\r\n` 粘进 `\n` 文档 ⇒ 不混行尾）。
    func testPasteNormalizesNewlinesToDocumentTerminator() {
        let text = "  a\n  "
        let plan = try! XCTUnwrap(paste("x\r\ny", into: text, caret(length(text))))
        XCTAssertFalse(plan.replacement.contains("\r"), "文档是 `\n`，不许把 `\r` 带进来")
        XCTAssertEqual(plan.applied(to: text), "  a\n  x\n  y")
    }

    /// 单行粘贴一律不重排（`nil`）—— 「不硬塞缩进」不等于「替它改缩进」。
    func testPasteSingleLineReturnsNil() {
        XCTAssertNil(paste("  single", into: "    body\n    ", caret(13)))
    }

    /// 顶格粘到顶格：没有要改的 ⇒ `nil`（别把系统默认粘贴换成自己那一份）。
    func testPasteFlatToFlatReturnsNil() {
        XCTAssertNil(paste("x\ny", into: "a", caret(1)))
    }

    /// 有选区时替换选区、其余文本一个字不动。
    func testPasteReplacesSelectionOnly() {
        let text = "    a\n    zz"
        let range = NSRange(location: length(text) - 2, length: 2)
        let plan = try! XCTUnwrap(paste("p\nq", into: text, range))
        XCTAssertEqual(plan.applied(to: text), "    a\n    p\n    q")
        XCTAssertEqual(plan.range, range)
    }

    // MARK: - 界面接线（钉住「点在编辑器里真的走这条路」）

    /// `FR-STD-WS-EDIT-021` 必须在**两个编辑面**里真的在：回车与粘贴两条路都调 Core 的同一份判定，
    /// 且都经唯一落点（一次替换 = 一步撤销）。
    ///
    /// 为什么两个面都要：工作区编辑器与 SQL 编辑器是两个编辑面，只接一处会留下「同一个动作在两处表现不同」。
    func testEditorWiresAutoIndent() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let workspace = try String(contentsOf: root.appendingPathComponent("App/Views/CodeEditorView.swift"),
                                   encoding: .utf8)
        XCTAssertTrue(workspace.contains("AutoIndent.newline("), "回车要调 Core 的判定（不在界面里另写一套）")
        XCTAssertTrue(workspace.contains("AutoIndent.paste("), "粘贴同样走 Core")
        XCTAssertTrue(workspace.contains("override func paste(_ sender: Any?)"), "粘贴要真的拦到")
        XCTAssertTrue(workspace.contains("override func insertNewline(_ sender: Any?)"), "回车走 insertNewline")
        XCTAssertTrue(workspace.contains("func applyEditPlan("), "要有唯一落点（撤销 / 着色 / 模型都由它带上）")

        let sql = try String(contentsOf: root.appendingPathComponent("App/Views/SQLEditorView.swift"),
                             encoding: .utf8)
        XCTAssertTrue(sql.contains("AutoIndent.newline("), "SQL 编辑面同样继承缩进")
        XCTAssertTrue(sql.contains("AutoIndent.paste("), "SQL 编辑面同样重排粘贴缩进")
        XCTAssertTrue(sql.contains("func applyAutoIndentPlan("), "SQL 编辑面要有落点（一次替换、一步撤销）")
    }
}
