import Foundation

/// 一次「自动缩进 / 智能粘贴」的落法（与 `LineMovePlan` / `MarkdownEditPlan` / `CodePairingPlan` 同口径：
/// UTF-16 坐标、**一次整块替换** —— 一次替换 = 一步 ⌘Z，拆成几次就成了「按一次撤销只退回一半」）。
public struct AutoIndentPlan: Equatable, Sendable {
    /// 要替换的范围（UTF-16）。回车与「单行粘贴」都是零长度插入，多行粘贴可能替换选中区。
    public let range: NSRange
    /// 替换成什么。
    public let replacement: String
    /// 替换完成后的光标位置（UTF-16）。
    public let caret: Int

    public init(range: NSRange, replacement: String, caret: Int) {
        self.range = range
        self.replacement = replacement
        self.caret = caret
    }

    /// 把计划落到文本上（判据与界面读同一份语义：`range` 换成 `replacement`）。
    public func applied(to text: String) -> String {
        (text as NSString).replacingCharacters(in: range, with: replacement)
    }
}

/// 自动缩进与智能粘贴（`FR-STD-WS-EDIT-021`）：回车继承上一行缩进、`{ ( [` 之后多一级、
/// 单独成行的 `} ) ]` 回退一级；粘贴多行文本按上下文重排缩进。
///
/// ## 为什么是纯函数
///
/// 这一族的判据天然是「给『文本 + 选区』要『期望文本 + 期望光标』」，而真正容易错的三件事
/// 都不在\"规则本身\"，在**落点**上：
///
/// · **行进 / 退的那一级取谁**：取**当前行的实际缩进**（前导空白原样带走，制表符与空格不改写成对方），
///   不是\"按层级重算\"—— 用户手写的不规则缩进（半级、混排）在这一行上也要成立；
/// · **什么时候不动**：有选区、光标后面还有正文（`if x { return` 这种）、顶格且无级可继承 ——
///   一律 `nil`（**交还系统默认回车**）。\"吞掉按键却不做任何事\"是本族最难查的失效形态；
/// · **外来缩进不硬塞**：粘贴块先剥掉**它自己的公共缩进**，再接上**上下文那一级的缩进**；
///   空白行保持空白（不产生尾随空格）。
///
/// ## 口径（每条都有判据）
///
/// · 缩进单位 = `CodeBuiltinFormatter.indentUnit`（4 空格，与内置格式化器同一份，不另写一个）；
/// · 行终止符 = **当前行自己的**终止符（文档最后一行没有终止符时，退到文档里第一个终止符，缺省 `\n`）
///   —— 在 `\r\n` 文档里回车不许插出一个裸 `\n`；
/// · ① 回车继承当前行缩进；② 光标紧前一字符是 `{` `(` `[` ⇒ 新行多一级；
///   ③ 当前行**第一个非空白字符**是 `} ) ]` ⇒ 新行少一级（减到 0 为止，不出现负缩进）；
///   ②③ 同时成立（`} else {` 这种）时 = 先按 ③ 减一级、再按 ② 加一级 ⇒ 结果回到本行那一级；
/// · ①②③ 之外**只做一件事**：光标正夹在一对刚配好的括号里（`{|}`）时回车把闭合符挪到下一行，
///   新行落在内层（`{\n⎵⎵⎵⎵|\n}`）—— 这是\"局部、可预测\"的边界，不做整篇重排；
/// · ④ 多行粘贴：剥公共缩进 + 接上下文缩进；单行粘贴**一律不重排**（`nil`），
///   顶格粘到顶格也 `nil`（没有要改的，别把默认粘贴换成自己那一份）。
public enum AutoIndent {

    /// 缩进单位（与内置格式化器同一个出处）。
    public static let unit: String = CodeBuiltinFormatter.indentUnit

    // MARK: - ① ② ③ 回车

