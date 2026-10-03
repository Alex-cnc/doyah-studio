import XCTest
@testable import DoyahCore

/// 语言登记表（FR-EDIT-38 ① / ② / ④）。
///
/// 这一族测的不是"某段代码能不能着色"，而是**表自己的自洽**：语言标识 ↔ 登记项同集合、
/// 扩展名不打架、`isCode` 的语言必须给得出注释规则与字符串界定符、每条扩展名都真判得回去。
/// 表是全工程的唯一事实源 —— 表错了，往下全是错的（加一个语言而忘了给它注释规则，
/// 症状是"个别文件打开后一个颜色都没有"）。
final class CodeLanguageRegistryTests: XCTestCase {

    private func marked(_ text: String, _ language: TextLanguage) -> [(String, String)] {
        CodeLexer.highlightedTokens(in: text, language: language).map {
            ($0.kind.rawValue, String(text[$0.range]))
        }
    }

    private func punctuation(_ text: String, _ language: TextLanguage) -> [String] {
        CodeLexer.tokens(in: text, language: language)
            .filter { $0.kind == .punctuation }
            .map { String(text[$0.range]) }
    }

    // MARK: 标识 ↔ 登记项（"新增语言只动语言定义文件"的机械半边）

    func testEveryIdentifierHasExactlyOneDefinition() {
        let definitions = CodeLanguageRegistry.all
        let fromTable = definitions.map(\.language.rawValue)
        XCTAssertEqual(fromTable.count, Set(fromTable).count, "同一个语言被登记了两次：\(fromTable)")
        XCTAssertEqual(Set(fromTable), Set(TextLanguage.allCases.map(\.rawValue)),
                       "语言标识与登记项不是同一个集合（多一个 / 少一个都算）")
    }

    func testDefinitionLookupGoesBothWays() {
        for language in TextLanguage.allCases {
            XCTAssertEqual(language.definition.language, language, "\(language.rawValue) 取到的定义不是它自己")
            XCTAssertFalse(language.displayName.isEmpty, "\(language.rawValue) 没有显示名")
            XCTAssertNotNil(CodeLanguageRegistry.definition(id: language.rawValue))
        }
    }

    /// 没登记过的标识**不是语言** —— 不许静默造一个"看起来像语言"的东西。
    func testUnregisteredIdentifierIsNotALanguage() {
        XCTAssertNil(TextLanguage(rawValue: "cobol"))
        XCTAssertNil(TextLanguage(rawValue: ""))
        XCTAssertNotNil(TextLanguage(rawValue: "go"))
    }

    /// 一个扩展名 / 文件名只能有一个主人：两处抢同一个的结果是"判语言随表顺序变"。
    func testNoTwoLanguagesClaimTheSameExtension() {
        var owners: [String: String] = [:]
        for definition in CodeLanguageRegistry.all {
            for fileExtension in definition.fileExtensions {
                XCTAssertFalse(fileExtension.contains("."), "扩展名不带点：\(fileExtension)")
                XCTAssertEqual(fileExtension, fileExtension.lowercased(), "扩展名一律小写：\(fileExtension)")
                if let existing = owners[fileExtension] {
                    XCTFail("扩展名 .\(fileExtension) 同时属于 \(existing) 与 \(definition.language.rawValue)")
                }
                owners[fileExtension] = definition.language.rawValue
            }
        }
        var names: [String: String] = [:]
        for definition in CodeLanguageRegistry.all {
            for fileName in definition.fileNames {
                XCTAssertEqual(fileName, fileName.lowercased(), "文件名一律小写：\(fileName)")
                if let existing = names[fileName] {
                    XCTFail("文件名 \(fileName) 同时属于 \(existing) 与 \(definition.language.rawValue)")
                }
                names[fileName] = definition.language.rawValue
            }
        }
    }

    /// `isCode` 为真的语言必须给得出**注释规则**与**字符串界定符**：
    /// 两者缺一，用户看到的就是"识别了但一个颜色都没有"的空编辑器，而且不报错。
    func testCodeLanguagesDeclareCommentsAndStrings() {
        for definition in CodeLanguageRegistry.all where definition.isCode {
            XCTAssertFalse(definition.syntax.comments.isEmpty, "\(definition.language.rawValue) 是代码语言却没有注释规则")
            XCTAssertFalse(definition.syntax.stringDelimiters.isEmpty, "\(definition.language.rawValue) 是代码语言却没有字符串界定符")
            XCTAssertFalse(definition.syntax.keywordLookup.isEmpty, "\(definition.language.rawValue) 是代码语言却没有关键字表")
        }
    }

