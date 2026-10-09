import XCTest
@testable import DoyahCore

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// `云D` 的**端到端最小闭环**判据（上传 `IR-16` + 增量下拉 `IR-15` + 断网重试 `IR-21`）。
///
/// 两条口径写在文件头，免得被下一个改它的人重新猜：
///
///  ① **默认全脱网**：这一组用例打的是 `CloudSyncService` —— 而它只经一个**假传输**
///     （`FakePostgrest`，一个内存里的小 PostgREST）出网。「不依赖真实链路」不是省事，
///     是判据要求（卡片判据 ④：网络可用 `URLProtocol` / 注入桩，不依赖真实链路）。
///  ② **真跑那一条单独门**：`testLiveCloudRoundTrip` 只在 `DOYAH_SYNC_E2E_LIVE=1` 时开跑
///     （默认 `XCTSkip`）——真账号口令从**仓外**读取，不落仓、不入日志、不打印。
final class NoteSyncE2ETests: XCTestCase {

    // MARK: - 假 PostgREST（内存服务端）

    /// 一个够用的内存 PostgREST：只认本片用到的那几种请求形状。
    ///
    /// 它同时是**断网开关**（`online == false` ⇒ 抛一个出网层错误）——「断网重试」这条判据
    /// 就是拿它把「网络不可用」变成可复现的输入，而不是靠拔网线。
    private final class FakePostgrest: CloudAuthTransport, @unchecked Sendable {
        var online = true
        /// 服务端持有的人行（`uid` → 行）。
        var rows: [String: CloudNoteRow] = [:]
        /// 记账（发给服务端的每一个请求）。
        var requests: [(method: String, url: URL, headers: [String: String], body: Data?)] = []
        /// 冒充的归属主键（`DEFAULT auth.uid()` 在服务端填的就是它）。
        var ownerId = "2108556584330371073"

        func send(_ request: CloudAuthHTTPRequest) throws -> CloudAuthHTTPResponse {
            guard online else {
                throw CloudSyncError.transport("offline (fake postgrest)")
            }
            requests.append((request.method, request.url, request.headers, request.body))

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
                // `owner_id` 由「服务端」按 `auth.uid()` 填 —— 上行体里没有它（合成默认值）。
                let stored = CloudNoteRow(
                    uid: upload.uid,
                    ownerId: ownerId,
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
                rows[upload.uid] = stored
                return CloudAuthHTTPResponse(status: 201, body: try! CloudSyncCoding.encoder().encode([stored]))
            case "GET":
                if let uid = query["uid"], uid.hasPrefix("eq.") {
                    let key = String(uid.dropFirst(3))
                    let hit = rows[key].map { [$0] } ?? []
                    return CloudAuthHTTPResponse(status: 200, body: (try? CloudSyncCoding.encoder().encode(hit)) ?? Data("[]".utf8))
                }
                var all = Array(rows.values)
                if let after = query["updated_at"], after.hasPrefix("gte."),
                   let bound = CloudSyncCoding.parseDate(String(after.dropFirst(4))) {
                    all = all.filter { $0.updatedAt >= bound }
                }
                all.sort { $0.updatedAt < $1.updatedAt }
                return CloudAuthHTTPResponse(status: 200, body: (try? CloudSyncCoding.encoder().encode(all)) ?? Data("[]".utf8))
            default:
                return CloudAuthHTTPResponse(status: 405, body: Data())
            }
        }
    }

    /// 可注入时钟（退避是**按时间推进**的：`ready(at:)` 只在到点后才放行，
    /// 所以「断网 → 退避 → 联网补传」这条链在测试里必须能推动时间，而不是靠真实等待）。
    private final class MutableClock: @unchecked Sendable {
        var now: Date
        init(_ now: Date) { self.now = now }
        func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
    }

    private func makeService(
        _ transport: FakePostgrest,
        clock: MutableClock = MutableClock(Date(timeIntervalSince1970: 1_790_000_000)),
        store: CloudSyncStateStore = MemoryCloudSyncStateStore(),
        token: @escaping @Sendable () throws -> String = { "test-access-token" }
    ) throws -> CloudSyncService {
        try CloudSyncService(
            endpoints: CloudSyncEndpoints(environmentID: "doyah-notes-test-env"),
            transport: transport,
            stateStore: store,
            tokenProvider: token,
            now: { clock.now }
        )
    }

