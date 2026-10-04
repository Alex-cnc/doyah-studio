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

    // MARK: - 两层归属（队列 L-97 第二片）

    /// 库里的两层结构（架 + 笔记本）。库还没建时如实返回**空**（不是「默认容器」——
    /// 默认容器是迁移写下去的数据，读的时候不该凭空造一个出来）。
    public func notebookDirectory() throws -> NotebookDirectory {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            return NotebookDirectory(shelves: [], notebooks: [])
        }
        return try open().notebookDirectory()
    }

    /// 归属对（`uuid` ↔ `notebook_uid`）。
    public func placements() throws -> [NotebookPlacement] {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return [] }
        return try open().placements()
    }

    /// **打开笔记时的一次性归属迁移**（幂等）：确保默认架 / 默认笔记本在，
    /// 并把缺归属的存量笔记落进默认笔记本。名字由调用方从语言表给（Core 不写死文案）。
    @discardableResult
    public func ensureOwnership(
        shelfName: String,
        notebookName: String,
        now: Date = Date()
    ) throws -> NotebookDirectory {
        try open().ensureDefaultContainers(shelfName: shelfName, notebookName: notebookName, now: now)
    }

    /// 把若干条笔记移到目标笔记本（不刷新 `updatedAt`，见 `NoteDatabase.move`）。
    @discardableResult
    public func move(noteIDs: [UUID], toNotebook notebookUid: String) throws -> Int {
        try open().move(noteIDs: noteIDs, toNotebook: notebookUid)
    }

    /// 算「删这个笔记本」的处置计划（**不写库**）：界面拿它写确认框
    /// （契约 §2.12 第 3 条：非空时写明「将影响多少笔记本与多少条笔记」）。
    /// 默认笔记本 / 认不出的 uid ⇒ `nil`（删不掉，调用方不必自己判）。
    public func removalPlan(
        forNotebook notebookUid: String,
        policy: ContainerRemovalPolicy = .default
    ) throws -> ContainerRemovalPlan? {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return nil }
        return try open().removalPlan(forNotebook: notebookUid, policy: policy)
    }

    /// 算「删这个架」的处置计划（同一条）。
    public func removalPlan(
        forShelf shelfUid: String,
        policy: ContainerRemovalPolicy = .default
    ) throws -> ContainerRemovalPlan? {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return nil }
        return try open().removalPlan(forShelf: shelfUid, policy: policy)
    }

    /// **删一个笔记本**（默认档 = 里面的笔记移到默认笔记本），返回落库后的处置结果。
    /// 默认笔记本 / 认不出的 uid ⇒ `nil`（没有可删的东西，库一个字节不动）。
    ///
    /// 计划在**同一次调用里重算**再落库：界面确认框上的数字与真正动手之间隔着一次点击，
    /// 中间库可能已经变了 —— 按过期的影响面删除，删掉的东西就不是用户确认过的那个了。
    @discardableResult
    public func removeNotebook(uid: String, policy: ContainerRemovalPolicy = .default) throws -> ContainerRemovalPlan? {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return nil }
        let database = try open()
        guard let plan = try database.removalPlan(forNotebook: uid, policy: policy) else { return nil }
        return try database.applyRemovalPlan(plan)
    }

    /// **删一个笔记本架**（默认档 = 架里的笔记本整架移到默认架）。
    @discardableResult
    public func removeShelf(uid: String, policy: ContainerRemovalPolicy = .default) throws -> ContainerRemovalPlan? {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return nil }
        let database = try open()
        guard let plan = try database.removalPlan(forShelf: uid, policy: policy) else { return nil }
        return try database.applyRemovalPlan(plan)
    }

    // MARK: - 容器编辑（队列 L-97 界面半第四片：新建 / 重命名 / 排序）

    /// **新建一个笔记本**（落进某个架）。排序位**在这一次调用里现算**（该架内现有条数）——
    /// 界面那侧的数字是几次点击之前算的，库里可能已经又多了两个，按旧数写下去就会重号。
    /// 认不出的架 ⇒ `nil`（库一个字节不动）：**不兜底到默认架** ——「新建到一个已经不存在的架里」
    /// 与「新建到默认架里」是两件事，前者该让调用方知道目标没了（那一侧会重新读库把树刷新）。
    @discardableResult
    public func createNotebook(inShelf shelfUid: String, name: String, now: Date = Date()) throws -> Notebook? {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return nil }
        let database = try open()
        let directory = try database.notebookDirectory()
        guard directory.shelf(uid: shelfUid) != nil else { return nil }
        return try database.createNotebook(
            shelfUid: shelfUid,
            name: name,
            sortOrder: directory.nextSortOrder(inShelf: shelfUid),
            now: now
        )
    }

    /// **把一个笔记本挪到另一个架**（跨架移动 —— 队列 `L-97` 落法 ① 的第四格）。
    /// 认不出的笔记本 / 认不出的目标架 / 已经在该架 ⇒ `nil`（库一个字节不动）；判定在
    /// `NoteDatabase.move(notebookUid:toShelf:)` 一处（与 `NotebookShelfMovePrompt.moveDestination` 同口径）。
    @discardableResult
    public func moveNotebook(uid: String, toShelf shelfUid: String) throws -> Notebook? {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return nil }
        return try open().move(notebookUid: uid, toShelf: shelfUid)
    }

    /// **改一个架的名字**（默认架也可改名 —— 契约 §2.12 第 2 条：不可删、可改名）。
    /// 认不出的 uid ⇒ `nil`。
    @discardableResult
    public func renameShelf(uid: String, name: String) throws -> Shelf? {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return nil }
        return try open().rename(shelfUid: uid, name: name)
    }

    /// **改一个笔记本的名字**（同一条）。
    @discardableResult
    public func renameNotebook(uid: String, name: String) throws -> Notebook? {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return nil }
        return try open().rename(notebookUid: uid, name: name)
    }

    /// **挪一步**（相邻上移 / 下移）：排序位按可见次序**整层重排**（规则在 `ContainerReorder`）。
    /// 返回**有没有真的写库**：已在最前 / 已在最后 / uid 认不出 ⇒ `false`（视图那一侧本来就不给点，
    /// 这里是第二道 —— 与 `moveNotes` 同族）。
    @discardableResult
    public func reorder(
        kind: NotebookContainerKind,
        containerUid: String,
        direction: ContainerReorderDirection
    ) throws -> Bool {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return false }
        let database = try open()
        guard let plan = ContainerReorder.plan(
            kind: kind,
            containerUid: containerUid,
            direction: direction,
            directory: try database.notebookDirectory()
        ) else { return false }
        try database.applySortOrders(plan, kind: kind)
        return true
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
        // 查一次旧行只为了拿 `createdAt` 与**收藏**：拿不到（新笔记 / 库是空的）就用 `now` / `false`。
        // 为什么收藏要在这里读回来：`upsert` 的 `ON CONFLICT` 段刻意不碰 `favorite`（与 `notebook_uid`
        // 同一条教训 —— 改几个字保存不该静默取消收藏），所以库里那份才是事实；
        // 返回的 `Note` 要如实反映它，否则调用方拿到的是「看起来没收藏」的假象。
        let existing = try id.flatMap { try database.note(id: $0) }
        var note = draft.makeNote(now: existing?.createdAt ?? now)
        if let id { note.id = id }
        note.isFavorite = existing?.isFavorite ?? false
        note.updatedAt = now
        _ = try database.upsert(note)
        return note
    }

    /// **收藏 / 取消收藏一条笔记**（队列 `L-184` 第三片）：返回**真的改了几行**。
    /// 认不出的 id ⇒ `0` —— 调用方按这个数如实处置，不要假装改成了。
    @discardableResult
    public func setFavorite(id: UUID, _ favorite: Bool) throws -> Int {
        try open().setFavorite(favorite, id: id)
    }

    /// 一条笔记是不是收藏（`nil` = 库里没有这条笔记）。
    public func isFavorite(id: UUID) throws -> Bool? {
        try open().isFavorite(id: id)
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
