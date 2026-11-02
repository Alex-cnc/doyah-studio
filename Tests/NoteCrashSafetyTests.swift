import Darwin
import Foundation
import XCTest
@testable import DoyahCore

/// `FR-STD-ALL-PLUG-008` 取证：**桌面各端笔记存储统一到本地 SQLite**。
///
/// 这一族补的是台账备注「界面点击点验待人工；打包项按平台口径非本侧」后面那半句里
/// **机器能判**的部分 —— 四条判据各自落到一个可读的读数上：
///
///   ① 元数据 / 正文 / 标签 / 时间线**落本地库**（读回来的是库里的那一份，不是内存里那份）；
///   ② 附件二进制**留在文件系统**、库里只存路径（字节相同、路径在附件家下、库没被撑大）；
///   ③ 表结构与 schema 版本的唯一性由 `Scripts/check-note-storage-unity.py` 静态判
///      （另两端的实现面现状在那边如实报「未知」）；
///   ④ **写入原子，崩溃后库不自坏** —— 这一条只能由真进程被杀证明：
///      起一个 `DoyahCLI notes write-probe` 真进程连续写笔记，中途 `SIGKILL`，
///      再打开同一份库问 `integrity_check` 与「有没有半条笔记」。
///
/// 为什么不自造写入器：库的写入口只该有一份。探针跑的是**产品自己的** `NoteLibrary.save`
/// （与界面同一条路），所以这里量到的原子性属于产品，不属于测试夹具。
final class NoteCrashSafetyTests: XCTestCase {

    private var root: URL!

