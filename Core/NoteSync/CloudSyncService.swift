import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// 云D · **端到端最小闭环的网络接线**（契约 `DoyahNotes Docs/需求规范书.md` §6.4 / §6.4.1 / §6.4.2）：
//
//   · `IR-15` 增量拉取（`updated_after=<cursor>` 分页拉）
//   · `IR-16` 单篇上行（幂等键 = `uid` + `rev`；回执三态：已接收 / 已过期 / 冲突留两版）
//   · `IR-21` 断网重试（本地队列 + 指数退避；联网后自动补传）
//
// 本文件是**共享逻辑层同步模块**里唯一发数据面 HTTP 的地方 —— 与 `CloudAuth.swift`（`云C`）同一条
// 接口面纪律（§6.4「接口面纪律」）：网络调用**只允许**出现在 `Core/NoteSync/`，界面侧不直接连网。
//
// 契约面事实（**实测**，非猜测 —— 端点形状按 CloudBase 官方 HTTP API 规范，卡上留痕）：
//   · 数据面基址 = `https://<envId>.api.tcloudbasegateway.com`，PostgREST 形态挂
//     `/v1/rdb/rest/<表>`（官方 `postgresql-development-cloudbase/references/http-api.md`）；
//   · 认证头 = `Authorization: Bearer <access_token>`（会话来自 `CloudAuthClient`，`云C`）；
//   · `notes.owner_id` 由**服务端列默认值**填 —— `DEFAULT auth.uid()`（RLS `owner_all`
//     `owner_id = auth.uid()`，角色 `authenticated`）⇒ **上行体里不写 `owner_id`**，
//     由数据库按当前令牌的 `sub` 补，客户端不参与归属判定（§6.4「身份与归属」条）。
//
// 三条装配口径（`云E`《格式自证》§五 点的就是这三处缺口；本片落装配点）：
//   ① **本地身份 ↔ 云端 `uid`**：`Note.id: UUID`（列 `note.uuid`，**不是** `uid`）→ 云端 `notes.uid`
//      = `uuidString` 原样（大小写与连字符都照原样，不在两端各做一次归一化）；
//   ② **`content`** = 本地正文权威源那一段富文本 JSON（`NoteBody` 编码面，落 `note.spans` 列的那一份）；
//   ③ **可选值 `nil`**：`Swift` 合成 `Codable` 的 `nil` = **键缺失**（不是 `null`）—— 与 `云E`
//      §二 读数一致；`deleted_at` 只在墓碑时出现。
//
// 本文件**不解释正文**（与 `SyncCore` 同一条）：它只把一行按列搬来搬去；「`content` 里那棵树长什么样」
// 属于 `NoteBody`。

// MARK: - 端点口径

/// 数据面端点（CloudBase PG · PostgREST 形态）。
///
/// 真值来自 CloudBase 官方 HTTP API 规范（`http-api-cloudbase` + `postgresql-development-cloudbase`），
/// **不是**本片自造的路径 —— 卡面点名「按官方 HTTP API 规范为准，两端同源」。
public struct CloudSyncEndpoints: Sendable {

    public let baseURL: URL

    public init(baseURL: URL) {
        self.baseURL = baseURL
    }

    /// 按环境 ID 组基址（`doyah-notes-db00-d6el2lr50a6ef27` ⇒ 网关基址）。
    public init(environmentID: String) {
        self.baseURL = URL(string: "https://\(environmentID).api.tcloudbasegateway.com")!
    }

    /// 数据面表入口：`/v1/rdb/rest/notes`。
    public func tableURL(_ table: String) -> URL {
        URL(string: "/v1/rdb/rest/\(table)", relativeTo: baseURL)!.absoluteURL
    }

    /// `notes` 表入口（本片只用这一张）。
    public func notesURL() -> URL { tableURL("notes") }

    /// 把查询串挂上去（`select` / `updated_at` / `order` / `limit` / `uid` …）。
    /// 交给 `URLComponents` 编码：`eq.` / `gte.` 里的 `.` 与值里的中文都不会被破坏。
    public func notesURL(query: [(String, String)]) -> URL {
        var components = URLComponents(url: notesURL(), resolvingAgainstBaseURL: false)!
        components.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        return components.url!
    }
}

// MARK: - 错误面

/// 同步数据面的错误。**不带用户可见文案、不带令牌本体**（界面按分支给本地化文案）。
public enum CloudSyncError: Error, Equatable, Sendable {
    /// 本机没有会话（没登录 / 会话被清）。
    case notAuthenticated
    /// 出网层失败（连不上 / 超时 / 非 HTTP 应答）—— payload 只放技术描述。
    /// **这一档 = 「断网」在同步模块里的形态**：调用方据此入队而非丢弃。
    case transport(String)
    /// 服务端返回了非 2xx。
    case server(code: String, status: Int)
    /// 2xx 但响应体解不出来。
    case malformedResponse
}

/// 判定「这次失败算不算断网」——只此一处（队列的入队条件读它，不各写一份）。
public extension CloudSyncError {
    var isOfflineLike: Bool {
        if case .transport = self { return true }
        return false
    }
}

// MARK: - 云端 `notes` 行（§6.4.1 的列，逐字按契约命名）

