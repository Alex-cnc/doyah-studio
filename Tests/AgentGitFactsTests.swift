import XCTest
@testable import DoyahCore

/// `FR-AGT-KNOW-CTX-001`（项目上下文自动带上：工作区结构 / 分支 / 未提交改动）的机械判据。
///
/// 这一批补的是**仓库视角**（此前上下文只有编辑器视角：文件、选中、终端、目录条目）。
/// 判据两条线：
///   · 解析线 —— `git status --porcelain=v1 --branch` 原文 ⇒ 分支 / 改动 / ahead / behind（不跑真 git）；
///   · 组装线 —— 三样都要进上下文，且**只带摘要**（分支+改动清单，不带 diff 正文）。

final class AgentGitFactsTests: XCTestCase {

    // MARK: - 解析线

    func testParsesBranchAheadBehindAndChanges() {
        let porcelain = """
        ## main...origin/main [ahead 2, behind 1]
         M Sources/A.swift
        ?? Docs/B.md
        M  Sources/C.swift
        """
        guard let facts = AgentGitFacts.parse(porcelain: porcelain) else { return XCTFail("应当解析出仓库状态") }
        XCTAssertEqual(facts.branch, "main")
        XCTAssertEqual(facts.ahead, 2)
        XCTAssertEqual(facts.behind, 1)
        XCTAssertEqual(facts.changed, [" M Sources/A.swift", "?? Docs/B.md", "M  Sources/C.swift"],
                       "状态码原样、按字符序排序（两次解析必须一致）")
        XCTAssertEqual(facts.omittedChanges, 0)
    }

    /// 没有上游（本地分支）⇒ ahead/behind 都是 0，不是「解析失败」。
    func testBranchWithoutUpstreamHasZeroCounts() {
        let facts = AgentGitFacts.parse(porcelain: "## feature/x\n M a.swift")
        XCTAssertEqual(facts?.branch, "feature/x")
        XCTAssertEqual(facts?.ahead, 0)
        XCTAssertEqual(facts?.behind, 0)
        XCTAssertEqual(facts?.changed.count, 1)
    }

    /// 没有分支行 ⇒ `nil`（不是仓库），**不许**编一个空分支出来。
    func testNoBranchLineIsNotARepository() {
        XCTAssertNil(AgentGitFacts.parse(porcelain: ""))
        XCTAssertNil(AgentGitFacts.parse(porcelain: " M a.swift"))
    }

    /// 全新仓库：`## No commits yet on main` 要变成可读形态，而不是留一句英文原文。
    func testNoCommitsYetIsNormalised() {
        XCTAssertEqual(AgentGitFacts.parse(porcelain: "## No commits yet on main")?.branch,
                       "NoCommits(main)")
    }

    /// 脏树上限：超过 40 条就截，**如实报丢了几条**（不静默）。
    func testChangeListIsCappedAndOmissionsAreCounted() {
        let lines = (0..<45).map { " M f\($0).swift" }.joined(separator: "\n")
        let facts = AgentGitFacts.parse(porcelain: "## main\n" + lines)
        XCTAssertEqual(facts?.changed.count, AgentGitFacts.maxEntries)
        XCTAssertEqual(facts?.omittedChanges, 45 - AgentGitFacts.maxEntries)
        XCTAssertTrue(facts?.summary.contains("omitted:5") ?? false, "\(facts?.summary ?? "nil")")
    }

    /// 摘要是机器可搜的形状（日志 / 过程面用），不含中文、不含换行。
    func testSummaryShapeIsMachineReadable() {
        let facts = AgentGitFacts.parse(porcelain: "## main...origin/main [ahead 1]\n?? x.md")!
        XCTAssertEqual(facts.summary, "branch:main · changed:1 · ahead:1")
    }

    // MARK: - 组装线（三样都进上下文）

    func testWorkspaceContextCarriesGitStateBeforeDirectory() {
        let git = AgentGitFacts(branch: "main", changed: [" M a.swift"], ahead: 1)
        let facts = AgentWorkspaceFacts(workspacePath: "/w", workspaceEntries: ["A.swift"],
                                        git: git)
        let refs = AgentWorkspaceContext.references(from: facts)
        guard case let .gitState(branch, changed, ahead, behind) = refs.first else {
            return XCTFail("仓库状态应当排在第一个（比目录更影响第一步动作），实际 \(refs)")
        }
        XCTAssertEqual(branch, "main")
        XCTAssertEqual(changed, [" M a.swift"])
        XCTAssertEqual(ahead, 1)
        XCTAssertEqual(behind, 0)
    }

    /// 渲染：只带摘要（分支 / 条数 / 清单），**不带 diff 正文**。
    func testRenderedSectionIsSummaryNotDiff() {
        let ref = AgentContextReference.gitState(branch: "main",
                                                 changed: [" M a.swift", "?? b.md"],
                                                 ahead: 0, behind: 0)
        let section = AgentContextAssembler.section(for: ref, limits: AgentContextLimits())
        XCTAssertTrue(section.body.contains("branch:main"), section.body)
        XCTAssertTrue(section.body.contains("changed:2"), section.body)
        XCTAssertTrue(section.body.contains(" M a.swift"), section.body)
        XCTAssertFalse(section.body.contains("+"), "不许把 diff 塞进上下文：\(section.body)")
    }

    /// 没有仓库信息时**这一段不出现**（不给模型塞空壳）。
    func testNoGitFactsMeansNoSection() {
        let refs = AgentWorkspaceContext.references(from: AgentWorkspaceFacts(workspacePath: "/w"))
        XCTAssertFalse(refs.contains { if case .gitState = $0 { return true }; return false })
    }
}