    /// 回落值**只有一条**（`plainText`）：CLI 的 `code-tokens --detect` 用退出码回答
    /// "判出来了没有"，问的就是这个字段 —— 数据说话，不是身份判断。
    func testExactlyOneDefinitionIsTheFallback() {
        XCTAssertEqual(CodeLanguageRegistry.all.filter(\.isFallback).map(\.language), [.plainText])
        XCTAssertTrue(TextLanguage.detect(path: "noextension").definition.isFallback)
        XCTAssertFalse(TextLanguage.detect(path: "main.go").definition.isFallback)
    }

    // MARK: 判语言（每条扩展名都判得回去 + 认不出如实纯文本）

    func testEveryExtensionAndFileNameRoundTripsThroughDetect() {
        for definition in CodeLanguageRegistry.all {
            for fileExtension in definition.fileExtensions {
                XCTAssertEqual(TextLanguage.detect(path: "file.\(fileExtension)"), definition.language,
                               ".\(fileExtension) 判不回去")
                XCTAssertEqual(TextLanguage.detect(path: "/tmp/项目/FILE.\(fileExtension.uppercased())"), definition.language,
                               "大写扩展名也要认（macOS 文件名不敏感）：.\(fileExtension)")
            }
            for fileName in definition.fileNames {
                XCTAssertEqual(TextLanguage.detect(path: "/Users/me/\(fileName)"), definition.language,
                               "\(fileName) 判不回去")
            }
        }
    }

    /// 文件名优先于扩展名；多段扩展名只看最后一段。
    func testDetectionOrderAndLastExtensionOnly() {
        XCTAssertEqual(TextLanguage.detect(path: "/Users/me/.zshrc"), .shell)
        XCTAssertEqual(TextLanguage.detect(path: "component.test.ts"), .typescript)
        XCTAssertEqual(TextLanguage.detect(path: "archive.sql.bak"), .plainText)
    }

    /// FR-EDIT-38 ④：认不出就**如实**回落纯文本，不硬安一个"看起来像"的语言。
    func testUnknownIsHonestlyPlainText() {
        XCTAssertEqual(TextLanguage.detect(path: ".gitignore"), .plainText)
        XCTAssertEqual(TextLanguage.detect(path: "noextension"), .plainText)
        XCTAssertEqual(TextLanguage.detect(path: ""), .plainText)
        XCTAssertEqual(TextLanguage.detect(path: "weird."), .plainText)
    }

    // MARK: 默认视图（FR-EDIT-36 消费者口径 / 队列 `L-149` 剩余②）

    /// 「用浏览器打开」这件事是**登记表里的数据**，不是工作区里的分支：
    /// 声明 `.browser` 的必须**恰好一条**（HTML），其余一律文本编辑器；且合成那份定义
    /// （`all` 带格式化能力）与 `definition(of:)` 取到的必须是同一个值（别在复制时丢掉）。
    func testDefaultViewIsDeclaredInTheRegistry() {
        let browserLanguages = CodeLanguageRegistry.all
            .filter { $0.defaultView == .browser }
            .map(\.language.rawValue)
        XCTAssertEqual(browserLanguages, ["html"], "声明「默认用浏览器打开」的语言必须恰好是 HTML：\(browserLanguages)")
        for definition in CodeLanguageRegistry.all {
            XCTAssertEqual(
                definition.defaultView,
                CodeLanguageRegistry.definition(of: definition.language).defaultView,
                "\(definition.language.rawValue) 两条路取到的默认视图不一致（合成定义时丢了字段）"
            )
        }
    }

    /// 工作区问的是「**这个路径**默认用哪种视图打开」—— 判语言那一步的回落就是这一档的答案。
    func testDefaultViewForPathUsesTheRegistry() {
        XCTAssertEqual(CodeLanguageRegistry.defaultView(forPath: "/Users/me/site/index.html"), .browser)
        XCTAssertEqual(CodeLanguageRegistry.defaultView(forPath: "page.htm"), .browser)
        XCTAssertEqual(CodeLanguageRegistry.defaultView(forPath: "INDEX.HTML"), .browser, "判语言不分大小写")
        XCTAssertEqual(CodeLanguageRegistry.defaultView(forPath: "template.xhtml"), .browser)

        // 其余一律文本编辑器 —— 包括认不出的（回落值也有自己的那一档，不许猜成浏览器）。
        XCTAssertEqual(CodeLanguageRegistry.defaultView(forPath: "notes.md"), .editor)
        XCTAssertEqual(CodeLanguageRegistry.defaultView(forPath: "schema.sql"), .editor)
        XCTAssertEqual(CodeLanguageRegistry.defaultView(forPath: "noextension"), .editor)
        XCTAssertEqual(CodeLanguageRegistry.defaultView(forPath: ""), .editor)
    }

