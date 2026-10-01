import AppKit
import Combine
import DoyahCore
import SwiftUI

/// 工作区 Markdown 预览的**渲染侧**（队列 `L-137` 第三片）。
///
/// ## 这一层只做一件事：把模型画出来
///
/// 块级结构与行内标记**都不在本文件里重新解析** —— 前者来自契约层
/// `MarkdownDocument`，后者是笔记侧同一个函数产出的 span。门禁
/// `Scripts/check-markdown-single-source.py` 守这一条（在 `App/` 里自己造一个
/// 块对象即红）。本文件只做三件：只读渲染 / 跟随滚动 / 如实报数。
///
/// ## 三条口径
///
/// ① **只读** —— 预览不是第二个编辑器（需求已拍板 Markdown 是唯一真相），
///    所以这里一个可编辑文本视图都没有（纯 `Text` 组合，不引 `NSTextView`）。
/// ② **跟随滚动** —— 编辑区光标行 → `MarkdownDocument.anchor(forSourceLine:)`
///    → 顶层块下标 → 滚到那一块。嵌套子块（列表里的子列表…）**只滚到它的顶层块**，
///    不另做一套"预览内行号"（那正是「数文本算行号」那条错路）。
/// ③ **如实报数** —— 解析被截断时预览底部必须说出少画了多少，不静默少画。
///
/// ## 边界（如实登记，别当已验）
///
/// · 链接**还不可点** ——「在已内嵌的浏览器页签里打开」要先定「链接进不进笔记侧
///   span 树」这条契约口径（队列 `L-137` 剩余③），本片不顺手加；
/// · 解析未做防抖，靠 `MarkdownDocument.parse` 自身上限（20,000 行 / 5,000 块）
///   兜住最坏情况，且解析在后台任务里跑（不占主线程）；
/// · 旁挂样式（`NoteSpan` 的 `color` / `size`）不生效 —— 它们来自笔记侧旁挂，
///   Markdown 文件里结构上不存在。
struct MarkdownPreviewView: View {
    /// 被预览的原文（与编辑区同一份 `WorkspaceTab.content`）。
    let text: String
    /// 该文件的语言（围栏代码块里没写语言时用它着色）。
    let language: TextLanguage
    /// 跟随滚动的输入面：编辑区光标所在行。
    @ObservedObject var cursor: MarkdownPreviewCursorModel

    @State private var document = MarkdownDocument.parse("")

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView { content }
                    .onChange(of: cursor.line) { _, line in
                        scroll(proxy, toSourceLine: line)
                    }
                    .onChange(of: document) { _, _ in
                        scroll(proxy, toSourceLine: cursor.line)
                    }
            }
            reportBar
        }
        .background(Theme.surface(.content))
        // 解析放后台：`MarkdownDocument.parse` 是有上限的纯函数（`Sendable`），
        // 但大文件上仍是毫秒级 —— 放主线程上打字会跟手变差。
        .task(id: text) {
            let parsed = await Task.detached(priority: .userInitiated) {
                MarkdownDocument.parse(text)
            }.value
            guard !Task.isCancelled else { return }
            document = parsed
        }
    }

    // MARK: 底稿

    @ViewBuilder
    private var content: some View {
        if document.blocks.isEmpty {
            Text(L(.workspacePreviewEmpty))
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.text(.tertiary))
                .padding(Spacing.l)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            MarkdownBlocksView(blocks: document.blocks, language: language)
        }
    }

    /// 少画了多少 —— 只有真截断时才出现（干净文档上一行都不多余）。
    @ViewBuilder
    private var reportBar: some View {
        if let counts = MarkdownPreviewContent.truncationCounts(document.report) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "scissors")
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.status(.warning))
                Text(L(.workspacePreviewSkippedNotice))
                    .font(Theme.font(.caption))
                    .foregroundStyle(Theme.text(.secondary))
                Spacer(minLength: Spacing.s)
                if counts.skipped > 0 {
                    countBadge(counts.skipped, label: L(.workspacePreviewSkippedLines))
                }
                if counts.unparsed > 0 {
                    countBadge(counts.unparsed, label: L(.workspacePreviewUnparsedLines))
                }
            }
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, Spacing.xs)
            .background(Theme.status(.warning).opacity(0.10))
        }
    }

    /// 计数按「标签 + 数字」分开画：数字是数据、不是文案 ⇒ **不进语言表**，
    /// 也就不必给 `L(...)` 传实参（本工程对实参形状有棘轮，能不加就不加）。
    private func countBadge(_ count: Int, label: String) -> some View {
        HStack(spacing: Spacing.hair) {
            Text(label)
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.text(.secondary))
            Text(verbatim: "\(count)")
                .font(Theme.font(.monoSmall))
                .foregroundStyle(Theme.text(.primary))
            Text(L(.workspacePreviewLineUnit))
                .font(Theme.font(.caption))
                .foregroundStyle(Theme.text(.secondary))
        }
    }

    /// 光标行 → 顶层块下标 → 滚到那一块。目标为空（行号越界）就**什么都不做**，
    /// 不猜一个位置（越界时滚动会跳到无关的块上，比不滚更糟）。
    private func scroll(_ proxy: ScrollViewProxy, toSourceLine line: Int) {
        guard let target = MarkdownPreviewContent.scrollTarget(forSourceLine: line, in: document) else { return }
        proxy.scrollTo(target, anchor: .top)
    }
}

