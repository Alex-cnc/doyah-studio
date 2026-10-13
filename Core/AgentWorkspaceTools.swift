import Foundation

/// 工具被拒的原因码（`FR-AI-20` ②：「拒绝并**报明原因**」）。
///
/// 刻意用**机器码 + 细节串**，不写死人话 —— 人话由带 `language:` 的渲染入口给
/// （与 `AgentGuardFinding` / 本地化纪律同一条口径：Core 不写死人话）。
public enum AgentToolRefusal: String, Codable, Equatable, Sendable {
    case outsideWorkspace
    case notFound
    case notAFile
    case notADirectory
    case binaryFile
    case unreadable
    case emptyQuery
    case unregistered
}

/// 读文件的输出（结构化 ⇒ 截断**可被断言**，不必靠人话里那句提示）。
public struct AgentToolFileOutput: Equatable, Sendable {
    public var path: String
    public var text: String
    public var truncated: Bool
    public var totalBytes: Int
}

/// 列目录的输出。
public struct AgentToolDirectoryOutput: Equatable, Sendable {
    public var path: String
    /// 目录项（目录带结尾 `/`），已排序。
    public var entries: [String]
    public var truncated: Bool
}

/// 搜索的输出：**文件名命中**与**内容命中**分列（`FR-AI-20` ① 要求两类都能命中）。
public struct AgentToolSearchOutput: Equatable, Sendable {
    public var fileNames: [String]
    /// `相对路径:行号: 片段`
    public var contentHits: [String]
    public var truncated: Bool
}

/// 要审批的动作（写 / 执行）。指纹按**次**算：工具名 + 参数 ⇒ 换参数要重新批。
public struct AgentApprovalRequest: Equatable, Sendable {
    public var toolName: String
    public var fingerprint: String
    /// 要写的差异预览 / 要跑的命令原文（给人看的**事实**，不是人话判词）。
    public var payload: String
}

/// 一次工具调用的结果。
public enum AgentToolOutcome: Equatable, Sendable {
    case file(AgentToolFileOutput)
    case directory(AgentToolDirectoryOutput)
    case search(AgentToolSearchOutput)
    /// 只读语句直接跑出来的结果（`query_db`）。
    case rows(AgentToolRowsOutput)
    case refused(AgentToolRefusal, detail: String)
    case needsApproval(AgentApprovalRequest)
}

/// `query_db` 的只读结果（行数据**不进**这个结构 —— 它只带列名与行数，`NFR-AI-01` 口径）。
public struct AgentToolRowsOutput: Equatable, Sendable {
    public var columns: [String]
    public var rowCount: Int
    public var statementKind: String
}

/// 工作区路径沙箱（`FR-AI-20` ②）：**唯一**一处判「这个路径在不在工作区里」。
///
/// 两条写法都要挡（判据点名）：**绝对路径**落在工作区外、以及用 `..` 爬出去。
/// 归一化后仍落在工作区内的 `..`（如 `a/../b`）是**合法**的 —— 挡的是「出去」，不是 `..` 本身。
public enum AgentWorkspaceSandbox {

    public enum Resolution: Equatable, Sendable {
        case inside(URL)
        case outside(detail: String)
    }

    public static func resolve(_ raw: String, in root: URL) -> Resolution {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .outside(detail: "empty path") }

        let candidate: URL
        if trimmed.hasPrefix("/") {
            candidate = URL(fileURLWithPath: trimmed).standardizedFileURL
        } else {
            candidate = root.appendingPathComponent(trimmed).standardizedFileURL
        }
        let base = root.standardizedFileURL

        let basePath = base.path.hasSuffix("/") ? base.path : base.path + "/"
        if candidate.path == base.path || candidate.path.hasPrefix(basePath) {
            return .inside(candidate)
        }
        return .outside(detail: candidate.path)
    }
}

/// 工作区内的工具实现（`FR-AI-20`；本片 = **只读三件**：`read_file` / `list_dir` / `search`）。
///
/// 检索**复用既有引擎**（`WorkspaceSearch`，契约 §3.33「一套引擎、两个入口」）——
/// 不为工具另写一套遍历，否则两套口径必然漂移。
public struct AgentWorkspaceTools: Sendable {

    public var root: URL
    /// 读文件的上限（超出即截断并**如实标记**，不静默）。
    public var maxReadBytes: Int
    /// 列目录的上限。
    public var maxDirectoryEntries: Int