/// 云端 `notes` 表的一行 —— **字段名照契约 §6.4.1**（`uid` `owner_id` `title` `content`
/// `content_type` `notebook_uid` `tags` `pinned` `rev` `updated_at` `deleted_at` `device_id`）。
///
/// 这是本片新落的**装配点**（`云E` §五 #9 登记的缺口）：上行的整行在这里成形，下行的整行在这里成型。
/// `owner_id` 只读不写 —— 上行体里没有它（由服务端 `DEFAULT auth.uid()` 填），下行解出来供核对。
public struct CloudNoteRow: Codable, Equatable, Sendable {
    public var uid: String
    public var ownerId: String?
    public var title: String?
    /// 富文本 JSON（`NoteBody` 编码面；本片只当**不透明快照**搬运）。
    public var content: String?
    public var contentType: String?
    public var notebookUid: String?
    public var tags: [String]?
    public var pinned: Bool?
    public var rev: Int
    public var updatedAt: Date
    public var deletedAt: Date?
    public var deviceId: String?

    public init(
        uid: String,
        ownerId: String? = nil,
        title: String? = nil,
        content: String? = nil,
        contentType: String? = nil,
        notebookUid: String? = nil,
        tags: [String]? = nil,
        pinned: Bool? = nil,
        rev: Int,
        updatedAt: Date,
        deletedAt: Date? = nil,
        deviceId: String? = nil
    ) {
        self.uid = uid
        self.ownerId = ownerId
        self.title = title
        self.content = content
        self.contentType = contentType
        self.notebookUid = notebookUid
        self.tags = tags
        self.pinned = pinned
        self.rev = rev
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.deviceId = deviceId
    }

    /// 上行体：**没有 `owner_id`**（服务端默认 `auth.uid()` 填）。
    ///
    /// 为什么另开一个类型而不是给 `ownerId` 加 `encodeIfPresent`：上行体是「服务端该自己决定的事
    /// 一律不写」的产物，写成独立类型它就无法被某个调用点悄悄塞进一个 `owner_id`。
    public struct Upload: Codable, Equatable, Sendable {
        public var uid: String
        public var title: String?
        public var content: String?
        public var contentType: String?
        public var notebookUid: String?
        public var tags: [String]?
        public var pinned: Bool?
        public var rev: Int
        public var updatedAt: Date
        public var deletedAt: Date?
        public var deviceId: String?

        enum CodingKeys: String, CodingKey {
            case uid, title, content, tags, pinned, rev
            case contentType = "content_type"
            case notebookUid = "notebook_uid"
            case updatedAt = "updated_at"
            case deletedAt = "deleted_at"
            case deviceId = "device_id"
        }

        public init(row: CloudNoteRow) {
            uid = row.uid
            title = row.title
            content = row.content
            contentType = row.contentType
            notebookUid = row.notebookUid
            tags = row.tags
            pinned = row.pinned
            rev = row.rev
            updatedAt = row.updatedAt
            deletedAt = row.deletedAt
            deviceId = row.deviceId
        }
    }

    /// 上行的 `Codable` 形状（`Upload`）。
    public var upload: Upload { Upload(row: self) }

    /// 同步面记录（决胜规则只认 `uid` / `rev` / `updatedAt` / `deletedAt` / `payload`）。
    public var record: SyncRecord {
        SyncRecord(
            uid: uid,
            rev: rev,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            deviceId: deviceId,
            payload: content ?? ""
        )
    }

    /// 由同步面记录 + 装配出来的元数据拼一行（**装配点**：一个地方成形）。
    public static func make(
        record: SyncRecord,
        title: String?,
        contentType: String?,
        notebookUid: String?,
        tags: [String]?,
        pinned: Bool?
    ) -> CloudNoteRow {
        CloudNoteRow(
            uid: record.uid,
            ownerId: nil,
            title: title,
            content: record.payload,
            contentType: contentType,
            notebookUid: notebookUid,
            tags: tags,
            pinned: pinned,
            rev: record.rev,
            updatedAt: record.updatedAt,
            deletedAt: record.deletedAt,
            deviceId: record.deviceId
        )
    }

    // 合成 `Codable` 的手写一份（`CodingKeys` 显式写出来：见 `Note` 的同一条注释）。
    enum CodingKeys: String, CodingKey {
        case uid, title, content, tags, pinned, rev
        case ownerId = "owner_id"
        case contentType = "content_type"
        case notebookUid = "notebook_uid"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case deviceId = "device_id"
    }
}

// MARK: - 冲突副本（`IR-16` 三态里的「冲突留两版」· 第二版落在哪里）

/// 被 LWW 判负的那一版 —— **落在本地这份副本里，不静默丢**。
///
/// 契约 §6.4「冲突合并」条：记录级 LWW 决胜 + **冲突留两版兜底**（人类主人 2026-10-09 拍板）。
/// 于是「两版都在」这件事需要一个**落点**：主版本（胜者）进本地库 / 上行到云端；
/// 负者（这一版）落进 `conflicts` 数组，随同步状态一起持久化（默认 `cloud-sync-state.json`）。
/// 判据要能指着它说「第二版在这儿」，所以它是具名类型、有 `uid` 有原文，而不是日志里一行字。
public struct CloudConflictCopy: Codable, Equatable, Sendable {
    /// 冲突的那条 `uid`。
    public var uid: String
    /// 判负的那一版（原文整条 `SyncRecord`：`rev` / `updatedAt` / `payload` 全在）。
    public var losing: SyncRecord
    /// 胜者（主版本）的 `rev`，便于读数时一眼看出胜负依据。
    public var winnerRev: Int
    /// 记下这一刻。
    public var at: Date

    public init(uid: String, losing: SyncRecord, winnerRev: Int, at: Date = Date()) {
        self.uid = uid
        self.losing = losing
        self.winnerRev = winnerRev
        self.at = at
    }
}

