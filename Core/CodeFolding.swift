import Foundation

/// **代码折叠**（`FR-STD-WS-EDIT-017`）：按语言的块级规则找出可折叠的**区域** +
/// 记住「哪几个区域被折起来了」。两件事都是纯逻辑，所以都在 Core。
///
/// ## 为什么折叠一定要分成两层
///
/// 「哪儿能折」是**从内容算出来的**（每次编辑都可能变），「哪一个被折了」是**用户做的决定**
/// （编辑不该把它清掉）。把两者揉成一个类型的话，改一个字就会把所有折叠状态重算成空 ——
/// 而需求 ③ 要的正是「切到别的文件再回来仍保持」。所以：
///
/// · `projection(in:language:)` —— 只读文本，产出区域表（`FoldProjection`）；
/// · `FoldState` —— 只记「哪些区域被折了」，**按锚记、不按行号记**（见下）。
///
/// ## 锚为什么不是行号
///
/// 行号是最脆的身份：在文件开头加一行注释，底下所有折叠都会「挪一格」——
/// 折着的块变成「从下一行开始折」，用户看到的是一段莫名其妙被藏起来的代码。
/// 锚 = **区域内首行的原文（去首尾空白）+ 同类首行的序号**：文本一改，同一段代码的锚不变；
/// 首行真被改了（比如函数改名），那条折叠**如实丢掉**（不猜它原来是哪一段）。
///
/// ## 折叠不改内容（需求 ④）
///
/// 本类型**只产出判定**（区域 / 标记 / 该藏哪几行），一个字都不写回文本；
/// 「把这几行藏起来」是视图那一层的事（`CodeTextView.applyFoldCollapse` 走段落样式，
/// 不进 `textStorage` 的字符、不进撤销栈）。搜索仍能搜到被藏起来的字 —— 因为字还在。
public enum CodeFolding {

    /// 一次判定最多收多少段区域（防病态文件把界面拖死）。
    ///
    /// 超了**按文档顺序取前 N 段**（确定行为），不是随机丢 —— 与行号列「几千行只画可见行」
    /// 同一条纪律：宁可少给，也不许让一次按键变成 O(n²)。
    public static let maximumRegions = 4_000

    // MARK: - 规则从登记表来

    /// 这门语言按什么规则找块。**语言知识只住在登记表**（`CodeLanguageDefinition.fold`）——
    /// 本文件里不出现任何语言标识（`check-language-registry.py` 的 A 档守着这条）。
    public static func rule(for language: TextLanguage) -> FoldRule {
        language.definition.fold
    }

    // MARK: - 区域（从内容算）

    /// 读一遍文本，产出这一份文档的全部可折叠区域。
    public static func projection(in text: String, language: TextLanguage) -> FoldProjection {
        guard !text.isEmpty else { return FoldProjection(regions: [], anchors: []) }
        let rule = rule(for: language)
        guard rule != .none else { return FoldProjection(regions: [], anchors: []) }

        let masked = maskedSpans(in: text, language: language)
        var regions: [FoldRegion] = []
        switch rule {
        case .braces:
            regions = braceRegions(in: text, masked: masked)
        case .indentation:
            regions = indentationRegions(in: text, masked: masked)
        case .none:
            regions = []
        }
        // 区域标记（`#region` … `#endregion`）与上面两套规则**并列**：花括号语言里也常有人
        // 手写区域；缩进语言同理。标记段按行配对，不参与嵌套深度的判定。
        regions.append(contentsOf: markerRegions(in: text))

        regions = normalised(regions)
        return FoldProjection(regions: regions, anchors: anchors(for: regions, in: text))
    }

    // MARK: - 花括号块

