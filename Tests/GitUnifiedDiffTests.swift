import XCTest
@testable import DoyahCore

/// `FR-STD-WS-VCS-001` 的**差异投影**判据（`git diff` 原文 ⇒ 可画的逐行结构）。
///
/// 这一族的重点是两件最容易写错的事：
///   ① **分段边界由 `@@` 的计数决定**，不是「遇到 `diff --git` 就翻页」——
///      否则 hunk 正文里一行以 `++` 开头的内容会被当成文件头；
///   ② **行号由两个游标推进**，`\ No newline at end of file` 只标属性、不推游标。
final class GitUnifiedDiffTests: XCTestCase {

    /// 一段最普通的两文件差异（改一行 + 加一行）。
    private let sample = """
    diff --git a/Sources/A.swift b/Sources/A.swift
    index 1111111..2222222 100644
    --- a/Sources/A.swift
    +++ b/Sources/A.swift
    @@ -1,4 +1,5 @@
     line one
    -line two
    +line two changed
    +line two and a half
     line three
     line four
    """

    // MARK: - 基本形状

    func testParsesHunkWithLineNumbers() {
        let document = GitUnifiedDiff.parse(sample)
        XCTAssertEqual(document.files.count, 1)
        guard let file = document.files.first, let hunk = file.hunks.first else {
            return XCTFail("应当解析出一个文件一段")
        }
        XCTAssertEqual(file.displayPath, "Sources/A.swift")
        XCTAssertEqual(hunk.oldStart, 1)
        XCTAssertEqual(hunk.oldCount, 4)
        XCTAssertEqual(hunk.newStart, 1)
        XCTAssertEqual(hunk.newCount, 5)
        XCTAssertEqual(hunk.lines.count, 6)
        XCTAssertEqual(hunk.lines.map(\.kind), [.context, .removed, .added, .added, .context, .context])
        // 行号：上下文与删除行走旧文游标，新增行走新文游标。
        XCTAssertEqual(hunk.lines[0].oldNumber, 1)
        XCTAssertEqual(hunk.lines[0].newNumber, 1)
        XCTAssertEqual(hunk.lines[1].oldNumber, 2)
        XCTAssertNil(hunk.lines[1].newNumber)
        XCTAssertEqual(hunk.lines[2].oldNumber, nil)
        XCTAssertEqual(hunk.lines[2].newNumber, 2)
        XCTAssertEqual(hunk.lines[3].newNumber, 3)
        XCTAssertEqual(hunk.lines[4].oldNumber, 3)
        XCTAssertEqual(hunk.lines[4].newNumber, 4)
        XCTAssertEqual(hunk.lines[5].newNumber, 5)
        XCTAssertEqual(hunk.lines[2].text, "line two changed", "正文不许带前缀符号")
        XCTAssertEqual(file.addedCount, 2)
        XCTAssertEqual(file.removedCount, 1)
        XCTAssertEqual(document.addedTotal, 2)
        XCTAssertEqual(document.removedTotal, 1)
    }

    /// **本族最关键的一条**：hunk 正文里以 `++` / `--` / `diff --git` 开头的内容行仍是正文。
    /// 按前缀认头会把它们当成文件头，随后整段差异错位（行号全错、内容跑进别的文件）。
    func testContentThatLooksLikeHeadersStaysContent() {
        let text = """
        diff --git a/notes.md b/notes.md
        --- a/notes.md
        +++ b/notes.md
        @@ -1,3 +1,3 @@
        --- not a file header
        +++ also not a file header
        diff --git a/fake b/fake
        """
        let document = GitUnifiedDiff.parse(text)
        XCTAssertEqual(document.files.count, 1, "正文里的 `diff --git` 不许开出一个新文件")
        guard let hunk = document.files.first?.hunks.first, hunk.lines.count == 3 else {
            // 先断言条数再按下标取：判红时**不许把这个用例自己变成一次崩溃**
            // （崩溃会让同一批后面的用例全都不执行，反例验证会看不出它们红没红）。
            return XCTFail("应当正好 3 行正文，实际 \(document.files.first?.hunks.first?.lines.count ?? -1)")
        }
        XCTAssertEqual(hunk.lines.map(\.kind), [.removed, .added, .context])
        XCTAssertEqual(hunk.lines[0].text, "-- not a file header")
        XCTAssertEqual(hunk.lines[1].text, "++ also not a file header")
        XCTAssertEqual(hunk.lines[2].text, "diff --git a/fake b/fake")
        // 删一行 + 加一行之后两条游标都各前进一格 ⇒ 这一行上下文是旧 2 / 新 2。
        XCTAssertEqual(hunk.lines[2].oldNumber, 2)
        XCTAssertEqual(hunk.lines[2].newNumber, 2)
    }

    /// `\ No newline at end of file` 描述**上一行**：标上去，但不占一行、不推游标。
    func testNoNewlineMarkerDoesNotAdvanceCursor() {
        let text = """
        diff --git a/x.txt b/x.txt
        --- a/x.txt
        +++ b/x.txt
        @@ -1,1 +1,1 @@
        -old
        \\ No newline at end of file
        +new
        \\ No newline at end of file
        """
        let document = GitUnifiedDiff.parse(text)
        guard let hunk = document.files.first?.hunks.first else { return XCTFail("应当有分段") }
        XCTAssertEqual(hunk.lines.count, 2, "标记不是一行内容")
        XCTAssertEqual(hunk.lines[0].kind, .removed)
        XCTAssertTrue(hunk.lines[0].noNewlineAtEnd)
        XCTAssertEqual(hunk.lines[1].kind, .added)
        XCTAssertTrue(hunk.lines[1].noNewlineAtEnd)
        XCTAssertEqual(hunk.lines[1].newNumber, 1, "游标没被那条标记推走")
    }

