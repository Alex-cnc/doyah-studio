import XCTest
@testable import DoyahCore

/// `FR-STD-WS-NAV-006` 的判据：同文件符号表的**解析**（悬停事实 + 定义位置）。
///
/// 这一条最容易的假绿是「全文搜一遍同名、取第一个命中」—— 在绝大多数样例上都对，
/// 只在**同名不同作用域**与**字符串 / 注释里的同名**上错。所以下面两组用例专门为那两件事设，
/// 删掉作用域那一层（把解析改成全文件找）时它们会红，其余用例仍绿 —— 这正是「判据能判红」的证据。
final class SymbolOutlineTests: XCTestCase {

    // MARK: 工具

    /// 光标放在 `marker` 这个字符**中间**（文档里只能出现一次）。
    private func offset(of marker: String, in text: String, delta: Int = 0) throws -> Int {
        let range = try XCTUnwrap(text.range(of: marker), "样例里找不到标记 \(marker)")
        let caret = text.index(range.lowerBound, offsetBy: delta)
        return text.utf16.distance(from: text.utf16.startIndex, to: caret)
    }

    private func lookup(_ text: String, _ language: TextLanguage, marker: String, delta: Int = 0) throws -> SymbolLookup {
        SymbolIndex.lookup(in: text, language: language, at: try offset(of: marker, in: text, delta: delta))
    }

    // MARK: ① 悬停给一句话所需的事实 + 定义位置

    func testHoverOnCallSiteGivesFunctionDefinition() throws {
        let text = """
        func makeTitle() -> String {
            "title"
        }
        let title = makeTitle()
        """
        let result = try lookup(text, .swift, marker: "= makeTitle()", delta: 2)
        let hover = try XCTUnwrap(result.hover, "调用点应当解析到函数定义，实际：\(result)")
        XCTAssertEqual(hover.name, "makeTitle")
        XCTAssertEqual(hover.kind, .function)
        XCTAssertEqual(hover.definitionLine, 1, "定义在第 1 行")
        XCTAssertEqual(hover.definition.length, "makeTitle".utf16.count)
    }

    func testHoverOnLocalVariableGivesVariableKind() throws {
        let text = """
        func body() {
            let rows = 3
            print(rows)
        }
        """
        let result = try lookup(text, .swift, marker: "rows)", delta: 0)
        let hover = try XCTUnwrap(result.hover)
        XCTAssertEqual(hover.kind, .variable)
        XCTAssertEqual(hover.definitionLine, 2)
    }

    func testDeclarationKindsAreClassifiedNotAllTheSame() {
        let text = """
        struct Point { }
        let origin = 0
        func move() { }
        """
        let declarations = SymbolIndex.declarations(in: text, language: .swift)
        let kinds = Dictionary(uniqueKeysWithValues: declarations.map { ($0.name, $0.kind) })
        XCTAssertEqual(kinds["Point"], .type)
        XCTAssertEqual(kinds["origin"], .variable)
        XCTAssertEqual(kinds["move"], .function)
    }

    /// 先调用后声明（Swift / Python 都允许）：同一作用域里往前找不到就取这一层的第一条。
    func testForwardReferenceInsideSameScopeResolves() throws {
        let text = """
        let total = sum()
        func sum() -> Int { 1 }
        """
        let result = try lookup(text, .swift, marker: "sum()")
        XCTAssertEqual(result.hover?.kind, .function, "同一作用域的先调用后声明应当解析到定义，实际：\(result)")
    }

    // MARK: ② 作用域：同名不同作用域要分得清（需求末栏）

    func testSameNameInSiblingFunctionIsNotResolved() throws {
        let text = """
        func a() {
            let x = 1
            print(x)
        }
        func b() {
            print(x, 2)
        }
        """
        // a 里的 x：解析到 a 自己那份
        let inside = try lookup(text, .swift, marker: "print(x)", delta: 6)
        XCTAssertEqual(inside.hover?.definitionLine, 2)
        // b 里的 x：本文件里**这个作用域**没有它 ⇒ 明说查不到，不许指到 a 的那一份
        let sibling = try lookup(text, .swift, marker: "x, 2", delta: 0)
        XCTAssertEqual(sibling, .miss(.notDeclaredInFile),
                       "b 里的 x 不存在，解析不许跨作用域借 a 的那一条，实际：\(sibling)")
    }

    func testInnerDeclarationShadowsOuter() throws {
        let text = """
        let value = 1
        func f() {
            let value = 2
            print(value)
        }
        """
        let result = try lookup(text, .swift, marker: "value)")
        XCTAssertEqual(result.hover?.definitionLine, 3, "内层声明要盖住外层")
    }

    func testOuterDeclarationIsVisibleInsideFunction() throws {
        let text = """
        let limit = 10
        func f() {
            print(limit)
        }
        """
        let result = try lookup(text, .swift, marker: "limit)")
        XCTAssertEqual(result.hover?.definitionLine, 1, "内层没有 ⇒ 由内向外走到文件级")
    }

    // MARK: ③ ④ 不出假结果：字符串 / 注释 / 标点 / 关键字 / 未声明

