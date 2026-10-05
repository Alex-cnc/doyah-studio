import Foundation

// MARK: - 语言定义（FR-EDIT-38 ①：声明式登记）

/// 词法器需要知道的**语言特质** —— 「这个语言里 `<div a="b">` 算标签」这类形状差异。
///
/// 为什么要单列：这之前这些差异是**写死在词法器里的身份判断**（`language == .html` /
/// `language == .css`）—— 那正是 FR-EDIT-38 ① 要拆掉的东西：加一个标记语言就得回头改
/// 词法器，而词法器本该对"有哪些语言"一无所知。
public struct CodeLanguageTraits: Sendable, Equatable {
    /// `<tag attr="v">` 形态的标记语言（HTML；将来的 XML）。
    public let hasMarkupTags: Bool
    /// 「后面紧跟冒号的标识符算属性名」（CSS：`color: red` 里的 `color`）。
    public let colonStartsPropertyName: Bool

    public init(hasMarkupTags: Bool = false, colonStartsPropertyName: Bool = false) {
        self.hasMarkupTags = hasMarkupTags
        self.colonStartsPropertyName = colonStartsPropertyName
    }

    public static let none = CodeLanguageTraits()
}

/// 一个语言的文件**默认用哪种视图打开**（`FR-EDIT-36` 的消费者口径 / 队列 `L-149` 剩余②）。
///
/// 为什么要写在登记表里：需求提出者 2026-09-30 原话「浏览器内置到工作区 Tab 页 …… **本质上 html
/// 也是一种文件**」—— 但「`.html` 该用浏览器视图打开」这件事是**语言 / 类型**的知识，不是工作区
/// 里的一句分支。写进登记表之后，将来再多一种「用浏览器打开的文件类型」（例如 `.svg` / `.pdf`）
/// = 改一行登记，工作区那一侧一行都不用动（与 `FR-EDIT-38` ①「新增语言不改核心代码」同一条口径）；
/// 而「按语言身份分支」（`if 扩展名 == "html"`）正是那条口径要清掉的形状，
/// 由 `Scripts/check-language-registry.py` 守着。
public enum CodeDefaultView: String, Sendable, Equatable, CaseIterable {
    /// 文本编辑器（绝大部分语言；也是认不出时的回落）。
    case editor
    /// 内嵌浏览器（工作区里的一类页签；标记语言走这一档 —— 浏览器**不是** SQL 工作台的页签）。
    case browser
}

/// 一个语言的**全部知识**：它叫什么、认哪些扩展名 / 文件名、按什么规则着色、是不是代码。
///
/// **新增语言 = 往 `CodeLanguageRegistry.definitions` 加一条 + 在本文件末尾给标识加一行
/// `static let`** —— 两处都在本文件里，核心代码（词法器 / 判语言 / 补全）一行都不用改。
/// 这正是 FR-EDIT-38 ① 的口径，且由 `Scripts/check-language-registry.py`（源锚点）与
/// `Tests/CodeLanguageRegistryTests.swift`（规则集完整性）守着。
public struct CodeLanguageDefinition: Sendable {
    /// 语言标识（与 `TextLanguage.rawValue` 同一个值）。
    public let language: TextLanguage
    /// 界面上的语言名（ASCII 专有名词：中文界面里也这么写）。
    public let displayName: String
    /// 扩展名（小写、不含点）。
    public let fileExtensions: [String]
    /// 没有扩展名但一眼认得出来的文件名（小写，如 `.zshrc`）。
    public let fileNames: [String]
    /// 是否按"代码"对待（关键字着色 + 补全）。纯文本与 Markdown 为 `false`。
    public let isCode: Bool
    /// 着色规则集（关键字 / 类型 / 字面量 / 内置名 / 注释 / 字符串 / 运算符 / 片段）。
    public let syntax: CodeSyntax
    /// 语言特质。
    public let traits: CodeLanguageTraits
    /// 这条登记项是不是**认不出时的回落值**（只有 `plainText` 是）。
    ///
    /// 为什么要这个字段：CLI 的 `code-tokens --detect` 用退出码回答"判出来了没有"，
    /// 而那本该是**数据**（这一条是回落值）而不是身份判断（`language == .plainText`）——
    /// 后者正是 FR-EDIT-38 ① 要从核心代码里清掉的形状。
    public let isFallback: Bool
    /// 格式化能力（FR-EDIT-39）。表在下面 `formats`，这里只是转发后的结果 ——
    /// 与 `syntax` / `traits` 一样，「这个语言怎么格式化」是**数据**，不是核心代码里的分支。
    public let format: CodeFormatCapability
    /// 这个语言的文件**默认用哪种视图打开**（`FR-EDIT-36` 消费者口径；见 `CodeDefaultView`）。
    public let defaultView: CodeDefaultView

    public init(
        _ language: TextLanguage,
        displayName: String,
        fileExtensions: [String],
        fileNames: [String] = [],
        isCode: Bool = true,
        syntax: CodeSyntax,
        traits: CodeLanguageTraits = .none,
        isFallback: Bool = false,
        format: CodeFormatCapability = .none,
        defaultView: CodeDefaultView = .editor
    ) {
        self.language = language
        self.displayName = displayName
        self.fileExtensions = fileExtensions
        self.fileNames = fileNames
        self.isCode = isCode
        self.syntax = syntax
        self.traits = traits
        self.isFallback = isFallback
        self.format = format
        self.defaultView = defaultView
    }

    /// 复制一份、换掉格式化能力。
    ///
    /// 为什么要有它：`formats` 表**单列**（不动那 18 条登记项），
    /// 于是「取定义」时必须把两边合成一条 —— 合成只此一处，
    /// 单测钉住「`CodeLanguageRegistry.all` 与 `definition(of:)` 给的是同一份定义」。
    func withFormat(_ capability: CodeFormatCapability) -> CodeLanguageDefinition {
        CodeLanguageDefinition(
            language,
            displayName: displayName,
            fileExtensions: fileExtensions,
            fileNames: fileNames,
            isCode: isCode,
            syntax: syntax,
            traits: traits,
            isFallback: isFallback,
            format: capability,
            defaultView: defaultView
        )
    }
}

/// 语言登记表 —— **语言的唯一事实源**（FR-EDIT-38 ①）。
///
/// 三条纪律（由 `Scripts/check-language-registry.py` 与
/// `Tests/CodeLanguageRegistryTests.swift` 两处守着）：
/// 1. **语言知识只允许出现在本文件** —— 核心文件里出现 `language == .xxx` / `case .xxx:`
///    这类"按语言身份分支"的写法即判红（台账里逐条登记理由才能例外）。
/// 2. **每条登记项都要给全**：扩展名非空、`isCode` 为真的语言必须有注释规则与字符串界定符
///    （否则"识别了却不着色"——用户看到的是一个不出错的空编辑器）。
/// 3. **一个扩展名 / 文件名只能属于一个语言**：两处抢同一个扩展名 = 判语言结果随表顺序变，
///    而这种错在界面上表现为"某些文件偶尔判错"。
public enum CodeLanguageRegistry {

    /// 全部登记项（`TextLanguage.allCases` 的次序就是这里的次序）。
    ///
    /// 带上 `formats` 表里的格式化能力（FR-EDIT-39）——「这个语言怎么格式化」与
    /// 「怎么着色」一样是定义的一部分，两条路取到的必须是同一份定义。
    public static var all: [CodeLanguageDefinition] {
        definitions.map { $0.withFormat(formats[$0.language.rawValue] ?? .none) }
    }

