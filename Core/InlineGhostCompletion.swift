import Foundation

/// 行内灰字补全要画的那一条建议（`FR-EDIT-57` 的**行内**形态）。
///
/// 为什么它是值类型、而不是"编辑器里的一个状态位"：这条东西的三个数
/// （替换哪一段 / 换成什么 / 灰字到底是什么）决定了"用户按 Tab 之后正文变成什么"，
/// 那是最不能出错的一步。放在 Core 里就**能逐条判**（`Tests/InlineGhostCompletionTests.swift`），
/// 留在 AppKit 回调里就只能靠手点。
public struct InlineGhostSuggestion: Sendable, Equatable {

    /// 要被替换掉的**已输入前缀**（UTF-16 长度单位，与 `NSTextView.selectedRange()` 同一口径）。
    public let range: NSRange

    /// 接受后真正写进文档的文本（**含前缀**）—— 例如敲了 `ret`，它是 `return`。
    public let insertText: String

    /// 画在光标右边的灰字（= `insertText` 去掉前缀，例如 `urn`）。
    ///
    /// 它**永远不进文本存储**：灰字是画出来的，不是打出来的。这条不变量由 App 侧守着
    /// （`draw` 里画），Core 这一层只负责把"该画什么"算清楚。
    public let ghost: String

    /// 这条建议是按哪种候选来的（关键字 / 片段 / 内置 / 文档词）—— 界面据此决定灰字的淡法。
    public let kind: CodeCompletionItem.Kind

    /// 接受后光标应落的位置（UTF-16，绝对偏移）。灰字只收**单行**候选
    /// （多行片段落在哪里是另一套约定，见 `CodeCompletion.caretOffset`），所以这里就是插入文本的末尾。
    public let caretOffset: Int

    public init(
        range: NSRange,
        insertText: String,
        ghost: String,
        kind: CodeCompletionItem.Kind,
        caretOffset: Int
    ) {
        self.range = range
        self.insertText = insertText
        self.ghost = ghost
        self.kind = kind
        self.caretOffset = caretOffset
    }
}

/// 行内灰字补全（`FR-EDIT-57`）：敲字时光标右边显示一条淡色建议，**Tab 接受 / Esc 忽略**。
///
/// ## 为什么要有这一片
///
/// 补全此前只有一条路：用户先按一次键（⌃Space / F5）弹出系统候选面板，再挑一条。
/// 需求提出者 2026-10-15 的原话是「**工作区的代码编辑器也要下功夫做到好用，编程助手的基本能力都要有**」——
/// 编程助手最日常的那个动作是"接着往下写时它把词补完"，而不是"每次都先举手要候选列表"。
/// 所以这一片补的是**不等用户举手**的那半：候选列表还在（同一个 `CodeCompletion`），
/// 只是最常见的那个候选直接以灰字摆在光标后面。
///
/// ## 五条口径（每条都是刻意的取舍，判据逐条守着）
///
/// 1. **灰字只画、不写**：它不进 `NSTextStorage` —— 所以撤销栈里没有它、保存的文件里没有它、
///    复制走的文本里也没有它。想让它进正文，只有"按 Tab"这一条路。
/// 2. **大小写必须逐字相同**：`insertText.hasPrefix(prefix)` 是**区分大小写**的。
///    SQL 那边关键字是大写，敲 `sel` 就**不给灰字**（而不是画出 `ECT` 拼成 `selECT` ——
///    那不是预览，是误导）。宁可少提示一次，也不许显示一个不存在的词。
/// 3. **只收单行**：含换行的候选（多行片段）一律不画。行内建议的语义是"把当前这个词补完"，
///    而多行片段是"插一段代码"——那件事的落点约定在 `CodeCompletion.caretOffset`，不该由灰字代劳。
/// 4. **灰字有长度上限**（`maximumGhostLength`）：一屏上一行塞不下就别提示，
///    否则灰字会把整行挤出去，用户还以为是文本折叠了。
/// 5. **不在词中间、不在字符串 / 注释里、有选区时都不出**：这四种时机下用户的意图不是"补完这个词"，
///    冒出来的灰字只会干扰（选区更是直接覆盖 —— 一按 Tab 就把选中内容换掉是最坏的"智能"）。
///
/// ## 已知边界（如实登记）
///
/// 字符串 / 注释的判定是**按本行**做的（只切当前这一行的词法）：跨行的 `/* … */`、Python 的
/// 三引号串里，本行看起来像普通代码 —— 那种情况下灰字仍会出现。不跨行是因为这段代码要跑在
/// **每次击键**上，整篇重切在 5,000 行文档上就是 `NFR-PERF-05` 那类卡顿；行内切片是常数级代价。
public enum InlineGhostCompletion {

    /// 前缀至少几个字符才给灰字。一个字（`r`）就往下猜，等于替用户写代码。
    public static let minimumPrefixLength = 2

    /// 灰字最长多少字符。超过就不提示（见口径 4）。
    public static let maximumGhostLength = 24

