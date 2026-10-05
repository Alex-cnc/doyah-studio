import Foundation

/// 工作区里的一行（条目 + 缩进层级）—— 扁平化之后交给界面渲染。
///
/// 放在 Core 而不是 App：它是**纯数据**，而且树与搜索两边都要用；
/// 放在 App 会让搜索逻辑没法单测。
public struct WorkspaceRow: Equatable, Sendable, Identifiable {
    public let entry: WorkspaceEntry
    public let depth: Int

    public var id: String { entry.relativePath }

    public init(entry: WorkspaceEntry, depth: Int) {
        self.entry = entry
        self.depth = depth
    }
}

/// 工作区内**按文件名**搜索（FR-EDIT-32）。
///
/// 刻意做成"有界的递归"而不是全文检索：
///   · 全文检索要扫内容、要处理二进制与大文件、要给进度与取消 —— 那是另一个功能；
///   · 而"我记得文件名里有个 agent，帮我找出来"是**打开工作区后最常做的事**。
///
/// 有界体现在三处（都写死成默认参数，可在单测里改小）：
///   1. 忽略名单（复用 `WorkspaceTree.searchIgnored` —— 检索**仍然**跳过构建产物 / 依赖目录，
///      与工作区树**看不看得见**是两件事）；
///   2. **深度上限** —— 防止有人把工作区选到 `/` 或家目录后界面卡死；
///   3. **结果上限** —— 命中过多时停下来并如实告知"已达上限"，而不是悄悄截断。
///
/// 另外：**不跟随符号链接**（跟随会跑出工作区，甚至成环）。
public enum WorkspaceSearch {

    public static let defaultResultLimit = 200
    public static let defaultMaxDepth = 8

    /// 搜索结果。
    public struct Result: Equatable, Sendable {
        public var entries: [WorkspaceEntry]
        /// 是否因为命中上限而提前停止（界面应如实提示）。
        public var isTruncated: Bool
        public init(entries: [WorkspaceEntry], isTruncated: Bool) {
            self.entries = entries
            self.isTruncated = isTruncated
        }
    }

    /// 在工作区内按文件名递归搜索。
    ///
    /// 匹配规则：**大小写与变音符号不敏感的子串匹配** —— 走引擎里那个**唯一谓词**
    /// （`matches(_:normalizedQuery:)`，与内容搜索同源），免得用户记不住大小写就搜不到。
    public static func findFileNames(
        in root: URL,
        query: String,
        limit: Int = defaultResultLimit,
        maxDepth: Int = defaultMaxDepth,
        ignored: Set<String> = WorkspaceTree.searchIgnored,
        fileManager: FileManager = .default
    ) -> Result {
        let needle = normalize(query: query)
        guard !needle.isEmpty, limit > 0, maxDepth >= 0 else {
            return Result(entries: [], isTruncated: false)
        }

        var found: [WorkspaceEntry] = []
        var truncated = false
        var queue: [(url: URL, depth: Int)] = [(root, 0)]

        while !queue.isEmpty {
            let (directory, depth) = queue.removeFirst()
            guard depth < maxDepth else { continue }
            guard let children = try? WorkspaceTree.children(
                of: directory, relativeTo: root, showHidden: false, ignored: ignored, fileManager: fileManager
            ) else { continue }

            for entry in children {
                switch entry.kind {
                case .symlink:
                    continue                      // 不跟随、也不报告：它可能指向工作区外
                case .directory:
                    queue.append((directory.appendingPathComponent(entry.name), depth + 1))
                case .file:
                    if matches(entry.name, normalizedQuery: needle) {
                        if found.count >= limit {
                            truncated = true
                            return Result(entries: found, isTruncated: true)
                        }
                        found.append(entry)
                    }
                }
            }
        }

        return Result(
            entries: found.sorted { $0.relativePath.localizedCaseInsensitiveCompare($1.relativePath) == .orderedAscending },
            isTruncated: truncated
        )
    }

    // MARK: - 内容检索（FR-EDIT-44 / FR-EDIT-42 共用的一套引擎）

