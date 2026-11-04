import Foundation

// `FR-R-13-08` 右侧主工作区的**只读富文本块模型**（Retro macOS · M0 第 2 片）。
//
// 契约出处 = `Docs/需求规范书.md` §3.13 `FR-R-13-08` 原文：
//   > 右侧 = 主工作区（富文本正文渲染：**标题层级 / 段落 / 引用 / 表格 / 列表 / 图片内联 / 视频内联播放器**）；
//   > **M0 = 只读**（不做编辑器）；显示设定（字号 / 目录锚点 / 导出）**不得改变包内容**。
// 渲染契约 = `Docs/概要设计.md` §3.5「渲染契约（档案与周报）」+ 两条不变量 1「**渲染是纯函数**
// （同一份库数据 + 同一份模板 ⇒ 逐字节相同的产物）」。
//
// 本片**只做块模型与「`report.md` ⇒ 块序列」的纯函数渲染**（领域层）。视图层是 R-04 的活，
// 媒体白名单 / 视频 / 外链是 R-03 的活 —— 故这里：
//   · **不 import 任何 GUI 框架**（概要设计 §2.2「依赖方向不变量 1」）；
//   · **只读**：本模型**没有任何写回入口**（`FR-R-13-08` 判据 ③「视图内不产生任何写回包的动作」）；
//   · 视频 / 白名单**不在本片** —— 见 `MarkdownBlock` 的块枚举（无 `.video` 分支，媒体策略归 R-03）。

// MARK: - 图片（`IR-05` 不变量 3）

/// 一条图片引用 `![alt](reference)` 的**解析结果**。
///
/// `reference` 是 `report.md` 里**原样写的相对路径串**（`IR-05` 不变量 3：「媒体按相对路径引用
/// （`assets/xxx.png`），不用绝对路径、不内嵌 base64」）；`resolution` 是它落到盘上的去向。
public struct MarkdownImage: Equatable {
    public let alt: String
    public let reference: String
    public let resolution: ImageResolution

    public init(alt: String, reference: String, resolution: ImageResolution) {
        self.alt = alt
        self.reference = reference
        self.resolution = resolution
    }
}

/// 图片的两条去向：**解析成功**（包内绝对路径）或**原位占位**（并已逐条报告）。
public enum ImageResolution: Equatable {
    /// 解析成功 ⇒ **包内绝对路径**（URL 已标准化；视图层拿它直接取图）。
    case inPackage(URL)
    /// 未解析成功 ⇒ **原位占位** + 一条 `ReportRenderIssue`（**不许静默丢弃** —— `IR-05` 不变量 5 / `FR-R-13-09`）。
    case placeholder(reason: ImagePlaceholderReason)
}

/// 占位的原因。三条逐一对应本片的负例判据：
public enum ImagePlaceholderReason: Equatable {
    /// 路径是包内相对路径，但**盘上没有这个文件**。
    case fileMissing
    /// 路径含 `..`、或标准化后**跑到包外**（`FR-R-13-09` 判据 ④「路径越界（`../`）」）。
    case pathOutOfPackage
    /// 不是「包内相对路径」这种形态 —— **绝对路径 / `data:` base64 / 带 scheme 的外链**。
    ///
    /// 本渲染器**不设**「按绝对路径取文件」或「解码 base64」的分支（`IR-05` 不变量 3 的硬口径）；
    /// 这类引用一律走**拒绝 + 报告**这一条路，而不是被当成合法输入去解析。
    case referenceNotRelative
}

// MARK: - 块

/// `report.md` 渲染出来的一个**块**。
///
/// 枚举的九条分支逐一对应 `FR-R-13-08` 原文列举的渲染面（标题层级 / 段落 / 引用 / 表格 / 列表 /
/// 图片）+ Markdown 正文里会出现的代码块与分隔线。
public enum MarkdownBlock: Equatable {
    /// 标题，`level` ∈ 1...6（`#` 的个数）。
    case heading(level: Int, text: String)
    /// 段落（连续非空行**按 LF 原样保留**，不做折行重排 —— 「与源文一致」）。
    case paragraph(text: String)
    /// 引用块（`>` 起始的连续行；每行剥掉一层 `>` 与紧随的一个空格，行间 LF 保留）。
    case quote(text: String)
    /// 表格：表头 + 数据行（`|` 分隔，单元格去除两侧空白）。
    ///
    /// 渲染器**不补齐、不截断**行（列数不齐是源文自身的问题，视图层按缺失列留空即可）；
    /// 「列数一致」由单测逐条钉住合法表的形态。
    case table(header: [String], rows: [[String]])
    /// 无序列表（`-` / `*` / `+` 起始的连续项）。
    case unorderedList(items: [String])
    /// 有序列表（`1.` / `2.` … 起始的连续项）。
    case orderedList(items: [String])
    /// 图片（一行恰为 `![alt](reference)` 时成块；行进混排的图片留在段落原文里）。
    case image(MarkdownImage)
    /// 代码块（``` 围栏；`language` = 围栏后的信息串，缺省 `nil`）。
    case codeBlock(language: String?, text: String)
    /// 分隔线（`---` / `***` / `___`，至少三个同种字符）。
    case horizontalRule
}

