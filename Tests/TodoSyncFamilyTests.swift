import XCTest
@testable import DoyahCore

/// `FR-NTS-TODO-LIST-001` 判据①②的机械证据 —— **待办本体四字段** + **与笔记同一条同步链路**。
///
/// 覆盖范围（先声明，免得被读成「全都判了」）：
///   · 判据①（四字段齐全且可编辑）：`Todo` 模型层 + schema v14 落库 + 归一规则 + 空值语义；
///     **界面层**只判「视图读的是 Core 给的那一份」（源锚点见 `verify-ui-interactions.sh`），
///     真鼠标点选未点（如实记）。
///   · 判据②（同一条链路、不做第二套）：一个 `SyncQueue`、一个 `CloudSyncService`、一份退避、
///     一份决胜；待办上行的表是 `todos`（这里用假 PostgREST 记 URL 与行）。
///   · 判据③（加密）：本仓笔记侧**没有开启**存储层加密（概设 §15.6：加密属整库层的事）⇒
///     这一条**不判通过**，只判「与笔记同一条存储 / 导出链路、不另开第二套」，加密本身记未覆盖。
final class TodoSyncFamilyTests: XCTestCase {

    // MARK: - 假 PostgREST（按表分行的内存服务端）

    private final class FakePostgrest: CloudAuthTransport, @unchecked Sendable {
        var online = true
        /// 表名 → (uid → 行)：两张表各自一份，用来证明「待办没有走 notes 表」。
        var tables: [String: [String: CloudNoteRow]] = ["notes": [:], "todos": [:]]
        /// 记账：每次请求的（方法 · 路径里的表名）。
        var calls: [(method: String, table: String)] = []

        func send(_ request: CloudAuthHTTPRequest) throws -> CloudAuthHTTPResponse {
            guard online else { throw CloudSyncError.transport("offline (fake postgrest)") }
            let table = request.url.pathComponents.last ?? ""
            calls.append((request.method, table))

            let components = URLComponents(url: request.url, resolvingAgainstBaseURL: false)
            let query = Dictionary(
                (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") },
                uniquingKeysWith: { first, _ in first }
            )

            switch request.method {
            case "POST":
                guard let body = request.body,
                      let upload = try? CloudSyncCoding.decoder().decode(CloudNoteRow.Upload.self, from: body)
                else {
                    return CloudAuthHTTPResponse(status: 400, body: Data("bad body".utf8))
                }
                let stored = CloudNoteRow(
                    uid: upload.uid,
                    ownerId: "test-owner",
                    title: upload.title,
                    content: upload.content,
                    contentType: upload.contentType,
                    notebookUid: upload.notebookUid,
                    tags: upload.tags,
                    pinned: upload.pinned,
                    rev: upload.rev,
                    updatedAt: upload.updatedAt,
                    deletedAt: upload.deletedAt,
                    deviceId: upload.deviceId
                )
                tables[table, default: [:]][upload.uid] = stored
                return CloudAuthHTTPResponse(status: 201, body: try! CloudSyncCoding.encoder().encode([stored]))
            case "GET":
                let rows = tables[table] ?? [:]
                if let uid = query["uid"], uid.hasPrefix("eq.") {
                    let hit = rows[String(uid.dropFirst(3))].map { [$0] } ?? []
                    return CloudAuthHTTPResponse(
                        status: 200,
                        body: (try? CloudSyncCoding.encoder().encode(hit)) ?? Data("[]".utf8)
                    )
                }
                let all = rows.values.sorted { $0.updatedAt < $1.updatedAt }
                return CloudAuthHTTPResponse(
                    status: 200,
                    body: (try? CloudSyncCoding.encoder().encode(all)) ?? Data("[]".utf8)
                )
            default:
                return CloudAuthHTTPResponse(status: 405, body: Data())
            }
        }
    }

    private final class MutableClock: @unchecked Sendable {
        var now: Date
        init(_ now: Date) { self.now = now }
    }