    private func row(
        uid: String,
        rev: Int,
        updatedAt: TimeInterval,
        content: String = "{\"spans\":[]}",
        deletedAt: TimeInterval? = nil
    ) -> CloudNoteRow {
        CloudNoteRow(
            uid: uid,
            title: "样例",
            content: content,
            contentType: "application/json",
            notebookUid: nil,
            tags: ["同步"],
            pinned: false,
            rev: rev,
            updatedAt: Date(timeIntervalSince1970: updatedAt),
            deletedAt: deletedAt.map { Date(timeIntervalSince1970: $0) },
            deviceId: "mac-test"
        )
    }

    /// 只读现取一行的桩：给队列重放用。
    private struct StubSource: CloudNoteSource {
        var rows: [String: CloudNoteRow]
        func cloudRow(uid: String) async throws -> CloudNoteRow? { rows[uid] }
    }

    // MARK: - 判据 ① 上行 `IR-16`：整行成形 · `owner_id` 不在上行体里

    func testUploadSendsRowWithoutOwnerIdAndIsAccepted() throws {
        let transport = FakePostgrest()
        let service = try makeService(transport)
        let note = row(uid: "8C4E2B10-5A7D-4F31-9E62-B0D3C7A95F48", rev: 0, updatedAt: 1_790_000_000)

        let merge = try service.push(row: note, rev: 1)

        XCTAssertEqual(merge.verdict, .accepted)
        XCTAssertEqual(service.revision(for: note.uid), 1, "上行成功后本地版本账应推进到 1")

        // 上行体里**没有** owner_id（服务端默认 auth.uid() 填）。
        let post = try XCTUnwrap(transport.requests.first { $0.method == "POST" })
        let body = try XCTUnwrap(post.body)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertNil(json["owner_id"], "上行体不许自带 owner_id")
        XCTAssertEqual(json["rev"] as? Int, 1)
        XCTAssertEqual(post.headers["Prefer"], "resolution=merge-duplicates,return=representation")
        // 端点形状照官方 HTTP API 规范（数据面 `/v1/rdb/rest/notes`）。
        XCTAssertTrue(post.url.path.hasSuffix("/v1/rdb/rest/notes"), "实际路径：\(post.url.path)")

        // 服务端存下来的那一行 `owner_id` = 测试账号 uid（由服务端填）。
        XCTAssertEqual(transport.rows[note.uid]?.ownerId, transport.ownerId)
    }

    // MARK: - 判据 ② 增量下拉 `IR-15`：`updated_after` 游标

    func testIncrementalPullUsesCursorAndDoesNotRefetch() throws {
        let transport = FakePostgrest()
        transport.rows["note-a"] = row(uid: "note-a", rev: 1, updatedAt: 100)
        transport.rows["note-b"] = row(uid: "note-b", rev: 1, updatedAt: 200)
        let service = try makeService(transport)

        let first = try service.pull()
        XCTAssertEqual(first.fetched, 2)
        XCTAssertEqual(first.unseen, 2, "首次拉取两行都是新的")
        XCTAssertEqual(service.cursor.updatedAfter, Date(timeIntervalSince1970: 200))

        // 第二次：游标已推进 ⇒ 服务器若仍回同刻的旧行，本地不再重复应用（去重）。
        let second = try service.pull()
        XCTAssertEqual(second.unseen, 0, "同刻边界行不再重复决胜")

        // 新写一条更新的 ⇒ 只拉回它（`gte` 会把同刻的边界行一并带回，本地再去重）。
        transport.rows["note-c"] = row(uid: "note-c", rev: 1, updatedAt: 300)
        let third = try service.pull()
        XCTAssertEqual(third.fetched, 2, "gte 游标会把同刻边界行一并带回")
        XCTAssertEqual(third.unseen, 1, "真正新见的只有 note-c")
        XCTAssertEqual(third.verdicts["note-c"], .accepted)

        let getURLs = transport.requests.filter { $0.method == "GET" }.map(\.url.absoluteString)
        XCTAssertTrue(getURLs.contains { $0.contains("updated_at=gte.") }, "第二次起应带 updated_after 游标：\(getURLs)")
    }

