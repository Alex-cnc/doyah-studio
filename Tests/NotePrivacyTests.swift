import XCTest
@testable import DoyahCore

// `FR-NTS-NOTE-PRIVACY-001`（私密保护）的机械证据：**不进搜索 / 不同步 / 不外发 / 需二次验证才可查看**。
//
// 三条纪律：
//   ① 每条「应该拦住」都配一条「公开笔记照常通过」的对照 —— 只判「私密被拦住」，
//      把整张表都拦住也能骗过去；
//   ② 泄漏面按**出口**各判一次（列表 / 搜索 / 同步 / 导出 / Agent / 揭示），
//      不拿「一个 canSync 为 false」去代替另外五个；
//   ③ 「撤私密要二次确认」判的是**行为**（不带确认就撤不掉），不是那个布尔常量本身。
final class NotePrivacyTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("doyah-note-privacy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    private func url(_ name: String = NoteLibrary.fileName) -> URL {
        directory.appendingPathComponent(name, isDirectory: false)
    }

    private func library() -> NoteLibrary {
        NoteLibrary(databaseURL: url())
    }

    private struct StubAuthorizer: NotePrivacyAuthorizing {
        let allowed: Bool
        func authorize(reason: String) async -> Bool { allowed }
    }

    /// 记下授权理由的桩件（判据「语言是传进来的」）：理由必须由调用方按当前语言给，
    /// `NoteLibrary.revealPrivate` 不许自带默认文案 —— 否则英文界面会弹出中文系统框。
    private final class ReasonRecordingAuthorizer: NotePrivacyAuthorizing, @unchecked Sendable {
        private let allowed: Bool
        private let lock = NSLock()
        private var recorded: [String] = []

        init(allowed: Bool) { self.allowed = allowed }

        var reasons: [String] {
            lock.lock(); defer { lock.unlock() }
            return recorded
        }

        func authorize(reason: String) async -> Bool {
            lock.lock(); recorded.append(reason); lock.unlock()
            return allowed
        }
    }

    // MARK: - ① 私密笔记不出现在检索结果（两条路都要判：短词走子串、长词走 FTS）

    func testPrivateNoteDisappearsFromSearchOnBothRoutes() async throws {
        let library = library()
        let note = try await library.save(
            NoteDraft(title: "私密骑行计划", body: "环洞庭湖的私密路线"),
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )

        // 对照：公开时两条路都找得到（2 字 → 子串兜底；4 字 → trigram 全文）。
        let publicShort = try await library.search("骑行")
        let publicLong = try await library.search("私密骑行")
        XCTAssertEqual(publicShort.notes.map(\.id), [note.id])
        XCTAssertEqual(publicLong.notes.map(\.id), [note.id])
        XCTAssertEqual(publicLong.route, .fullText, "长查询走的是全文检索那条路（判据覆盖的确实是 FTS）")
        XCTAssertEqual(publicShort.route, .substring, "短查询走的是子串兜底那条路")

        _ = try await library.setPrivate(id: note.id, true)

        let privateShort = try await library.search("骑行")
        let privateLong = try await library.search("私密骑行")
        XCTAssertTrue(privateShort.notes.isEmpty, "私密笔记不出现在检索结果（子串路）")
        XCTAssertTrue(privateLong.notes.isEmpty, "私密笔记不出现在检索结果（全文路）")
    }

    // MARK: - 「需二次验证才可查看」的列表面

    func testPrivateNoteLeavesTheListButKeepsALockPlate() async throws {
        let library = library()
        let note = try await library.save(NoteDraft(title: "藏着的那条", body: "正文"), now: Date(timeIntervalSince1970: 1_700_000_000))
        let visibleBefore = try await library.load()
        XCTAssertEqual(visibleBefore.count, 1, "对照：公开时在列表里")

        _ = try await library.setPrivate(id: note.id, true)

        let visibleAfter = try await library.load()
        XCTAssertTrue(visibleAfter.isEmpty, "私密条目不进列表")
        let plates = try await library.privateSummaries()
        XCTAssertEqual(plates.map(\.id), [note.id])
        XCTAssertEqual(plates.first?.title, "藏着的那条", "门牌给标题，好让人知道有这么一条")
        XCTAssertEqual(plates.first?.versionCount, 1)
    }

    // MARK: - ② 不外发：同步 / 导出 / Agent 三条出口各判一次

    func testPrivateNoteCannotLeaveTheDeviceButPublicOnesCan() {
        let publicNote = Note(title: "公开", body: "正文")
        var privateNote = publicNote
        privateNote.isPrivate = true

        XCTAssertTrue(NotePrivacy.canSync(publicNote))
        XCTAssertTrue(NotePrivacy.canExport(publicNote))
        XCTAssertTrue(NotePrivacy.canSendToAgent(publicNote))
        XCTAssertTrue(NotePrivacy.isSearchable(publicNote))

        XCTAssertFalse(NotePrivacy.canSync(privateNote), "不同步")
        XCTAssertFalse(NotePrivacy.canExport(privateNote), "不导出")
        XCTAssertFalse(NotePrivacy.canSendToAgent(privateNote), "不外发到 Agent / IM")
        XCTAssertFalse(NotePrivacy.isSearchable(privateNote), "不进搜索")
    }

    // MARK: - ③ 取消私密需二次确认

    func testUnprivateWithoutConfirmationIsRefusedAndTheFlagStays() async throws {
        let library = library()
        let note = try await library.save(NoteDraft(title: "秘密", body: "正文"), now: Date(timeIntervalSince1970: 1_700_000_000))
        let marked = try await library.setPrivate(id: note.id, true)
        XCTAssertEqual(marked, .changed(1))

        let refused = try await library.setPrivate(id: note.id, false)
        XCTAssertEqual(refused, .confirmationRequired, "撤私密不带二次确认 ⇒ 拒绝")
        let stillPrivate = try await library.isPrivate(id: note.id)
        XCTAssertEqual(stillPrivate, true, "拒绝之后它必须还是私密")

        let confirmed = try await library.setPrivate(id: note.id, false, confirmed: true)
        XCTAssertEqual(confirmed, .changed(1))
        let afterUnprivate = try await library.isPrivate(id: note.id)
        XCTAssertEqual(afterUnprivate, false)
        let visible = try await library.load()
        XCTAssertEqual(visible.count, 1, "撤掉之后回到列表")
    }

    // MARK: - 揭示（二次验证）四档出口

    func testRevealNeedsAuthorizationAndNeverLeaksOnDenial() async throws {
        let library = library()
        let note = try await library.save(NoteDraft(title: "秘密", body: "正文内容"), now: Date(timeIntervalSince1970: 1_700_000_000))
        _ = try await library.setPrivate(id: note.id, true)

        let denied = try await library.revealPrivate(id: note.id, authorizer: StubAuthorizer(allowed: false), reason: "unlock for test")
        XCTAssertEqual(denied, .denied, "验证没过 ⇒ 拒绝，内容一个字都不返回")

        let revealed = try await library.revealPrivate(id: note.id, authorizer: StubAuthorizer(allowed: true), reason: "unlock for test")
        guard case .revealed(let payload) = revealed else {
            return XCTFail("验证通过应该拿到内容，实际 = \(revealed)")
        }
        XCTAssertEqual(payload.note.body, "正文内容")
        XCTAssertEqual(payload.versions.count, 1, "看内容时历史版本一起给（回滚要在看得见的地方）")

        let publicNote = try await library.save(NoteDraft(title: "公开的", body: "正文"), now: Date(timeIntervalSince1970: 1_700_000_100))
        let notPrivate = try await library.revealPrivate(id: publicNote.id, authorizer: StubAuthorizer(allowed: true), reason: "unlock for test")
        XCTAssertEqual(notPrivate, .notPrivate, "公开笔记不该走「二次验证」这条门")

        let missing = try await library.revealPrivate(id: UUID(), authorizer: StubAuthorizer(allowed: true), reason: "unlock for test")
        XCTAssertEqual(missing, .notFound)
    }

    /// **判据「语言是传进来的」**：系统验证框里那句话由调用方给（`L(.notesPrivateUnlockReason)`），
    /// 本层不许自带默认中文字面量 —— 英文界面弹中文框是真缺陷，也让本地化棘轮 A 多记一条欠账。
    func testRevealPassesTheCallersReasonToTheAuthorizer() async throws {
        let library = library()
        let note = try await library.save(
            NoteDraft(title: "私密", body: "正文"),
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )
        _ = try await library.setPrivate(id: note.id, true)

        let recorder = ReasonRecordingAuthorizer(allowed: true)
        let english = "Authenticate to open this private note"
        let outcome = try await library.revealPrivate(id: note.id, authorizer: recorder, reason: english)
        guard case .revealed = outcome else {
            return XCTFail("验证通过应该拿到内容，实际 = \(outcome)")
        }
        XCTAssertEqual(recorder.reasons, [english], "授权框里那句话必须是调用方给的那一句，不许被本层换掉")
    }

    /// **防静默泄漏**：把私密笔记改几个字再保存，私密挡位不许被 `upsert` 的 `ON CONFLICT` 段抹掉。
    func testSavingAPrivateNoteDoesNotClearTheFlag() async throws {
        let library = library()
        let note = try await library.save(NoteDraft(title: "秘密", body: "原文"), now: Date(timeIntervalSince1970: 1_700_000_000))
        _ = try await library.setPrivate(id: note.id, true)

        _ = try await library.save(NoteDraft(title: "秘密", body: "改了两个字"), id: note.id, now: Date(timeIntervalSince1970: 1_700_000_100))
        let stillPrivate = try await library.isPrivate(id: note.id)
        XCTAssertEqual(stillPrivate, true, "改正文保存不许把私密抹掉")
        let found = try await library.search("改了两个字")
        XCTAssertTrue(found.notes.isEmpty, "改完之后仍然搜不到")
    }
}