// MARK: - 逐条报告

/// 渲染过程里的**一条**报告条目（`FR-R-13-08` 判据 ④「逐条报告且不崩」的机械形式）。
///
/// 与 R-01 的 `ReportPackageIssue` 同口径：**不抛异常、不静默降级** —— 出问题的块原位占位，
/// 同时在这里留一条可对账的记录。
public struct ReportRenderIssue: Equatable, CustomStringConvertible {
    public enum Kind: Equatable {
        /// 包内相对路径，但文件不在盘上。
        case imageFileMissing(reference: String)
        /// 路径越界（含 `..` 或标准化后跑到包外）。
        case imagePathOutOfPackage(reference: String)
        /// 非「包内相对路径」形态（绝对路径 / `data:` base64 / 带 scheme 的外链）。
        case imageReferenceNotRelative(reference: String)
    }

    /// 源文行号（1 起），便于把报告条目对回 `report.md`。
    public let line: Int
    public let kind: Kind

    public init(line: Int, kind: Kind) {
        self.line = line
        self.kind = kind
    }

    /// 人读的一行报告（回单 / 日志直接印）。
    public var description: String {
        switch kind {
        case .imageFileMissing(let reference):
            return "第 \(line) 行：图片文件缺失（\(reference)）—— 原位占位"
        case .imagePathOutOfPackage(let reference):
            return "第 \(line) 行：图片路径越界（\(reference)）—— 拒绝并原位占位"
        case .imageReferenceNotRelative(let reference):
            return "第 \(line) 行：图片引用不是包内相对路径（\(reference)）—— 拒绝并原位占位"
        }
    }
}

// MARK: - 渲染产物

/// 一次渲染的完整产物：块序列 + 逐条报告。**只读值类型**，没有任何写回入口。
public struct RenderedReport: Equatable {
    public let blocks: [MarkdownBlock]
    public let issues: [ReportRenderIssue]

    public init(blocks: [MarkdownBlock], issues: [ReportRenderIssue]) {
        self.blocks = blocks
        self.issues = issues
    }
}

// MARK: - 人读描述（纯函数判据的机械形式）

extension MarkdownBlock: CustomStringConvertible {
    /// 确定性的一行 / 多行描述。用途两条：① 排查时肉眼看得懂；② **纯函数判据**
    /// （同一份 `report.md` 连续两次渲染 ⇒ 逐字节相同）里拿来逐字节比的就是它。
    public var description: String {
        switch self {
        case .heading(let level, let text):
            return "H\(level) \(text)"
        case .paragraph(let text):
            return "P \(text)"
        case .quote(let text):
            return "Q \(text)"
        case .table(let header, let rows):
            let head = "T[" + header.joined(separator: "|") + "]"
            let body = rows.map { "[" + $0.joined(separator: "|") + "]" }.joined(separator: " ")
            return body.isEmpty ? head : head + " " + body
        case .unorderedList(let items):
            return "UL" + items.map { " <\($0)>" }.joined()
        case .orderedList(let items):
            return "OL" + items.map { " <\($0)>" }.joined()
        case .image(let image):
            switch image.resolution {
            case .inPackage(let url):
                return "IMG alt=\(image.alt) ref=\(image.reference) -> \(url.path)"
            case .placeholder(let reason):
                return "IMG alt=\(image.alt) ref=\(image.reference) -> 占位(\(reason))"
            }
        case .codeBlock(let language, let text):
            return "CODE(\(language ?? "")){\n\(text)\n}"
        case .horizontalRule:
            return "HR"
        }
    }
}

extension RenderedReport: CustomStringConvertible {
    /// 块的逐条描述，**LF 连接**（顺序即块的顺序，不去重、不排序 —— 纯函数的「逐字节」靠它可比）。
    /// 末尾追加报告条目区（无条目时为空），使两次渲染可以整体逐字节比对。
    public var description: String {
        var lines = blocks.map { $0.description }
        lines.append(contentsOf: issues.map { "ISSUE \($0.description)" })
        return lines.joined(separator: "\n")
    }
}