// MARK: - 同步状态（游标 + 版本账 + 队列 + 冲突副本）

/// 同步的**本地持久状态**：增量游标（`IR-15`）+ 每条 `uid` 的版本账（`IR-16` 的 `rev` 出处）+
/// 离线队列（`IR-21`）+ 冲突副本（`IR-16` 留两版）。
///
/// 为什么这几样收在一个值类型里：它们**必须一起前进** —— 上行成功却忘了推进 `rev`、或推进了游标
/// 却没落冲突副本，都会在下一次同步里变成「重复上行 / 静默丢一版」。收成一份可整体序列化 /
/// 反序列化的状态，就不会出现「只写了一半」。
public struct CloudSyncState: Codable, Equatable, Sendable {
    /// 增量游标（`SyncCursor`：时刻 + 同刻 boundaryUIDs）。
    public var cursor: SyncCursor
    /// 每条 `uid` 已上行到的 `rev`（本机视角的版本账）。
    public var revByUID: [String: Int]
    /// 出端标识（契约 §6.4.1 `device_id`）。
    public var deviceId: String
    /// 离线待办队列（入队序）。
    public var queue: [SyncQueueEntry]
    /// 被判负而留下的第二版（冲突副本）。
    public var conflicts: [CloudConflictCopy]

    public init(
        cursor: SyncCursor = SyncCursor(),
        revByUID: [String: Int] = [:],
        deviceId: String = CloudSyncState.defaultDeviceId(),
        queue: [SyncQueueEntry] = [],
        conflicts: [CloudConflictCopy] = []
    ) {
        self.cursor = cursor
        self.revByUID = revByUID
        self.deviceId = deviceId
        self.queue = queue
        self.conflicts = conflicts
    }

    /// 出端标识：优先环境变量 `DOYAH_DEVICE_ID`，否则主机名；**都不含用户名 / 口令**。
    public static func defaultDeviceId(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        if let override = environment["DOYAH_DEVICE_ID"], !override.isEmpty { return override }
        return ProcessInfo.processInfo.hostName
    }
}

/// 同步状态的持久化抽象层（默认落 JSON 文件；测试注入内存实现）。
public protocol CloudSyncStateStore: Sendable {
    func load() throws -> CloudSyncState
    func save(_ state: CloudSyncState) throws
}

/// 默认实现：JSON 文件（**原子写**，与工程其它存储同一条纪律 —— 写一半崩了不留下半截状态）。
///
/// **不含任何凭据**：这里只有 `uid` / `rev` / 游标 / 队列 / 冲突副本。会话令牌走钥匙串
/// （`NoteSyncTokenStore`，`云C`），不落这个文件。
public struct FileCloudSyncStateStore: CloudSyncStateStore {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// 默认落点：笔记数据家下的 `cloud-sync-state.json`（与 `notes.json` 同目录，不进工程数据家）。
    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.fileURL = NoteStore.defaultDirectory(environment: environment)
            .appendingPathComponent("cloud-sync-state.json", isDirectory: false)
    }

    public func load() throws -> CloudSyncState {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return CloudSyncState() }
        let data = try Data(contentsOf: fileURL)
        let decoder = CloudSyncCoding.decoder()
        return try decoder.decode(CloudSyncState.self, from: data)
    }

    public func save(_ state: CloudSyncState) throws {
        let encoder = CloudSyncCoding.encoder()
        let data = try encoder.encode(state)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }
}

/// 内存实现（单测 / 探针用；不落盘）。
public final class MemoryCloudSyncStateStore: CloudSyncStateStore, @unchecked Sendable {
    private var state: CloudSyncState
    public init(_ state: CloudSyncState = CloudSyncState()) { self.state = state }
    public func load() throws -> CloudSyncState { state }
    public func save(_ state: CloudSyncState) throws { self.state = state }
}

// MARK: - 现取本地行（`云B` 口径：队列只记 uid，重放时现取）

/// 把「某个 `uid` 当前在本地是什么样」交给同步模块的服务协议。
///
/// 为什么不是把正文塞进队列（`SyncQueue` 的类型注释已写死这条）：离线优先下**本地库是唯一事实源**，
/// 队列只是欠账索引；重放时现取，编辑后的正文才不会被队列里的旧副本盖回去。
public protocol CloudNoteSource: Sendable {
    /// 现取某 `uid` 的当前本地行（已装配成云端整行；`owner_id` 留空由服务端填）。取不到返回 `nil`。
    func cloudRow(uid: String) async throws -> CloudNoteRow?
}

// MARK: - 同步服务

/// 端到端最小闭环的**网络接线**：上行 `IR-16` · 增量下拉 `IR-15` · 断网重试 `IR-21`。
///
/// 组成（全部注入，便于机械复核）：端点口径 · 出网传输 · 状态存储 · 令牌提供者 · 时钟。
/// 复用 `云C` 的 `CloudAuthTransport`（同一个「发一个 HTTP 请求收一个应答」的最小形状）——
/// 数据面与账号面走**同一套出网抽象**，测试里一个假传输就能同时覆盖两条面。
public final class CloudSyncService: @unchecked Sendable {

    public let endpoints: CloudSyncEndpoints

    private let transport: CloudAuthTransport
    private let stateStore: CloudSyncStateStore
    private let tokenProvider: @Sendable () throws -> String
    private let now: @Sendable () -> Date

