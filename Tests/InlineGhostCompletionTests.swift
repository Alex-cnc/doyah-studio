import XCTest
@testable import DoyahCore

/// 行内灰字补全（`FR-EDIT-57` 的**行内**形态）。
///
/// 这一族的判据全是"该不该出 / 出的是什么 / 接受了变成什么"—— 也就是用户按 Tab 前后
/// 正文长什么样。观感（灰得多淡、跟不跟手）不在这里判，归人工点验。
final class InlineGhostCompletionTests: XCTestCase {

    private func ghost(
        _ text: String,
        caret: Int? = nil,
        language: TextLanguage = .javascript,
        words: [String] = [],
        selectionLength: Int = 0,
        enabled: Bool = true
    ) -> InlineGhostSuggestion? {
        let location = caret ?? (text as NSString).length
        return InlineGhostCompletion.suggestion(
            in: text,
            selection: NSRange(location: location, length: selectionLength),
            language: language,
            documentWords: words,
            enabled: enabled
        )
    }

    // MARK: 该出的时候出

    /// 敲 `ret` ⇒ 灰字 `urn`，接受后整词是 `return`（范围 = 已输入的那 3 个字符）。
    func testKeywordGivesGhostSuffix() {
        let suggestion = ghost("let x = ret")
        XCTAssertEqual(suggestion?.ghost, "urn")
        XCTAssertEqual(suggestion?.insertText, "return")
        XCTAssertEqual(suggestion?.kind, .keyword)
        XCTAssertEqual(suggestion?.range, NSRange(location: 8, length: 3))
        // 接受后光标在 `return` 末尾：`let x = ` 8 个字符 + `return` 6 个字符。
        XCTAssertEqual(suggestion?.caretOffset, 14)
    }

    /// 前缀只在当前这个词里 —— 前面隔着标点也算（`a.ret` 的补全不该带上 `a.`）。
    func testGhostReplacesOnlyTheCurrentWord() {
        let suggestion = ghost("a.ret")
        XCTAssertEqual(suggestion?.range, NSRange(location: 2, length: 3))
        let text = "a.ret" as NSString
        XCTAssertEqual(text.replacingCharacters(in: suggestion!.range, with: suggestion!.insertText), "a.return")
    }

    /// 文档里出现过的词也进灰字（候选顺序：关键字 → 片段 → 内置 → 文档词，与候选列表同一份）。
    func testDocumentWordGivesGhost() {
        let suggestion = ghost("retr", words: ["retryCount"])
        XCTAssertEqual(suggestion?.insertText, "retryCount")
        XCTAssertEqual(suggestion?.ghost, "yCount")
        XCTAssertEqual(suggestion?.kind, .word)
    }

    /// 大小写不敏感的语言里，**大小写逐字相同**才给灰字（SQL 关键字是大写）。
    func testCaseInsensitiveLanguageStillRequiresExactCase() {
        XCTAssertNil(ghost("sel", language: .sql), "`sel` + `ECT` 会拼成一个不存在的词，宁可不提示")
        let upper = ghost("SEL", language: .sql)
        XCTAssertEqual(upper?.insertText, "SELECT")
        XCTAssertEqual(upper?.ghost, "ECT")
    }

    /// 接受后的光标落在插入文本末尾（灰字只收单行，所以就是末尾）。
    func testCaretOffsetIsEndOfInsertText() {
        let suggestion = ghost("con", language: .javascript)
        XCTAssertEqual(suggestion?.insertText, "const")
        XCTAssertEqual(suggestion?.caretOffset, 5)
    }

    // MARK: 不该出的时候一个都不出（负例）

    /// 前缀太短（一个字就往下猜 = 替用户写代码）。
    func testShortPrefixGivesNothing() {
        XCTAssertNil(ghost("r"))
        XCTAssertNil(ghost("let r"))
        XCTAssertNil(ghost(""))
    }

    /// 纯数字不是补全。
    func testNumberPrefixGivesNothing() {
        XCTAssertNil(ghost("x = 12"))
    }

