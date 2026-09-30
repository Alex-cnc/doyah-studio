import Foundation

/// 工作区 Markdown 预览的**块级模型**（契约层：纯函数、可单测、只依赖 Foundation）。
///
/// ## 为什么要有这一层（队列 `L-137`）
///
/// 需求提出者 2026-09-30：「工作区的编辑器还要带 markdown 预览功能」。路线**只能是复用笔记侧的
/// Markdown 解析 + 平台层只做渲染**（`Docs/design/规划-工作区Markdown预览与内置浏览器-20260930.md` §1.2）：
///   · SwiftUI 自带的 `AttributedString(markdown:)` 只有**行内**标记，标题 / 列表 / 表格 / 代码块全不支持 ⇒ 达不到预览的基本盘；
///   · 第三方渲染库会在这个仓里造出**第二套 Markdown 解析**（笔记侧一套、编辑器一套）⇒ 同一份文档两处口径；
///   · 所以块级结构由**本文件**一处产出，行内标记由**笔记侧同一函数**产出（`NoteBodyProjection.parseInline`），
///     平台层只负责把模型画出来。**「不许第二套解析」由 `Scripts/check-markdown-single-source.py` 守。**
///
/// ## 支持的子集（GFM 的可用子集，刻意小）
///
/// 标题（ATX `#`~`######`）· 段落（软换行**原样保留成 `\n`**，怎么显示由平台层决定）·
/// 无序列表 / 有序列表（含嵌套，嵌套内容进 `children`）· 任务列表（`- [x]`）·
/// 表格（含对齐与 `\|` 转义）· 围栏代码块（``` / ~~~，带语言串）· 引用（`>`）· 分隔线。
///
/// ## 明确**不支持**（写在这里，而不是让它悄悄通过）
///
///   · **Setext 标题**（`标题` 下面一行 `===`）：`---` 一律按分隔线处理；
///   · **缩进式代码块**（四空格起）：按普通段落文本原样搬运；
///   · **HTML 块 / 脚注 / 删除线 / 链接目标**：前三个原样当纯文本搬运（不吞不改）；
///     **链接目标不在本层** —— 笔记侧的行内解析器没有「目标」字段，硬在预览侧再写一套链接解析
///     就是第二套解析。链接要能点（`L-137` 判据里的「在已内嵌的浏览器页签里打开」）必须先决定
///     「链接进不进笔记侧的 span 树」，那是**契约层决定** ⇒ 在渲染那一片里定，不在本文件里顺手加。
///   · **引用里的惰性续行**（不带 `>` 的行）：需要 `>` 逐行显式标注。
///
/// ## 每条口径都配一条用例（`Tests/MarkdownDocumentTests.swift`）
public enum MarkdownDocumentFormat {
    /// 文档模型的版本号：结构变了才升，并必须给出迁移规则（与 `NoteBodyFormat` 同一套纪律）。
    public static let currentVersion = 1
}

/// 表格列对齐（GFM 的 `:---` / `:---:` / `---:`）。
public enum MarkdownColumnAlignment: String, Equatable, Sendable, CaseIterable {
    /// 没写冒号（`---`）。
    case unspecified
    case leading
    case center
    case trailing
}

/// 列表条目（无序 / 有序共用；嵌套的块进 `children`）。
public struct MarkdownListItem: Equatable, Sendable {
    /// 条目正文的行内 span（**来自笔记侧同一函数**）。
    public var spans: [NoteSpan]
    /// 该条目在**原文里的行号**（1 起）—— 跟随滚动要把它映射到预览锚点。
    public var sourceLine: Int
    /// 嵌套在条目里的块（子列表 / 围栏 / 引用…）。
    public var children: [MarkdownBlock]

    public init(spans: [NoteSpan], sourceLine: Int, children: [MarkdownBlock] = []) {
        self.spans = spans
        self.sourceLine = sourceLine
        self.children = children
    }
}