    func testIdentifierInsideStringIsNotASymbol() throws {
        let text = """
        func run() { }
        let label = "run"
        """
        let result = try lookup(text, .swift, marker: "run\"", delta: 0)
        XCTAssertEqual(result, .miss(.protectedRegion), "字符串里的同名不是符号，实际：\(result)")
    }

    func testIdentifierInsideCommentIsNotASymbol() throws {
        let text = """
        func run() { }
        // run 这里只是注释
        """
        let result = try lookup(text, .swift, marker: "run 这里", delta: 0)
        XCTAssertEqual(result, .miss(.protectedRegion), "注释里的同名不是符号，实际：\(result)")
    }

    func testCaretOnWhitespaceIsNotAnIdentifier() throws {
        let text = "func run() { }\n\n"
        let result = try lookup(text, .swift, marker: "\n\n", delta: 1)
        XCTAssertEqual(result, .miss(.notAnIdentifier))
    }

    func testCaretOnKeywordIsNotAnIdentifier() throws {
        let text = "func run() { }\n"
        let result = try lookup(text, .swift, marker: "func", delta: 1)
        XCTAssertEqual(result, .miss(.notAnIdentifier), "关键字不是标识符")
    }

    func testUndeclaredIdentifierSaysSoInsteadOfGuessing() throws {
        let text = """
        func run() {
            unknownThing()
        }
        """
        let result = try lookup(text, .swift, marker: "unknownThing", delta: 3)
        XCTAssertEqual(result, .miss(.notDeclaredInFile))
        XCTAssertNil(result.hover)
    }

    /// 代码语言**大小写敏感**：`Limit` 不是 `limit`。
    func testCodeLanguagesAreCaseSensitive() throws {
        let text = """
        let limit = 1
        func f() {
            print(Limit)
        }
        """
        let result = try lookup(text, .swift, marker: "Limit)")
        XCTAssertEqual(result, .miss(.notDeclaredInFile), "代码语言不许大小写不敏感地匹配，实际：\(result)")
    }

    // MARK: 不建符号表的语言

    func testPlainTextHasNoSymbols() throws {
        let text = "let value = 1\n"
        XCTAssertEqual(SymbolIndex.lookup(in: text, language: .plainText, at: 1), .miss(.noSymbolsForLanguage))
        XCTAssertTrue(SymbolIndex.declarations(in: text, language: .plainText).isEmpty)
    }

    // MARK: SQL：表 / 别名 / 限定列

    private let sql = """
    CREATE TABLE orders (id bigint);
    SELECT o.total FROM orders o;
    """

    func testSQLTableDeclarationIsFound() throws {
        let declarations = SymbolIndex.declarations(in: sql, language: .sql)
        let table = try XCTUnwrap(declarations.first { $0.name == "orders" })
        XCTAssertEqual(table.kind, .table)
        XCTAssertEqual(table.line, 1)
    }

    func testSQLAliasPointsBackToItsTable() throws {
        let result = try lookup(sql, .sql, marker: "o;", delta: 0)
        let hover = try XCTUnwrap(result.hover, "别名 o 应当解析到声明，实际：\(result)")
        XCTAssertEqual(hover.kind, .alias)
        XCTAssertEqual(hover.target, "orders")
    }

    func testSQLQualifiedColumnIsExplainedNotGuessed() throws {
        let result = try lookup(sql, .sql, marker: "total", delta: 1)
        let hover = try XCTUnwrap(result.hover, "o.total 应当说得出是哪张表的列，实际：\(result)")
        XCTAssertEqual(hover.kind, .column)
        XCTAssertEqual(hover.name, "total")
        XCTAssertEqual(hover.target, "orders")
    }

    /// SQL **大小写不敏感**：`FROM ORDERS` 与 `orders` 是同一张表。
    func testSQLIsCaseInsensitive() throws {
        let text = "CREATE TABLE orders (id bigint);\nSELECT * FROM ORDERS;\n"
        let result = try lookup(text, .sql, marker: "ORDERS", delta: 1)
        XCTAssertEqual(result.hover?.kind, .table, "SQL 里 ORDERS 应当解析到 orders，实际：\(result)")
    }

    /// 没有限定名的裸列名 ⇒ 查不到就说查不到（不拿「全文搜一遍」凑一个答案）。
    func testSQLBareColumnWithoutDeclarationIsNotGuessed() throws {
        let text = "SELECT total FROM orders;\n"
        let result = try lookup(text, .sql, marker: "total", delta: 1)
        XCTAssertEqual(result, .miss(.notDeclaredInFile), "裸列名本文件没有定义，实际：\(result)")
    }

    // MARK: Python：文档串里的同名不算符号（跨语言同一口径）

    func testPythonDocstringNameIsProtected() throws {
        let fence = "\"\"\""
        let text = "def run():\n    " + fence + "run" + fence + "\n    return 1\n"
        let result = try lookup(text, .python, marker: "run\"\"\"", delta: 0)
        XCTAssertEqual(result, .miss(.protectedRegion))
    }

    func testPythonFunctionDeclarationIsFound() throws {
        let text = """
        def run():
            return 1
        run()
        """
        let result = try lookup(text, .python, marker: "\nrun()", delta: 1)
        XCTAssertEqual(result.hover?.kind, .function)
        XCTAssertEqual(result.hover?.definitionLine, 1)
    }
}
