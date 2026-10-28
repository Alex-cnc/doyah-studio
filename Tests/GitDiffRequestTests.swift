import XCTest
@testable import DoyahCore

/// `FR-STD-WS-VCS-002` 的**请求面**判据：忽略空白 / 上下文行数怎么变成 git 参数。
///
/// 这一族的重点是那一条最容易写错的：**开关必须插在 `--` 之前**。
/// 插在后面 git 会把 `-w` 当成一个叫 `-w` 的路径 —— 编译期不响、单测不响，
/// 界面上只显示成「差异读不出来」。
final class GitDiffRequestTests: XCTestCase {

    private let base = ["diff", "--no-color", "--no-ext-diff", "--", "Sources/A.swift"]

    // MARK: - 开关面

    func testDefaultRequestAddsNothingButGitDefaults() {
        let request = GitDiffRequest()
        XCTAssertFalse(request.ignoresWhitespace)
        XCTAssertEqual(request.contextLines, GitDiffRequest.defaultContextLines)
        XCTAssertEqual(request.switches, ["-U3"])
    }

    func testIgnoresWhitespaceAddsDashW() {
        var request = GitDiffRequest()
        request.ignoresWhitespace = true
        XCTAssertEqual(request.switches, ["-w", "-U3"])
    }

    /// 上下文 0 = 交给 git 的缺省，不传 `-U`（不要自己造一个「0 行上下文」）。
    func testZeroContextLinesOmitsTheSwitch() {
        let request = GitDiffRequest(ignoresWhitespace: false, contextLines: 0)
        XCTAssertEqual(request.switches, [])
    }

    func testNegativeContextLinesClampToZero() {
        XCTAssertEqual(GitDiffRequest(contextLines: -5).contextLines, 0)
        XCTAssertEqual(GitDiffRequest(contextLines: -5).switches, [])
    }

    // MARK: - 插进参数的位置

    func testSwitchesAreInsertedBeforeThePathSeparator() throws {
        let request = GitDiffRequest(ignoresWhitespace: true, contextLines: 12)
        let arguments = request.applying(to: base)
        let separator = try XCTUnwrap(arguments.firstIndex(of: "--"))
        let whitespace = try XCTUnwrap(arguments.firstIndex(of: "-w"))
        let context = try XCTUnwrap(arguments.firstIndex(of: "-U12"))
        XCTAssertLessThan(whitespace, separator, "`-w` 落在 `--` 之后会被 git 当成路径")
        XCTAssertLessThan(context, separator, "`-U<n>` 落在 `--` 之后同样会被当成路径")
        // 其余参数一个字不动、顺序不变。
        XCTAssertEqual(arguments.last, "Sources/A.swift")
        XCTAssertEqual(arguments.filter { $0 != "-w" && $0 != "-U12" }, base)
    }

    func testNothingIsInsertedWhenNoSwitchIsRequested() {
        let request = GitDiffRequest(ignoresWhitespace: false, contextLines: 0)
        XCTAssertEqual(request.applying(to: base), base)
    }

    /// 未跟踪文件走 `--no-index`：那条路的 `--` 更早出现，开关仍要在它之前。
    func testUntrackedArgumentsAlsoGetSwitchesBeforeSeparator() throws {
        let untracked = ["diff", "--no-color", "--no-ext-diff", "--no-index", "--", "/dev/null", "new.txt"]
        let arguments = GitDiffRequest(ignoresWhitespace: true, contextLines: 0).applying(to: untracked)
        let separator = try XCTUnwrap(arguments.firstIndex(of: "--"))
        let whitespace = try XCTUnwrap(arguments.firstIndex(of: "-w"))
        XCTAssertLessThan(whitespace, separator)
        XCTAssertEqual(arguments.last, "new.txt")
        XCTAssertEqual(arguments.filter { $0 != "-w" }, untracked)
    }

    /// 没有 `--` 的调用（理论上不会有）⇒ 开关追加在末尾，不吞掉任何参数。
    func testArgumentsWithoutSeparatorAppendSwitches() {
        let arguments = ["diff", "--stat"]
        let output = GitDiffRequest(ignoresWhitespace: false, contextLines: 40).applying(to: arguments)
        XCTAssertEqual(output, ["diff", "--stat", "-U40"])
    }

    // MARK: - 档位

    func testContextStepsStartAtGitDefault() {
        XCTAssertEqual(GitDiffRequest.contextSteps.first, GitDiffRequest.defaultContextLines)
        XCTAssertEqual(GitDiffRequest.contextSteps, GitDiffRequest.contextSteps.sorted())
    }
}
