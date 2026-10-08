import Foundation

// 队列 `HIST-1`（契约 `DR-02` 由「内存态」改判为**持久化** · SRS v3.327）：
// **查询历史落盘的唯一入口**。
//
// 为什么要有这一层（而不是让 `AppState` / 界面各自拿 `NoteDatabase`）：
//   ① **单一写入口**：写入 / 清空 / 单条删 / 启动加载四件事都从这里走。库表在 `NoteSchemaV7`
//      （与笔记同库同连接），而**只有这一层**拿得到那条连接 —— 第二条写路（各自 `open()` +
//      各自拼 SQL）不是「不许写」，是**写不出来**（连接是 `NoteDatabase` 的私有成员，
//      与 `NoteLibrary` 同一条纪律）。
//   ② **上限只在这一处裁**：`DR-02` 的「500 条或 90 天（先到者为准）」收在 `prune(_:now:)`
//      一处，读与写共用同一个数 —— 不会出现「界面以为上限 500、库里按 300 裁」这类两处各说各话。
//   ③ **本地 only**：只读写本机 `notes.sqlite3`，**零网络出口**（与 `check-notes-offline.py`
//      同族的承诺；判据直接 grep 本文件不许出现任何网络出入字样）。
//   ④ **与 `SQLArchive` 分工不覆盖**：归档 = 用户**主动收藏**、长期保留（磁盘上的 `*.sql`）；
//      这里 = 会话历史、有上限、可清空。两者互不读写对方的存储（`DR-02` 明文）。
//
// 线程口径：`NoteDatabase` 的连接自身串行化，**语义并发由本 actor 负责**（与 `NoteLibrary` /
// `SQLArchiveWriter` 同一条）。每次调用**现开连接**（与 `NoteLibrary.open()` 同一做法）：
// 历史的写入量与一次查询相比很小，换来的是一条更短、能被单测逐条钉住的路径，也没有常驻句柄要管。
public actor QueryHistoryStore {

    /// 条数上限（`DR-02` 明文：**500 条**）。
    public static let maxEntries = 500

    /// 时间上限（`DR-02` 明文：**90 天**）。与条数上限**先到者为准**。
    public static let maxAge: TimeInterval = 90 * 24 * 60 * 60

    private let databaseURL: URL

    public init(databaseURL: URL) {
        self.databaseURL = databaseURL
    }

    /// 默认位置 = 笔记库那个文件（`notes.sqlite3`）—— 历史与笔记**同库同连接**（schema v7）。
    public static func defaultStore(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> QueryHistoryStore {
        QueryHistoryStore(databaseURL: NoteDatabase.defaultFileURL(environment: environment))
    }

    // MARK: - 门面（load / append / clear / delete）

    /// 启动加载：读回全部历史（**执行时间倒序**），顺手按上限裁一次 —— 上一次运行留下的
    /// 超大 / 过期历史不该等到「再执行一条」才被裁掉。库还不存在 ⇒ 如实返回空表
    /// （**不顺手建库**，与 `NoteLibrary.load()` 同一条纪律）。
    ///
    /// `now` 可注入：判据要能造一条「90 天前」的行再自证它被裁掉，用真实时钟就测不稳。
    public func load(now: Date = Date()) throws -> [QueryHistory] {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return [] }
        let database = try open()
        try prune(database, now: now)
        return try database.queryHistory()
    }

    /// 追加一次执行（**写 = 按 id 覆盖**：连续重复执行同一条 SQL 时调用方复用最新那一条的 id，
    /// 于是「只刷新最新一条」不另开更新路）。返回**裁剪后**的完整历史（倒序）——
    /// 调用方直接拿它刷新内存列表即可，不必自己再裁一遍（上限只有那一处）。
    @discardableResult
    public func append(_ entry: QueryHistory, now: Date = Date()) throws -> [QueryHistory] {
        let database = try open()
        try database.upsertQueryHistory(entry)
        try prune(database, now: now)
        return try database.queryHistory()
    }

    /// 清空（用户点的「清空历史」）。库不存在 ⇒ 什么都没发生（不顺手建库）。
    public func clear() throws {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return }
        _ = try open().clearQueryHistory()
    }

    /// 删一条（用户点的「删除这一条」）。库不存在 / 认不出的 id ⇒ 什么都没发生（删是幂等的）。
    public func delete(id: UUID) throws {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return }
        try open().deleteQueryHistory(id: id)
    }

    // MARK: - 私有

    /// **唯一一处裁剪**（`DR-02`：500 条或 90 天，先到者为准）。
    private func prune(_ database: NoteDatabase, now: Date) throws {
        try database.pruneQueryHistory(keepingMax: Self.maxEntries, maxAge: Self.maxAge, now: now)
    }

    private func open() throws -> NoteDatabase {
        try NoteDatabase(path: databaseURL.path)
    }
}