    /// 匹配谓词 —— **唯一出处**。
    ///
    /// 两条纪律：
    ///   1. 文件名搜索与内容搜索**必须走同一个谓词**（大小写与变音符号不敏感的子串）；
    ///      界面侧（`App/`）不许另写一套 `contains` —— 否则「同一个词在文件名里搜得到、
    ///      在内容里搜不到」这类分歧迟早出现，而且是静默的。
    ///   2. 归一化只此一处（`precomposedStringWithCanonicalMapping`），免得两处各归一一次。
    static func matches(_ text: String, normalizedQuery query: String) -> Bool {
        guard !query.isEmpty else { return false }
        return text.precomposedStringWithCanonicalMapping
            .range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    /// 把查询词归一成比较用的形状（与 `matches` 同源）。
    public static func normalize(query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
            .lowercased()
    }

    // MARK: - 内容检索的产物（FR-EDIT-44 标头搜索框 / FR-EDIT-42 跨文件搜索共用）

    /// 一条内容命中 = **某个文件的某一行**。
    public struct ContentHit: Equatable, Sendable {
        public let entry: WorkspaceEntry
        /// 行号，**1 起**（与编辑器行号列同口径）。
        public let line: Int
        /// 该行原文裁剪后的摘要 —— **不改写原文**（不替换、不美化）。
        public let snippet: String
        public init(entry: WorkspaceEntry, line: Int, snippet: String) {
            self.entry = entry
            self.line = line
            self.snippet = snippet
        }
    }

    /// 一个文件里的命中组（界面按文件分组渲染）。
    public struct ContentGroup: Equatable, Sendable, Identifiable {
        public let entry: WorkspaceEntry
        public let hits: [ContentHit]
        public var id: String { entry.relativePath }
        public init(entry: WorkspaceEntry, hits: [ContentHit]) {
            self.entry = entry
            self.hits = hits
        }
    }

    /// **跳过报告** —— 跳过 ≠ 通过：二进制 / 超大 / 读不了的文件各记一笔，界面要看得见。
    public struct SkipReport: Equatable, Sendable {
        public var binary: Int
        public var tooLarge: Int
        public var unreadable: Int
        public var total: Int { binary + tooLarge + unreadable }
        public var isEmpty: Bool { total == 0 }
        public init(binary: Int = 0, tooLarge: Int = 0, unreadable: Int = 0) {
            self.binary = binary
            self.tooLarge = tooLarge
            self.unreadable = unreadable
        }
    }

    /// 内容检索结果。
    public struct ContentResult: Equatable, Sendable {
        public var groups: [ContentGroup]
        public var skips: SkipReport
        /// 真正读了内容的文件数（含读了但没命中的）。
        public var scannedFiles: Int
        /// 命中总数到达上限而提前停止（界面应如实提示）。
        public var isTruncated: Bool
        public var hitCount: Int { groups.reduce(0) { $0 + $1.hits.count } }
        public init(groups: [ContentGroup] = [], skips: SkipReport = SkipReport(),
                    scannedFiles: Int = 0, isTruncated: Bool = false) {
            self.groups = groups
            self.skips = skips
            self.scannedFiles = scannedFiles
            self.isTruncated = isTruncated
        }
        public static let empty = ContentResult()
    }

    // MARK: - 内容检索

    /// 单文件大小上限（超过就**跳过并报数**，不假装搜过）。
    public static let defaultMaxFileSize = 2 * 1024 * 1024
    /// 单个文件最多记多少条命中（免得一个文件把整份结果吃光）。
    public static let defaultPerFileLimit = 20
    /// 摘要长度上限（超出截断加省略号 —— **原文一个字不改**）。
    public static let defaultSnippetLimit = 200
    static let binaryProbeBytes = 8192

    /// 按**逻辑行**切分：每行在原文里占的 UTF-16 范围（**不含**行终止符）。
    ///
    /// **口径不在这一层**：行终止符有 `\n` / `\r\n` / `\r` / `U+2028` / `U+2029` / `U+0085`
    /// 好几种写法，而"第几行"的权威定义在 `Core/CodeLines`（编辑器行号列读的就是它）。
    /// 这里以前自己 `components(separatedBy: "\n")`，于是**命中行号与编辑器行号是两套数法** ——
    /// `U+2028` 之类终止符上两者会差，而 `FR-EDIT-44` 的「回车跳到命中行」正要把行号换回位置
    /// ⇒ 会**静默跳到相邻的行**。故改为复用 `CodeLines.contentRanges`（同一份实现）。
    static func lineRanges(in text: String) -> [NSRange] {
        CodeLines.contentRanges(in: text)
    }

    /// 解码成文本；**解不出来 = 二进制**（前 8 KiB 含 NUL 也算）。
    static func decodeText(_ data: Data) -> String? {
        if data.prefix(binaryProbeBytes).contains(0) { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// 上下文摘要：去掉首尾空白，超长截断加 `…`。
    static func snippet(_ line: String, limit: Int = defaultSnippetLimit) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit)) + "…"
    }

