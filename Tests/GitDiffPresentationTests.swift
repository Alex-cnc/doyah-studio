import XCTest
@testable import DoyahCore

/// `FR-STD-WS-VCS-002` 的**呈现面**判据：折叠上下文 + 按需渲染（万行级）。
///
/// 三条最容易写歪的：
///   ① 把 `+` / `-` 也折起来（那等于把差异藏了）；
///   ② 折叠锚按序号记（重取一次差异，折起来的就变成另一段）；
///   ③ 「还有 N 行」与「折了几行」混成一个数（界面上说不清停在哪）。
final class GitDiffPresentationTests: XCTestCase {

    /// 用真实 `git diff` 原文造样本（行号由解析器推进，别在夹具里手写行号）。
    private func file(_ body: [(String, String)], name: String = "x.txt") -> GitDiffFile {
        let oldCount = body.filter { $0.0 != "+" }.count
        let newCount = body.filter { $0.0 != "-" }.count
        var lines = ["diff --git a/\(name) b/\(name)",
                     "--- a/\(name)",
                     "+++ b/\(name)",
                     "@@ -1,\(oldCount) +1,\(newCount) @@"]
        lines.append(contentsOf: body.map { "\($0.0)\($0.1)" })
        let document = GitUnifiedDiff.parse(lines.joined(separator: "\n"))
        return document.files[0]
    }

    private func contextRun(_ count: Int, prefix: String = "ctx") -> [(String, String)] {
        (1...count).map { (" ", "\(prefix) \($0)") }
    }

    /// 改一行 + 一段长上下文 + 再改一行。
    private func twoChanges(context: Int) -> GitDiffFile {
        file([("-", "old one"), ("+", "new one")] + contextRun(context) + [("-", "old two"), ("+", "new two")])
    }

    // MARK: - 折叠

    func testLongContextRunFoldsWithCorrectHiddenCount() {
        let presentation = GitDiffPresentation.make(
            for: twoChanges(context: 8),
            options: GitDiffDisplayOptions(keepContext: 3, pageLimit: 10_000)
        )
        let folds = presentation.rows.compactMap { row -> GitDiffFold? in
            if case .fold(let fold) = row { return fold }
            return nil
        }
        XCTAssertEqual(folds.count, 1)
        XCTAssertEqual(folds.first?.hiddenCount, 2, "8 行上下文、每端留 3 ⇒ 中间折 2 行")
        XCTAssertEqual(presentation.foldCount, 1)
        XCTAssertEqual(presentation.foldedLineCount, 2)
        // 露出来的上下文恰好 6 行（两端各 3）。
        let visibleContext = presentation.rows.filter {
            if case .line(let line) = $0 { return line.kind == .context }
            return false
        }
        XCTAssertEqual(visibleContext.count, 6)
    }

    func testShortContextRunIsNotFolded() {
        // 6 行 = 两端各 3 ⇒ 没有该折的部分。
        let presentation = GitDiffPresentation.make(for: twoChanges(context: 6),
                                                    options: GitDiffDisplayOptions(keepContext: 3))
        XCTAssertEqual(presentation.foldCount, 0)
        XCTAssertEqual(presentation.foldedLineCount, 0)
    }

    func testChangedLinesAreNeverFolded() {
        let presentation = GitDiffPresentation.make(for: twoChanges(context: 8),
                                                    options: GitDiffDisplayOptions(keepContext: 3))
        let added = presentation.rows.filter {
            if case .line(let line) = $0 { return line.kind == .added }
            return false
        }
        let removed = presentation.rows.filter {
            if case .line(let line) = $0 { return line.kind == .removed }
            return false
        }
        XCTAssertEqual(added.count, 2)
        XCTAssertEqual(removed.count, 2)
    }

    func testZeroKeepFoldsTheWholeRun() {
        let presentation = GitDiffPresentation.make(for: twoChanges(context: 8),
                                                    options: GitDiffDisplayOptions(keepContext: 0))
        let fold = presentation.rows.compactMap { row -> GitDiffFold? in
            if case .fold(let value) = row { return value }
            return nil
        }.first
        XCTAssertEqual(fold?.hiddenCount, 8)
        XCTAssertEqual(presentation.foldCount, 1)
    }

    // MARK: - 展开

    func testExpandingAFoldShowsEveryLineAndRemovesTheFoldRow() {
        let file = twoChanges(context: 8)
        let folded = GitDiffPresentation.make(for: file, options: GitDiffDisplayOptions(keepContext: 3))
        guard case .fold(let fold)? = folded.rows.first(where: {
            if case .fold = $0 { return true }
            return false
        }) else { return XCTFail("长上下文段应当折起来") }

        let expanded = GitDiffPresentation.make(
            for: file,
            options: GitDiffDisplayOptions(keepContext: 3, expandedFolds: [fold.id])
        )
        XCTAssertEqual(expanded.foldCount, 0)
        XCTAssertEqual(expanded.rows.count, folded.rows.count + fold.hiddenCount - 1,
                       "展开 = 少一枚折叠行、多回那些被折的行")
        let visibleContext = expanded.rows.filter {
            if case .line(let line) = $0 { return line.kind == .context }
            return false
        }
        XCTAssertEqual(visibleContext.count, 8)
    }

