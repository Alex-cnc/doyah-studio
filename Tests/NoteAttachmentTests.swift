import XCTest
@testable import DoyahCore

// `FR-NTS-NOTE-ATTACH-001`（附件与图片）的机械证据。题面三条判据，逐条对一条用例：
//
//   ① 图片可缩放但不改写原文件 —— 收进来的是**字节拷贝**（sha256 对得上、源文件一字未动）；
//   ② 附件缺失时明确提示「文件不在了」—— 文件被外部删掉之后，索引还在、`missingAttachments` 点名它；
//   ③ 删除笔记不会静默删掉附件（另行确认）—— 删笔记之后文件仍在盘上、收据里带回清单，
//      只有**另行**调 `deleteAttachmentFiles` 才真的删。
//
// 纪律与 `NoteVersionTests` 同源：跑真库文件（临时目录）、每条「应该」配一条「不该」的对照。
final class NoteAttachmentTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("doyah-note-attachment-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    private func library() -> NoteLibrary {
        NoteLibrary(databaseURL: directory.appendingPathComponent(NoteLibrary.fileName, isDirectory: false))
    }

    /// 造一份「像图片」的源文件：PNG 头 + 一堆非文本字节（含 0x00 —— 文本化的实现会把它啃掉）。
    private func makeSource(name: String = "原图.png") throws -> URL {
        let url = directory.appendingPathComponent("source-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let file = url.appendingPathComponent(name, isDirectory: false)
        var bytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        bytes.append(contentsOf: (0..<4096).map { UInt8(($0 * 37) % 256) })
        try bytes.write(to: file)
        return file
    }

    private func note(_ library: NoteLibrary, title: String = "骑行计划") async throws -> Note {
        try await library.save(NoteDraft(title: title, body: "带一张原图\n备注"))
    }

    // MARK: - ① 字节原样（不压缩、不改写）

    func testImportCopiesBytesVerbatimAndLeavesTheOriginalUntouched() async throws {
        let library = library()
        let saved = try await note(library)
        let source = try makeSource()
        let before = try Data(contentsOf: source)

        let attachment = try await library.attach(fileAt: source, to: saved.id)

        // **字节逐字相同**（判据①「原图不被压缩覆盖」的机械形状：压缩 / 重新编码都会改字节）。
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: attachment.path)), before)
        XCTAssertEqual(attachment.byteCount, Int64(before.count))
        // 源文件**一个字节都没动**（缩放只是显示层的事，落盘这一层不许碰原文件）。
        XCTAssertEqual(try Data(contentsOf: source), before)
        // 落在**这一份库**的附件家里（换库不串目录）。
        XCTAssertTrue(attachment.path.hasPrefix(library.attachmentRoot.path), attachment.path)
        XCTAssertTrue(attachment.path.contains(saved.id.uuidString), attachment.path)
        // 索引读回来就是这一条（路径 / 字节数 / 时间都在）。
        let rows = try await library.attachments(of: saved.id)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.path, attachment.path)
        XCTAssertEqual(rows.first?.byteCount, attachment.byteCount)
    }

    func testTwoFilesWithTheSameNameDoNotOverwriteEachOther() async throws {
        let library = library()
        let saved = try await note(library)
        let first = try makeSource(name: "同名.png")
        // 第二个源在**另一个目录**、同名：覆盖式实现会让第一条索引指向第二份内容。
        let otherDirectory = directory.appendingPathComponent("other-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: otherDirectory, withIntermediateDirectories: true)
        let second = otherDirectory.appendingPathComponent("同名.png", isDirectory: false)
        try Data([0xFF, 0x00, 0x01, 0x02]).write(to: second)

        let one = try await library.attach(fileAt: first, to: saved.id)
        let two = try await library.attach(fileAt: second, to: saved.id)

        XCTAssertNotEqual(one.path, two.path, "同名文件必须各占一份，不许互相覆盖")
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: one.path)), try Data(contentsOf: first))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: two.path)), try Data(contentsOf: second))
        let afterBoth = try await library.attachments(of: saved.id)
        XCTAssertEqual(afterBoth.count, 2)
    }

    // MARK: - ② 文件不在了 ⇒ 明确点名（不静默跳过）

    func testMissingFileIsReportedNotSkipped() async throws {
        let library = library()
        let saved = try await note(library)
        let source = try makeSource()
        let attachment = try await library.attach(fileAt: source, to: saved.id)
        // 外部把文件删掉（用户自己拖走 / 外接盘拔了）——索引还在。
        try FileManager.default.removeItem(at: URL(fileURLWithPath: attachment.path))

        let missing = try await library.missingAttachments(of: saved.id)
        XCTAssertEqual(missing.map(\.id), [attachment.id], "文件不在了必须点名，不许当成没有附件")
        // 索引本身**不被顺手清掉**：清了就等于把「曾经挂过」这件事也擦掉（用户看不到该提示）。
        let stillIndexed = try await library.attachments(of: saved.id)
        XCTAssertEqual(stillIndexed.count, 1)
        // 判定处唯一（`NoteAttachmentStore.isMissing`）。
        let store = NoteAttachmentStore(root: library.attachmentRoot)
        XCTAssertTrue(store.isMissing(attachment))
    }

    // MARK: - ③ 删笔记不删文件；要删必须另行确认

    func testDeletingTheNoteKeepsTheAttachmentFilesOnDisk() async throws {
        let library = library()
        let saved = try await note(library)
        let attachment = try await library.attach(fileAt: try makeSource(), to: saved.id)

        let receipt = try await library.deleteReturningAttachments(id: saved.id, at: Date())

        XCTAssertTrue(receipt.deleted)
        XCTAssertEqual(receipt.attachments.map(\.id), [attachment.id], "收据必须带回「原本挂着哪些附件」")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: attachment.path),
            "删笔记只删索引，文件不许被静默删掉（判据③）"
        )
    }

    func testAttachmentFilesAreRemovedOnlyWhenExplicitlyAsked() async throws {
        let library = library()
        let saved = try await note(library)
        let attachment = try await library.attach(fileAt: try makeSource(), to: saved.id)
        let receipt = try await library.deleteReturningAttachments(id: saved.id, at: Date())

        // **没另行确认 ⇒ 一个文件都不删**（对照：上一条用例已经证明过，这里再钉一次读数）。
        let nothingAsked = try await library.deleteAttachmentFiles([])
        XCTAssertEqual(nothingAsked, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: attachment.path))

        // 人按了「一起删掉」⇒ 这才删，且如实报数。
        let removed = try await library.deleteAttachmentFiles(receipt.attachments)
        XCTAssertEqual(removed, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: attachment.path))
        // 再删一次 = 0（不在了的不算「删掉」—— 不把「本来就没有」算成业绩）。
        let removedAgain = try await library.deleteAttachmentFiles(receipt.attachments)
        XCTAssertEqual(removedAgain, 0)
    }

    // MARK: - 反例：挂不上时不许留半份

    func testAttachingToAMissingNoteLeavesNoFileBehind() async throws {
        let library = library()
        _ = try await note(library)   // 让库先存在（否则这一条测的是「库都不在」）
        let source = try makeSource()

        await XCTAssertThrowsErrorAsync {
            _ = try await library.attach(fileAt: source, to: UUID())
        }

        // 索引没写成 ⇒ 刚拷进来的文件必须被收掉（半份 = 谁也找不到的孤儿）。
        let leftover = FileManager.default
            .enumerator(atPath: library.attachmentRoot.path)?
            .allObjects as? [String] ?? []
        XCTAssertEqual(leftover, [], "索引没写成时，拷进来的文件必须一并收掉：\(leftover)")
        let unknownNoteFiles = try await library.attachments(of: UUID())
        XCTAssertEqual(unknownNoteFiles.count, 0)
    }

    func testAttachingAMissingSourceFailsAndWritesNoIndex() async throws {
        let library = library()
        let saved = try await note(library)
        let ghost = directory.appendingPathComponent("不在了.png", isDirectory: false)

        await XCTAssertThrowsErrorAsync {
            _ = try await library.attach(fileAt: ghost, to: saved.id)
        }
        let noIndex = try await library.attachments(of: saved.id)
        XCTAssertEqual(noIndex.count, 0)
    }

    /// 库还不存在时读附件 —— **空表**，不顺手建库（与 `reminders()` 同一条纪律）。
    func testAttachmentsOfAFreshLibraryAreEmptyAndDoNotCreateTheDatabase() async throws {
        let library = library()
        let freshAttachments = try await library.attachments(of: UUID())
        let freshMissing = try await library.missingAttachments(of: UUID())
        XCTAssertEqual(freshAttachments.count, 0)
        XCTAssertEqual(freshMissing.count, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: library.fileURL.path))
    }
}

/// `XCTAssertThrowsError` 的 async 版（本仓既有测试里也在用同一形状的私有壳）。
private func XCTAssertThrowsErrorAsync(
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("应当抛错，实际没抛", file: file, line: line)
    } catch {
        // 抛了就算过（具体错误类型由调用方按需再断言 —— 这几条判的是「不许静默成功」）。
    }
}
