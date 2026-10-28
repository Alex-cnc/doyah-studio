import Foundation

/// 网页文件在编辑器内的「预览」（`FR-STD-WS-WEB-003`）—— **计划层**。
///
/// 为什么单独一层：这条需求里唯一容易做歪的地方是「给页面读多少」。
/// 界面那一侧只是把 `WKWebView` 贴上去，真正决定**渲染哪一份内容**（盘上文件 / 未保存的缓冲）
/// 与**允许它读哪个目录**的是这里 —— 纯函数，能在无界面环境里跑判据。
///
/// 三条口径：
///   ① **读权限 = 这份文件所在的目录**（同目录的 css / 图片 / 脚本要一起读，收得只剩一个文件
///      页面就渲染成裸文档）；**目录本身是磁盘根 `/` 时不给计划** —— 那等于把整机交给页面；
///   ② **有未保存改动就渲染缓冲**（看到的就是正在编辑的那份），没有就走盘上文件；
///   ③ **越界的资源与链接一律拒绝并给可读原因**：远程地址不在预览里加载（要它就去浏览器页签，
///      与 `FR-STD-WS-WEB-003` ⑦ 是同一条路），`file:` 落在读权限根之外同样拒绝。
public enum HTMLPreview {

    /// 一次预览要渲染的东西。
    public enum Source: Equatable, Sendable {
        /// 磁盘上的那份文件（没有未保存改动时用）。
        case file(URL)
        /// 当前编辑缓冲（有未保存改动时用）—— 相对路径仍按**文件所在目录**解析。
        case buffer(text: String, baseDirectory: URL)
    }

    /// 一次渲染的完整计划。
    public struct Plan: Equatable, Sendable {
        public let source: Source
        /// 渲染进程的读权限根（= 该文件所在目录）。
        public let readAccessRoot: URL

        public init(source: Source, readAccessRoot: URL) {
            self.source = source
            self.readAccessRoot = readAccessRoot
        }
    }

    /// 一次预览请求的裁决。
    public enum Outcome: Equatable, Sendable {
        case render(Plan)
        /// 打不开，`reason` 可直接显示给用户。
        case block(reason: String)
    }

    /// 页面里一次资源 / 链接请求的裁决。
    public enum ResourceDecision: Equatable, Sendable {
        case allow
        case block(reason: String)
        /// 远程地址：预览不加载，但**给一条能走的路**（在浏览器页签里打开）。
        case handOffToBrowser(reason: String)

        /// 是否放行加载。
        public var isAllowed: Bool {
            if case .allow = self { return true }
            return false
        }

        /// 给用户看的原因（放行时为 `nil`）。
        public var reason: String? {
            switch self {
            case .allow: return nil
            case .block(let reason), .handOffToBrowser(let reason): return reason
            }
        }
    }

    /// 文件事实 —— **注入**而不是自己去问磁盘：判据要能在无界面、无 IO 的环境里跑。
    public struct FileFacts: Equatable, Sendable {
        public let exists: Bool
        public let isDirectory: Bool

        public init(exists: Bool, isDirectory: Bool) {
            self.exists = exists
            self.isDirectory = isDirectory
        }
    }

    // MARK: 计划

    /// 算出这次预览该怎么渲染。
    ///
    /// - Parameters:
    ///   - path: 页签对应的磁盘路径（`nil` / 空白 = 还没落盘）。
    ///   - isDirty: 编辑器里是否有未保存改动。
    ///   - buffer: 当前编辑缓冲（`isDirty` 为真时用它渲染）。
    ///   - facts: 磁盘事实（存在 / 是目录）。
    public static func plan(
        path: String?,
        isDirty: Bool,
        buffer: String,
        facts: FileFacts,
        language: AppLanguage = .simplifiedChinese
    ) -> Outcome {
        guard let path, !path.trimmingCharacters(in: .whitespaces).isEmpty else {
            return .block(reason: LocalizedStrings.text(.htmlPreviewNeedsSavedFile, language: language))
        }
        guard facts.exists else {
            return .block(reason: LocalizedStrings.text(.htmlPreviewFileMissing, language: language))
        }
        guard !facts.isDirectory else {
            return .block(reason: LocalizedStrings.text(.htmlPreviewPathIsDirectory, language: language))
        }

        let fileURL = URL(fileURLWithPath: path)
        let parent = fileURL.deletingLastPathComponent()
        // 目录 URL 一律带「这是目录」这一档（末尾斜杠）：相对地址要按目录解析，
        // 而 `URL(string:relativeTo:)` 会把不带斜杠的基址当**文件**——`../x` 会多退一级（实测）。
        let root = URL(fileURLWithPath: parent.path, isDirectory: true)
        // 磁盘根当读权限根 = 把整台机器交给页面里的任何一段脚本（`FR-STD-WS-WEB-003` ④）。
        guard root.path != "/" else {
            return .block(reason: LocalizedStrings.text(.htmlPreviewRootDirectoryRefused, language: language))
        }

        let source: Source = isDirty
            ? .buffer(text: buffer, baseDirectory: root)
            : .file(fileURL)
        return .render(Plan(source: source, readAccessRoot: root))
    }

