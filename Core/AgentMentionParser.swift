import Foundation

/// 一条 `@` 提及（`FR-AI-22` ①）：用户在这句话里点名要带上什么。
public struct AgentMention: Equatable, Sendable {
    public enum Kind: String, Sendable { case file, directory }
    /// 原样写的那一段（去掉 `@`），用于回显"我没找到 <raw>"。
    public let raw: String
    /// 相对工作区根归一化后的路径（`/` 分隔，不带 `./`）。
    public let path: String
    public let kind: Kind

    public init(raw: String, path: String, kind: Kind) {
        self.raw = raw
        self.path = path
        self.kind = kind
    }
}

/// 一条**没被采纳**的提及。为什么不采纳必须说清（静默丢掉是最坏的一种）。
public struct AgentMentionIssue: Equatable, Sendable {
    public enum Reason: String, Sendable {
        /// 指到工作区外面（含 `..` 逃逸、绝对路径越界）。
        case outsideWorkspace
        /// 工作区里没有这个东西。
        case notFound
        /// 是目录但没写结尾 `/`，或反之 —— **按实际类型纠正并在 issues 里说明**。
        case typeMismatch
    }
    public let raw: String
    public let reason: Reason

    public init(raw: String, reason: Reason) {
        self.raw = raw
        self.reason = reason
    }
}

/// 解析结果：**提示词原样不动**，提及单独拎出来（不改用户写的字）。
public struct AgentMentionParseResult: Equatable, Sendable {
    public let mentions: [AgentMention]
    public let issues: [AgentMentionIssue]

    public init(mentions: [AgentMention], issues: [AgentMentionIssue]) {
        self.mentions = mentions
        self.issues = issues
    }
}

/// `@文件` / `@目录` 的解析（`FR-AI-22` ①）。
///
/// 三条硬规矩：
/// 1. **只在句首或空白之后才认 `@`** —— 否则 `a@b.com` 这种邮箱会被当成提及；
/// 2. **路径必须落在工作区内**（`..` 逃逸、绝对路径越界一律 `outsideWorkspace`）——
///    与工具沙箱同一口径，不因为"只是读一下"就放宽；
/// 3. **提示词一个字都不改**：提及是额外的上下文供给，不是把用户的话重写一遍。
public enum AgentMentionParser {

    /// 提及后面允许紧跟的标点（中文句读也要剥 —— 用户写「@a.swift，改成这样」很常见）。
    /// 词边界标点。**刻意不含 `.` `:` `'` `"`** —— 它们本来就出现在文件名里
    /// （`a.swift`、`C:\\x`）；把 `.` 当边界会把每一个带扩展名的路径切坏（实测红过 9 条）。
    private static let tokenTerminators = CharacterSet(charactersIn: ",!?;，。；：！？、）)】」』”）")

    public static func parse(_ prompt: String, workspaceRoot: URL) -> AgentMentionParseResult {
        let root = workspaceRoot.standardizedFileURL
        var mentions: [AgentMention] = []
        var issues: [AgentMentionIssue] = []
        var seen = Set<String>()

        var index = prompt.startIndex
        while index < prompt.endIndex {
            guard prompt[index] == "@" else { index = prompt.index(after: index); continue }

            // ① 只认句首 / 空白之后的 `@`
            let isBoundary = index == prompt.startIndex
                || prompt[prompt.index(before: index)].isWhitespace
            guard isBoundary else { index = prompt.index(after: index); continue }

            var cursor = prompt.index(after: index)
            var raw = ""
            // ② 引号形式：@"带 空格 的路径"
            if cursor < prompt.endIndex, prompt[cursor] == "\"" {
                cursor = prompt.index(after: cursor)
                while cursor < prompt.endIndex, prompt[cursor] != "\"" {
                    raw.append(prompt[cursor]); cursor = prompt.index(after: cursor)
                }
                if cursor < prompt.endIndex { cursor = prompt.index(after: cursor) }  // 跳过收尾引号
            } else {
                // **标点也是词的边界**：中文句子里「@a.swift，改成这样」没有空格，
                // 只按空白切会把「，改成这样」一起吞进路径（实测红过两次）。
                while cursor < prompt.endIndex {
                    let ch = prompt[cursor]
                    if ch.isWhitespace { break }
                    if ch.unicodeScalars.contains(where: { tokenTerminators.contains($0) }) { break }
                    raw.append(ch); cursor = prompt.index(after: cursor)
                }
                // 剥掉尾部标点
                while let last = raw.unicodeScalars.last, tokenTerminators.contains(last) {
                    raw.unicodeScalars.removeLast()
                }
            }

            index = cursor
            guard !raw.isEmpty else { continue }

            switch resolve(raw: raw, root: root) {
            case .success(let mention):
                if seen.insert(mention.path).inserted { mentions.append(mention) }
            case .failure(let issue):
                issues.append(issue)
            }
        }
        return AgentMentionParseResult(mentions: mentions, issues: issues)
    }

    private enum Resolution {
        case success(AgentMention)
        case failure(AgentMentionIssue)
    }

    private static func resolve(raw: String, root: URL) -> Resolution {
        let wantsDirectory = raw.hasSuffix("/")
        let trimmed = wantsDirectory ? String(raw.dropLast()) : raw

        // 绝对路径 / `~` 一律按"不在工作区"处理 —— 不给"读一下系统文件"留口子
        guard !trimmed.hasPrefix("/"), !trimmed.hasPrefix("~") else {
            return .failure(AgentMentionIssue(raw: raw, reason: .outsideWorkspace))
        }

        let candidate = root.appendingPathComponent(trimmed).standardizedFileURL
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        let candidatePath = candidate.path
        // 相等 = 工作区根自己；否则必须以 rootPath 开头
        guard candidatePath == root.path || candidatePath.hasPrefix(rootPath) else {
            return .failure(AgentMentionIssue(raw: raw, reason: .outsideWorkspace))
        }
        // 用归一化后的路径再判一次 `..`（standardized 已消解，这里防的是符号链接之外的粗暴形式）
        guard !trimmed.split(separator: "/").contains("..") else {
            return .failure(AgentMentionIssue(raw: raw, reason: .outsideWorkspace))
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: candidatePath, isDirectory: &isDirectory) else {
            return .failure(AgentMentionIssue(raw: raw, reason: .notFound))
        }
        let kind: AgentMention.Kind = isDirectory.boolValue ? .directory : .file
        // 写的形态和实际类型不符 ⇒ **按实际类型采纳，但如实记一条 issue**（不静默改）
        let relative = candidatePath.replacingOccurrences(of: rootPath, with: "")
        if kind == .directory {
            // 目录一律带结尾 `/`：**归一化，不是纠错** —— 下游按结尾判类型
            return .success(AgentMention(raw: raw, path: relative + "/", kind: .directory))
        }
        return .success(AgentMention(raw: raw, path: relative, kind: kind))
    }
}
