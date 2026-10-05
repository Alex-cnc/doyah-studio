import Foundation

/// 一次 Markdown 编辑动作的**落法**：要替换哪一段、换成什么、光标停在哪。
///
/// 坐标一律是 **UTF-16 单元** —— 与 `NSTextView.selectedRange()` / `NSRange` 同一套，
/// 而不是 `String.Index`（两者在含 emoji / 中文的行上会差；`Core/CodeLines` 头顶那段
/// 注释讲过同一个坑，这里沿用它的口径）。
public struct MarkdownEditPlan: Equatable, Sendable {
    /// 要替换的范围（UTF-16）。
    public let range: NSRange
    /// 替换成什么。
    public let replacement: String
    /// 替换**完成后**的光标位置（UTF-16）。长度取 0（不选中任何字符）——
    /// 用户的下一个动作是接着敲字，替他选中一段只会让他多按一次方向键。
    public let caret: Int

    public init(range: NSRange, replacement: String, caret: Int) {
        self.range = range
        self.replacement = replacement
        self.caret = caret
    }
}

/// Markdown 编辑手感（`FR-EDIT-47` / `FR-EDIT-48`）：**列表续行**与**任务勾选翻转**。
///
/// ## 为什么是纯逻辑、纯函数
///
/// 这一族的判据天然是「给『文本 + 光标』要『期望文本 + 期望光标』」—— 完全可以在 Core 里
/// 逐条钉住。写在 `NSTextView` 的代理里就只能靠人工开界面复测，而「回车之后光标停在
/// 第几个字符」恰恰是这类手感最容易错半个字符的地方（少一个空格的 `-item` 与多一个空格的
/// `-  item` 都是错，且都只在界面上看得出来）。宿主层（`CodeTextView`）只负责把计划搬过去。
///
/// ## 口径（每一条都有判据）
///
/// · **只认完整的标记**：`-` 后面必须跟空格才是列表项（`-x`、`---` 都不是）；
/// · **光标必须在标记之后**：`-| item` 这种「标记还没敲完」的回车就是普通换行；
/// · **空项回车 = 退出列表**：整条前缀（缩进 + 引用号 + 标记）一起去掉，得到一行空行 ——
///   连着两下回车就该离开列表，而不是无限续出一个空条目；
/// · **新条目一律未勾选**：`- [x] ` 回车接着写的是下一件事，不是又一件已完成的事；
/// · **有序编号递增**（`9. ` → `10. `），**不补空格对齐**（补了反而与用户自己敲的对不齐）；
/// · **有选区时不接**：那一下回车的意思是把选中的文字换掉，不是续行。
public enum MarkdownListEditing {

    // MARK: - 续行（FR-EDIT-47）

    /// 回车时要插入什么。返回 `nil` = **按普通换行处理**（不是失败，是「这条口径不适用」）。
    public static func continuation(in text: String, selection: NSRange) -> MarkdownEditPlan? {
        guard selection.length == 0 else { return nil }
        let ns = text as NSString
        guard let line = scan(ns, at: selection.location) else { return nil }
        // 标记还没敲完（光标在标记内部）⇒ 这一下回车就是普通换行。
        guard selection.location >= line.markerEnd else { return nil }

        // 空项 ⇒ 退出列表：整条前缀一起去掉。
        if line.body.isEmpty {
            return MarkdownEditPlan(
                range: NSRange(location: line.lineStart, length: line.markerEnd - line.lineStart),
                replacement: "",
                caret: line.lineStart
            )
        }

        let insertion = "\n" + nextPrefix(for: line)
        return MarkdownEditPlan(
            range: NSRange(location: selection.location, length: 0),
            replacement: insertion,
            caret: selection.location + (insertion as NSString).length
        )
    }

    // MARK: - 任务勾选翻转（FR-EDIT-48）

