import Foundation

/// 一段注释的形态：`open` + 可选 `close`（没有 close 就是行注释）。
public struct CodeCommentStyle: Sendable, Equatable {
    public let open: String
    public let close: String?

    public init(line: String) {
        self.open = line
        self.close = nil
    }

    public init(block open: String, _ close: String) {
        self.open = open
        self.close = close
    }

    public var isLine: Bool { close == nil }
}

/// 补全里的一条**片段**（插入的是纯文本；`detail` 给人看）。
///
/// 刻意不用带占位符的 snippet 语法：那需要编辑器支持 Tab 跳位，
/// 而我们的编辑器是 `NSTextView` + 自己的补全面板。插入纯文本 + 把光标放在
/// 合理位置（约定见 `CodeCompletion`）已经能省掉大部分重复劳动，且**不会**留下
/// 一堆需要用户手动清理的占位符。
public struct CodeSnippet: Sendable, Equatable {
    public let label: String
    public let insertText: String
    /// 说明文字的**文案键**（Core 不持有中文：展示文本一律走 `LocalizedStrings`，
    /// 这也是 Core 本地化棘轮要求的口径）。
    public let detailKey: LKey

    public init(label: String, insertText: String, detailKey: LKey) {
        self.label = label
        self.insertText = insertText
        self.detailKey = detailKey
    }
}

/// 一个语言的**着色规则集**（FR-EDIT-38 ①：关键字 / 类型 / 字面量 / 内置名 / 注释 /
/// 字符串 / 运算符 / 片段）。
///
/// 为什么规则集与补全片段放**同一份**：着色与补全都是"这个词算不算关键字"的消费者。
/// 分成两份的典型症状是——用户看到 `await` 被着成关键字，补全却给不出来（或反过来）。
/// 这也正是 `SQLDialect` 已有的做法（`keywords` / `builtinFunctions` 同时喂高亮与补全）。
///
/// **本类型不再持有"我是哪个语言"**：语言身份（扩展名映射 / 显示名 / 特质）归
/// `CodeLanguageDefinition`，规则集只回答"这些字怎么上色"。这样词法器与补全都
/// 拿得到规则、却拿不到"语言身份"可判 —— 加语言时它们没什么可改的。
public struct CodeSyntax: Sendable {
    /// **聚合后的关键字表**：`keywords + types + literals`（着色与补全都读它）。
    ///
    /// 聚合在初始化时做一次，是为了让下面三张表能各写各的 —— 分类是可读性，
    /// 着色只有一个判据："这个词要不要按关键字上色"。
    public let keywords: [String]
    /// 类型名（`int` / `String` / `Vec`…）—— 着色上与关键字同类。
    public let types: [String]
    /// 字面量（`true` / `null` / `nil` / `None`…）—— 着色上与关键字同类。
    public let literals: [String]
    /// 内置名 / 属性 / 标签属性（`console` / `color` / `class`…）。
    public let builtins: [String]
    public let comments: [CodeCommentStyle]
    public let stringDelimiters: [String]
    /// 运算符表（多字符的写全：`->` / `::` / `==`）。词法器按**最长匹配**合并成一个记号，
    /// 没登记的多字符串退回"一个字符一个记号"（与既有行为一致）。
    public let operators: [String]
    public let isCaseInsensitive: Bool
    /// 双写引号是不是"转义一个引号"（SQL 的 `''`；JS / Python 用反斜杠，不是这种）。
    public let usesDoubledQuoteEscape: Bool
    public let snippets: [CodeSnippet]

    /// 归一化后的关键字集合（大小写不敏感的语言统一转小写，见 `normalized(_:)`）。
    public let keywordLookup: Set<String>
    public let builtinLookup: Set<String>
    /// 按长度降序的运算符表（最长匹配用；同长度按登记次序）。
    public let operatorLookup: [String]

    public init(
        keywords: [String] = [],
        types: [String] = [],
        literals: [String] = [],
        builtins: [String] = [],
        comments: [CodeCommentStyle] = [],
        stringDelimiters: [String] = ["\"", "'"],
        operators: [String] = [],
        isCaseInsensitive: Bool = false,
        usesDoubledQuoteEscape: Bool = false,
        snippets: [CodeSnippet] = []
    ) {
        let allKeywords = Self.merged(keywords, types, literals)
        self.keywords = allKeywords
        self.types = types
        self.literals = literals
        self.builtins = builtins
        self.comments = comments
        self.stringDelimiters = stringDelimiters
        self.operators = operators
        self.isCaseInsensitive = isCaseInsensitive
        self.usesDoubledQuoteEscape = usesDoubledQuoteEscape
        self.snippets = snippets
        self.keywordLookup = Set(allKeywords.map { Self.normalized($0, caseInsensitive: isCaseInsensitive) })
        self.builtinLookup = Set(builtins.map { Self.normalized($0, caseInsensitive: isCaseInsensitive) })
        self.operatorLookup = Self.longestFirst(operators)
    }

    /// 三张表合成一张、去掉重复（同一个词出现在两张表里不算错，但别让补全列表出现两遍）。
    private static func merged(_ lists: [String]...) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for list in lists {
            for word in list where seen.insert(word).inserted { result.append(word) }
        }
        return result
    }

    private static func longestFirst(_ operators: [String]) -> [String] {
        var seen: Set<String> = []
        let unique = operators.filter { !$0.isEmpty && seen.insert($0).inserted }
        return unique.sorted { $0.count == $1.count ? false : $0.count > $1.count }
    }

    /// **有没有规则可施** —— 一条都没有的语言（纯文本）一个记号都不给：
    /// 连数字都不该着色（它不是代码，颜色只会让人以为那是语法）。
    public var hasAnyRule: Bool {
        !keywordLookup.isEmpty || !builtinLookup.isEmpty || !comments.isEmpty || !stringDelimiters.isEmpty
    }

    /// 查表用的归一化：不区分大小写的语言（SQL / HTML / CSS / PHP）统一小写。
    public static func normalized(_ word: String, caseInsensitive: Bool) -> String {
        caseInsensitive ? word.lowercased() : word
    }

    public func normalized(_ word: String) -> String {
        Self.normalized(word, caseInsensitive: isCaseInsensitive)
    }

    public func isKeyword(_ word: String) -> Bool { keywordLookup.contains(normalized(word)) }
    public func isBuiltin(_ word: String) -> Bool { builtinLookup.contains(normalized(word)) }

    /// 取某个语言的规则集。**规则集来自登记表**（`CodeLanguageRegistry`）——
    /// 本文件里没有一条语言知识，`of(_:)` 只是换个问法。
    public static func of(_ language: TextLanguage) -> CodeSyntax {
        CodeLanguageRegistry.definition(of: language).syntax
    }
}
