import XCTest
@testable import DoyahCore

// **删除 = 墓碑**（契约 §6.4.1 / `IR-17`）的机械判据。
//
// 由头（2026-10-09 人类主人真机点验缺陷 `T-20261009-161` / `-162` / `-163`，原话逐字）：
//   · 「竟然测出一个没实现功能：删除笔记的按钮是在，但却不能删除所选笔记。」
//   · 「点删除有弹出确认框，点了确认删除，还是没能删除笔记。」
// 前门实测证据：云端墓碑 0 条 · 本地 `note` 表仍 2 行且删除期间无落盘 · `cloud-sync-state.json`
// 的 `queue` 是空的。⇒ 缺陷面 = **静默面**（没命中的删除不报错）+ **契约相抵**（本地物理删 vs
// 契约要求的墓碑），两处都由本文件的用例钉住。
//
// 三条口径（与仓里其它存储判据同源）：
//   ① 都跑**真库文件**（临时目录），不用 `:memory:` —— 墓碑列、FTS 外部内容表、WAL 在内存库里不是一回事；
//   ② **成对**：改前（物理删 / 静默 no-op）与改后（墓碑 / 抛错）各有一条断言，判据不是「跑通了就算」；
//   ③ **负例不许缺席**：没命中的删除必须**抛错**（`noteNotFound`），「什么都没发生」正是本次缺陷的本体。
final class NoteDeletionTombstoneTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("doyah-note-tombstone-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    // MARK: - 夹具

    private var url: URL { directory.appendingPathComponent(NoteLibrary.fileName, isDirectory: false) }

    private func library() -> NoteLibrary { NoteLibrary(databaseURL: url) }

    private func draft(title: String, body: String = "正文", tags: [String] = []) -> NoteDraft {
        NoteDraft(title: title, body: body, tags: tags)
    }

    /// 读库的原始行数（绕过一切过滤 —— 判据要看的是**表里真的有什么**，不是「读出来像什么」）。
    private func rawCount(_ sql: String) throws -> Int64 {
        let connection = try SQLiteConnection(path: url.path)
        defer { try? connection.close() }
        return try connection.scalarInt(sql) ?? -1
    }

    private let at = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - ① 删除落成墓碑（行还在、`deleted_at` 非空）

    /// **判据①**：删一条 ⇒ ① 列表 / 计数看不见它；② 表里**那一行还在**（墓碑，不是物理删）。
    func testDeletingLandsAsTombstoneAndLeavesThePhysicalRow() async throws {
        let store = library()
        let note = try await store.upsert(draft(title: "要删的", tags: ["骑行"]))

        let before = try await store.load()
        XCTAssertEqual(before.count, 1, "前提：先真的写进去了一条")
        try await store.delete(id: note.id, at: at)

        // ① 活着的读出口一律看不见它
        let after = try await store.load()
        XCTAssertTrue(after.isEmpty, "墓碑行还出现在列表里")
        let database = try NoteDatabase(path: url.path)
        XCTAssertEqual(try database.noteCount(), 0, "活着的笔记数应当归零")
        XCTAssertNil(try database.note(id: note.id), "按 id 也不该读得出来")

        // ② **表里那一行还在**（这正是本次修复的落点：改前这里是物理 `DELETE`）
        XCTAssertEqual(
            try rawCount("SELECT count(*) FROM note WHERE deleted_at IS NOT NULL"), 1,
            "删除必须落成墓碑（`deleted_at` 非空），不许物理删 —— 行没了删除就传不出去"
        )
        XCTAssertEqual(try rawCount("SELECT count(*) FROM note"), 1, "行被物理删了（墓碑应当把行留下）")
        XCTAssertNotNil(try database.deletedAt(id: note.id), "墓碑时刻没落下来")

        // ③ 同步面还读得到它（墓碑要能上行）
        XCTAssertNotNil(try database.noteIncludingDeleted(id: note.id), "同步面读不到墓碑行 ⇒ 墓碑永远发不出去")
    }

    /// **判据①b**：墓碑行**不再出现在检索里**，且 FTS 外部内容表里没有残留（改前的物理删靠触发器，
    /// 墓碑是 `UPDATE` ⇒ 必须自己把旧值喂给 FTS5，否则「删了还搜得到」）。
    func testTombstonedNoteLeavesListSearchAndCountAndKeepsNoOrphans() async throws {
        let store = library()
        let note = try await store.upsert(draft(title: "洞庭湖拉练", body: "第一天", tags: ["骑行"]))
        try NoteDatabase(path: url.path).addAttachment(NoteAttachment(path: "/tmp/a.txt"), to: note.id)

        let hit = try await store.search("洞庭湖")
        XCTAssertEqual(hit.notes.count, 1, "前提：删之前搜得到")
        try await store.delete(id: note.id, at: at)

        let miss = try await store.search("洞庭湖")
        XCTAssertTrue(miss.notes.isEmpty, "墓碑行还能被搜到（FTS 没清干净）")
        // 注意：`note_fts` 是**外部内容表**，`count(*)` 读的是内容表（`note`）—— 墓碑行的内容还在，
        // 所以这里量的必须是**倒排索引**（`MATCH`），不是行数。
        XCTAssertEqual(
            try rawCount("SELECT count(*) FROM note_fts WHERE note_fts MATCH '洞庭湖'"), 0,
            "倒排索引里还留着墓碑行的词（删了还搜得到）"
        )
        for table in ["note_tag", "note_timeline", "note_attachment"] {
            XCTAssertEqual(
                try rawCount("SELECT count(*) FROM \(table)"), 0,
                "\(table) 该随删除一起走（它们是这条笔记的私有派生物，没有跨端身份）"
            )
        }
    }

    // MARK: - ② 负例：没命中的删除**必须报错**，不许静默 no-op

    /// **判据②（负例 · 本次缺陷的本体）**：删一条**库里没有的** uuid ⇒ 抛 `noteNotFound`，
    /// 且库一个字节都不动。改前这里是一句静默的 `DELETE`（`changeCount == 0` 没人看）。
    func testDeletingAnUnknownNoteThrowsInsteadOfSilentlyDoingNothing() async throws {
        let store = library()
        _ = try await store.upsert(draft(title: "留下的"))
        _ = try NoteDatabase(path: url.path)   // 先把库与 schema 立起来

        let ghost = UUID()
        do {
            try await store.delete(id: ghost, at: at)
            XCTFail("删一条不存在的笔记居然是成功的（静默 no-op = 用户看到「点了没反应」）")
        } catch let error as NoteStorageFailure {
            guard case .noteNotFound(let id) = error else {
                return XCTFail("抛的不是 noteNotFound：\(error)")
            }
            XCTAssertEqual(id, ghost.uuidString, "报错要把没找到的那个 uuid 说出来")
        }

        XCTAssertEqual(try rawCount("SELECT count(*) FROM note WHERE deleted_at IS NOT NULL"), 0, "没命中的删除却落了墓碑")
        let survived = try await store.load()
        XCTAssertEqual(survived.count, 1, "没命中的删除动了库")
    }

    /// **判据②b**：同一条删两次 ⇒ 第二次**同样报错**（第二次它已经是墓碑了，不是「又删成功了一次」）。
    func testDeletingTheSameNoteTwiceIsNotSilent() async throws {
        let store = library()
        let note = try await store.upsert(draft(title: "只删一次"))

        try await store.delete(id: note.id, at: at)
        do {
            try await store.delete(id: note.id, at: at.addingTimeInterval(60))
            XCTFail("第二次删同一条又成功了（墓碑被覆盖 / 静默通过）")
        } catch let error as NoteStorageFailure {
            guard case .noteNotFound = error else { return XCTFail("抛的不是 noteNotFound：\(error)") }
        }
        XCTAssertEqual(
            try rawCount("SELECT count(*) FROM note WHERE deleted_at = \(at.timeIntervalSince1970)"), 1,
            "第二次删除改写了第一次的墓碑时刻（墓碑时刻必须保持第一次那个）"
        )
    }

    /// **判据②c**：库还不存在时删一条 ⇒ 返回 `false`（没有任何东西被删），**不顺手建一个空库**。
    func testDeletingFromAnAbsentLibraryReportsNothingWasDeleted() async throws {
        let store = library()
        let removed = try await store.delete(id: UUID(), at: at)
        XCTAssertFalse(removed, "库都不存在，却报「删掉了一件」")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "删一条顺手把空库造出来了")
    }

    // MARK: - ③ 同步队列的墓碑项 + `rev` +1（契约 v3.96 新纪律）

    /// **判据③**：删除入队的是**墓碑项**（`operation = .delete`），且该 `uid` 的下一次上行 `rev`
    /// **严格 +1** —— 契约 v3.96：`rev` 不自动递增，墓碑不 +1 就会被另一端的 LWW 覆盖回来
    /// （前门亲手实测：`PATCH` 置 `deleted_at` 后 `rev` 没变）。
    func testDeletionEnqueuesATombstoneUploadAndBumpsTheRevision() async throws {
        let store = MemoryCloudSyncStateStore()
        let service = try CloudSyncService(
            endpoints: CloudSyncEndpoints(environmentID: "test-env"),
            transport: RefusingTransport(),
            stateStore: store,
            tokenProvider: { "token" }
        )
        let uid = "E1DA45F4-8DB0-45F6-B215-4709030C4201"

        _ = try service.enqueue(uid: uid, operation: .upsert)
        XCTAssertEqual(service.pendingCount, 1, "前提：先欠了一笔上行")

        // 同一 `uid` 换成删除 ⇒ 队列里那一条**变成墓碑项**（同 uid 只有一条，后写的操作种类覆盖先写的）
        XCTAssertFalse(try service.enqueue(uid: uid, operation: .delete), "同一条 uid 不该入队两次")
        let ready = service.readyEntries()
        XCTAssertEqual(ready.count, 1)
        XCTAssertEqual(ready.first?.operation, .delete, "队列里欠的不是墓碑项")

        // `rev` +1：改前 `rev` 不动 ⇒ 另一端持更高 `rev` 的副本会把删除覆盖回来
        let before = service.revision(for: uid)
        XCTAssertEqual(service.nextRevision(for: uid), before + 1, "墓碑上行的 rev 必须严格 +1")
        XCTAssertEqual(try store.load().queue.count, 1, "队列没落盘（断网重试要能接着重放）")
    }

    /// **判据③b**：同步面现取本地行时**读得到墓碑**（`deleted_at` 非空）。
    /// 改前那条物理删之后 `cloudRow` 返回 `nil` ⇒ `flush` 把那笔欠账**就地销账**，
    /// 云端永远不知道这条被删了（「删了又被拉回来」的成因之一）。
    func testCloudSourceStillSeesTheTombstonedRow() async throws {
        let store = library()
        let note = try await store.upsert(draft(title: "墓碑上行"))
        try await store.delete(id: note.id, at: at)

        let source = NoteLibraryCloudSource(library: store)
        let row = try await source.cloudRow(uid: note.id.uuidString)
        let tombstone = try XCTUnwrap(row, "墓碑行读不到 ⇒ 墓碑永远发不出去")
        XCTAssertNotNil(tombstone.deletedAt, "上行的墓碑项里 `deleted_at` 是空的")
    }
}

/// 出网传输的假实现：本文件的判据**一行网络都不发**（进队 / `rev` / 现取本地行都是纯逻辑）。
/// 它的存在只是为了让「不该发请求的用例」在真发请求时**当场炸**，而不是悄悄连出去。
private struct RefusingTransport: CloudAuthTransport {
    struct Unexpected: Error {}

    func send(_ request: CloudAuthHTTPRequest) throws -> CloudAuthHTTPResponse {
        throw Unexpected()
    }
}