    public init(root: URL, maxReadBytes: Int = 262_144, maxDirectoryEntries: Int = 500) {
        self.root = root
        self.maxReadBytes = maxReadBytes
        self.maxDirectoryEntries = maxDirectoryEntries
    }

    // MARK: - read_file

    public func readFile(path: String) -> AgentToolOutcome {
        let resolved = AgentWorkspaceSandbox.resolve(path, in: root)
        guard case .inside(let url) = resolved else {
            if case .outside(let detail) = resolved { return .refused(.outsideWorkspace, detail: detail) }
            return .refused(.outsideWorkspace, detail: path)
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return .refused(.notFound, detail: url.lastPathComponent)
        }
        guard !isDirectory.boolValue else { return .refused(.notAFile, detail: url.lastPathComponent) }
        guard let data = try? Data(contentsOf: url) else {
            return .refused(.unreadable, detail: url.lastPathComponent)
        }

        // **截断要按字符安全**：文件比上限大时，先多读 4 字节（一个 UTF-8 序列最长 4 字节），
        // 再最多回退 3 字节找能解码的边界 —— 否则「按字节切」会切断多字节字符，
        // 把一个好好的文本文件误判成二进制（判据当场抓过这个缺陷）。
        // 文件**没超上限**时按整段判：那时二进制与文本的界线是确定的（回退会放走真二进制）。
        let truncated = data.count > maxReadBytes
        let text: String
        if truncated {
            var slice = data.prefix(maxReadBytes + 4)
            var decoded: String?
            for _ in 0..<4 {
                if let candidate = String(data: slice, encoding: .utf8) { decoded = candidate; break }
                guard !slice.isEmpty else { break }
                slice = slice.dropLast()
            }
            guard let decoded else {
                return .refused(.binaryFile, detail: url.lastPathComponent)
            }
            text = decoded
        } else {
            guard let whole = String(data: data, encoding: .utf8) else {
                // 二进制：解码不出来就**如实拒**，不塞一堆乱码给模型
                return .refused(.binaryFile, detail: url.lastPathComponent)
            }
            text = whole
        }

        return .file(AgentToolFileOutput(path: relativePath(url),
                                        text: text,
                                        truncated: truncated,
                                        totalBytes: data.count))
    }

    // MARK: - list_dir

    public func listDirectory(path: String) -> AgentToolOutcome {
        let resolved = AgentWorkspaceSandbox.resolve(path, in: root)
        guard case .inside(let url) = resolved else {
            if case .outside(let detail) = resolved { return .refused(.outsideWorkspace, detail: detail) }
            return .refused(.outsideWorkspace, detail: path)
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return .refused(.notFound, detail: url.lastPathComponent)
        }
        guard isDirectory.boolValue else { return .refused(.notADirectory, detail: url.lastPathComponent) }

        let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        var entries: [String] = []
        for name in names.sorted() {
            var childIsDirectory: ObjCBool = false
            let child = url.appendingPathComponent(name)
            _ = FileManager.default.fileExists(atPath: child.path, isDirectory: &childIsDirectory)
            entries.append(childIsDirectory.boolValue ? name + "/" : name)
        }
        let truncated = entries.count > maxDirectoryEntries
        if truncated { entries = Array(entries.prefix(maxDirectoryEntries)) }
        return .directory(AgentToolDirectoryOutput(path: relativePath(url), entries: entries, truncated: truncated))
    }

    // MARK: - search

    /// 搜索（文件名 + 内容两类）。**复用既有引擎**，不另写遍历。
    public func searchStructured(query: String, limit: Int = 50) -> AgentToolOutcome {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return .refused(.emptyQuery, detail: query) }

        let files = WorkspaceSearch.findFileNames(in: root, query: needle, limit: limit)
        let contents = WorkspaceSearch.findContents(in: root, query: needle, limit: limit)

        var hits: [String] = []
        for group in contents.groups {
            for hit in group.hits {
                hits.append("\(group.entry.relativePath):\(hit.line): \(hit.snippet)")
            }
        }
        return .search(AgentToolSearchOutput(fileNames: files.entries.map(\.relativePath),
                                            contentHits: hits,
                                            truncated: files.isTruncated || contents.isTruncated))
    }

    public func search(query: String, limit: Int = 50) -> AgentToolOutcome {
        searchStructured(query: query, limit: limit)
    }

    // MARK: - 内部

    private func relativePath(_ url: URL) -> String {
        let base = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(base) else { return url.lastPathComponent }
        let suffix = path.dropFirst(base.count)
        return suffix.hasPrefix("/") ? String(suffix.dropFirst()) : String(suffix)
    }
}
