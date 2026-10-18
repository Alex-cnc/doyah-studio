import XCTest
@testable import DoyahCore

/// 工作区**路径候选**（`FR-EDIT-57` 的最后一块：`@` / 相对路径提示）。
///
/// 与词那一路那 18 例的分工：前四道门（开关 / 单空选区 / 光标夹回 / 字符串注释里不出）由
/// `InlineGhostCompletionTests` 钉住，这里只判**路径这条多出来的那几条** ——
/// 什么算"在写路径"、只补最后一段、目录补完带 `/`、大小写按规范写法落地、排序可判、
/// 以及 `.notPath` / `.nothing` 那个分叉（后者不许退化成词补全）。这些在 AppKit 回调里只能靠手点。
final class InlineGhostPathTests: XCTestCase {

    private func index(_ entries: [(String, Bool)]) -> [WorkspacePathCandidate] {
        entries.map { WorkspacePathCandidate(relativePath: $0.0, isDirectory: $0.1) }
    }

    /// 一个像真工作区的小树。
    private var tree: [WorkspacePathCandidate] {
        index([
            ("Docs", true),
            ("Docs/design", true),
            ("Docs/design/开发循环-每轮卡.md", false),
            ("Docs/readme.md", false),
            ("Docs/img", true),
            ("App", true),
            ("App/Main.swift", false),
            ("README.md", false)
        ])
    }

    private func ghost(
        _ text: String,
        caret: Int? = nil,
        selectionLength: Int = 0,
        language: TextLanguage = .markdown,
        index: [WorkspacePathCandidate]? = nil,
        enabled: Bool = true
    ) -> PathGhostOutcome {
        PathGhostCompletion.pathSuggestion(
            in: text,
            selection: NSRange(location: caret ?? (text as NSString).length, length: selectionLength),
            language: language,
            index: index ?? tree,
            enabled: enabled
        )
    }

    // MARK: 什么时候算"在写路径"

    /// 裸词**不再**猜路径：敲 `ret` 交给词法候选（否则会被补成 `README.md` —— 替用户改代码）。
    func testBareWordIsNotPath() {
        XCTAssertEqual(ghost("ret"), .notPath)
        XCTAssertEqual(ghost("Docs"), .notPath)
    }

    /// `@` 标记 / 带 `/` / `~` 起头 —— 三种都算在写路径。
    func testPathShapes() {
        guard case .suggestion(let at) = ghost("@Doc") else { return XCTFail("@Doc 没出灰字") }
        XCTAssertEqual(at.insertText, "@Docs/")
        XCTAssertEqual(at.ghost, "s/")
        XCTAssertEqual(at.range, NSRange(location: 0, length: 4))
        XCTAssertEqual(at.caretOffset, 6)

        guard case .suggestion(let slash) = ghost("见 ![图](Docs/de") else { return XCTFail("Docs/de 没出灰字") }
        XCTAssertEqual(slash.insertText, "Docs/design/")
        XCTAssertEqual(slash.ghost, "sign/")

        XCTAssertEqual(ghost("~/nowhere"), .nothing, "`~` 起头是路径形态，但表里没有 ⇒ 什么都不出")
    }

    /// `@` 后面还空着：**是**路径形态但没有可补的 ⇒ `.nothing`（不许退化成词补全）。
    func testEmptyMentionIsNothingNotWordCompletion() {
        XCTAssertEqual(ghost("@"), .nothing)
    }

    /// 路径写错一半（表里没有）：`.nothing`，不是 `.notPath` —— 否则词法候选会在这里冒出一个标识符。
    func testUnknownPathIsNothing() {
        XCTAssertEqual(ghost("Docs/zzz"), .nothing)
        XCTAssertEqual(ghost("@Nonexistent/x"), .nothing)
    }

    /// 已经打全了（文件）：没得补 ⇒ `.nothing`；目录还差一个结尾 `/` ⇒ 仍然有得补。
    func testFullyTypedPath() {
        XCTAssertEqual(ghost("README.md"), .notPath, "没有 `/` 也没有 `@` ⇒ 交给词法")
        XCTAssertEqual(ghost("Docs/readme.md"), .nothing)
        guard case .suggestion(let dir) = ghost("@Docs") else { return XCTFail("@Docs 没补结尾斜杠") }
        XCTAssertEqual(dir.insertText, "@Docs/")
        XCTAssertEqual(dir.ghost, "/", "路径打全了，但目录还差一个结尾 `/` —— 这一格仍然有得补")
    }

    // MARK: 只补最后一段 + 规范写法

    /// 敲小写得到磁盘上的规范写法（大小写不敏感匹配，替换成 `Docs/design/`）。
    func testCaseInsensitiveMatchWritesCanonicalForm() {
        guard case .suggestion(let suggestion) = ghost("docs/desi") else { return XCTFail("没出灰字") }
        XCTAssertEqual(suggestion.insertText, "Docs/design/")
        XCTAssertEqual(suggestion.ghost, "gn/")
    }

    /// 前面的目录部分要**真的**对上，不能是子串：`Doc/` 不该匹配到 `Docs/…`。
    func testDirectoryPartMustMatchWholeSegments() {
        XCTAssertEqual(ghost("Doc/des"), .nothing)
    }

    /// 目录补完带 `/`，文件不带。
    func testDirectoryGetsTrailingSlashFileDoesNot() {
        guard case .suggestion(let dir) = ghost("Docs/im") else { return XCTFail("目录没出灰字") }
        XCTAssertEqual(dir.insertText, "Docs/img/")

        guard case .suggestion(let file) = ghost("Docs/read") else { return XCTFail("文件没出灰字") }
        XCTAssertEqual(file.insertText, "Docs/readme.md")
        XCTAssertEqual(file.ghost, "me.md")
    }

