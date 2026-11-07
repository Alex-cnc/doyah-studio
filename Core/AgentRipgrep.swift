import Foundation

/// **随包 ripgrep** —— 智能体 `search` 工具的首选执行器（2026-11-07 主人拍板）。
///
/// 由头是真机读数：同一个查询（`WorkspaceSearch`），`rg` 0.04–0.06 秒，而
/// `WorkspaceSearch.findContents`（一次性全仓遍历 + 每个文件整篇解码成 String）1.4–1.8 秒。
/// 调用点只有一处：`AgentWorkspaceTools.searchStructured`（见那里的注释与行号）。
///
/// # 三条纪律
///
/// 1. **找不到 / 起不来 ⇒ 返回 `nil`，绝不抛错、绝不返回空**。调用方据此回落
///    `WorkspaceSearch` 的 Swift 实现（同一份忽略名单、同一个匹配谓词）。
///    判 `nil` 的情形：随包路径没有、没有可执行位、`posix_spawn` 失败（架构不符）、
///    超时、退出码不是 0/1（rg 用 1 表示「无命中」，2 是真错）。
/// 2. **扫描面与 Swift 实现逐字对齐**：隐藏条目不搜（`WorkspaceTree.children` 的 `showHidden: false`）、
///    按 `WorkspaceTree.searchIgnored` 逐个 `--glob !<名>`、`--max-depth` / `--max-filesize`
///    同参数、不跟随符号链接（rg 默认）。2026-11-07 实测本仓：两边的**文件集合完全相同**
///    （2334 = 2334，双向差集都是 0），见 `Tests/AgentRipgrepSearchTests.swift`。
/// 3. **命中映射不改口径**：行号仍取 rg 的 `line_number`（1 起）；摘要仍走
///    `WorkspaceSearch.snippet`（去首尾空白 + 200 字截断）；分组/排序仍按文件、按行号升序；
///    `路径:行: 片段` 这一个字符串形状由调用点拼，不在这里另写一套。
///
/// # 已知口径差（写在这里，免得下次当成 bug 查）
///
/// * **去变音符号**：`WorkspaceSearch.matches` 用 `.diacriticInsensitive`（`cafe` 能命中 `café`），
///   而 rg 只有大小写不敏感（`-i`）。所以 `search` 工具走 rg 时**不再折叠变音符号** ——
///   跨写法搜不到的那一类词，用词面上带重音的写法再搜一次就能中。界面侧（标头搜索框 /
///   替换定位）仍走 `WorkspaceSearch` 本体，一个字节都没变。
/// * **行号数法**：rg 只认 `\n` 换行，`WorkspaceSearch` 用 `CodeLines.contentRanges`
///   （认 `\r` / `U+2028` / `U+2029`）。含这些字符的文件上两者可能差几行。
/// * **符号链接**：Swift 侧显式跳过；rg 默认不跟随目录符号链接，但会把指向文件的链接列进
///   `--files`。少见的边界，不影响正文检索。
/// * **命中超上限时截到的是不同子集**：Swift 按遍历顺序取前 N 条，rg 按它自己的（并行）输出
///   顺序取前 N 条。不截断时两边集合逐字相同（`Tests/AgentRipgrepSearchTests` 就是这么判的）；
///   截断时只有「条数」同口径。
public enum AgentRipgrep {

    /// 可执行文件名（PATH 里找的就是它）。
    public static let binaryName = "rg"
    /// 随包相对路径（相对 `Bundle.main.resourceURL`）—— `Contents/Resources/tools/rg`。
    public static let toolRelativePath = "tools/rg"
    /// 随包这一份的版本（`rg --version` 首行；升级时与 `App/Resources/tools/README.md` 一起改）。
    public static let bundledVersion = "15.2.0"

    /// 一次内容检索的读数（`elapsedMillis` / `scannedFiles` 入账用）。
    public struct ContentScan: Equatable, Sendable {
        /// 与 `queries` **同序**。
        public var results: [WorkspaceSearch.ContentResult]
        public var elapsedMillis: Int
        /// rg 的 `stats.searches`：真正读了内容的文件数（含读了但没命中的）。
        public var scannedFiles: Int
    }

