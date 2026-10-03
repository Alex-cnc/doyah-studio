import Foundation

// 笔记存储层（`FR-PLUG-08` / Q23 拍板：桌面各端笔记存储统一到本地 SQLite）。
//
// 这一层坐在 `SQLiteKit`（C 绑定）之上，做三件事：
//   ① **schema v1 与升级**：版本号写进 `PRAGMA user_version`，打开即幂等升到最新版；
//   ② **笔记 ↔ 表的映射**：`note` / `note_tag` / `note_timeline` / `note_attachment` + `note_fts`（FTS5）；
//   ③ **快照备份**：`VACUUM INTO` 出一份**自洽的副本**（不是把活跃库文件拷走 —— 那在 WAL 下会拿到半份数据）。
//
// 三条口径值得写在前面（都是别处踩过的坑）：
//   · **时间存 REAL 秒**（`Date.timeIntervalSince1970`），不存 ISO8601 字符串。字符串排序是字典序、
//     跨时区还要解析；而 `ORDER BY updated_at DESC` 这种排序是数值语义。JSON 里的 ISO8601 是**旧格式**，
//     由迁移器换算一次（见 `NoteLibraryMigration`）。
//   · **NULL 与空串不是一回事**：`source_connection_name` 为 NULL 表示「这条笔记没有连接来源」，
//     空串表示「有来源、但名字是空的」。取值一律走 `SQLiteValue`，不做 Swift 类型推断。
//   · **不认识的枚举值不许降级**：`source_kind` 存 TEXT；读到表里没有的 kind 时**抛错**，
//     不默默当成 `.manual`（静默降级会让「这条是怎么来的」永久失真）。
//
// 全文检索（FTS5）的口径来自第 18 轮实测：默认分词器 `unicode61` **不切中文**
// （`MATCH '骑行'` 命中 0），所以 `note_fts` 用 `tokenize='trigram'`；而 trigram **要求查询串 ≥3 字**
// （`'洞庭湖'` 命中、2 字的 `'骑行'` 不命中）。因此 `search(_:)` 对 1~2 字的查询**走 LIKE 兜底**并
// 在返回值里如实标注走了哪条路 —— 「检索不到」与「分词器不切中文」是两件事，不能让用户面对前者。

/// 笔记库的 schema **v1**（`FR-PLUG-08`）。
///
/// DDL 写成一份**有序的语句清单**而不是一坨字符串：迁移器按顺序执行、门禁（与单测）按名单核对
/// 「说要建的表 / 索引 / 触发器，库里是不是真有」——「我以为建过了」是这类代码最贵的缺陷。
public enum NoteSchemaV1 {

    /// 版本号（写进 `PRAGMA user_version`，随事务原子生效）。
    public static let version: Int32 = 1

    /// 表与虚拟表（含 FTS5 的 `note_fts`）。
    public static let tables: [String] = ["note", "note_tag", "note_timeline", "note_attachment", "note_fts"]

    /// 触发器：`note_fts` 与 `note` **结构性同步**（不给「忘了更新索引」留窗口）。
    public static let triggers: [String] = [
        "note_fts_after_insert",
        "note_fts_after_delete",
        "note_fts_after_update"
    ]

    /// 索引（把「按条件查」要用的列先备好：更新时间倒序 / 标签 / 时间线 / 附件）。
    public static let indexes: [String] = [
        "note_updated_at_index",
        "note_source_kind_index",
        "note_tag_tag_index",
        "note_timeline_note_index",
        "note_attachment_note_index"
    ]

    /// 建库语句（顺序即依赖顺序：`note` 先，触发器最后）。
    public static let ddl: [String] = [
        """
        CREATE TABLE note (
            id INTEGER PRIMARY KEY,
            uuid TEXT NOT NULL UNIQUE,
            title TEXT NOT NULL,
            body TEXT NOT NULL DEFAULT '',
            source_kind TEXT NOT NULL,
            source_connection_name TEXT,
            source_fingerprint TEXT,
            source_captured_at REAL NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            contains_row_data INTEGER NOT NULL DEFAULT 0 CHECK (contains_row_data IN (0, 1)),
            storage_version INTEGER NOT NULL DEFAULT 1
        );
        """,
        "CREATE INDEX note_updated_at_index ON note (updated_at DESC);",
        "CREATE INDEX note_source_kind_index ON note (source_kind);",
        """
        CREATE TABLE note_tag (
            note_id INTEGER NOT NULL REFERENCES note (id) ON DELETE CASCADE,
            tag TEXT NOT NULL,
            PRIMARY KEY (note_id, tag)
        );
        """,
        "CREATE INDEX note_tag_tag_index ON note_tag (tag);",
        """
        CREATE TABLE note_timeline (
            id INTEGER PRIMARY KEY,
            note_id INTEGER NOT NULL REFERENCES note (id) ON DELETE CASCADE,
            at REAL NOT NULL,
            kind TEXT NOT NULL,
            detail TEXT
        );
        """,
        "CREATE INDEX note_timeline_note_index ON note_timeline (note_id, at);",
        """
        CREATE TABLE note_attachment (
            id INTEGER PRIMARY KEY,
            uuid TEXT NOT NULL UNIQUE,
            note_id INTEGER NOT NULL REFERENCES note (id) ON DELETE CASCADE,
            path TEXT NOT NULL,
            byte_count INTEGER,
            added_at REAL NOT NULL
        );
        """,
        "CREATE INDEX note_attachment_note_index ON note_attachment (note_id);",
        // FTS5 外部内容表：正文存在 `note` 里，索引只存倒排表（省一份正文拷贝），
        // 同步由触发器负责。`tokenize='trigram'` 是中文能检索的前提（见文件头）。
        """
        CREATE VIRTUAL TABLE note_fts USING fts5 (
            title,
            body,
            content = 'note',
            content_rowid = 'id',
            tokenize = 'trigram'
        );
        """,
        """
        CREATE TRIGGER note_fts_after_insert AFTER INSERT ON note BEGIN
            INSERT INTO note_fts (rowid, title, body) VALUES (new.id, new.title, new.body);
        END;
        """,
        // 外部内容表的删除必须把**旧值**喂给 FTS5（这是官方口径，不是可省的一步）。
        """
        CREATE TRIGGER note_fts_after_delete AFTER DELETE ON note BEGIN
            INSERT INTO note_fts (note_fts, rowid, title, body) VALUES ('delete', old.id, old.title, old.body);
        END;
        """,
        """
        CREATE TRIGGER note_fts_after_update AFTER UPDATE ON note BEGIN
            INSERT INTO note_fts (note_fts, rowid, title, body) VALUES ('delete', old.id, old.title, old.body);
            INSERT INTO note_fts (rowid, title, body) VALUES (new.id, new.title, new.body);
        END;
        """
    ]
}

