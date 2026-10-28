import Foundation

// `FR-STD-WS-VCS-001`（Git 只读与差异）的**状态投影**。
//
// 盘上已有的 `AgentGitFacts` 是**给模型看的一行摘要**（分支 + 改动条目 + ahead/behind，40 条封顶）；
// 这个文件是**给人看的那份**：界面上要按类别分组、要能点开一个文件看差异、要说清「已暂存 / 未暂存 /
// 未跟踪 / 有冲突」。两者读的是**同一种原文**（`git status --porcelain=v1 --branch`），
// 所以分支那一行的解析收在这里（`GitBranchHeader`），`AgentGitFacts` 也走它 —— 一处解析，两处消费。
//
// 三条硬口径：
//   ① **只解析，不跑 git**：入参是原文 ⇒ 判据不需要真仓库、也不会因为机器上没装 git 而静默变绿；
//   ② **不认识的行不许丢也不许编**：状态码认不出 ⇒ `kind = .unknown` 且**原码照留**，
//      界面上显示「认不出的状态」，而不是把它当成普通修改（那会让人以为改动被看见了）；
//   ③ **顺序确定**：同一份原文解析两遍必须逐条相同（按路径 → 状态码排序），
//      否则界面每次刷新都换一版顺序，用户会以为改动在跳。

/// 一条改动属于哪一类（界面按它上色 / 给一句人话；文案键在语言表，Core 不写中文）。
public enum GitChangeKind: String, Equatable, Sendable {

    case untracked
    case added
    case modified
    case deleted
    case renamed
    case copied
    case conflicted
    case typeChanged
    case unknown

    /// 语言表里的标签键（`gitChange*` 一族）。
    public var labelKey: LKey {
        switch self {
        case .untracked: return .gitChangeUntracked
        case .added: return .gitChangeAdded
        case .modified: return .gitChangeModified
        case .deleted: return .gitChangeDeleted
        case .renamed: return .gitChangeRenamed
        case .copied: return .gitChangeCopied
        case .conflicted: return .gitChangeConflicted
        case .typeChanged: return .gitChangeTypeChanged
        case .unknown: return .gitChangeUnknown
        }
    }

    /// 这一档在列表里是否要醒目（冲突是唯一「点开看差异也解决不了」的那一档）。
    public var isBlocking: Bool { self == .conflicted }
}

/// 一个改动文件（`git status --porcelain=v1` 的一行）。
public struct GitWorktreeEntry: Equatable, Sendable, Identifiable {

    /// 暂存区状态码（porcelain 的第一列；`?` = 未跟踪）。
    public var indexStatus: Character
    /// 工作区状态码（porcelain 的第二列）。
    public var worktreeStatus: Character
    /// 相对仓库根的路径（**原样**，不拼前缀）。
    public var path: String
    /// 重命名 / 复制时的源路径（其余情况为 nil）。
    public var originalPath: String?
    /// 归类（由两列状态码推出，见 `classify`）。
    public var kind: GitChangeKind

    public init(indexStatus: Character, worktreeStatus: Character, path: String,
                originalPath: String? = nil, kind: GitChangeKind) {
        self.indexStatus = indexStatus
        self.worktreeStatus = worktreeStatus
        self.path = path
        self.originalPath = originalPath
        self.kind = kind
    }

    /// 列表行的身份：同一路径在暂存 / 未暂存两侧各算一条（`M ` 与 ` M` 是两件事）。
    public var id: String { path + "|" + String(indexStatus) + String(worktreeStatus) }

    /// 两列状态码原样（`M ` / ` M` / `??` / `UU` …）。
    public var code: String { String(indexStatus) + String(worktreeStatus) }

    /// 暂存区有变化（`?` = 未跟踪，不算「已暂存」）。
    public var isStaged: Bool { indexStatus != " " && indexStatus != "?" }

    /// 工作区有变化（未跟踪也算「还没进暂存」的那一侧）。
    public var isUnstaged: Bool { worktreeStatus != " " }