    /// 一次文件名检索的读数。
    public struct NameScan: Equatable, Sendable {
        /// 与 `queries` **同序**。
        public var results: [WorkspaceSearch.Result]
        public var elapsedMillis: Int
    }

    /// 一次「加速」= 文件名 + 内容两趟 rg，供调用点整体替换掉两趟 Swift 遍历。
    public struct Acceleration: Equatable, Sendable {
        public var fileNames: [WorkspaceSearch.Result]
        public var contents: [WorkspaceSearch.ContentResult]
        public var elapsedMillis: Int
        /// 实际用的那个可执行文件（随包 / PATH）—— 探针要能读出来。
        public var executablePath: String
    }

    // MARK: - 定位

    /// 随包路径（**存在且可执行**才算数；没有返回 `nil`）。
    public static func bundledExecutable(in bundle: Bundle = .main) -> String? {
        guard let resources = bundle.resourceURL else { return nil }
        let path = resources.appendingPathComponent(toolRelativePath).path
        return isExecutable(path) ? path : nil
    }

    /// 取值顺序：**随包 → PATH**。两处都没有 ⇒ `nil`（调用方回落）。
    ///
    /// 刻意不缓存：随包文件被删 / 被 chmod 掉要能立刻被看见（一次 `stat` 而已，
    /// 比一次 1.4 秒的全仓遍历便宜三个数量级）。
    public static func locate(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        if let bundled = bundledExecutable(in: bundle) { return bundled }
        let path = environment["PATH"] ?? ""
        for directory in path.split(separator: ":") where !directory.isEmpty {
            let candidate = String(directory) + "/" + binaryName
            if isExecutable(candidate) { return candidate }
        }
        return nil
    }

    /// 可执行位 + 不是目录 + 真的存在。
    public static func isExecutable(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { return false }
        return !isDirectory.boolValue && FileManager.default.isExecutableFile(atPath: path)
    }

    // MARK: - 组合入口（调用点用的就是这一个）

    /// 文件名 + 内容两趟 rg。**任何一步失败 ⇒ `nil`**（调用方回落 Swift 实现，不是回落空结果）。
    ///
    /// - Parameter executable: 不给就自己找（随包 → PATH）。单测用它钉一个确定的可执行文件，
    ///   或用它把一个不存在的路径钉成「rg 不可用」。
    public static func accelerate(
        in root: URL,
        queries: [String],
        limit: Int = WorkspaceSearch.defaultResultLimit,
        perFileLimit: Int = WorkspaceSearch.defaultPerFileLimit,
        maxDepth: Int = WorkspaceSearch.defaultMaxDepth,
        maxFileSize: Int = WorkspaceSearch.defaultMaxFileSize,
        snippetLimit: Int = WorkspaceSearch.defaultSnippetLimit,
        ignored: Set<String> = WorkspaceTree.searchIgnored,
        executable: String? = nil,
        timeout: TimeInterval = 15
    ) -> Acceleration? {
        guard let path = executable ?? locate(), isExecutable(path) else { return nil }
        let started = Date()
        guard let names = searchFileNames(
            in: root, queries: queries, limit: limit, maxDepth: maxDepth,
            ignored: ignored, executable: path, timeout: timeout
        ) else { return nil }
        guard let contents = searchContents(
            in: root, queries: queries, limit: limit, perFileLimit: perFileLimit,
            maxDepth: maxDepth, maxFileSize: maxFileSize, snippetLimit: snippetLimit,
            ignored: ignored, executable: path, timeout: timeout
        ) else { return nil }
        return Acceleration(
            fileNames: names.results, contents: contents.results,
            elapsedMillis: Int(Date().timeIntervalSince(started) * 1000),
            executablePath: path
        )
    }

    // MARK: - 内容检索

