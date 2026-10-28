import Foundation

/// 同文件符号表 + 悬停文档 + 跳转到定义（`FR-STD-WS-NAV-006`，**词法级起步**）。
///
/// ## 这一期做什么、不做什么（需求 ③ 原话「跨文件与语言服务器不在本期，不出假结果」）
///
/// 做：**同一个文件里**的符号表 —— 声明（函数 / 类型 / 变量 / 表 / 别名）落在哪个范围、
/// 引用解析到哪一条声明；悬停给一句话说明 + 定义位置；跳转给出要选中的范围。
/// 不做：跨文件、类型推断、语言服务器；**猜不出来就不猜**（返回 `SymbolMiss` 而不是最近似的那条）。
///
/// ## 为什么判据能判红（这类功能最典型的假绿）
///
/// 「全文搜一遍同名、取第一个命中」在大多数样例会**看起来完全正确** —— 直到同名不同作用域：
///
/// ```swift
/// func a() { let x = 1 }
/// func b() { print(x) }   // ← 这里的 x 在 b 里根本不存在
/// ```
///
/// 全文搜会把 `b` 里的 `x` 指到 `a` 的 `x` 上。需求末栏专门写了「不是『全文搜一遍同名』——
/// 同名不同作用域要分得清」，所以解析必须**按作用域由内向外走**（`scopes`），
/// 走到底找不到就是 `.notDeclaredInFile`。判据 `Tests/SymbolOutlineTests.swift` 里
/// 「同名不同作用域」与「字符串 / 注释里的同名不算符号」两组就是专门为这条设的。
///
/// ## 为什么规则是数据而不是 `language == .swift` 分支
///
/// 与 `CodeLanguageDefinitions` 的 `folds` / `snippets` 同一条理由（`FR-EDIT-38` ①）：
/// 「这个语言里哪个关键字引出一个名字」是**知识**，加一个语言只动本文件末尾那张表一行，
/// 解析器一行都不用改。`Scripts/check-language-registry.py` 守的正是「引擎里不许出现语言身份判断」。
public enum SymbolIndex {

    // MARK: - 查

    /// 光标 `offset`（UTF-16）处的符号：命中就给一句话所需的事实，查不到就**明说查不到**。
    public static func lookup(in text: String, language: TextLanguage, at offset: Int) -> SymbolLookup {
        let rules = SymbolRules.rules(for: language)
        guard rules.isEnabled else { return .miss(.noSymbolsForLanguage) }
        let document = Document(text: text, language: language, rules: rules)
        return document.lookup(at: offset)
    }

    /// 文件里的全部声明（判据与将来的「大纲视图」共用；按出现次序）。
    public static func declarations(in text: String, language: TextLanguage) -> [SymbolDeclaration] {
        let rules = SymbolRules.rules(for: language)
        guard rules.isEnabled else { return [] }
        return Document(text: text, language: language, rules: rules).declarations
    }
}

// MARK: - 形状

/// 符号是哪一类（界面按它选一句话，Core 只给结构）。
public enum SymbolKind: String, Sendable, Equatable, CaseIterable {
    case function
    case type
    case variable
    case table
    case alias
    case column
}

/// 一条声明：名字、类别、名字在文档里的范围（UTF-16）、行号（1 起）、所属作用域。
public struct SymbolDeclaration: Equatable, Sendable {
    public let name: String
    public let kind: SymbolKind
    public let range: NSRange
    public let line: Int
    /// 作用域编号（0 = 文件级）；同号即同一层，由 `{ }` 或 SQL 语句界出来。
    public let scope: Int
    /// 别名指向的真实表名（只有 `.alias` 有）；列指向它所属的表（只有 `.column` 有）。
    public let target: String?

    public init(name: String, kind: SymbolKind, range: NSRange, line: Int, scope: Int, target: String? = nil) {
        self.name = name
        self.kind = kind
        self.range = range
        self.line = line
        self.scope = scope
        self.target = target
    }
}

/// 查不到时的理由 —— **必须是分档的**：「光标不在标识符上」与「本文件里没有它的定义」
/// 是两件事，界面上该说的话也不同（需求 ④「查不到就明说查不到，不猜」）。
public enum SymbolMiss: String, Sendable, Equatable {
    /// 光标不在标识符上（空白 / 标点 / 关键字 / 数字）。
    case notAnIdentifier
    /// 落在字符串或注释里 —— 那里没有符号可言。
    case protectedRegion
    /// 本文件里没有它的定义（跨文件与语言服务器不在本期）。
    case notDeclaredInFile
    /// 这个语言不建符号表（纯文本 / Markdown / 配置类）。
    case noSymbolsForLanguage
}