    public static func definition(of language: TextLanguage) -> CodeLanguageDefinition {
        // 表里必有它的定义：`TextLanguage.init?(rawValue:)` 已经用同一张表判过存在性。
        definition(id: language.rawValue) ?? fallback
    }

    public static func definition(id: String) -> CodeLanguageDefinition? { index[id] }

    /// 按路径判语言：**文件名优先，其次扩展名**，都不认就纯文本（FR-EDIT-38 ④）。
    ///
    /// `path` 可以是绝对路径、相对路径或只有一个文件名 —— 只看最后一段。
    public static func detect(path: String) -> TextLanguage {
        let name = (path as NSString).lastPathComponent.lowercased()
        guard !name.isEmpty else { return .plainText }
        if let owner = fileNameIndex[name] { return owner }
        // 最后一个点必须在末尾之前：`weird.` 没有扩展名（不是"扩展名为空"的怪东西）
        guard let dot = name.lastIndex(of: "."), dot < name.index(before: name.endIndex) else {
            return .plainText
        }
        return extensionIndex[String(name[name.index(after: dot)...])] ?? .plainText
    }

    /// 按路径给出「这个文件默认用哪种视图打开」—— **工作区打开文件的唯一出处**（`FR-EDIT-36` 消费者口径）。
    ///
    /// 为什么要一个函数而不是让调用方自己 `detect` + 取字段：调用方一旦自己拼，
    /// 「认不出的文件怎么办」就会被各写一份（今天是「当文本打开」，明天可能有人写成「当浏览器打开」）。
    /// 这里只有一句：**判语言 → 取那一档登记**，认不出就落到 `plainText` 的登记（= 文本编辑器）。
    public static func defaultView(forPath path: String) -> CodeDefaultView {
        definition(of: detect(path: path)).defaultView
    }

    /// 扩展名 → 语言 / 文件名 → 语言（单测与门禁判"有没有两个语言抢同一个"）。
    public static var extensionOwners: [String: TextLanguage] { extensionIndex }
    public static var fileNameOwners: [String: TextLanguage] { fileNameIndex }

    /// 兜底定义。理论上取不到（`TextLanguage` 只能由本表构造出来），但写成**常量**而不是
    /// `definitions.last!`：表的次序不是契约，`last!` 会在有人挪动次序时静默变成另一个语言。
    private static let fallback = CodeLanguageDefinition(
        .plainText,
        displayName: "Plain Text",
        fileExtensions: [],
        isCode: false,
        syntax: CodeSyntax(stringDelimiters: []),
        isFallback: true
    )