/// 笔记库的 schema **v2**（队列 `L-97` 第二片）：**两层归属落库**（笔记本架 / 笔记本）。
///
/// 契约出处：`DoyahNotes/Docs/核心契约.md` **§2.12 两层归属**（`shelf` / `notebook` 实体 +
/// `Inspiration.notebookUid` 非空）。本侧只引用不复制 —— 表名 / 列名与契约同形。
///
/// 三条口径写在前面（都是这一片真正的取舍）：
///   · **`note.notebook_uid` 刻意不加外键**：加了 `ON DELETE CASCADE` 之后「删一个笔记本」会**静默删掉**
///     里面的笔记，而契约 §2.12 要求删容器时二选一（一并删 / **移到默认笔记本**，默认取后者）。
///     归属策略归 `NotebookDirectory`（Core 半）算，库这一层只存值。
///   · **列可空**：v1 的存量笔记没有归属 ⇒ 补列这一句只能加可空列。而「没有无归属笔记」这条不变量
///     由**写入与迁移**保证（`upsert(_ note:)` 落默认笔记本、`ensureDefaultContainers` 兜底回填），
///     不由 `NOT NULL` 保证 —— 那会让 `ALTER TABLE` 在存量库上直接失败。
///   · **改列不动数据**：`upsert(_ note:)` 的 `ON CONFLICT DO UPDATE` **不含 `notebook_uid`** ——
///     否则「改几个字再保存」会把这条笔记的归属抹回默认（静默的数据损坏）。
public enum NoteSchemaV2 {

    public static let version: Int32 = 2

    /// 新增的表。
    public static let tables: [String] = ["shelf", "notebook"]

    /// 新增的索引。
    public static let indexes: [String] = ["notebook_shelf_index", "note_notebook_index"]

    /// 升级语句（顺序即依赖顺序：`shelf` 先于 `notebook`，补列在两张表之后）。
    public static let ddl: [String] = [
        """
        CREATE TABLE shelf (
            id INTEGER PRIMARY KEY,
            uid TEXT NOT NULL UNIQUE,
            name TEXT NOT NULL,
            sort_order INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL,
            is_default INTEGER NOT NULL DEFAULT 0 CHECK (is_default IN (0, 1))
        );
        """,
        """
        CREATE TABLE notebook (
            id INTEGER PRIMARY KEY,
            uid TEXT NOT NULL UNIQUE,
            shelf_uid TEXT NOT NULL REFERENCES shelf (uid) ON DELETE CASCADE,
            name TEXT NOT NULL,
            sort_order INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL,
            is_default INTEGER NOT NULL DEFAULT 0 CHECK (is_default IN (0, 1))
        );
        """,
        "CREATE INDEX notebook_shelf_index ON notebook (shelf_uid, sort_order);",
        // 存量笔记补列：v1 的笔记一开始没有归属 ⇒ 可空列（回填见 `ensureDefaultContainers`）。
        "ALTER TABLE note ADD COLUMN notebook_uid TEXT;",
        "CREATE INDEX note_notebook_index ON note (notebook_uid);"
    ]
}

/// 附件索引的一条（`FR-PLUG-08`：**附件二进制留在文件系统，库里只存路径**）。
public struct NoteAttachment: Equatable, Sendable {
    public var id: UUID
    public var path: String
    /// 记录时的字节数（**只是元信息**，不据此校验文件；文件可能已被外部改动）。
    public var byteCount: Int64?
    public var addedAt: Date

    public init(id: UUID = UUID(), path: String, byteCount: Int64? = nil, addedAt: Date = Date()) {
        self.id = id
        self.path = path
        self.byteCount = byteCount
        self.addedAt = addedAt
    }
}

/// 时间线的一条（谁在什么时候因为什么动了这条笔记）。
public struct NoteTimelineEntry: Equatable, Sendable {
    public var at: Date
    public var kind: String
    public var detail: String?

    public init(at: Date, kind: String, detail: String? = nil) {
        self.at = at
        self.kind = kind
        self.detail = detail
    }
}

/// 存储层的失败。**机器可读**的出口（界面文案由语言表按类别组织，这一层不产文案）。
public enum NoteStorageFailure: Error, Equatable, CustomStringConvertible {
    /// 表里出现了这一版不认识的 `source_kind` —— 不降级、不猜（见文件头第三条口径）。
    case unknownSourceKind(String)
    /// 库的 schema 版本比这一版代码更新（将来回退 App 版本时会遇到）：**拒绝写入**而不是继续用。
    case unsupportedSchemaVersion(found: Int32, supported: Int32)
    /// 快照目标已存在：**不覆盖**（备份不许把上一次的备份顶掉）。
    case snapshotTargetExists(String)
    /// 快照写出来了，但读回来不对（行数或完整性检查不过）。
    case snapshotMismatch(String)

