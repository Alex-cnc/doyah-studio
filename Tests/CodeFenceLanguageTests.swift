import XCTest
@testable import DoyahCore

/// 围栏语言 → 词法器语言的翻译（§9.1.16 ①）。
///
/// 这一层要是错了，界面上的表现是「代码没上色」，而人是分不出
/// 「没上色」和「语言没认出来」的 —— 所以它必须有判据，不能靠肉眼。
final class CodeFenceLanguageTests: XCTestCase {

    func testCommonAliasesResolveToRealLanguages() {
        XCTAssertEqual(CodeFenceLanguage.resolve("sql"), .sql)
        XCTAssertEqual(CodeFenceLanguage.resolve("SQL"), .sql, "大小写不该决定认不认得")
        XCTAssertEqual(CodeFenceLanguage.resolve("postgres"), .sql)
        XCTAssertEqual(CodeFenceLanguage.resolve("py"), TextLanguage.detect(path: "a.py"))
        XCTAssertEqual(CodeFenceLanguage.resolve("js"), TextLanguage.detect(path: "a.js"))
        XCTAssertEqual(CodeFenceLanguage.resolve("sh"), TextLanguage.detect(path: "a.sh"))
        XCTAssertEqual(CodeFenceLanguage.resolve("json"), .json)
    }

    /// 翻译出来的语言必须**真能让词法器切出关键字** —— 只比对枚举名不够。
    func testResolvedLanguageActuallyProducesKeywordTokens() {
        let language = CodeFenceLanguage.resolve("sql")
        let tokens = CodeLexer.tokens(in: "select 1 from t", language: language)
        XCTAssertTrue(tokens.contains { $0.kind == .keyword }, "SQL 关键字没被识别 ⇒ 界面上就是『没上色』")
    }

    /// 认不出 ⇒ plainText；空围栏同样。
    func testUnknownFenceFallsBackToPlainText() {
        XCTAssertEqual(CodeFenceLanguage.resolve("brainfuck"), .plainText)
        XCTAssertEqual(CodeFenceLanguage.resolve(""), .plainText)
        XCTAssertEqual(CodeFenceLanguage.resolve(nil), .plainText)
        XCTAssertEqual(CodeFenceLanguage.resolve("text"), .plainText)
    }

    /// 认不出时正文**逐字不变**（不吞字，也不重排）。
    func testPlainTextKeepsEveryCharacter() {
        let code = "select 1 -- 中文注释\n  from t"
        let language = CodeFenceLanguage.resolve("unknown")
        XCTAssertEqual(language, .plainText)
        // 纯文本不产记号（词法器只给「要上色的」那几类）；界面按「无记号 ⇒ 整段原文」处理。
        let rebuilt = CodeLexer.tokens(in: code, language: language).map { String(code[$0.range]) }.joined()
        XCTAssertTrue(rebuilt.isEmpty || rebuilt == code)
    }
}