    /// 纯文本的定义里一条规则都没有 —— 所以词法器对它零输出（连数字都不着色）。
    func testPlainTextHasNoRulesAndYieldsNoTokens() {
        let syntax = TextLanguage.plainText.definition.syntax
        XCTAssertTrue(syntax.keywordLookup.isEmpty)
        XCTAssertTrue(syntax.builtinLookup.isEmpty)
        XCTAssertTrue(syntax.comments.isEmpty)
        XCTAssertTrue(syntax.stringDelimiters.isEmpty)
        XCTAssertFalse(syntax.hasAnyRule)
        XCTAssertTrue(CodeLexer.tokens(in: "const x = 1 // 不是代码", language: .plainText).isEmpty)
    }

    // MARK: 覆盖面（FR-EDIT-38 ②：Alpha 2 = 常见编程语言前 10）

    /// 前 10 名逐条给样例文本：**着色表不是声明出来的，是量出来的** ——
    /// 每条都要真的分得出关键字 / 注释 / 字符串三类。
    func testAlphaTwoTopTenLanguagesHighlightTheirOwnCode() {
        let samples: [(TextLanguage, String, [String])] = [
            (.python, "def f():\n    \"\"\"doc\"\"\"\n    return 1  # 注释", ["def", "return"]),
            (.javascript, "const s = \"x\"; // 注释", ["const"]),
            (.typescript, "const s: string = \"x\"; // 注释", ["const", "string"]),
            (.java, "public class A { String s = \"x\"; } // 注释", ["public", "class", "String"]),
            (.c, "int main(void) { printf(\"x\"); } // 注释", ["int"]),
            (.cpp, "const char* s = \"x\"; // 注释", ["const"]),
            (.csharp, "public class A { string s = \"x\"; } // 注释", ["public", "class", "string"]),
            (.go, "package main\nfunc main() { s := \"x\" } // 注释", ["package", "func"]),
            (.rust, "fn main() { let s = \"x\"; } // 注释", ["fn", "let"]),
            (.php, "<?php function f() { return \"x\"; } // 注释", ["function", "return"])
        ]
        XCTAssertEqual(samples.count, 10, "Alpha 2 的口径是「常见编程语言前 10」")
        for (language, code, expectedKeywords) in samples {
            XCTAssertTrue(language.isCode, "\(language.rawValue) 应当按代码处理")
            let tokens = marked(code, language)
            XCTAssertFalse(tokens.isEmpty, "\(language.rawValue) 一个着色记号都没有")
            XCTAssertFalse(tokens.filter { $0.0 == "comment" }.isEmpty, "\(language.rawValue) 认不出注释")
            XCTAssertFalse(tokens.filter { $0.0 == "string" }.isEmpty, "\(language.rawValue) 认不出字符串")
            let keywords = tokens.filter { $0.0 == "keyword" }.map(\.1)
            for expected in expectedKeywords {
                XCTAssertTrue(keywords.contains(expected), "\(language.rawValue) 没把 \(expected) 着成关键字（实际：\(keywords)）")
            }
            // 反向：注释里的词不许被着成关键字
            XCTAssertFalse(keywords.contains("注释"), "\(language.rawValue) 把注释里的词也着成了关键字")
        }
    }

    /// 前 10 名都要有"能补全的东西"与"能认出的扩展名"。
    func testTopTenLanguagesAreCompleteEnoughToUse() {
        for language in [TextLanguage.python, .javascript, .typescript, .java, .c, .cpp, .csharp, .go, .rust, .php] {
            let definition = language.definition
            XCTAssertFalse(definition.fileExtensions.isEmpty, "\(language.rawValue) 没有扩展名")
            XCTAssertFalse(definition.syntax.keywords.isEmpty, "\(language.rawValue) 没有关键字")
            XCTAssertFalse(definition.syntax.snippets.isEmpty, "\(language.rawValue) 一条片段都没有")
        }
    }

    // MARK: 运算符（规则集的第四类：登记了才合并，没登记就一个字符一个记号）