/// 命中时交付的事实：名字 + 类别 + **定义位置**（跳转就选这一段）+ 行号。
public struct SymbolHover: Equatable, Sendable {
    public let name: String
    public let kind: SymbolKind
    public let definition: NSRange
    public let definitionLine: Int
    public let target: String?

    public init(name: String, kind: SymbolKind, definition: NSRange, definitionLine: Int, target: String? = nil) {
        self.name = name
        self.kind = kind
        self.definition = definition
        self.definitionLine = definitionLine
        self.target = target
    }
}

public enum SymbolLookup: Equatable, Sendable {
    case found(SymbolHover)
    case miss(SymbolMiss)

    public var hover: SymbolHover? {
        guard case let .found(hover) = self else { return nil }
        return hover
    }

    public var miss: SymbolMiss? {
        guard case let .miss(reason) = self else { return nil }
        return reason
    }
}

/// 一个语言的符号规则（**数据**；加语言只动 `SymbolRules.table` 一行）。
public struct SymbolRules: Sendable, Equatable {
    /// 关键字（小写）→ 它引出的那个名字是哪一类符号。
    public let declarations: [String: SymbolKind]
    /// 按 `{ }` 分作用域（代码语言）。`false` ⇒ 全文件一个作用域。
    public let usesBraceScopes: Bool
    /// 认 `FROM / JOIN / INTO / UPDATE / CREATE TABLE` 后面的表名与别名（SQL 那一档）。
    public let tracksTables: Bool
    /// 大小写不敏感（SQL 把 `SELECT` 与 `select` 当同一个词）。
    public let caseInsensitive: Bool

    public init(declarations: [String: SymbolKind],
                usesBraceScopes: Bool = true,
                tracksTables: Bool = false,
                caseInsensitive: Bool = false) {
        self.declarations = declarations
        self.usesBraceScopes = usesBraceScopes
        self.tracksTables = tracksTables
        self.caseInsensitive = caseInsensitive
    }

    /// 一个语言什么都不建的时候（纯文本 / Markdown）—— 界面据此说「这个类型没有符号表」。
    public var isEnabled: Bool { !declarations.isEmpty || tracksTables }

    public static let none = SymbolRules(declarations: [:])

    /// **唯一登记处**：`TextLanguage.rawValue` → 规则。
    ///
    /// 只登记「声明关键字 + 表引用」这两件事，因为这一期就是词法级：
    /// 方法声明（Java / C# 的 `public void foo()`）不带关键字前缀，靠词法认不出来 ——
    /// **认不出来就不登记**，宁可查不到（`.notDeclaredInFile`）也不出一条错的。
    private static let table: [String: SymbolRules] = [
        TextLanguage.swift.rawValue: SymbolRules(declarations: [
            "func": .function, "class": .type, "struct": .type, "enum": .type,
            "protocol": .type, "actor": .type, "typealias": .type,
            "let": .variable, "var": .variable
        ]),
        TextLanguage.python.rawValue: SymbolRules(declarations: [
            "def": .function, "class": .type
        ]),
        TextLanguage.javascript.rawValue: SymbolRules(declarations: [
            "function": .function, "class": .type,
            "const": .variable, "let": .variable, "var": .variable
        ]),
        TextLanguage.typescript.rawValue: SymbolRules(declarations: [
            "function": .function, "class": .type, "interface": .type, "enum": .type,
            "type": .type, "const": .variable, "let": .variable, "var": .variable
        ]),
        TextLanguage.go.rawValue: SymbolRules(declarations: [
            "func": .function, "type": .type, "var": .variable, "const": .variable
        ]),
        TextLanguage.rust.rawValue: SymbolRules(declarations: [
            "fn": .function, "struct": .type, "enum": .type, "trait": .type,
            "let": .variable, "const": .variable
        ]),
        TextLanguage.php.rawValue: SymbolRules(declarations: [
            "function": .function, "class": .type, "interface": .type, "trait": .type
        ]),
        TextLanguage.java.rawValue: SymbolRules(declarations: [
            "class": .type, "interface": .type, "enum": .type, "record": .type
        ]),
        TextLanguage.csharp.rawValue: SymbolRules(declarations: [
            "class": .type, "interface": .type, "enum": .type, "struct": .type, "record": .type
        ]),
        TextLanguage.c.rawValue: SymbolRules(declarations: [
            "struct": .type, "enum": .type, "union": .type
        ]),
        TextLanguage.cpp.rawValue: SymbolRules(declarations: [
            "struct": .type, "enum": .type, "union": .type, "namespace": .type
        ]),
        TextLanguage.shell.rawValue: SymbolRules(declarations: [
            "function": .function
        ]),
        TextLanguage.sql.rawValue: SymbolRules(declarations: [
            "create": .table
        ], usesBraceScopes: false, tracksTables: true, caseInsensitive: true)
    ]

