import XCTest
@testable import DoyahCore

/// 移行与复制行（`FR-STD-WS-EDIT-009`）：`⌥↑` / `⌥↓` 整行（或整段）上移 / 下移，`⇧⌥↓` 向下复制。
///
/// 判据形态与其余编辑动作族一致：「给『文本 + 选区』要『期望文本 + 期望选区』」。
/// 这族最容易错的三件事各自有判据钉住：
/// · **行终止符算谁的**（`\r\n` 与「末行没有终止符」两条）；
/// · **光标 / 选区跟不跟**（不是加常数，多行长短不一时才看得出来）；
/// · **边界**（首行上移 / 末行下移 = 无操作且不报错，需求 ④）。
final class LineMoveEditTests: XCTestCase {

    private func apply(_ plan: LineMovePlan, to text: String) -> String {
        (text as NSString).replacingCharacters(in: plan.range, with: plan.replacement)
    }

    private func caret(_ offset: Int) -> NSRange { NSRange(location: offset, length: 0) }

    private func move(_ text: String, _ range: NSRange, _ direction: LineMoveDirection) -> LineMovePlan? {
        LineMoveEdit.move(in: text, selection: range, direction: direction)
    }

    // MARK: - ① 单行上移 / 下移，光标跟随

    /// 最日常的那一条：光标在第 1 行，`⌥↓` ⇒ 与下一行交换，光标跟着走到原行新位置。
    func testMovesLineDownAndCaretFollows() {
        let text = "a\nb\nc"
        let plan = try! XCTUnwrap(move(text, caret(0), .down))
        XCTAssertEqual(apply(plan, to: text), "b\na\nc")
        XCTAssertEqual(plan.caret, 2, "光标跟着「a」那一行走（不是留在行号 1 上）")
        XCTAssertEqual(plan.selectionLength, 0)
    }

    /// 反向：光标在第 2 行，`⌥↑` ⇒ 与上一行交换，光标回到行首。
    func testMovesLineUpAndCaretFollows() {
        let text = "a\nb\nc"
        let plan = try! XCTUnwrap(move(text, caret(2), .up))
        XCTAssertEqual(apply(plan, to: text), "b\na\nc")
        XCTAssertEqual(plan.caret, 0)
    }

    /// 行内位置也要跟着走：光标在「b」行第 1 个字符处，下移之后仍在该行同一个字符上。
    func testCaretKeepsInLineOffset() {
        let text = "a\nbcd\ne"
        let plan = try! XCTUnwrap(move(text, caret(3), .down))   // "bcd" 的 'c'
        XCTAssertEqual(apply(plan, to: text), "a\ne\nbcd")
        XCTAssertEqual(plan.caret, 5, "bcd 现在从 4 起、行内偏移 1 ⇒ 光标落在 'c' 上（不是行首）")
    }

    // MARK: - ② 多行选区整段移动

    /// 选中后两行 ⇒ **整段**上移一行（段内顺序不变：`c` 仍在 `d` 前）。
    func testMovesSelectedBlockUpAsAWhole() {
        let text = "a\nb\nc\nd"
        let plan = try! XCTUnwrap(move(text, NSRange(location: 4, length: 3), .up))
        XCTAssertEqual(apply(plan, to: text), "a\nc\nd\nb")
        XCTAssertEqual(plan.caret, 2, "选区跟着段一起走")
        XCTAssertEqual(plan.selectionLength, 3, "选中长度不变（还是那三个字符）")
    }

    /// 选中前两行 ⇒ 整段下移一行。
    func testMovesSelectedBlockDownAsAWhole() {
        let text = "a\nb\nc"
        let plan = try! XCTUnwrap(move(text, NSRange(location: 0, length: 3), .down))
        XCTAssertEqual(apply(plan, to: text), "c\na\nb")
        XCTAssertEqual(plan.caret, 2)
        XCTAssertEqual(plan.selectionLength, 3)
    }

    /// 选区终点落在**行首** ⇒ 那一行不算进来（与 `CodeCommentToggling` 同一套取法）。
    /// 判据：`"a\n"` 这一段只覆盖第 1 行，`⌥↓` 只换第 1、2 行 —— 第 3 行原封不动。
    func testSelectionEndingAtLineStartDoesNotIncludeThatLine() {
        let text = "a\nb\nc"
        let plan = try! XCTUnwrap(move(text, NSRange(location: 0, length: 2), .down))
        XCTAssertEqual(apply(plan, to: text), "b\na\nc")
    }