    /// 本地账（决胜结果与两版兜底都落在这里；`云B` 的 `SyncLedger`）。
    public private(set) var ledger: SyncLedger

    private var state: CloudSyncState

    /// 单页拉取上限（`IR-15` 分页）。
    public var pageLimit: Int = 200

    public init(
        endpoints: CloudSyncEndpoints,
        transport: CloudAuthTransport,
        stateStore: CloudSyncStateStore,
        tokenProvider: @escaping @Sendable () throws -> String,
        now: @escaping @Sendable () -> Date = { Date() }
    ) throws {
        self.endpoints = endpoints
        self.transport = transport
        self.stateStore = stateStore
        self.tokenProvider = tokenProvider
        self.now = now
        self.state = try stateStore.load()
        self.ledger = SyncLedger()
    }

    /// 便捷构造：把「真出网 + 文件状态」装好（App 侧用）。
    public static func live(
        environmentID: String,
        tokenProvider: @escaping @Sendable () throws -> String,
        stateStore: CloudSyncStateStore? = nil
    ) throws -> CloudSyncService {
        try CloudSyncService(
            endpoints: CloudSyncEndpoints(environmentID: environmentID),
            transport: URLSessionCloudAuthTransport(),
            stateStore: stateStore ?? FileCloudSyncStateStore(),
            tokenProvider: tokenProvider
        )
    }

    // MARK: 状态读

    public var deviceId: String { state.deviceId }
    public var cursor: SyncCursor { state.cursor }
    public var pendingCount: Int { state.queue.count }
    public var conflicts: [CloudConflictCopy] { state.conflicts }

    /// 某 `uid` 已上行到的 `rev`（没有 = 0）。
    public func revision(for uid: String) -> Int { state.revByUID[uid] ?? 0 }

    /// 下一次上行这一 `uid` 该用的 `rev`（单调 +1）。
    public func nextRevision(for uid: String) -> Int { revision(for: uid) + 1 }

    // MARK: `IR-21` 入队

    /// 记「这一 `uid` 欠云端一次操作」。同 `uid` 只一条（`SyncQueue` 的幂等落在队列上）。
    @discardableResult
    public func enqueue(uid: String, operation: SyncOperation = .upsert) throws -> Bool {
        var queue = SyncQueue(entries: state.queue, now: now)
        let added = queue.enqueue(uid: uid, operation: operation)
        state.queue = queue.entries
        try stateStore.save(state)
        return added
    }

    /// 队列里到点可以重放的条目（`IR-21` 的退避由 `SyncQueue` 决定）。
    public func readyEntries() -> [SyncQueueEntry] {
        SyncQueue(entries: state.queue, now: now).ready(at: now())
    }

    // MARK: `IR-16` 单篇上行

    /// 上行一条笔记（`IR-16`）。返回三态决胜结果（`SyncMerge`）。
    ///
    /// 为什么先读再写（而不是盲目覆盖）：契约要求「服务端按 LWW 决胜，回执三态」，而本环境**不许改
    /// 云端配置**（停手线 ③：不许自建触发器 / 函数）⇒ LWW 用 `云B` 的记录级决胜规则在**客户端**判，
    /// 判完再把胜者写上去。决胜规则与 `SyncLedger` **同源**（`SyncResolution.decide`），不另起一套。
    ///
    /// - Parameters:
    ///   - row: 要上行的整行（`owner_id` 已由类型保证不在上行体里）。
    ///   - rev: 这一版的 `rev`（调用方用 `nextRevision(for:)` 取）。
    /// - Returns: 决胜结果（`.accepted` 已接收 / `.expired` 已过期 / `.conflict` 留两版）。
    @discardableResult
    public func push(row: CloudNoteRow, rev: Int) throws -> SyncMerge {
        let token = try requireToken()
        var outgoing = row
        outgoing.rev = rev

        let remote = try fetchRow(uid: row.uid, token: token)
        let merge = SyncResolution.decide(incoming: outgoing.record, local: remote?.record)

        switch merge.verdict {
        case .expired:
            // 服务端那一版更新：本地这一版判负 —— **不丢**，落冲突副本；不上行。
            recordConflict(merge.conflict ?? outgoing.record, winnerRev: merge.primary.rev)
        case .accepted:
            try upload(outgoing, token: token)
        case .conflict:
            // 两版都留：胜者上行，负者落冲突副本。**不许静默丢数据**（契约 §6.4「冲突合并」）。
            try upload(outgoing, token: token)
            if let losing = merge.conflict { recordConflict(losing, winnerRev: merge.primary.rev) }
        }

        state.revByUID[row.uid] = merge.primary.rev
        try stateStore.save(state)
        ledger.apply(merge.primary)
        return merge
    }

    // MARK: `IR-15` 增量下拉

    /// 一页记录（`IR-15`）：`updated_after=<游标>` 取回、滤掉同刻已见过的那些。
    public func fetchPage(token: String) throws -> [CloudNoteRow] {
        var query: [(String, String)] = [("select", "*"), ("order", "updated_at.asc"), ("limit", String(pageLimit))]
        if let after = state.cursor.updatedAfter {
            query.append(("updated_at", "gte.\(CloudSyncCoding.iso8601String(after))"))
        }
        let response = try send(
            CloudAuthHTTPRequest(
                method: "GET",
                url: endpoints.notesURL(query: query),
                headers: ["Authorization": "Bearer \(token)"]
            )
        )
        guard (200...299).contains(response.status) else {
            throw CloudSyncError.server(code: "HTTP_\(response.status)", status: response.status)
        }
        do {
            return try CloudSyncCoding.decoder().decode([CloudNoteRow].self, from: response.body)
        } catch {
            throw CloudSyncError.malformedResponse
        }
    }