    /// **语言的唯一登记处**（FR-EDIT-38 ①：加语言只动这一张表 + 文件末尾的标识行）。
    private static let definitions: [CodeLanguageDefinition] = [

        CodeLanguageDefinition(
            .sql,
            displayName: "SQL",
            fileExtensions: ["sql", "psql", "ddl", "dml"],
            syntax: CodeSyntax(
                // SQL 的关键字与内置函数**直接取自方言**（`PostgresDialect`）—— 与编辑器高亮、
                // 补全用的是同一份定义。方言侧已冻结（见 SRS v3.180），这里只**读**它。
                keywords: PostgresDialect().keywords,
                builtins: PostgresDialect().builtinFunctions,
                comments: [CodeCommentStyle(line: "--"), CodeCommentStyle(block: "/*", "*/")],
                stringDelimiters: ["'", "\""],
                operators: sqlOperators,
                isCaseInsensitive: true,
                // SQL 的 `'it''s'` 是一个字符串 —— 不认这条就会把它切成两段，后面的括号 / 关键字跟着错位。
                usesDoubledQuoteEscape: true,
                snippets: [
                    CodeSnippet(label: "select", insertText: "SELECT * FROM ", detailKey: .codeDetailQuery),
                    CodeSnippet(label: "selectwhere", insertText: "SELECT *\nFROM table_name\nWHERE condition", detailKey: .codeDetailQuery),
                    CodeSnippet(label: "insert", insertText: "INSERT INTO table_name (columns)\nVALUES (values)", detailKey: .codeDetailInsert),
                    CodeSnippet(label: "update", insertText: "UPDATE table_name\nSET column = value\nWHERE condition", detailKey: .codeDetailUpdate),
                    CodeSnippet(label: "delete", insertText: "DELETE FROM table_name\nWHERE condition", detailKey: .codeDetailDelete),
                    CodeSnippet(label: "create", insertText: "CREATE TABLE table_name (\n  id bigint PRIMARY KEY\n)", detailKey: .codeDetailCreateTable),
                    CodeSnippet(label: "join", insertText: "JOIN other ON other.id = table_name.other_id", detailKey: .codeDetailJoin)
                ]
            )
        ),

        CodeLanguageDefinition(
            .javascript,
            displayName: "JavaScript",
            fileExtensions: ["js", "mjs", "cjs", "jsx"],
            syntax: CodeSyntax(
                keywords: javascriptCoreKeywords,
                literals: javascriptLiterals,
                builtins: [
                    "console", "log", "window", "document", "JSON", "Object", "Array", "String", "Number", "Boolean",
                    "Math", "Date", "Promise", "Map", "Set", "Symbol", "Error", "RegExp", "parseInt", "parseFloat",
                    "setTimeout", "setInterval", "fetch", "require", "module", "exports"
                ],
                comments: slashComments,
                stringDelimiters: ["\"", "'", "`"],
                operators: javascriptOperators,
                snippets: [
                    CodeSnippet(label: "log", insertText: "console.log()", detailKey: .codeDetailLog),
                    CodeSnippet(label: "func", insertText: "function name() {\n  \n}", detailKey: .codeDetailFunction),
                    CodeSnippet(label: "arrow", insertText: "const name = () => {\n  \n}", detailKey: .codeDetailArrow),
                    CodeSnippet(label: "forof", insertText: "for (const item of items) {\n  \n}", detailKey: .codeDetailLoop),
                    CodeSnippet(label: "try", insertText: "try {\n  \n} catch (error) {\n  console.error(error)\n}", detailKey: .codeDetailException),
                    CodeSnippet(label: "import", insertText: "import {  } from \"\"", detailKey: .codeDetailImport),
                    CodeSnippet(label: "fetch", insertText: "const response = await fetch(url)", detailKey: .codeDetailRequest)
                ]
            )
        ),

        CodeLanguageDefinition(
            .typescript,
            displayName: "TypeScript",
            fileExtensions: ["ts", "tsx", "mts", "cts"],
            syntax: CodeSyntax(
                keywords: javascriptCoreKeywords + [
                    "interface", "type", "enum", "implements", "public", "private", "protected", "readonly", "declare",
                    "namespace", "abstract", "keyof", "infer", "satisfies", "override", "is", "asserts"
                ],
                types: ["never", "unknown", "any", "string", "number", "boolean", "object", "symbol", "bigint"],
                literals: javascriptLiterals,
                builtins: [
                    "console", "log", "window", "document", "JSON", "Object", "Array", "String", "Number", "Boolean",
                    "Math", "Date", "Promise", "Map", "Set", "Symbol", "Error", "RegExp", "parseInt", "parseFloat",
                    "setTimeout", "setInterval", "fetch", "require", "module", "exports",
                    "Partial", "Required", "Readonly", "Record", "Pick", "Omit"
                ],
                comments: slashComments,
                stringDelimiters: ["\"", "'", "`"],
                operators: javascriptOperators,
                snippets: [
                    CodeSnippet(label: "log", insertText: "console.log()", detailKey: .codeDetailLog),
                    CodeSnippet(label: "func", insertText: "function name() {\n  \n}", detailKey: .codeDetailFunction),
                    CodeSnippet(label: "arrow", insertText: "const name = () => {\n  \n}", detailKey: .codeDetailArrow),
                    CodeSnippet(label: "forof", insertText: "for (const item of items) {\n  \n}", detailKey: .codeDetailLoop),
                    CodeSnippet(label: "try", insertText: "try {\n  \n} catch (error) {\n  console.error(error)\n}", detailKey: .codeDetailException),
                    CodeSnippet(label: "import", insertText: "import {  } from \"\"", detailKey: .codeDetailImport),
                    CodeSnippet(label: "fetch", insertText: "const response = await fetch(url)", detailKey: .codeDetailRequest),
                    CodeSnippet(label: "interface", insertText: "interface Name {\n  \n}", detailKey: .codeDetailType),
                    CodeSnippet(label: "type", insertText: "type Name = {\n  \n}", detailKey: .codeDetailType)
                ]
            )
        ),

        CodeLanguageDefinition(
            .html,
            displayName: "HTML",
            fileExtensions: ["html", "htm", "xhtml"],
            syntax: CodeSyntax(
                keywords: [
                    "html", "head", "body", "title", "meta", "link", "script", "style", "div", "span", "p", "a", "img",
                    "ul", "ol", "li", "table", "thead", "tbody", "tr", "td", "th", "form", "input", "button", "label",
                    "select", "option", "textarea", "section", "header", "footer", "nav", "main", "article", "aside",
                    "h1", "h2", "h3", "h4", "h5", "h6", "br", "hr", "strong", "em", "code", "pre", "iframe", "canvas",
                    "svg", "template", "slot"
                ],
                builtins: [
                    "class", "id", "style", "href", "src", "alt", "title", "type", "name", "value", "placeholder",
                    "disabled", "checked", "selected", "readonly", "required", "target", "rel", "width", "height",
                    "colspan", "rowspan", "for", "action", "method", "charset", "content", "defer", "async", "lang"
                ],
                comments: [CodeCommentStyle(block: "<!--", "-->")],
                stringDelimiters: ["\"", "'"],
                isCaseInsensitive: true,
                snippets: [
                    CodeSnippet(label: "html5", insertText: "<!DOCTYPE html>\n<html lang=\"zh-CN\">\n<head>\n  <meta charset=\"utf-8\">\n  <title></title>\n</head>\n<body>\n  \n</body>\n</html>", detailKey: .codeDetailTemplate),
                    CodeSnippet(label: "div", insertText: "<div></div>", detailKey: .codeDetailElement),
                    CodeSnippet(label: "a", insertText: "<a href=\"\"></a>", detailKey: .codeDetailLink),
                    CodeSnippet(label: "img", insertText: "<img src=\"\" alt=\"\">", detailKey: .codeDetailImage),
                    CodeSnippet(label: "input", insertText: "<input type=\"text\" name=\"\">", detailKey: .codeDetailInput),
                    CodeSnippet(label: "ul", insertText: "<ul>\n  <li></li>\n</ul>", detailKey: .codeDetailList)
                ]
            ),
            traits: CodeLanguageTraits(hasMarkupTags: true),
            defaultView: .browser
        ),

        CodeLanguageDefinition(
            .css,
            displayName: "CSS",
            fileExtensions: ["css", "scss", "sass", "less"],
            syntax: CodeSyntax(
                keywords: ["@media", "@import", "@keyframes", "@font-face", "@supports", "@charset", "important"],
                builtins: [
                    "color", "background", "background-color", "background-image", "display", "flex", "grid", "position",
                    "top", "right", "bottom", "left", "width", "height", "min-width", "max-width", "min-height",
                    "max-height", "margin", "padding", "border", "border-radius", "font", "font-size", "font-family",
                    "font-weight", "line-height", "text-align", "text-decoration", "letter-spacing", "opacity",
                    "overflow", "z-index", "transform", "transition", "animation", "box-shadow", "cursor", "gap",
                    "align-items", "align-content", "justify-content", "flex-direction", "flex-wrap", "grid-template-columns",
                    "grid-template-rows", "visibility", "content", "outline", "filter", "object-fit", "white-space"
                ],
                comments: [CodeCommentStyle(block: "/*", "*/")],
                stringDelimiters: ["\"", "'"],
                isCaseInsensitive: true,
                snippets: [
                    CodeSnippet(label: "flex", insertText: "display: flex;\nalign-items: center;\njustify-content: center;", detailKey: .codeDetailLayout),
                    CodeSnippet(label: "grid", insertText: "display: grid;\ngrid-template-columns: repeat(3, 1fr);\ngap: 8px;", detailKey: .codeDetailLayout),
                    CodeSnippet(label: "center", insertText: "position: absolute;\ntop: 50%;\nleft: 50%;\ntransform: translate(-50%, -50%);", detailKey: .codeDetailCenter),
                    CodeSnippet(label: "media", insertText: "@media (max-width: 768px) {\n  \n}", detailKey: .codeDetailMedia)
                ]
            ),
            traits: CodeLanguageTraits(colonStartsPropertyName: true)
        ),

        CodeLanguageDefinition(
            .json,
            displayName: "JSON",
            fileExtensions: ["json", "jsonc", "geojson"],
            fileNames: [".eslintrc", ".prettierrc", "package-lock.json"],
            syntax: CodeSyntax(
                literals: ["true", "false", "null"],
                // JSON 标准里没有注释，但配置文件（`.eslintrc` / `tsconfig.json`）里天天见；
                // 认它比"把注释当代码着成关键字"更接近用户预期。
                comments: [CodeCommentStyle(line: "//"), CodeCommentStyle(block: "/*", "*/")],
                stringDelimiters: ["\""],
                snippets: [
                    CodeSnippet(label: "object", insertText: "{\n  \"key\": \"value\"\n}", detailKey: .codeDetailObject),
                    CodeSnippet(label: "array", insertText: "[\n  \n]", detailKey: .codeDetailArray)
                ]
            )
        ),

        CodeLanguageDefinition(
            .python,
            displayName: "Python",
            fileExtensions: ["py", "pyw", "pyi"],
            syntax: CodeSyntax(
                keywords: [
                    "def", "class", "return", "if", "elif", "else", "for", "while", "break", "continue", "pass",
                    "import", "from", "as", "try", "except", "finally", "raise", "with", "lambda", "global",
                    "nonlocal", "assert", "yield", "async", "await", "del", "in", "is", "not", "and", "or",
                    "self", "match", "case"
                ],
                literals: ["None", "True", "False"],
                builtins: [
                    "print", "len", "range", "str", "int", "float", "bool", "list", "dict", "set", "tuple", "sum",
                    "min", "max", "sorted", "enumerate", "zip", "open", "isinstance", "type", "super", "format",
                    "abs", "round", "any", "all", "map", "filter"
                ],
                comments: [CodeCommentStyle(line: "#")],
                stringDelimiters: ["\"", "'"],
                operators: cLikeOperators,
                snippets: [
                    CodeSnippet(label: "def", insertText: "def name():\n    ", detailKey: .codeDetailFunction),
                    CodeSnippet(label: "class", insertText: "class Name:\n    def __init__(self):\n        ", detailKey: .codeDetailClass),
                    CodeSnippet(label: "main", insertText: "if __name__ == \"__main__\":\n    ", detailKey: .codeDetailEntry),
                    CodeSnippet(label: "for", insertText: "for item in items:\n    ", detailKey: .codeDetailLoop),
                    CodeSnippet(label: "try", insertText: "try:\n    \nexcept Exception as error:\n    print(error)", detailKey: .codeDetailException)
                ]
            )
        ),

        CodeLanguageDefinition(
            .shell,
            displayName: "Shell",
            fileExtensions: ["sh", "bash", "zsh", "fish", "command"],
            fileNames: [".bashrc", ".bash_profile", ".zshrc", ".profile", ".bash_aliases"],
            // Shell 也是"按代码写出来的"（有变量 / 管道 / 控制结构），但在编辑器里
            // 关键字密度低，`isCode = false` 保持既有口径（补全不主动介入）。
            isCode: false,
            syntax: CodeSyntax(
                keywords: [
                    "if", "then", "else", "elif", "fi", "for", "while", "until", "do", "done", "case", "esac",
                    "function", "return", "export", "local", "readonly", "source", "echo", "exit", "set", "unset"
                ],
                builtins: ["grep", "sed", "awk", "cat", "ls", "cd", "mkdir", "rm", "cp", "mv", "chmod", "curl", "git"],
                comments: [CodeCommentStyle(line: "#")],
                stringDelimiters: ["\"", "'"],
                operators: shellOperators,
                snippets: [
                    CodeSnippet(label: "if", insertText: "if [ condition ]; then\n  \nfi", detailKey: .codeDetailCondition),
                    CodeSnippet(label: "for", insertText: "for item in items; do\n  \ndone", detailKey: .codeDetailLoop),
                    CodeSnippet(label: "func", insertText: "name() {\n  \n}", detailKey: .codeDetailFunction)
                ]
            )
        ),

        CodeLanguageDefinition(
            .yaml,
            displayName: "YAML",
            fileExtensions: ["yml", "yaml"],
            isCode: false,
            syntax: CodeSyntax(
                literals: ["true", "false", "null", "yes", "no"],
                comments: [CodeCommentStyle(line: "#")],
                stringDelimiters: ["\"", "'"],
                snippets: [
                    CodeSnippet(label: "map", insertText: "key: value", detailKey: .codeDetailMap),
                    CodeSnippet(label: "list", insertText: "- item", detailKey: .codeDetailListItem)
                ]
            )
        ),

        CodeLanguageDefinition(
            .markdown,
            displayName: "Markdown",
            fileExtensions: ["md", "markdown", "mdx"],
            isCode: false,
            syntax: CodeSyntax(
                // 模板刻意用 ASCII 占位（`## Heading` / `[text](url)`）：插入的是**文档内容**，
                // 不该预设用户用什么语言写文档。
                stringDelimiters: ["`"],
                snippets: [
                    CodeSnippet(label: "h2", insertText: "## Heading", detailKey: .codeDetailHeading),
                    CodeSnippet(label: "code", insertText: "```\n\n```", detailKey: .codeDetailCodeBlock),
                    CodeSnippet(label: "link", insertText: "[text](url)", detailKey: .codeDetailLink),
                    CodeSnippet(label: "table", insertText: "| col | col |\n|---|---|\n|  |  |", detailKey: .codeDetailTable)
                ]
            )
        ),

        // **认不出就纯文本**（FR-EDIT-38 ④）：一份"什么都不认"的定义，着色器对它零输出 ——
        // 不假装高亮、也不硬安一个"看起来像"的语言。**字符串界定符要显式清空**：
        // `CodeSyntax` 的默认值是 `["\"", "'"]`（大多数语言都这样），照默认走的话纯文本会把
        // 引号当字符串着色 —— 那就不是"什么都没认出来"了。
        CodeLanguageDefinition(
            .swift,
            displayName: "Swift",
            fileExtensions: ["swift"],
            syntax: CodeSyntax(
                keywords: [
                    "associatedtype", "class", "deinit", "enum", "extension", "fileprivate", "func", "import",
                    "init", "inout", "internal", "let", "open", "operator", "precedencegroup", "private", "protocol",
                    "public", "rethrows", "static", "struct", "subscript", "typealias", "var", "break", "case",
                    "catch", "continue", "default", "defer", "do", "else", "fallthrough", "for", "guard", "if", "in",
                    "repeat", "return", "throw", "switch", "where", "while", "as", "is", "super", "self", "Self",
                    "try", "throws", "async", "await", "actor", "nonisolated", "borrowing", "consuming", "package",
                    "macro", "lazy", "weak", "unowned", "mutating", "nonmutating", "override", "final", "required",
                    "convenience", "dynamic", "indirect", "infix", "prefix", "postfix", "some", "any"
                ],
                types: [
                    "Int", "Int8", "Int16", "Int32", "Int64", "UInt", "Double", "Float", "Decimal", "String",
                    "Character", "Bool", "Array", "Dictionary", "Set", "Optional", "Result", "Error", "Void", "Any",
                    "AnyObject", "Never", "Substring", "ClosedRange", "Range", "URL", "Date", "Data", "UUID",
                    "Codable", "Encodable", "Decodable", "Equatable", "Hashable", "Comparable", "Identifiable",
                    "Sendable", "MainActor", "Task", "Published"
                ],
                literals: ["nil", "true", "false"],
                builtins: [
                    "print", "debugPrint", "assert", "precondition", "fatalError", "dump", "min", "max", "abs",
                    "zip", "map", "filter", "reduce", "withAnimation", "DispatchQueue"
                ],
                comments: slashComments,
                stringDelimiters: ["\"", "'"],
                operators: cLikeOperators + ["...", "..<", "->", "??", "?.", "&&", "||", "=>"],
                snippets: [
                    CodeSnippet(label: "func", insertText: "func name() {\n  \n}", detailKey: .codeDetailFunction),
                    CodeSnippet(label: "struct", insertText: "struct Name {\n  \n}", detailKey: .codeDetailType),
                    CodeSnippet(label: "class", insertText: "final class Name {\n  \n}", detailKey: .codeDetailClass),
                    CodeSnippet(label: "guard", insertText: "guard condition else { return }", detailKey: .codeDetailCondition),
                    CodeSnippet(label: "if", insertText: "if condition {\n  \n}", detailKey: .codeDetailCondition)
                ]
            )
        ),
        CodeLanguageDefinition(
            .arkts,
            displayName: "ArkTS",
            fileExtensions: ["ets", "arkts"],
            syntax: CodeSyntax(
                keywords: javascriptCoreKeywords + arkUIKeywords + [
                    "interface", "type", "enum", "implements", "public", "private", "protected", "readonly",
                    "declare", "namespace", "abstract", "keyof", "infer", "satisfies", "override", "is", "asserts",
                    "struct", "as", "from", "of"
                ],
                types: ["never", "unknown", "any", "string", "number", "boolean", "object", "symbol", "bigint", "ESObject"],
                literals: javascriptLiterals,
                builtins: [
                    "console", "log", "JSON", "Object", "Array", "String", "Number", "Boolean", "Math", "Date",
                    "Promise", "Map", "Set", "Symbol", "Error", "RegExp", "parseInt", "parseFloat", "setTimeout",
                    "setInterval", "AppStorage", "LocalStorage", "PersistentStorage", "Environment", "router",
                    "animateTo", "getContext"
                ],
                comments: slashComments,
                stringDelimiters: ["\"", "'", "`"],
                operators: javascriptOperators,
                snippets: [
                    CodeSnippet(label: "component", insertText: "@Entry\n@Component\nstruct Name {\n  build() {\n    \n  }\n}", detailKey: .codeDetailClass),
                    CodeSnippet(label: "state", insertText: "@State value: number = 0", detailKey: .codeDetailKeyword),
                    CodeSnippet(label: "build", insertText: "build() {\n  \n}", detailKey: .codeDetailFunction),
                    CodeSnippet(label: "if", insertText: "if (condition) {\n  \n}", detailKey: .codeDetailCondition),
                    CodeSnippet(label: "forof", insertText: "for (const item of items) {\n  \n}", detailKey: .codeDetailLoop)
                ]
            )
        ),

        CodeLanguageDefinition(
            .plainText,
            displayName: "Plain Text",
            fileExtensions: ["txt", "text", "log", "csv", "tsv"],
            isCode: false,
            syntax: CodeSyntax(stringDelimiters: []),
            isFallback: true
        ),

        // MARK: Alpha 2 · 常见编程语言前 10（FR-EDIT-38 ②，2026-09-30 需求提出者口径：
        // 按「人真在写什么」取 —— Stack Overflow 使用率 + GitHub 活跃仓库，不用 TIOBE 榜）
        // 上面前端那一批（JS / TS / HTML / CSS / JSON / Python / SQL）已在前 10 里，这里补其余 5 个。

        CodeLanguageDefinition(
            .java,
            displayName: "Java",
            fileExtensions: ["java"],
            syntax: CodeSyntax(
                keywords: [
                    "abstract", "assert", "break", "case", "catch", "class", "const", "continue", "default", "do",
                    "else", "enum", "extends", "final", "finally", "for", "goto", "if", "implements", "import",
                    "instanceof", "interface", "native", "new", "package", "private", "protected", "public", "record",
                    "return", "sealed", "permits", "static", "strictfp", "super", "switch", "synchronized", "this",
                    "throw", "throws", "transient", "try", "var", "volatile", "while", "yield"
                ],
                types: [
                    "boolean", "byte", "char", "double", "float", "int", "long", "short", "void", "String", "Object",
                    "Integer", "Double", "Long", "Boolean", "Character", "List", "Map", "Set", "ArrayList", "HashMap",
                    "HashSet", "Optional", "Stream", "Exception", "RuntimeException"
                ],
                literals: ["true", "false", "null"],
                builtins: ["System", "Math", "Collections", "Arrays", "Objects", "Thread", "Runnable", "Comparator"],
                comments: slashComments,
                stringDelimiters: ["\"", "'"],
                operators: cLikeOperators + ["<<=", ">>=", ">>>"],
                snippets: [
                    CodeSnippet(label: "class", insertText: "public class Name {\n  \n}", detailKey: .codeDetailClass),
                    CodeSnippet(label: "main", insertText: "public static void main(String[] args) {\n  \n}", detailKey: .codeDetailEntry),
                    CodeSnippet(label: "for", insertText: "for (int i = 0; i < n; i++) {\n  \n}", detailKey: .codeDetailLoop),
                    CodeSnippet(label: "try", insertText: "try {\n  \n} catch (Exception error) {\n  error.printStackTrace();\n}", detailKey: .codeDetailException),
                    CodeSnippet(label: "import", insertText: "import java.util.List;", detailKey: .codeDetailImport)
                ]
            )
        ),

        CodeLanguageDefinition(
            .c,
            displayName: "C",
            fileExtensions: ["c", "h"],
            syntax: CodeSyntax(
                keywords: [
                    "auto", "break", "case", "const", "continue", "default", "do", "else", "enum", "extern", "for",
                    "goto", "if", "inline", "register", "restrict", "return", "sizeof", "static", "struct", "switch",
                    "typedef", "union", "volatile", "while", "_Bool", "_Static_assert", "_Thread_local"
                ],
                types: [
                    "char", "double", "float", "int", "long", "short", "signed", "unsigned", "void", "size_t",
                    "ssize_t", "ptrdiff_t", "int8_t", "int16_t", "int32_t", "int64_t", "uint8_t", "uint16_t",
                    "uint32_t", "uint64_t", "bool", "FILE", "time_t"
                ],
                literals: ["NULL", "true", "false"],
                builtins: [
                    "printf", "fprintf", "sprintf", "snprintf", "malloc", "calloc", "realloc", "free", "memcpy",
                    "memset", "memmove", "strlen", "strcmp", "strcpy", "strncpy", "fopen", "fclose", "fread", "fwrite"
                ],
                comments: slashComments,
                stringDelimiters: ["\"", "'"],
                operators: cLikeOperators,
                snippets: [
                    CodeSnippet(label: "main", insertText: "int main(void) {\n  \n  return 0;\n}", detailKey: .codeDetailEntry),
                    CodeSnippet(label: "for", insertText: "for (int i = 0; i < n; i++) {\n  \n}", detailKey: .codeDetailLoop),
                    CodeSnippet(label: "struct", insertText: "typedef struct {\n  \n} Name;", detailKey: .codeDetailType),
                    CodeSnippet(label: "ifdef", insertText: "#ifndef NAME_H\n#define NAME_H\n\n#endif", detailKey: .codeDetailCondition)
                ]
            )
        ),

        CodeLanguageDefinition(
            .cpp,
            displayName: "C++",
            // `.h` 归 C（同一份 C 头文件两种语言都编得动）；C++ 自己的头用小写/长扩展：
            // `hpp` / `hh` / `hxx`。**一个扩展名只能有一个主人** —— 两处抢同一个的结果是
            // 判语言随表顺序变（单测与门禁都会先判红）。
            fileExtensions: ["cpp", "cc", "cxx", "c++", "hpp", "hh", "hxx", "ipp"],
            syntax: CodeSyntax(
                keywords: [
                    "alignas", "alignof", "auto", "break", "case", "catch", "class", "concept", "const", "consteval",
                    "constexpr", "constinit", "const_cast", "continue", "co_await", "co_return", "co_yield", "decltype",
                    "default", "delete", "do", "dynamic_cast", "else", "enum", "explicit", "export", "extern", "final",
                    "for", "friend", "goto", "if", "inline", "mutable", "namespace", "new", "noexcept", "operator",
                    "override", "private", "protected", "public", "register", "reinterpret_cast", "requires", "return",
                    "sizeof", "static", "static_assert", "static_cast", "struct", "switch", "template", "this",
                    "thread_local", "throw", "try", "typedef", "typeid", "typename", "union", "using", "virtual",
                    "volatile", "while"
                ],
                types: [
                    "bool", "char", "char8_t", "char16_t", "char32_t", "double", "float", "int", "long", "short",
                    "signed", "unsigned", "void", "wchar_t", "size_t", "string", "string_view", "vector", "array",
                    "map", "unordered_map", "set", "unordered_set", "pair", "tuple", "deque", "list", "optional",
                    "variant", "shared_ptr", "unique_ptr", "weak_ptr", "std"
                ],
                literals: ["true", "false", "nullptr"],
                builtins: ["cout", "cin", "cerr", "endl", "move", "forward", "make_shared", "make_unique"],
                comments: slashComments,
                stringDelimiters: ["\"", "'"],
                operators: cLikeOperators + ["<<=", ">>="],
                snippets: [
                    CodeSnippet(label: "main", insertText: "int main() {\n  \n  return 0;\n}", detailKey: .codeDetailEntry),
                    CodeSnippet(label: "class", insertText: "class Name {\npublic:\n  Name();\nprivate:\n  \n};", detailKey: .codeDetailClass),
                    CodeSnippet(label: "for", insertText: "for (const auto& item : items) {\n  \n}", detailKey: .codeDetailLoop),
                    CodeSnippet(label: "include", insertText: "#include <iostream>", detailKey: .codeDetailImport)
                ]
            )
        ),

        CodeLanguageDefinition(
            .csharp,
            displayName: "C#",
            fileExtensions: ["cs"],
            syntax: CodeSyntax(
                keywords: [
                    "abstract", "as", "base", "break", "case", "catch", "checked", "class", "const", "continue",
                    "default", "delegate", "do", "else", "enum", "event", "explicit", "extern", "false", "finally",
                    "fixed", "for", "foreach", "goto", "if", "implicit", "in", "interface", "internal", "is", "lock",
                    "namespace", "new", "null", "operator", "out", "override", "params", "partial", "private",
                    "protected", "public", "readonly", "record", "ref", "return", "sealed", "sizeof", "stackalloc",
                    "static", "struct", "switch", "this", "throw", "true", "try", "typeof", "unchecked", "unsafe",
                    "using", "var", "virtual", "volatile", "while", "async", "await", "when", "with", "yield", "global"
                ],
                types: [
                    "bool", "byte", "char", "decimal", "double", "dynamic", "float", "int", "long", "nint", "nuint",
                    "object", "sbyte", "short", "string", "uint", "ulong", "ushort", "void", "Task", "Action", "Func",
                    "List", "Dictionary", "IEnumerable", "IList", "IDictionary", "Nullable", "Exception", "DateTime",
                    "TimeSpan", "Guid", "StringBuilder"
                ],
                builtins: ["Console", "Math", "Enumerable", "Convert", "Environment", "Debug"],
                comments: slashComments,
                stringDelimiters: ["\"", "'"],
                operators: cLikeOperators + ["=>", "??", "?.", "??="],
                snippets: [
                    CodeSnippet(label: "main", insertText: "public static void Main(string[] args)\n{\n  \n}", detailKey: .codeDetailEntry),
                    CodeSnippet(label: "class", insertText: "public class Name\n{\n  \n}", detailKey: .codeDetailClass),
                    CodeSnippet(label: "foreach", insertText: "foreach (var item in items)\n{\n  \n}", detailKey: .codeDetailLoop),
                    CodeSnippet(label: "using", insertText: "using System;\nusing System.Collections.Generic;", detailKey: .codeDetailImport)
                ]
            )
        ),

        CodeLanguageDefinition(
            .go,
            displayName: "Go",
            fileExtensions: ["go"],
            syntax: CodeSyntax(
                keywords: [
                    "break", "case", "chan", "const", "continue", "default", "defer", "else", "fallthrough", "for",
                    "func", "go", "goto", "if", "import", "interface", "map", "package", "range", "return", "select",
                    "struct", "switch", "type", "var"
                ],
                types: [
                    "bool", "byte", "complex64", "complex128", "error", "float32", "float64", "int", "int8", "int16",
                    "int32", "int64", "rune", "string", "uint", "uint8", "uint16", "uint32", "uint64", "uintptr",
                    "any"
                ],
                literals: ["nil", "true", "false", "iota"],
                builtins: [
                    "append", "cap", "close", "copy", "delete", "len", "make", "new", "panic", "print", "println",
                    "recover", "fmt", "errors", "strings", "strconv", "time", "context", "sync", "http"
                ],
                comments: slashComments,
                // 反引号是 Go 的**原始字符串**（里面不处理转义）—— 与 JS 模板串同样的形状。
                stringDelimiters: ["\"", "'", "`"],
                operators: cLikeOperators + [":=", "<-"],
                snippets: [
                    CodeSnippet(label: "func", insertText: "func name() {\n  \n}", detailKey: .codeDetailFunction),
                    CodeSnippet(label: "main", insertText: "func main() {\n  \n}", detailKey: .codeDetailEntry),
                    CodeSnippet(label: "struct", insertText: "type Name struct {\n  \n}", detailKey: .codeDetailType),
                    CodeSnippet(label: "iferr", insertText: "if err != nil {\n  return err\n}", detailKey: .codeDetailCondition),
                    CodeSnippet(label: "for", insertText: "for index, item := range items {\n  \n}", detailKey: .codeDetailLoop)
                ]
            )
        ),

        CodeLanguageDefinition(
            .rust,
            displayName: "Rust",
            fileExtensions: ["rs"],
            syntax: CodeSyntax(
                keywords: [
                    "as", "async", "await", "break", "const", "continue", "crate", "dyn", "else", "enum", "extern",
                    "fn", "for", "if", "impl", "in", "let", "loop", "match", "mod", "move", "mut", "pub", "ref",
                    "return", "self", "Self", "static", "struct", "super", "trait", "type", "unsafe", "use", "where",
                    "while", "yield", "union", "box"
                ],
                types: [
                    "bool", "char", "f32", "f64", "i8", "i16", "i32", "i64", "i128", "isize", "str", "u8", "u16",
                    "u32", "u64", "u128", "usize", "String", "Vec", "Option", "Result", "Some", "None", "Ok", "Err",
                    "Box", "Rc", "Arc", "Cell", "RefCell", "HashMap", "HashSet", "BTreeMap", "PathBuf", "Path", "Cow"
                ],
                literals: ["true", "false"],
                builtins: [
                    "println", "print", "format", "vec", "panic", "assert", "assert_eq", "matches", "todo",
                    "unimplemented", "Some", "None", "Ok", "Err"
                ],
                comments: slashComments,
                stringDelimiters: ["\"", "'"],
                operators: cLikeOperators + ["..=", "..", "->", "::", "=>", "&&", "||"],
                snippets: [
                    CodeSnippet(label: "fn", insertText: "fn name() {\n  \n}", detailKey: .codeDetailFunction),
                    CodeSnippet(label: "main", insertText: "fn main() {\n  \n}", detailKey: .codeDetailEntry),
                    CodeSnippet(label: "struct", insertText: "struct Name {\n  \n}", detailKey: .codeDetailType),
                    CodeSnippet(label: "impl", insertText: "impl Name {\n  pub fn new() -> Self {\n    Self {  }\n  }\n}", detailKey: .codeDetailClass),
                    CodeSnippet(label: "match", insertText: "match value {\n  Some(item) => {  }\n  None => {  }\n}", detailKey: .codeDetailCondition)
                ]
            )
        ),

        CodeLanguageDefinition(
            .php,
            displayName: "PHP",
            fileExtensions: ["php", "phtml", "php5", "phps"],
            syntax: CodeSyntax(
                keywords: [
                    "abstract", "and", "as", "break", "callable", "case", "catch", "class", "clone", "const",
                    "continue", "declare", "default", "do", "echo", "else", "elseif", "empty", "enum", "extends",
                    "final", "finally", "fn", "for", "foreach", "function", "global", "goto", "if", "implements",
                    "include", "include_once", "instanceof", "insteadof", "interface", "isset", "list", "match",
                    "namespace", "new", "or", "print", "private", "protected", "public", "readonly", "require",
                    "require_once", "return", "switch", "throw", "trait", "try", "unset", "use", "while", "xor", "yield"
                ],
                types: [
                    "array", "bool", "float", "int", "iterable", "mixed", "object", "self", "parent", "static",
                    "string", "void", "Exception", "Throwable", "Closure", "DateTime", "PDO", "stdClass", "ArrayObject"
                ],
                literals: ["true", "false", "null"],
                builtins: [
                    "count", "strlen", "implode", "explode", "array_map", "array_filter", "array_merge", "sprintf",
                    "printf", "var_dump", "json_encode", "json_decode", "preg_match", "trim", "substr", "str_replace"
                ],
                comments: [CodeCommentStyle(line: "//"), CodeCommentStyle(line: "#"), CodeCommentStyle(block: "/*", "*/")],
                stringDelimiters: ["\"", "'"],
                operators: cLikeOperators + ["??", "->", "=>", "===", "!==", ".="],
                // PHP 的关键字**不区分大小写**（`FUNCTION` / `Return` 都合法）——
                // 变量名区分大小写，但那是标识符不是关键字，本层不管。
                isCaseInsensitive: true,
                snippets: [
                    CodeSnippet(label: "php", insertText: "<?php\n\n", detailKey: .codeDetailTemplate),
                    CodeSnippet(label: "function", insertText: "function name()\n{\n  \n}", detailKey: .codeDetailFunction),
                    CodeSnippet(label: "class", insertText: "class Name\n{\n  public function __construct()\n  {\n    \n  }\n}", detailKey: .codeDetailClass),
                    CodeSnippet(label: "foreach", insertText: "foreach ($items as $key => $item) {\n  \n}", detailKey: .codeDetailLoop)
                ]
            )
        ),
    ]