    /// 行内上下文判定（字符串 / 注释）的行长上限：更长的行（压缩过的 JS 之类）直接跳过那次判定。
    public static let maximumLineLengthForContextScan = 4_000

    /// 算一条灰字建议。`nil` = 这一刻不该出灰字（每个 `nil` 的理由都写在上面的口径里）。
    ///
    /// - Parameters:
    ///   - text: 当前文档全文。
    ///   - selection: 当前选区（UTF-16）。**只接受长度 0**（有选区 ⇒ 不出，见口径 5）。
    ///   - language: 当前语言 —— 关键字 / 片段 / 内置全从它对应的语言表来（与着色同一份）。
    ///   - documentWords: 当前文档里的候选词（`CodeCompletion.words(…)` 的结果，App 侧缓存的）。
    ///   - enabled: 总开关（关掉时一个候选都不算）。
    public static func suggestion(
        in text: String,
        selection: NSRange,
        language: TextLanguage,
        documentWords: [String] = [],
        enabled: Bool = true
    ) -> InlineGhostSuggestion? {
        guard enabled else { return nil }
        // 有选区 ⇒ 不出：一按 Tab 就把用户选中的内容换掉，是最坏的那种"智能"。
        guard selection.length == 0 else { return nil }
        let ns = text as NSString

        // 越界的光标（理论上不会有）夹回文档，而不是让它算出一段不存在的文本。
        let caret = min(max(0, selection.location), ns.length)

        // 光标右边还是词字符 ⇒ 用户在词中间改东西（`return|Value` 这种），不是"正在打字等补全"。
        if caret < ns.length, isIdentifierBody(ns.character(at: caret)) { return nil }

        // 往前扫到这个词的开头 —— 前缀就是"光标到这个开头"那一段。
        var start = caret
        while start > 0, isIdentifierBody(ns.character(at: start - 1)) { start -= 1 }
        let prefixRange = NSRange(location: start, length: caret - start)
        guard prefixRange.length > 0 else { return nil }
        let prefix = ns.substring(with: prefixRange)
        guard prefix.count >= minimumPrefixLength, !prefix.allSatisfy({ $0.isNumber }) else { return nil }

        // 在字符串 / 注释里不出（按本行判定，边界见类型注释）。
        if isInsideCommentOrString(ns: ns, caret: caret, language: language) { return nil }

        // 候选与"按 ⌃Space 弹列表"是**同一份**（`CodeCompletion`）—— 两处各算一套必然漂移。
        let items = CodeCompletion.suggestions(
            prefix: prefix,
            language: language,
            documentWords: documentWords
        )

        for item in items {
            // 口径 2：大小写逐字相同才算（否则会拼出一个不存在的词）。
            guard item.insertText != prefix, item.insertText.hasPrefix(prefix) else { continue }
            let ghost = String(item.insertText.dropFirst(prefix.count))
            // 口径 3 / 4：只收单行、且不超长。
            guard !ghost.isEmpty,
                  !ghost.contains("\n"), !ghost.contains("\r"),
                  ghost.count <= maximumGhostLength else { continue }
            return InlineGhostSuggestion(
                range: prefixRange,
                insertText: item.insertText,
                ghost: ghost,
                kind: item.kind,
                caretOffset: prefixRange.location + (item.insertText as NSString).length
            )
        }
        return nil
    }

    /// 光标是否落在**本行**的注释或字符串里。
    ///
    /// 只切当前这一行（见类型注释的"已知边界"）：每次击键都跑，整篇重切在大文档上是真卡顿。
    private static func isInsideCommentOrString(ns: NSString, caret: Int, language: TextLanguage) -> Bool {
        let lineRange = ns.lineRange(for: NSRange(location: caret, length: 0))
        // 行首可能带换行符（`lineRange` 含行尾的 `\n`）；去掉它，让行内偏移与文本对得上。
        let raw = ns.substring(with: lineRange)
        let line = raw.hasSuffix("\n") ? String(raw.dropLast()) : raw
        guard line.utf16.count <= maximumLineLengthForContextScan else { return false }
        let caretInLine = min(max(0, caret - lineRange.location), line.utf16.count)

        // 这一行一个字都没有（空行 / 只有空白）⇒ 不可能在字符串或注释里。
        guard !line.isEmpty else { return false }

        for token in CodeLexer.tokens(in: line, language: language) {
            guard token.kind == .comment || token.kind == .string else { continue }
            let start = line.utf16.distance(from: line.utf16.startIndex, to: token.range.lowerBound)
            let end = line.utf16.distance(from: line.utf16.startIndex, to: token.range.upperBound)
            // 判"前缀最后一个字符"也在里面：光标恰好在词的末尾时，前缀本身才是要判的那段。
            if caretInLine > start, caretInLine <= end { return true }
        }
        return false
    }

    /// 词字符 = 字母 / 数字 / 下划线（与 `CodeCompletion.words` 抽词的界一致）。
    private static func isIdentifierBody(_ codeUnit: unichar) -> Bool {
        guard let scalar = UnicodeScalar(codeUnit) else { return false }
        return CharacterSet.alphanumerics.contains(scalar) || scalar == "_"
    }
}