    /// 增量下拉一页并应用到本地账（`IR-15`）。
    ///
    /// - Returns: 这一页逐 `uid` 的回执三态 + 真正新见的条数（游标判据与 `SyncCursor.unseen` 同源）。
    @discardableResult
    public func pull() throws -> (verdicts: [String: SyncVerdict], fetched: Int, unseen: Int) {
        let token = try requireToken()
        let page = try fetchPage(token: token)
        let unseen = state.cursor.unseen(in: page.map(\.record))
        let verdicts = ledger.apply(unseen)
        state.cursor.advance(with: page.map(\.record))
        for row in page where (state.revByUID[row.uid] ?? 0) < row.rev {
            state.revByUID[row.uid] = row.rev
        }
        try stateStore.save(state)
        return (verdicts, page.count, unseen.count)
    }

    // MARK: `IR-21` 断网重试（联网后自动补传）

    /// 一次重放的结果读数（判据 3 的证据：**恰好补传几条**）。
    public struct FlushReport: Equatable, Sendable {
        /// 本轮到点、尝试重放的条数。
        public var attempted: Int
        /// 成功上行并出队的条数。
        public var succeeded: Int
        /// 失败（仍留在队列、退了避）的条数。
        public var failed: Int
        /// 本轮结束后队列长度。
        public var pending: Int
        /// 逐条重试计数（`uid` → 已失败次数），供「重试次数」读数。
        public var attempts: [String: Int]
    }

    /// 重放队列里到点的条目（`IR-21`）：**现取**本地行 → 上行 → 成功出队 / 失败退避。
    ///
    /// 断网时（传输抛 `transport`）失败**不出队**、退避往后推；恢复后再调一次即自动补传。
    /// - Returns: 读数（尝试 / 成功 / 失败 / 队列长度 / 逐条重试次数）。
    @discardableResult
    public func flush(source: CloudNoteSource) async throws -> FlushReport {
        let token = try requireToken()
        var queue = SyncQueue(entries: state.queue, now: now)
        let ready = queue.ready(at: now())
        var succeeded = 0
        var failed = 0

        for entry in ready {
            do {
                guard let row = try await source.cloudRow(uid: entry.uid) else {
                    // 本地已经没有这一行（删了）：队列里这一条欠账就地销账，不假装成功。
                    queue.dequeue(uid: entry.uid)
                    continue
                }
                if entry.operation == .delete {
                    // 墓碑上行：`deleted_at` 非空即可（`IR-17`：**不物理删**）。
                    var tombstone = row
                    tombstone.deletedAt = now()
                    // 删除也是一次内容变更：`rev` 照常 +1。
                    _ = try push(row: tombstone, rev: nextRevision(for: entry.uid))
                } else {
                    _ = try push(row: row, rev: nextRevision(for: entry.uid))
                }
                queue.dequeue(uid: entry.uid)
                succeeded += 1
            } catch let error as CloudSyncError where error.isOfflineLike {
                queue.fail(uid: entry.uid)
                failed += 1
            } catch let error as CloudSyncError {
                // 服务端拒绝（非断网）：也按失败退避 —— 但不静默丢，下一次仍会重试。
                _ = error
                queue.fail(uid: entry.uid)
                failed += 1
            } catch {
                queue.fail(uid: entry.uid)
                failed += 1
            }
        }

        state.queue = queue.entries
        try stateStore.save(state)
        var attempts: [String: Int] = [:]
        for entry in queue.entries { attempts[entry.uid] = entry.attempts }
        return FlushReport(
            attempted: ready.count,
            succeeded: succeeded,
            failed: failed,
            pending: queue.pendingCount,
            attempts: attempts
        )
    }

    /// 便捷：把一条笔记「入队 + 立刻尝试上行」。
    ///
    /// 这是 `AppState` 的触发点入口：写库成功后调它 —— 在线则当场补传（队列清空），
    /// 断网则**留在队列**（不报错、不丢），联网后由下一次 `flush` 自动补传（`IR-21`）。
    @discardableResult
    public func enqueueAndPush(uid: String, operation: SyncOperation = .upsert, source: CloudNoteSource) async -> FlushReport? {
        try? enqueue(uid: uid, operation: operation)
        return try? await flush(source: source)
    }

    // MARK: 内部 · 网络

    private func requireToken() throws -> String {
        do {
            let token = try tokenProvider()
            guard !token.isEmpty else { throw CloudSyncError.notAuthenticated }
            return token
        } catch let error as CloudSyncError {
            throw error
        } catch {
            throw CloudSyncError.notAuthenticated
        }
    }

    private func fetchRow(uid: String, token: String) throws -> CloudNoteRow? {
        let url = endpoints.notesURL(query: [
            ("select", "*"),
            ("uid", "eq.\(uid)"),
            ("limit", "1"),
        ])
        let response = try send(
            CloudAuthHTTPRequest(method: "GET", url: url, headers: ["Authorization": "Bearer \(token)"])
        )
        guard (200...299).contains(response.status) else {
            throw CloudSyncError.server(code: "HTTP_\(response.status)", status: response.status)
        }
        do {
            return try CloudSyncCoding.decoder().decode([CloudNoteRow].self, from: response.body).first
        } catch {
            throw CloudSyncError.malformedResponse
        }
    }