    /// 回车该怎么落。返回 `nil` = **交还系统默认回车**（有选区 / 后面还有正文 / 顶格且无级可继承）。
    public static func newline(in text: String,
                               selection: NSRange,
                               indentUnit unit: String = AutoIndent.unit) -> AutoIndentPlan? {
        guard !unit.isEmpty else { return nil }
        let ns = text as NSString
        let length = ns.length
        let start = min(max(0, selection.location), length)
        let end = min(max(start, start + max(0, selection.length)), length)
        // 有选区 ⇒ 不猜「这段换成什么」，让系统按自己的语义来。
        guard start == end else { return nil }

        guard let line = lineBounds(around: start, in: ns) else { return nil }
        let terminator = line.terminator.isEmpty ? documentTerminator(in: ns) : line.terminator
        let lineText = ns.substring(with: NSRange(location: line.start,
                                                  length: line.contentsEnd - line.start))
        let beforeCaret = ns.substring(with: NSRange(location: line.start, length: start - line.start))
        let afterCaret = ns.substring(with: NSRange(location: start, length: line.contentsEnd - start))

        let base = leadingWhitespace(lineText)
        var indent = base
        // ③ 这一行本身就是闭合行（`} ) ]` 打头）⇒ 回退一级。
        if let first = firstNonWhitespace(lineText), isCloser(first) {
            indent = dedent(indent, by: unit)
        }
        // ② 光标紧前是左括号 ⇒ 多一级。
        if let previous = beforeCaret.last, isOpener(previous) {
            indent += unit
        }

        let after = trimLeadingWhitespace(afterCaret)

        if after.isEmpty {
            // 顶格、也不加级：没有任何可继承的东西 ⇒ 交还系统（别把默认回车换成自己那一份）。
            guard !indent.isEmpty else { return nil }
            let replacement = terminator + indent
            return AutoIndentPlan(range: NSRange(location: start, length: 0),
                                  replacement: replacement,
                                  caret: start + (replacement as NSString).length)
        }

        // 光标夹在一对括号中间（`{|}`）：把闭合符挪到下一行，新行落在内层。
        if let firstAfter = after.first, isCloser(firstAfter),
           let previous = beforeCaret.last, isOpener(previous), pairs(previous, firstAfter) {
            let replacement = terminator + indent + terminator + base
            let caret = start + ((terminator + indent) as NSString).length
            return AutoIndentPlan(range: NSRange(location: start, length: 0),
                                  replacement: replacement,
                                  caret: caret)
        }

        // 光标后面还有正文（`if x { return`）：不猜，交还系统。
        return nil
    }

    // MARK: - ④ 智能粘贴

    /// 多行粘贴该怎么落。返回 `nil` = **交还系统粘贴**（单行 / 空块 / 没有要改的缩进）。
    public static func paste(_ pasted: String,
                             into text: String,
                             selection: NSRange,
                             indentUnit unit: String = AutoIndent.unit) -> AutoIndentPlan? {
        guard !pasted.isEmpty else { return nil }
        let ns = text as NSString
        let length = ns.length
        let start = min(max(0, selection.location), length)
        let end = min(max(start, start + max(0, selection.length)), length)

        let line = lineBounds(around: start, in: ns)
        let terminator: String
        if let line, !line.terminator.isEmpty {
            terminator = line.terminator
        } else {
            terminator = documentTerminator(in: ns)
        }
        let normalized = normalizedNewlines(pasted, to: terminator)
        let lines = normalized.components(separatedBy: terminator)
        // 单行粘贴：不重排（\"不把外来缩进硬塞进来\" 不等于\"替它改缩进\"）。
        guard lines.count > 1 else { return nil }

        let contextIndent: String
        if let line {
            let prefix = ns.substring(with: NSRange(location: line.start, length: start - line.start))
            contextIndent = leadingWhitespace(prefix)
        } else {
            contextIndent = ""
        }

        let foreign = commonLeadingWhitespace(of: lines)
        var reindented: [String] = []
        reindented.reserveCapacity(lines.count)
        for (index, lineText) in lines.enumerated() {
            if lineText.trimmingCharacters(in: .whitespaces).isEmpty {
                reindented.append("")            // 空白行保持空白（不留尾随空格）
            } else if index == 0 {
                // **第一行不加上下文缩进**：光标前面那段文本（含它已有的缩进）就是它的上下文，
                // 再加一次会在缩进过的空行上叠成双倍（实测最典型的一处）。
                reindented.append(String(lineText.dropFirst(foreign.count)))
            } else {
                reindented.append(contextIndent + String(lineText.dropFirst(foreign.count)))
            }
        }
        let replacement = reindented.joined(separator: terminator)
        // 没有要改的（顶格粘到顶格 / 本来就对齐）⇒ 交还系统，别把默认粘贴换掉。
        guard replacement != normalized else { return nil }
        return AutoIndentPlan(range: NSRange(location: start, length: end - start),
                              replacement: replacement,
                              caret: start + (replacement as NSString).length)
    }

