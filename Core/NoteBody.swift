import Foundation

/// 笔记正文的**权威源与投影**（Q8 已拍板选 C：Markdown 为源 + 受限样式旁挂）。
///
/// 这一层要回答的不是"格式好不好看"，而是**投影到底有损在哪**。所以它是一个可单测的纯函数对：
///   · `toSpans`：权威源（Markdown + 旁挂样式）→ 编辑器要的 span 树（鸿蒙 `RichEditor` / iOS / Android 各自渲染它）；
///   · `fromSpans`：span 树 → 权威源（**能进 Markdown 的就写进 Markdown，进不了的落旁挂**）；
///   · `exportMarkdown`：给"导出 md 文件"用 —— **必须同时给出降级报告**，不许静默丢样式。
///
/// **支持的子集刻意很小**（Q8 的"不做清单"在这里变成代码）：
/// 粗体 `**x**`、斜体 `*x*`、行内代码 `` `x` ``、**链接 `[文字](目标)`**（2026-10-01 第 146 轮补，
/// 队列 `L-137` 剩余③ —— 人类主人答「#2，进」）；**行内颜色与字号 Markdown 表达不了 → 一律进旁挂**；
/// 其余 Markdown 语法（标题、列表、表格…）**原样当纯文本搬运**，不解析也不破坏 ——
/// 这保证了"AI 写进来的 Markdown 不会被我们改坏"。
/// **链接刻意只到"目标"为止**：它是不是能加载的地址、该开在哪儿，都不在这一层判
/// （前者是浏览器那条唯一入口，后者是契约「默认开在已内嵌的浏览器页签里」）。
public enum NoteBodyFormat {
    /// 权威源的版本号：结构变了才升，并必须给出迁移规则（Q8 的硬要求）。
    public static let currentVersion = 1
}

/// 旁挂样式：只承载 **Markdown 表达不了**的属性（颜色 / 字号），并按"文本 + 第几次出现"定位。
///
/// 为什么用"文本 + 序号"而不是偏移量：偏移量在 AI 改写后会整体失效（一改就全错位），
/// 而"这段文字 + 它是第几次出现"在人改、AI 改之后**仍大概率对得上**；对不上就如实降级（见 `toSpans`）。
public struct NoteSidecarStyle: Codable, Equatable, Sendable {
    public var text: String
    /// 同一段文字在一篇笔记里出现的次序（从 0 开始）。
    public var occurrence: Int
    /// `#RRGGBB`。
    public var color: String?
    /// 字号（缺省 nil = 跟随主题）。
    public var size: Int?

    public init(text: String, occurrence: Int = 0, color: String? = nil, size: Int? = nil) {
        self.text = text
        self.occurrence = occurrence
        self.color = color
        self.size = size
    }
}

/// 权威源：Markdown 正文 + 版本号 + 旁挂样式。
public struct NoteBody: Codable, Equatable, Sendable {
    public var version: Int
    public var markdown: String
    public var sidecar: [NoteSidecarStyle]

    public init(version: Int = NoteBodyFormat.currentVersion, markdown: String = "", sidecar: [NoteSidecarStyle] = []) {
        self.version = version
        self.markdown = markdown
        self.sidecar = sidecar
    }

    /// 版本迁移：**只认自己认识的版本**，更高的版本如实拒绝（不猜、不静默降级）。
    public enum MigrationError: Error, Equatable {
        case fromFuture(Int)
    }

    public func migrated() throws -> NoteBody {
        guard version <= NoteBodyFormat.currentVersion else {
            throw MigrationError.fromFuture(version)
        }
        var copy = self
        copy.version = NoteBodyFormat.currentVersion
        return copy
    }
}

/// span 树（编辑器渲染用）：一段文字 + 它带的样式 +（链接才有）目标。
public struct NoteSpan: Equatable, Sendable {
    public enum Style: String, Equatable, Sendable, CaseIterable {
        case bold
        case italic
        case code
        /// 行内颜色（Markdown 表达不了，来自旁挂）
        case color
        /// 字号（同上）
        case size
    }