    /// 标识 → 定义（`TextLanguage` 的存在性判定与"取定义"都走它）。
    private static let index: [String: CodeLanguageDefinition] = {
        var table: [String: CodeLanguageDefinition] = [:]
        for definition in all { table[definition.language.rawValue] = definition }
        return table
    }()

    // MARK: 格式化能力（FR-EDIT-39）

    /// 各语言「怎么格式化」——**单列一张表**，并且只被格式化那一层读（着色 / 补全 / 判语言
    /// 与它无关）。不塞进上面每一条登记项里的理由：加一个语言的格式化能力 = 这里加一行，
    /// 而动不着那 18 条（那 18 条的每个字段都被判据逐条盯着）。
    ///
    /// **登记纪律**（`Scripts/check-code-formatting.py` 与
    /// `Tests/CodeFormattingTests.swift` 两处守着）：
    /// 1. 只登记**满足「从 stdin 读源码、把结果写 stdout、成功退出码 0」**的工具 ——
    ///    这条纪律就是「格式化不碰磁盘」的全部保证（要改文件的工具一律不许登记）；
    /// 2. `displayName` 不许空（说了用外部工具就得说得清是哪一个）；
    /// 3. 内置兜底（`builtin`）只许给**证明得了「那段空白不在内容里」**的语言 —— 靠词法（字符串 / 注释）
    ///    或者靠**它自己的语法边界**（Markdown 的围栏：`markdownTidy` 认 ``` / ~~~，围栏内一字不动）。
    ///    证明不了的一律不给兜底（纯文本）⇒ 用了如实拒绝。**「证明得了」不等于「能全做」**：
///    YAML 的档只做行尾空白与结尾换行（缩进与块标量体内一个字不动）—— 拿一条窄规则换「点了有反应」，
///    边界必须写在函数注释与文档里，不许让用户以为它是格式化器。
    ///
    /// 不在这张表里的语言 = **没有可用的格式化方式**（如实拒绝），而不是硬塞一个改不对的东西。
    private static let formats: [String: CodeFormatCapability] = [
        // SQL：既有 FR-EDIT-22 的保守格式化器当兜底（工作区里的 .sql 没有连接上下文，
        // 这一层只保证「关键字大写 + 子句换行 + 缩进」这几条保守规则）。
        "sql": CodeFormatCapability(builtin: .sql),
        "javascript": CodeFormatCapability(tools: prettier, builtin: .braceIndent),
        "typescript": CodeFormatCapability(tools: prettier, builtin: .braceIndent),
        // JSON：内置档是**断行重排**那一种（字符串外空白语义无关 ⇒ 唯一敢断行的语言）。
        "json": CodeFormatCapability(tools: prettier, builtin: .json),
        "css": CodeFormatCapability(tools: prettier, builtin: .braceIndent),
        "html": CodeFormatCapability(tools: prettier, builtin: .whitespace),
        "python": CodeFormatCapability(
            tools: [CodeFormatTool(executable: "black", arguments: ["-q", "-"], displayName: "Black")],
            // **强档**（需求提出者 2026-10-03：「Python 要强格式化，因为它本身就有严格的格式要求」）：
            // 缩进宽度归一成 4 空格一级，结构按源码自己的相对层级推；三引号内与括号续行不动。
            builtin: .python
        ),
        "go": CodeFormatCapability(
            // `gofmt` **不认 `--version`**（给了会被当成文件参数）⇒ 登记空数组：
            // 版本探测这条路对它关掉，界面只说名字，不编版本号。
            tools: [CodeFormatTool(executable: "gofmt", displayName: "gofmt", versionArguments: [])],
            builtin: .braceIndent
        ),
        "rust": CodeFormatCapability(
            tools: [CodeFormatTool(executable: "rustfmt", arguments: ["--emit", "stdout"], displayName: "rustfmt")],
            builtin: .braceIndent
        ),
        "c": CodeFormatCapability(tools: clangFormat, builtin: .braceIndent),
        "cpp": CodeFormatCapability(tools: clangFormat, builtin: .braceIndent),
        "java": CodeFormatCapability(
            tools: [CodeFormatTool(executable: "google-java-format", arguments: ["-"], displayName: "google-java-format")],
            builtin: .braceIndent
        ),
        // C# / PHP：常见发行版里没有「读 stdin、写 stdout」的官方格式化器
        // （`dotnet format` 按工程跑、`php-cs-fixer` 只改文件）⇒ 不登记外部工具，只给内置兜底。
        "csharp": CodeFormatCapability(builtin: .braceIndent),
        "php": CodeFormatCapability(builtin: .braceIndent),
        // Shell：`shfmt` 不给文件就读 stdin、写 stdout。
        // 内置兜底**不登记** —— Shell 在登记表里没有词法规则，兜底没法证明空白不在字符串里。
        "shell": CodeFormatCapability(
            tools: [CodeFormatTool(executable: "shfmt", arguments: ["-"], displayName: "shfmt")],
            // 需求提出者 2026-10-03：「shell 和 yaml 也要加进来」。宽度 2 空格一级；
            // **停靠符（heredoc）体内一字不动** —— 那里是数据，不是脚本。
            builtin: .shell
        ),
        // Markdown：**有内置档**（`CodeFormatBuiltin.markdown` = 围栏感知的空白规整）。
        // 需求提出者 2026-10-03 点名「Markdown 与 JSON 必须内置」；它确实破了「兜底只给有词法的
        // 语言」这条，因为**它的词法就是围栏** —— `markdownTidy` 自己认 ``` / ~~~，
        // 围栏内一字不动、硬换行标记不吞（见该函数的四条纪律）。
        "markdown": CodeFormatCapability(tools: prettier, builtin: .markdown),
        // YAML：需求提出者 2026-10-03 点名要它 ⇒ 给一个**只做证明得了语义无关**的档：
        // 行尾空白 + 结尾恰好一个换行；**缩进一个字不动**、**块标量（`|` / `>`）体内整段透传**。
        // 它**不是**格式化器（对齐 / 折行 / 引号风格不碰）—— 边界写在 `yamlTidy` 的注释里。
        "yaml": CodeFormatCapability(tools: prettier, builtin: .yaml),
        // Swift 是**花括号语言** ⇒ 用现成的 `braceIndent`（不另造规则）。
        "swift": CodeFormatCapability(builtin: .braceIndent),
        // ArkTS 是 **TypeScript 方言** ⇒ 同 TS 的档（大括号缩进）。
        "arkts": CodeFormatCapability(builtin: .braceIndent)
    ]