    public static func rules(for language: TextLanguage) -> SymbolRules {
        table[language.rawValue] ?? SymbolRules.none
    }
}

// MARK: - 引擎（一次解析，多次查询）

/// 一次把文档切成「记号 + 作用域 + 声明」，查询只在这三样上走。
///
/// 为什么不用 `Scanner` / 正则：字符串与注释里的同名必须不算符号，而这件事仓库里只有一处实现
/// （`CodeLexer.protectedSpans`）—— 自己再写一份引号识别，两处口径迟早分家（`FR-STD-WS-NAV-005` 同一条教训）。
struct Document {

    struct Token {
        let kind: CodeToken.Kind
        let word: String
        let offset: Int
        let length: Int
        /// 这个记号落在哪个作用域里。
        var scope: Int
        var range: NSRange { NSRange(location: offset, length: length) }
    }

    let tokens: [Token]
    let protected: [Range<Int>]
    let declarations: [SymbolDeclaration]
    /// 作用域父链：`parent[i]` = i 的直接外层（0 自己没有外层）。
    let parent: [Int]
    private let rules: SymbolRules
    private let text: String

    init(text: String, language: TextLanguage, rules: SymbolRules) {
        self.text = text
        self.rules = rules
        let raw = CodeLexer.tokens(in: text, language: language)
        let utf16 = text.utf16
        var built: [Token] = []
        built.reserveCapacity(raw.count)
        for token in raw {
            let start = utf16.distance(from: utf16.startIndex, to: token.range.lowerBound)
            let end = utf16.distance(from: utf16.startIndex, to: token.range.upperBound)
            let word = String(text[token.range])
            // 空白是标点 token —— 符号解析只看**有内容的**记号（否则 `LIMIT 2` 这类
            // 「跳过几个记号」的判定会被空格吃掉，`CREATE TABLE t` 直接认不出来）。
            if token.kind == .punctuation, word.allSatisfy({ $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" }) {
                continue
            }
            built.append(Token(kind: token.kind,
                               word: word,
                               offset: start,
                               length: end - start,
                               scope: 0))
        }
        self.protected = CodeLexer.protectedSpans(in: text, language: language)

        // 作用域：按 `{ }` 的嵌套建一族编号（0 = 文件级）。SQL 不分花括号 ⇒ 全文件一个作用域。
        var parents: [Int] = [0]
        if rules.usesBraceScopes {
            var stack: [Int] = []
            for index in built.indices {
                let word = built[index].word
                if built[index].kind == .punctuation && word == "}" {
                    if let popped = stack.popLast() { _ = popped }
                }
                built[index].scope = stack.last ?? 0
                if built[index].kind == .punctuation && word == "{" {
                    let id = parents.count
                    parents.append(stack.last ?? 0)
                    stack.append(id)
                }
            }
        }
        self.parent = parents
        self.tokens = built
        self.declarations = Document.scanDeclarations(tokens: built, text: text, rules: rules)
    }

    // MARK: 声明扫描

    private static func scanDeclarations(tokens: [Token], text: String, rules: SymbolRules) -> [SymbolDeclaration] {
        var found: [SymbolDeclaration] = []
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            defer { index += 1 }
            guard token.kind == .keyword else { continue }
            let keyword = normalizedWord(token.word, rules: rules)

            if let kind = rules.declarations[keyword] {
                // `CREATE TABLE t` 的 `table` 自己也是关键字 ⇒ 跳过紧随其后的关键字找名字。
                guard let name = nextIdentifier(in: tokens, after: index, limit: 2) else { continue }
                found.append(SymbolDeclaration(name: name.word,
                                               kind: kind,
                                               range: name.range,
                                               line: line(of: name.offset, in: text),
                                               scope: name.scope))
                if kind == .table, rules.tracksTables {
                    index = appendTableReferences(tokens: tokens, after: name, text: text, into: &found)
                    continue
                }
                continue
            }

            if rules.tracksTables, ["from", "join", "into", "update"].contains(keyword) {
                guard let name = nextIdentifier(in: tokens, after: index, limit: 2) else { continue }
                found.append(SymbolDeclaration(name: name.word,
                                               kind: .table,
                                               range: name.range,
                                               line: line(of: name.offset, in: text),
                                               scope: name.scope))
                index = appendTableReferences(tokens: tokens, after: name, text: text, into: &found)
            }
        }
        return found
    }