    // MARK: - 行与空白

    /// 光标所在行：行首 / 内容末尾 / 行终止符（`CodeLines` 用的是同一个原语
    /// `NSString.getLineStart`，这里只为「这一行在哪」取一次，不另数换行）。
    struct LineBounds {
        let start: Int
        let contentsEnd: Int
        let terminator: String
    }

    static func lineBounds(around offset: Int, in ns: NSString) -> LineBounds? {
        var start = 0, end = 0, contentsEnd = 0
        ns.getLineStart(&start, end: &end, contentsEnd: &contentsEnd,
                        for: NSRange(location: min(max(0, offset), ns.length), length: 0))
        guard start <= contentsEnd, contentsEnd <= end, end <= ns.length else { return nil }
        let terminator = end > contentsEnd
            ? ns.substring(with: NSRange(location: contentsEnd, length: end - contentsEnd))
            : ""
        return LineBounds(start: start, contentsEnd: contentsEnd, terminator: terminator)
    }

    /// 文档的第一个行终止符（缺省 `\n`）—— 最后一行没有终止符时用它，别在 `\r\n` 文档里插裸 `\n`。
    static func documentTerminator(in ns: NSString) -> String {
        let text = ns as String
        if text.contains("\r\n") { return "\r\n" }
        if text.contains("\n") { return "\n" }
        if text.contains("\r") { return "\r" }
        return "\n"
    }

    /// 把粘贴文本的行终止符统一成 `terminator`。
    static func normalizedNewlines(_ text: String, to terminator: String) -> String {
        var out = text.replacingOccurrences(of: "\r\n", with: "\n")
        out = out.replacingOccurrences(of: "\r", with: "\n")
        out = out.replacingOccurrences(of: "\u{2028}", with: "\n")
        out = out.replacingOccurrences(of: "\u{2029}", with: "\n")
        return terminator == "\n" ? out : out.replacingOccurrences(of: "\n", with: terminator)
    }

    static func leadingWhitespace(_ text: String) -> String {
        var out = ""
        for character in text {
            guard character == " " || character == "\t" else { break }
            out.append(character)
        }
        return out
    }

    static func trimLeadingWhitespace(_ text: String) -> String {
        String(text.dropFirst(leadingWhitespace(text).count))
    }

    static func firstNonWhitespace(_ text: String) -> Character? {
        for character in text where character != " " && character != "\t" {
            return character
        }
        return nil
    }

    /// 少一级：单位对得上就整段去掉，对不上一律退回空串（**不出现负缩进、也不无级可减时造一级**）。
    static func dedent(_ indent: String, by unit: String) -> String {
        guard !indent.isEmpty, indent.hasSuffix(unit) else { return "" }
        return String(indent.dropLast(unit.count))
    }

    static func commonLeadingWhitespace(of lines: [String]) -> String {
        var prefixes: [String] = []
        for line in lines where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            prefixes.append(leadingWhitespace(line))
        }
        guard var common = prefixes.first else { return "" }
        for prefix in prefixes.dropFirst() {
            while !common.isEmpty && !prefix.hasPrefix(common) { common.removeLast() }
            if common.isEmpty { break }
        }
        return common
    }

    static func isOpener(_ character: Character) -> Bool {
        character == "{" || character == "(" || character == "["
    }

    static func isCloser(_ character: Character) -> Bool {
        character == "}" || character == ")" || character == "]"
    }

    static func pairs(_ opener: Character, _ closer: Character) -> Bool {
        switch (opener, closer) {
        case ("{", "}"), ("(", ")"), ("[", "]"): return true
        default: return false
        }
    }
}