    /// 写探针的正文形状 —— 与 `CLI/main.swift` 里 `notes write-probe` 那段注释同源。
    /// **改一处必须同批改另一处**：漂移的后果是判据判红（看得见），不是悄悄变绿。
    private static let probeBody = String(repeating: "x", count: 4096) + ":END"

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("doyah-crash-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    // MARK: - ④ 崩溃后库不自坏

    /// 三种「砍在中途」的时刻各砍一次：每一次都要求
    /// ① `integrity_check` 还是 `ok`；② 落盘的每条笔记都是**完整的一条**（正文有尾巴、两枚标签、有版本）；
    /// ③ 崩完还能继续写、继续读。
    func testKilledWriterLeavesTheDatabaseIntactAndComplete() async throws {
        guard let cli = cliBinary() else {
            throw XCTSkip("找不到 DoyahCLI（先 `swift build` 或设 DOYAH_CLI=<可执行文件>）—— 没跑就等于没判")
        }
        var readings: [(delayMs: Int, notes: Int, walBytes: Int)] = []

        // 砍的时刻要落在**写流中间**：开着 40 ms 的负例窗口时一条约 80 ms，400 ms 时已有若干条提交。
        for delayMs in [400, 700, 1000] {
            let databaseURL = try freshDatabaseURL()
            let crash = try await runAndKill(cli: cli, databaseURL: databaseURL, delayMs: delayMs)

            let database = try NoteDatabase(path: databaseURL.path)
            XCTAssertEqual(
                try database.integrityCheck(), "ok",
                "第 \(delayMs) ms 砍下去之后 integrity_check 不是 ok ⇒ 崩写把库弄坏了"
            )

            let notes = crash.notes
            XCTAssertFalse(notes.isEmpty, "这一轮一条都没落盘 ⇒ 没崩在写的过程中，这轮读数不可用（不是在说通过）")
            for note in notes {
                let index = try probeIndex(of: note)
                XCTAssertEqual(note.body, Self.probeBody, "第 \(index) 条是半条：正文没完整落盘")
                XCTAssertEqual(
                    Set(note.tags), ["probe", "lane-\(index % 4)"],
                    "第 \(index) 条的标签与正文不在同一次提交里（拆成了两次写）"
                )
                XCTAssertGreaterThanOrEqual(
                    try database.versionCount(of: note.id), 1,
                    "第 \(index) 条落了盘却没有版本记录 ⇒ 三件事没进同一个事务"
                )
            }

            // 崩完这一份库还能当活库用：能写、能读回、还能再崩一次
            let library = NoteLibrary(databaseURL: databaseURL)
            let survivor = try await library.save(NoteDraft(title: "after-crash-\(delayMs)", body: "崩后还能写"))
            let reloaded = try await library.load().first(where: { $0.id == survivor.id })?.body
            XCTAssertEqual(reloaded, "崩后还能写")

            readings.append((delayMs, notes.count, crash.walBytes))
        }

        // 读数进日志（证据文件按这行抄；不做断言 —— WAL 为 0 只是说那一砍落在两次提交之间）
        print("崩写读数（砍下去的时刻 / 已完整落盘条数 / WAL 字节）：\(readings)")
    }

    // MARK: - ① 元数据 / 正文 / 标签 / 时间线落本地库

    func testNoteMetadataBodyTagsAndTimelineLiveInTheLocalDatabase() async throws {
        let databaseURL = try freshDatabaseURL()
        let library = NoteLibrary(databaseURL: databaseURL)

        let saved = try await library.save(
            NoteDraft(title: "库里有", body: "正文也在库里", tags: ["a", "b"])
        )

        // 另开一个连接读回来：读的是**库里的那一份**，不是内存里那个对象
        let database = try NoteDatabase(path: databaseURL.path)
        XCTAssertEqual(try database.note(id: saved.id)?.title, "库里有")
        XCTAssertEqual(try database.note(id: saved.id)?.body, "正文也在库里")
        XCTAssertEqual(try database.note(id: saved.id)?.tags.sorted(), ["a", "b"])
        XCTAssertFalse(try database.timeline(of: saved.id).isEmpty, "时间线没落库")

        // schema 版本以库头为准（不是内存常量自说自话）
        let version = try await library.schemaVersion()
        XCTAssertEqual(version, NoteDatabase.supportedVersion)

        // 主存只有一条：同目录里不许再出现旧的 `notes.json`（那是迁移的输入，不是并行主存）
        let siblings = try FileManager.default.contentsOfDirectory(
            atPath: databaseURL.deletingLastPathComponent().path
        )
        XCTAssertEqual(siblings.filter { $0.hasSuffix(".json") }, [], "笔记目录里还有 JSON 主存")
        XCTAssertTrue(siblings.contains(NoteDatabase.fileName), "库文件不在预期位置：\(siblings)")
    }

    // MARK: - ② 附件留在文件系统，库里只存路径

    func testAttachmentBytesStayOnTheFileSystemNotInTheDatabase() async throws {
        let databaseURL = try freshDatabaseURL()
        let library = NoteLibrary(databaseURL: databaseURL)
        let note = try await library.save(NoteDraft(title: "带附件"))

        let payload = Data((0 ..< 4096).map { UInt8($0 % 251) })
        let source = root.appendingPathComponent("原始件.bin")
        try payload.write(to: source)

        let before = try fileSize(databaseURL)
        let attachment = try await library.attach(fileAt: source, to: note.id)
        let after = try fileSize(databaseURL)

        XCTAssertTrue(
            attachment.path.hasPrefix(library.attachmentRoot.path),
            "附件路径不在附件家里：\(attachment.path)"
        )
        XCTAssertEqual(
            try Data(contentsOf: URL(fileURLWithPath: attachment.path)), payload,
            "落盘的附件与被选中的文件不是同一份字节"
        )
        XCTAssertLessThan(
            after - before, 64 * 1024,
            "库被撑大了 \(after - before) 字节 ⇒ 附件二进制进了库（BLOB）"
        )
        let indexed = try await library.attachments(of: note.id)
        XCTAssertEqual(indexed.count, 1)

        // 删掉源文件不影响挂着的这份（拷的是字节，不是引用）
        try FileManager.default.removeItem(at: source)
        XCTAssertTrue(FileManager.default.fileExists(atPath: attachment.path))
        let missing = try await library.missingAttachments(of: note.id)
        XCTAssertEqual(missing.count, 0)
    }

    // MARK: - 夹具

    private func freshDatabaseURL() throws -> URL {
        let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(NoteDatabase.fileName, isDirectory: false)
    }

    /// 命令行二进制：环境变量优先，其次找测试 bundle 的**兄弟**（SwiftPM 把两者放在同一个产物目录）。
    private func cliBinary() -> URL? {
        if let raw = ProcessInfo.processInfo.environment["DOYAH_CLI"], !raw.isEmpty {
            let url = URL(fileURLWithPath: raw)
            return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
        }
        let bundleURL = Bundle(for: type(of: self)).bundleURL
        let candidates = [
            bundleURL.deletingLastPathComponent().appendingPathComponent("DoyahCLI"),
            bundleURL.appendingPathComponent("Contents/MacOS/DoyahCLI")
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private struct CrashOutcome {
        let notes: [Note]
        let walBytes: Int
        let ran: Bool
    }

    /// 起一个真写进程，等它开始写，`delayMs` 之后 `SIGKILL`，再读回那一份库。
    private func runAndKill(cli: URL, databaseURL: URL, delayMs: Int) async throws -> CrashOutcome {
        let process = Process()
        process.executableURL = cli
        process.arguments = [
            "notes", "write-probe",
            "--database", databaseURL.path,
            "--count", "4000",
            "--pause-ms", "2"
        ]
        process.standardOutput = Pipe()
        let errors = Pipe()
        process.standardError = errors
        // **负例开关**：把 `save` 三块之间的窗口拉宽（不设就一次都不睡）。
        // 有了它，「三块拆成三次提交」这种缺陷才会**稳定**被判红 —— 真实窗口只有几微秒，
        // 靠运气砍中才能看见（本批第一次跑撞到过一条无版本的笔记，复跑就绿了）。
        var environment = ProcessInfo.processInfo.environment
        environment["DOYAH_NOTE_SAVE_GAP_MS"] = "40"
        process.environment = environment
        try process.run()

        // 等库文件出现（最多 20 秒）：不靠「睡一会儿大概就好了」
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline, !FileManager.default.fileExists(atPath: databaseURL.path) {
            if !process.isRunning {
                let text = String(
                    data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8
                ) ?? ""
                XCTFail("写探针提前退出，库都没建出来：\(text)")
                break
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: databaseURL.path), "20 秒内库没建出来")

        Thread.sleep(forTimeInterval: Double(delayMs) / 1000.0)
        let stillRunning = process.isRunning
        if stillRunning { kill(process.processIdentifier, SIGKILL) }
        process.waitUntilExit()

        // 记 WAL 侧车的大小：它说明「砍下去那一刻库里还有没归并的页」（只是读数，不是断言）
        let walPath = databaseURL.path + "-wal"
        let walBytes = (try? fileSize(URL(fileURLWithPath: walPath))) ?? 0

        // 崩完之后用**产品入口**读回：这一步本身也是判据（打不开就是坏了）
        let library = NoteLibrary(databaseURL: databaseURL)
        let notes = try await library.load()
        return CrashOutcome(notes: notes, walBytes: walBytes, ran: stillRunning)
    }

    private func probeIndex(of note: Note) throws -> Int {
        guard note.title.hasPrefix("probe-"), let index = Int(note.title.dropFirst("probe-".count)) else {
            throw XCTSkip("非探针笔记混进来了：\(note.title)")
        }
        return index
    }

    private func fileSize(_ url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.intValue ?? 0
    }
}