    /// 表名后面可能跟一个别名（`FROM orders o` / `FROM orders AS o`）—— 记成 `.alias`，
    /// `target` 指回真表。返回值是扫描可以跳过到的位置（别名与 `AS` 都已经吃掉）。
    private static func appendTableReferences(tokens: [Token],
                                             after table: Token,
                                             text: String,
                                             into found: inout [SymbolDeclaration]) -> Int {
        guard let tableIndex = tokens.firstIndex(where: { $0.offset == table.offset && $0.length == table.length })
        else { return tokens.count }
        var index = tableIndex + 1
        if index < tokens.count, tokens[index].kind == .keyword, tokens[index].word.lowercased() == "as" {
            index += 1
        }
        guard index < tokens.count, tokens[index].kind == .identifier else { return tableIndex }
        let alias = tokens[index]
        found.append(SymbolDeclaration(name: alias.word,
                                       kind: .alias,
                                       range: alias.range,
                                       line: line(of: alias.offset, in: text),
                                       scope: alias.scope,
                                       target: table.word))
        return index
    }

    /// `index` 之后第一个标识符（最多跳过 `limit` 个记号：`CREATE TABLE` 那两个关键字）。
    private static func nextIdentifier(in tokens: [Token], after index: Int, limit: Int) -> Token? {
        var cursor = index + 1
        var skipped = 0
        while cursor < tokens.count && skipped <= limit {
            let token = tokens[cursor]
            if token.kind == .identifier { return token }
            if token.kind == .keyword || token.kind == .punctuation { skipped += 1; cursor += 1; continue }
            return nil
        }
        return nil
    }

    // MARK: 查询

    func lookup(at offset: Int) -> SymbolLookup {
        if protected.contains(where: { $0.contains(offset) }) { return .miss(.protectedRegion) }
        guard let token = tokens.first(where: { offset >= $0.offset && offset < $0.offset + $0.length })
        else { return .miss(.notAnIdentifier) }
        guard token.kind == .identifier else { return .miss(.notAnIdentifier) }
        let name = normalizedWord(token.word, rules: rules)

        // 由内向外走作用域：**同名不同作用域要分得清**（需求末栏）。
        var scope = token.scope
        while true {
            if let hit = declaration(named: name, in: scope, before: token.offset) {
                return .found(hover(for: hit))
            }
            guard scope != 0, parent[scope] != scope else { break }
            scope = parent[scope]
        }
        // 走到底没有 ⇒ 再看一眼是不是 `别名.列` 这种限定引用（有资格说「这是哪张表的列」）。
        if let qualified = qualifiedReference(at: token) { return .found(qualified) }
        return .miss(.notDeclaredInFile)
    }

    /// 同一层里：**先取引用之前最近的那条**；之前没有就取这一层的第一条
    /// （Swift / Python 都允许先调用后声明 —— 只在这一层里找，不跨作用域）。
    private func declaration(named name: String, in scope: Int, before offset: Int) -> SymbolDeclaration? {
        let layer = declarations.filter { $0.scope == scope && normalizedWord($0.name, rules: rules) == name }
        guard !layer.isEmpty else { return nil }
        let preceding = layer.filter { $0.range.location <= offset }
        return preceding.last ?? layer.first
    }

    /// `orders.total`：`total` 本文件没有声明，但带限定名 ⇒ 说得出「`total` 是 `orders` 的列」，
    /// 跳转落在 `orders` 的定义上。**不带限定就什么都不说**（那才是真正的「查不到」）。
    private func qualifiedReference(at token: Token) -> SymbolHover? {
        guard let index = tokens.firstIndex(where: { $0.offset == token.offset && $0.length == token.length }),
              index >= 2
        else { return nil }
        let dot = tokens[index - 1]
        guard dot.kind == .punctuation, dot.word == "." else { return nil }
        let qualifier = tokens[index - 2]
        guard qualifier.kind == .identifier else { return nil }
        let name = normalizedWord(qualifier.word, rules: rules)
        for candidate in declarations where normalizedWord(candidate.name, rules: rules) == name {
            let table = candidate.target ?? candidate.name
            return SymbolHover(name: token.word,
                               kind: .column,
                               definition: candidate.range,
                               definitionLine: candidate.line,
                               target: table)
        }
        return nil
    }

    private func hover(for declaration: SymbolDeclaration) -> SymbolHover {
        SymbolHover(name: declaration.name,
                    kind: declaration.kind,
                    definition: declaration.range,
                    definitionLine: declaration.line,
                    target: declaration.target)
    }

}

private func normalizedWord(_ word: String, rules: SymbolRules) -> String {
    rules.caseInsensitive ? word.lowercased() : word
}

private func line(of offset: Int, in text: String) -> Int {
    guard offset > 0 else { return 1 }
    let utf16 = text.utf16
    guard let end = utf16.index(utf16.startIndex, offsetBy: min(offset, utf16.count), limitedBy: utf16.endIndex)
    else { return 1 }
    return text[text.startIndex..<end].reduce(1) { count, character in
        character == "\n" ? count + 1 : count
    }
}