    public var text: String
    public var styles: Set<Style>
    public var color: String?
    public var size: Int?
    /// **链接目标**（`[文字](目标)` 里那段括号），**原样**保存。
    ///
    /// 两件事刻意**不在这里**判：① 它是不是一个能加载的地址（那是浏览器那条唯一入口的事，
    /// 见 `BrowserSession.parseAddress`）；② 它该开在哪儿（契约：默认在已内嵌的浏览器页签里）。
    /// 链接 span 的 `text` 是**显示文字**（点之前看见的那几个字）；非链接 span 是 `nil`。
    /// **链接不进 `styles`** —— 它不是粗体那种"样式"，它是**目标**。
    public var link: String?

    public init(text: String, styles: Set<Style> = [], color: String? = nil, size: Int? = nil, link: String? = nil) {
        self.text = text
        self.styles = styles
        self.color = color
        self.size = size
        self.link = link
    }
}

/// 投影结果：spans + **如实报出的降级**（哪些样式没能落到 span 上、为什么）。
public struct NoteProjection: Equatable, Sendable {
    public var spans: [NoteSpan]
    public var degradations: [String]

    public init(spans: [NoteSpan], degradations: [String] = []) {
        self.spans = spans
        self.degradations = degradations
    }
}

public enum NoteBodyProjection {

    // MARK: - 权威源 → span 树

    /// **行内标记的唯一解析处**（全局只有这一份，见下）。
    ///
    /// 抽出来是因为队列 `L-137`（工作区 Markdown 预览）：预览的**块级**结构由
    /// `MarkdownDocument` 产出，而每一块里的**行内**标记必须与笔记侧**同一份实现** ——
    /// 否则同一个 `**粗体**` 在笔记里是粗体、在预览里是星号，两套口径。
    /// 门禁 `Scripts/check-markdown-single-source.py` 就守这一条（`nextMarker` 只许在 `NoteBody.swift`）。
    ///
    /// **口径一字未改**（提取前它长在 `toSpans` 里）：只认 `**` / `*` / `` ` `` 三个标记；
    /// **取最早出现的那个**（不是「先试代码再试粗体」）；未闭合 / 空内容不算一对；
    /// 扫到谁先出现就切谁，切不动就整段退化成纯文本（不吞、不改写）。
    ///
    /// **2026-10-01 第 146 轮补第 4 个候选：链接**（队列 `L-137` 剩余③；人类主人答「#2，进」⇒
    /// 口径 = **链接进笔记侧 span 树**）。三条与上面同一族的口径：
    ///   · `[文字](目标)` 形态要求**紧挨着**的 `](`，文字与目标**都非空** —— 空的不算一对（同「空内容不算一对」）；
    ///   · 与其它标记**同一个先来后到**：谁在文本里先出现就先切谁（`**[a](b)**` 得到的是一个粗体 span，
    ///     文字是 `[a](b)` 原文 —— **标记里的标记不再解析**，子集刻意很小）；
    ///   · **不跨行、不做括号平衡**：文字与目标里出现换行 ⇒ 退回普通文本；目标里出现不成对的 `)`
    ///     ⇒ 截到**第一个 `)`**（多出来那个留在剩余文本里）。两条都有用例钉着，别改口径时忘掉。
    /// 目标落 `NoteSpan.link`（**不进 `styles`**）；能不能加载不在这里判（浏览器那条入口的事）。
    public static func parseInline(_ markdown: String) -> [NoteSpan] {
        var spans: [NoteSpan] = []
        var remaining = Substring(markdown)
        while !remaining.isEmpty {
            if let marker = nextMarker(in: remaining) {
                if !marker.before.isEmpty {
                    spans.append(NoteSpan(text: String(marker.before)))
                }
                switch marker.marker {
                case "**": spans.append(NoteSpan(text: String(marker.inner), styles: [.bold]))
                case "*": spans.append(NoteSpan(text: String(marker.inner), styles: [.italic]))
                case "[": spans.append(NoteSpan(text: String(marker.inner), link: marker.target.map(String.init)))
                default: spans.append(NoteSpan(text: String(marker.inner), styles: [.code]))
                }
                remaining = marker.after
            } else {
                spans.append(NoteSpan(text: String(remaining)))
                remaining = ""
            }
        }
        return spans
    }

