import Foundation

// `FR-PLUG-08` 第 3 批：**笔记库的唯一入口**。
//
// 为什么要有这一层（而不是让界面 / CLI 直接拿 `NoteDatabase`）：
//   ① 引擎换了、调用点不该跟着换 —— 界面与 CLI 只用「读一份笔记列表 / 存一条 / 删一条 / 搜一下」四件事，
//      把它们收在一个 actor 里，SQLite 的连接、schema 升级、事务全在这一层之下；
//   ② **一处决定「缺库」与「库坏了」**：`loadOutcome()` 与 `NoteStore.loadOutcome()` **同名同语义**
//      （`.absent` / `.loaded` / `.unreadable`），所以调用点的 `switch` 一字不改 —— 换引擎不该顺带改界面行为；
//   ③ **一次写 = 一个事务**：`NoteDatabase.upsert` 已经把「本体 + 标签 + 时间线」放进一个事务，
//      这一层不再拆开做第二次写（半条笔记是最难查的一类不一致）。
//
// 与旧引擎（`NoteStore`，JSON 文件）的关系：**旧引擎只作为迁移的输入留档**
// （`NoteLibraryMigration` 读它、搬完改名 `notes.json.migrated`），界面与 CLI 不再碰它 ——
// 这一条由 `Tests/NoteLibraryTests.swift` 里的源树判据机械守着（App/ 与 CLI/ 里出现
// `NoteStore.defaultStore()` / `NoteStore(fileURL:` 即报红）。
//
// 线程口径：`NoteDatabase` 的连接自身串行化，语义并发由本 actor 负责（与旧引擎同一条纪律）。
public actor NoteLibrary {

    /// 库文件名（`notes.sqlite3`）。**与旧格式不同名** —— 迁移靠「目标不在」判定要不要搬。
    public static var fileName: String { NoteDatabase.fileName }

    private let databaseURL: URL

    public init(databaseURL: URL) {
        self.databaseURL = databaseURL
    }

    // MARK: - 位置

    /// 笔记的数据家（与 `FR-PLUG-04` 之后的位置**同一个目录**，只是文件名从 `notes.json` 变成 `notes.sqlite3`）。
    public static func defaultDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        NoteDatabase.defaultDirectory(environment: environment)
    }

    public static func defaultDatabaseURL(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        NoteDatabase.defaultFileURL(environment: environment)
    }

    public static func defaultLibrary(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> NoteLibrary {
        NoteLibrary(databaseURL: defaultDatabaseURL(environment: environment))
    }

    /// 库文件路径（**只读的一条**：`notes` 出口用它把位置打给脚本）。
    public nonisolated var fileURL: URL { databaseURL }

    // MARK: - 读

    /// 与 `NoteStore.LoadOutcome` **同形同义**：`.absent` = 还没有库（第一次用），
    /// `.unreadable` = 库在但读不出来（**如实报，不回退成「空库」糊过去**）。
    public enum LoadOutcome: Equatable, Sendable {
        case absent
        case loaded([Note])
        case unreadable(failure: String)
    }

    public func loadOutcome() -> LoadOutcome {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return .absent }
        do {
            return .loaded(try open().notes())
        } catch {
            return .unreadable(failure: String(describing: error))
        }
    }

    public func load() throws -> [Note] {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return [] }
        return try open().notes()
    }

    public func search(_ query: String, limit: Int = 200) throws -> NoteDatabase.SearchResult {
        try open().search(query, limit: limit)
    }

    // MARK: - 写

    /// 保存草稿（新建或按 id 覆盖），返回落库后的笔记。
    ///
    /// **与旧引擎逐条同义**（换引擎不该改语义）：编辑已有笔记时**保留它的 `createdAt`**
    /// （创建时间是事实，不该因为改了几个字就被改写成现在）；`updatedAt` 一律取 `now`。
    /// 新增的一档是 `NoteDatabase.upsert` 自带的**时间线留痕**（每次写记一条 `upsert`）。
    @discardableResult
    public func upsert(_ draft: NoteDraft, id: UUID? = nil, now: Date = Date()) throws -> Note {
        let database = try open()
        // 查一次旧行只为了拿 `createdAt`：拿不到（新笔记 / 库是空的）就用 `now`。
        let createdAt = (try id.flatMap { try database.note(id: $0) })?.createdAt ?? now
        var note = draft.makeNote(now: createdAt)
        if let id { note.id = id }
        note.updatedAt = now
        _ = try database.upsert(note)
        return note
    }

    public func delete(id: UUID) throws {
        let database = try open()
        // 库还不存在时删一条 = 什么都没发生（不要顺手建一个空库出来）。
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return }
        try database.delete(id: id)
    }

    // MARK: - 快照 / 维护

    /// 备份 = **单文件快照**（`VACUUM INTO`），不是把活跃的库文件直接交给云同步。
    public func snapshot(to url: URL, fileManager: FileManager = .default) throws -> NoteSnapshot {
        try open().snapshot(to: url, fileManager: fileManager)
    }

    /// 库里的 schema 版本（`PRAGMA user_version`）—— 证据脚本与单测拿它自证「开的真是这个库」。
    public func schemaVersion() throws -> Int32 { try open().userVersion }

    /// 表清单（与 `NoteSchemaV1.tables` 对账）。
    public func tableNames() throws -> [String] { try open().tableNames() }

    // MARK: - 私有

    /// 打开（必要时新建）并把 schema 升到本版。**打开即幂等**：已经是最新版的库不会被动。
    /// 比代码新的库由 `NoteDatabase` 抛 `unsupportedSchemaVersion` —— 这里不吞，让 `loadOutcome()` 如实报出来。
    private func open() throws -> NoteDatabase {
        try NoteDatabase(path: databaseURL.path)
    }
}