/// 任务列表条目。**复选框已从正文里摘出**，变成 `isChecked`（正文里不再留 `[x]` 那串字）。
public struct MarkdownTaskItem: Equatable, Sendable {
    public var isChecked: Bool
    public var spans: [NoteSpan]
    public var sourceLine: Int
    /// 嵌套在条目里的块 —— 任务条目也会带子列表，**不丢**。
    public var children: [MarkdownBlock]

    public init(isChecked: Bool, spans: [NoteSpan], sourceLine: Int, children: [MarkdownBlock] = []) {
        self.isChecked = isChecked
        self.spans = spans
        self.sourceLine = sourceLine
        self.children = children
    }
}

/// 一个块。**行号是模型的一等公民**：预览要能「编辑区光标在哪、预览就滚到哪」，
/// 而那条映射不能靠渲染时数文本（数出来的行与源文件的行是两回事）。
public struct MarkdownBlock: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case heading(level: Int, spans: [NoteSpan])
        case paragraph(spans: [NoteSpan])
        case bulletList(items: [MarkdownListItem])
        case orderedList(start: Int, items: [MarkdownListItem])
        case taskList(items: [MarkdownTaskItem])
        /// 表头与每一行的**每一格**都是各自的 span 数组（一格里的行内标记可能切成好几段）。
        case table(header: [[NoteSpan]], alignments: [MarkdownColumnAlignment], rows: [[[NoteSpan]]])
        /// `language` = 围栏后的语言串第一个词（没写 ⇒ `nil`，不猜）。
        case codeBlock(language: String?, lines: [String])
        case quote(blocks: [MarkdownBlock])
        case thematicBreak
    }

    public var kind: Kind
    /// 块在原文里的起始行号（1 起）。
    public var sourceLine: Int

    public init(kind: Kind, sourceLine: Int) {
        self.kind = kind
        self.sourceLine = sourceLine
    }

    /// 标题层级（不是标题 ⇒ `nil`）。渲染层要用它选字号，写在这里免得每个视图自己 switch。
    public var headingLevel: Int? {
        if case let .heading(level, _) = kind { return level }
        return nil
    }

    /// 这个块**直接**带的行内文本（标题 / 段落 / 引用与列表要靠各自的条目）。
    public var inlineSpans: [NoteSpan] {
        switch kind {
        case let .heading(_, spans), let .paragraph(spans): return spans
        default: return []
        }
    }
}

/// 解析上限与**如实的截断报告**。
///
/// 口径：预览**不许**因为文件大就把界面卡死，但也**不许静默少画** —— 少了多少行要说出来。
/// 报告里两个字段都是**行数**（不是「块数」）：块数要解析完才知道，而解析正是我们不做的那件事，
/// 报一个自己也不知道的数字等于编。
public struct MarkdownParseReport: Equatable, Sendable {
    /// 因 `maxLines` 上限而未参与解析的行数（0 = 全文都解析了）。
    public var skippedLineCount: Int
    /// 因 `maxBlocks` 上限而停止解析时剩下的行数（0 = 没到上限）。
    public var unparsedLineCount: Int

    public init(skippedLineCount: Int = 0, unparsedLineCount: Int = 0) {
        self.skippedLineCount = skippedLineCount
        self.unparsedLineCount = unparsedLineCount
    }

    /// 有没有被截断（界面据此决定要不要报数）。**文案不在这里** —— 展示文案归语言表（App 侧）。
    public var isTruncated: Bool { skippedLineCount > 0 || unparsedLineCount > 0 }
}

/// 解析上限。默认值刻意给得**宽**（20 000 行是「够长的文档」，不是「限制用户」）。
public struct MarkdownParseLimits: Equatable, Sendable {
    public var maxLines: Int
    public var maxBlocks: Int

    public init(maxLines: Int = 20_000, maxBlocks: Int = 5_000) {
        self.maxLines = maxLines
        self.maxBlocks = maxBlocks
    }
}

/// 文档模型：块数组 + 截断报告 + 原文行数。
public struct MarkdownDocument: Equatable, Sendable {
    public var version: Int
    public var blocks: [MarkdownBlock]
    public var report: MarkdownParseReport
    /// 原文行数（**截断前**的总数 —— 报告要拿它对账）。
    public var lineCount: Int