    /// Markdown + 旁挂 → span 树。**解析不了的东西原样保留为纯文本**（不吞、不改写）。
    ///
    /// **语言由调用方给定**（队列 L-47 / L-65 的口径）：降级说明是**给人看的话**，
    /// 界面要英文就传 `.english`。此前这里写死简体中文 ⇒ 语言表里
    /// `noteSidecarLost` / `noteLostColor` / `noteLostSize` / `noteExportDegraded`
    /// 的英文译文**永远不可达**（死译文）。**刻意不留默认值**：默认值等于把「写死语言」藏起来。
    public static func toSpans(_ body: NoteBody, language: AppLanguage) -> NoteProjection {
        var spans = parseInline(body.markdown)
        var degradations: [String] = []

        // 旁挂：按"文本 + 第几次出现"定位 —— **要能在 span 内部再切一刀**。
        // 一开始我按"整段 span 文本相等"定位，结果纯文本（没有任何 Markdown 标记）时整篇是一个大 span，
        // 旁挂永远定位不到（测试当场抓到）。正确做法是：找到那段文字后**把 span 切成三份**再上样式。
        // 已知简化：出现次序按"扫描顺序"计，不做跨 span 的严格计数（原型够用，正式实现要写清口径）。
        for style in body.sidecar {
            var seen = 0
            var applied = false
            var index = 0
            while index < spans.count {
                guard let range = spans[index].text.range(of: style.text) else {
                    index += 1
                    continue
                }
                if seen < style.occurrence {
                    seen += 1
                    index += 1
                    continue
                }
                let text = spans[index].text
                var styled = NoteSpan(text: style.text, styles: spans[index].styles, color: style.color, size: style.size)
                if style.color != nil { styled.styles.insert(.color) }
                if style.size != nil { styled.styles.insert(.size) }
                let before = String(text[text.startIndex..<range.lowerBound])
                let after = String(text[range.upperBound...])
                var replacement: [NoteSpan] = []
                if !before.isEmpty { replacement.append(NoteSpan(text: before)) }
                replacement.append(styled)
                if !after.isEmpty { replacement.append(NoteSpan(text: after)) }
                spans.replaceSubrange(index...index, with: replacement)
                applied = true
                break
            }
            if !applied {
                degradations.append(LocalizedStrings.format(.noteSidecarLost, language: language, String(style.occurrence + 1), style.text))
            }
        }
        return NoteProjection(spans: spans, degradations: degradations)
    }

    /// 行内解析扫到的一个候选：切点 + 切点之前的文字 + 标记本身 + 标记里的文字 +
    ///（链接才有）目标 + 切点之后的剩余。
    private struct InlineMarker {
        var start: Range<String.Index>
        var before: Substring
        var marker: String
        var inner: Substring
        var target: Substring?
        var after: Substring
    }

    private static func nextMarker(in text: Substring) -> InlineMarker? {
        // **取最早出现的那个标记**（不是"先试代码再试粗体"——那样会把更早的粗体漏掉，
        // 本轮测试当场抓到：`普通 **加粗** … ` 里的粗体被当成了前导纯文本）。
        // 另外**空内容不算一对**（`**粗体` 未闭合时不该被剥掉一颗星）。
        // 链接（`[`）与三个成对标记**同一个先来后到**：谁先出现切谁。
        var best: InlineMarker?
        for marker in ["`", "**", "*", "["] {
            guard let start = text.range(of: marker) else { continue }
            if let best, best.start.lowerBound <= start.lowerBound { continue }
            guard let candidate = markerCandidate(in: text, marker: marker, at: start) else { continue }
            best = candidate
        }
        return best
    }

    /// 从 `start` 处切一刀：成对标记看**同一个标记的下一处**，链接看**紧挨着的 `](` 与第一个 `)`**。
    private static func markerCandidate(
        in text: Substring,
        marker: String,
        at start: Range<String.Index>
    ) -> InlineMarker? {
        if marker == "[" {
            return linkMarker(in: text, at: start)
        }
        let afterStart = text[start.upperBound...]
        guard let end = afterStart.range(of: marker) else { return nil }
        let inner = afterStart[afterStart.startIndex..<end.lowerBound]
        guard !inner.isEmpty else { return nil }
        return InlineMarker(
            start: start,
            before: text[text.startIndex..<start.lowerBound],
            marker: marker,
            inner: inner,
            target: nil,
            after: afterStart[end.upperBound...]
        )
    }

