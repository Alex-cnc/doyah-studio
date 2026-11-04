import Foundation

// 一条**媒体引用 ⇒ 解析结果**（Retro macOS · M0 第 3 片 · 派单卡 `t_b92f9c11`）。
//
// 契约出处与硬口径见 `MediaPolicy.swift` 文件头（`FR-R-13-09` / `IR-05` 不变量 3 + 5）。
// 本文件只落「一条引用 → 一条去向」的**纯函数**映射：
//   · 白名单图片（相对路径 + 文件在盘上）⇒ `.inlineImage`（**包内绝对路径**）；
//   · 白名单视频（`mp4`）⇒ `.inlineVideo`（**本地内联可播候选** —— 本层只给策略与去向，
//     **不接播放器**，能不能解码是播放层的事）；
//   · 白名单外格式（`avi` / `mov` / 无扩展名 …）⇒ `.placeholder(formatNotWhitelisted)` + **一条报告**
//     （`IR-05` 不变量 5「原位降级为占位，不报错、不崩」）；
//   · 文件缺失 ⇒ `.placeholder(fileMissing)` + 一条报告；
//   · 路径越界（含 `..`、或标准化后跑到包外）⇒ `.placeholder(pathOutOfPackage)` + 一条报告；
//   · 非相对形态（绝对路径 / base64）⇒ `.placeholder(referenceNotRelative)` + 一条报告；
//   · `http(s)://` 外链 ⇒ `.externalLink` —— **交系统默认处理**（点击打开浏览器 / 系统播放器），
//     **不产生报告**（合法形态、不是错），**本层不设 iframe / WebView 分支**。
//
// 判定序（**先形态 → 再白名单 → 后碰盘**），与判据 ③ 的逐条口径一一对应：
//   ① 形态分类（词法）→ 外链 / 非相对 直接定案；
//   ② `..` 越界（词法）；
//   ③ 扩展名白名单（词法）—— 白名单外**到此为止**，**根本不碰盘**（不会因为「盘上恰好有个同名
//      `avi`」之类的事改判；格式门在存盘门之前）；
//   ④ 锚在包目录解析 + **包内复核**（词法标准化后的双保险）；
//   ⑤ 文件在盘上？（**唯一碰盘的一步**）。
//
// **只读**：本层只 `FileManager.fileExists` 探一次盘，**没有任何写盘入口**（与 `IR-05` 不变量 7
// 「Retro 不写这个包」同口径）。**逐条报告且不崩**：任何取不到的引用都落 `placeholder` + `issue`，
// **不 throw、不中断**（与 `FR-R-13-08` ④ 同口径）。

// MARK: - 占位原因

/// 一条引用**没内联成**时，为什么原位占位。四条逐一对应本片的负例判据。
public enum MediaPlaceholderReason: Equatable, CustomStringConvertible {
    /// 白名单内的扩展名，但**盘上没有这个文件**。
    case fileMissing
    /// 含 `..`、或标准化后**跑到包外**（`FR-R-13-09` 判据 ④「路径越界（`../`）」）。
    case pathOutOfPackage
    /// 不是「包内相对路径」形态 —— **绝对路径 / `data:` base64 / 其它 scheme**。本层**不设**
    /// 「按绝对路径取文件」或「解码 base64」的分支（`IR-05` 不变量 3 的硬口径）。
    case referenceNotRelative
    /// 扩展名**不在白名单**（`avi` / `mov` / 无扩展名 …）—— `IR-05` 不变量 5「原位降级为占位」。
    /// `fileExtension` 保留原串（可能是 `nil` = 无扩展名），便于报告里点得出是哪种格式。
    case formatNotWhitelisted(fileExtension: String?)

    public var description: String {
        switch self {
        case .fileMissing:
            return "文件缺失"
        case .pathOutOfPackage:
            return "路径越界"
        case .referenceNotRelative:
            return "引用不是包内相对路径"
        case .formatNotWhitelisted(let fileExtension):
            return "格式不在白名单（\(fileExtension ?? "无扩展名")）"
        }
    }
}

// MARK: - 解析结果