    /// Prettier 靠**文件名**判 parser，所以实参里带上文件路径（`%FILE%` 由 Core 填）。
    private static let prettier = [
        CodeFormatTool(
            executable: "prettier",
            arguments: ["--stdin-filepath", CodeFormatTool.fileNamePlaceholder],
            displayName: "Prettier"
        )
    ]

    /// `clang-format` 不给文件就读 stdin；`-assume-filename` 让它按对的方言选项跑。
    private static let clangFormat = [
        CodeFormatTool(
            executable: "clang-format",
            arguments: ["-assume-filename", CodeFormatTool.fileNamePlaceholder],
            displayName: "clang-format"
        )
    ]

    /// 扩展名 / 文件名 → 语言。**先登记者优先**（两个语言抢同一个扩展名时行为是确定的），
    /// 但这种重复本身是错的 —— 单测 `testNoTwoLanguagesClaimTheSameExtension` 与门禁都会判红。
    private static let extensionIndex: [String: TextLanguage] = {
        var table: [String: TextLanguage] = [:]
        for definition in definitions {
            for fileExtension in definition.fileExtensions where table[fileExtension] == nil {
                table[fileExtension] = definition.language
            }
        }
        return table
    }()

    private static let fileNameIndex: [String: TextLanguage] = {
        var table: [String: TextLanguage] = [:]
        for definition in definitions {
            for fileName in definition.fileNames where table[fileName] == nil {
                table[fileName] = definition.language
            }
        }
        return table
    }()
}