    // MARK: - 判据 ③ 断网重试 `IR-21`：入队 1 ⇒ 联网自动补传恰 1

    func testOfflineWriteQueuesThenFlushUploadsExactlyOnce() async throws {
        let transport = FakePostgrest()
        transport.online = false                       // 断网
        let clock = MutableClock(Date(timeIntervalSince1970: 1_790_000_000))
        let service = try makeService(transport, clock: clock)
        let note = row(uid: "note-offline", rev: 0, updatedAt: 1_790_000_000)
        let source = StubSource(rows: [note.uid: note])

        // 断网写入一条：入队 1，一次 POST 都没发出去。
        let offline = try await service.enqueueAndPush(uid: note.uid, source: source)
        XCTAssertEqual(service.pendingCount, 1, "断网写入应留 1 条欠账")
        XCTAssertEqual(transport.requests.filter { $0.method == "POST" }.count, 0)
        XCTAssertEqual(offline?.succeeded, 0)

        // 退避在时间上往后推（`IR-21`）：不动时钟 ⇒ 还没到点、不重试。
        let tooSoon = try await service.flush(source: source)
        XCTAssertEqual(tooSoon.attempted, 0, "退避未到点 ⇒ 不重试")

        // 时间推进（退避到期）后联网：自动补传**恰 1 条**，队列清空，服务端计 +1、不重复。
        clock.advance(5)
        transport.online = true
        let flushed = try await service.flush(source: source)
        XCTAssertEqual(flushed.attempted, 1)
        XCTAssertEqual(flushed.succeeded, 1)
        XCTAssertEqual(flushed.pending, 0, "补传成功后队列应清空")
        XCTAssertEqual(transport.requests.filter { $0.method == "POST" }.count, 1, "补传恰 1 次")
        XCTAssertEqual(transport.rows.count, 1)

        // 再调一次：没有欠账 ⇒ 一条都不发（不重复上行）。
        let again = try await service.flush(source: source)
        XCTAssertEqual(again.attempted, 0)
        XCTAssertEqual(transport.requests.filter { $0.method == "POST" }.count, 1)
    }

    /// 失败退避：断网时重试计数 +1 且仍留在队列（进入退避，联网后仍能补上）。
    func testFailedFlushBacksOffAndKeepsEntry() async throws {
        let transport = FakePostgrest()
        transport.online = false
        let clock = MutableClock(Date(timeIntervalSince1970: 1_790_000_000))
        let service = try makeService(transport, clock: clock)
        let note = row(uid: "note-retry", rev: 0, updatedAt: 1_790_000_000)
        let source = StubSource(rows: [note.uid: note])

        let report = try await service.enqueueAndPush(uid: note.uid, source: source)
        XCTAssertEqual(report?.failed, 1, "断网 ⇒ 本轮失败 1 条")
        XCTAssertEqual(report?.pending, 1, "失败不出队")
        XCTAssertEqual(report?.attempts["note-retry"], 1, "重试计数 +1")

        // 退避窗口内不重试；窗口过后（时间推进）才再试一次 ⇒ 计数 +1。
        let tooSoon = try await service.flush(source: source)
        XCTAssertEqual(tooSoon.attempted, 0, "退避窗口内不重试")
        clock.advance(3)
        let again = try await service.flush(source: source)
        XCTAssertEqual(again.attempted, 1)
        XCTAssertEqual(again.failed, 1)
        XCTAssertEqual(again.attempts["note-retry"], 2, "第二次失败 ⇒ 计数 2")
    }

    // MARK: - 判据 ⑥ 冲突留两版（`IR-16` 第三态）：第二版落在冲突副本里

    func testConflictKeepsBothVersionsAndRecordsLosingCopy() throws {
        let transport = FakePostgrest()
        // 服务端已有一条 rev 2、较早时刻的版本。
        transport.rows["note-conf"] = row(uid: "note-conf", rev: 2, updatedAt: 500, content: "{\"v\":\"server\"}")
        let service = try makeService(transport)

        // 本机也改了同一条：rev 相同（2）但内容不同、时刻更晚 ⇒ 冲突，本地这一版胜出。
        let local = row(uid: "note-conf", rev: 2, updatedAt: 600, content: "{\"v\":\"local\"}")
        let merge = try service.push(row: local, rev: 2)

        XCTAssertEqual(merge.verdict, .conflict, "同 rev 不同内容 ⇒ 留两版")
        // 第二版（判负的服务端那一版）**落在冲突副本里**，不静默丢。
        XCTAssertEqual(service.conflicts.count, 1)
        let losing = try XCTUnwrap(service.conflicts.first)
        XCTAssertEqual(losing.uid, "note-conf")
        XCTAssertEqual(losing.losing.payload, "{\"v\":\"server\"}")
        XCTAssertEqual(losing.winnerRev, 2)
        // 胜者照常上行（服务端存的是本地那一版）。
        XCTAssertEqual(transport.rows["note-conf"]?.content, "{\"v\":\"local\"}")
    }

