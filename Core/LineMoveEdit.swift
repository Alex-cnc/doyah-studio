import Foundation

/// 一次「移行 / 复制行」编辑动作的落法（与 `CodePairingPlan` / `CodeCommentPlan` / `MarkdownEditPlan` 同口径：
/// UTF-16 坐标、**一次整块替换**）。
///
/// 为什么是整块而不是几次小替换：宿主走 `shouldChangeText → replaceCharacters → didChangeText`
/// 时，**一次替换 = 一步 ⌘Z**。拆成「删一行、再插一行」会变成两步撤销，
/// 用户按一次 ⌘Z 只会把行插回去、正文却少了一块。
public struct LineMovePlan: Equatable, Sendable {
    /// 要替换的范围（UTF-16）—— **受影响的整块行**。
    public let range: NSRange
    /// 替换成什么。
    public let replacement: String
    /// 替换完成后的选区起点（UTF-16）。
    public let caret: Int
    /// 替换完成后的选区长度（0 = 只有光标）。
    public let selectionLength: Int

    public init(range: NSRange, replacement: String, caret: Int, selectionLength: Int = 0) {
        self.range = range
        self.replacement = replacement
        self.caret = caret
        self.selectionLength = selectionLength
    }
}

/// 移行方向（`⌥↑` / `⌥↓`）。
public enum LineMoveDirection: Sendable {
    case up
    case down
}

/// 移行与复制行（`FR-STD-WS-EDIT-009`）：`⌥↑` / `⌥↓` 整行（或选中整段）上移 / 下移，`⇧⌥↓` 向下复制。
///
/// ## 为什么是纯函数
///
/// 判据天然是「给『文本 + 选区』要『期望文本 + 期望选区』」—— 这族最容易错的不是\"换顺序\"，
/// 而是三件只在界面上\"看着别扭\"的事：
///
/// · **行终止符算谁的**：`"a\r\n"` 上移一位若把 `\r\n` 留在原地，两行会粘成 `"ba\r\n"`；
///   **末尾那一行没有终止符**（`"a\nb"` 里的 `b`）更麻烦 —— 它一旦上移，就得从别人那里
///   借一个终止符，否则会和上一行合成一行。所以本文件把行拆成「内容」与「终止符」两半，
///   **终止符按位置留、内容按行搬**：这样文档末尾\"有没有换行符\"这件事整体不变，
///   而各行的内容顺序真的换了；
/// · **光标 / 选区跟不跟**：跟着走 —— 但\"跟\"不是把光标加一个常数，
///   而是**光标之前有几行搬过去了**就挪多长（多行选区里每行长度不同，用常数会偏）；
/// · **首行上移 / 末行下移 / 空文档**：**交还系统**（返回 `nil`，不是失败也不是报错）——
///   需求 ④ 的原话是\"无操作且不报错\"。
///
/// ## 口径（每条都有判据）
///
/// · **影响范围 = 选区覆盖的整行**（无选区 ⇒ 光标那一行）；选区终点落在行首 ⇒ **不算进那一行**
///   （与 `CodeCommentToggling` 同一套取法，主流编辑器一致）；
/// · **一次移动只跨一行**（上移 = 与上一行交换，下移 = 与下一行交换）：多行选区是**整段**跨，
///   不是逐行各跨（逐行会把段内顺序也搅乱）；
/// · **复制 = 副本紧随原行**（需求 ③），**选区留在原件上**（连按 `⇧⌥↓` 得到 N 份，光标不会跟着往下跑）；
/// · **空行照样能移 / 能复制**（需求 ⑤）：空行的\"内容\"是空串，逻辑与普通行一字不差；
/// · **行数口径只走 `CodeLines`**（行号列 / 跳行 / 高亮同一份实现），本文件不自己数 `\n` ——
///   否则 `U+2028` 这类终止符上会与编辑器画出来的行分叉；
/// · **不做语义重构**（需求\"不做\"列）：只搬行，不改缩进、不重命名、不动注释。
public enum LineMoveEdit {

    /// `⌥↑` / `⌥↓` 该怎么落。返回 `nil` = **无操作**（首行上移 / 末行下移 / 空文档）。
    public static func move(in text: String, selection: NSRange,
                            direction: LineMoveDirection) -> LineMovePlan? {
        guard let layout = LineLayout(text: text, selection: selection) else { return nil }
        switch direction {
        case .up: return layout.movedUp()
        case .down: return layout.movedDown()
        }
    }