    public init(
        version: Int = MarkdownDocumentFormat.currentVersion,
        blocks: [MarkdownBlock],
        report: MarkdownParseReport = MarkdownParseReport(),
        lineCount: Int
    ) {
        self.version = version
        self.blocks = blocks
        self.report = report
        self.lineCount = lineCount
    }

    /// Markdown → 文档模型。**纯函数**：同样的输入永远同样的输出，不读盘、不看环境、不联网。
    public static func parse(_ markdown: String, limits: MarkdownParseLimits = MarkdownParseLimits()) -> MarkdownDocument {
        var parser = MarkdownBlockParser(lines: MarkdownBlockParser.splitLines(markdown), limits: limits)
        let blocks = parser.parseBlocks()
        return MarkdownDocument(
            blocks: blocks,
            report: MarkdownParseReport(
                skippedLineCount: parser.skippedLineCount,
                unparsedLineCount: parser.unparsedLineCount
            ),
            lineCount: parser.lineCount
        )
    }
}

// MARK: - 跟随滚动的锚点映射（`L-137` 判据 ③）

/// 预览锚点：**编辑区里的某一行，在预览里对应哪一块**。
///
/// 跟随滚动**不许**在渲染时数文本 —— 数出来的「第 N 行」与源文件的第 N 行是两回事
/// （段落软换行、被吃掉的标记、代码块的每一行都会让两者错位）。所以映射只走**行号**这一条通道：
/// 解析层早把每块的原文绝对行号记进模型，这里只做一次纯查表。
public struct MarkdownPreviewAnchor: Equatable, Sendable {
    /// 顶层块下标 —— **渲染层的滚动落点**（`MarkdownDocument.blocks[blockIndex]`）。
    public var blockIndex: Int
    /// 命中块所在的嵌套路径（空数组 = 光标行落在顶层块自己身上）。
    ///
    /// 口径：每一层给的是**该块子块数组里的下标**，而「子块数组」= 这一层的子块按顺序摊平
    /// （列表 = 各条目 `children` 依次拼接 —— 条目本身不是块；引用 = 它自己的 `blocks`）。
    /// 渲染层要下钻时按同一套摊平口径走，别自己另算一套。
    public var nestedPath: [Int]
    /// 命中块的起始行（1 起，原文绝对行号）。**不变量：它 ≤ 光标行**。
    public var sourceLine: Int

    public init(blockIndex: Int, nestedPath: [Int] = [], sourceLine: Int) {
        self.blockIndex = blockIndex
        self.nestedPath = nestedPath
        self.sourceLine = sourceLine
    }

    /// 光标行是不是落在某个**嵌套**块里（渲染层据此决定要不要下钻）。
    public var isNested: Bool { !nestedPath.isEmpty }
}

extension MarkdownPreviewAnchor {

    /// 一个块的直接子块（摊平口径的**唯一出处**，与 `anchor(forSourceLine:)` 同源）。
    static func childBlocks(of block: MarkdownBlock) -> [MarkdownBlock] {
        switch block.kind {
        case let .bulletList(items), let .orderedList(_, items):
            return items.flatMap(\.children)
        case let .taskList(items):
            return items.flatMap(\.children)
        case let .quote(blocks):
            return blocks
        case .heading, .paragraph, .table, .codeBlock, .thematicBreak:
            return []
        }
    }
}

extension MarkdownDocument {