    // MARK: - ③ 向下复制（⇧⌥↓）

    /// 副本**紧随原行**，选区留在原件上（连按得到 N 份、光标不往下跑）。
    func testDuplicatePutsCopyRightAfterAndKeepsSelectionOnOriginal() {
        let text = "a\nb\nc"
        let plan = try! XCTUnwrap(LineMoveEdit.duplicate(in: text, selection: caret(2)))
        XCTAssertEqual(apply(plan, to: text), "a\nb\nb\nc")
        XCTAssertEqual(plan.caret, 2, "选区留在原件（不是跳到副本上）")
        XCTAssertEqual(plan.selectionLength, 0)
    }

    /// 末行**没有行终止符**时，副本要先借一个终止符，否则两份会粘成一行（`ab` 而不是 `a` / `b`）。
    func testDuplicateLastLineWithoutTrailingNewline() {
        let text = "a\nb"
        let plan = try! XCTUnwrap(LineMoveEdit.duplicate(in: text, selection: caret(2)))
        XCTAssertEqual(apply(plan, to: text), "a\nb\nb")
    }

    /// 整段复制：副本整段紧随其后。
    func testDuplicateSelectedBlock() {
        let text = "a\nb\nc"
        let plan = try! XCTUnwrap(LineMoveEdit.duplicate(in: text, selection: NSRange(location: 0, length: 3)))
        XCTAssertEqual(apply(plan, to: text), "a\nb\na\nb\nc")
        XCTAssertEqual(plan.caret, 0)
        XCTAssertEqual(plan.selectionLength, 3)
    }

    /// 单行文档复制：`"abc"` ⇒ `"abc\nabc"`（末尾有没有换行不影响语义，只影响借谁的终止符）。
    func testDuplicateSingleLineDocument() {
        let text = "abc"
        let plan = try! XCTUnwrap(LineMoveEdit.duplicate(in: text, selection: caret(1)))
        XCTAssertEqual(apply(plan, to: text), "abc\nabc")
    }

    // MARK: - ④ 边界：首行上移 / 末行下移 = 无操作且不报错

    func testFirstLineCannotMoveUp() {
        XCTAssertNil(move("a\nb", caret(0), .up))
    }

    func testLastLineCannotMoveDown() {
        XCTAssertNil(move("a\nb", caret(2), .down))
    }

    /// 末尾多一个空行（`"a\n"` 的第 2 行）也是「最后一行」—— 它同样不能下移。
    func testTrailingEmptyLineIsTheLastLine() {
        let text = "a\n"
        XCTAssertNil(move(text, caret(2), .down))
        let plan = try! XCTUnwrap(move(text, caret(2), .up))
        XCTAssertEqual(apply(plan, to: text), "\na", "空行上移：终止符按位置留 ⇒ 文档末尾仍然没有换行")
    }

    /// 空文档：三个动作都交还系统（不崩、不写东西）。
    func testEmptyDocumentIsNoOp() {
        XCTAssertNil(move("", caret(0), .up))
        XCTAssertNil(move("", caret(0), .down))
        XCTAssertNil(LineMoveEdit.duplicate(in: "", selection: caret(0)))
    }

    // MARK: - ⑤ 空行同样可移 / 可复制

    func testBlankLineMovesUpLikeAnyOtherLine() {
        let text = "a\n\nc"
        let plan = try! XCTUnwrap(move(text, caret(2), .up))
        XCTAssertEqual(apply(plan, to: text), "\na\nc")
        XCTAssertEqual(plan.caret, 0)
    }

    func testBlankLineDuplicates() {
        let text = "a\n\nc"
        let plan = try! XCTUnwrap(LineMoveEdit.duplicate(in: text, selection: caret(2)))
        XCTAssertEqual(apply(plan, to: text), "a\n\n\nc")
    }

    // MARK: - 行终止符口径（`\r\n` 两字节 / 末行没有终止符）