    /// `⇧⌥↓` 该怎么落。返回 `nil` = **无操作**（空文档）。
    public static func duplicate(in text: String, selection: NSRange) -> LineMovePlan? {
        guard let layout = LineLayout(text: text, selection: selection) else { return nil }
        return layout.duplicatedDown()
    }

    /// 文档的**行布局**（内容 / 终止符分开存）。只为上面两个入口服务，不对外。
    ///
    /// 只在构造时算一次：一次编辑动作里行数可能上万（大文档），
    /// 判据要的是\"对\"，界面要的是\"不卡\"。
    struct LineLayout {
        let ns: NSString
        let length: Int
        /// 每行的起始偏移（`CodeLines` 口径，末尾带终止符时多一个空行）。
        let starts: [Int]
        /// 每行的**内容**（不含行终止符）。
        let contents: [String]
        /// 每行的**行终止符**（`"\n"` / `"\r\n"` / `""`…）；只有文档最后一行可能是空串。
        let terms: [String]
        /// 选区覆盖的第一行 / 最后一行（**0 起**的下标）。
        let first: Int
        let last: Int
        /// 光标相对**所在行行首**的偏移（UTF-16）。
        let caretRel: Int
        /// 选区终点相对**最后一行行首**的偏移（UTF-16）。无选区时等于 `caretRel`。
        let endRel: Int
        /// 原选区（已夹进文档范围）。
        let selection: NSRange

        init?(text: String, selection raw: NSRange) {
            guard !text.isEmpty else { return nil }
            let ns = text as NSString
            let length = ns.length
            let starts = CodeLines.lineStarts(in: text)
            guard !starts.isEmpty else { return nil }
            let contentRanges = CodeLines.contentRanges(in: text)
            guard contentRanges.count == starts.count else { return nil }

            var contents: [String] = []
            var terms: [String] = []
            contents.reserveCapacity(starts.count)
            terms.reserveCapacity(starts.count)
            for index in starts.indices {
                let lineEnd = index + 1 < starts.count ? starts[index + 1] : length
                let content = contentRanges[index]
                contents.append(ns.substring(with: content))
                let termStart = NSMaxRange(content)
                terms.append(termStart < lineEnd
                             ? ns.substring(with: NSRange(location: termStart, length: lineEnd - termStart))
                             : "")
            }

            let start = min(max(0, raw.location), length)
            let end = min(max(start, start + max(0, raw.length)), length)
            let clamped = NSRange(location: start, length: end - start)

            // 行号换算走 `CodeLines`（与行号列同一份，不另数换行）。
            let firstIndex = CodeLines.lineNumber(at: start, lineStarts: starts) - 1
            // 选区终点落在**行首**时不算进那一行 —— 取终点前一个字符所在的行走（`CodeCommentToggling` 同款）。
            let probe = end > start ? max(start, end - 1) : start
            let lastIndex = CodeLines.lineNumber(at: probe, lineStarts: starts) - 1
            guard firstIndex >= 0, firstIndex < starts.count,
                  lastIndex >= firstIndex, lastIndex < starts.count else { return nil }

            self.ns = ns
            self.length = length
            self.starts = starts
            self.contents = contents
            self.terms = terms
            self.first = firstIndex
            self.last = lastIndex
            self.caretRel = start - starts[firstIndex]
            self.endRel = end - starts[lastIndex]
            self.selection = clamped
        }

        /// 第 `index` 行（**含终止符**）在文档里的结束偏移。
        func lineEnd(_ index: Int) -> Int {
            index + 1 < starts.count ? starts[index + 1] : length
        }

        /// 按「内容按行搬、终止符按位置留」重建一段文本。
        func text(_ replacementContents: [String], positions: ClosedRange<Int>) -> String {
            var out = ""
            for position in positions {
                out += replacementContents[position]
                out += terms[position]
            }
            return out
        }

        /// 行起点表（相对于给定区间起点 `origin`）。
        func relativeStarts(_ replacementContents: [String], positions: ClosedRange<Int>) -> [Int: Int] {
            var map: [Int: Int] = [:]
            var offset = 0
            for position in positions {
                map[position] = offset
                offset += (replacementContents[position] as NSString).length
                offset += (terms[position] as NSString).length
            }
            return map
        }