// MARK: - 语言标识（新增语言：① 上面加一条登记 ② 这里加一行 `static let`）

/// 语言的**标识**。它们只是名字 —— 名字之外的一切（扩展名、规则集、显示名）
/// 都在上面的登记表里。所以"新增语言只动语言定义文件"是可以机械核对的：
/// 语言标识与登记项必须**同集合**（`Tests/CodeLanguageRegistryTests.swift` 逐个对账，
/// 少一个多一个都判红）。
extension TextLanguage {
    public static let sql = TextLanguage(registered: "sql")
    public static let javascript = TextLanguage(registered: "javascript")
    public static let typescript = TextLanguage(registered: "typescript")
    public static let html = TextLanguage(registered: "html")
    public static let css = TextLanguage(registered: "css")
    public static let json = TextLanguage(registered: "json")
    public static let markdown = TextLanguage(registered: "markdown")
    public static let yaml = TextLanguage(registered: "yaml")
    public static let shell = TextLanguage(registered: "shell")
    public static let python = TextLanguage(registered: "python")
    public static let java = TextLanguage(registered: "java")
    public static let c = TextLanguage(registered: "c")
    public static let cpp = TextLanguage(registered: "cpp")
    public static let csharp = TextLanguage(registered: "csharp")
    public static let go = TextLanguage(registered: "go")
    public static let rust = TextLanguage(registered: "rust")
    public static let php = TextLanguage(registered: "php")
    /// Swift 与 ArkTS（`Q61` / `FR-EDIT-38` Beta 1 缺口）：两者都进语言表，
    /// `.ets` / `.arkts` 归 ArkTS，`.swift` 归 Swift —— 一个扩展名只许一个主人。
    public static let swift = TextLanguage(registered: "swift")
    public static let arkts = TextLanguage(registered: "arkts")
    /// 认不出就是它（FR-EDIT-38 ④）—— 登记表最后一条，与 `detect` 的回落同一个值。
    public static let plainText = TextLanguage(registered: "plainText")
}

