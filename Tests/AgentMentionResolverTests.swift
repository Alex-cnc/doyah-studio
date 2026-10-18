import XCTest
@testable import DoyahCore

/// `@` 提及落地（`FR-AI-22` ①）：**真读得到才带、读不到要说清、二进制不塞给模型**。
final class AgentMentionResolverTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("resolve-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "struct A {}".write(to: root.appendingPathComponent("a.swift"), atomically: true, encoding: .utf8)
        try "说明".write(to: root.appendingPathComponent("说明.md"), atomically: true, encoding: .utf8)
        try Data([0x00, 0x01, 0x02, 0x00]).write(to: root.appendingPathComponent("bin.dat"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Sources"),
                                                withIntermediateDirectories: true)
        try "x".write(to: root.appendingPathComponent("Sources/x.swift"), atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func resolve(_ prompt: String) -> (refs: [AgentContextReference], notes: [String]) {
        let parsed = AgentMentionParser.parse(prompt, workspaceRoot: root)
        let out = AgentMentionResolver.references(
            for: parsed, root: root,
            reader: AgentMentionResolver.fileReader(root: root, maxCharacters: 20_000),
            lister: AgentMentionResolver.directoryLister(root: root, maxEntries: 80))
        return (out.references, out.notes)
    }

    func testMentionedFileIsReallyRead() {
        let (refs, notes) = resolve("@a.swift 帮我改这里")
        guard case .file(let path, let text)? = refs.first else { return XCTFail("应带文件段：\(refs)") }
        XCTAssertEqual(path, "a.swift")
        XCTAssertEqual(text, "struct A {}")
        XCTAssertTrue(notes.isEmpty)
    }

    func testMentionedDirectoryListsEntries() {
        let (refs, _) = resolve("@Sources/ 里有什么")
        guard case .directory(let path, let entries)? = refs.first else { return XCTFail("应带目录段") }
        XCTAssertEqual(path, "Sources/")
        XCTAssertEqual(entries, ["x.swift"])
    }

    func testBinaryFileIsNotAttachedButExplained() {
        let (refs, notes) = resolve("@bin.dat 看看")
        XCTAssertTrue(refs.isEmpty, "二进制不塞给模型")
        XCTAssertTrue(notes.contains { $0.contains("二进制") }, "要说清为什么没带：\(notes)")
    }

    func testMissingMentionIsExplained() {
        let (refs, notes) = resolve("@nope.swift 看看")
        XCTAssertTrue(refs.isEmpty)
        XCTAssertTrue(notes.contains { $0.contains("没有这个文件") }, "实际：\(notes)")
    }

    func testOutsideWorkspaceIsExplained() {
        let (refs, notes) = resolve("@../secret 看看")
        XCTAssertTrue(refs.isEmpty)
        XCTAssertTrue(notes.contains { $0.contains("不在工作区内") }, "实际：\(notes)")
    }

    func testMultipleMentionsAllResolved() {
        let (refs, _) = resolve("@a.swift 和 @说明.md")
        XCTAssertEqual(refs.count, 2)
    }

    func testReaderClampsOverlongTextOnce() {
        let big = String(repeating: "y", count: 500)
        try? big.write(to: root.appendingPathComponent("big.txt"), atomically: true, encoding: .utf8)
        let reader = AgentMentionResolver.fileReader(root: root, maxCharacters: 100)
        let read = reader("big.txt")
        XCTAssertEqual(read.status, .ok)
        XCTAssertEqual(read.text.count, 100, "先挡一次极端大小（截断标记交给组装器）")
    }
}