    /// 冲突副本**落盘**（不是只在内存里）：换一个服务实例重新读盘，第二版仍在 —— 这一条给的是
    /// 「判据 ⑥ 的第二版落在哪里」的可复现读数（文件路径 + 文件正文都打印出来）。
    func testConflictCopyLandsInPersistedStateFile() throws {
        let transport = FakePostgrest()
        transport.rows["note-conf2"] = row(uid: "note-conf2", rev: 2, updatedAt: 500, content: "{\"v\":\"server\"}")
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cloud-d-\(UUID().uuidString)", isDirectory: true)
        let store = FileCloudSyncStateStore(fileURL: dir.appendingPathComponent("cloud-sync-state.json"))
        let service = try makeService(transport, store: store)

        let local = row(uid: "note-conf2", rev: 2, updatedAt: 600, content: "{\"v\":\"local\"}")
        XCTAssertEqual(try service.push(row: local, rev: 2).verdict, .conflict)

        // 新实例 + 同一个盘上状态 ⇒ 冲突副本仍在（落盘）。
        let reloaded = try CloudSyncService(
            endpoints: CloudSyncEndpoints(environmentID: "doyah-notes-test-env"),
            transport: transport,
            stateStore: store,
            tokenProvider: { "test-access-token" }
        )
        XCTAssertEqual(reloaded.conflicts.count, 1)
        XCTAssertEqual(reloaded.conflicts.first?.losing.payload, "{\"v\":\"server\"}")

        let text = try String(contentsOf: store.fileURL, encoding: .utf8)
        XCTAssertTrue(text.contains("note-conf2"))
        XCTAssertTrue(text.contains("server"), "第二版原文应在状态文件里留下")
        print("CONFLICT_STATE_FILE=\(store.fileURL.path)")
        print("CONFLICT_STATE_BODY=\(text)")
    }

    // MARK: - 判据 ④-b 真跑（默认跳过；`DOYAH_SYNC_E2E_LIVE=1` 才跑）

    /// 对**真** CloudBase 环境跑一遍最小闭环：登录 → 单篇上行 → 增量下拉 → 断网重试读数。
    ///
    /// 口令从**仓外**读取（`~/.dsh/private/cloud-sync-test-account.json`），不落仓、不打印。
    func testLiveCloudRoundTrip() async throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(
            environment["DOYAH_SYNC_E2E_LIVE"] == "1",
            "真跑用例：默认跳过。设 DOYAH_SYNC_E2E_LIVE=1 才跑（走真云端账号）"
        )
        let home = FileManager.default.homeDirectoryForCurrentUser
        let accountURL = home.appendingPathComponent(".dsh/private/cloud-sync-test-account.json")
        let accountData = try Data(contentsOf: accountURL)
        let account = try XCTUnwrap(try JSONSerialization.jsonObject(with: accountData) as? [String: Any])
        let username = try XCTUnwrap(account["username"] as? String)
        let password = try XCTUnwrap(account["password"] as? String)
        let envID = try XCTUnwrap(account["envId"] as? String)

        // 登录（账号面）。
        let auth = CloudAuthClient(
            endpoints: CloudAuthEndpoints(environmentID: envID),
            transport: URLSessionCloudAuthTransport(),
            store: MemoryTokenStore()
        )
        let session = try auth.signIn(username: username, password: password)
        print("LIVE login ok uid=\(session.subject)")

        let store = MemoryCloudSyncStateStore()
        let service = try CloudSyncService(
            endpoints: CloudSyncEndpoints(environmentID: envID),
            transport: URLSessionCloudAuthTransport(),
            stateStore: store,
            tokenProvider: { session.accessToken }
        )