/// 块的排布（**只读**）。
///
/// 单独拎出来是为了让判据量的**就是真渲染的那一份**：`L-137` 的界面判据
/// （`TestsUISnapshot/MarkdownPreviewProbeTests.swift`）在离屏宿主里直接挂这个视图，
/// 而不是在测试里另拼一套 VStack —— 另拼一套只能证明"测试拼法会变高"。
struct MarkdownBlocksView: View {
    let blocks: [MarkdownBlock]
    let language: TextLanguage

    var body: some View {
        LazyVStack(alignment: .leading, spacing: Spacing.m) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                MarkdownBlockView(block: block, language: language)
                    // 滚动落点 = **顶层块下标**（与 `MarkdownPreviewAnchor.blockIndex` 同一个数）。
                    .id(index)
            }
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 一个块的渲染。**只读**：这里没有任何可编辑视图，也没有第二套解析。
///
/// 非 `private` 是有意的（判据要离屏量它），别把它当公开 API 用。
struct MarkdownBlockView: View {
    let block: MarkdownBlock
    let language: TextLanguage

    @ViewBuilder
    var body: some View {
        switch block.kind {
        case let .heading(level, spans):
            MarkdownInline.text(spans)
                .font(Theme.font(Self.headingStyle(level)))
                .foregroundStyle(Theme.text(.bright))
                .fixedSize(horizontal: false, vertical: true)
        case let .paragraph(spans):
            MarkdownInline.text(spans)
                .font(Theme.font(.body))
                .foregroundStyle(Theme.text(.primary))
                .fixedSize(horizontal: false, vertical: true)
        case let .bulletList(items):
            VStack(alignment: .leading, spacing: Spacing.xs) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    listRow(marker: Text(verbatim: "•"), spans: item.spans, children: item.children)
                }
            }
        case let .orderedList(start, items):
            VStack(alignment: .leading, spacing: Spacing.xs) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    listRow(marker: Text(verbatim: "\(start + index)."), spans: item.spans, children: item.children)
                }
            }
        case let .taskList(items):
            VStack(alignment: .leading, spacing: Spacing.xs) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    taskRow(item)
                }
            }
        case let .table(header, alignments, rows):
            VStack(alignment: .leading, spacing: 0) {
                tableRow(header, alignments: alignments, isHeader: true)
                Divider()
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    tableRow(row, alignments: alignments, isHeader: false)
                }
            }
        case let .codeBlock(fence, lines):
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    // 围栏没写语言 ⇒ **不着色**（模型的口径就是"不猜"），
                    // 拿外层文件的语言去猜会把 shell 片段按 markdown 着色。
                    MarkdownCodeLine.text(line, language: fence.flatMap(TextLanguage.init(rawValue:)))
                }
            }
            .padding(Spacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface(.panel))
        case let .quote(blocks):
            HStack(alignment: .top, spacing: Spacing.s) {
                Rectangle()
                    .fill(Theme.text(.tertiary))
                    .frame(width: Spacing.hair)
                VStack(alignment: .leading, spacing: Spacing.s) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, child in
                        MarkdownBlockView(block: child, language: language)
                    }
                }
            }
        case .thematicBreak:
            Divider()
        }
    }

    // MARK: 行

    private func listRow(marker: Text, spans: [NoteSpan], children: [MarkdownBlock]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            marker
                .font(Theme.font(.body))
                .foregroundStyle(Theme.text(.tertiary))
                .frame(minWidth: Spacing.l, alignment: .trailing)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                MarkdownInline.text(spans)
                    .font(Theme.font(.body))
                    .foregroundStyle(Theme.text(.primary))
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                    MarkdownBlockView(block: child, language: language)
                }
            }
        }
    }

    private func taskRow(_ item: MarkdownTaskItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            Image(systemName: item.isChecked ? "checkmark.square.fill" : "square")
                .font(Theme.font(.caption))
                .foregroundStyle(item.isChecked ? Theme.status(.success) : Theme.text(.tertiary))
            VStack(alignment: .leading, spacing: Spacing.xs) {
                MarkdownInline.text(item.spans)
                    .font(Theme.font(.body))
                    .foregroundStyle(item.isChecked ? Theme.text(.secondary) : Theme.text(.primary))
                    .strikethrough(item.isChecked)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Array(item.children.enumerated()), id: \.offset) { _, child in
                    MarkdownBlockView(block: child, language: language)
                }
            }
        }
    }

    private func tableRow(
        _ cells: [[NoteSpan]],
        alignments: [MarkdownColumnAlignment],
        isHeader: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
                MarkdownInline.text(cell)
                    .font(Theme.font(isHeader ? .bodyStrong : .body))
                    .foregroundStyle(Theme.text(isHeader ? .bright : .primary))
                    .frame(maxWidth: .infinity, alignment: Self.alignment(at: index, in: alignments))
            }
        }
        .padding(.vertical, Spacing.hair)
    }

    private static func headingStyle(_ level: Int) -> Theme.TextStyle {
        switch level {
        case ...1: return .title
        case 2: return .bodyStrong
        default: return .body
        }
    }

    private static func alignment(at index: Int, in alignments: [MarkdownColumnAlignment]) -> Alignment {
        guard index < alignments.count else { return .leading }
        switch alignments[index] {
        case .unspecified, .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}

/// 行内 span → `Text`（只读组合）。
///
/// 本层**不解析任何标记**：`spans` 是笔记侧同一个函数
/// （`NoteBodyProjection.parseInline`）的产物，这里只把 bold / italic / code
/// 三种样式映射成字体与颜色。
enum MarkdownInline {
    static func text(_ spans: [NoteSpan]) -> Text {
        spans.reduce(Text(verbatim: "")) { $0 + run($1) }
    }

    private static func run(_ span: NoteSpan) -> Text {
        var text = Text(verbatim: span.text)
        if span.styles.contains(.bold) { text = text.bold() }
        if span.styles.contains(.italic) { text = text.italic() }
        if span.styles.contains(.code) {
            text = text
                .font(Theme.font(.monoSmall))
                .foregroundColor(Theme.syntax(.function))
        }
        return text
    }
}

/// 围栏代码块的**一行** → `Text`：着色复用 `CodeLexer`（**同一个词法器**，
/// 不另写"预览版"关键字表），色值走 `SyntaxTone` 令牌（与编辑器同一套）。
enum MarkdownCodeLine {
    static func text(_ line: String, language: TextLanguage?) -> Text {
        let source = line.isEmpty ? " " : line
        guard let language else { return plain(source) }
        let tokens = CodeLexer.tokens(in: source, language: language).filter { $0.kind.isHighlighted }
        guard !tokens.isEmpty else { return plain(source) }
        var result = Text(verbatim: "")
        var position = source.startIndex
        // `where` 那一句是**防越界**：词法器给的是有序不重叠区间，真出现乱序时
        // 跳过那一段，而不是用 `position > lowerBound` 去切出一个非法区间。
        for token in tokens where token.range.lowerBound >= position {
            if position < token.range.lowerBound {
                result = result + plain(String(source[position..<token.range.lowerBound]))
            }
            result = result + Text(verbatim: String(source[token.range]))
                .foregroundColor(tint(for: token.kind))
            position = token.range.upperBound
        }
        if position < source.endIndex {
            result = result + plain(String(source[position...]))
        }
        return result
    }

    static func tint(for kind: CodeToken.Kind) -> Color {
        switch kind {
        case .keyword, .tag: return Theme.syntax(.keyword)
        case .builtin: return Theme.syntax(.function)
        case .string: return Theme.syntax(.string)
        case .comment: return Theme.syntax(.comment)
        case .number: return Theme.syntax(.number)
        case .attribute: return Theme.syntax(.identifier)
        case .identifier, .punctuation: return Theme.text(.primary)
        }
    }

    private static func plain(_ text: String) -> Text {
        Text(verbatim: text).foregroundColor(Theme.text(.primary))
    }
}

/// 预览的两件**纯逻辑**（界面上真的调它们，也就真被判据钉住）。
enum MarkdownPreviewContent {

    /// 光标行 → **滚动落点**（顶层块下标）。
    ///
    /// 这里刻意只做一次查表：块覆盖范围 / 嵌套下钻 / 越界返 `nil` 的口径
    /// 全部在契约层（`MarkdownDocument.anchor(forSourceLine:)`），
    /// 界面层再算一遍就是第二套口径。
    static func scrollTarget(forSourceLine line: Int, in document: MarkdownDocument) -> Int? {
        document.anchor(forSourceLine: line)?.blockIndex
    }

    /// 需要如实报出来的截断计数；**没截断就是 `nil`**（干净文档上不多画一行）。
    static func truncationCounts(_ report: MarkdownParseReport) -> (skipped: Int, unparsed: Int)? {
        guard report.isTruncated else { return nil }
        return (report.skippedLineCount, report.unparsedLineCount)
    }
}

/// 跟随滚动的**输入面**：编辑区光标所在行。
///
/// 为什么是一件独立对象、而不是 `WorkspaceAreaView` 的 `@State`：光标每换一行
/// 只该惊动**预览**这一侧。放进视图状态会让 `WorkspaceAreaView.body` 每次移动
/// 光标都重算，连带编辑器 `updateNSView` 里的全文比较也白跑一遍。
@MainActor
final class MarkdownPreviewCursorModel: ObservableObject {

    /// 1 起（与 `CodeLines` 的行号同一口径）；初值 1 = 文档开头。
    @Published private(set) var line: Int = 1

    /// 同一行重复上报**不再发布**（连按方向键时预览会反复对齐到同一块）。
    /// 越界值（≤ 0）直接丢掉 —— 宁可不动，也不猜一个位置。
    func report(line: Int) {
        guard line > 0, line != self.line else { return }
        self.line = line
    }
}