    /// `[文字](目标)`（队列 `L-137` 剩余③）。
    ///
    /// 四条边界都写在这里，不留在"读代码的人自己想"：
    /// ① `](` 必须**紧挨着**（`[文字] (目标)` 不是链接）；
    /// ② 文字与目标**都非空**；
    /// ③ 文字与目标**都不许跨行** —— 一个 `](` 能跨过整篇把后面的文字吞进"链接文字"里，
    ///    那是"吞"，与这个文件的口径相反；
    /// ④ 目标取**第一个 `)`**，**不做括号平衡**（`[a](b(c))` 的目标是 `b(c`，
    ///    多出来那个 `)` 留在剩余文本里原样搬运）。
    private static func linkMarker(in text: Substring, at start: Range<String.Index>) -> InlineMarker? {
        guard let bracket = text.range(of: "](", range: start.upperBound..<text.endIndex) else { return nil }
        let inner = text[start.upperBound..<bracket.lowerBound]
        guard !inner.isEmpty, !inner.contains("\n") else { return nil }
        let targetStart = bracket.upperBound
        guard let close = text.range(of: ")", range: targetStart..<text.endIndex) else { return nil }
        let target = text[targetStart..<close.lowerBound]
        guard !target.isEmpty, !target.contains("\n") else { return nil }
        return InlineMarker(
            start: start,
            before: text[text.startIndex..<start.lowerBound],
            marker: "[",
            inner: inner,
            target: target,
            after: text[close.upperBound...]
        )
    }

    // MARK: - span 树 → 权威源

    /// span 树 → 权威源。**能进 Markdown 的进 Markdown，进不了的落旁挂** ——
    /// 这样"编辑器里改过再存"不会悄悄丢掉颜色与字号。
    public static func fromSpans(_ spans: [NoteSpan]) -> NoteBody {
        var markdown = ""
        var sidecar: [NoteSidecarStyle] = []
        var seen: [String: Int] = [:]

        for span in spans {
            var text = span.text
            if let link = span.link {
                // **链接优先**：`[文字](目标)` 是 Markdown 表达得了的 ⇒ 与颜色 / 字号那两档不同，
                // **不落旁挂**（往返原样，见 `testLinkRoundTripStaysInMarkdown`）。
                text = "[" + span.text + "](" + link + ")"
            } else if span.styles.contains(.code) {
                text = "`" + text + "`"
            } else {
                if span.styles.contains(.bold) { text = "**" + text + "**" }
                if span.styles.contains(.italic) { text = "*" + text + "*" }
            }
            markdown += text

            if span.color != nil || span.size != nil {
                let occurrence = seen[span.text, default: 0]
                seen[span.text] = occurrence + 1
                sidecar.append(NoteSidecarStyle(text: span.text, occurrence: occurrence, color: span.color, size: span.size))
            }
        }
        return NoteBody(markdown: markdown, sidecar: sidecar)
    }

    // MARK: - 导出（给"导出 .md 文件"用，必须报降级）

    public struct ExportResult: Equatable, Sendable {
        public var markdown: String
        /// 导出后**一定会丢**的东西（人要看得到，而不是自己发现）。
        public var degradations: [String]
    }

    public static func exportMarkdown(_ body: NoteBody, language: AppLanguage) -> ExportResult {
        var degradations: [String] = []
        for style in body.sidecar {
            var lost: [String] = []
            if let color = style.color { lost.append(LocalizedStrings.format(.noteLostColor, language: language, color)) }
            if let size = style.size { lost.append(LocalizedStrings.format(.noteLostSize, language: language, String(size))) }
            if !lost.isEmpty {
                degradations.append(LocalizedStrings.format(.noteExportDegraded, language: language, style.text, lost.joined(separator: " / ")))
            }
        }
        // 导出的是**权威源本身**（不重排、不美化）：AI 写进来的排版不该被我们改掉。
        return ExportResult(markdown: body.markdown, degradations: degradations)
    }
}
