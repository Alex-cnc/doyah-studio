import Foundation

/// **导出转换层 · HTML 半**（片 `WY-3a` · 派单 `T-20261008-050` 判据 4）。
///
/// 依据：`DR-09` 第三改判（正文权威源 = 富文本 spans · 导入/导出走转换层）+ 概要设计 `ADR-06`。
///
/// 三条口径（与 Markdown 半 `NoteBodyProjection.exportMarkdown` 同族）：
///   · **输入是权威源 `NoteBody`**，不是投影字符串 —— 行内颜色 / 字号 / 下划线 / 底色只长在 span 上，
///     拿 `body` 重解一遍 Markdown 会把它们全丢掉；HTML 表达得了它们，没有理由丢。
///   · **块级不另起一套** —— 标题层级来自 `MarkdownDocument`（块级唯一产地：本文件**不构造**
///     `MarkdownBlock`、不扫 Markdown 标记），列表来自 `NoteSpan.block`（片 `WY-1b2` 的块级三档）。
///   · **丢东西必须报** —— `degradations` 逐条如实写（样式值不是可渲染形态 / span 上不认得的字段），不静默。
///
/// 已知简化（如实登记，不假装覆盖）：围栏代码块 / 表格 / 引用在 v2 投影里仍是纯文本
/// （`NoteBodyProjection.markdown(from:)` 不生成它们的标记）⇒ HTML 里落成段落文本，原样可读。
public enum NoteHTMLExport {

    public struct Result: Equatable, Sendable {
        public var html: String
        public var degradations: [String]

        public init(html: String, degradations: [String] = []) {
            self.html = html
            self.degradations = degradations
        }
    }

    /// 导出**整份 HTML 文档**（`<!DOCTYPE html>` + `lang`）。`title` 非空时进 `<title>` 与首个 `<h1>`。
    public static func exportHTML(
        _ body: NoteBody,
        language: AppLanguage,
        title: String? = nil
    ) -> Result {
        var degradations = unrenderableFieldReports(body.spans, language: language)
        var bodyHTML = ""
        let lines = lineSpans(body.spans)
        let headings = headingLevels(in: MarkdownDocument.parse(body.body))
        var index = 0
        while index < lines.count {
            if let level = headings[index + 1] {
                let spans = strippingHeadingMarker(lines[index], level: level)
                let inline = inlineHTML(spans, degradations: &degradations, language: language)
                bodyHTML += "<h\(level)>" + inline + "</h\(level)>\n"
                index += 1
                continue
            }
            if let kind = listKind(of: lines[index]) {
                bodyHTML += "<" + kind.tag + ">\n"
                while index < lines.count, listKind(of: lines[index])?.grouping == kind.grouping {
                    bodyHTML += listItemHTML(lines[index], degradations: &degradations, language: language)
                    index += 1
                }
                bodyHTML += "</" + kind.tag + ">\n"
                continue
            }
            if isBlank(lines[index]) { index += 1; continue }
            var paragraphs: [String] = []
            while index < lines.count, !isBlank(lines[index]),
                  headings[index + 1] == nil, listKind(of: lines[index]) == nil {
                paragraphs.append(inlineHTML(lines[index], degradations: &degradations, language: language))
                index += 1
            }
            bodyHTML += "<p>" + paragraphs.joined(separator: "\n") + "</p>\n"
        }
        var html = "<!DOCTYPE html>\n<html lang=\"" + languageCode(language) + "\">\n<head>\n"
        html += "<meta charset=\"utf-8\">\n"
        if let title, !title.isEmpty { html += "<title>" + escaped(title) + "</title>\n" }
        html += "</head>\n<body>\n"
        if let title, !title.isEmpty { html += "<h1>" + escaped(title) + "</h1>\n" }
        html += bodyHTML
        html += "</body>\n</html>\n"
        return Result(html: html, degradations: degradations)
    }

    // MARK: - 行内

    private static func inlineHTML(
        _ spans: [NoteSpan],
        degradations: inout [String],
        language: AppLanguage
    ) -> String {
        var html = ""
        for span in spans {
            html += inlineHTML(span, degradations: &degradations, language: language)
        }
        return html
    }

    /// 一个 span → HTML。**嵌套即语义**：`<b><i>字</i></b>` 这种形状不需要，但同族标签按下面这个
    /// 固定顺序套（由内到外：代码 → 粗 → 斜 → 下划线 → 底色 → 文字色 → 字号 → 链接）——
    /// 顺序写死是为了「同一份 span 每次导出逐字一致」，不靠调用方自觉。
    private static func inlineHTML(
        _ span: NoteSpan,
        degradations: inout [String],
        language: AppLanguage
    ) -> String {
        var html = escaped(span.text)
        if span.styles.contains(.code) { html = "<code>" + html + "</code>" }
        if span.styles.contains(.bold) { html = "<b>" + html + "</b>" }
        if span.styles.contains(.italic) { html = "<i>" + html + "</i>" }
        if span.styles.contains(.underline) { html = "<u>" + html + "</u>" }
        let background = renderableColor(span.backgroundColor, label: "background-color", degradations: &degradations, language: language)
        if let background { html = "<mark style=\"background-color:" + background + "\">" + html + "</mark>" }
        let color = renderableColor(span.color, label: "color", degradations: &degradations, language: language)
        if let color { html = "<span style=\"color:" + color + "\">" + html + "</span>" }
        if let size = span.size {
            if size > 0 {
                html = "<span style=\"font-size:\(size)px\">" + html + "</span>"
            } else {
                degradations.append(LocalizedStrings.format(.noteHTMLLostStyle, language: language, String(size), "font-size"))
            }
        }
        if let link = span.link, !link.isEmpty {
            html = "<a href=\"" + escaped(link) + "\">" + html + "</a>"
        }
        return html
    }