        /// 光标 / 选区终点按「原来在第几行的第几个字符 ⇒ 那一行现在在哪」搬过去。
        ///
        /// 不用「加一个常数」：多行选区里每行长短不一，常数一加就偏；
        /// 而且换行符可能是 `\r\n`（两字节），跨一行不一定跨两个字符。
        func plan(range: NSRange, replacement: String, origin: Int,
                  caretIndex oldCaret: Int, endIndex oldEnd: Int,
                  newStarts: [Int: Int], replacementContents: [String]) -> LineMovePlan {
            let caretBase = newStarts[oldCaret] ?? 0
            let caretRoom = (replacementContents[oldCaret] as NSString).length
                + (terms[oldCaret] as NSString).length
            let caret = origin + caretBase + min(caretRel, caretRoom)

            let endBase = newStarts[oldEnd] ?? caretBase
            let endRoom = (replacementContents[oldEnd] as NSString).length
                + (terms[oldEnd] as NSString).length
            let end = origin + endBase + min(endRel, endRoom)

            return LineMovePlan(range: range,
                                replacement: replacement,
                                caret: caret,
                                selectionLength: max(0, end - caret))
        }

        func movedUp() -> LineMovePlan? {
            guard first > 0 else { return nil }   // 首行上移 = 无操作（需求 ④）
            let regionStart = starts[first - 1]
            let regionEnd = lineEnd(last)
            let positions = (first - 1)...last

            var newContents = contents
            let lifted = contents[first - 1]
            for position in first...last { newContents[position - 1] = contents[position] }
            newContents[last] = lifted

            // 旧下标 → 新下标：first...last 各上移一位，原来那一行（first-1）落到 last。
            var newIndex: [Int: Int] = [:]
            for position in first...last { newIndex[position] = position - 1 }
            newIndex[first - 1] = last

            let replacement = text(newContents, positions: positions)
            let startsMap = relativeStarts(newContents, positions: positions)
            var mapped: [Int: Int] = [:]
            for (old, new) in newIndex { mapped[old] = startsMap[new] ?? 0 }

            return plan(range: NSRange(location: regionStart, length: regionEnd - regionStart),
                        replacement: replacement, origin: regionStart,
                        caretIndex: first, endIndex: last,
                        newStarts: mapped, replacementContents: newContents)
        }

        func movedDown() -> LineMovePlan? {
            guard last + 1 < starts.count else { return nil }   // 末行下移 = 无操作（需求 ④）
            let regionStart = starts[first]
            let regionEnd = lineEnd(last + 1)
            let positions = first...(last + 1)

            var newContents = contents
            let dropped = contents[last + 1]
            for position in stride(from: last, through: first, by: -1) {
                newContents[position + 1] = contents[position]
            }
            newContents[first] = dropped

            var newIndex: [Int: Int] = [:]
            for position in first...last { newIndex[position] = position + 1 }
            newIndex[last + 1] = first

            let replacement = text(newContents, positions: positions)
            let startsMap = relativeStarts(newContents, positions: positions)
            var mapped: [Int: Int] = [:]
            for (old, new) in newIndex { mapped[old] = startsMap[new] ?? 0 }

            return plan(range: NSRange(location: regionStart, length: regionEnd - regionStart),
                        replacement: replacement, origin: regionStart,
                        caretIndex: first, endIndex: last,
                        newStarts: mapped, replacementContents: newContents)
        }

        func duplicatedDown() -> LineMovePlan? {
            let blockStart = starts[first]
            let blockEnd = lineEnd(last)
            guard blockEnd > blockStart else { return nil }
            let block = ns.substring(with: NSRange(location: blockStart, length: blockEnd - blockStart))

            // 块尾没有终止符（文档到此为止）⇒ 副本要**先借一个终止符**再落，否则两份会粘成一行。
            // 借谁的：块前一行的终止符（同一份文档的书写习惯）；块在最前面就退回 `"\n"`。
            var insertion = block
            if terms[last].isEmpty {
                let separator = first > 0 ? terms[first - 1] : "\n"
                insertion = separator + block
            }

            // 选区留在**原件**上（连按 `⇧⌥↓` 得到 N 份、光标不往下跑）—— 这是本文件的口径，判据钉住它。
            return LineMovePlan(range: NSRange(location: blockEnd, length: 0),
                                replacement: insertion,
                                caret: selection.location,
                                selectionLength: selection.length)
        }
    }
}