    /// 登记的运算符按**最长匹配**合并成一个记号（`==` 不再拆成两个 `=`）。
    func testRegisteredOperatorsMergeByLongestMatch() {
        XCTAssertTrue(punctuation("a == b", .javascript).contains("=="))
        XCTAssertFalse(punctuation("a == b", .javascript).contains("="))
        XCTAssertTrue(punctuation("value -> name", .java).contains("->"))
        XCTAssertTrue(punctuation("a && b", .shell).contains("&&"))
        XCTAssertTrue(punctuation("map::new()", .rust).contains("::"))
        // 最长匹配：`===` 要吃掉三个字符，而不是先匹配到 `==`
        XCTAssertTrue(punctuation("a === b", .javascript).contains("==="))
        XCTAssertTrue(punctuation("s => s", .javascript).contains("=>"))
    }

    /// 没登记运算符的语言（HTML）退回"一个字符一个记号" —— 与既有行为一致，
    /// 也就是说**合并是登记表说了算**，不是词法器自作主张。
    func testUnregisteredOperatorsStaySingleCharacter() {
        let tokens = punctuation("a == b", .html)
        XCTAssertTrue(tokens.contains("="))
        XCTAssertFalse(tokens.contains("=="))
    }

    /// 合并**必须前进**：任何输入都不许出现零宽记号（`@media` 那次死循环的教训，
    /// 现在多了一条按表匹配的路径，同样要保证前进）。
    func testOperatorMatchingAlwaysAdvances() {
        for language in TextLanguage.allCases {
            let tricky = "@media <==> ... :: -> ?? && || => != -- ++ // ** /* #"
            let tokens = CodeLexer.tokens(in: tricky, language: language)
            var covered = 0
            var previous: String.Index?
            for token in tokens {
                if let previous { XCTAssertLessThan(previous, token.range.lowerBound, "\(language.rawValue) 记号次序不对") }
                XCTAssertLessThan(token.range.lowerBound, token.range.upperBound, "\(language.rawValue) 出现零宽记号")
                previous = token.range.lowerBound
                covered += tricky.distance(from: token.range.lowerBound, to: token.range.upperBound)
            }
            if !tokens.isEmpty {
                XCTAssertEqual(covered, tricky.count, "\(language.rawValue) 有字符没被任何记号覆盖（可能被跳过了）")
            }
        }
    }

    // MARK: 主题令牌（FR-EDIT-38 ③ 的 Core 半边）

    /// 高亮色属于**主题令牌**：`SyntaxTone` 是唯一取色入口，且每个色调都要有值。
    /// （"编辑器里不许出现裸色值"那一半是 App 侧，由 `Scripts/check-language-registry.py` 判。）
    func testSyntaxColorsComeFromThemeTokens() {
        XCTAssertFalse(SyntaxTone.allCases.isEmpty)
        for tone in SyntaxTone.allCases {
            for theme in DesignTheme.allCases {
                // 取得到就是令牌在位；具体色值随主题变化由既有设计令牌单测守着。
                _ = tone.color(in: theme)
            }
        }
    }

    /// 2026-10-03（`Q61` 拍板）：**Swift 与 ArkTS 进表** —— 前者是 `FR-EDIT-38` 的 Beta 1 缺口（清单里本来就点名包含它），
    /// 后者是需求提出者新增（他点名的「高频语言」里有 arkts，而旧清单里没有）。
    func testSwiftAndArkTSAreRegistered() {
        XCTAssertEqual(CodeLanguageRegistry.detect(path: "main.swift"), .swift)
        XCTAssertEqual(CodeLanguageRegistry.detect(path: "Index.ets"), .arkts)
        XCTAssertEqual(CodeLanguageRegistry.detect(path: "Index.arkts"), .arkts)
        // **一个扩展名只许一个主人**：`.ts` 仍归 TypeScript ⇒ ArkTS 只认 `.ets` / `.arkts`（Q61 选项②）。
        XCTAssertEqual(CodeLanguageRegistry.detect(path: "index.ts"), .typescript)
        for language in [TextLanguage.swift, .arkts] {
            let syntax = CodeLanguageRegistry.definition(of: language).syntax
            XCTAssertFalse(syntax.keywords.isEmpty, "\(language.rawValue) 得给得出关键字")
            XCTAssertFalse(syntax.comments.isEmpty, "\(language.rawValue) 得给得出注释规则")
            XCTAssertFalse(syntax.stringDelimiters.isEmpty, "\(language.rawValue) 得给得出字符串界定符")
        }
        // 装饰器当关键字列（ArkTS 的 ArkUI 部分），钉一条免得整串被删光还没人知道。
        XCTAssertTrue(CodeLanguageRegistry.definition(of: .arkts).syntax.keywords.contains("Entry"))
    }
}
