import XCTest
@testable import DoyahCore

/// Markdown 编辑手感（`FR-MD-01` 列表续行 / `FR-MD-02` 任务勾选翻转）。
///
/// 判据形态 = 「给『文本 + 光标』要『期望文本 + 期望光标』」：这一族最容易错的就是
/// **光标差半个字符**（少一个空格的 `-item`、多一个空格的 `-  item` 都是错，
/// 而两者在界面上都不显眼），所以每条都同时钉「文本」与「光标」。
final class MarkdownEditingTests: XCTestCase {

    // MARK: - 小工具

    private func continuation(_ text: String, caret: Int) -> MarkdownEditPlan? {
        MarkdownListEditing.continuation(in: text, selection: NSRange(location: caret, length: 0))
    }

    private func toggle(_ text: String, caret: Int) -> MarkdownEditPlan? {
        MarkdownListEditing.toggleTask(in: text, selection: NSRange(location: caret, length: 0))
    }

    /// 把计划落到文本上（宿主层做的就是这件事）。
    private func apply(_ plan: MarkdownEditPlan, to text: String) -> String {
        (text as NSString).replacingCharacters(in: plan.range, with: plan.replacement)
    }

    // MARK: - 续行（FR-MD-01）

    /// 最日常的那一条：`- ` 回车接着写下一项，光标停在新条目的标记之后。
    func testBulletContinuesWithSameMarker() {
        let text = "- 买牛奶"
        let plan = try! XCTUnwrap(continuation(text, caret: (text as NSString).length))
        XCTAssertEqual(plan.replacement, "\n- ")
        XCTAssertEqual(plan.range, NSRange(location: 5, length: 0), "插入点在光标处（不吞掉已有内容）")
        XCTAssertEqual(apply(plan, to: text), "- 买牛奶\n- ")
        XCTAssertEqual(plan.caret, 8, "光标停在新标记之后 —— 差一个字符就要多按一次方向键")
    }

    /// 三种无序符号都续（用户用哪个就跟着用哪个）。
    func testAllThreeBulletCharsContinue() {
        for bullet in ["- ", "* ", "+ "] {
            let text = bullet + "甲"
            let plan = continuation(text, caret: (text as NSString).length)
            XCTAssertEqual(plan?.replacement, "\n" + bullet, "`\(bullet)` 没续上")
        }
    }

    /// 缩进与引用号原样跟着走（`> ` / `> > ` / 两个空格的嵌套列表）。
    func testIndentAndQuoteMarkersArePreserved() {
        let cases = ["  - 甲", "\t- 甲", "> - 甲", "> > * 甲", "  > - 甲"]
        for text in cases {
            let plan = continuation(text, caret: (text as NSString).length)
            let prefix = text.replacingOccurrences(of: "甲", with: "")
            XCTAssertEqual(plan?.replacement, "\n" + prefix, "`\(text)` 的前缀没原样带下来")
        }
    }

    /// 有序列表编号递增；分隔符（`.` / `)`）跟着用户自己敲的那个。
    func testOrderedListNumberIncrements() {
        let cases: [(String, String)] = [
            ("1. 甲", "\n2. "),
            ("9. 甲", "\n10. "),
            ("17. 甲", "\n18. "),
            ("3) 甲", "\n4) "),
            ("  > 9. 甲", "\n  > 10. ")
        ]
        for (text, expected) in cases {
            let plan = continuation(text, caret: (text as NSString).length)
            XCTAssertEqual(plan?.replacement, expected, "`\(text)` 的下一项不对")
        }
    }

    /// 任务项续出来的是**未勾选**的新条目 —— 回车接着写的是下一件事，不是又一件已完成的事。
    func testTaskItemContinuesUnchecked() {
        for source in ["- [x] 洗车", "- [X] 洗车", "- [ ] 洗车", "1. [ ] 洗车"] {
            let plan = continuation(source, caret: (source as NSString).length)
            let expected = source.hasPrefix("1.") ? "\n2. [ ] " : "\n- [ ] "
            XCTAssertEqual(plan?.replacement, expected, "`\(source)` 续出来的新条目不对")
        }
    }