    /// 勾 / 取消勾选**光标所在行**的任务框。返回 `nil` = 这一行没有任务框（那一下按键不该被吞）。
    public static func toggleTask(in text: String, selection: NSRange) -> MarkdownEditPlan? {
        guard selection.length == 0 else { return nil }
        let ns = text as NSString
        guard let line = scan(ns, at: selection.location), line.isTask,
              let box = taskBoxRange(in: ns, from: line.lineStart, to: line.contentsEnd)
        else { return nil }

        let checked = isChecked(ns.character(at: box.location + 1))
        let flipped = checked ? uncheckedState : checkedState
        // 只换**方框里那一个字符**（`[ ]` ⇄ `[x]`）：等长替换 ⇒ 光标不用动，
        // 方括号本身也一字不动（把三个字符一起换掉会把 `[x]` 写成 `x`）。
        let state = NSRange(location: box.location + 1, length: 1)
        return MarkdownEditPlan(range: state, replacement: flipped, caret: selection.location)
    }

    // MARK: - 行扫描（唯一的解析处）

    /// 一行的「前缀」（缩进 + 引用号 + 列表标记）与它后面的正文。
    struct LineScan {
        /// 这一行的起点（含缩进）。
        let lineStart: Int
        /// 行内容结束（**不含**换行符）。
        let contentsEnd: Int
        /// 缩进 + 引用号 + 列表标记（**含标记后的那一个空格**），原样可复用。
        let prefix: String
        /// 前缀结束的位置；光标必须 ≥ 它，续行才成立。
        let markerEnd: Int
        /// 有序标记的编号 / 分隔符（`.` / `)`）与它在**本行内**的范围；无序为 `nil`。
        /// 范围是「相对行首」的 —— 前缀字符串就是从行首开始的，换编号时要用它，
        /// 不能靠 `hasSuffix` 去猜（`1. [ ] ` 这种既是有序又是任务的行的尾部并不是编号）。
        let ordered: (delimiter: String, number: Int, range: NSRange)?
        /// 是不是任务项（`- [ ] ` / `- [x] `）。
        let isTask: Bool
        /// 标记之后的正文（原样，用来判「空项」）。
        let body: String
    }

