import SwiftUI
import DoyahCore

/// 转写区的正文渲染（`§7.9.10` 的排版语汇 + 一直挂着的两个缺口）。
///
/// **这一版解决什么**（§9.1.16 缺口里最常被看到的两个）：
///   1. **围栏代码块**：` ```lang ` 成块 —— 等宽、只描边不铺底（§7.9.10 硬规则 ⑥）、可整段选中复制；
///   2. **行内代码与链接**：`code` 走等宽，`http(s)` 链接可点（`Text` 自带 `link` 属性，系统浏览器打开）。
///
/// **故意不做的**（写在这里免得被当成漏了）：
///   - **语法高亮**：那要引一整套词法器（`highlight.js` 之于 Web、`Splash` 之于 Swift），
///     与「正文一律等宽」的契约会打架；本版只保证「代码块一眼可辨、复制不走样」。
///   - **图片显示**：远端图片要下载 / 缓存 / 尺寸约束，属独立一片，见 §9.1.16 缺口登记。
///   - **表格**：GFM 表格要列宽计算，同样独立一片。
///
/// 复杂度刻意压得很低：只按行扫围栏（``` 或 ~~~），不写完整 Markdown 解析器 ——
/// 转写区是**模型输出**，不是文档，容错优先（认不出的就当普通文本，原样显示，绝不吞掉）。
struct AgentTranscriptText: View {
    let text: String
    /// 与行首栏对齐用的字体（等宽，来自 §7.9.10）。
    var font: Font = .system(.callout, design: .monospaced)
    /// 会话内搜索的命中词（`nil` / 空串 = 不染）。
    ///
    /// **判定在 Core、染色在界面**：偏移由 `AgentTranscriptSearch` 从**渲染出来的那串字**上取，
    /// 界面照着同一份偏移铺底色 —— 两边各算一遍必然出现「界面亮了两处、判据说一处」。
    var highlight: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            ForEach(Array(Self.blocks(text).enumerated()), id: \.offset) { _, block in
                switch block {
                case .prose(let raw):
                    inline(raw)
                case .code(let language, let code):
                    codeBlock(language: language, code: code)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 块

    enum Block: Equatable {
        case prose(String)
        case code(language: String?, code: String)
    }

    /// 按行切块：成对的围栏之间算代码，其余算正文。**落单的围栏当普通文本**（模型常常边写边流）。
    static func blocks(_ text: String) -> [Block] {
        var out: [Block] = []
        var prose: [String] = []
        var code: [String] = []
        var language: String?
        var inCode = false

        func flushProse() {
            let joined = prose.joined(separator: "\n")
            if !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                out.append(.prose(joined))
            }
            prose.removeAll()
        }

        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isFence = trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")
            if isFence {
                if inCode {
                    out.append(.code(language: language, code: code.joined(separator: "\n")))
                    code.removeAll()
                    language = nil
                    inCode = false
                } else {
                    flushProse()
                    let tag = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    language = tag.isEmpty ? nil : tag
                    inCode = true
                }
                continue
            }
            if inCode { code.append(line) } else { prose.append(line) }
        }
        if inCode {
            // 没闭合：已经写出来的代码照旧按代码显示（流式中途就是这个样子），不丢内容。
            out.append(.code(language: language, code: code.joined(separator: "\n")))
        } else {
            flushProse()
        }
        return out
    }

    // MARK: - 渲染

    /// 正文：Markdown 的行内语法（粗体 / 行内代码 / 链接）。解析失败就原样显示 —— 转写区不许「吞字」。
    private func inline(_ raw: String) -> some View {
        let attributed = TranscriptHighlight.apply(highlight, to: Self.inlineAttributed(raw, font: font))
        return Text(attributed)
            .font(font)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func inlineAttributed(_ raw: String, font: Font) -> AttributedString {
        var attributed: AttributedString
        if let parsed = try? AttributedString(
            markdown: raw,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            attributed = parsed
        } else {
            attributed = AttributedString(raw)
        }
        // 行内代码：等宽 + 次要色。逐 run 改属性（`inlinePresentationIntent` 是 Markdown 给的语义）。
        for run in attributed.runs {
            if run.inlinePresentationIntent?.contains(.code) == true {
                attributed[run.range].font = .system(.callout, design: .monospaced)
                attributed[run.range].foregroundColor = Theme.text(.secondary)
            }
        }
        return attributed
    }

    /// 代码块：**照 Hermes TUI 的样子** —— 没有框、没有底纹，只有一行 `─ 语言` 抬头，
    /// 正文缩进两格、整块等宽（`markdown.tsx`：`paddingLeft={2}` + `'─ ' + lang`）。
    ///
    /// **着色复用编辑器那套词法器**（`CodeLexer` + `Theme.syntax`），不另写一份：
    /// 两处各写一份词法，迟早是「编辑器里对、对话里错」——而错的代价是**误导**（颜色错了，
    /// 人会以为自己在看真语法）。语言认不出就不染（`TextLanguage.detect` 给 `.plainText` 时
    /// `CodeLexer` 只产一段 plain，正文逐字不变）。
    private func codeBlock(language: String?, code: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let language, !language.isEmpty {
                Text("─ " + language)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(Theme.text(.tertiary))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(highlighted(code, language: language))
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.leading, Spacing.m)          // 两格缩进（与 TUI 的 paddingLeft={2} 同义）
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 把词法记号拼成带色富文本（**拼回去等于原文**：记号覆盖整段，不重排、不裁剪）。
    private func highlighted(_ code: String, language: String?) -> AttributedString {
        let lang = CodeFenceLanguage.resolve(language)
        var out = AttributedString()
        var cursor = code.startIndex
        for token in CodeLexer.tokens(in: code, language: lang) where token.kind.isHighlighted {
            if cursor < token.range.lowerBound {
                out.append(AttributedString(String(code[cursor..<token.range.lowerBound])))
            }
            var piece = AttributedString(String(code[token.range]))
            piece.foregroundColor = MarkdownCodeLine.tint(for: token.kind)
            out.append(piece)
            cursor = token.range.upperBound
        }
        if cursor < code.endIndex {
            out.append(AttributedString(String(code[cursor...])))
        }
        return out
    }

    @Environment(\.colorScheme) private var colorScheme
}

/// 会话内搜索的**染色**那一层（判定在 `AgentTranscriptSearch`）。
///
/// 为什么单独拎出来：转写区里三处都要染（正文 / 工具行 / 时间线事件），
/// 各写一遍 `attributed.characters.index(…)` 就等于三份偏移换算 —— 换一处漏一处。
/// 这里只认「渲染出来的那串字」，所以 Markdown 解析过的正文与纯文本走同一条路。
enum TranscriptHighlight {

    /// 命中底色。**只铺底、不改字色** —— 改字色会让代码行内代码（本来就有次要色）失去区分，
    /// 而且深色 / 浅色两档主题下同一个字色不会都对。
    static func apply(_ needle: String?, to attributed: AttributedString) -> AttributedString {
        guard let needle,
              !needle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return attributed }
        let plain = String(attributed.characters)
        let ranges = AgentTranscriptSearch.occurrences(of: needle, in: plain)
        guard !ranges.isEmpty else { return attributed }

        var out = attributed
        for range in ranges {
            guard range.upperBound <= out.characters.count else { continue }
            let start = out.characters.index(out.startIndex, offsetBy: range.lowerBound)
            let end = out.characters.index(out.startIndex, offsetBy: range.upperBound)
            out[start..<end].backgroundColor = Theme.status(.warning).opacity(0.22)
        }
        return out
    }
}
