import XCTest
@testable import DoyahCore
@testable import DoyahStudioApp

/// **工具观察文本的回灌判据**（2026-10-22 修 `list_dir` 一直「返回空」的那次事故）。
///
/// 事故形状：`AgentLoop.summary(of:)` 只把计数回灌给模型（`dir:.:23` / `file:a.txt:812` /
/// `search:3:7`），正文一个字不给。模型看不见内容 ⇒ 一遍遍重调同一条工具 ⇒ 界面上表现为
/// 「list_dir 不断返回空」，模型只好反复说「我先看一下项目结构」，直到跳数耗光。
///
/// 这些用例守的是一句话：**工具看见的东西，下一跳必须真读到**。
final class AgentToolObservationTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("doyah-observe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "let answer = 42\n".write(to: root.appendingPathComponent("a.swift"), atomically: true, encoding: .utf8)
        try "说明文字\n".write(to: root.appendingPathComponent("readme.md"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("sub"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    /// `list_dir` 的观察里必须**有目录项名字**（这次事故的正例）。
    func testDirectoryObservationCarriesEntryNames() {
        let tools = AgentWorkspaceTools(root: root)
        let observation = AgentLoop.summary(of: tools.listDirectory(path: "."))
        XCTAssertTrue(observation.contains("a.swift"), "目录项名字必须进观察，否则模型看不见就等于没列")
        XCTAssertTrue(observation.contains("readme.md"), "第二个文件同样要在")
        XCTAssertTrue(observation.contains("sub/"), "子目录带结尾斜杠，模型才分得清目录与文件")
        XCTAssertTrue(observation.contains("3 项"), "项数仍要给（断言计数与内容同在）")
    }

    /// `read_file` 的观察里必须**有文件正文**。
    func testFileObservationCarriesContent() {
        let tools = AgentWorkspaceTools(root: root)
        let observation = AgentLoop.summary(of: tools.readFile(path: "a.swift"))
        XCTAssertTrue(observation.contains("let answer = 42"), "读文件的观察不带正文 = 模型根本没读到")
        XCTAssertTrue(observation.contains("file:a.swift:"), "抬头仍带路径与字节数（便于核对是否截断）")
    }

    /// 空目录必须**明说**「空目录」——「空目录」与「没回灌」在模型看来不能长得一样。
    func testEmptyDirectorySaysSo() throws {
        let empty = root.appendingPathComponent("empty", isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        let tools = AgentWorkspaceTools(root: root)
        let observation = AgentLoop.summary(of: tools.listDirectory(path: "empty"))
        XCTAssertTrue(observation.contains("(空目录)"))
    }

    /// `search` 的观察里必须**有命中片段**（文件名与内容两类都要）。
    func testSearchObservationCarriesHits() {
        let tools = AgentWorkspaceTools(root: root)
        let observation = AgentLoop.summary(of: tools.search(query: "answer", limit: 20))
        XCTAssertTrue(observation.contains("命中"), "至少要有命中计数那行")
        XCTAssertTrue(observation.contains("a.swift"), "命中文件名要进观察")
    }

    /// 超长正文：**截断必须标注**（原文多大、留了多少），不许静默少字。
    func testOversizedPayloadIsAnnotatedNotSilentlyCut() throws {
        let big = String(repeating: "行内容\n", count: 4_000)   // 约 16KB，超过 8,000 字符上限
        try big.write(to: root.appendingPathComponent("big.txt"), atomically: true, encoding: .utf8)
        let tools = AgentWorkspaceTools(root: root)
        let observation = AgentLoop.summary(of: tools.readFile(path: "big.txt"))
        XCTAssertTrue(observation.contains("[truncated:file:"), "截断要带标注，不许静默")
        XCTAssertLessThan(observation.count, AgentLoop.maxObservationCharacters + 200)
    }
}