    /// 空条目回车 = **退出列表**：整条前缀一起去掉，得到一行空行。
    func testEmptyItemExitsTheList() {
        for text in ["- ", "* ", "+ ", "- [ ] ", "- [x] ", "1. ", "  - ", "> - [ ] "] {
            let caret = (text as NSString).length
            let plan = try! XCTUnwrap(continuation(text, caret: caret), "`\(text)` 应当退出列表")
            XCTAssertEqual(plan.range, NSRange(location: 0, length: caret), "`\(text)` 要整条前缀一起去掉")
            XCTAssertEqual(plan.replacement, "")
            XCTAssertEqual(plan.caret, 0)
            XCTAssertEqual(apply(plan, to: text), "", "`\(text)` 退完应当是一行空行")
        }
    }

    /// 空任务项**没有尾随空格**时同样退出（`- [ ]` 直接顶到行尾是最常见的写法）。
    func testEmptyTaskWithoutTrailingSpaceExitsToo() {
        let text = "- [ ]"
        let plan = try! XCTUnwrap(continuation(text, caret: text.count))
        XCTAssertEqual(plan.range, NSRange(location: 0, length: 5))
        XCTAssertEqual(apply(plan, to: text), "")
    }

    /// 不是列表项 ⇒ 交还给普通换行（`nil`；不是失败，是「这条口径不适用」）。
    func testNonListLinesAreLeftToPlainNewline() {
        let cases = ["普通一行", "-x", "--", "* * *", "---", "___", "1.x", "1.甲", "> 引用", "# 标题"]
        for text in cases {
            XCTAssertNil(continuation(text, caret: (text as NSString).length), "`\(text)` 不该被当成列表项")
        }
    }

    /// 标记还没敲完（光标在标记内部）⇒ 这一下回车就是普通换行。
    func testCaretInsideTheMarkerIsAPlainNewline() {
        XCTAssertNil(continuation("- 甲", caret: 0))
        XCTAssertNil(continuation("- 甲", caret: 1), "光标卡在 `-` 与空格之间")
        XCTAssertNil(continuation("- [ ] 甲", caret: 3), "光标在任务框内部")
        XCTAssertNotNil(continuation("- 甲", caret: 2), "光标到了标记之后就该续")
    }

    /// 光标在行中 ⇒ 在光标处断开（后面的尾巴跟着新前缀走），不是插到行尾。
    func testCaretInTheMiddleSplitsAndKeepsTheTail() {
        let text = "- 一二三"          // UTF-16：- 空格 一 二 三
        let plan = try! XCTUnwrap(continuation(text, caret: 4))
        XCTAssertEqual(plan.range, NSRange(location: 4, length: 0), "插入点在光标处——不许挪到行尾")
        XCTAssertEqual(apply(plan, to: text), "- 一二\n- 三")
        XCTAssertEqual(plan.caret, 7)
    }

    /// 有选区 ⇒ 那一下回车的意思是把选中的文字换掉，不是续行。
    func testSelectionIsNotAContinuation() {
        let text = "- 甲乙"
        XCTAssertNil(MarkdownListEditing.continuation(in: text, selection: NSRange(location: 2, length: 2)))
        XCTAssertNil(MarkdownListEditing.toggleTask(in: text, selection: NSRange(location: 2, length: 2)))
    }

    /// 只有 Markdown 吃这一族手感：YAML / 纯文本 / SQL 里一个字都不许动。
    func testTheScopeIsMarkdownOnly() {
        XCTAssertTrue(MarkdownEditingScope.applies(to: .markdown))
        for language in [TextLanguage.plainText, .yaml, .shell, .sql, .swift] {
            XCTAssertFalse(MarkdownEditingScope.applies(to: language), "`\(language.rawValue)` 不该续行")
        }
    }

    // MARK: - 任务勾选翻转（FR-MD-02）