    func testExpandingOneFoldLeavesTheOtherFolded() {
        let file = file([("-", "old head"), ("+", "new head")]
                        + contextRun(8, prefix: "first")
                        + [("-", "old mid"), ("+", "new mid")]
                        + contextRun(8, prefix: "second")
                        + [("-", "old tail"), ("+", "new tail")])
        let folded = GitDiffPresentation.make(for: file, options: GitDiffDisplayOptions(keepContext: 3))
        let folds: [GitDiffFold] = folded.rows.compactMap {
            if case .fold(let value) = $0 { return value }
            return nil
        }
        XCTAssertEqual(folds.count, 2)

        let half = GitDiffPresentation.make(
            for: file,
            options: GitDiffDisplayOptions(keepContext: 3, expandedFolds: [folds[0].id])
        )
        XCTAssertEqual(half.foldCount, 1, "只点开了一段")
        XCTAssertEqual(half.foldedLineCount, folds[1].hiddenCount)
    }

    // MARK: - 折叠锚

    func testFoldAnchorIsStableAcrossTwoParsesOfTheSameDiff() {
        let first = GitDiffPresentation.make(for: twoChanges(context: 8))
        let second = GitDiffPresentation.make(for: twoChanges(context: 8))
        func ids(_ presentation: GitDiffFilePresentation) -> [String] {
            presentation.rows.compactMap {
                if case .fold(let fold) = $0 { return fold.id }
                return nil
            }
        }
        XCTAssertFalse(ids(first).isEmpty)
        XCTAssertEqual(ids(first), ids(second), "同一份差异重取两次，折起来的必须是同一段")
    }

    func testFoldAnchorChangesWhenTheRunChanges() {
        func fold(_ context: Int) -> GitDiffFold? {
            GitDiffPresentation.make(for: twoChanges(context: context)).rows.compactMap {
                if case .fold(let value) = $0 { return value }
                return nil
            }.first
        }
        let short = fold(8)
        let long = fold(12)
        XCTAssertNotNil(short)
        XCTAssertNotNil(long)
        XCTAssertNotEqual(short?.id, long?.id, "这一段的长短变了，锚就该跟着变")
        XCTAssertNotEqual(short?.hiddenCount, long?.hiddenCount)
    }

    // MARK: - 按需渲染

    func testPageLimitTruncatesAndReportsHiddenRows() {
        let file = twoChanges(context: 8)
        let full = GitDiffPresentation.make(for: file, options: GitDiffDisplayOptions(pageLimit: 10_000))
        let paged = GitDiffPresentation.make(for: file, options: GitDiffDisplayOptions(pageLimit: 4))

        XCTAssertEqual(full.totalRows, paged.totalRows, "分页不改变总行数")
        XCTAssertEqual(paged.rows.count, 5, "4 行正文 + 1 行「还有 N 行」")
        guard case .more(let hidden)? = paged.rows.last else { return XCTFail("末尾应当是「还有 N 行」") }
        XCTAssertEqual(hidden, full.totalRows - 4)
        XCTAssertEqual(paged.hiddenRows, hidden)
        XCTAssertEqual(full.hiddenRows, 0)
    }

    func testPageLimitLargerThanDocumentShowsEverything() {
        let presentation = GitDiffPresentation.make(for: twoChanges(context: 8),
                                                    options: GitDiffDisplayOptions(pageLimit: 1_000))
        XCTAssertFalse(presentation.rows.contains {
            if case .more = $0 { return true }
            return false
        })
        XCTAssertEqual(presentation.hiddenRows, 0)
        XCTAssertEqual(presentation.rows.count, presentation.totalRows)
    }

    func testPageLimitAlwaysAllowsAtLeastOneRow() {
        let presentation = GitDiffPresentation.make(for: twoChanges(context: 8),
                                                    options: GitDiffDisplayOptions(pageLimit: 0))
        XCTAssertEqual(presentation.rows.count, 2, "1 行正文 + 1 行「还有 N 行」")
        XCTAssertEqual(presentation.hiddenRows, presentation.totalRows - 1)
    }

    /// 万行级：只生成一页，视图里不会出现一万个 `Text`。
    func testTenThousandLineDiffOnlyGeneratesOnePage() {
        var body: [(String, String)] = []
        for index in 1...5_000 {
            body.append(("-", "old line \(index)"))
            body.append(("+", "new line \(index)"))
        }
        let presentation = GitDiffPresentation.make(for: file(body))
        XCTAssertEqual(presentation.rows.count, GitDiffPresentation.defaultPageLimit + 1)
        XCTAssertEqual(presentation.totalRows, 1 + 10_000, "分段头 + 一万行正文")
        XCTAssertEqual(presentation.hiddenRows, presentation.totalRows - GitDiffPresentation.defaultPageLimit)
    }

    // MARK: - 空面

    func testFileWithoutHunksHasNoRows() {
        let document = GitUnifiedDiff.parse("""
        diff --git a/bin.png b/bin.png
        index 1111111..2222222 100644
        Binary files a/bin.png and b/bin.png differ
        """)
        let presentation = GitDiffPresentation.make(for: document.files[0])
        XCTAssertTrue(presentation.rows.isEmpty)
        XCTAssertEqual(presentation.totalRows, 0)
        XCTAssertEqual(presentation.hiddenRows, 0)
    }
}
