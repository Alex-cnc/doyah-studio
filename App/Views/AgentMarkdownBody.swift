import DoyahCore
import SwiftUI

/// 对话正文的 **Markdown 渲染**（详设 `§5.3.8`「正文渲染」那一条）。
///
/// ## 三条硬口径
///
/// ① **解析只有一份**：正文 → `MarkdownDocument.parse`（契约层的块模型）→ `MarkdownBlock` 数组，
///    行内标记是笔记侧同一个函数（`NoteBodyProjection.parseInline`）产出的 `NoteSpan`。
///    本文件里**一个解析函数都没有** —— 围栏判闭合用的是契约层给出的 `unclosedFenceLine`，
///    不在这儿再扫一遍（`Scripts/check-markdown-single-source.py` 守这一条：
///    在 `App/` 里自己造块、或自带一份行内标记集合，即红）。
/// ② **流式未闭合 ⇒ 原文照发**：围栏只写了一半（```` ``` ```` 还没收口）时**不做猜测性渲染** ——
///    围栏**之前**的块照常画（它们已经定稿，高度不会变），从围栏那一行起**逐字**原样显示；
///    定稿（`isStreaming == false`）之后整段按完整文档重排。中途不换口径，所以不会抖高度。
/// ③ **呈现口径**：整份等宽（对话是终端语汇），代码块带 `─ 语言` 抬头 + 底色 + 描边。
///    这只是换了一份 `MarkdownPresentation` —— 块布局仍是 `MarkdownBlockView` 那一份，
///    没有第二套渲染。
///
/// ## 复制的是源码
/// 正文渲染在这里，**复制按钮拿的仍是 `AgentChatMessage.text`（Markdown 源码）** ——
/// 用户要拿去粘回终端 / 贴进文件，可见文本（粗体去过标记、代码块加了抬头）不是他想要的东西。
struct AgentMarkdownBody: View {

    /// Markdown **源码**（`AgentChatMessage.text`，逐字）。
    let text: String
    /// 这一条还在流式接收（决定「未闭合围栏」那一档走不走）。
    let isStreaming: Bool
    /// 正文用的字体（与行首栏同一支：转写区通篇等宽）。
    var font: Font = .system(.callout, design: .monospaced)
    /// 会话内搜索的命中词（`nil` / 空串 = 不染）。
    var highlight: String? = nil

    var body: some View {
        switch AgentMarkdownBodyContent.layout(text: text, isStreaming: isStreaming) {
        case let .document(document):
            blocks(document)
        case let .streaming(prefix, rawTail):
            VStack(alignment: .leading, spacing: Spacing.s) {
                blocks(prefix)
                raw(rawTail)
            }
        }
    }

    // MARK: - 两档渲染

    private func blocks(_ document: MarkdownDocument) -> some View {
        MarkdownBlocksView(
            blocks: document.blocks,
            // 外面那个 `language` 只在「围栏没写语言」时才有意义，而代码块的口径是
            // **不猜**（`MarkdownBlockView` 只认围栏自己的语言串）⇒ 这里给纯文本，不上色。
            language: .plainText,
            presentation: presentation,
            outerPadding: false,
            lazyBlocks: false
        )
    }

    /// **原文照发**：一个标记都不解释、一行都不重排。
    ///
    /// 为什么连行内强调都不染：流式中途的 `**` 可能正在写成 `***`，此刻「猜它已经是粗体」
    /// 与下一秒重排就会出现同一段字两种样子（正是契约禁止的「中途抖动」）。
    private func raw(_ source: String) -> some View {
        Text(TranscriptHighlight.apply(highlight, to: AttributedString(source)))
            .font(font)
            .foregroundStyle(Theme.text(.primary))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 对话那一档呈现口径（**只挑字体与描边**，不解一字节）。
    private var presentation: MarkdownPresentation {
        MarkdownPresentation(
            body: font,
            strong: font,
            mono: font,
            // 标题不换字号（终端只有一种字号），靠 `Theme.text(.bright)` 与语义位置区分层级。
            heading: { _ in font },
            code: .labelled,
            taskMark: .glyph,
            highlight: highlight
        )
    }
}

/// 正文的**排版决定**（纯函数，`Tests/AgentMarkdownBodyTests.swift` 钉着）。
///
/// 单独拎出来是为了让「什么时候原文照发」这件事能被单测逐条咬住 ——
/// 它是一句话的规矩，却最容易在视图里被写成「看起来差不多」。
enum AgentMarkdownBodyContent {

    enum Layout: Equatable {
        /// 定稿：整份按块渲染。
        case document(MarkdownDocument)
        /// 流式中且末尾有个**没收口**的围栏：围栏之前照常渲染，从围栏那一行起原文照发。
        case streaming(prefix: MarkdownDocument, rawTail: String)
    }

    /// 正文 → 排版决定。
    ///
    /// `isStreaming == false` 时**一律**按完整文档渲染：收尾之后不再有"半成品"这一说
    /// （未闭合的围栏按 CommonMark 跑到文末，那是定稿内容，照代码块画）。
    static func layout(text: String, isStreaming: Bool) -> Layout {
        let document = MarkdownDocument.parse(text)
        guard isStreaming, let fenceLine = document.unclosedFenceLine else {
            return .document(document)
        }
        let lines = text.components(separatedBy: "\n")
        guard fenceLine >= 1, fenceLine <= lines.count else { return .document(document) }
        // 围栏那一行（1 起）之前的全部算「已定稿」，从它本身起到文末算「还没写完」。
        let head = lines[0..<(fenceLine - 1)].joined(separator: "\n")
        let tail = lines[(fenceLine - 1)...].joined(separator: "\n")
        return .streaming(prefix: MarkdownDocument.parse(head), rawTail: tail)
    }
}
