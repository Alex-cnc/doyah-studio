import Foundation
import XCTest
@testable import DoyahCore

/// `FR-AGT-CORE-LOOP-006` 取证：**同一个工具面**（App 调的就是这一套）在临时工作区里真跑一遍。
///
/// 为什么要有这一份：界面里的「查找文件 / 读文件 / 列目录」已由人类主人点过，
/// 但 `write_file` / `edit_file` / `run_command` 没有人点过 —— 这里用真进程、真落盘补齐，
/// **不编造成功**：每条判据都读回磁盘 / 读回进程退出码。
final class AgentToolFaceEndToEndTests: XCTestCase {
    private var root: URL!
    private var tools: AgentWorkspaceTools!

    /// 真起进程的 runner（与 App 侧适配层同语义：起不来就返回 -1，不编 0）。
    private struct RealRunner: AgentCommandRunner {
        func run(executable: String, arguments: [String], workingDirectory: URL) -> AgentCommandResult {
            let process = Process()
            // 白名单里给的是裸名字（`cat`），真起进程要落到绝对路径上
            let resolved = executable.hasPrefix("/") ? executable : "/bin/" + executable
            process.executableURL = URL(fileURLWithPath: resolved)
            process.arguments = arguments
            process.currentDirectoryURL = workingDirectory
            let out = Pipe(), err = Pipe()
            process.standardOutput = out
            process.standardError = err
            do { try process.run() } catch {
                return AgentCommandResult(exitCode: -1, standardOutput: "", standardError: "起不来：\(error.localizedDescription)")
            }
            process.waitUntilExit()
            let o = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let e = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return AgentCommandResult(exitCode: process.terminationStatus, standardOutput: o, standardError: e)
        }
    }

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("doyah-toolface-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "第一行\n第二行 枫叶\n".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try "内层：趋势线\n".write(to: root.appendingPathComponent("sub/b.md"), atomically: true, encoding: .utf8)
        // 大文件：超过 maxReadBytes 必截断
        let big = String(repeating: "x", count: 4_096) + "尾巴"
        try big.write(to: root.appendingPathComponent("big.txt"), atomically: true, encoding: .utf8)
        tools = AgentWorkspaceTools(root: root, maxReadBytes: 1_024, maxDirectoryEntries: 100)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    // MARK: - read_file

    func testReadFileReturnsRealContent() {
        guard case .file(let file) = tools.readFile(path: "a.txt") else {
            return XCTFail("应读到文件")
        }
        XCTAssertTrue(file.text.contains("枫叶"))
        XCTAssertFalse(file.truncated)
        XCTAssertEqual(file.totalBytes, "第一行\n第二行 枫叶\n".utf8.count)
    }

    func testReadFileTruncatesAndSaysSo() {
        guard case .file(let file) = tools.readFile(path: "big.txt") else {
            return XCTFail("应读到文件")
        }
        XCTAssertTrue(file.truncated, "超上限必须如实标记截断")
        XCTAssertLessThan(file.text.utf8.count, file.totalBytes)
    }

    func testReadFileRefusesEscapeAndMissingFile() {
        if case .refused(let why, _) = tools.readFile(path: "../外面.txt") {
            XCTAssertEqual(why, .outsideWorkspace)
        } else { XCTFail("越界必须拒") }

        if case .refused(let why, _) = tools.readFile(path: "没有这个文件.txt") {
            XCTAssertEqual(why, .notFound)
        } else { XCTFail("不存在必须如实说不存在") }
    }

    // MARK: - list_dir

    func testListDirectorySeesEverythingOnDisk() {
        guard case .directory(let dir) = tools.listDirectory(path: ".") else {
            return XCTFail("应列出目录")
        }
        XCTAssertTrue(dir.entries.contains("a.txt"))
        XCTAssertTrue(dir.entries.contains("sub/"), "目录列表里子目录带尾斜杠：\(dir.entries)")
        XCTAssertFalse(dir.truncated)
    }

    // MARK: - search

    func testSearchFindsContentInChinese() {
        guard case .search(let hits) = tools.search(query: "枫叶") else {
            return XCTFail("应返回搜索结果")
        }
        XCTAssertTrue(hits.contentHits.contains { $0.contains("a.txt") }, "中文关键词要能命中：\(hits.contentHits)")
    }

    func testSearchFindsNestedFile() {
        guard case .search(let hits) = tools.search(query: "趋势线") else {
            return XCTFail("应返回搜索结果")
        }
        XCTAssertTrue(hits.contentHits.contains { $0.contains("sub/b.md") } == true
                      || hits.fileNames.contains { $0.contains("b.md") },
                      "子目录里的内容要能被找到")
    }

    // MARK: - write_file（审批 → 真落盘）

    func testWriteNeedsApprovalThenReallyWrites() throws {
        let prepared = tools.prepareWrite(path: "新文件.txt", content: "写进去的内容\n")
        guard case .needsApproval(let request) = prepared else {
            return XCTFail("写文件必须先要审批，实际：\(prepared)")
        }
        // 没批准时不许落盘
        let refused = tools.writeFile(path: "新文件.txt", content: "写进去的内容\n",
                                      fingerprint: "错的指纹", granted: [])
        if case .refused(let why, _) = refused {
            XCTAssertEqual(why, .approvalRequired)
        } else { XCTFail("未批准就写 = 越权") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("新文件.txt").path))

        let outcome = tools.writeFile(path: "新文件.txt", content: "写进去的内容\n",
                                      fingerprint: request.fingerprint, granted: [request.fingerprint])
        guard case .wrote = outcome else { return XCTFail("批准后应写入，实际：\(outcome)") }
        let onDisk = try String(contentsOf: root.appendingPathComponent("新文件.txt"), encoding: .utf8)
        XCTAssertEqual(onDisk, "写进去的内容\n", "落盘内容必须与批准的内容一致")
    }

