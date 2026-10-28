import XCTest
@testable import DoyahCore

/// `FR-STD-WS-VCS-001`（Git 只读与差异）的**状态投影**判据。
///
/// 这一族钉的是「界面看到的那份清单」：分支 / ahead-behind / 每个文件归哪一类 /
/// 已暂存与未暂存分开 / 认不出的行不许丢。全部喂原文，**不跑真 git**。
final class GitWorktreeStatusTests: XCTestCase {

    // MARK: - 分支与计数

    func testParsesBranchAheadBehind() {
        let porcelain = """
        ## main...origin/main [ahead 2, behind 1]
         M Sources/A.swift
        """
        guard let status = GitWorktreeStatus.parse(porcelain: porcelain) else {
            return XCTFail("应当解析出仓库状态")
        }
        XCTAssertEqual(status.branch, "main")
        XCTAssertEqual(status.ahead, 2)
        XCTAssertEqual(status.behind, 1)
        XCTAssertEqual(status.entries.count, 1)
    }

    /// 没有上游（本地分支）⇒ 0/0，不是解析失败。
    func testBranchWithoutUpstream() {
        let status = GitWorktreeStatus.parse(porcelain: "## feature/x\n M a.swift")
        XCTAssertEqual(status?.branch, "feature/x")
        XCTAssertEqual(status?.ahead, 0)
        XCTAssertEqual(status?.behind, 0)
    }

    /// 空仓库：git 给的是 `No commits yet on main` ⇒ 保留成可读形态，别当成一个叫这名字的分支。
    func testEmptyRepositoryBranch() {
        let status = GitWorktreeStatus.parse(porcelain: "## No commits yet on main\n?? a.txt")
        XCTAssertEqual(status?.branch, "NoCommits(main)")
        XCTAssertEqual(status?.entries.first?.kind, .untracked)
    }

    /// 没有分支行 ⇒ nil（不是仓库）。**不许**编一个空分支出来。
    func testNotARepositoryReturnsNil() {
        XCTAssertNil(GitWorktreeStatus.parse(porcelain: ""))
        XCTAssertNil(GitWorktreeStatus.parse(porcelain: " M a.swift\n?? b.md"))
    }

    // MARK: - 分类

    func testClassifiesTwoColumnsSeparately() {
        let porcelain = """
        ## main
        M  staged.swift
         M unstaged.swift
        MM both.swift
        ?? new.md
        """
        guard let status = GitWorktreeStatus.parse(porcelain: porcelain) else { return XCTFail("解析失败") }
        XCTAssertEqual(status.entries.map(\.path), ["both.swift", "new.md", "staged.swift", "unstaged.swift"],
                       "按路径排序（确定性）")
        let byPath = Dictionary(uniqueKeysWithValues: status.entries.map { ($0.path, $0) })
        XCTAssertTrue(byPath["staged.swift"]?.isStaged == true)
        XCTAssertFalse(byPath["staged.swift"]?.isUnstaged == true)
        XCTAssertTrue(byPath["unstaged.swift"]?.isUnstaged == true)
        XCTAssertFalse(byPath["unstaged.swift"]?.isStaged == true)
        XCTAssertTrue(byPath["both.swift"]?.isStaged == true)
        XCTAssertTrue(byPath["both.swift"]?.isUnstaged == true)
        XCTAssertTrue(byPath["new.md"]?.isUntracked == true)
        XCTAssertFalse(byPath["new.md"]?.isStaged == true, "未跟踪不算已暂存")
        XCTAssertEqual(status.stagedCount, 2)
        XCTAssertEqual(status.unstagedCount, 3)
    }

    /// 冲突七码逐条都归 `.conflicted`（它们是唯一「点开差异也解决不了」的一档）。
    func testConflictsAreAllClassified() {
        let codes = ["DD", "AU", "UD", "UA", "DU", "AA", "UU"]
        for code in codes {
            let entry = GitWorktreeStatus.entry(from: code + " f.swift")
            XCTAssertEqual(entry?.kind, .conflicted, "\(code) 应当归冲突")
            XCTAssertTrue(entry?.isConflicted == true, "\(code) 应当被判为冲突")
        }
        let porcelain = "## main\n" + codes.map { $0 + " f.swift" }.joined(separator: "\n")
        XCTAssertEqual(GitWorktreeStatus.parse(porcelain: porcelain)?.conflictCount, codes.count)
    }