    private func upload(_ row: CloudNoteRow, token: String) throws {
        // **上行体 = canonical JSON**（契约 §6.4.1.1 判据①②）：键序按契约列序（不是字典序）、
        // 可选键省略、`deleted_at` 显式 `null` —— 由 `CloudSyncCoding.uploadJSON` 一处成形。
        let body = Data(CloudSyncCoding.uploadJSON(row).utf8)
        let response = try send(
            CloudAuthHTTPRequest(
                method: "POST",
                url: endpoints.notesURL(),
                headers: [
                    "Authorization": "Bearer \(token)",
                    "Prefer": "resolution=merge-duplicates,return=representation",
                ],
                body: body
            )
        )
        guard (200...299).contains(response.status) else {
            throw CloudSyncError.server(code: "HTTP_\(response.status)", status: response.status)
        }
    }

    private func send(_ request: CloudAuthHTTPRequest) throws -> CloudAuthHTTPResponse {
        var headers = request.headers
        headers["Content-Type"] = "application/json"
        headers["Accept"] = "application/json"
        let outgoing = CloudAuthHTTPRequest(
            method: request.method, url: request.url, headers: headers, body: request.body
        )
        do {
            return try transport.send(outgoing)
        } catch let error as CloudSyncError {
            throw error
        } catch {
            throw CloudSyncError.transport(String(describing: error))
        }
    }

    private func recordConflict(_ losing: SyncRecord, winnerRev: Int) {
        let copy = CloudConflictCopy(uid: losing.uid, losing: losing, winnerRev: winnerRev, at: now())
        // 同一版（幂等键 + 快照 + 时刻都同）重复到达时不重复堆叠。
        if state.conflicts.contains(where: { $0.uid == copy.uid && $0.losing == copy.losing }) { return }
        state.conflicts.append(copy)
    }
}

// MARK: - 本地库适配（现取一行的**生产实现**）

/// `CloudNoteSource` 的生产实现：从本机笔记库（`note` 表 + `note.spans` 列）现取一行的云端装配面。
///
/// 三条映射（`云E` §五 点名的缺口，本片落装配）：
///   · `uid` = `note.uuid`（`Note.id.uuidString` 原样）；
///   · `content` = `note.spans` 列的富文本 JSON（没有就退回投影文本 `body`，**不伪造空正文**）；
///   · `notebook_uid` / `tags` / `pinned` 从库里的归属与列取值现读。
///
/// `rev` 不在这里给（本类型给 0 占位）——`rev` 是**同步面的版本账**，只有 `CloudSyncService`
/// 拿得住（`nextRevision(for:)`）；装配面与版本账分开，才不会出现「两个地方各自 +1」。
public struct NoteLibraryCloudSource: CloudNoteSource {

    public let library: NoteLibrary
    public let contentType: String

    public init(
        library: NoteLibrary = NoteLibrary.defaultLibrary(),
        // **`text/plain`**（契约 §6.4.1.1 判据④：`content_type` = 与本地 `contentType` 同值）。
        // 片「载荷同形」（急件 · `T-20261009-158`）：真机实测本侧写的是 `application/json`，
        // 与本地同值口径不符 —— 正文形态由 `content.version` 承载，`content_type` 只报「正文是文本」。
        contentType: String = "text/plain"
    ) {
        self.library = library
        self.contentType = contentType
    }

    /// `note.spans`（内部形态）→ **交换面 canonical**（契约 §2.4 / §6.4.1.1）。
    ///
    /// 本侧 `note.spans` 列存的是**内部模型**（`text` / `styles` 数组 / `backgroundColor` 平铺）；
    /// 上行 `content` 必须是契约的**交换形态**（`type` / `content` / `styles` 对象）——两者刻意不同，
    /// 由 `NoteBodyExchange` 在这一处做**唯一**投影（同一次写入在两端同形）。
    /// `spans` 列缺失（老数据）⇒ 由投影文本现造一份 `NoteBody`，**仍然**走交换面编码（不裸发纯文本）。
    static func exchangeContent(spansJSON: String?, body: String) -> String {
        if let spansJSON, !spansJSON.isEmpty,
           let document = try? JSONDecoder().decode(NoteBody.self, from: Data(spansJSON.utf8)) {
            return NoteBodyExchange.json(document)
        }
        return NoteBodyExchange.json(NoteBody(markdown: body))
    }

    public func cloudRow(uid: String) async throws -> CloudNoteRow? {
        guard let id = UUID(uuidString: uid) else { return nil }
        let notes = try await library.load()
        guard let note = notes.first(where: { $0.id == id }) else { return nil }
        let spans = ((try? await library.noteSpans(id: id)) ?? nil)
        let placement = ((try? await library.placements()) ?? []).first { $0.noteID == uid }
        return CloudNoteRow(
            uid: uid,
            title: note.title,
            content: Self.exchangeContent(spansJSON: spans, body: note.body),
            contentType: contentType,
            notebookUid: placement?.notebookUid,
            tags: note.tags,
            pinned: note.isPinned,
            rev: 0,
            // **归一到 UTC 毫秒**（裁定 ⑲ ②）：本地 `Note.updatedAt` 是全精度 `Date`，而交换面
            // 走的是毫秒 3 位 —— 不归一的话，「同一次写入」在本地与云端会是两个不等的瞬时
            // （同一 `rev` 的幂等重放会被判成冲突）。
            updatedAt: CloudSyncCoding.normalizedToMilliseconds(note.updatedAt),
            deletedAt: nil,
            deviceId: nil
        )
    }
}

