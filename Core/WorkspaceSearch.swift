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

    /// 匹配**选项** —— **唯一出处**（`matches` 与替换定位读的是同一张表）。
    ///
    /// 大小写 + 变音符号不敏感：用户记不住大小写，也不该因为 `café` / `cafe` 的写法差别搜不到。
    static let matchOptions: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    /// 匹配谓词 —— **唯一出处**。
    ///
    /// 两条纪律：
    ///   1. 文件名搜索、内容搜索与**替换定位**必须走同一个谓词（大小写与变音符号不敏感的子串）；
    ///      界面侧（`App/`）不许另写一套 `contains` —— 否则「同一个词搜得到、替换时却定位不到」
    ///      这类分歧迟早出现，而且是静默的。
    ///   2. 归一化只此一处（`normalize(query:)`）、匹配选项只此一处（`matchOptions`）。
    static func matches(_ text: String, normalizedQuery query: String) -> Bool {
        !matchRanges(in: text, normalizedQuery: query).isEmpty
    }

    /// 在一段文本里找出查询词的**所有非重叠命中区间**（原文坐标，UTF-16 偏移）。
    ///
    /// `matches` 就是「这里非空」；替换定位就是拿这些区间逐段改 —— **同一套规则算两件不同的事**，
    /// 不许另写一套。区间直接在**原文**上算（不先做 `precomposedStringWithCanonicalMapping`）：
    /// 分解形式的字符（`e` + 组合重音）归一后长度会变，预归一得到的区间会落**错的字符上**；
    /// 而 `.diacriticInsensitive` 本身就能跨写法匹配，本不需要预归一。
    static func matchRanges(in text: String, normalizedQuery query: String) -> [NSRange] {
        guard !query.isEmpty else { return [] }
        let hay = text as NSString
        let length = hay.length
        guard length > 0 else { return [] }
        var out: [NSRange] = []
        var from = 0
        while from <= length {
            let found = hay.range(
                of: query, options: matchOptions, range: NSRange(location: from, length: length - from)
            )
            guard found.location != NSNotFound, found.length > 0 else { break }
            out.append(found)
            from = found.location + found.length      // 相邻命中**不重叠**（与高亮同一口径）
        }
        return out
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

    /// 读一个文件成文本；**读不成 ⇒ 记一笔跳过并返回 `nil`**（跳过 ≠ 通过）。
    ///
    /// 三条跳过路径（二进制 / 超大 / 读不出）与它们的计数**只此一处** ——
    /// 内容检索与替换计划共用：两处各写一套 = 「搜得到、替换时却静默跳过」。
    static func readTextFile(
        _ entry: WorkspaceEntry,
        url: URL,
        maxFileSize: Int,
        skips: inout SkipReport,
        fileManager: FileManager
    ) -> String? {
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        if size > maxFileSize { skips.tooLarge += 1; return nil }
        guard let data = try? Data(contentsOf: url) else { skips.unreadable += 1; return nil }
        guard let text = decodeText(data) else { skips.binary += 1; return nil }
        return text
    }

    /// 上下文摘要：去掉首尾空白，超长截断加 `…`。
    static func snippet(_ line: String, limit: Int = defaultSnippetLimit) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit)) + "…"
    }

    /// 有界遍历工作区里的**文本文件**，逐个交给 `body`；返回真正读了内容的文件数。
    ///
    /// 这一层是**内容检索与替换计划共用的唯一骨架**：忽略名单 / 深度上限 / 不跟随符号链接
    /// 都在这里，跳过按类计数也在这里（`readTextFile`）。`body` 返回 `false` 表示「够了，停」
    /// （内容检索命中总数到上限时用）。两处各写一套遍历 = 忽略名单 / 深度 / 跳过计数迟早分叉。
    @discardableResult
    static func scanTextFiles(
        in root: URL,
        maxDepth: Int,
        maxFileSize: Int,
        ignored: Set<String>,
        fileManager: FileManager,
        skips: inout SkipReport,
        body: (_ entry: WorkspaceEntry, _ text: String) -> Bool
    ) -> Int {
        var scanned = 0
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
                    continue                      // 与文件名搜索同：不跟随、也不报告
                case .directory:
                    queue.append((directory.appendingPathComponent(entry.name), depth + 1))
                case .file:
                    let url = directory.appendingPathComponent(entry.name)
                    guard let text = readTextFile(
                        entry, url: url, maxFileSize: maxFileSize, skips: &skips, fileManager: fileManager
                    ) else { continue }
                    scanned += 1
                    if !body(entry, text) { return scanned }
                }
            }
        }
        return scanned
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
        var total = 0
        var truncated = false

        let scanned = scanTextFiles(
            in: root, maxDepth: maxDepth, maxFileSize: maxFileSize,
            ignored: ignored, fileManager: fileManager, skips: &skips
        ) { entry, text in
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
            return !truncated
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

    // MARK: - 替换计划（FR-EDIT-42 的另一半）

    /// 一行的替换预览：**改之前 / 改之后**（先看清，再落盘）。
    public struct LineChange: Equatable, Sendable {
        /// 行号（1 起，与编辑器行号列 / 内容命中**同一口径**）。
        public let line: Int
        /// 改之前那一行（原文，**不含**行终止符）。
        public let before: String
        /// 改之后那一行。
        public let after: String
        /// 这一行改了几处。
        public let count: Int
        public init(line: Int, before: String, after: String, count: Int) {
            self.line = line
            self.before = before
            self.after = after
            self.count = count
        }
    }

    /// 一份文件的替换计划（改哪几行 + 替换后的**完整内容**）。
    public struct FileChange: Equatable, Sendable, Identifiable {
        public let entry: WorkspaceEntry
        public let changes: [LineChange]
        /// 这份文件一共改了几处。
        public let count: Int
        /// 替换后的**完整内容**（落盘就写它 —— 与预览出自同一次计算，不会不一致）。
        public let replaced: String
        public var id: String { entry.relativePath }
        public init(entry: WorkspaceEntry, changes: [LineChange], count: Int, replaced: String) {
            self.entry = entry
            self.changes = changes
            self.count = count
            self.replaced = replaced
        }
    }

    /// 一份**替换计划**：先出这个（差异预览），用户确认后再 `apply` 落盘（`FR-EDIT-42`）。
    ///
    /// 与内容检索**同一套规则**：忽略名单 / 深度 / 二进制与超大判定 / 匹配谓词全部同源 ——
    /// 「搜得到、替换时却看不见」是这一族最容易出的分歧。
    public struct ReplacePlan: Equatable, Sendable {
        /// 用户输入的查询词（原样，供界面显示）。
        public let query: String
        /// 用户输入的替换词（原样；空串 = 删除命中处）。
        public let replacement: String
        public let files: [FileChange]
        public let skips: SkipReport
        /// 真正读了内容的文件数（含读了但没命中的）。
        public let scannedFiles: Int

        public var fileCount: Int { files.count }
        public var changeCount: Int { files.reduce(0) { $0 + $1.count } }
        public var isEmpty: Bool { files.isEmpty }

        public init(query: String = "", replacement: String = "", files: [FileChange] = [],
                    skips: SkipReport = SkipReport(), scannedFiles: Int = 0) {
            self.query = query
            self.replacement = replacement
            self.files = files
            self.skips = skips
            self.scannedFiles = scannedFiles
        }

        public static let empty = ReplacePlan()
    }

    /// 落盘回执 = **撤销凭证**：每个被改文件**改之前**的原字节（撤销 = 原样写回）。
    public struct ReplaceUndo: Sendable {
        public let originals: [String: Data]
        public var fileCount: Int { originals.count }
        public var isEmpty: Bool { originals.isEmpty }
        public init(originals: [String: Data] = [:]) {
            self.originals = originals
        }
    }

    /// 把一行里的命中**全部替换**掉 —— 只改命中的那些字符，其余一个字节不动。
    /// 返回（改后的行, 改了几处）。
    public static func applyToLine(
        _ line: String, normalizedQuery query: String, replacement: String
    ) -> (text: String, count: Int) {
        let ranges = matchRanges(in: line, normalizedQuery: query)
        guard !ranges.isEmpty else { return (line, 0) }
        let mutable = NSMutableString(string: line)
        for range in ranges.reversed() {       // 从后往前改，避免下标位移
            mutable.replaceCharacters(in: range, with: replacement)
        }
        return (mutable as String, ranges.count)
    }

    /// 替换整份文本 —— **逐行改完再按各行的行终止符原样拼回去**（`CRLF` 不会变成 `LF`）。
    ///
    /// 行切法与行号口径只经 `CodeLines`（与编辑器 / 内容检索同源），绝不 `components(separatedBy:)`。
    public static func applyToText(_ text: String, normalizedQuery query: String, replacement: String) -> String {
        let ns = text as NSString
        let starts = CodeLines.lineStarts(in: text)
        let contents = CodeLines.contentRanges(in: text)
        var out = String()
        out.reserveCapacity(ns.length)
        for (index, content) in contents.enumerated() {
            let raw = ns.substring(with: content)
            out += applyToLine(raw, normalizedQuery: query, replacement: replacement).text
            // 行终止符**原样保留**（行尾保真：不把 CRLF 改成 LF、也不增减空行）
            let contentEnd = content.location + content.length
            let lineEnd = index + 1 < starts.count ? starts[index + 1] : ns.length
            if lineEnd > contentEnd {
                out += ns.substring(with: NSRange(location: contentEnd, length: lineEnd - contentEnd))
            }
        }
        return out
    }

    /// 给一份文件算出替换计划（`nil` = 这个文件没有命中）。
    static func fileChange(
        for entry: WorkspaceEntry, text: String, normalizedQuery query: String, replacement: String
    ) -> FileChange? {
        let ns = text as NSString
        var changes: [LineChange] = []
        var count = 0
        for (index, content) in CodeLines.contentRanges(in: text).enumerated() {
            let raw = ns.substring(with: content)
            let applied = applyToLine(raw, normalizedQuery: query, replacement: replacement)
            guard applied.count > 0 else { continue }
            changes.append(LineChange(line: index + 1, before: raw, after: applied.text, count: applied.count))
            count += applied.count
        }
        guard count > 0 else { return nil }
        return FileChange(
            entry: entry, changes: changes, count: count,
            replaced: applyToText(text, normalizedQuery: query, replacement: replacement)
        )
    }

    /// 在工作区内算一份**替换计划**（`FR-EDIT-42`：先出差异预览，再落盘）。
    ///
    /// 空查询**一律拒绝**（它会把每一行的每一处都换掉 —— 那是灾难的入口）；替换词与查询词
    /// **完全相同**也拒绝（换了等于没换）。两条拒绝都返回空计划，界面据此不显示「应用」。
    public static func replacePlan(
        in root: URL,
        query: String,
        replacement: String,
        maxDepth: Int = defaultMaxDepth,
        maxFileSize: Int = defaultMaxFileSize,
        ignored: Set<String> = WorkspaceTree.searchIgnored,
        fileManager: FileManager = .default
    ) -> ReplacePlan {
        let needle = normalize(query: query)
        guard !needle.isEmpty, replacement != query else { return .empty }
        var skips = SkipReport()
        var files: [FileChange] = []

        let scanned = scanTextFiles(
            in: root, maxDepth: maxDepth, maxFileSize: maxFileSize,
            ignored: ignored, fileManager: fileManager, skips: &skips
        ) { entry, text in
            if let change = fileChange(for: entry, text: text, normalizedQuery: needle, replacement: replacement) {
                files.append(change)
            }
            return true
        }

        return ReplacePlan(
            query: query, replacement: replacement,
            files: files.sorted {
                $0.entry.relativePath.localizedCaseInsensitiveCompare($1.entry.relativePath) == .orderedAscending
            },
            skips: skips, scannedFiles: scanned
        )
    }

    /// **单条替换**：只改某一份文件的某一行（面板上「替换这一条」）。
    ///
    /// 与全部替换**同一套规则**，只是范围收窄到一行；返回的计划与全部替换同形 ——
    /// 落盘 / 撤销走同一条路（`apply` / `revert`），不留第二套写盘口径。
    public static func replaceLine(
        in root: URL,
        query: String,
        replacement: String,
        entry: WorkspaceEntry,
        line: Int,
        maxFileSize: Int = defaultMaxFileSize,
        fileManager: FileManager = .default
    ) -> ReplacePlan {
        let needle = normalize(query: query)
        guard !needle.isEmpty, replacement != query, line >= 1 else { return .empty }
        let url = root.appendingPathComponent(entry.relativePath)
        var skips = SkipReport()
        guard let text = readTextFile(
            entry, url: url, maxFileSize: maxFileSize, skips: &skips, fileManager: fileManager
        ) else { return .empty }
        let contents = CodeLines.contentRanges(in: text)
        guard contents.indices.contains(line - 1), let lineRange = CodeLines.range(ofLine: line, in: text) else {
            return .empty
        }
        let ns = text as NSString
        let before = ns.substring(with: contents[line - 1])
        let appliedOnContent = applyToLine(before, normalizedQuery: needle, replacement: replacement)
        guard appliedOnContent.count > 0 else { return .empty }
        // 落盘那一版**带上行终止符**再改，改完仍是同一种行尾（行尾保真）。
        let appliedOnFullLine = applyToLine(
            ns.substring(with: lineRange), normalizedQuery: needle, replacement: replacement
        )
        let replaced = ns.replacingCharacters(in: lineRange, with: appliedOnFullLine.text)
        let change = LineChange(
            line: line, before: before, after: appliedOnContent.text, count: appliedOnContent.count
        )
        return ReplacePlan(
            query: query, replacement: replacement,
            files: [FileChange(entry: entry, changes: [change], count: change.count, replaced: replaced)],
            skips: skips, scannedFiles: 1
        )
    }

    /// 把整份计划**落盘**（先备份后写），返回**撤销凭证**。
    ///
    /// 三条纪律：
    ///   ① 空计划**不碰盘**（返回空凭证）；
    ///   ② 任一文件读不出 / 写不进 ⇒ **把已写的回滚**并返回 `nil`（宁可整份不做，
    ///      也不留「一半改了、一半没改」的中间态）；
    ///   ③ 撤销凭证存的是**改之前的原字节** —— 撤销不重新搜一遍（拿改后的文本当依据，
    ///      撤销就成了第二次改）。
    @discardableResult
    public static func apply(
        _ plan: ReplacePlan, in root: URL, fileManager: FileManager = .default
    ) -> ReplaceUndo? {
        guard !plan.isEmpty else { return ReplaceUndo() }
        var originals: [String: Data] = [:]
        for file in plan.files {
            let url = root.appendingPathComponent(file.entry.relativePath)
            guard let original = fileManager.contents(atPath: url.path) else {
                restore(originals, in: root)
                return nil
            }
            originals[file.entry.relativePath] = original
            guard let data = file.replaced.data(using: .utf8),
                  (try? data.write(to: url, options: .atomic)) != nil else {
                restore(originals, in: root)
                return nil
            }
        }
        return ReplaceUndo(originals: originals)
    }

    /// **撤销**一次落盘：把原字节逐个写回。返回是否全部写回成功。
    @discardableResult
    public static func revert(_ undo: ReplaceUndo, in root: URL, fileManager: FileManager = .default) -> Bool {
        var ok = true
        for (relativePath, data) in undo.originals {
            let url = root.appendingPathComponent(relativePath)
            if (try? data.write(to: url, options: .atomic)) == nil { ok = false }
        }
        return ok
    }

    /// 回滚：把已记下的原字节写回去（`apply` 中途失败时用；尽力恢复，不再抛）。
    private static func restore(_ originals: [String: Data], in root: URL) {
        for (relativePath, data) in originals {
            try? data.write(to: root.appendingPathComponent(relativePath), options: .atomic)
        }
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