    /// 在工作区内**按内容**检索（`FR-EDIT-44` 标头搜索框 / `FR-EDIT-42` 跨文件搜索共用）。
    ///
    /// 与 `findFileNames` 同骨架、**同一个匹配谓词**（有界递归 / 不跟随符号链接 /
    /// 尊重忽略名单 / 如实报数），差别只在「读内容并按行命中」。
    ///
    /// 跳过三条路各自计数，**跳过 ≠ 通过**：二进制（解不出 UTF-8 或含 NUL）/
    /// 超过 `maxFileSize` / 读不了。命中按文件分组，组内按行号升序。
    public static func findContents(
        in root: URL,
        query: String,
        limit: Int = defaultResultLimit,
        perFileLimit: Int = defaultPerFileLimit,
        maxDepth: Int = defaultMaxDepth,
        maxFileSize: Int = defaultMaxFileSize,
        snippetLimit: Int = defaultSnippetLimit,
        ignored: Set<String> = WorkspaceTree.searchIgnored,
        fileManager: FileManager = .default
    ) -> ContentResult {
        let needle = normalize(query: query)
        guard !needle.isEmpty, limit > 0, perFileLimit > 0, maxDepth >= 0, maxFileSize > 0 else {
            return .empty
        }
        var groups: [ContentGroup] = []
        var skips = SkipReport()
        var scanned = 0
        var total = 0
        var truncated = false
        var queue: [(url: URL, depth: Int)] = [(root, 0)]

        while !queue.isEmpty && !truncated {
            let (directory, depth) = queue.removeFirst()
            guard depth < maxDepth else { continue }
            guard let children = try? WorkspaceTree.children(
                of: directory, relativeTo: root, showHidden: false, ignored: ignored, fileManager: fileManager
            ) else { continue }

            for entry in children {
                switch entry.kind {
                case .symlink:
                    continue                      // 与文件名搜索同：不跟随、也不报告
                case .directory:
                    queue.append((directory.appendingPathComponent(entry.name), depth + 1))
                case .file:
                    let url = directory.appendingPathComponent(entry.name)
                    let attributes = try? fileManager.attributesOfItem(atPath: url.path)
                    let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
                    if size > maxFileSize { skips.tooLarge += 1; continue }
                    guard let data = try? Data(contentsOf: url) else { skips.unreadable += 1; continue }
                    guard let text = decodeText(data) else { skips.binary += 1; continue }
                    scanned += 1

                    var fileHits: [ContentHit] = []
                    let ns = text as NSString
                    for (index, range) in lineRanges(in: text).enumerated() {
                        let raw = ns.substring(with: range)
                        guard matches(raw, normalizedQuery: needle) else { continue }
                        if total >= limit { truncated = true; break }
                        fileHits.append(ContentHit(
                            entry: entry, line: index + 1, snippet: snippet(raw, limit: snippetLimit)
                        ))
                        total += 1
                        if fileHits.count >= perFileLimit { break }
                    }
                    if !fileHits.isEmpty { groups.append(ContentGroup(entry: entry, hits: fileHits)) }
                    if truncated { break }
                }
            }
        }

        return ContentResult(
            groups: groups.sorted {
                $0.entry.relativePath.localizedCaseInsensitiveCompare($1.entry.relativePath) == .orderedAscending
            },
            skips: skips,
            scannedFiles: scanned,
            isTruncated: truncated
        )
    }

    // MARK: - 标头搜索框的结果（FR-EDIT-44）

    /// 标头搜索框（`FR-EDIT-44`）的**一次结果**：文件名命中 + 内容命中。
    ///
    /// 为什么要有这一层（而不是让视图连着调两次引擎）：
    ///   1. **两组的成员与顺序是口径**（文件名在前；内容按文件分组、组内行号升序）——
    ///      写在视图里就没法单测，而「同一份目录两次检索结果稳定且有序」正是 `FR-EDIT-44` 的判据；
    ///   2. 键盘行走的**扁平顺序**与渲染顺序必须是**同一个**（两份顺序迟早不一致，
    ///      症状 = ↑↓ 选中的行与高亮的行不是同一条）；
    ///   3. 跳过与截断的**如实报数**要一路传到界面（跳过 ≠ 通过）。
    public struct HeaderSearchResults: Equatable, Sendable {