    func testWriteRefusesOutsideWorkspace() {
        let prepared = tools.prepareWrite(path: "../溜出去.txt", content: "x")
        if case .refused(let why, _) = prepared {
            XCTAssertEqual(why, .outsideWorkspace)
        } else { XCTFail("越界写必须拒：\(prepared)") }
    }

    // MARK: - edit_file

    func testEditReplacesExactText() throws {
        let prepared = tools.prepareEdit(path: "a.txt", oldString: "第二行", newString: "改过的第二行")
        guard case .needsApproval(let request) = prepared else {
            return XCTFail("改文件要先审批：\(prepared)")
        }
        let outcome = tools.editFile(path: "a.txt", oldString: "第二行", newString: "改过的第二行",
                                     fingerprint: request.fingerprint, granted: [request.fingerprint])
        _ = outcome
        let onDisk = try String(contentsOf: root.appendingPathComponent("a.txt"), encoding: .utf8)
        XCTAssertTrue(onDisk.contains("改过的第二行"))
        XCTAssertEqual(onDisk, "第一行\n改过的第二行 枫叶\n", "只替换掉 oldString，其余一字不动")
    }

    // MARK: - run_command（真进程）

    func testRunCommandExecutesForReal() {
        let prepared = tools.prepareCommand("cat a.txt")
        guard case .needsApproval(let request) = prepared else {
            return XCTFail("跑命令要先审批：\(prepared)")
        }
        let outcome = tools.runCommand("cat a.txt",
                                       fingerprint: request.fingerprint, granted: [request.fingerprint],
                                       runner: RealRunner())
        guard case .command(let result) = outcome else { return XCTFail("应真跑一条命令：\(outcome)") }
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.standardOutput.contains("枫叶"), "真实 cat 输出里要有文件内容：\(result.standardOutput)")
    }

    func testRunCommandRefusedWithoutApproval() {
        let outcome = tools.runCommand("cat a.txt", fingerprint: "无", granted: [], runner: RealRunner())
        if case .refused(let why, _) = outcome {
            XCTAssertEqual(why, .approvalRequired)
        } else { XCTFail("未批准的命令不许跑") }
    }
}