// MARK: - 同步开关的落点（契约 §10.4 `S3`：默认关 · 用户显式开启）

/// 云同步开关的**唯一持久键**（`S3`：默认关，由用户显式开启；服务端不得代开）。
///
/// 为什么放在 Core：开关的两端分处两个文件 —— 账号界面（`AccountFlowModel`）写它、
/// 笔记写库的触发点（`AppState`）读它。键与默认值收在一处，两端才不可能「一个开着、一个当关」。
public enum CloudSyncPreference {
    /// `UserDefaults` 键（默认 `false` ⇒ 关）。
    public static let enabledKey = "doyah.notes.cloudSyncEnabled"

    /// 当前是否开启（缺省 = 关）。
    public static func isEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: enabledKey)
    }

    /// 置位（界面开关调它）。
    public static func setEnabled(_ enabled: Bool, _ defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: enabledKey)
    }
}

// MARK: - 日期与 JSON 编码口径（`云E` §四 B 层：确定性序列化）

/// 同步面的编解码口径 —— **一处定义**（端点请求体、状态文件、解码都用它，不各写一份）。
///
/// **时间口径（前门裁 ⑲ ② · SRS v3.93 `2bfe63b` §6.4.1.1）**：
///   · **写入** = ISO 8601 **毫秒 3 位 + 时区偏移**（`2026-10-09T22:40:00.000+08:00`）；
///   · **读取 / 比对** = 先**归一到 UTC 毫秒**再比（服务端实测形如
///     `2026-10-09T22:02:32.008207+08:00` —— 小数位不定、带偏移）；
///   · **禁止时间字段字符串比较** —— 比的是归一后的**瞬时**，不是字面串。
///
/// 键序 / 空白 / `/` 转义（`云E` §四 B1/B2/B5 + 裁定 ⑲ ③）：键按**字典序**、**紧凑**、`/` **不转义**、
/// `null` 只在行级 `deleted_at`。
enum CloudSyncCoding {

    /// **写入口**：ISO8601 带小数秒，时区 = **本机**（⇒ 偏移形如 `+08:00`，与契约 canonical 样例、
    /// 服务端 `timestamptz` 的渲染形态同形）。小数位由 `ISO8601DateFormatter` 固定为 **3 位（毫秒）**。
    private static func writer() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = .current
        return formatter
    }

    /// **读入口**：带小数秒的 ISO8601。偏移 / `Z` 由串自带，与本机时区无关。
    private static func fractional() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }

    private static func plain() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }

    /// **归一到 UTC 毫秒**（裁定 ⑲ ②：比对前先归一 —— 服务端给的小数位不定 · 6 位实测）。
    /// 于是「同一次写入」在两侧、在两种小数位下都得到**同一个 `Date`** —— 时间字段不做字符串比较。
    static func normalizedToMilliseconds(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 * 1000).rounded() / 1000)
    }

    /// **写入**口径：ISO8601 毫秒 3 位 + 时区偏移 —— 上行与 `updated_after` 游标都用它。
    static func iso8601String(_ date: Date) -> String {
        writer().string(from: date)
    }

    /// **读取**口径：ISO8601（小数 1–9 位 / `Z` / ±偏移）或纯数值（Unix 秒）⇒ 归一到 UTC 毫秒。
    static func parseDate(_ string: String) -> Date? {
        if let date = fractional().date(from: string) { return normalizedToMilliseconds(date) }
        if let date = plain().date(from: string) { return normalizedToMilliseconds(date) }
        return nil
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self) {
                guard let date = parseDate(string) else {
                    throw DecodingError.dataCorruptedError(
                        in: container, debugDescription: "unrecognized date: \(string)"
                    )
                }
                return date
            }
            if let seconds = try? container.decode(Double.self) {
                return normalizedToMilliseconds(Date(timeIntervalSince1970: seconds))
            }
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "date is neither ISO8601 string nor number"
            )
        }
        return decoder
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        // 键序稳定（`云E` §四 B1）+ 不转义 `/`（B5）+ 紧凑（B2）—— 跨端逐字节比对与冲突判定的前提。
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(iso8601String(date))
        }
        return encoder
    }

    /// **上行体的 canonical JSON**（契约 §6.4.1.1 判据①②③）——**键序按契约列序**，不是字典序：
    /// `uid` → `title` → `content` → `content_type` → `notebook_uid` → `tags` → `pinned` → `rev`
    /// → `updated_at` → `deleted_at` → `device_id`（`owner_id` **不写**，服务端 `default auth.uid()`）。
    ///
    /// 三条硬口径：
    ///   · **可选键省略** —— 没值的键**不输出**（不写 `null` 占位）；
    ///   · **唯一例外 = `deleted_at`** —— 未删除时**显式 `null`**（墓碑语义要求该列可查、可比较）；
    ///   · `content` = **字符串**（内含 JSON，不得作为嵌套对象传输）；`/` 不转义；紧凑。
    ///
    /// 为什么不用 `encoder()`：`JSONEncoder` 的键序不保插入序，`.sortedKeys` 只给字典序 ——
    /// 两者都拿不到契约列序（判据①）。
    static func uploadJSON(_ row: CloudNoteRow) -> String {
        var parts: [String] = []
        parts.append("\"uid\":\(NoteBodyExchange.quoted(row.uid))")
        if let title = row.title { parts.append("\"title\":\(NoteBodyExchange.quoted(title))") }
        if let content = row.content { parts.append("\"content\":\(NoteBodyExchange.quoted(content))") }
        if let contentType = row.contentType {
            parts.append("\"content_type\":\(NoteBodyExchange.quoted(contentType))")
        }
        if let notebookUid = row.notebookUid {
            parts.append("\"notebook_uid\":\(NoteBodyExchange.quoted(notebookUid))")
        }
        if let tags = row.tags {
            parts.append("\"tags\":[\(tags.map(NoteBodyExchange.quoted).joined(separator: ","))]")
        }
        if let pinned = row.pinned { parts.append("\"pinned\":\(pinned)") }
        parts.append("\"rev\":\(row.rev)")
        parts.append("\"updated_at\":\(NoteBodyExchange.quoted(iso8601String(row.updatedAt)))")
        if let deletedAt = row.deletedAt {
            parts.append("\"deleted_at\":\(NoteBodyExchange.quoted(iso8601String(deletedAt)))")
        } else {
            parts.append("\"deleted_at\":null")
        }
        if let deviceId = row.deviceId { parts.append("\"device_id\":\(NoteBodyExchange.quoted(deviceId))") }
        return "{\(parts.joined(separator: ","))}"
    }
}

