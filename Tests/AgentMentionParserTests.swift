import XCTest
@testable import DoyahCore

/// `@文件` / `@目录` 解析（`FR-AI-22` ①）：
/// **认不认、认成什么、越界怎么报**，逐条钉住。
final class AgentMentionParserTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mention-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "struct A {}\n".write(to: root.appendingPathComponent("a.swift"), atomically: true, encoding: .utf8)
        try "说明\n".write(to: root.appendingPathComponent("说明.md"), atomically: true, encoding: .utf8)
        try "x".write(to: root.appendingPathComponent("my file.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Sources"),
                                                withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testParsesSingleFile() {
        let r = AgentMentionParser.parse("@a.swift 帮我改这里", workspaceRoot: root)
        XCTAssertEqual(r.mentions.count, 1)
        XCTAssertEqual(r.mentions.first?.path, "a.swift")
        XCTAssertEqual(r.mentions.first?.kind, .file)
        XCTAssertTrue(r.issues.isEmpty)
    }

    func testParsesDirectoryWithSlash() {
        let r = AgentMentionParser.parse("看看 @Sources/ 里有什么", workspaceRoot: root)
        XCTAssertEqual(r.mentions.first?.kind, .directory)
        XCTAssertEqual(r.mentions.first?.path, "Sources/")
    }

    func testDirectoryWithoutSlashIsAcceptedByActualType() {
        let r = AgentMentionParser.parse("@Sources 里有什么", workspaceRoot: root)
        XCTAssertEqual(r.mentions.first?.kind, .directory, "按实际类型采纳，不因为少写 / 就丢掉")
        XCTAssertEqual(r.mentions.first?.path, "Sources/")
    }

    func testChinesePath() {
        let r = AgentMentionParser.parse("@说明.md 看看", workspaceRoot: root)
        XCTAssertEqual(r.mentions.first?.path, "说明.md")
    }

    func testQuotedPathWithSpace() {
        let r = AgentMentionParser.parse("@\"my file.txt\" 读一下", workspaceRoot: root)
        XCTAssertEqual(r.mentions.first?.path, "my file.txt")
    }

    func testTrailingChinesePunctuationIsStripped() {
        let r = AgentMentionParser.parse("@a.swift，改成这样", workspaceRoot: root)
        XCTAssertEqual(r.mentions.first?.path, "a.swift", "中文逗号不能算进路径")
    }

    func testMultipleMentionsAndDeduplication() {
        let r = AgentMentionParser.parse("@a.swift 和 @说明.md 和 @a.swift", workspaceRoot: root)
        XCTAssertEqual(r.mentions.map(\.path), ["a.swift", "说明.md"], "重复的只带一次")
    }

    func testOutsideWorkspaceIsRejected() {
        let r = AgentMentionParser.parse("@../secret.txt 读一下", workspaceRoot: root)
        XCTAssertTrue(r.mentions.isEmpty)
        XCTAssertEqual(r.issues.first?.reason, .outsideWorkspace)
    }

    func testAbsolutePathIsRejected() {
        let r = AgentMentionParser.parse("@/etc/passwd 读一下", workspaceRoot: root)
        XCTAssertTrue(r.mentions.isEmpty, "绝对路径不给口子")
        XCTAssertEqual(r.issues.first?.reason, .outsideWorkspace)
    }

    func testHomePathIsRejected() {
        let r = AgentMentionParser.parse("@~/.ssh/id_rsa 念一遍", workspaceRoot: root)
        XCTAssertTrue(r.mentions.isEmpty)
        XCTAssertEqual(r.issues.first?.reason, .outsideWorkspace)
    }

    func testMissingPathIsReported() {
        let r = AgentMentionParser.parse("@nope.swift 看看", workspaceRoot: root)
        XCTAssertTrue(r.mentions.isEmpty)
        XCTAssertEqual(r.issues.first?.reason, .notFound)
        XCTAssertEqual(r.issues.first?.raw, "nope.swift")
    }

    func testEmailIsNotAMention() {
        let r = AgentMentionParser.parse("mail me at a@b.com", workspaceRoot: root)
        XCTAssertTrue(r.mentions.isEmpty, "邮箱里的 @ 不是提及")
        XCTAssertTrue(r.issues.isEmpty)
    }

    func testBareAtSignIsIgnored() {
        let r = AgentMentionParser.parse("@ 没有路径", workspaceRoot: root)
        XCTAssertTrue(r.mentions.isEmpty)
        XCTAssertTrue(r.issues.isEmpty, "空提及不报错也不产生噪音")
    }
}
