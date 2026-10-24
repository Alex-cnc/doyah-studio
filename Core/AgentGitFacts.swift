import Foundation

// `FR-AGT-KNOW-CTX-001`（项目上下文自动带上：**工作区结构 / 分支 / 未提交改动** 三样）。
//
// 此前只有「文件 / 选中 / 终端 / 目录条目」—— 都是**编辑器视角**。模型真正缺的是**仓库视角**：
// 我现在在哪个分支上、工作树脏不脏、跟上游差几个提交。少了这三样，它会对着改了半截的树
// 给出「已经完成」的结论（然后被完成判据打回，白烧一跳）。
//
// 三条硬口径：
//   ① **只解析，不跑 git**：入参是 `git status --porcelain=v1 --branch` 的原文 ——
//      这样判据不需要真仓库、也不会因为机器上没装 git 而静默降级；
//   ② **只带摘要**：分支名 + 改动条目（截断上限内）+ ahead/behind，**不带 diff 正文**
//      （diff 会让上下文在开跑第一秒就爆预算，而模型要的是「我站哪儿、脏不脏」）；
//   ③ **不认识的行不许丢也不许编**：认不出的状态码原样保留（`? <原始行>`），
//      宁可让模型看见一条怪行，也不许静默吞掉一个被改过的文件。

/// 仓库状态摘要（`git status --porcelain=v1 --branch` 的解析结果）。
public struct AgentGitFacts: Equatable, Sendable {

    /// 分支名；detached 时是 `HEAD (detached at <sha>)` 那样的可读形态。
    public var branch: String
    /// 改动条目（**已排序**：先按状态码、再按路径，保证两次解析结果一致）。
    /// 形状：`M  Sources/A.swift`（状态码原样 + 空格 + 路径）。
    public var changed: [String]
    /// 相对上游领先几个提交；没有上游 = 0。
    public var ahead: Int
    /// 落后几个提交；没有上游 = 0。
    public var behind: Int

    public init(branch: String, changed: [String] = [], ahead: Int = 0, behind: Int = 0) {
        self.branch = branch
        self.changed = changed
        self.ahead = ahead
        self.behind = behind
    }

    /// 改动条目上限（超出部分丢弃并在 `truncatedCount` 里如实报数）。
    public static let maxEntries = 40

    /// 解析 `git status --porcelain=v1 --branch` 的原文。空串 / 没有分支行 ⇒ `nil`（不是仓库）。
    ///
    /// 认得的形状：
    ///   `## main...origin/main [ahead 2, behind 1]`
    ///   `## No commits yet on main`
    ///   `## HEAD (no branch)`
    ///   `XY path`（`??` 未跟踪、` M` 已改未暂存、`M ` 已暂存 …）
    public static func parse(porcelain: String) -> AgentGitFacts? {
        let lines = porcelain.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard let branchLine = lines.first(where: { $0.hasPrefix("## ") }) else { return nil }
        let head = String(branchLine.dropFirst(3))

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
        // `main...origin/main` ⇒ 只要本地那半段；`No commits yet on main` 原样留一句可读的。
        if let dots = branch.range(of: "...") {
            branch = String(branch[branch.startIndex..<dots.lowerBound])
        }
        if branch.hasPrefix("No commits yet on ") {
            branch = "NoCommits(" + String(branch.dropFirst("No commits yet on ".count)) + ")"
        }

        var changed: [String] = []
        for line in lines where !line.hasPrefix("## ") {
            guard line.count > 3 else { changed.append(line); continue }
            let code = String(line.prefix(2))
            let path = String(line.dropFirst(3))
            changed.append(code + " " + path)
        }
        changed.sort()

        var facts = AgentGitFacts(branch: branch, changed: Array(changed.prefix(maxEntries)),
                                  ahead: ahead, behind: behind)
        facts.omittedChanges = max(0, changed.count - maxEntries)
        return facts
    }

    /// 因为上限被丢掉的改动条目数（0 = 全在）。
    public var omittedChanges: Int = 0

    /// 一句话摘要（给日志 / 过程面；**不进模型上下文** —— 上下文走 `AgentContextReference`）。
    public var summary: String {
        var parts = ["branch:\(branch)", "changed:\(changed.count)"]
        if omittedChanges > 0 { parts.append("omitted:\(omittedChanges)") }
        if ahead > 0 { parts.append("ahead:\(ahead)") }
        if behind > 0 { parts.append("behind:\(behind)") }
        return parts.joined(separator: " · ")
    }
}