    private struct StubNoteSource: CloudNoteSource {
        var rows: [String: CloudNoteRow]
        func cloudRow(uid: String) async throws -> CloudNoteRow? { rows[uid] }
    }

    private struct StubTodoSource: CloudTodoSource {
        var rows: [String: CloudNoteRow]
        func todoCloudRow(uid: String) async throws -> CloudNoteRow? { rows[uid] }
    }

    private func makeService(
        _ transport: FakePostgrest,
        clock: MutableClock = MutableClock(Date(timeIntervalSince1970: 1_790_000_000)),
        store: CloudSyncStateStore = MemoryCloudSyncStateStore()
    ) throws -> CloudSyncService {
        try CloudSyncService(
            endpoints: CloudSyncEndpoints(environmentID: "doyah-notes-test-env"),
            transport: transport,
            stateStore: store,
            tokenProvider: { "test-access-token" },
            now: { clock.now }
        )
    }

    private func row(uid: String, updatedAt: TimeInterval, content: String = "{\"v\":1}") -> CloudNoteRow {
        CloudNoteRow(
            uid: uid,
            title: "样例",
            content: content,
            contentType: "application/json",
            notebookUid: nil,
            tags: nil,
            pinned: nil,
            rev: 0,
            updatedAt: Date(timeIntervalSince1970: updatedAt),
            deletedAt: nil,
            deviceId: "mac-test"
        )
    }

    // MARK: - 判据②：一个队列装两类对象

    /// 笔记与待办进**同一个队列**（一条欠账各一行、家族不同），不是两条队列。
    func testTodoAndNoteQueueIntoOneQueueWithTheirOwnFamily() throws {
        let transport = FakePostgrest()
        let service = try makeService(transport)

        try service.enqueue(uid: "note-a", family: .note)
        try service.enqueue(uid: "todo-a", family: .todo)

        XCTAssertEqual(service.pendingCount, 2, "一条队列装两条欠账（不是各开一条队列）")
        let families = Set(service.pendingEntries.map(\.family))
        XCTAssertEqual(families, [.note, .todo], "两条欠账的家族各自对得上")
    }

    /// 同一个 `uid` 出现在两个家族里 ⇒ **两条欠账**（去重键是 `(family, uid)`）。
    func testSameUIDOnBothFamiliesIsTwoEntries() throws {
        let transport = FakePostgrest()
        let service = try makeService(transport)

        try service.enqueue(uid: "same-uid", family: .note)
        try service.enqueue(uid: "same-uid", family: .todo)

        XCTAssertEqual(service.pendingCount, 2)
        XCTAssertTrue(service.pendingEntries.contains { $0.uid == "same-uid" && $0.family == .note })
        XCTAssertTrue(service.pendingEntries.contains { $0.uid == "same-uid" && $0.family == .todo })
    }

    /// 重放时**按家族各上各的表**：笔记走 `notes`，待办走 `todos`。
    func testFlushPushesTodosToTheTodosTableThroughTheSameService() async throws {
        let transport = FakePostgrest()
        let service = try makeService(transport)
        let noteRow = row(uid: "note-a", updatedAt: 1_790_000_000)
        let todoRow = row(uid: "todo-a", updatedAt: 1_790_000_001, content: "{\"title\":\"待办\"}")

        try service.enqueue(uid: "note-a", family: .note)
        try service.enqueue(uid: "todo-a", family: .todo)

        let report = try await service.flush(
            source: StubNoteSource(rows: ["note-a": noteRow]),
            todoSource: StubTodoSource(rows: ["todo-a": todoRow])
        )

        XCTAssertEqual(report.succeeded, 2)
        XCTAssertEqual(report.pending, 0)
        XCTAssertNotNil(transport.tables["todos"]?["todo-a"], "待办上行到 `todos` 表")
        XCTAssertNotNil(transport.tables["notes"]?["note-a"], "笔记仍走 `notes` 表")
        XCTAssertNil(transport.tables["notes"]?["todo-a"], "待办**不许**混进笔记表")
        XCTAssertNil(transport.tables["todos"]?["note-a"])
    }