    /// 在工作区内按内容检索（**一次 rg 扫盘、多词各比一遍**）。
    ///
    /// 词表与 `WorkspaceSearch.findContents(in:queries:…)` 同序同义；`nil` = rg 不可用 / 调用失败。
    public static func searchContents(
        in root: URL,
        queries: [String],
        limit: Int = WorkspaceSearch.defaultResultLimit,
        perFileLimit: Int = WorkspaceSearch.defaultPerFileLimit,
        maxDepth: Int = WorkspaceSearch.defaultMaxDepth,
        maxFileSize: Int = WorkspaceSearch.defaultMaxFileSize,
        snippetLimit: Int = WorkspaceSearch.defaultSnippetLimit,
        ignored: Set<String> = WorkspaceTree.searchIgnored,
        executable: String,
        timeout: TimeInterval = 15
    ) -> ContentScan? {
        let needles = queries.map(WorkspaceSearch.normalize(query:))
        var groups = [[WorkspaceSearch.ContentGroup]](repeating: [], count: queries.count)
        var totals = [Int](repeating: 0, count: queries.count)
        var truncated = [Bool](repeating: false, count: queries.count)
        var order = [[String]](repeating: [], count: queries.count)
        var hitsByPath = [[String: [WorkspaceSearch.ContentHit]]](repeating: [:], count: queries.count)
        let active = needles.indices.filter { !needles[$0].isEmpty }
        guard !active.isEmpty, limit > 0, perFileLimit > 0, maxDepth >= 0, maxFileSize > 0 else {
            return ContentScan(results: queries.map { _ in .empty }, elapsedMillis: 0, scannedFiles: 0)
        }

        // **不传 `--sort path`**：它逼 rg 单线程，同一条命令在本仓 50–70ms → 20ms（实测）。
        // 输出顺序由我们自己收口（下面按路径排），所以结果依旧可复现。
        var arguments = ["--json", "--stats",
                         "--fixed-strings", "--ignore-case",
                         "--no-config", "--no-ignore", "--no-messages",
                         "--max-depth", String(maxDepth),
                         "--max-filesize", String(maxFileSize)]
        // **不传 `--max-count`**：rg 那个上限是「每个文件对所有词合计多少行」，而
        // `WorkspaceSearch` 的 `perFileLimit` 是「每个文件**每个词**多少条」—— 传下去会在
        // 一个热文件上把后面几个词全挤掉。上限在下面按词、按文件自己数（同一条口径）。
        arguments.append(contentsOf: ignoreGlobArguments(ignored))
        for index in active {
            arguments.append("-e")
            arguments.append(needles[index])
        }
        arguments.append(contentsOf: ["--", "."])

        let started = Date()
        guard let outcome = run(executable: executable, arguments: arguments,
                                workingDirectory: root, timeout: timeout) else { return nil }
        let millis = Int(Date().timeIntervalSince(started) * 1000)
        var scannedFiles = 0

        for line in outcome.text.split(separator: "\n", omittingEmptySubsequences: true) {
            // 快筛：绝大多数行是 `begin` / `end` 事件，不必解 JSON。
            guard line.contains("\"type\":\"match\"") else {
                if line.contains("\"type\":\"summary\""), scannedFiles == 0 {
                    scannedFiles = summarySearches(line) ?? 0
                }
                continue
            }
            guard let event = jsonObject(line),
                  let data = event["data"] as? [String: Any],
                  let pathText = (data["path"] as? [String: Any])?["text"] as? String,
                  let lineNumber = data["line_number"] as? Int
            else { continue }
            let relativePath = stripDotSlash(pathText)
            let raw = ((data["lines"] as? [String: Any])?["text"] as? String) ?? ""
            let text = trimLineTerminator(raw)
            for index in active where !truncated[index] {
                guard WorkspaceSearch.matches(text, normalizedQuery: needles[index]) else { continue }
                if totals[index] >= limit { truncated[index] = true; continue }
                // 单文件条数上限：与 `WorkspaceSearch.findContents` 的 `perFileLimit` 同一条
                // 口径（每文件每词最多这么多条），只挡这一个文件、不停整个词。
                if (hitsByPath[index][relativePath]?.count ?? 0) >= perFileLimit { continue }
                let entry = WorkspaceEntry(
                    name: (relativePath as NSString).lastPathComponent,
                    relativePath: relativePath, kind: .file
                )
                if hitsByPath[index][relativePath] == nil {
                    hitsByPath[index][relativePath] = []
                    order[index].append(relativePath)
                }
                hitsByPath[index][relativePath]?.append(WorkspaceSearch.ContentHit(
                    entry: entry, line: lineNumber,
                    snippet: WorkspaceSearch.snippet(text, limit: snippetLimit)
                ))
                totals[index] += 1
                // **不因为「某个文件吃满 perFileLimit」停掉这个词**：`--max-count` 与
                // `WorkspaceSearch` 的 `perFileLimit` 是同一条口径（每文件最多这么多行），
                // 停的是这个文件、不是这次搜索 —— 混成一个标志会把后面的文件全丢掉。
            }
        }

        for index in 0..<queries.count where !order[index].isEmpty {
            var built: [WorkspaceSearch.ContentGroup] = []
            // 按路径排：rg 是多线程的，输出顺序本身不保证；**排序在这里做**，
            // 于是同一个查询在两次调用里给出同一份列表（缓存 / 判据 / 模型都读同一份）。
            for path in order[index].sorted() {
                let hits = (hitsByPath[index][path] ?? []).sorted { $0.line < $1.line }
                guard let first = hits.first else { continue }
                built.append(WorkspaceSearch.ContentGroup(entry: first.entry, hits: hits))
            }
            groups[index] = built
        }

        let results = queries.indices.map { index in
            WorkspaceSearch.ContentResult(
                groups: groups[index], skips: WorkspaceSearch.SkipReport(),
                scannedFiles: scannedFiles,
                isTruncated: truncated[index]
            )
        }
        return ContentScan(results: results, elapsedMillis: millis, scannedFiles: scannedFiles)
    }