        // 往上抬游标到「现在」之前一点，保证这一条能被增量拉回；删本地状态（换空态）复拉。
        let uid = UUID().uuidString
        let stamp = Date()
        let note = CloudNoteRow(
            uid: uid,
            title: "云D 端到端最小闭环",
            content: "{\"spans\":[{\"text\":\"云D\"}],\"version\":2}",
            contentType: "application/json",
            notebookUid: nil,
            tags: ["云D", "端到端"],
            pinned: false,
            rev: 0,
            updatedAt: stamp,
            deletedAt: nil,
            deviceId: "mac-d-live"
        )

        let merge = try service.push(row: note, rev: 1)
        print("LIVE upload verdict=\(merge.verdict.rawValue) uid=\(uid) rev=\(service.revision(for: uid))")
        XCTAssertEqual(merge.verdict, .accepted)

        // 增量下拉：同一环境再开一个「空本地」服务，按游标把这一条拉回来。
        let fresh = try CloudSyncService(
            endpoints: CloudSyncEndpoints(environmentID: envID),
            transport: URLSessionCloudAuthTransport(),
            stateStore: MemoryCloudSyncStateStore(),
            tokenProvider: { session.accessToken }
        )
        // 游标置到上传之前，覆盖到刚上行的那一条。
        _ = try fresh.enqueue(uid: uid)
        let pulled = try fresh.pull()
        print("LIVE pull fetched=\(pulled.fetched) unseen=\(pulled.unseen) verdict=\(pulled.verdicts[uid].map(\.rawValue) ?? "nil")")

        // 断网重试：先用断网传输写入（入队 1），再用真传输补传。
        let offlineStore = MemoryCloudSyncStateStore()
        let offlineTransport = OfflineTransport()
        let offlineService = try CloudSyncService(
            endpoints: CloudSyncEndpoints(environmentID: envID),
            transport: offlineTransport,
            stateStore: offlineStore,
            tokenProvider: { session.accessToken }
        )
        let uid2 = UUID().uuidString
        let note2 = CloudNoteRow(
            uid: uid2, title: "云D 断网重试", content: "{}", contentType: "application/json",
            notebookUid: nil, tags: [], pinned: false, rev: 0, updatedAt: Date(),
            deletedAt: nil, deviceId: "mac-d-live"
        )
        let source = StubSource(rows: [uid2: note2])
        let queued = try await offlineService.enqueueAndPush(uid: uid2, source: source)
        print("LIVE offline queued pending=\(offlineService.pendingCount) succeeded=\(queued?.succeeded ?? -1)")