    /// 光标行（1 起）→ 预览锚点。**纯函数**：同样输入永远同样输出，不读界面、不读时钟。
    ///
    /// ## 覆盖范围（唯一口径 —— 写在这里，免得渲染层再定一套）
    ///   · 块覆盖 `[自己的起始行, 下一个块的起始行 - 1]` ⇒ 块之间的空行归**前一个块**
    ///     （空行在预览里不是独立的一块，光标停在空行上时预览该停在它上面那块）；
    ///   · **最后一个块覆盖到原文末行**，含「文件以换行结尾」多出的那一行 ——
    ///     在末尾打字的瞬间光标正停在那一行，跟随滚动不能偏偏在那时失去锚点；
    ///   · 落在**第一个块之前**的行（文首空行）⇒ 锚到第一个块（文档开头不能没有跟随滚动）；
    ///   · 行号 ≤ 0 或 > `lineCount` ⇒ `nil` —— 不在原文里的行**不猜**；
    ///   · 被上限截断的尾巴仍在 `lineCount` 之内 ⇒ 落在最后一个已解析块：预览本来也只画到那儿，
    ///     少画了多少由 `report` 如实报数，不靠锚点假装有内容。
    ///
    /// ## 嵌套
    /// 落在子块里时锚点**下钻到最精确的那一层**（子块起始行更晚、且 ≤ 光标行，才算更精确；
    /// 与父块同起始行的子块不参与 —— 同一视觉位置，多一层下标没有信息）。
    public func anchor(forSourceLine line: Int) -> MarkdownPreviewAnchor? {
        guard !blocks.isEmpty, line >= 1, line <= lineCount else { return nil }
        let top = line < blocks[0].sourceLine ? 0 : lastBlockIndex(atOrBefore: line)
        var anchor = MarkdownPreviewAnchor(blockIndex: top, sourceLine: blocks[top].sourceLine)
        var lowerBound = blocks[top].sourceLine
        var children = MarkdownPreviewAnchor.childBlocks(of: blocks[top])
        while let position = children.lastIndex(where: { $0.sourceLine <= line && $0.sourceLine > lowerBound }) {
            anchor.nestedPath.append(position)
            anchor.sourceLine = children[position].sourceLine
            lowerBound = children[position].sourceLine
            children = MarkdownPreviewAnchor.childBlocks(of: children[position])
        }
        return anchor
    }

    /// 顶层块按起始行有序（解析器保证）⇒ 二分出「起始行 ≤ 光标行」的最后一个。
    private func lastBlockIndex(atOrBefore line: Int) -> Int {
        var low = 0
        var high = blocks.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if blocks[mid].sourceLine <= line {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return low
    }
}

// MARK: - 块级扫描器

/// 行驱动的块级扫描器。**状态就是一个行游标**：每次循环必须消费至少一行
/// （`parseBlocks` 里有兜底断言，见注释），否则同一行会被反复解析成死循环。
private struct MarkdownBlockParser {

    private let lines: [String]
    private let limits: MarkdownParseLimits
    private var index = 0
    private(set) var skippedLineCount = 0
    private(set) var unparsedLineCount = 0
    let lineCount: Int
    /// 本解析器 `lines[0]` 在**原文**里的前一行序号（顶层 = 0）。
    /// 有了它，引用 / 列表子块里的 `sourceLine` 也是**原文绝对行号** —— 否则
    /// 「编辑区第 40 行」映射到预览里会指到第 3 行，跟随滚动就成了随机滚动。
    private let lineOffset: Int

    init(lines: [String], limits: MarkdownParseLimits, lineOffset: Int = 0) {
        self.lineCount = lines.count
        self.limits = limits
        self.lineOffset = lineOffset
        if lines.count > limits.maxLines {
            // 超限：**只解析前 maxLines 行**，剩下的如实报数（不静默少画）。
            self.skippedLineCount = lines.count - limits.maxLines
            self.lines = Array(lines.prefix(limits.maxLines))
        } else {
            self.lines = lines
        }
    }

    static func splitLines(_ markdown: String) -> [String] {
        markdown.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            line.hasSuffix("\r") ? String(line.dropLast()) : String(line)
        }
    }