    func testToggleFlipsBothWays() {
        let unchecked = "- [ ] 洗车"
        let plan = try! XCTUnwrap(toggle(unchecked, caret: (unchecked as NSString).length))
        XCTAssertEqual(plan.range, NSRange(location: 3, length: 1), "只动方框里那一个字符 —— 方括号本身不许碰")
        XCTAssertEqual(apply(plan, to: unchecked), "- [x] 洗车")

        for checked in ["- [x] 洗车", "- [X] 洗车", "  > - [x] 洗车"] {
            let plan = try! XCTUnwrap(toggle(checked, caret: 3), "`\(checked)` 应当能取消勾选")
            XCTAssertTrue(apply(plan, to: checked).contains("[ ]"), "`\(checked)` 没翻回来")
        }
    }

    /// 翻转是**等长**替换 ⇒ 光标不用动（不动光标才不会把用户的选区搅乱）。
    func testToggleIsLengthPreservingAndKeepsTheCaret() {
        let text = "- [ ] 甲乙丙"
        for caret in [0, 3, 6, (text as NSString).length] {
            let plan = try! XCTUnwrap(toggle(text, caret: caret))
            XCTAssertEqual((plan.replacement as NSString).length, 1, "只换方框里的那一个字符")
            XCTAssertEqual(plan.caret, caret)
            XCTAssertEqual((apply(plan, to: text) as NSString).length, (text as NSString).length)
        }
    }

    /// 勾的是**光标所在那一行** —— 同一份文档里别的任务框一个都不许动。
    func testToggleAffectsOnlyTheCaretLine() {
        let text = "- [x] 甲\n- [ ] 乙\n- [x] 丙"
        let caret = (text as NSString).length - 3           // 落在最后一行
        let plan = try! XCTUnwrap(toggle(text, caret: caret))
        XCTAssertEqual(apply(plan, to: text), "- [x] 甲\n- [ ] 乙\n- [ ] 丙")
    }

    /// 不是任务行 ⇒ 不吞这一下按键（交还给系统）。
    func testToggleOnANonTaskLineIsNotSwallowed() {
        for text in ["- 甲", "普通一行", "1. 甲", "[x] 没有列表标记"] {
            XCTAssertNil(toggle(text, caret: (text as NSString).length), "`\(text)` 不该被当成任务行")
        }
    }

    // MARK: - 接线（源码判据）

    /// 宿主必须**真的**把这两件事接上 —— 纯逻辑写好了却没人调用，是这一族最典型的假绿
    /// （判据全绿、界面上一处都没接）。判法 = 在源码里钉锚点（剥注释后再判，注释里写着
    /// 标识名不算接线）。
    func testHostWiringUsesTheEditorHandfeel() {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let editor = Self.stripComments(
            try! String(contentsOf: root.appendingPathComponent("App/Views/CodeEditorView.swift"), encoding: .utf8)
        )
        XCTAssertTrue(editor.contains("MarkdownListEditing.continuation"), "回车续行要接在编辑器里")
        XCTAssertTrue(editor.contains("MarkdownListEditing.toggleTask"), "勾选翻转要接在编辑器里")
        XCTAssertTrue(editor.contains("MarkdownEditingScope.applies"), "生效范围要经唯一出处判（不许在视图里自己判语言）")
        XCTAssertTrue(editor.contains("override func insertNewline"), "回车走的是 insertNewline 这一条路")
        XCTAssertFalse(
            editor.contains("allowsNonContiguousLayout = MarkdownEditingScope"),
            "这条锚点防的是「把两件事写串」——非连续布局与编辑手感不是一回事"
        )
    }

    /// 剥注释（`//` 与 `///` 行、`/* */` 块）。
    private static func stripComments(_ source: String) -> String {
        var output: [String] = []
        var inBlock = false
        for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if inBlock {
                if trimmed.contains("*/") { inBlock = false }
                continue
            }
            if trimmed.hasPrefix("/*") {
                inBlock = !trimmed.contains("*/")
                continue
            }
            if trimmed.hasPrefix("//") { continue }
            output.append(String(line))
        }
        return output.joined(separator: "\n")
    }
}
