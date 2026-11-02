import XCTest
@testable import DoyahCore

/// `FR-NTS-NOTE-EXPORT-001`（导出与迁移）的机器判据 —— 需求 §3.5 那条 + 概设 §15.3 五条不变量。
///
/// **覆盖范围（如实声明）**：
///   · ① 「导出包含全部正文与附件引用」—— 三种产物（Markdown / 纯文本 / 备份包）逐条对账，
///     每条笔记的正文、标签、附件路径都在；条数三形态恒等（契约「三形态同源」）；
///   · ② 「导入还原后笔记数、标签、时间一致」—— **真库往返**：导出到包、导入另一只空库，
///     逐字段比对（id / 标题 / 正文投影 / 正文权威源 / 标签集合 / 创建与更新时间 / 整理位 / 附件引用）；
///   · ③ 「导出格式有版本号」—— 包里有 `format` + `formatVersion`；**版本高于本端 ⇒ 拒绝导入**
///     且库文件逐字节不动（不半懂不懂地读）；
///   · 「导出是副本」—— 导出前后**库文件逐字节相同**、逐条字段不变；
///   · 「私密不外发」—— 私密条目在三种产物里都不出现（契约 §15.6）；
///   · **未覆盖**：附件**字节**不随包走（包里只有引用；原件在 `<数据家>/attachments/`）·
///     历史版本 / 时间线 / 回收站不进包 · 归属笔记本在目标库不存在时落默认笔记本（回执计数，不假装一模一样）·
///     真鼠标点菜单里的「导出 / 导入」未点（入口在 `AppState`，本文件判到库与包的边界）。
final class NoteArchiveTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NoteArchiveTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
        super.tearDown()
    }

    private func makeLibrary(_ name: String) async throws -> NoteLibrary {
        let directory = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let library = NoteLibrary(databaseURL: directory.appendingPathComponent(NoteLibrary.fileName))
        try await library.ensureOwnership(shelfName: "架", notebookName: "收件箱")
        return library
    }

    /// 直接走库写一条**时间精确**的笔记（`NoteLibrary.upsert` 会把 `updatedAt` 改成「现在」，
    /// 那样就判不出「还原后时间一致」了）。同时写正文权威源。
    @discardableResult
    private func seed(
        _ library: NoteLibrary,
        id: UUID = UUID(),
        title: String,
        body: String,
        tags: [String],
        createdAt: Date,
        updatedAt: Date,
        favorite: Bool = false,
        pinned: Bool = false,
        privateNote: Bool = false
    ) throws -> Note {
        let database = try NoteDatabase(path: library.fileURL.path)
        let note = Note(
            id: id,
            title: title,
            body: body,
            tags: tags,
            createdAt: createdAt,
            updatedAt: updatedAt,
            isFavorite: favorite,
            isPinned: pinned
        )
        try database.upsert(note)
        let spans = NoteBody(spans: [NoteSpan(text: body, color: "#112233")])
        let encoded = String(decoding: try JSONEncoder().encode(spans), as: UTF8.self)
        try database.setNoteSpans(encoded, body: body, id: id)
        if privateNote {
            _ = try database.setPrivate(true, id: id)
        }
        return note
    }

    // MARK: - ② 完整还原（真库往返）

    func testPackageRoundTripRestoresEveryField() async throws {
        let source = try await makeLibrary("source")
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000.25)
        let updatedAt = Date(timeIntervalSince1970: 1_700_000_900.75)
        let noteID = UUID()
        try seed(
            source,
            id: noteID,
            title: "导出与迁移",
            body: "正文第一段，带颜色。",
            tags: ["备份", "迁移"],
            createdAt: createdAt,
            updatedAt: updatedAt,
            favorite: true,
            pinned: true
        )
        // 附件：真拷一份文件进附件家，再挂到这条笔记上。
        let file = root.appendingPathComponent("原图 1.txt")
        try Data("附件字节".utf8).write(to: file)
        let attachment = try await source.attach(
            fileAt: file, to: noteID, now: Date(timeIntervalSince1970: 1_700_000_500)
        )

        let package = try await source.archivePackage(at: Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertEqual(package.format, "doyah.notes.backup", "包的格式标识必须逐字是契约那一串")
        XCTAssertEqual(package.formatVersion, NoteArchiveFormat.currentVersion, "包里必须有格式版本位")
        XCTAssertEqual(package.notes.count, 1, "只有一条非私密笔记 ⇒ 包里就一条")
        let exported = try XCTUnwrap(package.notes.first)
        XCTAssertEqual(exported.tags, ["备份", "迁移"])
        XCTAssertEqual(exported.attachments.map(\.id), [attachment.id], "附件引用必须进包")
        XCTAssertNotNil(exported.spans, "正文权威源必须进包（否则行内样式丢了）")

        // 导入一只**全新的空库**（不同目录 ⇒ 默认笔记本 uid 也不同）。
        let target = try await makeLibrary("target")
        let data = try await source.archiveData()
        let report = try await target.importArchive(data)
        XCTAssertEqual(report.restored, 1)
        XCTAssertEqual(report.skippedPrivateExisting, 0)
        XCTAssertEqual(report.notebookFallbacks, 1, "原归属笔记本在目标库不存在 ⇒ 落默认笔记本并计数")

        let restoredNotes = try await target.load()
        let restored = try XCTUnwrap(restoredNotes.first)
        XCTAssertEqual(restored.id, noteID)
        XCTAssertEqual(restored.title, exported.title)
        XCTAssertEqual(restored.body, exported.body)
        XCTAssertEqual(restored.tags, exported.tags)
        XCTAssertEqual(restored.createdAt, createdAt, "创建时间必须逐秒还原，不许换成导入时刻")
        XCTAssertEqual(restored.updatedAt, updatedAt, "更新时间必须逐秒还原，不许换成导入时刻")
        XCTAssertEqual(restored.isFavorite, true)
        XCTAssertEqual(restored.isPinned, true)
        XCTAssertEqual(restored.source.kind.rawValue, exported.sourceKind)

        let restoredAttachments = try await target.attachments(of: noteID)
        let restoredAttachment = try XCTUnwrap(restoredAttachments.first)
        XCTAssertEqual(restoredAttachment.id, attachment.id)
        XCTAssertEqual(restoredAttachment.path, attachment.path)
        XCTAssertEqual(restoredAttachment.byteCount, attachment.byteCount)
        XCTAssertEqual(restoredAttachment.addedAt, attachment.addedAt)

        let restoredSpans = try await NoteDatabase(path: target.fileURL.path).noteSpans(id: noteID)
        XCTAssertEqual(restoredSpans, exported.spans, "正文权威源（spans）必须逐字还原")
        XCTAssertEqual(restoredAttachments.count, 1)
    }

    // MARK: - 「导出是副本」

    func testExportLeavesTheLibraryByteIdentical() async throws {
        let library = try await makeLibrary("copy")
        try seed(
            library,
            title: "副本判据",
            body: "导出不该改这个名字。",
            tags: ["不变"],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        // 先做一次读、把连接关掉（WAL 可能在这一刻 checkpoint）—— 再取字节基线。
        let before = try await library.load()
        let bytesBefore = try Data(contentsOf: library.fileURL)

        _ = try await library.archivePackage()
        _ = try await library.archiveText(.markdown, language: .simplifiedChinese)
        _ = try await library.archiveText(.plainText, language: .simplifiedChinese)

        let bytesAfter = try Data(contentsOf: library.fileURL)
        let after = try await library.load()
        XCTAssertEqual(bytesAfter, bytesBefore, "导出只读库：库文件必须逐字节相同")
        XCTAssertEqual(after.count, before.count)
        XCTAssertEqual(after.first?.title, before.first?.title)
        XCTAssertEqual(after.first?.body, before.first?.body)
        XCTAssertEqual(after.first?.updatedAt, before.first?.updatedAt)
    }

    // MARK: - ③ 版本位 / 版本高了拒绝导入

    func testNewerPackageVersionIsRefusedAndLeavesTheLibraryUntouched() async throws {
        let library = try await makeLibrary("version")
        try seed(
            library,
            title: "版本判据",
            body: "旧端读新包必须拒绝。",
            tags: [],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let bytesBefore = try Data(contentsOf: library.fileURL)

        let currentPackageData = try await library.archiveData()
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: currentPackageData) as? [String: Any]
        )
        object["formatVersion"] = NoteArchiveFormat.currentVersion + 1
        let future = try JSONSerialization.data(withJSONObject: object)

        do {
            _ = try await library.importArchive(future)
            XCTFail("版本高于本端支持范围必须拒绝导入 —— 不许半懂不懂地读")
        } catch let failure as NoteArchiveFailure {
            XCTAssertEqual(
                failure,
                .unsupportedFormatVersion(
                    found: NoteArchiveFormat.currentVersion + 1,
                    supported: NoteArchiveFormat.currentVersion
                )
            )
        }
        let bytesAfter = try Data(contentsOf: library.fileURL)
        XCTAssertEqual(bytesAfter, bytesBefore, "被拒的导入一个字节都不许写")
        let remaining = try await library.load()
        XCTAssertEqual(remaining.count, 1)
    }

    // MARK: - ① 三形态同源 + 私密不外发

    func testThreeFormsComeFromTheSameSourceAndNeverCarryPrivateNotes() async throws {
        let library = try await makeLibrary("forms")
        try seed(
            library,
            title: "公开甲",
            body: "甲正文\n第二行",
            tags: ["甲"],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        let publicID = UUID()
        try seed(
            library,
            id: publicID,
            title: "公开乙",
            body: "乙正文",
            tags: [],
            createdAt: Date(timeIntervalSince1970: 1_700_000_200),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_300)
        )
        let file = root.appendingPathComponent("附件.txt")
        try Data("x".utf8).write(to: file)
        let attachment = try await library.attach(fileAt: file, to: publicID)
        try seed(
            library,
            title: "私密丙",
            body: "私密正文不许外发",
            tags: ["私密"],
            createdAt: Date(timeIntervalSince1970: 1_700_000_400),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_400),
            privateNote: true
        )

        let package = try await library.archivePackage()
        let markdown = try await library.archiveText(.markdown, language: .simplifiedChinese)
        let plain = try await library.archiveText(.plainText, language: .simplifiedChinese)

        XCTAssertEqual(package.notes.count, 2, "三形态同源：非私密两条")
        let markdownHeadings = markdown
            .components(separatedBy: "\n")
            .filter { $0.hasPrefix("# ") }
        XCTAssertEqual(markdownHeadings.count, 2, "Markdown 里必须正好两条（每条一个 `# 标题`）")
        XCTAssertTrue(plain.contains("公开甲") && plain.contains("公开乙"), "纯文本必须两条都在")
        XCTAssertFalse(plain.contains("---"), "纯文本不带 Markdown 分隔线")
        for title in ["公开甲", "公开乙"] {
            XCTAssertTrue(markdown.contains(title), "Markdown 少了「\(title)」")
            XCTAssertTrue(plain.contains(title), "纯文本少了「\(title)」")
        }
        XCTAssertTrue(markdown.contains(attachment.path), "Markdown 必须带附件引用")
        XCTAssertTrue(plain.contains(attachment.path), "纯文本必须带附件引用")
        XCTAssertTrue(markdown.contains("标签：甲"), "Markdown 必须带标签")
        XCTAssertFalse(markdown.contains("私密丙"), "私密条目不许进 Markdown")
        XCTAssertFalse(plain.contains("私密丙"), "私密条目不许进纯文本")
        XCTAssertFalse(package.notes.contains { $0.title == "私密丙" }, "私密条目不许进备份包")
        let packageBytes = try await library.archiveData()
        XCTAssertFalse(String(decoding: packageBytes, as: UTF8.self).contains("私密正文"),
                       "私密正文一个字节都不许在包里出现")
    }

    // MARK: - 私密冲突：目标里同 uuid 那条是私密 ⇒ 跳过不碰（如实计数）

    func testPrivateCollisionIsSkippedNotOverwritten() async throws {
        let library = try await makeLibrary("collision")
        let noteID = UUID()
        try seed(
            library,
            id: noteID,
            title: "先公开后私密",
            body: "原始正文",
            tags: [],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let data = try await library.archiveData()
        // 导出之后才把它标成私密：现在同一个包再导回来，不许把这条的内容换掉。
        _ = try await library.setPrivate(id: noteID, true, confirmed: true)
        let before = try XCTUnwrap(try NoteDatabase(path: library.fileURL.path).note(id: noteID))

        let report = try await library.importArchive(data)
        XCTAssertEqual(report.restored, 0)
        XCTAssertEqual(report.skippedPrivateExisting, 1)

        let after = try XCTUnwrap(try NoteDatabase(path: library.fileURL.path).note(id: noteID))
        XCTAssertEqual(after.title, before.title)
        XCTAssertEqual(after.body, before.body)
        XCTAssertEqual(after.updatedAt, before.updatedAt)
        XCTAssertTrue(after.isPrivate, "被跳过的私密条目必须仍是私密（不许顺手解除）")
    }

    // MARK: - 不是本产品的包 ⇒ 明确拒绝

    func testForeignFileIsRefusedAsNotABackupPackage() async throws {
        let library = try await makeLibrary("foreign")
        let foreign = try JSONSerialization.data(withJSONObject: [
            "format": "something.else", "formatVersion": 1, "notes": []
        ])
        do {
            _ = try await library.importArchive(foreign)
            XCTFail("不认识的格式必须拒绝")
        } catch let failure as NoteArchiveFailure {
            XCTAssertEqual(failure, .notABackupPackage("something.else"))
        }
    }
}