    // MARK: - 文件名检索

    /// 按文件名检索（`rg --files` 列完再在 Swift 里过**同一个谓词**，所以变音符号折叠仍在）。
    ///
    /// `nil` = rg 不可用 / 调用失败（调用方回落 `WorkspaceSearch.findFileNames`）。
    public static func searchFileNames(
        in root: URL,
        queries: [String],
        limit: Int = WorkspaceSearch.defaultResultLimit,
        maxDepth: Int = WorkspaceSearch.defaultMaxDepth,
        ignored: Set<String> = WorkspaceTree.searchIgnored,
        executable: String,
        timeout: TimeInterval = 15
    ) -> NameScan? {
        let needles = queries.map(WorkspaceSearch.normalize(query:))
        var found = [[WorkspaceEntry]](repeating: [], count: queries.count)
        var truncated = [Bool](repeating: false, count: queries.count)
        let active = needles.indices.filter { !needles[$0].isEmpty }
        guard !active.isEmpty else {
            return NameScan(results: queries.map { _ in .init(entries: [], isTruncated: false) }, elapsedMillis: 0)
        }

        var arguments = ["--files", "--no-config", "--no-ignore", "--no-messages",
                         "--max-depth", String(maxDepth)]
        arguments.append(contentsOf: ignoreGlobArguments(ignored))
        arguments.append(".")

        let started = Date()
        guard let outcome = run(executable: executable, arguments: arguments,
                                workingDirectory: root, timeout: timeout) else { return nil }
        let millis = Int(Date().timeIntervalSince(started) * 1000)

        for rawLine in outcome.text.split(separator: "\n", omittingEmptySubsequences: true) {
            let relativePath = stripDotSlash(String(rawLine))
            guard !relativePath.isEmpty else { continue }
            let name = (relativePath as NSString).lastPathComponent
            for index in active where !truncated[index] {
                guard WorkspaceSearch.matches(name, normalizedQuery: needles[index]) else { continue }
                if found[index].count >= limit { truncated[index] = true; continue }
                found[index].append(WorkspaceEntry(name: name, relativePath: relativePath, kind: .file))
            }
            if active.allSatisfy({ truncated[$0] }) { break }
        }

        let results = queries.indices.map { index in
            WorkspaceSearch.Result(
                entries: found[index].sorted {
                    $0.relativePath.localizedCaseInsensitiveCompare($1.relativePath) == .orderedAscending
                },
                isTruncated: truncated[index]
            )
        }
        return NameScan(results: results, elapsedMillis: millis)
    }