    /// 一段 `{` … `}` 就是一段区域（`startLine` = 开了这个括号的那一行，`endLine` = 闭合行）。
    ///
    /// 三条口径：
    /// ① **字符串与注释里的括号不算**（`masked` 由词法器给 —— 与着色同一份切分，
    ///    另写一套「引号里的花括号不算」的正则，迟早与着色分叉）；
    /// ② 开闭在**同一行**的不算区域（单行 `{ return }` 折起来没有意义，还会把标记画满一屏）；
    /// ③ 没配上的 `{`（文件末尾少一个 `}`）**不产出区域**，也不崩 —— 不拿「到文件末尾」当配上了，
    ///    那会把后半篇都藏进一个不存在的块里。
    private static func braceRegions(in text: String, masked: [Range<Int>]) -> [FoldRegion] {
        let ns = text as NSString
        let length = ns.length
        let starts = CodeLines.lineStarts(in: text)
        var regions: [FoldRegion] = []
        var stack: [Int] = []
        var lineIndex = 0          // `starts` 里的下标（0 基）
        var maskedIndex = 0

        for index in 0..<length {
            while lineIndex + 1 < starts.count, starts[lineIndex + 1] <= index { lineIndex += 1 }
            while maskedIndex < masked.count, masked[maskedIndex].upperBound <= index { maskedIndex += 1 }
            if maskedIndex < masked.count, masked[maskedIndex].contains(index) { continue }

            let character = ns.character(at: index)
            if character == 0x7B {                      // {
                stack.append(lineIndex + 1)
            } else if character == 0x7D {               // }
                guard let open = stack.popLast() else { continue }
                let line = lineIndex + 1
                if line > open {
                    regions.append(FoldRegion(startLine: open, endLine: line, kind: .block))
                }
            }
        }
        return regions
    }

    // MARK: - 缩进块

    /// 缩进语言（Python / YAML）：**以 `:` 收尾的行**开一个块，块的末尾 = 后面所有缩进更深的
    /// 非空行的最后一行（中间的空行照算在块内，尾部的空行不算 —— 折起来不该把下一段的空行也吞掉）。
    ///
    /// 为什么要求「行尾是 `:`」而不是「下一行缩进更深就算」：后者在续行 / 多行表达式上会产出
    /// 一段段毫无意义的区域（每个对齐的行都成一段），折叠标记会密到没法用。
    private static func indentationRegions(in text: String, masked: [Range<Int>]) -> [FoldRegion] {
        let ns = text as NSString
        let contents = CodeLines.contentRanges(in: text)
        var regions: [FoldRegion] = []

        for index in 0..<contents.count {
            let range = contents[index]
            guard range.length > 0 else { continue }
            let line = range.location
            let end = range.location + range.length
            // 行尾（去空白）那个字符必须是 `:`，且**不在**字符串 / 注释里。
            var tail = end
            while tail > line, isWhitespace(ns.character(at: tail - 1)) { tail -= 1 }
            guard tail > line, ns.character(at: tail - 1) == 0x3A, !isMasked(tail - 1, by: masked) else {
                continue
            }
            let headerIndent = indentWidth(at: line, contentsEnd: end, in: ns)
            // 往后找块尾：空行跳过（不截断块），缩进严格更深即属本块，遇到同级或更浅就停。
            var lastLine: Int? = nil
            var cursor = index + 1
            while cursor < contents.count {
                let next = contents[cursor]
                if next.length == 0 { cursor += 1; continue }
                let indent = indentWidth(at: next.location, contentsEnd: next.location + next.length, in: ns)
                if indent <= headerIndent { break }
                lastLine = cursor
                cursor += 1
            }
            guard let lastLine, lastLine > index else { continue }
            regions.append(FoldRegion(startLine: index + 1, endLine: lastLine + 1, kind: .indentation))
        }
        return regions
    }

    // MARK: - 区域标记（`#region` … `#endregion`）

    /// 手写区域：以 `#region` 开、`#endregion` 合（前缀允许用注释符引出，如 `// #region`）。
    /// 没配上的 `#region` 不产出区域（与花括号同一条口径）。
    private static func markerRegions(in text: String) -> [FoldRegion] {
        let contents = CodeLines.contentRanges(in: text)
        let ns = text as NSString
        var regions: [FoldRegion] = []
        var stack: [Int] = []
        for index in 0..<contents.count {
            let range = contents[index]
            guard range.length > 0 else { continue }
            let body = ns.substring(with: range)
            guard let keyword = regionKeyword(in: body) else { continue }
            if keyword == .open {
                stack.append(index + 1)
            } else if let open = stack.popLast(), index + 1 > open {
                regions.append(FoldRegion(startLine: open, endLine: index + 1, kind: .marker))
            }
        }
        return regions
    }

    private enum RegionKeyword { case open, close }