    /// 断网 ⇒ 待办留在队列、退避；恢复后一次补传（`IR-21` 对两个家族是同一条路）。
    func testOfflineTodoStaysQueuedThenFlushesOnReconnect() async throws {
        let transport = FakePostgrest()
        transport.online = false
        let clock = MutableClock(Date(timeIntervalSince1970: 1_790_000_000))
        let service = try makeService(transport, clock: clock)
        let todoRow = row(uid: "todo-offline", updatedAt: 1_790_000_000)

        try service.enqueue(uid: "todo-offline", family: .todo)
        let first = try await service.flush(
            source: StubNoteSource(rows: [:]),
            todoSource: StubTodoSource(rows: ["todo-offline": todoRow])
        )
        XCTAssertEqual(first.succeeded, 0)
        XCTAssertEqual(first.failed, 1)
        XCTAssertEqual(first.pending, 1, "断网不许丢欠账")

        transport.online = true
        clock.now = clock.now.addingTimeInterval(60)
        let second = try await service.flush(
            source: StubNoteSource(rows: [:]),
            todoSource: StubTodoSource(rows: ["todo-offline": todoRow])
        )
        XCTAssertEqual(second.succeeded, 1, "恢复后补传一条")
        XCTAssertEqual(second.pending, 0)
        XCTAssertEqual(transport.tables["todos"]?["todo-offline"]?.rev, 1)
    }

    /// 删除：本地已经**物理删**（取不到行）⇒ 仍要上行墓碑（`uid` + `rev` + `deleted_at` 就够）。
    func testTodoDeleteSendsTombstoneWithoutNeedingTheLocalRow() async throws {
        let transport = FakePostgrest()
        let service = try makeService(transport)

        try service.enqueue(uid: "todo-gone", operation: .delete, family: .todo)
        let report = try await service.flush(
            source: StubNoteSource(rows: [:]),
            todoSource: StubTodoSource(rows: [:])   // 本地已经没有了
        )

        XCTAssertEqual(report.succeeded, 1, "墓碑不依赖本地那一行还在")
        let stored = try XCTUnwrap(transport.tables["todos"]?["todo-gone"])
        XCTAssertNotNil(stored.deletedAt, "上行体的 `deleted_at` 非空")
        XCTAssertEqual(stored.rev, 1, "删除也是一次版本（rev 照常 +1）")
    }

    /// 增量游标**按家族各一格**：拉待办不会把笔记的游标推走（反之亦然）。
    func testTodoCursorIsSeparateFromNotesCursor() throws {
        let transport = FakePostgrest()
        transport.tables["notes"] = ["note-x": row(uid: "note-x", updatedAt: 1_790_000_010)]
        transport.tables["todos"] = ["todo-y": row(uid: "todo-y", updatedAt: 1_790_000_020)]
        let service = try makeService(transport)

        _ = try service.pull(family: .todo)

        XCTAssertNotNil(service.cursor(for: .todo).updatedAfter, "待办游标走了一步")
        XCTAssertNil(service.cursor(for: .note).updatedAfter, "笔记游标一步都没动（两条表各走各的）")
    }

    /// 旧状态文件（队列条目里没有 `family` 这一格）⇒ 读成笔记，**不整份解不出来**。
    func testLegacyQueueEntryWithoutFamilyDecodesAsNote() throws {
        let json = """
        [{"uid":"old-a","operation":"upsert","attempts":1,
          "enqueuedAt":790000000,"nextAttemptAt":790000000}]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let entries = try decoder.decode([SyncQueueEntry].self, from: Data(json.utf8))

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].family, .note, "缺这一格的旧条目按笔记落")
        XCTAssertEqual(entries[0].attempts, 1, "其它字段原样读回来")
    }
}