    // MARK: 页面里的资源与链接

    /// 裁决一次资源 / 链接请求（`baseDirectory` = 预览的读权限根）。
    ///
    /// 三个档位分开说，因为「怎么处理」不同：放行 · 拒绝（说了也白说） · 交给浏览器页签（有出路）。
    public static func decide(
        resource: URL,
        baseDirectory: URL,
        language: AppLanguage = .simplifiedChinese
    ) -> ResourceDecision {
        let scheme = (resource.scheme ?? "").lowercased()

        switch scheme {
        case "":
            // 相对地址不该走到这里（下面 `decide(link:)` 会先解析）；当成不可解析拒绝。
            return .block(reason: LocalizedStrings.text(.htmlPreviewEmptyAddress, language: language))
        case "about":
            // 本地空白页，没有出网。
            return .allow
        case "data":
            // 内联数据：同样没有出网（图片 / 小型样式常这么写）。
            return .allow
        case "file":
            return fileDecision(resource, baseDirectory: baseDirectory, language: language)
        case "http", "https":
            return .handOffToBrowser(
                reason: LocalizedStrings.format(
                    .htmlPreviewRemoteBlocked,
                    language: language,
                    resource.absoluteString
                )
            )
        default:
            return .block(
                reason: LocalizedStrings.format(.htmlPreviewSchemeBlocked, language: language, scheme + ":")
            )
        }
    }

    /// 页面上拿到的一串地址（`href` / `src`）——相对地址按预览根解析。
    public static func decide(
        link: String,
        baseDirectory: URL,
        language: AppLanguage = .simplifiedChinese
    ) -> ResourceDecision {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .block(reason: LocalizedStrings.text(.htmlPreviewEmptyAddress, language: language))
        }
        // 片段（`#anchor`）与查询留在同一份文档里：没有新请求，直接放行。
        if trimmed.hasPrefix("#") { return .allow }

        // 基址必须是**目录**（末尾斜杠）：否则 `URL(string:relativeTo:)` 会把它当文件，
        // `../x` 多退一级（实测：`/ws/../x` 被算成 `/x` 的上一级）。
        let base = baseDirectory.hasDirectoryPath
            ? baseDirectory
            : URL(fileURLWithPath: baseDirectory.path, isDirectory: true)
        guard let url = URL(string: trimmed, relativeTo: base) else {
            return .block(reason: LocalizedStrings.text(.htmlPreviewEmptyAddress, language: language))
        }
        // `URL(string:relativeTo:)` 对 `//host/path` 这种协议相对地址会给出 http(s) —— 交给上面那档。
        return decide(resource: url.absoluteURL, baseDirectory: baseDirectory, language: language)
    }

    /// `file:` 的那一档：**落在读权限根里才放行**。
    ///
    /// 判法是路径分量比较（不是字符串前缀）：`/ws` 与 `/ws2` 用 `hasPrefix` 会误判成同一个根。
    public static func fileDecision(
        _ url: URL,
        baseDirectory: URL,
        language: AppLanguage = .simplifiedChinese
    ) -> ResourceDecision {
        guard url.isFileURL, !url.path.isEmpty else {
            return .block(reason: LocalizedStrings.text(.htmlPreviewEmptyAddress, language: language))
        }
        if isWithinRoot(url, root: baseDirectory) {
            return .allow
        }
        return .block(
            reason: LocalizedStrings.format(.htmlPreviewResourceOutsideRoot, language: language, url.path)
        )
    }

    /// `url`（解析掉 `..` 之后）是否落在 `root` 里（含 root 本身）。
    public static func isWithinRoot(_ url: URL, root: URL) -> Bool {
        let rootComponents = root.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let targetComponents = url.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        guard targetComponents.count >= rootComponents.count else { return false }
        return Array(targetComponents.prefix(rootComponents.count)) == rootComponents
    }
}
