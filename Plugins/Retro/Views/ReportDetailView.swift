import AppKit
import SwiftUI

import DoyahRetroCore

// `FR-R-13-08` 右侧**只读富文本工作区**（Retro macOS · M0 第 4 片 · 派单卡 `t_66956c06`）。
//
// 契约出处 = `Docs/需求规范书.md` §3.13 `FR-R-13-08` 判据 ②③④ + §3.13 `FR-R-13-09`（多媒体契约）：
//   > **右侧 = 主工作区**（富文本正文渲染：标题层级 / 段落 / 引用 / 表格 / 列表 / **图片内联** /
//   > **视频内联播放器**）；**M0 = 只读**；显示设定不得改变包内容。
//   > 判据 ④：空包 / 缺件 / 编码错 ⇒ **逐条报告且不崩**。
//
// 分工（**各层各守一段，不重写**）：
//   · 块结构 / 图片四条去向 = 领域层 `ReportRenderer`（R-02，纯函数）；
//   · 媒体去向（白名单图片内联 / `mp4` 本地内联 / `http(s)` 外链 / 占位）= 领域层 `MediaResolve`（R-03）；
//   · 本文件只把「块序列 + 媒体去向」**画出来**，并在视图尾部逐条列出报告面（渲染报告 + 媒体报告）。
//
// **视频怎么进来的**：R-02 的块模型没有 `.video` 分支（媒体策略归 R-03）—— `report.md` 里
// `![alt](assets/clip.mp4)` 在块层就是一个 `.image`；本视图层把它的 `reference` 交给
// `MediaResolve`，**由领域层判定**它是白名单图片、白名单视频还是外链 / 占位（不在这里猜扩展名）。
//
// **只读**（判据 ③）：本文件只读盘上文件用于显示（`NSImage(contentsOf:)` 是**读**），
// 全层没有任何对包目录的写动作 —— 机械判据 = `Tools/check-readonly.py`。
// **外链不嵌 iframe**（`FR-R-13-09` 视频②）：外链一律走 `ExternalLinkButton`（交系统默认处理）。

// MARK: - 右区（一期 = 一份包）

/// 一期周报的右区：正文（`report.md` ⇒ 块序列）+ 逐条报告。
public struct ReportDetailView: View {
    public let package: ReportPackage
    /// 块序列 + 渲染报告（R-02 的纯函数产物；**只读值类型**）。
    public let rendered: RenderedReport
    /// 媒体报告（R-03：白名单外 / 缺失 / 越界 / 非相对 —— 逐条）。
    public let mediaIssues: [MediaIssue]