    /// 这一行是不是区域标记。判定顺序：先剥掉行首注释符（`//` / `#` / `--` / `/*`），
    /// 再看第一个词 —— 而不是在整行里 `contains("region")`（注释里提一句「region」就会开一个块）。
    private static func regionKeyword(in line: String) -> RegionKeyword? {
        var body = line.trimmingCharacters(in: .whitespaces)
        for opener in ["//", "#", "--", "/*", ";;"] where body.hasPrefix(opener) {
            body = String(body.dropFirst(opener.count)).trimmingCharacters(in: .whitespaces)
            break
        }
        let word = body.prefix { !$0.isWhitespace }
        switch word.lowercased() {
        case "region", "#region": return .open
        case "endregion", "#endregion": return .close
        default: return nil
        }
    }

    // MARK: - 规范化

    /// 去重 + 丢掉自相矛盾的区域 + 排序 + 封顶。
    ///
    /// 排序口径 = **按首行升序、同首行按尾行降序**（外层在前）：外层折起来时内层整段都在
    /// 它里面，判据与视图都按这个次序走，不会出现「先看到内层、再看到更大的外层」那种来回跳的标记。
    private static func normalised(_ regions: [FoldRegion]) -> [FoldRegion] {
        var seen = Set<FoldRegion>()
        var unique: [FoldRegion] = []
        for region in regions {
            guard region.endLine > region.startLine, region.startLine >= 1 else { continue }
            if seen.insert(region).inserted { unique.append(region) }
        }
        unique.sort {
            $0.startLine == $1.startLine ? $0.endLine > $1.endLine : $0.startLine < $1.startLine
        }
        if unique.count > maximumRegions { unique = Array(unique.prefix(maximumRegions)) }
        return unique
    }

    // MARK: - 锚

    /// 一段区域的签名 = 「kind + 首行原文（去首尾空白）」。
    static func signature(for region: FoldRegion, contents: [NSRange], in ns: NSString) -> String {
        let body: String
        if region.startLine - 1 < contents.count, region.startLine >= 1 {
            body = ns.substring(with: contents[region.startLine - 1])
        } else {
            body = ""
        }
        // kind 也进签名：同一行既可能是块首、也可能被手写成区域首（理论上不会，但别让两种
        // 语义共用一把钥匙）。带进签名后，改了 kind 只会让那一条折叠如实失效。
        return "\(region.kind.rawValue)|\(body.trimmingCharacters(in: .whitespaces))"
    }

    /// 一串区域的锚（序号 = 「前面出现过几条同签名的区域」）—— `FoldProjection` 用它。
    ///
    /// 序号是「同签名靠后者」的唯一区分手段：一份文件里两个 `    }` 收尾的块首行签名相同
    /// （比如两个空行开头的匿名闭包），只按签名记的话折一个会折两个。
    static func anchors(for regions: [FoldRegion], in text: String) -> [FoldState.Anchor] {
        let contents = CodeLines.contentRanges(in: text)
        let ns = text as NSString
        var counts: [String: Int] = [:]
        return regions.map { region in
            let base = signature(for: region, contents: contents, in: ns)
            let occurrence = counts[base, default: 0]
            counts[base] = occurrence + 1
            return FoldState.Anchor(signature: base, occurrence: occurrence)
        }
    }

    // MARK: - 小工具

    private static func isWhitespace(_ character: unichar) -> Bool {
        character == 0x20 || character == 0x09 || character == 0x0B || character == 0x0C
    }

    private static func isMasked(_ offset: Int, by masked: [Range<Int>]) -> Bool {
        for range in masked where range.contains(offset) { return true }
        return false
    }

    /// 一行的缩进宽度（空格 1、制表符按 4 —— 这里只用来比较相对深浅，绝对值不影响判决）。
    private static func indentWidth(at start: Int, contentsEnd: Int, in ns: NSString) -> Int {
        var width = 0
        var index = start
        while index < contentsEnd {
            let character = ns.character(at: index)
            if character == 0x20 {
                width += 1
            } else if character == 0x09 {
                width += 4
            } else {
                break
            }
            index += 1
        }
        return width
    }