    // MARK: - 块级

    private enum ListKind: Equatable {
        case bullet
        case ordered
        case task(checked: Bool)

        var tag: String {
            switch self {
            case .bullet, .task: return "ul"
            case .ordered: return "ol"
            }
        }

        /// **分组键**：勾选状态不同的两个任务项仍属**同一个** `<ul>`（否则每一项都会新开一个列表）。
        var grouping: String {
            switch self {
            case .bullet: return "bullet"
            case .ordered: return "ordered"
            case .task: return "task"
            }
        }
    }

    private static func listItemHTML(
        _ spans: [NoteSpan],
        degradations: inout [String],
        language: AppLanguage
    ) -> String {
        var prefix = ""
        if let kind = listKind(of: spans), case .task(let checked) = kind {
            prefix = "<input type=\"checkbox\"" + (checked ? " checked" : "") + " disabled> "
        }
        return "<li>" + prefix + inlineHTML(spans, degradations: &degradations, language: language) + "</li>\n"
    }

    /// 这一行是不是列表项、哪一档（看 `NoteSpan.block`；都没有 ⇒ `nil` = 不是列表项）。
    private static func listKind(of spans: [NoteSpan]) -> ListKind? {
        for span in spans {
            if let block = span.block {
                switch block {
                case .ordered: return .ordered
                case .bullet: return .bullet
                case .task(let checked): return .task(checked: checked)
                }
            }
        }
        return nil
    }

    /// 权威源 span 树 → **按行切**。只按 `\n` 切（与 `MarkdownBlockParser.splitLines` 同规则去掉行尾 `\r`），
    /// **不判任何 Markdown 语义** —— 「这一行是什么块」由 `MarkdownDocument`（标题）与 `span.block`（列表）说了算。
    private static func lineSpans(_ spans: [NoteSpan]) -> [[NoteSpan]] {
        var lines: [[NoteSpan]] = [[]]
        for span in spans {
            let pieces = span.text.split(separator: "\n", omittingEmptySubsequences: false)
            for (offset, piece) in pieces.enumerated() {
                if offset > 0 { lines.append([]) }
                var text = String(piece)
                if text.hasSuffix("\r") { text = String(text.dropLast()) }
                var copy = span
                copy.text = text
                lines[lines.count - 1].append(copy)
            }
        }
        return lines
    }

    private static func isBlank(_ spans: [NoteSpan]) -> Bool {
        spans.allSatisfy { $0.text.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// **标题层级只从 `MarkdownDocument` 取**（块级唯一产地）：收集「原文行号 → 层级」，引用/列表里嵌的标题也收。
    private static func headingLevels(in document: MarkdownDocument) -> [Int: Int] {
        var levels: [Int: Int] = [:]
        func walk(_ blocks: [MarkdownBlock]) {
            for block in blocks {
                switch block.kind {
                case let .heading(level, _): levels[block.sourceLine] = level
                case let .quote(children): walk(children)
                case let .bulletList(items):
                    for item in items { walk(item.children) }
                case let .orderedList(_, items):
                    for item in items { walk(item.children) }
                case let .taskList(items):
                    for item in items { walk(item.children) }
                default: break
                }
            }
        }
        walk(document.blocks)
        return levels
    }

    /// 标题行的 `#` 标记从**首段非空文本**上摘掉（行号与层级是 `MarkdownDocument` 判的，这里只摘已知宽度的前缀）。
    private static func strippingHeadingMarker(_ spans: [NoteSpan], level: Int) -> [NoteSpan] {
        var spans = spans
        guard let first = spans.firstIndex(where: { !$0.text.isEmpty }) else { return spans }
        var text = spans[first].text
        while text.hasPrefix(" ") { text.removeFirst() }
        var removed = 0
        while removed < level, text.hasPrefix("#") { text.removeFirst(); removed += 1 }
        while text.hasPrefix(" ") { text.removeFirst() }
        spans[first].text = text
        return spans.filter { !$0.text.isEmpty }
    }

    // MARK: - 降级报告（丢东西必须报）

    /// 颜色类样式值的**可渲染形态**（`#RRGGBB`）。不是这个形态 ⇒ 报一条降级、**按无样式处理**
    /// （把它原样写进 `style=` 会让浏览器静默丢掉整条声明，那才是真静默）。
    private static func renderableColor(
        _ value: String?,
        label: String,
        degradations: inout [String],
        language: AppLanguage
    ) -> String? {
        guard let value, !value.isEmpty else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.count == 7, trimmed.hasPrefix("#"), trimmed.dropFirst().allSatisfy({ $0.isHexDigit }) else {
            degradations.append(LocalizedStrings.format(.noteHTMLLostStyle, language: language, value, label))
            return nil
        }
        return trimmed
    }

    /// span 上**不认得**的字段（未来版本写的）逐条报出来 —— 前向兼容的另一半：留得住（模型），也要说得出（这里）。
    private static func unrenderableFieldReports(_ spans: [NoteSpan], language: AppLanguage) -> [String] {
        var reports: [String] = []
        for span in spans where !span.unknownFields.isEmpty {
            for key in span.unknownFields.keys.sorted() {
                reports.append(LocalizedStrings.format(.noteHTMLLostUnknownField, language: language, span.text, key))
            }
        }
        return reports
    }

    // MARK: - 零件

    private static func escaped(_ text: String) -> String {
        var out = ""
        for character in text {
            switch character {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            default: out.append(character)
            }
        }
        return out
    }

    private static func languageCode(_ language: AppLanguage) -> String {
        switch language {
        case .english: return "en"
        default: return "zh-Hans"
        }
    }
}