    public init(package: ReportPackage) {
        self.package = package
        let rendered = ReportRenderer.render(package: package)
        self.rendered = rendered
        self.mediaIssues = rendered.blocks.compactMap { block -> MediaIssue? in
            guard case .image(let image) = block else { return nil }
            return MediaResolve.resolve(
                reference: image.reference,
                packageDirectory: package.directoryURL
            ).issue
        }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                Divider()
                ForEach(Array(rendered.blocks.enumerated()), id: \.offset) { pair in
                    blockView(for: pair.element)
                }
                if !rendered.issues.isEmpty || !mediaIssues.isEmpty {
                    Divider()
                    issueSection
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: 头部（期号 / 日期 / 标题 / 摘要 / 媒体件数）

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(package.metadata.title)
                .font(.title2)
                .bold()
            HStack(spacing: 10) {
                Text("期号 \(package.metadata.id)")
                Text(package.metadata.published)
                Text("媒体 \(package.metadata.mediaCount) 件")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if !package.metadata.summary.isEmpty {
                Text(package.metadata.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: 块 ⇒ 视图（九条分支逐条对应 `MarkdownBlock`）

    @ViewBuilder
    private func blockView(for block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(text)
                .font(headingFont(level: level))
                .bold()
                .padding(.top, 4)
        case .paragraph(let text):
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        case .quote(let text):
            HStack(alignment: .top, spacing: 8) {
                Rectangle()
                    .frame(width: 3)
                    .foregroundStyle(.secondary)
                Text(text)
                    .italic()
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .table(let cells, let rows):
            TableBlockView(columns: cells, rows: rows)
        case .unorderedList(let items):
            ListBlockView(items: items, ordered: false)
        case .orderedList(let items):
            ListBlockView(items: items, ordered: true)
        case .image(let image):
            MediaBlockView(
                alt: image.alt,
                reference: image.reference,
                packageDirectory: package.directoryURL
            )
        case .codeBlock(let language, let text):
            CodeBlockView(language: language, text: text)
        case .horizontalRule:
            Divider()
        }
    }

    private func headingFont(level: Int) -> Font {
        switch level {
        case 1: return .largeTitle
        case 2: return .title
        case 3: return .title2
        case 4: return .title3
        case 5: return .headline
        default: return .subheadline
        }
    }

    // MARK: 逐条报告（渲染报告 + 媒体报告，都不静默）

    private var issueSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("逐条报告（\(rendered.issues.count + mediaIssues.count) 条）")
                .font(.headline)
            ForEach(Array(rendered.issues.enumerated()), id: \.offset) { pair in
                issueLine(pair.element.description)
            }
            ForEach(Array(mediaIssues.enumerated()), id: \.offset) { pair in
                issueLine(pair.element.description)
            }
        }
    }

    private func issueLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - 媒体（去向由领域层 `MediaResolve` 定，视图层只负责画）

/// 一个媒体引用 ⇒ 去向视图。**单一事实源 = `MediaResolve`**（R-03）：
///   白名单图片 ⇒ 内联图；白名单视频（`mp4`）⇒ 本地内联播放器；
///   `http(s)` 外链 ⇒ 外链按钮（**不嵌 iframe / WebView**）；其余 ⇒ 原位占位。
struct MediaBlockView: View {
    let alt: String
    let reference: String
    let packageDirectory: URL

    var body: some View {
        switch MediaResolve.resolve(reference: reference, packageDirectory: packageDirectory).resolution {
        case .inlineImage(_, let url):
            InlineImageView(alt: alt, url: url)
        case .inlineVideo(_, let url):
            VideoPlayerView(url: url, caption: alt)
        case .externalLink(let url):
            ExternalLinkButton(url: url, title: alt.isEmpty ? url.absoluteString : alt)
        case .placeholder(let reason, let reference):
            PlaceholderMediaView(reason: reason, reference: reference, alt: alt)
        }
    }
}

/// 包内图片**内联显示**（`FR-R-13-09` 图片口径 = 内联）。`NSImage(contentsOf:)` 只**读**盘。
struct InlineImageView: View {
    let alt: String
    let url: URL
    var maxWidth: CGFloat = 520
    var showsCaption: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: maxWidth, alignment: .leading)
            } else {
                Text("图片读不出：\(url.lastPathComponent)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if showsCaption, !alt.isEmpty {
                Text(alt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// 取不到内联的媒体 ⇒ **原位占位**（`FR-R-13-09` 判据 ③④：占位 + 一条报告，**不静默丢弃**）。
struct PlaceholderMediaView: View {
    let reason: MediaPlaceholderReason
    let reference: String
    let alt: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(alt.isEmpty ? reference : alt)
                    .font(.callout)
                Text(reason.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - 表格 / 列表 / 代码块（纯展示，数据全来自块模型）

/// 表格：表头 + 数据行。**不补齐、不截断**行（源文列数不齐是源文自身的事，短行缺列留空）。
struct TableBlockView: View {
    let columns: [String]
    let rows: [[String]]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) { cells(columns, bold: true) }
            Divider()
            ForEach(Array(rows.enumerated()), id: \.offset) { pair in
                HStack(alignment: .top, spacing: 12) { cells(pair.element, bold: false) }
            }
        }
        .padding(8)
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private func cells(_ values: [String], bold: Bool) -> some View {
        ForEach(Array(columns.indices), id: \.self) { index in
            Text(index < values.count ? values[index] : "")
                .font(bold ? .headline : .body)
                .frame(minWidth: 60, alignment: .leading)
        }
    }
}

/// 无序（`•`）/ 有序（`1.`）列表。
struct ListBlockView: View {
    let items: [String]
    let ordered: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { pair in
                HStack(alignment: .top, spacing: 6) {
                    Text(ordered ? "\(pair.offset + 1)." : "•")
                        .font(.system(.body, design: .monospaced))
                        .frame(minWidth: 18, alignment: .trailing)
                    Text(pair.element)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// 代码块（``` 围栏；`language` = 围栏后的信息串）。
struct CodeBlockView: View {
    let language: String?
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let language, !language.isEmpty {
                Text(language)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(text)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.gray.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}