/// 一条媒体引用的**去向**。
public enum MediaResolution: Equatable {
    /// 白名单图片 ⇒ 内联（`url` = **包内绝对路径**，视图层拿它直接取图）。
    case inlineImage(reference: String, url: URL)
    /// 白名单视频 ⇒ 本地内联（`url` = 包内绝对路径）—— **可播候选**，播放器不在本层。
    case inlineVideo(reference: String, url: URL)
    /// 外链 ⇒ **交系统默认处理**（点击打开浏览器 / 系统播放器，本层不嵌 iframe / WebView）。
    /// 合法形态 ⇒ **不产生报告条目**。
    case externalLink(url: URL)
    /// 未内联成功 ⇒ **原位占位** + 一条 `MediaIssue`（**不许静默丢弃** —— `FR-R-13-09` 判据 ④）。
    case placeholder(reason: MediaPlaceholderReason, reference: String)

    /// 是不是「内联」去向（图片 / 视频）—— 视图层据此走内联渲染。
    public var isInline: Bool {
        switch self {
        case .inlineImage, .inlineVideo: return true
        case .externalLink, .placeholder: return false
        }
    }

    /// 是不是「占位」去向（此时 `MediaResolveOutcome.issue` 必有一条）。
    public var isPlaceholder: Bool {
        if case .placeholder = self { return true }
        return false
    }
}

extension MediaResolution: CustomStringConvertible {
    /// 确定性的一行描述（回单 / 日志 / 排查直接印；两次解析同一输入必逐字节同形）。
    public var description: String {
        switch self {
        case .inlineImage(let reference, let url):
            return "IMG ref=\(reference) -> \(url.path)"
        case .inlineVideo(let reference, let url):
            return "VID ref=\(reference) -> \(url.path)（本地内联可播候选）"
        case .externalLink(let url):
            return "LINK \(url.absoluteString) -> 交系统默认处理"
        case .placeholder(let reason, let reference):
            return "占位(\(reason)) ref=\(reference)"
        }
    }
}

// MARK: - 逐条报告

/// 解析过程里的**一条**报告条目（`FR-R-13-09` 判据 ④「逐条报告且不崩」的机械形式）。
/// 与 R-01 的 `ReportPackageIssue` / R-02 的 `ReportRenderIssue` 同口径：**不抛异常、不静默降级**。
public struct MediaIssue: Equatable, CustomStringConvertible {
    public enum Kind: Equatable {
        /// 白名单内扩展名，但文件不在盘上。
        case fileMissing(reference: String)
        /// 路径越界（含 `..` 或标准化后跑到包外）。
        case pathOutOfPackage(reference: String)
        /// 非「包内相对路径」形态（绝对路径 / `data:` base64 / 其它 scheme）。
        case referenceNotRelative(reference: String)
        /// 扩展名不在白名单（`avi` / `mov` / 无扩展名 …）。
        case formatNotWhitelisted(reference: String, fileExtension: String?)
    }

    /// 源文行号（1 起）；上游没给行号时为 `nil`（报告里就不印「第 N 行」）。
    public let line: Int?
    public let kind: Kind

    public init(line: Int?, kind: Kind) {
        self.line = line
        self.kind = kind
    }

    /// 出问题的引用串（各分支逐条给得出）。
    public var reference: String {
        switch kind {
        case .fileMissing(let reference),
             .pathOutOfPackage(let reference),
             .referenceNotRelative(let reference):
            return reference
        case .formatNotWhitelisted(let reference, _):
            return reference
        }
    }

    /// 人读的一行报告（回单 / 日志直接印）。
    public var description: String {
        let prefix = line.map { "第 \($0) 行：" } ?? ""
        switch kind {
        case .fileMissing(let reference):
            return "\(prefix)媒体文件缺失（\(reference)）—— 原位占位"
        case .pathOutOfPackage(let reference):
            return "\(prefix)媒体路径越界（\(reference)）—— 拒绝并原位占位"
        case .referenceNotRelative(let reference):
            return "\(prefix)媒体引用不是包内相对路径（\(reference)）—— 拒绝并原位占位"
        case .formatNotWhitelisted(let reference, let fileExtension):
            return "\(prefix)媒体格式不在白名单（\(reference) · \(fileExtension ?? "无扩展名")）—— 原位占位"
        }
    }
}

// MARK: - 解析产物