    // MARK: - 文件级形状

    func testNewFileAndDeletedFileFlags() {
        let text = """
        diff --git a/new.txt b/new.txt
        new file mode 100644
        --- /dev/null
        +++ b/new.txt
        @@ -0,0 +1,2 @@
        +a
        +b
        diff --git a/gone.txt b/gone.txt
        deleted file mode 100644
        --- a/gone.txt
        +++ /dev/null
        @@ -1,1 +0,0 @@
        -bye
        """
        let document = GitUnifiedDiff.parse(text)
        XCTAssertEqual(document.files.count, 2)
        XCTAssertEqual(document.files[0].isNew, true)
        XCTAssertEqual(document.files[0].isDeleted, false)
        XCTAssertEqual(document.files[0].displayPath, "new.txt")
        XCTAssertEqual(document.files[0].addedCount, 2)
        XCTAssertEqual(document.files[1].isDeleted, true)
        XCTAssertEqual(document.files[1].displayPath, "gone.txt", "删掉的文件只有旧路径")
        XCTAssertEqual(document.files[1].removedCount, 1)
    }

    func testBinaryFileIsMarkedAndHasNoBody() {
        let text = """
        diff --git a/logo.png b/logo.png
        index 1111111..2222222 100644
        Binary files a/logo.png and b/logo.png differ
        """
        let document = GitUnifiedDiff.parse(text)
        XCTAssertEqual(document.files.count, 1)
        XCTAssertEqual(document.files.first?.isBinary, true)
        XCTAssertEqual(document.files.first?.hasBody, false)
        XCTAssertEqual(document.hasBinary, true)
    }

    /// 只改了名字（没有正文）：文件仍在、路径两半都在、`hasBody` 为假。
    func testRenameWithoutHunks() {
        let text = """
        diff --git a/old.swift b/new.swift
        similarity index 100%
        rename from old.swift
        rename to new.swift
        """
        let document = GitUnifiedDiff.parse(text)
        guard let file = document.files.first else { return XCTFail("改名也要有一条") }
        XCTAssertEqual(file.oldPath, "old.swift")
        XCTAssertEqual(file.newPath, "new.swift")
        XCTAssertEqual(file.displayPath, "new.swift")
        XCTAssertFalse(file.hasBody)
        XCTAssertFalse(document.hasBody)
    }

    func testMultipleFilesAreSplit() {
        let text = """
        diff --git a/a.txt b/a.txt
        --- a/a.txt
        +++ b/a.txt
        @@ -1,1 +1,1 @@
        -a
        +a2
        diff --git a/b.txt b/b.txt
        --- a/b.txt
        +++ b/b.txt
        @@ -5,1 +5,1 @@
        -b
        +b2
        """
        let document = GitUnifiedDiff.parse(text)
        XCTAssertEqual(document.files.count, 2)
        XCTAssertEqual(document.files.map(\.displayPath), ["a.txt", "b.txt"])
        XCTAssertEqual(document.files[1].hunks.first?.oldStart, 5)
    }

    /// 上限：一个巨型文件不整份进视图；超了 `truncated` 为真，行数被截。
    func testTruncatesLongFiles() {
        var lines = ["diff --git a/big.txt b/big.txt", "--- a/big.txt", "+++ b/big.txt", "@@ -1,0 +1,10 @@"]
        lines.append(contentsOf: (0..<10).map { "+row \($0)" })
        let document = GitUnifiedDiff.parse(lines.joined(separator: "\n"), maxLinesPerFile: 3)
        guard let file = document.files.first else { return XCTFail("应当有一条") }
        XCTAssertEqual(file.hunks.first?.lines.count, 3)
        XCTAssertTrue(file.truncated)
        XCTAssertTrue(document.isTruncated)
    }

    func testEmptyInputYieldsEmptyDocument() {
        XCTAssertTrue(GitUnifiedDiff.parse("").isEmpty)
        // 只有元数据、没有 `diff --git`：什么都不算（不是「一个空文件」）。
        XCTAssertTrue(GitUnifiedDiff.parse("index 111..222\n").isEmpty)
    }

    /// 非 git 的 diff 会在路径后跟制表符 + 时间戳；`/dev/null` 两向都要认。
    func testPathStrippingHandlesTabAndDevNull() {
        XCTAssertEqual(GitUnifiedDiff.stripPrefix("b/dir/x.swift"), "dir/x.swift")
        XCTAssertEqual(GitUnifiedDiff.stripPrefix("a/dir/x.swift\t2026-10-29 00:00:00"), "dir/x.swift")
        XCTAssertEqual(GitUnifiedDiff.stripPrefix("/dev/null"), "")
    }

    /// `@@ -1 +1 @@`（省掉计数 = 1）也要解析得对。
    func testHunkHeaderWithoutCounts() {
        let text = """
        diff --git a/a.txt b/a.txt
        --- a/a.txt
        +++ b/a.txt
        @@ -7 +7 @@
        -x
        +y
        """
        guard let hunk = GitUnifiedDiff.parse(text).files.first?.hunks.first else {
            return XCTFail("应当解析出分段")
        }
        XCTAssertEqual(hunk.oldStart, 7)
        XCTAssertEqual(hunk.oldCount, 1)
        XCTAssertEqual(hunk.newCount, 1)
        XCTAssertEqual(hunk.lines.first?.oldNumber, 7)
        XCTAssertEqual(hunk.lines.last?.newNumber, 7)
    }
}