    // MARK: - 进程

    struct Outcome {
        var text: String
        var exitCode: Int32
    }

    /// 跑一次 rg。**失败一律 `nil`**（调用方据此回落，不把「跑不起来」当成「没命中」）。
    ///
    /// 这里刻意**不用 `waitUntilExit()`**：实测它在 macOS 上是 63–67 毫秒的固定开销
    /// （`/usr/bin/true` 也一样，跟被调程序无关），一次 `search` 要跑两趟 ⇒ 光等就 130 毫秒，
    /// 比整个检索还贵。改等 `terminationHandler` + 管道 EOF，实测 1–2 毫秒。
    static func run(executable: String, arguments: [String],
                    workingDirectory: URL, timeout: TimeInterval) -> Outcome? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        var environment = ProcessInfo.processInfo.environment
        // 路径与正文里的中文不该因为宿主 locale 变化而换成问号（JSON 也是 UTF-8）。
        environment["LC_ALL"] = "en_US.UTF-8"
        environment["LANG"] = "en_US.UTF-8"
        // 用户自己的 `RIPGREP_CONFIG_PATH` 会**静默改掉**搜索口径（`--glob` / `--hidden` …）：
        // 命令行上的 `--no-config` 负责挡读取，这里再把 locale 钉死。
        process.environment = environment

        let collector = OutputCollector()
        let group = DispatchGroup()
        group.enter()
        process.terminationHandler = { _ in group.leave() }
        do {
            try process.run()
        } catch {
            // 起不来（路径不在 / 架构不符 EBADARCH / 没有执行权）⇒ **如实返回 nil**，
            // 调用方回落 Swift 引擎。这里**绝不能**去读 `terminationStatus`：没起来的
            // `NSConcreteTask` 读它会抛 `task still running` 的 NSException（当场 abort）。
            return nil
        }
        // **必须边跑边读**：结果可以到几百 KB，超过管道缓冲（64 KB）就会两边互等到超时。
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            collector.data = pipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        if group.wait(timeout: .now() + timeout) == .timedOut {
            if process.isRunning { process.terminate() }
            return nil
        }
        // rg 的口径：0 = 有命中，1 = 没命中，2 = 出错。2 及以上 ⇒ 这次读数不算数。
        guard process.terminationStatus == 0 || process.terminationStatus == 1 else { return nil }
        return Outcome(text: String(decoding: collector.data, as: UTF8.self),
                       exitCode: process.terminationStatus)
    }

    /// 后台读线程与调用线程之间只传这一块数据（`DispatchGroup.wait` 是同步点）。
    final class OutputCollector: @unchecked Sendable {
        var data = Data()
    }

    // MARK: - 小工具

    /// 忽略名单 ⇒ `--glob !<名>`（与 `WorkspaceTree.searchIgnored` 逐项对应，任一层同名都跳过）。
    static func ignoreGlobArguments(_ ignored: Set<String>) -> [String] {
        ignored.sorted().flatMap { ["--glob", "!" + $0] }
    }

    /// rg 以 `.` 为搜索根时输出 `./Core/x.swift` —— 相对路径的口径是**不带** `./` 的。
    static func stripDotSlash(_ path: String) -> String {
        if path.hasPrefix("./") { return String(path.dropFirst(2)) }
        return path
    }

    /// 去掉行尾终止符（`\n` / `\r\n`）—— 摘要不该带换行，行号才是行位置的唯一出处。
    static func trimLineTerminator(_ line: String) -> String {
        var text = line
        if text.hasSuffix("\n") { text.removeLast() }
        if text.hasSuffix("\r") { text.removeLast() }
        return text
    }

    static func jsonObject(_ line: Substring) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// `summary.stats.searches` —— 真正读了内容的文件数。
    static func summarySearches(_ line: Substring) -> Int? {
        guard let event = jsonObject(line),
              let data = event["data"] as? [String: Any],
              let stats = data["stats"] as? [String: Any]
        else { return nil }
        return stats["searches"] as? Int
    }
}