    /// `\r\n` 必须整块跟着走：只搬 `\n` 会留下一个孤立 `\r`，两行会粘成 `"ba\r\n"`。
    func testCRLFLineEndingsTravelWithTheLine() {
        let text = "a\r\nb\r\nc"
        let plan = try! XCTUnwrap(move(text, caret(0), .down))
        XCTAssertEqual(apply(plan, to: text), "b\r\na\r\nc")
        XCTAssertEqual(plan.caret, 3, "跨一行是三个 UTF-16 单元（`b` + `\\r\\n`），不是两个")
    }

    /// 末行没有终止符时上移：**不能**把它和上一行粘起来，也不能凭空造出一个末尾换行。
    func testMovingUnterminatedLastLineKeepsDocumentTailShape() {
        let text = "a\nb"
        let plan = try! XCTUnwrap(move(text, caret(2), .up))
        XCTAssertEqual(apply(plan, to: text), "b\na")
        XCTAssertFalse(apply(plan, to: text).hasSuffix("\n"), "文档末尾原本没有换行，移完也不许有")
    }

    /// 文档末尾那个**空行**（`"a\nb\nc\n"` 的第 4 行）也是一行：`⌥↓` 会与它交换。
    /// 终止符按位置留 ⇒ 末行从此是 `c`、且**没有**终止符（形状随内容走，不是被谁写死）。
    func testMovingLineIntoTrailingBlankLineSwapsWithIt() {
        let text = "a\nb\nc\n"
        let plan = try! XCTUnwrap(move(text, caret(4), .down))
        XCTAssertEqual(apply(plan, to: text), "a\nb\n\nc")
        XCTAssertFalse(apply(plan, to: text).hasSuffix("\n"))
    }

    // MARK: - 一次替换 / 可逆

    /// 必须是**一次**整块替换，不是几次小替换 —— 否则 ⌘Z 要按好几下（与注释切换同一条纪律）。
    func testPlanIsOneSingleBlockReplacement() {
        let text = "a\nb\nc\nd"
        let plan = try! XCTUnwrap(move(text, NSRange(location: 4, length: 3), .up))
        XCTAssertEqual(plan.range, NSRange(location: 2, length: 5), "覆盖「上一行 + 整段」")
    }

    /// 下移再上移 ⇒ 文本与光标都回到原样（反向动作真的互为逆）。
    func testMoveDownThenUpRestoresTextAndCaret() {
        let text = "alpha\nbeta\ngamma\ndelta"
        let down = try! XCTUnwrap(move(text, NSRange(location: 6, length: 4), .down))
        let afterDown = apply(down, to: text)
        let up = try! XCTUnwrap(move(afterDown, NSRange(location: down.caret, length: down.selectionLength), .up))
        XCTAssertEqual(apply(up, to: afterDown), text)
        XCTAssertEqual(up.caret, 6, "光标回到原处")
        XCTAssertEqual(up.selectionLength, 4)
    }

    // MARK: - 接线判据（源码扫描：Core 有了，界面别掉链子）

    /// `FR-STD-WS-EDIT-009` 必须在编辑器里**真的在**：三个按键 + 唯一落点 + 判定只在 Core。
    ///
    /// 特别钉住「在 `keyDown` 里拦」：`⌥` 方向键不走 `performKeyEquivalent`，
    /// 写在那边等于没接（按了没反应，且没有任何提示）。
    func testEditorWiresLineMove() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("App/Views/CodeEditorView.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(source.contains("override func keyDown(with event: NSEvent)"),
                      "⌥ 方向键要在 keyDown 里拦（performKeyEquivalent 收不到）")
        XCTAssertTrue(source.contains("LineMoveEdit.move(") , "要调 Core 的判定，不许在界面里另写一套")
        XCTAssertTrue(source.contains("LineMoveEdit.duplicate("), "复制行同样走 Core")
        XCTAssertTrue(source.contains("func moveLines("), "要有移行的落点方法")
        XCTAssertTrue(source.contains("func duplicateLines("), "要有复制行的落点方法")
        XCTAssertTrue(source.contains("specialKey"), "按方向键判键，不按字符判（⌥↑ 没有可读字符）")
        XCTAssertTrue(source.contains("func applyEditPlan("), "要有唯一落点（撤销 / 着色 / 模型都由它带上）")
    }
}