    /// 扫光标所在行。返回 `nil` = **这一行不是列表项**（含：整行是分隔线 `* * *`）。
    static func scan(_ ns: NSString, at caret: Int) -> LineScan? {
        guard caret >= 0, caret <= ns.length else { return nil }
        var start = 0
        var end = 0
        var contentsEnd = 0
        ns.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: caret, length: 0))
        // 解析用**整行内容**（不按光标截断）：判「空项」要看这一行是不是真的没内容 ——
        // 按光标截断的话，`- [ ] |洗车` 会被当成空项、把整行清掉，尾巴上的「洗车」就丢了。
        let contentEnd = contentsEnd
        let lineText = ns.substring(with: NSRange(location: start, length: contentEnd - start))
        if isThematicBreak(lineText) { return nil }

        var i = start
        // ① 缩进（空格 / 制表符，原样保留）
        while i < contentEnd, isSpaceOrTab(ns.character(at: i)) { i += 1 }
        // ② 引用号（可叠加：`>` / `> ` / `> > `）
        while i < contentEnd, ns.character(at: i) == char(">") {
            i += 1
            if i < contentEnd, ns.character(at: i) == char(" ") { i += 1 }
        }
        // ③ 列表标记：无序 `- ` / `* ` / `+ `；有序 `1. ` / `1) `
        var ordered: (delimiter: String, number: Int, range: NSRange)?
        var isBullet = false
        if i < contentEnd {
            let c = ns.character(at: i)
            if isBulletChar(c), i + 1 < contentEnd, ns.character(at: i + 1) == char(" ") {
                isBullet = true
                i += 2
            } else if isDigit(c) {
                var j = i
                while j < contentEnd, isDigit(ns.character(at: j)) { j += 1 }
                if j < contentEnd, isOrderedDelimiter(ns.character(at: j)),
                   j + 1 < contentEnd, ns.character(at: j + 1) == char(" ") {
                    let digits = ns.substring(with: NSRange(location: i, length: j - i))
                    let delimiter = ns.substring(with: NSRange(location: j, length: 1))
                    ordered = (
                        delimiter: delimiter,
                        number: Int(digits) ?? 1,
                        range: NSRange(location: i - start, length: j - i + 2)
                    )
                    i = j + 2
                }
            }
        }
        guard isBullet || ordered != nil else { return nil }

        // ④ 任务框：只认紧跟标记的那一个（`[ ]` / `[x]` / `[X]`），后面可以直接是行尾。
        var isTask = false
        if i + 2 < contentEnd, ns.character(at: i) == char("["), ns.character(at: i + 2) == char("]"),
           isTaskState(ns.character(at: i + 1)) {
            i += 3
            if i < contentEnd, ns.character(at: i) == char(" ") { i += 1 }
            isTask = true
        }

        return LineScan(
            lineStart: start,
            contentsEnd: contentEnd,
            prefix: ns.substring(with: NSRange(location: start, length: i - start)),
            markerEnd: i,
            ordered: ordered,
            isTask: isTask,
            body: ns.substring(with: NSRange(location: i, length: contentEnd - i))
        )
    }

    // MARK: - 下一行的前缀

    static func nextPrefix(for line: LineScan) -> String {
        var prefix = line.prefix
        if let ordered = line.ordered {
            // 只换编号那一格（连同分隔符后面的空格），缩进与引用号原样跟着走（`> 9. ` → `> 10. `）。
            let next = "\(ordered.number + 1)\(ordered.delimiter) "
            prefix = (prefix as NSString).replacingCharacters(in: ordered.range, with: next)
        }
        if line.isTask {
            // 新条目一律未勾选：把方框里那一个字符改回空格，其余一字不动。
            let nsPrefix = prefix as NSString
            if let box = taskBoxRange(in: nsPrefix, from: 0, to: nsPrefix.length) {
                let state = NSRange(location: box.location + 1, length: 1)
                prefix = nsPrefix.replacingCharacters(in: state, with: uncheckedState)
            }
        }
        return prefix
    }

    // MARK: - 词法小件

    /// 任务框的状态字符：` ` = 未勾选、`x` / `X` = 已勾选。写在这里**只此一处**。
    static let uncheckedState = " "
    static let checkedState = "x"

    static func isTaskState(_ c: unichar) -> Bool {
        c == char(" ") || c == char("x") || c == char("X")
    }

    static func isChecked(_ c: unichar) -> Bool { c == char("x") || c == char("X") }

    /// 行内第一个任务框 `[?]` 的范围（`from..<to` 之内）。
    static func taskBoxRange(in ns: NSString, from: Int, to: Int) -> NSRange? {
        var i = from
        while i + 2 < to {
            if ns.character(at: i) == char("["), ns.character(at: i + 2) == char("]"),
               isTaskState(ns.character(at: i + 1)) {
                return NSRange(location: i, length: 3)
            }
            i += 1
        }
        return nil
    }

    /// 主题分隔线（`---` / `***` / `___`，空白与制表符隔开也算，至少三个）——
    /// 它长得像无序列表（`* * *`），但回车续一行「* 」显然不是用户要的。
    static func isThematicBreak(_ line: String) -> Bool {
        let stripped = line.filter { $0 != " " && $0 != "\t" }
        guard stripped.count >= 3, let first = stripped.first, first == "-" || first == "*" || first == "_" else {
            return false
        }
        return stripped.allSatisfy { $0 == first }
    }

    private static func isBulletChar(_ c: unichar) -> Bool { c == char("-") || c == char("*") || c == char("+") }
    private static func isOrderedDelimiter(_ c: unichar) -> Bool { c == char(".") || c == char(")") }
    private static func isDigit(_ c: unichar) -> Bool { c >= char("0") && c <= char("9") }
    private static func isSpaceOrTab(_ c: unichar) -> Bool { c == char(" ") || c == 0x09 }

    /// 单字符 ASCII 的 `unichar`（本文件只处理 ASCII 结构字符，用不上 Unicode 标量）。
    private static func char(_ s: Character) -> unichar { unichar(s.asciiValue ?? 0) }
}

/// 这一族手感**对哪些文档生效**（唯一出处）。
///
/// 只对 Markdown：`- ` / `* ` / `[ ]` 在别的语言里是别的东西 —— YAML 的列表用同一套符号
/// （但 `[x]` 是数组），SQL 里的 `-` 是减号，纯文本里用户想要的往往是**原样的回车**。
/// 判据在 `Tests/MarkdownEditingTests.swift`：换一门语言就一个字都不许动。
public enum MarkdownEditingScope {
    public static func applies(to language: TextLanguage) -> Bool { language == .markdown }
}