    /// 未跟踪：`??`（新增未纳入版本管理）。
    public var isUntracked: Bool { indexStatus == "?" }

    /// 冲突：porcelain 的七个合并态码（`DD` / `AU` / `UD` / `UA` / `DU` / `AA` / `UU`）。
    public var isConflicted: Bool {
        let pairs: Set<String> = ["DD", "AU", "UD", "UA", "DU", "AA", "UU"]
        return pairs.contains(code)
    }

    /// 由两列状态码归类。**顺序即优先级**：冲突 > 未跟踪 > 重命名 > 复制 > 新增 > 删除 > 类型变 > 修改。
    public static func classify(index: Character, worktree: Character) -> GitChangeKind {
        let pair = String(index) + String(worktree)
        let conflicts: Set<String> = ["DD", "AU", "UD", "UA", "DU", "AA", "UU"]
        if conflicts.contains(pair) { return .conflicted }
        if index == "?" && worktree == "?" { return .untracked }
        if index == "R" || worktree == "R" { return .renamed }
        if index == "C" || worktree == "C" { return .copied }
        if index == "A" || worktree == "A" { return .added }
        if index == "D" || worktree == "D" { return .deleted }
        if index == "T" || worktree == "T" { return .typeChanged }
        if index == "M" || worktree == "M" { return .modified }
        return .unknown
    }
}

/// 分支那一行（`## …`）的解析结果。
///
/// 抽出来的理由：`AgentGitFacts`（给模型）与 `GitWorktreeStatus`（给界面）都要它，
/// 各写一份就是「同一个分支名两处说法」—— 迟早一处认 `ahead` 一处不认。
public enum GitBranchHeader {

    /// 解析 `## ` 之后的正文。认得的形状：
    ///   `main...origin/main [ahead 2, behind 1]`
    ///   `main`（没有上游）
    ///   `No commits yet on main`（空仓库）
    ///   `HEAD (no branch)`（detached，原样保留）
    public static func parse(_ head: String) -> (branch: String, ahead: Int, behind: Int) {
        var branch = head
        var ahead = 0
        var behind = 0
        if let bracket = head.range(of: " [") {
            branch = String(head[head.startIndex..<bracket.lowerBound])
            let tail = String(head[bracket.upperBound...]).replacingOccurrences(of: "]", with: "")
            for part in tail.split(separator: ",") {
                let piece = part.trimmingCharacters(in: .whitespaces)
                if piece.hasPrefix("ahead ") { ahead = Int(piece.dropFirst("ahead ".count)) ?? 0 }
                if piece.hasPrefix("behind ") { behind = Int(piece.dropFirst("behind ".count)) ?? 0 }
            }
        }
        // `main...origin/main` ⇒ 只要本地那半段。
        if let dots = branch.range(of: "...") {
            branch = String(branch[branch.startIndex..<dots.lowerBound])
        }
        // 空仓库：原样留一句可读的（`NoCommits(main)`），别让它看起来像个分支名。
        if branch.hasPrefix("No commits yet on ") {
            branch = "NoCommits(" + String(branch.dropFirst("No commits yet on ".count)) + ")"
        }
        return (branch, ahead, behind)
    }
}

/// 一次 `git status --porcelain=v1 --branch` 的完整投影（界面用；摘要给模型的那份是 `AgentGitFacts`）。
public struct GitWorktreeStatus: Equatable, Sendable {

    /// 分支名（detached 时是 git 自己那句）。
    public var branch: String
    /// 相对上游领先几个提交（没有上游 = 0）。
    public var ahead: Int
    /// 落后几个提交。
    public var behind: Int
    /// 改动条目（**已排序**：路径 → 状态码，确定性）。
    public var entries: [GitWorktreeEntry]
    /// 因为上限被丢掉的条目数（0 = 全在）。
    public var omitted: Int

    public init(branch: String, ahead: Int = 0, behind: Int = 0,
                entries: [GitWorktreeEntry] = [], omitted: Int = 0) {
        self.branch = branch
        self.ahead = ahead
        self.behind = behind
        self.entries = entries
        self.omitted = omitted
    }

