import Foundation

/// **代码编辑器的行号口径**（FR-EDIT-36「编辑器行号列」，队列 L-64）。
///
/// 为什么放 Core、不留在视图里：行号看着是"画出来的东西"，但**哪一行算第几行**是纯逻辑 ——
/// 行终止符有 `\n` / `\r\n` / `\r` / `U+2028` / `U+2029` / `U+0085` 好几种写法，末尾换行算不算
/// 多一行、混排中文与 emoji 时按什么单位数，这些一旦错了，界面上的表现是"行号跟内容对不上"，
/// 既难查也没法测。放进 Core 就能逐条钉住（`Tests/CodeLinesTests.swift`）。
///
/// ## 两条口径（都是拍出来的，不是顺手写的）
///
/// **① 单位 = UTF-16 偏移**，不是 `String.Index`。行号最终要落到 `NSLayoutManager` /
/// `NSRange` 的字符索引上，而 `String` 的 `Index` 数的是"字符"：含 emoji 的一行里两者会差
/// （`"😀\n"` 是 3 个 UTF-16 单元、2 个字符）⇒ 中文注释一多行号就整体偏。单位必须与画它的那一层一致。
///
/// **② 末尾是行终止符 ⇒ 多一个空行**（`"a\n"` 是 **2** 行，不是 1 行）。理由 = 光标真的能停在
/// 那一行上：`NSTextView` 会为末尾终止符生成 **extra line fragment**，用户点在那个空行里是有反应的。
/// 少给一个号，会出现"光标在那一行、左边却没有行号"的错位。
///
/// 「行」的定义直接借用 `NSString.getLineStart(_:end:contentsEnd:for:)` —— 与 AppKit 自己认的
/// 行终止符同源，所以 Core 算出来的行号与编辑器**实际画出来的行**是同一件事，
/// 不另立一套判据（另立一套 = 迟早对不上）。
public enum CodeLines {