    mutating func parseBlocks() -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        while index < lines.count {
            if blocks.count >= limits.maxBlocks {
                unparsedLineCount = lines.count - index
                break
            }
            let before = index
            if let block = parseNextBlock() {
                blocks.append(block)
            }
            // 兜底（也是不变量的写法）：**任何分支都不许不消费行** —— 不消费就是死循环。
            if index == before {
                index += 1
            }
        }
        return blocks
    }

    // MARK: 一个块

    private mutating func parseNextBlock() -> MarkdownBlock? {
        let line = lines[index]
        if Self.isBlank(line) {
            index += 1
            return nil
        }
        if let fence = Self.fenceStart(line) {
            return parseCodeBlock(opening: fence)
        }
        if let heading = Self.atxHeading(line) {
            let sourceLine = lineOffset + index + 1
            index += 1
            return MarkdownBlock(kind: .heading(level: heading.level, spans: NoteBodyProjection.parseInline(heading.text)), sourceLine: sourceLine)
        }
        if Self.isThematicBreak(line) {
            let sourceLine = lineOffset + index + 1
            index += 1
            return MarkdownBlock(kind: .thematicBreak, sourceLine: sourceLine)
        }
        if Self.isQuote(line) {
            return parseQuote()
        }
        // 表格要**先于段落**判：表头那行本身也长得像段落。
        if let alignments = tableAlignments(after: index) {
            return parseTable(alignments: alignments)
        }
        if let marker = Self.listMarker(line) {
            return parseList(first: marker)
        }
        return parseParagraph()
    }

    private mutating func parseCodeBlock(opening: Fence) -> MarkdownBlock {
        let sourceLine = lineOffset + index + 1
        index += 1
        var content: [String] = []
        while index < lines.count {
            if Self.isFenceClosing(lines[index], marker: opening.marker, count: opening.count) {
                index += 1
                break
            }
            content.append(lines[index])
            index += 1
        }
        // 未闭合的围栏**跑到文末**（CommonMark 的口径）：不报错、不吞内容，照原样当代码。
        let language = opening.info.split(separator: " ").first.map(String.init)
        return MarkdownBlock(kind: .codeBlock(language: language, lines: content), sourceLine: sourceLine)
    }

    private mutating func parseQuote() -> MarkdownBlock {
        let sourceLine = lineOffset + index + 1
        var inner: [String] = []
        while index < lines.count {
            let stripped = Self.droppingIndent(lines[index])
            guard stripped.hasPrefix(">") else { break }
            var content = String(stripped.dropFirst())
            if content.hasPrefix(" ") {
                content.removeFirst()
            }
            inner.append(content)
            index += 1
        }
        var nested = MarkdownBlockParser(lines: inner, limits: limits, lineOffset: sourceLine - 1)
        return MarkdownBlock(kind: .quote(blocks: nested.parseBlocks()), sourceLine: sourceLine)
    }

    private mutating func parseParagraph() -> MarkdownBlock {
        let sourceLine = lineOffset + index + 1
        var collected: [String] = []
        while index < lines.count {
            let line = lines[index]
            if Self.isBlank(line) { break }
            if !collected.isEmpty {
                // 段落被下一个块打断：这里逐个问「下一行是不是块的开始」。
                if Self.fenceStart(line) != nil || Self.atxHeading(line) != nil
                    || Self.isThematicBreak(line) || Self.isQuote(line)
                    || Self.listMarker(line) != nil || tableAlignments(after: index) != nil {
                    break
                }
            }
            collected.append(line.trimmingCharacters(in: .whitespaces))
            index += 1
        }
        // 软换行**原样留下 `\n`**（显示口径归平台层：预览给空格还是给断行，是渲染的决定）。
        let text = collected.joined(separator: "\n")
        return MarkdownBlock(kind: .paragraph(spans: NoteBodyProjection.parseInline(text)), sourceLine: sourceLine)
    }

    private mutating func parseTable(alignments: [MarkdownColumnAlignment]) -> MarkdownBlock {
        let sourceLine = lineOffset + index + 1
        let header = Self.tableCells(lines[index]).map { NoteBodyProjection.parseInline($0) }
        index += 2   // 表头 + 分隔行
        var rows: [[[NoteSpan]]] = []
        while index < lines.count {
            let line = lines[index]
            if Self.isBlank(line) { break }
            if Self.fenceStart(line) != nil || Self.atxHeading(line) != nil { break }
            guard line.contains("|") else { break }
            var cells = Self.tableCells(line)
            // 短行**补齐**（渲染层不必自己防越界）；长行**不丢**（多出来的格子留着，不静默扔数据）。
            while cells.count < alignments.count {
                cells.append("")
            }
            rows.append(cells.map { NoteBodyProjection.parseInline($0) })
            index += 1
        }
        return MarkdownBlock(kind: .table(header: header, alignments: alignments, rows: rows), sourceLine: sourceLine)
    }

    private mutating func parseList(first marker: ListMarker) -> MarkdownBlock {
        struct RawItem {
            var text: String
            var sourceLine: Int
            var children: [MarkdownBlock]
        }

        let sourceLine = lineOffset + index + 1
        let baseIndent = marker.indent
        let ordered = marker.ordered
        var raw: [RawItem] = []

        while index < lines.count {
            let line = lines[index]
            if Self.isBlank(line) {
                // 空行：后面还是**同一段列表**（同缩进、同种类）才继续 —— 这就是「松散列表」。
                guard let next = nextNonBlank(after: index),
                      let peek = Self.listMarker(lines[next]),
                      peek.indent == baseIndent, peek.ordered == ordered else { break }
                index = next
                continue
            }
            guard let current = Self.listMarker(line), current.indent == baseIndent, current.ordered == ordered else { break }
            let itemLine = lineOffset + index + 1
            index += 1

            var textLines = [current.text]
            // 子块的行**连原文行号一起收**：子块解析出来的 `sourceLine` 必须是原文绝对行号，
            // 有间隔时补空行把编号顶齐（空行是干净的填充，跳过即可）—— 否则跟随滚动会指错行。
            var childLines: [(line: Int, text: String)] = []
            while index < lines.count {
                let candidate = lines[index]
                if Self.isBlank(candidate) { break }
                let indent = Self.indentWidth(candidate)
                if indent <= baseIndent { break }
                let inner = Self.dedent(candidate, by: min(indent, current.contentIndent))
                if Self.startsNestedBlock(inner) {
                    while let last = childLines.last, last.line < index {
                        childLines.append((last.line + 1, ""))
                    }
                    childLines.append((index + 1, inner))
                } else {
                    // 普通续行：算这一条的正文（GFM 里它是同一个段落的软换行）。
                    textLines.append(inner)
                }
                index += 1
            }
            var children: [MarkdownBlock] = []
            if let first = childLines.first {
                var nested = MarkdownBlockParser(
                    lines: childLines.map(\.text),
                    limits: limits,
                    lineOffset: first.line - 1
                )
                children = nested.parseBlocks()
            }
            raw.append(RawItem(text: textLines.joined(separator: "\n"), sourceLine: itemLine, children: children))
        }

        // **整段全带复选框 ⇒ 任务列表**；只要有一条不带，整段按普通列表走、
        // 那一串 `[x]` **原样留在文本里**（摘一半会让界面出现两套写法，说不清哪种才算数）。
        let allTasks = !raw.isEmpty && raw.allSatisfy { Self.taskItem(in: $0.text) != nil }
        if allTasks {
            let items = raw.compactMap { item -> MarkdownTaskItem? in
                guard let task = Self.taskItem(in: item.text) else { return nil }
                return MarkdownTaskItem(
                    isChecked: task.isChecked,
                    spans: NoteBodyProjection.parseInline(task.text),
                    sourceLine: item.sourceLine,
                    children: item.children
                )
            }
            return MarkdownBlock(kind: .taskList(items: items), sourceLine: sourceLine)
        }

        let items = raw.map { item in
            MarkdownListItem(
                spans: NoteBodyProjection.parseInline(item.text),
                sourceLine: item.sourceLine,
                children: item.children
            )
        }
        return ordered
            ? MarkdownBlock(kind: .orderedList(start: marker.number, items: items), sourceLine: sourceLine)
            : MarkdownBlock(kind: .bulletList(items: items), sourceLine: sourceLine)
    }

    private func nextNonBlank(after position: Int) -> Int? {
        var cursor = position + 1
        while cursor < lines.count {
            if !Self.isBlank(lines[cursor]) { return cursor }
            cursor += 1
        }
        return nil
    }

    // MARK: 表格判定

    /// 当前位置是不是一张表：本行含 `|`，且**下一行是分隔行**、格子数与表头相同。
    private func tableAlignments(after position: Int) -> [MarkdownColumnAlignment]? {
        guard position + 1 < lines.count else { return nil }
        let header = lines[position]
        guard header.contains("|") else { return nil }
        let delimiter = lines[position + 1]
        guard delimiter.contains("|") || delimiter.contains("-") else { return nil }
        let delimiterCells = Self.tableCells(delimiter)
        guard !delimiterCells.isEmpty else { return nil }
        var alignments: [MarkdownColumnAlignment] = []
        for cell in delimiterCells {
            guard let alignment = Self.columnAlignment(cell) else { return nil }
            alignments.append(alignment)
        }
        guard Self.tableCells(header).count == alignments.count else { return nil }
        return alignments
    }

    static func columnAlignment(_ cell: String) -> MarkdownColumnAlignment? {
        let trimmed = cell.trimmingCharacters(in: .whitespaces)
        let leading = trimmed.hasPrefix(":")
        let trailing = trimmed.hasSuffix(":")
        let core = trimmed.dropFirst(leading ? 1 : 0).dropLast(trailing ? 1 : 0)
        guard !core.isEmpty, core.allSatisfy({ $0 == "-" }) else { return nil }
        switch (leading, trailing) {
        case (true, true): return .center
        case (true, false): return .leading
        case (false, true): return .trailing
        case (false, false): return .unspecified
        }
    }

    /// 拆一格表格行。只认 `\|` 这一个转义（其它反斜杠原样留着 —— 路径里的 `\` 不该被我们吃掉）。
    static func tableCells(_ line: String) -> [String] {
        var text = line.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("|") {
            text.removeFirst()
        }
        var characters = Array(text)
        var cells: [String] = []
        var current = ""
        var trailingPipe = false
        var cursor = 0
        while cursor < characters.count {
            let character = characters[cursor]
            if character == "\\", cursor + 1 < characters.count, characters[cursor + 1] == "|" {
                current.append("|")
                trailingPipe = false
                cursor += 2
                continue
            }
            if character == "|" {
                cells.append(current)
                current = ""
                trailingPipe = cursor == characters.count - 1
                cursor += 1
                continue
            }
            current.append(character)
            cursor += 1
        }
        cells.append(current)
        if trailingPipe, cells.count > 1 {
            cells.removeLast()
        }
        return cells.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    // MARK: 行级判定

    static func isBlank(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// 去掉行首缩进（空格 / 制表符）。
    static func droppingIndent(_ line: String) -> Substring {
        var cursor = line.startIndex
        while cursor < line.endIndex, line[cursor] == " " || line[cursor] == "\t" {
            cursor = line.index(after: cursor)
        }
        return line[cursor...]
    }

    /// 缩进宽度（制表符按 GFM：**4 空格**）。
    static func indentWidth(_ line: String) -> Int {
        var width = 0
        for character in line {
            if character == " " { width += 1 } else if character == "\t" { width += 4 } else { break }
        }
        return width
    }

    /// 按宽度去掉行首缩进。
    static func dedent(_ line: String, by width: Int) -> String {
        var remaining = max(0, width)
        var cursor = line.startIndex
        while cursor < line.endIndex, remaining > 0 {
            let character = line[cursor]
            if character == " " {
                remaining -= 1
                cursor = line.index(after: cursor)
            } else if character == "\t" {
                remaining = max(0, remaining - 4)
                cursor = line.index(after: cursor)
            } else {
                break
            }
        }
        return String(line[cursor...])
    }

    struct Fence {
        var marker: Character
        var count: Int
        var info: String
    }

    /// 围栏开始（``` / ~~~，3 个起；前面最多 3 个空格）。
    static func fenceStart(_ line: String) -> Fence? {
        let stripped = droppingIndent(line)
        guard let first = stripped.first, first == "`" || first == "~" else { return nil }
        var count = 0
        var cursor = stripped.startIndex
        while cursor < stripped.endIndex, stripped[cursor] == first {
            count += 1
            cursor = stripped.index(after: cursor)
        }
        guard count >= 3 else { return nil }
        let info = String(stripped[cursor...]).trimmingCharacters(in: .whitespaces)
        if first == "`", info.contains("`") { return nil }
        return Fence(marker: first, count: count, info: info)
    }

    static func isFenceClosing(_ line: String, marker: Character, count: Int) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        var matched = 0
        for character in trimmed {
            if character == marker { matched += 1 } else { break }
        }
        guard matched >= count else { return false }
        // 收尾围栏后面**不许有别的东西**。
        return matched == trimmed.count
    }

    static func atxHeading(_ line: String) -> (level: Int, text: String)? {
        let stripped = droppingIndent(line)
        var level = 0
        for character in stripped {
            if character == "#" { level += 1 } else { break }
        }
        guard (1...6).contains(level) else { return nil }
        let rest = stripped.dropFirst(level)
        guard rest.isEmpty || rest.first == " " || rest.first == "\t" else { return nil }
        var text = String(rest).trimmingCharacters(in: .whitespaces)
        while text.hasSuffix("#") {
            text.removeLast()
        }
        return (level, text.trimmingCharacters(in: .whitespaces))
    }

    static func isThematicBreak(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first, first == "-" || first == "*" || first == "_" else { return false }
        let marks = trimmed.filter { $0 != " " && $0 != "\t" }
        guard marks.count >= 3 else { return false }
        return marks.allSatisfy { $0 == first }
    }

    static func isQuote(_ line: String) -> Bool {
        droppingIndent(line).hasPrefix(">")
    }

    struct ListMarker {
        var indent: Int
        var ordered: Bool
        var number: Int
        /// 正文起点（缩进 + 标记宽度）—— 续行按它去缩进。
        var contentIndent: Int
        var text: String
    }

    static func listMarker(_ line: String) -> ListMarker? {
        let indent = indentWidth(line)
        let rest = dedent(line, by: indent)
        guard let first = rest.first else { return nil }

        if first == "-" || first == "*" || first == "+" {
            let tail = String(rest.dropFirst())
            guard tail.isEmpty || tail.hasPrefix(" ") || tail.hasPrefix("\t") else { return nil }
            return ListMarker(indent: indent, ordered: false, number: 0, contentIndent: indent + 2, text: tail.isEmpty ? "" : String(tail.dropFirst()))
        }

        var digits = 0
        var cursor = rest.startIndex
        while cursor < rest.endIndex, rest[cursor].isNumber {
            digits += 1
            cursor = rest.index(after: cursor)
        }
        guard digits > 0, cursor < rest.endIndex else { return nil }
        let delimiter = rest[cursor]
        guard delimiter == "." || delimiter == ")" else { return nil }
        let tail = String(rest[rest.index(after: cursor)...])
        guard tail.isEmpty || tail.hasPrefix(" ") || tail.hasPrefix("\t") else { return nil }
        let number = Int(rest[rest.startIndex..<cursor]) ?? 1
        return ListMarker(
            indent: indent,
            ordered: true,
            number: number,
            contentIndent: indent + digits + 2,
            text: tail.isEmpty ? "" : String(tail.dropFirst())
        )
    }

    /// 条目续行里，哪些算「下一个块」（进 `children`）—— 其余的算这一条的正文。
    static func startsNestedBlock(_ line: String) -> Bool {
        listMarker(line) != nil || fenceStart(line) != nil || atxHeading(line) != nil
            || isQuote(line) || isThematicBreak(line)
    }

    /// 任务条目的复选框（`[ ]` / `[x]` / `[X]`，**后面必须有空格**才算）。
    static func taskItem(in text: String) -> (isChecked: Bool, text: String)? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let characters = Array(trimmed)
        guard characters.count >= 3, characters[0] == "[", characters[2] == "]" else { return nil }
        let mark = characters[1]
        guard mark == " " || mark == "x" || mark == "X" else { return nil }
        let rest = String(characters.dropFirst(3))
        guard rest.isEmpty || rest.hasPrefix(" ") else { return nil }
        return (mark != " ", rest.isEmpty ? "" : String(rest.dropFirst()))
    }
}