    /// 光标在词中间（右边还是词字符）⇒ 用户在改这个词，不是等补全。
    func testCaretInsideWordGivesNothing() {
        XCTAssertNil(ghost("return", caret: 3))
        XCTAssertNil(ghost("let returnValue", caret: 7))
    }

    /// 有选区 ⇒ 不出（一按 Tab 就把选中内容换掉是最坏的"智能"）。
    func testSelectionGivesNothing() {
        XCTAssertNil(ghost("return", caret: 3, selectionLength: 3))
    }

    /// 没有候选 ⇒ 不出（不许硬凑一个"最像的"）。
    func testUnknownPrefixGivesNothing() {
        XCTAssertNil(ghost("let zzzzq"))
    }

    /// 多行片段不画（行内建议的语义是"把这个词补完"，不是"插一段代码"）。
    ///
    /// Python 的 `def` 三个候选都不该落成灰字：关键字 `def` 与前缀**完全相同**（没有可补的部分）、
    /// 片段 `def name():⏎` 是多行。
    func testMultiLineSnippetNeverGhosts() {
        XCTAssertNil(ghost("def", language: .python))
    }

    /// 灰字超长不画（会把整行挤出屏幕）。上限 24 个字符，这里给 25。
    func testOverlongGhostGivesNothing() {
        XCTAssertNil(ghost("retr", words: ["retryCountFromTheServerSideXY"]))
        // 边界：正好 24 个字符仍然要画。
        XCTAssertEqual(ghost("retr", words: ["retryCountFromTheServerSideX"])?.ghost,
                       "yCountFromTheServerSideX")
    }

    /// 本行是注释 ⇒ 不出。
    func testInsideLineCommentGivesNothing() {
        XCTAssertNil(ghost("// ret"))
        XCTAssertNil(ghost("x = 1 // ret"))
    }

    /// 本行在字符串里 ⇒ 不出。
    func testInsideStringGivesNothing() {
        XCTAssertNil(ghost("\"ret\""))
        XCTAssertNil(ghost("const s = \"ret"))
    }

    /// 注释结束之后的那一段又该出了（判定不是"这一行有注释就整行闭嘴"）。
    func testAfterCommentEndsGhostComesBack() {
        // `*/` 之后的 `ret` 在注释外 —— 本行词法把它切成了普通标识符。
        XCTAssertEqual(ghost("/* note */ ret", language: .javascript)?.ghost, "urn")
    }

    /// 总开关关掉 ⇒ 一个候选都不算。
    func testDisabledGivesNothing() {
        XCTAssertNil(ghost("let x = ret", enabled: false))
    }

    /// 光标越界（理论上不会有）夹回文档，而不是算出一段不存在的文本。
    func testOutOfRangeCaretIsClamped() {
        let suggestion = InlineGhostCompletion.suggestion(
            in: "ret",
            selection: NSRange(location: 99, length: 0),
            language: .javascript
        )
        XCTAssertEqual(suggestion?.insertText, "return")
        XCTAssertEqual(suggestion?.range, NSRange(location: 0, length: 3))
    }

    // MARK: 候选只有一处（与候选列表同源）

    /// `words(inTokens:)` 与 `words(in:language:)` 必须给出**同一个列表** ——
    /// 前者是每次击键那条路（拿高亮那一拍已经切好的记号），后者是候选列表那条路。
    /// 两条路各算一套，用户在灰字里看到的词和按 ⌃Space 看到的词就会不一样。
    func testWordsFromTokensMatchWholeTextPath() {
        let text = """
        let retryCount = 0
        let counter = retryCount + 1
        // retryCount 在注释里，不算
        let s = "counterValue"
        """
        let byTokens = CodeCompletion.words(
            inTokens: CodeLexer.tokens(in: text, language: .javascript),
            text: text
        )
        XCTAssertEqual(byTokens, CodeCompletion.words(in: text, language: .javascript))
        XCTAssertTrue(byTokens.contains("retryCount"))
        XCTAssertFalse(byTokens.contains("counterValue"), "字符串里的词不是候选")
    }
}