    /// 每个逻辑行的**起始位置**（UTF-16 偏移，严格递增，至少有一个元素）。
    ///
    /// 空文档返回 `[0]` —— 「什么都没有」仍然是**第 1 行**（编辑器可以落光标）。
    public static func lineStarts(in text: String) -> [Int] {
        let ns = text as NSString
        let length = ns.length
        var starts: [Int] = [0]
        var cursor = 0

        while cursor < length {
            var lineEnd = 0
            var contentsEnd = 0
            ns.getLineStart(nil, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: cursor, length: 0))
            // 守卫：拿不到更靠后的位置就停（宁可少一行，也不许死循环 —— 行号列是每次重绘都跑的代码）。
            guard lineEnd > cursor else { break }
            guard lineEnd < length else {
                // 最后一行：末尾带行终止符时，光标还能停在它后面那一行（见口径 ②）。
                if contentsEnd < lineEnd { starts.append(length) }
                break
            }
            starts.append(lineEnd)
            cursor = lineEnd
        }
        return starts
    }

    /// 行数（空文档 = 1）。
    public static func count(in text: String) -> Int {
        lineStarts(in: text).count
    }

    /// 行号列要留几位数（`digits(9) = 1` / `digits(10) = 2`）——
    /// 宽度不能用固定值：99 行与 10000 行的列宽不一样，写死就会在第 100 行处把数字挤掉。
    public static func gutterDigits(in text: String) -> Int {
        digits(of: count(in: text))
    }

    /// 行号列几位数（供视图与单测共用同一口径）。
    public static func digits(of lineCount: Int) -> Int {
        max(1, String(max(1, lineCount)).count)
    }

    /// 位置 `offset`（UTF-16 偏移）落在**第几行**（从 1 起）。
    ///
    /// 越界一律夹到两端（不改调用方行为、也不崩）；`offset == length` 落**最后一行**
    /// —— 视图里"末尾空行"那一格的查询正是这个位置。
    public static func lineNumber(at offset: Int, in text: String) -> Int {
        let starts = lineStarts(in: text)
        return lineNumber(at: offset, lineStarts: starts)
    }

    /// 第 `line` 行（1 起）在文本里占的 **UTF-16 范围**（含该行的行终止符）。
    ///
    /// 用途 = `lineNumber(at:)` 的**逆运算**：内容检索命中给的是**行号**
    /// （`FR-EDIT-44` 的「回车打开并跳到命中行」），编辑器要跳过去就得把行号换回
    /// `NSRange`。这条换算与 `lineNumber(at:)` 必须同一份实现 —— 两处各写一套
    /// （一处按 `\n` 数、一处按 `NSString.getLineStart` 数）在 `U+2028` 这类行终止符上
    /// 会给出**不同的行号**，症状是「跳到了相邻几行」，且是静默的。
    ///
    /// 越界（`< 1` 或 `> count(in:)`）返回 `nil`：宁可让调用方看见"没有这一行"，
    /// 也不要夹到别的行上去（跳错行比不跳更难查）。
    public static func range(ofLine line: Int, in text: String) -> NSRange? {
        let ns = text as NSString
        return range(ofLine: line, lineStarts: lineStarts(in: text), length: ns.length)
    }

    /// 同上，但用**已经算好的** `lineStarts` 与文本长度（视图里一次跳一行，不必重算整篇）。
    public static func range(ofLine line: Int, lineStarts starts: [Int], length: Int) -> NSRange? {
        guard line >= 1, line <= starts.count else { return nil }
        let start = starts[line - 1]
        let end = line < starts.count ? starts[line] : length
        return NSRange(location: start, length: max(0, end - start))
    }

    /// 每个逻辑行的**内容范围**（**不含**行终止符）—— 与 `lineStarts(in: count:at:)` 同一份切法。
    ///
    /// 用途 = 「按行读原文」：内容检索命中要给**该行原文**做摘要，而摘要是摆给用户看的，
    /// 末尾多带一个 `\n` 只会在结果列表里多出一片空白。
    /// 行号与切法仍由本类型唯一决定（调用方不要另写一套 `components(separatedBy: "\n")` ——
    /// 那样在 `U+2028` 这类终止符上与编辑器行号会分叉）。
    public static func contentRanges(in text: String) -> [NSRange] {
        let ns = text as NSString
        let length = ns.length
        let starts = lineStarts(in: text)
        return starts.enumerated().map { index, start in
            let end = index + 1 < starts.count ? starts[index + 1] : length
            return NSRange(location: start, length: max(0, contentEnd(ofLineAt: start, end: end, in: ns) - start))
        }
    }

    /// 一行的内容末尾（去掉行终止符）。`\r\n` 算两字节，其余终止符各一字节。
    private static func contentEnd(ofLineAt start: Int, end: Int, in ns: NSString) -> Int {
        var contentEnd = end
        guard contentEnd > start else { return contentEnd }
        let last = ns.character(at: contentEnd - 1)
        guard last == 0x0A || last == 0x0D || last == 0x2028 || last == 0x2029 || last == 0x0085 else {
            return contentEnd
        }
        contentEnd -= 1
        if last == 0x0A, contentEnd > start, ns.character(at: contentEnd - 1) == 0x0D {
            contentEnd -= 1
        }
        return contentEnd
    }

    /// 同上，但用**已经算好的** `lineStarts`（视图每次重绘要问很多次，不该反复重算整篇文本）。
    public static func lineNumber(at offset: Int, lineStarts starts: [Int]) -> Int {
        guard !starts.isEmpty else { return 1 }
        guard let last = starts.last else { return 1 }
        let clamped = min(max(0, offset), last)
        // 二分：找最后一个 `<= clamped` 的行起点。
        var low = 0
        var high = starts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if starts[mid] <= clamped { low = mid } else { high = mid - 1 }
        }
        return low + 1
    }
}