        /// 一行结果 = 一个文件名命中，或一条内容命中（某文件的某一行）。
        public enum Row: Equatable, Sendable {
            case file(WorkspaceEntry)
            case content(ContentHit)

            /// 这一行指向的文件（回车要打开它）。
            public var entry: WorkspaceEntry {
                switch self {
                case .file(let entry): return entry
                case .content(let hit): return hit.entry
                }
            }

            /// 内容命中的行号；文件名命中没有行（打开即可，不必跳）。
            public var line: Int? {
                switch self {
                case .file: return nil
                case .content(let hit): return hit.line
                }
            }

            /// 稳定 id（同一份目录、同一个词 ⇒ 同一个 id）—— 界面按它做差异渲染。
            public var id: String {
                switch self {
                case .file(let entry): return "file\u{1}\(entry.relativePath)"
                case .content(let hit): return "content\u{1}\(hit.entry.relativePath)\u{1}\(hit.line)"
                }
            }
        }

        /// 归一化之后的查询词（空 = 没在搜）。
        public let query: String
        public let files: [WorkspaceEntry]
        public let filesTruncated: Bool
        public let content: ContentResult
        /// 键盘行走 / 渲染共用的**唯一**顺序：文件名命中在前，随后是内容命中（按文件分组、组内行号升序）。
        public let rows: [Row]

        public var isEmpty: Bool { rows.isEmpty }
        /// 内容命中条数。
        public var contentHitCount: Int { content.hitCount }
        /// 跳过计数（二进制 / 超限 / 读不出）—— 界面必须看得见。
        public var skips: SkipReport { content.skips }
        /// 任一上限触发（界面应如实提示）。
        public var isTruncated: Bool { filesTruncated || content.isTruncated }

        public static let empty = HeaderSearchResults(
            query: "", files: [], filesTruncated: false, content: .empty
        )

        public init(query: String, files: [WorkspaceEntry], filesTruncated: Bool, content: ContentResult) {
            self.query = query
            self.files = files
            self.filesTruncated = filesTruncated
            self.content = content
            var rows: [Row] = files.map { Row.file($0) }
            for group in content.groups {
                for hit in group.hits { rows.append(.content(hit)) }
            }
            self.rows = rows
        }

        /// 选中下标夹到合法范围（↑↓ 到边界原地不动，不许越界、也不许"跳回 0"）。
        /// 空结果返回 0 —— 界面拿它当下标用，不必再判一次。
        public func clamped(_ index: Int) -> Int {
            guard !rows.isEmpty else { return 0 }
            return min(max(0, index), rows.count - 1)
        }

        /// 按 ↑/↓ 走一步（`delta` = ±1），边界上原地不动。
        public func moved(from index: Int, by delta: Int) -> Int {
            clamped(clamped(index) + delta)
        }
    }

    /// 标头搜索框的一次检索：**文件名命中 + 内容命中**一次算完（`FR-EDIT-44`）。
    ///
    /// 两个半边走的是**同一套引擎**（同一个匹配谓词、同一份忽略名单、同样的有界遍历）——
    /// 「两处各写一套匹配」是这个功能最容易出的分歧，`FR-EDIT-44` 的条文明确不许。
    public static func headerResults(
        in root: URL,
        query: String,
        fileLimit: Int = defaultResultLimit,
        limit: Int = defaultResultLimit,
        perFileLimit: Int = defaultPerFileLimit,
        maxDepth: Int = defaultMaxDepth,
        maxFileSize: Int = defaultMaxFileSize,
        snippetLimit: Int = defaultSnippetLimit,
        ignored: Set<String> = WorkspaceTree.searchIgnored,
        fileManager: FileManager = .default
    ) -> HeaderSearchResults {
        let needle = normalize(query: query)
        guard !needle.isEmpty else { return .empty }
        let names = findFileNames(
            in: root, query: query, limit: fileLimit, maxDepth: maxDepth,
            ignored: ignored, fileManager: fileManager
        )
        let contents = findContents(
            in: root, query: query, limit: limit, perFileLimit: perFileLimit, maxDepth: maxDepth,
            maxFileSize: maxFileSize, snippetLimit: snippetLimit, ignored: ignored, fileManager: fileManager
        )
        return HeaderSearchResults(
            query: needle, files: names.entries, filesTruncated: names.isTruncated, content: contents
        )
    }
}
