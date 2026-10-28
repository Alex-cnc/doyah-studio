import Foundation

/// 工作区里的**项目规则文件**（`FR-AGT-KNOW-CTX-003`）：开跑前读，读到的每一条都带路径。
///
/// 三条口径（每条都对应一类真实错法）：
/// 1. **只读、不新建**：找不到就是找不到，不许顺手写一个空 `AGENTS.md`（那会把「项目没定规矩」变成「定了空规矩」）；
/// 2. **带路径**：同一句话从 `AGENTS.md` 来还是从 `.doyah/rules/10-门禁.md` 来，含义完全不同 —— 路径必须跟正文一起进上下文；
/// 3. **有界**：单文件与总量各有上限，超了**如实报**（截了多少字 / 因预算跳过几份），不静默截断。
public struct AgentProjectRuleSource: Equatable, Sendable {

    /// 相对工作区根的路径（如 `AGENTS.md` / `.doyah/rules/10-门禁.md`）。
    public var relativePath: String
    /// 正文（已按上限截断；截断的字数见 `truncatedCharacters`）。
    public var text: String
    /// 这一份被截掉的字数（0 = 完整）。
    public var truncatedCharacters: Int

    public init(relativePath: String, text: String, truncatedCharacters: Int = 0) {
        self.relativePath = relativePath
        self.text = text
        self.truncatedCharacters = truncatedCharacters
    }
}

/// 一次规则读取的读数。**找不到也要能说清「找了哪几处」**。
public struct AgentProjectRulesResult: Equatable, Sendable {

    public var sources: [AgentProjectRuleSource]
    /// 固定候选位置（无论找到没找到都列出来）—— 界面与提示词据此说「我看了这些地方」。
    public var searchedPaths: [String]
    /// 读不了的文件份数（非 UTF-8 / 权限不足等）。
    public var skippedFiles: Int
    /// 因总量上限被整份跳过的份数。
    public var skippedByBudget: Int
    /// 合计被截掉的字数。
    public var truncatedCharacters: Int

    public var isEmpty: Bool { sources.isEmpty }

    public init(sources: [AgentProjectRuleSource] = [],
                searchedPaths: [String] = [],
                skippedFiles: Int = 0,
                skippedByBudget: Int = 0,
                truncatedCharacters: Int = 0) {
        self.sources = sources
        self.searchedPaths = searchedPaths
        self.skippedFiles = skippedFiles
        self.skippedByBudget = skippedByBudget
        self.truncatedCharacters = truncatedCharacters
    }
}

public enum AgentProjectRules {

    /// 根目录下的固定候选（顺序即优先级：项目级在前，工具级在后）。
    public static let rootFileNames = ["AGENTS.md", "DOYAH.md"]
    /// 目录形式的候选（其中 `*.md` 按文件名排序，顺序稳定才可逐字对拍）。
    public static let rulesDirectoryName = ".doyah/rules"

    public struct Limits: Equatable, Sendable {
        public var maxCharactersPerFile: Int
        public var maxTotalCharacters: Int

        public init(maxCharactersPerFile: Int = 8_000, maxTotalCharacters: Int = 24_000) {
            self.maxCharactersPerFile = maxCharactersPerFile
            self.maxTotalCharacters = maxTotalCharacters
        }

        public static let standard = Limits()
    }

    /// 读一遍（**只读**；不创建任何文件/目录）。
    public static func load(workspacePath: String?,
                            limits: Limits = .standard,
                            fileManager: FileManager = .default) -> AgentProjectRulesResult {
        guard let workspacePath, !workspacePath.isEmpty else {
            return AgentProjectRulesResult(searchedPaths: rootFileNames + [rulesDirectoryName])
        }
        let root = URL(fileURLWithPath: workspacePath, isDirectory: true)

        var searched = rootFileNames
        var candidates: [URL] = rootFileNames.map { root.appendingPathComponent($0) }

        let rulesDirectory = root.appendingPathComponent(rulesDirectoryName, isDirectory: true)
        if let names = try? fileManager.contentsOfDirectory(atPath: rulesDirectory.path) {
            let markdown = names.filter { $0.hasSuffix(".md") }.sorted()
            searched.append(rulesDirectoryName + "/" + (markdown.isEmpty ? "*.md" : markdown.joined(separator: "、")))
            candidates.append(contentsOf: markdown.map { rulesDirectory.appendingPathComponent($0) })
        } else {
            searched.append(rulesDirectoryName)
        }

        var sources: [AgentProjectRuleSource] = []
        var skippedFiles = 0
        var skippedByBudget = 0
        var truncatedTotal = 0
        var used = 0

        for url in candidates {
            guard fileManager.fileExists(atPath: url.path) else { continue }
            guard let raw = try? String(contentsOf: url, encoding: .utf8) else {
                skippedFiles += 1
                continue
            }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let remaining = max(0, limits.maxTotalCharacters - used)
            if remaining == 0 {
                skippedByBudget += 1
                continue
            }
            let cap = min(limits.maxCharactersPerFile, remaining)
            var text = trimmed
            var truncated = 0
            if text.count > cap {
                truncated = text.count - cap
                text = String(text.prefix(cap))
            }
            used += text.count
            truncatedTotal += truncated
            sources.append(AgentProjectRuleSource(relativePath: relativePath(of: url, root: root),
                                                  text: text,
                                                  truncatedCharacters: truncated))
        }

        return AgentProjectRulesResult(sources: sources,
                                       searchedPaths: searched,
                                       skippedFiles: skippedFiles,
                                       skippedByBudget: skippedByBudget,
                                       truncatedCharacters: truncatedTotal)
    }

    static func relativePath(of url: URL, root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath) else { return url.lastPathComponent }
        var relative = String(path.dropFirst(rootPath.count))
        if relative.hasPrefix("/") { relative.removeFirst() }
        return relative
    }
}