    /// 字符串与注释占的字符范围（UTF-16 偏移）—— 由**词法器**给，不另写一套引号识别。
    static func maskedSpans(in text: String, language: TextLanguage) -> [Range<Int>] {
        guard !text.isEmpty else { return [] }
        let tokens = CodeLexer.tokens(in: text, language: language)
        guard !tokens.isEmpty else { return [] }
        var spans: [Range<Int>] = []
        for token in tokens where token.kind == .string || token.kind == .comment {
            let range = NSRange(token.range, in: text)
            guard range.length > 0, range.location >= 0 else { continue }
            spans.append(range.location..<(range.location + range.length))
        }
        spans.sort { $0.lowerBound < $1.lowerBound }
        return spans
    }
}

// MARK: - 区域与标记

/// 语言的折叠规则（**数据，不是身份判断** —— 登记在 `CodeLanguageDefinition.fold`）。
public enum FoldRule: String, Sendable, Equatable, CaseIterable {
    /// 这门语言没有块级结构可折（纯文本、Markdown、HTML —— 折 HTML 要按标签配对，
    /// 那是另一套规则，不是「花括号」能顶的，所以如实不给）。
    case none
    /// 花括号块：`{` … `}`（C 族 / SQL / JSON / Swift / Go / Rust …）
    case braces
    /// 缩进块：以 `:` 收尾的行 + 更深缩进（Python / YAML）
    case indentation
}

/// 一段可折叠的区域（行号 1 起，按 `CodeLines` 的口径）。
///
/// `startLine` = **折起来之后仍然看得见的那一行**（函数签名那一行），`endLine` = 块的最后一行。
/// 折起来时隐藏的是 `startLine + 1 … endLine`。
public struct FoldRegion: Hashable, Sendable {
    public enum Kind: String, Sendable, Hashable {
        /// 花括号块
        case block
        /// 缩进块
        case indentation
        /// 手写区域标记（`#region` … `#endregion`）
        case marker
    }

    public let startLine: Int
    public let endLine: Int
    public let kind: Kind

    public init(startLine: Int, endLine: Int, kind: Kind) {
        self.startLine = startLine
        self.endLine = endLine
        self.kind = kind
    }

    /// 折起来会藏起几行（`0` 表示这不是一段有效区域）。
    public var hiddenLineCount: Int { max(0, endLine - startLine) }

    /// 折起来时被隐藏的行（含两端）：`startLine + 1 … endLine`。
    public var hiddenLines: ClosedRange<Int>? {
        hiddenLineCount > 0 ? (startLine + 1)...endLine : nil
    }
}

/// 行号槽上那一枚标记：哪一行有标记、它是折着的还是展开的。
public struct FoldMarker: Equatable, Sendable {
    public let line: Int
    public let isFolded: Bool

    public init(line: Int, isFolded: Bool) {
        self.line = line
        self.isFolded = isFolded
    }
}

/// 一次判定的结果：区域表 + 与它一一对应的锚。
public struct FoldProjection: Sendable, Equatable {
    public let regions: [FoldRegion]
    public let anchors: [FoldState.Anchor]

    public init(regions: [FoldRegion], anchors: [FoldState.Anchor]) {
        self.regions = regions
        self.anchors = anchors
    }
}

// MARK: - 折叠状态（用户做的决定）

/// 一份文件**在会话内**的折叠状态：哪些区域被折起来了。
///
/// 只记锚（见 `CodeFolding` 文件头的「锚为什么不是行号」），因此它对编辑是**稳的**：
/// 在别处加几行、块内改字，折叠都还在；首行真被改了，那一条如实失效。
public struct FoldState: Equatable, Sendable {

    /// 一段区域的稳定身份（首行原文 + 同签名序号，kind 一并进签名）。
    public struct Anchor: Hashable, Sendable {
        public let signature: String
        public let occurrence: Int

        public init(signature: String, occurrence: Int) {
            self.signature = signature
            self.occurrence = occurrence
        }
    }

    public private(set) var folded: Set<Anchor>

    public init(folded: Set<Anchor> = []) {
        self.folded = folded
    }

    /// 有没有任何折叠（视图据此决定要不要重排）。
    public var isEmpty: Bool { folded.isEmpty }

    /// 折起来的段数。
    public var count: Int { folded.count }

    // MARK: 查询

    /// 这一行现在折着吗（只有区域首行可能折）。
    public func isFolded(_ region: FoldRegion, in projection: FoldProjection) -> Bool {
        guard let index = projection.regions.firstIndex(of: region) else { return false }
        return folded.contains(projection.anchors[index])
    }