    public var description: String {
        switch self {
        case .unknownSourceKind(let raw):
            return "unknown note source kind in the database: \(raw)"
        case .unsupportedSchemaVersion(let found, let supported):
            return "database schema version \(found) is newer than supported \(supported)"
        case .snapshotTargetExists(let path):
            return "snapshot target already exists: \(path)"
        case .snapshotMismatch(let reason):
            return "snapshot verification failed: \(reason)"
        }
    }
}

/// 一次快照的结果（`VACUUM INTO`）。
public struct NoteSnapshot: Equatable, Sendable {
    public var url: URL
    public var byteCount: Int64
    /// 快照里的笔记条数（与源库**当场核对过**）。
    public var noteCount: Int
    /// 快照自带的 `PRAGMA user_version`。
    public var schemaVersion: Int32
    /// `PRAGMA integrity_check` 的原话（正常是 `ok`）。
    public var integrity: String

    public init(url: URL, byteCount: Int64, noteCount: Int, schemaVersion: Int32, integrity: String) {
        self.url = url
        self.byteCount = byteCount
        self.noteCount = noteCount
        self.schemaVersion = schemaVersion
        self.integrity = integrity
    }
}

/// 笔记库（SQLite）。
///
/// **线程口径**：连接自身串行化（`SQLiteKit` 内是递归锁 + `FULLMUTEX`），语义上的并发由调用方
/// （`NoteStore` 是 actor）负责。这里不做第二套队列 —— 两层锁解决不了任何问题，只会多一处死锁面。
public final class NoteDatabase {

    /// 库文件名。**与旧格式 `notes.json` 不同名**：迁移要靠「目标不在」判定要不要搬（L-03 的纪律）。
    public static let fileName = "notes.sqlite3"

    /// 这一版代码支持的 schema 版本。
    public static let supportedVersion = NoteSchemaV2.version

    private let connection: SQLiteConnection

    /// 打开（必要时新建）并**升到最新 schema**。幂等：已经是最新版的库再打开不会动任何数据。
    public init(path: String) throws {
        let connection = try SQLiteConnection(path: path)
        self.connection = connection
        try configure(connection)
        try applySchemaIfNeeded()
    }

    /// 连接参数（每一条都有理由，别省）：
    ///   · `journal_mode = WAL` —— 「并发写 + 多进程读」是 `FR-PLUG-08` 的判据之一；
    ///   · `foreign_keys = ON` —— SQLite 默认**不**开外键；不开的话 `ON DELETE CASCADE` 是装饰品，
    ///     删一条笔记会留下孤儿标签 / 时间线 / 附件行；
    ///   · `synchronous = NORMAL` —— WAL 下的常规档：崩溃不坏库（可能丢最后若干事务，不丢一致性）。
    ///     刻意**不用** `OFF`：笔记库的价值就在「崩溃不坏数据」这条判据上。
    private func configure(_ connection: SQLiteConnection) throws {
        try connection.setPragma("journal_mode = WAL")
        try connection.setPragma("foreign_keys = ON")
        try connection.setPragma("synchronous = NORMAL")
    }

    deinit { try? connection.close() }

    public var path: String { connection.path }

    public func close() throws { try connection.close() }

    // MARK: - schema

    /// 库头里的 `user_version`。
    public var userVersion: Int32 {
        (try? connection.scalarInt("PRAGMA user_version")).flatMap { $0 } .map(Int32.init) ?? 0
    }

    /// 库里的 `journal_mode`（自证 WAL 真的生效，而不是"我以为设了"）。
    public var journalMode: String {
        (try? connection.scalarText("PRAGMA journal_mode")) ?? ""
    }

    /// 外键开关真的开着吗（同上）。
    public var foreignKeysEnabled: Bool {
        (try? connection.scalarInt("PRAGMA foreign_keys")).flatMap { $0 } == 1
    }

    /// 按需建/升级到最新 schema（当前 v2）。**一个事务里做完**：DDL 与版本号一起生效，
    /// 不会出现「表建了一半、版本已记 2」。
    ///
    /// 逐版升级（不是「按最新版直接建」）：存量库要真的走 v1 → v2 这两步，
    /// 判据（与单测）才有机会证明「老库升得上来」—— 一条只在新库上跑通的路是假绿。
    public func applySchemaIfNeeded() throws {
        let current = userVersion
        if current > Self.supportedVersion {
            // 比代码更新的库（用户回退过 App 版本）：**拒绝动它**，让人来处理，而不是拿旧代码去改新库。
            throw NoteStorageFailure.unsupportedSchemaVersion(found: current, supported: Self.supportedVersion)
        }
        guard current < Self.supportedVersion else { return }
        try connection.transaction {
            if current < NoteSchemaV1.version {
                for statement in NoteSchemaV1.ddl { try connection.execute(statement) }
                try connection.setPragma("user_version = \(NoteSchemaV1.version)")
            }
            if current < NoteSchemaV2.version {
                for statement in NoteSchemaV2.ddl { try connection.execute(statement) }
                try connection.setPragma("user_version = \(NoteSchemaV2.version)")
            }
        }
    }

    /// 把库切成「单文件日志」（`journal_mode = DELETE`）：迁移器在**换名之前**用它 —— 换名只搬主库文件，
    /// WAL 的 `-wal` / `-shm` 侧车会留在原地，那样交出去的库会少半份已提交数据。
    /// 交付之后由 `NoteDatabase` 打开时再切回 WAL（开关记在库头，只写一次）。
    func switchToSingleFileJournal() throws {
        try connection.setPragma("journal_mode = DELETE")
    }