    /// 只补当前这一层：`Docs/d` 不会跳过 `design/` 直接补到更深的文件。
    func testMatchesCurrentSegmentOnly() {
        // 两个都在这一层上行：目录 `design/` 与它下面的那个文件；**短的（目录）排第一**。
        let matched = PathGhostCompletion.candidates(typed: "Docs/d", in: tree)
        XCTAssertEqual(matched.first, "Docs/design/")
        XCTAssertEqual(matched.count, 2)
        XCTAssertFalse(matched.contains("Docs/img/"), "`d` 不该匹配到 `img`")
    }

    /// 目录后面留空（`Docs/`）⇒ 补第一个子项（短的优先）。
    func testEmptyLeafCompletesFirstChild() {
        XCTAssertEqual(
            PathGhostCompletion.candidates(typed: "Docs/", in: tree).first,
            "Docs/img/"
        )
    }

    // MARK: 排序与边界

    /// 排序可判：短路径优先；同长时目录优先；其余按字典序（本地化、大小写不敏感）。
    func testCandidateOrderIsDeterministic() {
        let mixed = index([("ab/x.md", false), ("ab/zz", true), ("ab/yy", true), ("ab/aa.md", false)])
        XCTAssertEqual(
            PathGhostCompletion.candidates(typed: "ab/", in: mixed),
            ["ab/yy/", "ab/zz/", "ab/x.md", "ab/aa.md"]
        )
    }

    /// 词中间不出（也不许退化成词补全）：光标右侧还是路径体。
    func testCaretInsidePathGivesNothing() {
        XCTAssertEqual(ghost("Docs/design", caret: 6), .nothing)
    }

    /// 有选区 / 关掉开关 / 在字符串或注释里 —— 前四道门与词那一路**同一份**。
    func testSharedGatesApply() {
        XCTAssertEqual(ghost("Docs/des", selectionLength: 3), .nothing)
        XCTAssertEqual(ghost("Docs/des", enabled: false), .nothing)
        XCTAssertEqual(ghost("// Docs/des", language: .swift), .nothing)
        XCTAssertEqual(ghost("\"Docs/des\"", caret: 9, language: .swift), .nothing)
    }

    /// 灰字太长（病态长名字）⇒ 不提示，而不是画一屏灰字（词那一路的上限是 24，路径放宽到 120）。
    func testOverlongGhostIsSkipped() {
        let longName = String(repeating: "a", count: 200)
        let long = index([("Docs/design/\(longName).md", false)])
        XCTAssertEqual(ghost("Docs/de", index: long), .nothing)

        let shortEnough = index([("Docs/design/\(String(repeating: "a", count: 100)).md", false)])
        guard case .suggestion = ghost("Docs/de", index: shortEnough) else {
            return XCTFail("120 字符以内的路径该给灰字")
        }
    }

    /// 走查：从索引到灰字一条链（`@` 标记 + 目录 + 大小写 + 落点）。
    func testMentionWithNestedPathAndCaretOffset() {
        let text = "见 @Docs/design/开"
        guard case .suggestion(let suggestion) = ghost(text) else { return XCTFail("没出灰字") }
        XCTAssertEqual(suggestion.insertText, "@Docs/design/开发循环-每轮卡.md")
        XCTAssertEqual(suggestion.ghost, "发循环-每轮卡.md")
        XCTAssertEqual(suggestion.range, NSRange(location: 2, length: 14))
        XCTAssertEqual(suggestion.caretOffset, 2 + (suggestion.insertText as NSString).length)
    }

    // MARK: 索引（有界快照）

    /// 索引收目录也收文件、跳过点开头（与访达一致）与符号链接、深度与条数有界且**如实标记截断**。
    func testIndexIsBoundedAndHonest() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("path-index-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("A/B/C"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".hidden"), withIntermediateDirectories: true)
        try "x".write(to: root.appendingPathComponent("A/B/note.md"), atomically: true, encoding: .utf8)
        try "x".write(to: root.appendingPathComponent("top.md"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("link"),
            withDestinationURL: root.appendingPathComponent("A")
        )

        let full = PathGhostCompletion.index(in: root)
        let paths = Set(full.candidates.map(\.relativePath))
        XCTAssertTrue(paths.contains("A"))
        XCTAssertTrue(paths.contains("A/B"))
        XCTAssertTrue(paths.contains("A/B/note.md"))
        XCTAssertTrue(paths.contains("top.md"))
        XCTAssertFalse(paths.contains(".hidden"), "点开头按访达口径不显示")
        XCTAssertFalse(paths.contains("link"), "符号链接不跟随、也不当路径候选")
        XCTAssertFalse(full.isTruncated)
        XCTAssertEqual(full.candidates.first(where: { $0.relativePath == "A" })?.isDirectory, true)

        // 深度：根算第 0 层，`maxDepth: 1` 只收根那一层。
        let shallow = PathGhostCompletion.index(in: root, maxDepth: 1)
        XCTAssertEqual(Set(shallow.candidates.map(\.relativePath)), ["A", "top.md"])

        // 条数：上限到顶就停，并如实说截断了（不静默少给）。
        let capped = PathGhostCompletion.index(in: root, limit: 2)
        XCTAssertEqual(capped.candidates.count, 2)
        XCTAssertTrue(capped.isTruncated)
    }
}