// MARK: - 发往云端的载荷 · canonical 同形判据

/// **上行载荷的 canonical 同形检查**（急件 · 派单 `T-20261009-158` 第 ④ 件）。
///
/// 由头 = 真机实测：链路通了，但载荷**不合契约**（`content_type=application/json` + `content` 内部
/// 是内部模型形态）——这类偏差本该**在出包前判红**，而不是等跨端互验才发现。于是把契约 §6.4.1.1
/// 的判据①②③④压成一份**可跑、可负例**的机械检查：对上行体的 `content` / `content_type` 逐条核对，
/// 返回违规清单（空 = 通过）。判据本体只在这一份，单测与出包前检查读同一条。
public enum CloudPayloadCanonical {

    /// 契约允许的 `content_type`（= 本地 `contentType` 同值）。
    public static let expectedContentType = "text/plain"

    /// 行级 snake_case 键名 —— 只许出现在**行级**，`content` 内部出现即判红（契约 §6.4.1.1 禁令①）。
    static let rowLevelSnakeKeys = ["content_type", "notebook_uid", "updated_at", "deleted_at", "device_id", "owner_id"]

    /// 违规码（**语言无关**：Core 不得新增展示文案字面量 —— 出口层自己映射成人话，
    /// `Scripts/check-core-localization.py` 的棘轮就不必为诊断串开口子）。
    public enum Violation: String, Equatable, Sendable, CaseIterable {
        /// 判据④：`content_type` 与本地同值不符（应 `text/plain`）。
        case contentTypeMismatch
        /// `content` 缺失或为空。
        case contentMissing
        /// `content` 是空壳（`{}` / `[]` / `""`）—— 空壳不算笔记。
        case contentEmptyShell
        /// 判据①：`content` 内 `version` 不在首位。
        case contentVersionNotFirst
        /// `content` 缺 `spans`。
        case contentMissingSpans
        /// 判据③ 禁令①：`content` 内部出现行级 snake 键。
        case contentRowLevelSnakeKey
        /// `content` 用了内部键 `text`（交换面应 `content`）。
        case contentUsesInternalTextKey
        /// `styles` 是数组（交换面应对象）。
        case contentStylesIsArray
        /// span 的 `type` 与 `content` 不成对（每个 span 都须带 `type`）。
        case spanTypeContentUnpaired
    }

    /// 逐条核对上行载荷。空数组 = 通过。
    public static func violations(content: String?, contentType: String?) -> [Violation] {
        var found: [Violation] = []

        // 判据④：`content_type` = 与本地 `contentType` 同值
        if (contentType ?? "") != expectedContentType {
            found.append(.contentTypeMismatch)
        }

        // 判据③④：`content` 必须是**非空壳**的 JSON 字符串
        guard let content, !content.isEmpty else {
            found.append(.contentMissing)
            return found
        }
        if content == "{}" || content == "[]" || content == "\"\"" {
            found.append(.contentEmptyShell)
        }

        // 判据①：`content` 内键序 = `version` → `spans`（`version` 必须在首位）
        if !content.hasPrefix("{\"version\":") {
            found.append(.contentVersionNotFirst)
        }
        if !content.contains("\"spans\":") {
            found.append(.contentMissingSpans)
        }

        // 判据③：`content` 是字符串，内部**不得** snake 化
        for key in rowLevelSnakeKeys where content.contains("\"\(key)\"") {
            found.append(.contentRowLevelSnakeKey)
        }

        // 交换形态：span 用 `type` + `content` + `styles` **对象**；内部键 `text` / 数组式 `styles` 判红
        if content.contains("\"text\":") {
            found.append(.contentUsesInternalTextKey)
        }
        if content.contains("\"styles\":[") {
            found.append(.contentStylesIsArray)
        }
        // 每个 span 都必须带 `type`（`TEXT` / `LIST_*`）—— 数量对不上即判红
        let typeCount = occurrences(of: "\"type\":", in: content)
        let contentCount = occurrences(of: "\"content\":", in: content)
        if typeCount != contentCount || typeCount == 0 {
            found.append(.spanTypeContentUnpaired)
        }

        return found
    }

    /// 子串出现次数（判据用，纯函数）。
    static func occurrences(of needle: String, in haystack: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        var count = 0
        var search = haystack[...]
        while let range = search.range(of: needle) {
            count += 1
            search = search[range.upperBound...]
        }
        return count
    }
}