    /// 库里实际存在的表 / 虚拟表（门禁与单测按 `NoteSchemaV1.tables` + `NoteSchemaV2.tables` 对账）。
    public func tableNames() throws -> [String] {
        try connection.schemaObjects(kind: "table")
    }

    /// 库里实际存在的触发器。
    public func triggerNames() throws -> [String] {
        try connection.schemaObjects(kind: "trigger")
    }

    /// `PRAGMA integrity_check` 的原话（正常是 `ok`）。
    public func integrityCheck() throws -> String {
        try connection.scalarText("PRAGMA integrity_check") ?? "no result"
    }

    // MARK: - 写

    /// 写入或按 uuid 覆盖一条笔记，返回它的 rowid。
    ///
    /// 一条笔记的三块（本体 + 标签 + 时间线）在**一个事务**里落库：半个笔记（正文进去了、标签没进去）
    /// 是最难查的一类不一致。附件不在这里动 —— 附件是**独立动作**（加附件不该顺带重写正文）。
    @discardableResult
    public func upsert(_ note: Note) throws -> Int64 {
        try connection.transaction {
            try connection.execute(
                """
                INSERT INTO note (
                    uuid, title, body, source_kind, source_connection_name, source_fingerprint,
                    source_captured_at, created_at, updated_at, contains_row_data, storage_version
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT (uuid) DO UPDATE SET
                    title = excluded.title,
                    body = excluded.body,
                    source_kind = excluded.source_kind,
                    source_connection_name = excluded.source_connection_name,
                    source_fingerprint = excluded.source_fingerprint,
                    source_captured_at = excluded.source_captured_at,
                    updated_at = excluded.updated_at,
                    contains_row_data = excluded.contains_row_data,
                    storage_version = excluded.storage_version;
                """,
                [
                    .text(note.id.uuidString),
                    .text(note.title),
                    .text(note.body),
                    .text(note.source.kind.rawValue),
                    note.source.connectionName.map { SQLiteValue.text($0) } ?? .null,
                    note.source.fingerprint.map { SQLiteValue.text($0) } ?? .null,
                    .real(note.source.capturedAt.timeIntervalSince1970),
                    .real(note.createdAt.timeIntervalSince1970),
                    .real(note.updatedAt.timeIntervalSince1970),
                    .integer(note.containsRowData ? 1 : 0),
                    .integer(Int64(NoteSchemaV1.version))
                ]
            )
            // **按 uuid 反查 rowid**，而不是读 `last_insert_rowid()`：走的是 upsert 的 UPDATE 分支时，
            // 那个值可能是上一句话留下的 —— 静默指向另一条笔记，而且不会有任何症状。
            let rowID = try requireRowID(of: note.id)
            // 归属补缺（schema v2）：**新笔记**落默认笔记本；已有归属的**一字不动**
            // （`ON CONFLICT` 那一段不含 `notebook_uid`，这里也只管 NULL / 空串）。
            // 默认容器还没建（首次运行、且调用方还没走过 `ensureDefaultContainers`）时这条 UPDATE
            // 不匹配任何行、也不写入 NULL —— 交给迁移那一步兜底。
            try connection.execute(
                """
                UPDATE note SET notebook_uid = (SELECT uid FROM notebook WHERE is_default = 1 LIMIT 1)
                WHERE uuid = ? AND (notebook_uid IS NULL OR notebook_uid = '');
                """,
                [.text(note.id.uuidString)]
            )
            // 标签是**全量替换**语义（`Note.tags` 是完整集合）：先清后插，省掉「差集算法写错」这类缺陷。
            try connection.execute("DELETE FROM note_tag WHERE note_id = ?", [.integer(rowID)])
            for tag in Set(note.tags).sorted() {
                try connection.execute(
                    "INSERT INTO note_tag (note_id, tag) VALUES (?, ?)",
                    [.integer(rowID), .text(tag)]
                )
            }
            try connection.execute(
                "INSERT INTO note_timeline (note_id, at, kind, detail) VALUES (?, ?, ?, ?)",
                [
                    .integer(rowID),
                    .real(note.updatedAt.timeIntervalSince1970),
                    .text(NoteTimelineKind.upsert),
                    .null
                ]
            )
            return rowID
        }
    }

    /// 追加一条附件索引（**只存路径**）。
    public func addAttachment(_ attachment: NoteAttachment, to id: UUID) throws {
        try connection.transaction {
            let rowID = try requireRowID(of: id)
            try connection.execute(
                "INSERT OR REPLACE INTO note_attachment (uuid, note_id, path, byte_count, added_at) VALUES (?, ?, ?, ?, ?)",
                [
                    .text(attachment.id.uuidString),
                    .integer(rowID),
                    .text(attachment.path),
                    attachment.byteCount.map { SQLiteValue.integer($0) } ?? .null,
                    .real(attachment.addedAt.timeIntervalSince1970)
                ]
            )
        }
    }

    /// 追加一条时间线（保真：**只增不改**，时间线是流水）。
    public func recordTimeline(_ entry: NoteTimelineEntry, for id: UUID) throws {
        try connection.transaction {
            let rowID = try requireRowID(of: id)
            try connection.execute(
                "INSERT INTO note_timeline (note_id, at, kind, detail) VALUES (?, ?, ?, ?)",
                [
                    .integer(rowID),
                    .real(entry.at.timeIntervalSince1970),
                    .text(entry.kind),
                    entry.detail.map { SQLiteValue.text($0) } ?? .null
                ]
            )
        }
    }