    /// 行号槽的标记表：每一段区域一枚（首行 + 折没折）。
    public func markers(in projection: FoldProjection) -> [FoldMarker] {
        projection.regions.enumerated().map { index, region in
            FoldMarker(line: region.startLine, isFolded: folded.contains(projection.anchors[index]))
        }
    }

    /// 现在被藏起来的行号（1 起）。**只算真正折起来的**区域；外层折着时内层整段也一起藏。
    public func hiddenLines(in projection: FoldProjection) -> Set<Int> {
        var hidden = Set<Int>()
        for (index, region) in projection.regions.enumerated()
        where folded.contains(projection.anchors[index]) {
            guard let range = region.hiddenLines else { continue }
            hidden.formUnion(range)
        }
        return hidden
    }

    /// 被藏起来的那些行 → **合并成连续段** 的 `NSRange`（UTF-16 偏移）。
    ///
    /// 为什么要合并：视图侧要按段设段落样式 / 触发重排，一段一个 `NSRange` 最省；
    /// 逐行给会让 5,000 行的块变成 5,000 次属性写入。
    public func hiddenRanges(in projection: FoldProjection, text: String) -> [NSRange] {
        let lines = hiddenLines(in: projection).sorted()
        guard !lines.isEmpty else { return [] }
        let starts = CodeLines.lineStarts(in: text)
        let length = (text as NSString).length
        var ranges: [NSRange] = []
        var runStart = lines[0]
        var previous = lines[0]
        func flush() {
            guard let head = CodeLines.range(ofLine: runStart, lineStarts: starts, length: length),
                  let tail = CodeLines.range(ofLine: previous, lineStarts: starts, length: length)
            else { return }
            let end = tail.location + tail.length
            guard end > head.location else { return }
            ranges.append(NSRange(location: head.location, length: end - head.location))
        }
        for line in lines.dropFirst() {
            if line == previous + 1 {
                previous = line
            } else {
                flush()
                runStart = line
                previous = line
            }
        }
        flush()
        return ranges
    }

    /// 落在**折起来的那几行里**的区域（光标进去时要展开它）——
    /// 不展开的话用户能在看不见的行里打字，这是折叠最典型的「按了没反应」。
    public func foldedRegions(containing line: Int, in projection: FoldProjection) -> [FoldRegion] {
        projection.regions.enumerated().compactMap { index, region in
            guard folded.contains(projection.anchors[index]), let range = region.hiddenLines,
                  range.contains(line) else { return nil }
            return region
        }
    }

    // MARK: 变换（每个都返回新状态，不改自己）

    /// 折叠 / 展开某一行的块。这一行不是区域首行 ⇒ 原样返回（不猜用户想折哪一段）。
    ///
    /// 同一行上若有**多段**区域（例如一行既开了 `{`、又写着 `#region`），按「任一折着就算折着」
    /// 的标记语义一起折 / 一起展 —— 只翻其中一段会出现「点了标记、标记没变」的死角。
    public func toggling(line: Int, in projection: FoldProjection) -> FoldState {
        let indices = projection.regions.indices.filter { projection.regions[$0].startLine == line }
        guard !indices.isEmpty else { return self }
        let anchors = indices.map { projection.anchors[$0] }
        var next = self
        if anchors.contains(where: { next.folded.contains($0) }) {
            for anchor in anchors { next.folded.remove(anchor) }
        } else {
            next.folded.formUnion(anchors)
        }
        return next
    }

    /// 展开指定几条（光标进入折起来的块时用）。
    public func expanding(_ regions: [FoldRegion], in projection: FoldProjection) -> FoldState {
        var next = self
        for region in regions {
            guard let index = projection.regions.firstIndex(of: region) else { continue }
            next.folded.remove(projection.anchors[index])
        }
        return next
    }

    /// 文本变了之后对账：**只保留还存在的锚**。
    ///
    /// 不这么做的后果是「折叠越用越多」：块被删掉了、首行改名了，旧锚仍躺在状态里，
    /// 而它再也不会命中任何区域 —— 用户看不到任何症状，直到某天同样的首行又出现，
    /// 那段代码**莫名其妙是折着的**（锚是签名，这正是签名式身份的两面）。
    public func reconciled(with projection: FoldProjection) -> FoldState {
        let alive = Set(projection.anchors)
        let kept = folded.intersection(alive)
        return kept == folded ? self : FoldState(folded: kept)
    }
}