        // 换成真传输补传（同一条队列搬过去）。退避窗口是 `baseDelay=2s` ⇒ 等它到期，
        // 这正是「联网后自动补传」在真实时钟下的样子（不做假等待，如实等）。
        try await Task.sleep(nanoseconds: 2_500_000_000)
        let retryStore = offlineStore
        let retryService = try CloudSyncService(
            endpoints: CloudSyncEndpoints(environmentID: envID),
            transport: URLSessionCloudAuthTransport(),
            stateStore: retryStore,
            tokenProvider: { session.accessToken }
        )
        let flushed = try await retryService.flush(source: source)
        print("LIVE flush attempted=\(flushed.attempted) succeeded=\(flushed.succeeded) pending=\(flushed.pending)")
        XCTAssertEqual(flushed.attempted, 1)
        XCTAssertEqual(flushed.succeeded, 1)
        XCTAssertEqual(flushed.pending, 0)
    }

    // MARK: - 判据 ⑤ 时间口径（前门裁 ⑲ ② · SRS v3.93 `2bfe63b` §6.4.1.1）

    /// **写入 = ISO8601 毫秒 3 位 + 时区偏移；读取 / 比对先归一到 UTC 毫秒**。
    ///
    /// 三条断言（都与本机时区无关）：① 写入的字面形状（`…T22:40:00.000+08:00` / `…Z`）；
    /// ② 往返（写 → 读）恢复出**同一个瞬时**；③ 服务端那种 **6 位小数**形态读进来后
    /// **归一到毫秒** —— 与「同一个毫秒」的三位形态**相等**，且写回来仍是 3 位
    /// （时间字段**不做字符串比较**，比的是归一后的瞬时）。
    func testTimestampWriteReadFollowsCanonicalMillisecondRule() throws {
        let instant = Date(timeIntervalSince1970: 1_790_000_000.123)

        // ① 写入形状：ISO8601 · 毫秒 3 位 · 带时区
        let written = CloudSyncCoding.iso8601String(instant)
        XCTAssertTrue(
            written.range(
                of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}(Z|[+-]\d{2}:\d{2})$"#,
                options: .regularExpression
            ) != nil,
            "写入必须是「ISO8601 · 毫秒 3 位 · 带时区」：\(written)"
        )

        // ② 往返：写 → 读 ⇒ 同一个瞬时（毫秒精度）
        let back = try XCTUnwrap(CloudSyncCoding.parseDate(written))
        XCTAssertEqual(back.timeIntervalSince1970, instant.timeIntervalSince1970, accuracy: 0.000_5)

        // ③ 服务端 6 位小数 ⇒ 归一到毫秒（与三位形态同一瞬时），写回来仍是 3 位
        let sixDigits = try XCTUnwrap(CloudSyncCoding.parseDate("2026-10-09T22:02:32.008207+08:00"))
        let threeDigits = try XCTUnwrap(CloudSyncCoding.parseDate("2026-10-09T22:02:32.008+08:00"))
        XCTAssertEqual(sixDigits, threeDigits, "6 位与 3 位小数必须归一到同一个瞬时（毫秒）")
        let rewritten = CloudSyncCoding.iso8601String(sixDigits)
        XCTAssertTrue(
            rewritten.range(of: #"\.\d{3}(Z|[+-]\d{2}:\d{2})$"#, options: .regularExpression) != nil,
            "服务端 6 位写回来必须归到 3 位：\(rewritten)"
        )
        XCTAssertEqual(CloudSyncCoding.parseDate(rewritten), sixDigits, "写 → 读仍必须同一个瞬时")
    }

    /// 一次性令牌存储（真跑用例里会话只在内存，不碰钥匙串）。
    private final class MemoryTokenStore: NoteSyncTokenStore, @unchecked Sendable {
        private let lock = NSLock()
        private var stored: NoteSyncSession?
        func setSession(_ session: NoteSyncSession) throws { lock.lock(); stored = session; lock.unlock() }
        func session() throws -> NoteSyncSession? { lock.lock(); defer { lock.unlock() }; return stored }
        func deleteSession() throws { lock.lock(); stored = nil; lock.unlock() }
    }

    /// 永远断网的传输（真跑用例里造「断网写入」）。
    private final class OfflineTransport: CloudAuthTransport, @unchecked Sendable {
        func send(_ request: CloudAuthHTTPRequest) throws -> CloudAuthHTTPResponse {
            throw CloudSyncError.transport("offline (live probe)")
        }
    }

    // MARK: - 判据 ⑥ 发往云端的载荷 · canonical 同形（急件 · 派单 `T-20261009-158` 第 ④ 件）

    /// **上行 `content` = 契约 §2.4 交换形态**（不是本侧内部模型形态）：`version` → `spans`；
    /// 每个 span `type` → `content` → `styles`（**对象**）；`backgroundColor` / `code` 收在 `styles` 内、
    /// 有值才写。真机实测的偏差（`text` / 数组式 `styles` / 缺 `type` / `application/json`）在这一条下判红。
    func testExchangePayloadIsContractShapedAndInternalShapeIsRejected() throws {
        let body = NoteBody(spans: [
            NoteSpan(text: "普通文字"),
            NoteSpan(text: "粗体", styles: [.bold]),
            NoteSpan(text: "链接", link: "https://example.com/a"),
            NoteSpan(text: "荧光", backgroundColor: NoteHighlight.backgroundColorHex),
            NoteSpan(text: "带勾任务", block: .task(checked: true))
        ])
        let exchange = NoteBodyExchange.json(body)
        XCTAssertEqual(
            exchange,
            ##"{"version":2,"spans":[{"type":"TEXT","content":"普通文字","styles":{"bold":false,"italic":false,"underline":false,"fontSize":16,"color":"#000000"}},{"type":"TEXT","content":"粗体","styles":{"bold":true,"italic":false,"underline":false,"fontSize":16,"color":"#000000"}},{"type":"TEXT","content":"链接","styles":{"bold":false,"italic":false,"underline":false,"fontSize":16,"color":"#000000"},"link":"https://example.com/a"},{"type":"TEXT","content":"荧光","styles":{"bold":false,"italic":false,"underline":false,"fontSize":16,"color":"#000000","backgroundColor":"#FFF3B0"}},{"type":"LIST_CHECKBOX","content":"带勾任务","styles":{"bold":false,"italic":false,"underline":false,"fontSize":16,"color":"#000000"},"checked":true}]}"##,
            "交换面 canonical 形状（键序 / 类型 / styles 对象 / 有值才写）"
        )
        XCTAssertFalse(exchange.contains("\\/"), "`/` 不得转义成 `\\/`")

        // 正例：交换形态 + `text/plain` ⇒ 0 违规
        XCTAssertEqual(
            CloudPayloadCanonical.violations(content: exchange, contentType: "text/plain"), [],
            "交换形态 + text/plain 必须 0 违规"
        )

        // 负例：本侧**内部**形态（= 真机实测那一版）+ `application/json` ⇒ 判红
        let internalShape = try NoteBodyCanonical.json(body)
        let negative = CloudPayloadCanonical.violations(content: internalShape, contentType: "application/json")
        XCTAssertGreaterThanOrEqual(negative.count, 2, "内部形态 + application/json 必须判红：\(negative)")
        for expected: CloudPayloadCanonical.Violation in [.contentTypeMismatch, .contentUsesInternalTextKey, .contentStylesIsArray, .spanTypeContentUnpaired] {
            XCTAssertTrue(negative.contains(expected), "负例必须命中 `\(expected)`：\(negative)")
        }
    }

    /// **上行体键序**（判据① 行级 = 契约列序）+ `deleted_at` 显式 `null`（判据② 唯一例外）。
    func testUploadBodyFollowsCanonicalRowKeyOrder() throws {
        let row = CloudNoteRow(
            uid: "8C4E2B10-5A7D-4F31-9E62-B0D3C7A95F48",
            title: "周会纪要",
            content: NoteBodyExchange.json(NoteBody(spans: [NoteSpan(text: "周三")])),
            contentType: CloudPayloadCanonical.expectedContentType,
            notebookUid: "656AF1CB-367B-4A0E-94AF-97C5812DF176",
            tags: ["工作"],
            pinned: false,
            rev: 8,
            updatedAt: Date(timeIntervalSince1970: 1_790_000_000),
            deletedAt: nil,
            deviceId: "macos-test"
        )
        let json = CloudSyncCoding.uploadJSON(row)
        XCTAssertFalse(json.contains("\"owner_id\""), "上行体不许自带 owner_id")
        let pairs = [
            ("\"uid\"", "\"title\""), ("\"title\"", "\"content\""), ("\"content\"", "\"content_type\""),
            ("\"content_type\"", "\"notebook_uid\""), ("\"notebook_uid\"", "\"tags\""),
            ("\"tags\"", "\"pinned\""), ("\"pinned\"", "\"rev\""), ("\"rev\"", "\"updated_at\""),
            ("\"updated_at\"", "\"deleted_at\""), ("\"deleted_at\"", "\"device_id\"")
        ]
        for (earlier, later) in pairs {
            let a = try XCTUnwrap(json.range(of: earlier)?.lowerBound)
            let b = try XCTUnwrap(json.range(of: later)?.lowerBound)
            XCTAssertLessThan(a, b, "键序应为契约列序：\(earlier) 必须在 \(later) 前\n\(json)")
        }
        XCTAssertTrue(json.contains("\"deleted_at\":null"), "未删除时 `deleted_at` 必须显式 null：\(json)")
        XCTAssertFalse(json.contains("\\/"), "`/` 不得转义")
        // 往返：形状没变（只是键序 / 缺省换了）⇒ 上行体的解码面照旧认得
        let back = try CloudSyncCoding.decoder().decode(CloudNoteRow.Upload.self, from: Data(json.utf8))
        XCTAssertEqual(back.uid, row.uid)
        XCTAssertEqual(back.rev, 8)
        XCTAssertEqual(back.contentType, CloudPayloadCanonical.expectedContentType)
        XCTAssertNil(back.deletedAt)
    }
}