// MARK: - 各语言共用的规则片段
//
// 这些常量**不是**"写死的语言分支"（词法器里那种）—— 它们是登记表里的数据，
// 放在一处只是免得同一个运算符表抄 10 遍。

private let slashComments = [CodeCommentStyle(line: "//"), CodeCommentStyle(block: "/*", "*/")]

/// JavaScript 的关键字（不含字面量 —— 字面量单列，见 FR-EDIT-38 ① 的规则集口径）。
/// TypeScript 在这个基础上加自己的关键字与类型。
private let javascriptCoreKeywords = [
    "const", "let", "var", "function", "return", "if", "else", "for", "while", "do", "switch", "case",
    "default", "break", "continue", "class", "extends", "super", "new", "this", "typeof", "instanceof",
    "in", "of", "delete", "void", "yield", "async", "await", "try", "catch", "finally", "throw",
    "import", "export", "from", "as", "static", "get", "set"
]

private let javascriptLiterals = ["true", "false", "null", "undefined", "NaN", "Infinity"]

/// JS / TS 的运算符比 C 系多几个（严格相等、幂、无符号右移）—— 登记进来才谈得上"最长匹配"。
private let javascriptOperators = cLikeOperators + ["===", "!==", "**", ">>>"]

/// C 系语言的运算符（含多字符：`->` / `::` / `==` / `&&` …）。**长串在前**不影响正确性
/// （`CodeSyntax` 初始化时按长度排序取最长匹配），这里按"常见程度"排，便于人读。
private let cLikeOperators = [
    "->", "::", "=>", "==", "!=", "<=", ">=", "&&", "||", "++", "--", "+=", "-=", "*=", "/=", "%=",
    "&=", "|=", "^=", "<<", ">>", "...", "??", "?."
]

// 只登记**真的到得了**的运算符：`$(` / `${` / `2>` 这种永远不会走到这一步
// （`$` 是标识符起始、数字已被数字规则吃掉）—— 登记了却到不了 = 死数据。
private let shellOperators = ["&&", "||", ">>", "<<", "|&", "==", "!=", "->"]

/// ArkTS = **TypeScript 方言 + ArkUI 装饰器**（需求提出者 2026-10-03 拍板纳入，见 `Q61`）。
/// 装饰器当关键字列（它们只能出现在声明位置，高亮出来比当普通标识符有用）。
private let arkUIKeywords = [
    "Entry", "Component", "ComponentV2", "Reusable", "Preview", "CustomDialog", "Concurrent",
    "State", "Prop", "Link", "Provide", "Consume", "Observed", "ObjectLink", "Watch", "Track",
    "StorageLink", "StorageProp", "LocalStorageLink", "LocalStorageProp", "ProvideAndConsume",
    "Builder", "BuilderParam", "LocalBuilder", "Require", "Sendable", "AnimatableExtend", "Styles", "Extend"
]

private let sqlOperators = ["::", "||", "<>", "!=", "<=", ">=", "->>", "->"]