    /// 删一条笔记（标签 / 时间线 / 附件索引靠外键级联一起走，`foreign_keys = ON` 是前提）。
    public func delete(id: UUID) throws {
        try connection.execute("DELETE FROM note WHERE uuid = ?", [.text(id.uuidString)])
    }

    // MARK: - 读

    public func noteCount() throws -> Int {
        Int(try connection.scalarInt("SELECT count(*) FROM note") ?? 0)
    }

    /// 全部笔记（更新时间倒序、同时间按标题 —— **稳定有序**，界面不必自己再排一遍）。
    public func notes() throws -> [Note] {
        try notes(from: "SELECT * FROM note ORDER BY updated_at DESC, title ASC")
    }

    public func note(id: UUID) throws -> Note? {
        try notes(from: "SELECT * FROM note WHERE uuid = ?", [.text(id.uuidString)]).first
    }

    /// 时间线（按时间正序 —— 读流水要顺着读）。
    public func timeline(of id: UUID) throws -> [NoteTimelineEntry] {
        let rowID = try requireRowID(of: id)
        return try connection
            .query("SELECT at, kind, detail FROM note_timeline WHERE note_id = ? ORDER BY at ASC, id ASC", [.integer(rowID)])
            .map { row in
                NoteTimelineEntry(
                    at: Date(timeIntervalSince1970: row["at"].doubleValue ?? 0),
                    kind: row.text("kind") ?? "",
                    detail: row.text("detail")
                )
            }
    }

    /// 附件索引（按加入时间正序）。
    public func attachments(of id: UUID) throws -> [NoteAttachment] {
        let rowID = try requireRowID(of: id)
        return try connection
            .query(
                "SELECT uuid, path, byte_count, added_at FROM note_attachment WHERE note_id = ? ORDER BY added_at ASC",
                [.integer(rowID)]
            )
            .compactMap { row in
                guard let uuid = row.text("uuid"), let identifier = UUID(uuidString: uuid) else { return nil }
                return NoteAttachment(
                    id: identifier,
                    path: row.text("path") ?? "",
                    byteCount: row["byte_count"].intValue,
                    addedAt: Date(timeIntervalSince1970: row["added_at"].doubleValue ?? 0)
                )
            }
    }

    /// 检索结果 + **走的是哪条路**（trigram 全文检索还是 LIKE 兜底）。
    ///
    /// 为什么要把路径一起返回：trigram 要求查询串 ≥3 字，1~2 字的查询（中文里很常见）只能兜底；
    /// 调用方需要能如实告诉用户"这两条是按子串匹配找的"。
    public struct SearchResult: Equatable, Sendable {
        public enum Route: String, Equatable, Sendable {
            /// FTS5 trigram 命中（查询串 ≥3 字且短语在标题 / 正文里出现）。
            /// **标签命中在这条路里作为补充一并并入**（`note_fts` 只索引标题与正文）——
            /// 路线说的是「这次查询有没有走成全文检索」，不是「每条结果的每一个命中来源」。
            case fullText
            /// 子串扫描兜底：全文索引**没命中**（查询串 < 3 字 —— trigram 不产出 token；
            /// 或 ≥3 字的短语落了空），整条按子串扫标题 / 正文 / 标签。
            case substring
        }
        public var route: Route
        public var notes: [Note]
    }

    /// 检索**标题 / 正文 / 标签**（`FR-PLUG-08` 的「按条件查与全文检索」）。
    ///
    /// **三个字段都要查**：界面搜索框的占位符写着「搜索标题 / 正文 / 标签」，而 `note_fts`
    /// 只索引标题与正文 ⇒ 标签那一半必须在两条路里各补一次（队列 L-44 收口时实测到的
    /// 「差一点」：界面检索从内存过滤改走库，标签命中会**静默丢掉**，占位符当场变成一句假话）。
    /// 合并后的顺序按 `updated_at DESC, title ASC` **重排**（两次查询拼起来的数组不能各排各的），
    /// 与 `notes()` 同一个口径。
    public func search(_ query: String, limit: Int = 200) throws -> SearchResult {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return SearchResult(route: .fullText, notes: try notes()) }

        // `LIKE` 的模式串（`%` 包住的子串；转义见 `escapeLike`）—— 两条路都要用它，所以先算出来。
        let pattern = "%" + Self.escapeLike(needle) + "%"