    func testRenameKeepsOriginalPath() {
        guard let entry = GitWorktreeStatus.entry(from: "R  old/name.swift -> new/name.swift") else {
            return XCTFail("改名行应当解析出条目")
        }
        XCTAssertEqual(entry.kind, .renamed)
        XCTAssertEqual(entry.path, "new/name.swift")
        XCTAssertEqual(entry.originalPath, "old/name.swift")
    }

    /// 认不出的状态码：**保留**原行并标 `.unknown`，绝不当成「普通修改」丢掉。
    func testUnknownStatusIsKeptNotDropped() {
        guard let entry = GitWorktreeStatus.entry(from: "ZZ weird.swift") else {
            return XCTFail("认不出的行也不许丢")
        }
        XCTAssertEqual(entry.kind, .unknown)
        XCTAssertEqual(entry.path, "weird.swift")
        XCTAssertEqual(entry.code, "ZZ", "原码照留 —— 界面据此说「认不出的状态」")
    }

    /// git 给带空格 / 特殊字符的路径加引号：剥掉那对引号（否则界面上路径带引号）。
    func testQuotedPathIsUnquoted() {
        XCTAssertEqual(GitWorktreeStatus.entry(from: "?? \"a b.md\"")?.path, "a b.md")
        XCTAssertEqual(GitWorktreeStatus.entry(from: " M \"dir/with space/x.swift\"")?.path,
                       "dir/with space/x.swift")
    }

    /// 同一份原文解析两遍必须逐条相同（否则界面每次刷新都换顺序）。
    func testOrderIsDeterministic() {
        let porcelain = """
        ## main
         M b.swift
        ?? a.md
        A  c.swift
         D d.swift
        """
        let first = GitWorktreeStatus.parse(porcelain: porcelain)
        let second = GitWorktreeStatus.parse(porcelain: porcelain)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first?.entries.map(\.path), ["a.md", "b.swift", "c.swift", "d.swift"])
    }

    /// 上限：条目超过 `maxEntries` 只留前 N 条，**丢掉的条数如实报**（不静默截断）。
    func testEntryCapReportsOmitted() {
        let lines = (0..<(GitWorktreeStatus.maxEntries + 7)).map { " M f\($0).swift" }
        let porcelain = (["## main"] + lines).joined(separator: "\n")
        guard let status = GitWorktreeStatus.parse(porcelain: porcelain) else { return XCTFail("解析失败") }
        XCTAssertEqual(status.entries.count, GitWorktreeStatus.maxEntries)
        XCTAssertEqual(status.omitted, 7)
    }

    // MARK: - 与给模型那份摘要同源

    /// 分支那一行只有**一个解析器**：`AgentGitFacts`（给模型）与 `GitWorktreeStatus`（给界面）
    /// 读同一份原文必须同答 —— 各写一份就会一处认 ahead 一处不认。
    func testBranchHeaderSharedWithAgentFacts() {
        let samples = [
            "## main...origin/main [ahead 2, behind 1]",
            "## feature/x",
            "## No commits yet on main",
            "## HEAD (no branch)",
        ]
        for head in samples {
            let status = GitWorktreeStatus.parse(porcelain: head + "\n M a.swift")
            let facts = AgentGitFacts.parse(porcelain: head + "\n M a.swift")
            XCTAssertEqual(status?.branch, facts?.branch, "分支名两处必须同答：\(head)")
            XCTAssertEqual(status?.ahead, facts?.ahead, "ahead 两处必须同答：\(head)")
            XCTAssertEqual(status?.behind, facts?.behind, "behind 两处必须同答：\(head)")
        }
    }

    /// 干净工作区：有分支行、没有条目 ⇒ `isClean`，不是「读不到」。
    func testCleanTreeIsCleanNotFailure() {
        let status = GitWorktreeStatus.parse(porcelain: "## main...origin/main")
        XCTAssertEqual(status?.isClean, true)
        XCTAssertEqual(status?.branch, "main")
    }
}