    /// 列表上限。比 `AgentGitFacts` 的 40 大得多：界面那一侧可以滚，但也不该把一个几万条改动的
    /// 仓库整份喂给 SwiftUI（一次布局就是几万行视图）。
    public static let maxEntries = 400

    /// 工作区干净吗（没有任何条目）。
    public var isClean: Bool { entries.isEmpty }

    /// 已暂存条目数。
    public var stagedCount: Int { entries.filter(\.isStaged).count }

    /// 未暂存条目数（含未跟踪）。
    public var unstagedCount: Int { entries.filter(\.isUnstaged).count }

    /// 冲突条目数。
    public var conflictCount: Int { entries.filter(\.isConflicted).count }

    /// 解析 `git status --porcelain=v1 --branch` 原文。**没有分支行 ⇒ nil（不是仓库）**，
    /// 不编一个空分支出来 —— 界面据此说「这里不是仓库」而不是「分支为空」。
    public static func parse(porcelain: String) -> GitWorktreeStatus? {
        let lines = porcelain.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let branchLine = lines.first(where: { $0.hasPrefix("## ") }) else { return nil }
        let header = GitBranchHeader.parse(String(branchLine.dropFirst(3)))
        let parsed = entries(from: lines)
        return GitWorktreeStatus(branch: header.branch, ahead: header.ahead, behind: header.behind,
                                 entries: Array(parsed.prefix(maxEntries)),
                                 omitted: max(0, parsed.count - maxEntries))
    }

    /// 条目行（去掉分支行）⇒ 条目，**已排序**。
    public static func entries(from lines: [String]) -> [GitWorktreeEntry] {
        var result: [GitWorktreeEntry] = []
        for line in lines where !line.hasPrefix("## ") {
            if line.isEmpty { continue }
            guard let entry = entry(from: line) else { continue }
            result.append(entry)
        }
        result.sort { lhs, rhs in
            if lhs.path != rhs.path { return lhs.path < rhs.path }
            return lhs.code < rhs.code
        }
        return result
    }

    /// 一行 ⇒ 一个条目。认不出的形状**不丢**：归类成 `.unknown` 且原行进路径，
    /// 让人看见「有这么一条、但程序不认识它」。
    public static func entry(from line: String) -> GitWorktreeEntry? {
        let chars = Array(line)
        guard chars.count >= 4 else {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            return GitWorktreeEntry(indexStatus: " ", worktreeStatus: " ", path: trimmed, kind: .unknown)
        }
        let index = chars[0]
        let worktree = chars[1]
        var path = String(chars[3...])
        var original: String?
        // 重命名 / 复制：`R  old -> new`。取**第一处** ` -> `：路径里带这个串的情形极罕见，
        // 而取最后一处会把 `a -> b -> c` 的源路径劈错。
        let kind = GitWorktreeEntry.classify(index: index, worktree: worktree)
        if kind == .renamed || kind == .copied, let arrow = path.range(of: " -> ") {
            original = unquote(String(path[path.startIndex..<arrow.lowerBound]))
            path = String(path[arrow.upperBound...])
        }
        return GitWorktreeEntry(indexStatus: index, worktreeStatus: worktree,
                                path: unquote(path), originalPath: original, kind: kind)
    }

    /// 去掉 git 给特殊路径加的那对引号。
    ///
    /// **边界如实登记**：只剥引号并还原 `\"` 与 `\\`，**不解释** C 风格转义（`\t` / `\303\251`）。
    /// 探针那一侧用 `-c core.quotePath=false` 让 git 直接给原样 UTF-8，所以正常路径不会走到这里；
    /// 走到这里说明路径里真的有控制字符 —— 那时显示的是它的转义形态，比丢一条改动好。
    static func unquote(_ text: String) -> String {
        guard text.count >= 2, text.hasPrefix("\""), text.hasSuffix("\"") else { return text }
        let inner = String(text.dropFirst().dropLast())
        return inner
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}