        // 口径：查询串按**字符**数（不是字节）判定 —— 中文一个字符三个字节，按字节判会让 1 个汉字过关、
        // 而 trigram 实际切不出 token，于是"检索得到但什么都没找到"。
        if needle.count >= 3 {
            // FTS5 的 MATCH 需要**字面量**串（`?` 绑定在 FTS5 的查询语法里不被接受为短语），
            // 所以这里显式转义双引号并整体包成短语 —— 用户输入里的 `-` / `*` 因此不会被当成查询运算符。
            let phrase = "\"" + needle.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            let rows = try connection.query(
                """
                SELECT note.* FROM note
                JOIN note_fts ON note_fts.rowid = note.id
                WHERE note_fts MATCH ?
                ORDER BY note.updated_at DESC, note.title ASC
                LIMIT ?;
                """,
                [.text(phrase), .integer(Int64(limit))]
            )
            // 兜底判据：trigram 只覆盖 ≥3 字的**连续子串**，若查询串里含空格（"关于 骑行" 这类），
            // 短语匹配会空手而归 —— 这时退回子串扫描，宁可慢一点也不假装"没有"。
            if !rows.isEmpty {
                // 标签补充：`note_fts` 里没有标签这一列，所以「只有标签命中」的那些要单独捞一次，
                // 已经在全文结果里的不重复算（`id NOT IN (… MATCH …)`）。
                let tagRows = try connection.query(
                    """
                    SELECT * FROM note
                    WHERE id NOT IN (SELECT rowid FROM note_fts WHERE note_fts MATCH ?)
                      AND EXISTS (
                        SELECT 1 FROM note_tag
                        WHERE note_tag.note_id = note.id AND note_tag.tag LIKE ? ESCAPE '\\'
                      )
                    ORDER BY updated_at DESC, title ASC
                    LIMIT ?;
                    """,
                    [.text(phrase), .text(pattern), .integer(Int64(limit))]
                )
                let merged = try materialize(rows) + (try materialize(tagRows))
                return SearchResult(route: .fullText, notes: Self.byRecency(merged))
            }
        }
        let rows = try connection.query(
            """
            SELECT * FROM note
            WHERE title LIKE ? ESCAPE '\\' OR body LIKE ? ESCAPE '\\'
               OR EXISTS (
                 SELECT 1 FROM note_tag
                 WHERE note_tag.note_id = note.id AND note_tag.tag LIKE ? ESCAPE '\\'
               )
            ORDER BY updated_at DESC, title ASC
            LIMIT ?;
            """,
            [.text(pattern), .text(pattern), .text(pattern), .integer(Int64(limit))]
        )
        return SearchResult(route: .substring, notes: try materialize(rows))
    }

    /// 合并结果的定序（与 `notes()` 同口径）：最近更新在前，同一时刻按标题。
    private static func byRecency(_ notes: [Note]) -> [Note] {
        notes.sorted { left, right in
            if left.updatedAt != right.updatedAt { return left.updatedAt > right.updatedAt }
            return left.title < right.title
        }
    }

    /// `LIKE` 的转义（`%` / `_` / `\` 都要转，否则用户搜 `100%` 会匹配到一切）。
    static func escapeLike(_ text: String) -> String {
        var escaped = ""
        for character in text {
            if character == "\\" || character == "%" || character == "_" {
                escaped.append("\\")
            }
            escaped.append(character)
        }
        return escaped
    }

    // MARK: - 两层归属（schema v2 · 队列 L-97 第二片）

    /// 库里的两层结构（架 + 笔记本）。结构本身**不兜底**：库里一条都没有就如实返回空
    /// （兜底落点在 `NotebookDirectory` 的那几个 `resolved*` 与 `ensureDefaultContainers`）。
    public func notebookDirectory() throws -> NotebookDirectory {
        NotebookDirectory(shelves: try shelves(), notebooks: try notebooks())
    }

    /// 全部笔记本架（稳定排序与界面同口径：排序位 → 创建时刻 → uid）。
    public func shelves() throws -> [Shelf] {
        try connection
            .query("SELECT uid, name, sort_order, created_at, is_default FROM shelf ORDER BY sort_order ASC, created_at ASC, uid ASC")
            .map { row in
                Shelf(
                    uid: row.text("uid") ?? "",
                    name: row.text("name") ?? "",
                    sortOrder: Int(row.int("sort_order") ?? 0),
                    createdAt: Date(timeIntervalSince1970: row["created_at"].doubleValue ?? 0),
                    isDefault: row.int("is_default") == 1
                )
            }
    }

    /// 全部笔记本（同一条稳定排序）。
    public func notebooks() throws -> [Notebook] {
        try connection
            .query(
                "SELECT uid, shelf_uid, name, sort_order, created_at, is_default FROM notebook ORDER BY sort_order ASC, created_at ASC, uid ASC"
            )
            .map { row in
                Notebook(
                    uid: row.text("uid") ?? "",
                    shelfUid: row.text("shelf_uid") ?? "",
                    name: row.text("name") ?? "",
                    sortOrder: Int(row.int("sort_order") ?? 0),
                    createdAt: Date(timeIntervalSince1970: row["created_at"].doubleValue ?? 0),
                    isDefault: row.int("is_default") == 1
                )
            }
    }

    /// 写一个笔记本架（按 `uid` 覆盖；`is_default` 由调用方定）。
    public func upsert(_ shelf: Shelf) throws {
        try connection.execute(
            """
            INSERT INTO shelf (uid, name, sort_order, created_at, is_default) VALUES (?, ?, ?, ?, ?)
            ON CONFLICT (uid) DO UPDATE SET
                name = excluded.name, sort_order = excluded.sort_order, is_default = excluded.is_default;
            """,
            [
                .text(shelf.uid),
                .text(shelf.name),
                .integer(Int64(shelf.sortOrder)),
                .real(shelf.createdAt.timeIntervalSince1970),
                .integer(shelf.isDefault ? 1 : 0)
            ]
        )
    }

    /// 写一个笔记本（按 `uid` 覆盖）。`shelfUid` 指向不存在的架时**外键会拦下来**
    /// （`shelf_uid` 有 `REFERENCES shelf (uid)`，而 `foreign_keys = ON`）—— 这正是「不存在无归属笔记本」。
    public func upsert(_ notebook: Notebook) throws {
        try connection.execute(
            """
            INSERT INTO notebook (uid, shelf_uid, name, sort_order, created_at, is_default) VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT (uid) DO UPDATE SET
                shelf_uid = excluded.shelf_uid, name = excluded.name,
                sort_order = excluded.sort_order, is_default = excluded.is_default;
            """,
            [
                .text(notebook.uid),
                .text(notebook.shelfUid),
                .text(notebook.name),
                .integer(Int64(notebook.sortOrder)),
                .real(notebook.createdAt.timeIntervalSince1970),
                .integer(notebook.isDefault ? 1 : 0)
            ]
        )
    }

    /// 删一个笔记本架（里面的笔记本靠外键级联走）。
    ///
    /// **刻意只做「删这一行」**：里面的笔记怎么办是 `ContainerRemovalPlan`（Core 半）算出来的策略
    /// （一并删 / 移到默认笔记本），调用方先落那个计划、再调这里 —— 库这一层不替上层做决定。
    public func deleteShelf(uid: String) throws {
        try connection.execute("DELETE FROM shelf WHERE uid = ?", [.text(uid)])
    }

    /// 删一个笔记本（同一条纪律：笔记的处置归调用方）。
    public func deleteNotebook(uid: String) throws {
        try connection.execute("DELETE FROM notebook WHERE uid = ?", [.text(uid)])
    }

    /// 归属对（`uuid` ↔ `notebook_uid`）。顺序与 `notes()` 同口径（最近更新在前），
    /// 这样「按笔记本过滤」的结果与不过滤时的相对次序一致。
    public func placements() throws -> [NotebookPlacement] {
        try connection
            .query("SELECT uuid, notebook_uid FROM note ORDER BY updated_at DESC, title ASC")
            .compactMap { row in
                guard let uuid = row.text("uuid") else { return nil }
                return NotebookPlacement(noteID: uuid, notebookUid: row.text("notebook_uid"))
            }
    }

    /// 一条笔记的归属（缺归属 = `nil`）。
    public func notebookUid(of id: UUID) throws -> String? {
        try connection.scalarText("SELECT notebook_uid FROM note WHERE uuid = ?", [.text(id.uuidString)])
    }

    /// **缺归属**的笔记条数（`NULL` / 空串）。迁移与判据用它自证「没有无归属笔记」——
    /// 这一条是可量的事实，不是「我以为回填过了」。
    public func unassignedNoteCount() throws -> Int {
        Int(try connection.scalarInt("SELECT count(*) FROM note WHERE notebook_uid IS NULL OR notebook_uid = ''") ?? 0)
    }

    /// 把若干条笔记移到目标笔记本。返回**真正被改动**的行数。
    ///
    /// 两条纪律：① 目标 uid **认不出就落默认笔记本**（走 `NotebookDirectory.resolvedNotebookUid`，
    /// 与列表 / 过滤同一处兜底）；② **不碰 `updated_at`** —— 契约 §2.12 第 4 条：
    /// 移动不属于「编辑正文」，不构成一次内容更新。
    @discardableResult
    public func move(noteIDs: [UUID], toNotebook notebookUid: String) throws -> Int {
        guard !noteIDs.isEmpty else { return 0 }
        let target = try notebookDirectory().resolvedNotebookUid(notebookUid)
        let placeholders = Array(repeating: "?", count: noteIDs.count).joined(separator: ", ")
        var bindings: [SQLiteValue] = [.text(target)]
        bindings.append(contentsOf: noteIDs.map { SQLiteValue.text($0.uuidString) })
        try connection.execute(
            "UPDATE note SET notebook_uid = ? WHERE uuid IN (\(placeholders))",
            bindings
        )
        return noteIDs.count
    }

    /// **一次性归属迁移 + 幂等补缺**（队列 `L-97` 第二片的「旧数据迁移」那一半）。
    ///
    /// 三件事，全在一个事务里：① 没有默认架 ⇒ 建一个；② 没有默认笔记本 ⇒ 建一个（挂在默认架上）；
    /// ③ 缺归属（`NULL` / 空串 / **认不出的 uid**）的笔记一律落默认笔记本。
    ///
    /// 名字由**调用方给**（Core 不许写死文案 —— 默认容器的名字是要落库、要显示给用户的**数据**）。
    /// 幂等：第二次调用时三条都不匹配任何行 ⇒ 库一个字节都不变（单测按 `uid` 与条数逐项对账）。
    @discardableResult
    public func ensureDefaultContainers(
        shelfName: String,
        notebookName: String,
        now: Date = Date()
    ) throws -> NotebookDirectory {
        try connection.transaction {
            var directory = try notebookDirectory()
            if directory.defaultShelf == nil {
                try upsert(Shelf(name: shelfName, sortOrder: directory.shelves.count, createdAt: now, isDefault: true))
                directory = try notebookDirectory()
            }
            if directory.defaultNotebook == nil {
                let shelfUid = directory.defaultShelf!.uid
                try upsert(
                    Notebook(
                        shelfUid: shelfUid,
                        name: notebookName,
                        sortOrder: directory.notebooks(inShelf: shelfUid).count,
                        createdAt: now,
                        isDefault: true
                    )
                )
                directory = try notebookDirectory()
            }
            let defaultNotebookUid = directory.defaultNotebook!.uid
            try connection.execute(
                """
                UPDATE note SET notebook_uid = ?
                WHERE notebook_uid IS NULL OR notebook_uid = ''
                   OR notebook_uid NOT IN (SELECT uid FROM notebook);
                """,
                [.text(defaultNotebookUid)]
            )
        }
        return try notebookDirectory()
    }

    // MARK: - 快照备份

    /// 生成时间戳命名的快照文件名（`notes-20260927T143000.sqlite3`）—— 不覆盖上一次的备份。
    public static func snapshotFileName(at date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> String {
        var components = calendar.dateComponents(in: TimeZone(secondsFromGMT: 0) ?? .gmt, from: date)
        components.calendar = calendar
        let stamp = String(
            format: "%04d%02d%02dT%02d%02d%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0,
            components.hour ?? 0,
            components.minute ?? 0,
            components.second ?? 0
        )
        return "notes-\(stamp).sqlite3"
    }

    /// **快照备份**（`FR-PLUG-08`：备份口径 = 快照，不是同步活跃库文件）。
    ///
    /// 为什么必须是 `VACUUM INTO` 而不是"拷一份库文件"：WAL 模式下已提交的数据可能还只在 `-wal` 里，
    /// 裸拷 `notes.sqlite3` 会拿到**缺最后若干事务**的一份；而云同步盘在文件写到一半时抓到的更是半份。
    /// `VACUUM INTO` 由 SQLite 自己产出一份**事务一致、已压缩、单文件**的副本。
    ///
    /// 三步都是硬要求：① 先 `wal_checkpoint(TRUNCATE)`（把 WAL 并回主库，快照读的就是全部已提交数据）；
    /// ② 写到 `.partial` 再改名（**中途失败不留半个"备份"** —— 比没有备份更危险的是以为有）；
    /// ③ 写完**读回来核对**（行数 + `integrity_check`），核对不过就当没成功。
    @discardableResult
    public func snapshot(to url: URL, fileManager: FileManager = .default) throws -> NoteSnapshot {
        guard !fileManager.fileExists(atPath: url.path) else {
            throw NoteStorageFailure.snapshotTargetExists(url.path)
        }
        try connection.setPragma("wal_checkpoint(TRUNCATE)")

        let partial = url.appendingPathExtension("partial")
        if fileManager.fileExists(atPath: partial.path) {
            // `.partial` 是我们自己的中间件（上次失败留下的），删掉不涉及用户数据。
            try? fileManager.removeItem(at: partial)
        }
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        // `VACUUM INTO` 的目标路径**不能用参数绑定**（不是普通表达式位置），所以只能是字面量；
        // 于是这里的转义是安全边界：单引号翻倍，路径里的 `'` 不会截断语句。
        let literal = partial.path.replacingOccurrences(of: "'", with: "''")
        try connection.execute("VACUUM INTO '\(literal)'")

        // 读回来核对：备份没人验过就等于没有备份。
        let expectedCount = try noteCount()
        let restored = try NoteDatabase(path: partial.path)
        let restoredCount = try restored.noteCount()
        let integrity = try restored.integrityCheck()
        let restoredVersion = restored.userVersion
        try restored.close()
        guard restoredCount == expectedCount, integrity == "ok" else {
            try? fileManager.removeItem(at: partial)
            throw NoteStorageFailure.snapshotMismatch(
                "expected \(expectedCount) note(s) and integrity ok, got \(restoredCount) and \(integrity)"
            )
        }

        try fileManager.moveItem(at: partial, to: url)
        let size = (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        return NoteSnapshot(
            url: url,
            byteCount: size,
            noteCount: restoredCount,
            schemaVersion: restoredVersion,
            integrity: integrity
        )
    }

    // MARK: - 内部

    private func requireRowID(of id: UUID) throws -> Int64 {
        guard let rowID = try connection.scalarInt("SELECT id FROM note WHERE uuid = ?", [.text(id.uuidString)]) else {
            // 调用方自己的前置条件被破坏（先写后取、或删了还在用）：这是程序错误，用断言式的失败说清楚。
            throw SQLiteFailure(
                code: SQLiteResultCode.error,
                message: "no note row for uuid \(id.uuidString)",
                operation: .step,
                sql: "SELECT id FROM note WHERE uuid = ?"
            )
        }
        return rowID
    }

    private func notes(from sql: String, _ bindings: [SQLiteValue] = []) throws -> [Note] {
        try materialize(try connection.query(sql, bindings))
    }

    /// 行 → `Note`（**一行的所有列都在这里被读一次**；读不认识的值时抛错，不降级）。
    ///
    /// 标签单独一句查（`IN` 列表按 rowid 批量取），避免每行一条 `SELECT` 的 N+1。
    private func materialize(_ rows: [SQLiteRow]) throws -> [Note] {
        guard !rows.isEmpty else { return [] }
        let rowIDs = rows.compactMap { $0.int("id") }
        var tagsByRow: [Int64: [String]] = [:]
        if !rowIDs.isEmpty {
            let placeholders = Array(repeating: "?", count: rowIDs.count).joined(separator: ", ")
            let tagRows = try connection.query(
                "SELECT note_id, tag FROM note_tag WHERE note_id IN (\(placeholders)) ORDER BY tag ASC",
                rowIDs.map { SQLiteValue.integer($0) }
            )
            for row in tagRows {
                guard let noteID = row.int("note_id") else { continue }
                tagsByRow[noteID, default: []].append(row.text("tag") ?? "")
            }
        }
        return try rows.map { row in
            guard let uuidText = row.text("uuid"), let uuid = UUID(uuidString: uuidText) else {
                throw SQLiteFailure(
                    code: SQLiteResultCode.mismatch,
                    message: "note row has no usable uuid",
                    operation: .step
                )
            }
            let kindText = row.text("source_kind") ?? ""
            guard let rawKind = NoteSource.Kind(rawValue: kindText) else {
                throw NoteStorageFailure.unknownSourceKind(kindText)
            }
            return Note(
                id: uuid,
                title: row.text("title") ?? "",
                body: row.text("body") ?? "",
                tags: tagsByRow[row.int("id") ?? 0] ?? [],
                source: NoteSource(
                    kind: rawKind,
                    connectionName: row.text("source_connection_name"),
                    fingerprint: row.text("source_fingerprint"),
                    capturedAt: Date(timeIntervalSince1970: row["source_captured_at"].doubleValue ?? 0)
                ),
                createdAt: Date(timeIntervalSince1970: row["created_at"].doubleValue ?? 0),
                updatedAt: Date(timeIntervalSince1970: row["updated_at"].doubleValue ?? 0),
                containsRowData: row["contains_row_data"].intValue == 1
            )
        }
    }
}

/// 时间线上这类动作的 `kind` 取值（写成常量而不是散在调用点的字面量 —— 检索与展示都要按它筛）。
public enum NoteTimelineKind {
    public static let upsert = "upsert"
    public static let delete = "delete"
    public static let attachment = "attachment"
    public static let migrate = "migrate"
}