/// 一次解析的**完整产物**：去向 + 至多一条报告。**只读值类型**，没有任何写回入口。
public struct MediaResolveOutcome: Equatable {
    public let resolution: MediaResolution
    /// 占位 ⇒ **恰好一条**；内联 / 外链 ⇒ `nil`。**不许静默丢弃**。
    public let issue: MediaIssue?

    public init(resolution: MediaResolution, issue: MediaIssue?) {
        self.resolution = resolution
        self.issue = issue
    }
}

// MARK: - 入口

/// 媒体引用 ⇒ 解析结果（纯函数：只由 `(reference, 包目录)` 决定，不读时钟 / 环境 / 随机）。
public enum MediaResolve {

    /// 解析一条媒体引用。
    ///
    /// - Parameters:
    ///   - reference: `report.md` 里**原样写的引用串**（`IR-05` 不变量 3 规定是相对路径）。
    ///   - packageDirectory: **这一期的包目录**（`index.json` / `report.md` / `assets/` 那一层）；
    ///     相对路径一律**锚在这个目录上**解析。
    ///   - line: 源文行号（1 起，可选）—— 拿到就写进报告条目，便于对回 `report.md`。
    public static func resolve(
        reference: String,
        packageDirectory: URL,
        line: Int? = nil
    ) -> MediaResolveOutcome {
        let trimmed = reference.trimmingCharacters(in: .whitespaces)
        switch MediaReferenceClassifier.classify(trimmed) {
        case .externalLink(let url):
            // 合法形态：交系统默认处理，不报告、不崩。本层到此为止（不嵌 iframe / WebView）。
            return MediaResolveOutcome(resolution: .externalLink(url: url), issue: nil)

        case .notRelative:
            return placeholder(.referenceNotRelative,
                               reference: trimmed,
                               line: line,
                               kind: .referenceNotRelative(reference: trimmed))

        case .relativePath(let path):
            // ② 越界（任何一段是 `..`）⇒ 拒绝，不做「先拼再判断能不能绕回来」的花活。
            if path.split(separator: "/", omittingEmptySubsequences: false).contains("..") {
                return placeholder(.pathOutOfPackage,
                                   reference: trimmed,
                                   line: line,
                                   kind: .pathOutOfPackage(reference: trimmed))
            }

            // ③ 白名单（格式门在碰盘之前）—— 白名单外到此为止，不碰盘。
            let fileExtension = MediaWhitelist.fileExtension(of: path)
            guard let fileExtension, let kind = MediaWhitelist.kind(forFileExtension: fileExtension) else {
                return placeholder(.formatNotWhitelisted(fileExtension: fileExtension),
                                   reference: trimmed,
                                   line: line,
                                   kind: .formatNotWhitelisted(reference: trimmed, fileExtension: fileExtension))
            }

            // ④ 锚在包目录解析 + **包内复核**（词法标准化后的双保险）。
            let base = packageDirectory.standardizedFileURL
            let resolved = URL(fileURLWithPath: path, isDirectory: false, relativeTo: base).standardizedFileURL
            let basePath = base.path.hasSuffix("/") ? String(base.path.dropLast()) : base.path
            guard resolved.path == basePath || resolved.path.hasPrefix(basePath + "/") else {
                return placeholder(.pathOutOfPackage,
                                   reference: trimmed,
                                   line: line,
                                   kind: .pathOutOfPackage(reference: trimmed))
            }

            // ⑤ 唯一碰盘的一步。
            guard FileManager.default.fileExists(atPath: resolved.path) else {
                return placeholder(.fileMissing,
                                   reference: trimmed,
                                   line: line,
                                   kind: .fileMissing(reference: trimmed))
            }

            switch kind {
            case .image:
                return MediaResolveOutcome(resolution: .inlineImage(reference: trimmed, url: resolved), issue: nil)
            case .video:
                return MediaResolveOutcome(resolution: .inlineVideo(reference: trimmed, url: resolved), issue: nil)
            }
        }
    }

    // MARK: - 内部

    private static func placeholder(
        _ reason: MediaPlaceholderReason,
        reference: String,
        line: Int?,
        kind: MediaIssue.Kind
    ) -> MediaResolveOutcome {
        MediaResolveOutcome(
            resolution: .placeholder(reason: reason, reference: reference),
            issue: MediaIssue(line: line, kind: kind)
        )
    }
}
