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
    public func removeNotebook(
        uid: String,
        policy: ContainerRemovalPolicy = .default,
        at: Date = Date()
    ) throws -> ContainerRemovalPlan? {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return nil }
        let database = try open()
        guard let plan = try database.removalPlan(forNotebook: uid, policy: policy) else { return nil }
        return try database.applyRemovalPlan(plan, at: at)
    }

    /// **删一个笔记本架**（默认档 = 架里的笔记本整架移到默认架）。
    @discardableResult
    public func removeShelf(
        uid: String,
        policy: ContainerRemovalPolicy = .default,
        at: Date = Date()
    ) throws -> ContainerRemovalPlan? {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return nil }
        let database = try open()
        guard let plan = try database.removalPlan(forShelf: uid, policy: policy) else { return nil }
        return try database.applyRemovalPlan(plan, at: at)
    }

    // MARK: - 容器编辑（队列 L-97 界面半第四片：新建 / 重命名 / 排序）

    /// **新建一个笔记本**（落进某个架）。排序位**在这一次调用里现算**（该架内现有条数）——
    /// 界面那侧的数字是几次点击之前算的，库里可能已经又多了两个，按旧数写下去就会重号。
    /// 认不出的架 ⇒ `nil`（库一个字节不动）：**不兜底到默认架** ——「新建到一个已经不存在的架里」
    /// 与「新建到默认架里」是两件事，前者该让调用方知道目标没了（那一侧会重新读库把树刷新）。
    @discardableResult
    /// `uid` 可指定：**撤销「删了一个笔记本」**要把它按原 uid 建回来（否则恢复出来的笔记
    /// 会落默认笔记本，而契约 §15.9 要的是「回原位」）。常规新建走默认（现造一个）。
    public func createNotebook(
        inShelf shelfUid: String,
        name: String,
        uid: String = UUID().uuidString,
        now: Date = Date()
    ) throws -> Notebook? {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return nil }
        let database = try open()
        let directory = try database.notebookDirectory()
        guard directory.shelf(uid: shelfUid) != nil else { return nil }
        return try database.createNotebook(
            shelfUid: shelfUid,
            name: name,
            sortOrder: directory.nextSortOrder(inShelf: shelfUid),
            uid: uid,
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
        let note = try preparedNote(draft, id: id, now: now, database: database)
        _ = try database.upsert(note)
        return note
    }

    /// 把草稿拼成要落库的那一条（保留 `createdAt` 与组织状态 / 私密挡位）。
    ///
    /// 抽出来是为了让 `upsert`（单独写）与 `save`（三块一个事务）**用同一份拼装**：
    /// 两处各写一遍，改一处忘另一处就是「同一份草稿在两条路上落出不同结果」。
    private func preparedNote(
        _ draft: NoteDraft,
        id: UUID?,
        now: Date,
        database: NoteDatabase
    ) throws -> Note {
        // 查一次旧行只为了拿 `createdAt` 与**组织状态（收藏 / 置顶）**：拿不到（新笔记 / 库是空的）就用 `now` / `false`。
        // 为什么这两个要在这里读回来：`upsert` 的 `ON CONFLICT` 段刻意不碰 `favorite` / `pinned`（与
        // `notebook_uid` 同一条教训 —— 改几个字保存不该静默取消收藏 / 取消置顶），所以库里那份才是事实；
        // 返回的 `Note` 要如实反映它，否则调用方拿到的是「看起来没收藏 / 没置顶」的假象。
        let existing = try id.flatMap { try database.note(id: $0) }
        var note = draft.makeNote(now: existing?.createdAt ?? now)
        if let id { note.id = id }
        note.isFavorite = existing?.isFavorite ?? false
        note.isPinned = existing?.isPinned ?? false
        // 私密挡位同理：`upsert` 的 `ON CONFLICT` 段不碰 `is_private`（改几个字保存不许静默解除私密），
        // 所以库里那份才是事实；返回的 `Note` 要如实反映它，否则调用方拿到的是「看起来不私密」的假象。
        note.isPrivate = existing?.isPrivate ?? note.isPrivate
        note.updatedAt = now
        return note
    }

    /// **一次保存 = 本体 + 正文权威源 + 历史版本**（`FR-NTS-NOTE-VERSION-001`）。
    ///
    /// 为什么要有这一条（而不是让调用方连着调 `upsert` + `setNoteSpans`）：版本要记的是
    /// **这次保存落下去的那一份完整内容**，而 `upsert`（标题 / 标签 / 正文投影）与
    /// `setNoteSpans`（spans + 正文）是两次写 —— 中间那一瞬的库里状态是「新标题 + 旧 spans」。
    /// 把三件事收进一个 actor 方法，版本一定在两次写**都完成之后**才记，读出来不会半新半旧。
    ///
    /// `spans` 为 `nil` 时**不写正文列**（只有标题 / 标签变了的保存）：与 `setNoteSpans`
    /// 「只由有权威源的那条路写正文」同一条纪律，不拿投影覆盖别人的权威源。
    @discardableResult
    public func save(
        _ draft: NoteDraft,
        spans: String? = nil,
        id: UUID? = nil,
        now: Date = Date(),
        reason: NoteVersionReason = .save,
        retention: NoteVersionRetention = .default
    ) throws -> Note {
        // **一个连接、一个事务**：三块（本体 / 正文权威源 / 历史版本）要么全在、要么全不在。
        // 改前是 `upsert()` + `open().setNoteSpans()` + `open().recordVersion()` —— 三次提交、
        // 三条连接：进程在中间被杀会留下「笔记在、版本没有」（`NoteCrashSafetyTests` 实测撞到）。
        let database = try open()
        let note = try preparedNote(draft, id: id, now: now, database: database)
        try database.save(
            note,
            spans: spans,
            body: spans.map { noteBody(fromSpans: $0, fallback: draft.body) } ?? draft.body,
            versionAt: now,
            reason: reason,
            retention: retention
        )
        // 返回**库里读回来的那一份**（正文 / spans / 版本号都以库为准，不用内存里那份猜）。
        return try database.note(id: note.id) ?? note
    }

    /// 正文投影（`spans` 编不出来时退回调用方给的正文）：与 `NoteBody` 的编解码面同一份，
    /// 不在这里另起一套解析。
    private func noteBody(fromSpans spans: String, fallback: String) -> String {
        guard let data = spans.data(using: .utf8),
              let body = try? JSONDecoder().decode(NoteBody.self, from: data) else { return fallback }
        return body.body
    }

    // MARK: - 导出与迁移（`FR-NTS-NOTE-EXPORT-001`）
    //
    // 三种产物都从**同一次** `archiveEntries()` 取数（契约 §15.3「三形态同源」）——
    // 这里不各写一遍「把哪些笔记拿出来」：那会立刻出现「Markdown 导了 12 条、备份包 11 条」。

    /// 备份包（结构化那一份；`spans` 在里面，所以**无损**）。
    ///
    /// 库还不在盘上 ⇒ 空包（**不建库**：「导出是副本」不许因为导出这个动作在盘上多出一个文件）。
    public func archivePackage(at moment: Date = Date()) throws -> NoteArchivePackage {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            return NoteArchivePackage(exportedAt: moment, notes: [])
        }
        return NoteArchivePackage(exportedAt: moment, notes: try open().archiveEntries())
    }

    /// 备份包的落盘字节（键排序 ⇒ 同一份库两次导出逐字节相同）。
    public func archiveData(at moment: Date = Date()) throws -> Data {
        try NoteArchive.encode(try archivePackage(at: moment))
    }

    /// Markdown / 纯文本产物（有损的那两种）。条数与备份包恒等。
    public func archiveText(_ kind: NoteArchiveFormat.Kind, language: AppLanguage) throws -> String {
        let entries = try archivePackage().notes
        switch kind {
        case .markdown: return NoteArchive.markdown(entries, language: language)
        case .plainText: return NoteArchive.plainText(entries, language: language)
        case .package: return String(decoding: try NoteArchive.encode(NoteArchivePackage(exportedAt: Date(), notes: entries)), as: UTF8.self)
        }
    }

    /// 导入自己导出的包：先解包（格式 / 版本这两道在前），再整批写回。
    public func importArchive(_ data: Data) throws -> NoteArchiveImportReport {
        let package = try NoteArchive.decode(data)
        return try open().restoreArchive(package.notes)
    }

    // MARK: - 历史版本（`FR-NTS-NOTE-VERSION-001`）

    /// 一条笔记的历史版本（**最新在前**；每版带时间与摘要）。
    public func versions(of id: UUID, limit: Int = 200) throws -> [NoteVersionEntry] {
        try open().versions(of: id, limit: limit)
    }

    /// 某一版。
    public func version(of id: UUID, number: Int) throws -> NoteVersionEntry? {
        try open().version(of: id, number: number)
    }

    /// 一篇笔记留了几版（界面说「已留 N 版」、判据读数用）。
    public func versionCount(of id: UUID) throws -> Int {
        try open().versionCount(of: id)
    }

    /// **回滚到某一版**：把那一版的标题 / 正文 / 标签 / spans 重新落库。
    ///
    /// 「回滚本身也生成新版本」由**形状**保证 —— 回滚走的就是 `save`，于是它自己会记一版
    /// （`reason == .rollback`），不需要在回滚路径上多写一句「别忘了记版本」。
    /// 认不出的版本号 ⇒ `nil`（调用方按「没有这一版」如实处置）。
    @discardableResult
    public func rollback(
        id: UUID,
        to version: Int,
        now: Date = Date(),
        retention: NoteVersionRetention = .default
    ) throws -> Note? {
        guard let entry = try open().version(of: id, number: version) else { return nil }
        let database = try open()
        let existing = try database.note(id: id)
        let draft = NoteDraft(
            title: entry.title,
            body: entry.body,
            tags: entry.tags,
            source: existing?.source ?? NoteSource(),
            isPrivate: existing?.isPrivate ?? false
        )
        return try save(draft, spans: entry.spans, id: id, now: now, reason: .rollback, retention: retention)
    }

    // MARK: - 附件（`FR-NTS-NOTE-ATTACH-001`）

    /// 附件根目录：**与库文件同一个数据家**（`<库所在目录>/attachments`）。
    ///
    /// 为什么不走 `NoteAttachmentStore(environment:)` 的默认根：库可以指到临时目录（判据 / CLI），
    /// 附件必须跟着**这一份库**走 —— 否则判据里的附件落到真用户数据家去，还会互相串。
    public nonisolated var attachmentRoot: URL {
        databaseURL.deletingLastPathComponent().appendingPathComponent("attachments", isDirectory: true)
    }

    /// 一条笔记的附件索引（库不在 / 没有这一条 ⇒ 空表，**不顺手建库** —— 与 `reminders()` 同一条纪律）。
    ///
    /// 「没有这一条」也返回空表而不是抛：附件清单的唯一用处是「界面上画什么」，
    /// 一条已经不在的笔记没有附件可画（`requireRowID` 那类程序错误仍会抛，这里只挡「查无此条」）。
    public func attachments(of id: UUID) throws -> [NoteAttachment] {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return [] }
        let database = try open()
        guard try database.note(id: id) != nil else { return [] }
        return try database.attachments(of: id)
    }

    /// **收一份文件进来并挂到这条笔记上**：先落盘（字节拷贝），再写索引行。
    ///
    /// 顺序不能反：先写索引再拷文件，拷贝失败就会留下一条指向不存在文件的索引（判据② 的「文件不在了」
    /// 会立刻出现，但那是我们自己造的）。拷贝成功而索引失败 ⇒ **把刚拷的文件删掉**，不留半份。
    ///
    /// - Returns: 索引里的那一条（路径 = 附件家下的绝对路径）。
    public func attach(
        fileAt source: URL,
        to id: UUID,
        now: Date = Date(),
        store: NoteAttachmentStore? = nil
    ) throws -> NoteAttachment {
        let filer = store ?? NoteAttachmentStore(root: attachmentRoot)
        let attachment = try filer.importFile(at: source, noteID: id, now: now)
        do {
            try open().addAttachment(attachment, to: id)
        } catch {
            try? filer.deleteFiles([attachment])
            throw error
        }
        return attachment
    }

    /// 这条笔记上**文件已经不在**的附件（判据②的读数入口）。
    public func missingAttachments(of id: UUID, store: NoteAttachmentStore? = nil) throws -> [NoteAttachment] {
        let filer = store ?? NoteAttachmentStore(root: attachmentRoot)
        return filer.missing(in: try attachments(of: id))
    }

    /// **真的删附件文件**（判据③：只有人另行确认才走这里；索引行由删除笔记那一支处理）。
    @discardableResult
    public func deleteAttachmentFiles(
        _ attachments: [NoteAttachment], store: NoteAttachmentStore? = nil
    ) throws -> Int {
        let filer = store ?? NoteAttachmentStore(root: attachmentRoot)
        return try filer.deleteFiles(attachments)
    }

    /// 删除的收据：**落了几行墓碑 + 这条笔记原本挂着哪些附件**。
    ///
    /// 判据③要的是「删笔记不会静默删掉附件」—— 于是「它有哪些附件」必须在删之前读出来交给调用方，
    /// 由界面把「这些文件还在 `…/attachments/<noteID>/`，要不要一起删」问一次。库在这一层
    /// **一个附件文件都不碰**（墓碑只删索引行，见 `NoteDatabase.tombstone` 注释第 ③ 条）。
    public struct NoteDeletionReceipt: Equatable, Sendable {
        /// `true` = 真的落下了墓碑；`false` = 库还不存在（没有任何东西被删）。
        public var deleted: Bool
        /// 删之前这条笔记挂着的附件（文件仍在盘上）。
        public var attachments: [NoteAttachment]

        public init(deleted: Bool, attachments: [NoteAttachment]) {
            self.deleted = deleted
            self.attachments = attachments
        }
    }

    /// 与 `delete(id:at:)` 同一件事，但**把附件清单带回来**（界面按它问「要不要一起删文件」）。
    public func deleteReturningAttachments(id: UUID, at date: Date) throws -> NoteDeletionReceipt {
        let held = try attachments(of: id)
        let deleted = try delete(id: id, at: date)
        return NoteDeletionReceipt(deleted: deleted, attachments: deleted ? held : [])
    }

    // MARK: - 私密挡位（`FR-NTS-NOTE-PRIVACY-001`）

    /// 私密条目门牌（**无正文 / 无标签**）：界面「私密」那一栏只显示这些。
    public func privateSummaries() throws -> [NoteDatabase.PrivateNoteSummary] {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return [] }
        return try open().privateSummaries()
    }

    /// **标 / 撤私密**。撤私密必须先带 `confirmed: true`（判据③「取消私密需二次确认」）——
    /// 确认动作是界面上的那一次二次确认，这一层只负责「没确认就不给撤」。
    @discardableResult
    public func setPrivate(id: UUID, _ isPrivate: Bool, confirmed: Bool = false) throws -> NotePrivacyChangeOutcome {
        if !isPrivate, NotePrivacy.unprivateRequiresConfirmation, !confirmed {
            return .confirmationRequired
        }
        return .changed(try open().setPrivate(isPrivate, id: id))
    }

    public func isPrivate(id: UUID) throws -> Bool? {
        try open().isPrivate(id: id)
    }

    /// 打开一条**私密**笔记的内容（判据「需二次验证才可查看」）。
    ///
    /// 三条出口分得开：`notPrivate`（走普通读）/ `denied`（验证没过，**内容一个字都不返回**）/
    /// `revealed`（带内容与历史版本）。把「拒绝」与「没有这条」分开，是因为两者的用户处置完全不同。
    public enum RevealOutcome: Equatable, Sendable {
        case revealed(RevealedPrivateNote)
        case denied
        case notFound
        case notPrivate
    }

    /// 判据**「语言是传进来的」**：`reason` 是**必填**、没有默认值 —— 它是系统验证框里显示的那句话，
    /// 要由界面按当前语言给（`L(.notesPrivateUnlockReason)`）。本层若自带一个中文字面量默认值，
    /// 英文界面会弹出中文框，同时本地化棘轮 A 会把这里记成一条新欠账（2026-11-02 实测：101 → 102 文件）。
    public func revealPrivate(
        id: UUID,
        authorizer: NotePrivacyAuthorizing,
        reason: String
    ) async throws -> RevealOutcome {
        let database = try open()
        guard let note = try database.note(id: id) else { return .notFound }
        guard note.isPrivate else { return .notPrivate }
        guard await authorizer.authorize(reason: reason) else { return .denied }
        return .revealed(RevealedPrivateNote(note: note, versions: try database.versions(of: id)))
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

    /// **置顶 / 取消置顶一条笔记**（队列 `L-184` 第四片）：返回**真的改了几行**。
    /// 认不出的 id ⇒ `0` —— 调用方按这个数如实处置，不要假装改成了。
    @discardableResult
    public func setPinned(id: UUID, _ pinned: Bool) throws -> Int {
        try open().setPinned(pinned, id: id)
    }

    /// 一条笔记是不是置顶（`nil` = 库里没有这条笔记）。
    public func isPinned(id: UUID) throws -> Bool? {
        try open().isPinned(id: id)
    }

    // MARK: - 正文权威源 spans（schema v8 · 片 `WY-2a`）

    /// **写一条笔记的正文权威源 `spans`（JSON）+ 它的 `body` 投影** —— 界面侧（编辑器保存）的
    /// 唯一写路。落到 `NoteDatabase.setNoteSpans`，那一处是**全仓唯一**写 `spans` 列的地方
    /// （片 `WY-1a` 立的单一写入口，本片把它接到编辑面上）。
    ///
    /// 为什么这一层要有这条转发（而不是让 App 直接拿 `NoteDatabase`）：`FR-PLUG-08` 的口径是
    /// 「界面与 CLI 只用 `NoteLibrary` 这四件事」—— `NoteDatabase` 的连接与 schema 升级都在这层之下，
    /// 界面伸手进去就等于把「库表长什么样」焊死在编辑器里（见本文件头注释第 ① 条）。
    /// 返回**真的改了几行**：认不出的 id ⇒ `0`（调用方按数如实处置，与 `setFavorite` / `setPinned` 同口径）。
    @discardableResult
    public func setNoteSpans(_ spans: String, body: String, id: UUID) throws -> Int {
        try open().setNoteSpans(spans, body: body, id: id)
    }

    /// 一条笔记的正文权威源（JSON 原样；`nil` = 库里没有这条 **或** 该列还是 `NULL`（v1 存量，未迁移））。
    /// 两种 `nil` 对读的人是同一件事（这条还没有 v2 权威源），与 `NoteDatabase.noteSpans` 同形。
    public func noteSpans(id: UUID) throws -> String? {
        try open().noteSpans(id: id)
    }

    /// **旧正文迁移**（`FR-RT-11` · 片 `WY-2b`）：把 v1 存量笔记的正文（Markdown 文本、`spans` 为
    /// `NULL`）迁成 v2 权威源（span 树 JSON）；**迁移前的全量原文先落盘备份**。
    ///
    /// 判据（`FR-RT-11` 原文三条）：① 迁移前后投影一致 ⇒ `Report.mismatches` 为空；
    /// ② 二次迁移无 diff ⇒ 第二跑 `written == 0` 且 `backupName == nil`；③ 备份文件在盘 ⇒ `Report.backupURL`。
    ///
    /// 备份落点缺省 = 数据家（`databaseURL` 所在目录）；`backupDirectory` 可覆盖（测试用临时目录）。
    /// 库还不存在 ⇒ 如实返回空读数（**不顺手建一个空库**，与 `load()` / `todos()` 同一条纪律）。
    public func migrateLegacyBodiesIfNeeded(
        backupDirectory: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> NoteBodyMigrationRunner.Report {
        // `DOYAH_NOTES_DIR` 覆盖（脚本 / 测试把数据挪到临时目录）⇒ **主动让路**：那是「数据家在别处」
        // 的信号，照迁只会把真实用户的正文迁进临时目录 —— 与 `NoteLibraryMigration.migrateIfNeeded`
        // 第 5 条同一条纪律。（显式给了 `backupDirectory` 的调用点 = 测试，不受这条影响。）
        if backupDirectory == nil, let override = environment["DOYAH_NOTES_DIR"], !override.isEmpty {
            return NoteBodyMigrationRunner.emptyReport(outcome: .skippedOverridden)
        }
        // 库还不存在 ⇒ 没有要搬的东西（**不顺手建一个空库**，与 `load()` / `todos()` 同纪律）。
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            return NoteBodyMigrationRunner.emptyReport(outcome: .nothingToMigrate)
        }
        return try NoteBodyMigrationRunner.run(
            store: NoteBodyMigrationDatabaseStore(database: open()),
            sink: FileNoteBodyMigrationSink(directory: backupDirectory ?? databaseURL.deletingLastPathComponent())
        )
    }

    // MARK: - 待办任务清单（schema v5 · 队列 `N-11` 的 macOS 核心层半）

    /// 全部任务（**创建时间正序** —— 稳定有序；三档排序口径属契约半，见 `Todo` 的说明）。
    /// 库还不存在时如实返回空表（**不顺手建一个空库**，与 `load()` 同一条纪律）。
    public func todos() throws -> [Todo] {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return [] }
        return try open().todos()
    }

    /// 一条任务（`nil` = 库里没有这一条）。
    public func todo(id: UUID) throws -> Todo? {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return nil }
        return try open().todo(id: id)
    }

    /// 写入或覆盖一条任务（本体 + 标签一个事务）。返回落库后的那一份（**读回事实**，
    /// 不是把入参原样回给调用方 —— 与 `upsert(_ draft:)` 同一条纪律）。
    ///
    /// 两条纪律与笔记侧同形：
    ///   ① **完成态与完成时刻只认库里那一份** —— 它们只有 `setDone` 一条写路（与收藏 / 置顶
    ///      「只有 setter 一条路」同一条教训：否则「打开一条已完成的任务、改个标题、保存」
    ///      会把它**静默改回未完成**）；
    ///   ② 截止时间**跟着调用方**（改期就是重写这一列；另开一条「改期」的路只会多一处口径）。
    @discardableResult
    public func upsert(_ todo: Todo) throws -> Todo {
        let database = try open()
        var value = todo
        if let existing = try database.todo(id: todo.id) {
            value.done = existing.done
            value.completedAt = existing.completedAt
        }
        _ = try database.upsert(value)
        return value
    }

    /// **完成 / 重开**一条任务：返回**真的改了几行**（认不出的 id ⇒ `0`，调用方按数如实处置）。
    /// 只动完成态与完成时刻 + `updatedAt`，**不碰截止时间**（契约裁决 ①）。
    @discardableResult
    public func setDone(id: UUID, _ done: Bool, at moment: Date = Date()) throws -> Int {
        try open().setDone(done, id: id, at: moment)
    }

    /// **一次「改重复任务」**（`FR-NTS-TODO-CALENDAR-001` 判据④）：要落的几笔在**同一个事务**里写完，
    /// 返回读回事实（`upsert(_ todo:)` 一条条来一遍，完成态仍只认库里那一份）。
    ///
    /// 为什么必须是一个事务：`.thisOccurrence` 要改两行（那一串补一格「跳过」+ 新起一条独立记录）。
    /// 分两次写，中间失败会留下「原日子不发生了、改动那条却没写进去」—— 用户那边就是**任务凭空少一次**，
    /// 而两步各自都成功过，日志里看不出问题。
    @discardableResult
    public func saveOccurrenceEdit(_ edit: TodoOccurrenceEdit) throws -> [Todo] {
        let database = try open()
        // 完成态与完成时刻只认库里那一份（与 `upsert(_ todo:)` 同一条纪律）：先读回，再一个事务写完。
        var rows: [Todo] = []
        for value in edit.writes {
            var row = value
            if let existing = try database.todo(id: value.id) {
                row.done = existing.done
                row.completedAt = existing.completedAt
            }
            rows.append(row)
        }
        try database.upsert(rows)
        return rows
    }

    public func deleteTodo(id: UUID) throws {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return }
        try open().deleteTodo(id: id)
    }

    // MARK: - 任务 ↔ 笔记的转化链接（schema v13 · `FR-NTS-TODO-LINK-001`）

    /// 全部链接（界面那一屏一次读齐：靠它判「对方还在不在」，不逐条查库）。
    /// 库还不存在时如实返回空表（**不顺手建一个空库**，与 `todos()` 同一条纪律）。
    public func links() throws -> [TodoNoteLink] {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return [] }
        return try open().links()
    }

    /// 某条笔记的链接。
    public func links(noteID: UUID) throws -> [TodoNoteLink] {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return [] }
        return try open().links(noteID: noteID)
    }

    /// 某条任务的链接。
    public func links(todoID: UUID) throws -> [TodoNoteLink] {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return [] }
        return try open().links(todoID: todoID)
    }

    /// 写一条链接（同一对对象只有一条）。
    @discardableResult
    public func saveLink(_ link: TodoNoteLink) throws -> TodoNoteLink {
        _ = try open().upsert(link)
        return link
    }

    /// 删一条链接：返回**真的删了几行**（0 = 本来就没有，调用方如实说）。
    @discardableResult
    public func deleteLink(id: UUID) throws -> Int {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return 0 }
        return try open().deleteLink(id: id)
    }

    // MARK: - 提醒（schema v6 · 队列 `L-100` 落法 ④ 的存储半）

    /// 某个归属（一条笔记 / 一条任务）的提醒。
    /// 库还不存在时如实返回空表（**不顺手建一个空库**，与 `todos()` 同一条纪律）。
    public func reminders(of owner: ReminderOwner) throws -> [Reminder] {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return [] }
        return try open().reminders(of: owner)
    }

    /// 库里**所有**提醒（界面入口半那一份索引：清单行上那枚小铃铛与「提醒」区都读它）。
    /// 库不存在时如实返回空表（不顺手建库）。
    public func reminders() throws -> [Reminder] {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return [] }
        return try open().reminders()
    }

    /// 建 / 改一条提醒。**归属必须真的存在** —— 挂到一条不存在的笔记 / 任务上 ⇒ 抛错
    /// （与 `upsert(_ todo:)` 的「先写后取」同一条纪律；不落一条谁也找不到的提醒）。
    public func addReminder(_ reminder: Reminder) throws {
        try open().upsert(reminder)
    }

    /// 删一条提醒（**任务/笔记被删时它的提醒由库的级联一并走**，见 `NoteSchemaV6`）。
    public func deleteReminder(id: UUID) throws {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return }
        try open().deleteReminder(id: id)
    }

    /// **删一条笔记 = 落墓碑**（契约 §6.4.1 / `IR-17`）—— 门面这一层只做两件事：
    /// ① 库不在 ⇒ 没有可删的（返回 `false`，不顺手建一个空库）；
    /// ② **`changeCount == 0` ⇒ 抛 `noteNotFound`**（改前这里是"删了就是删了"的静默路径，
    /// 2026-10-09 人类主人真机点验缺陷 `T-20261009-162`：没命中的删除必须**报错**，不许静默 no-op）。
    ///
    /// - Returns: `true` = 真的落下了墓碑；`false` = 库还不存在（没有任何东西被删）。
    @discardableResult
    public func delete(id: UUID, at: Date) throws -> Bool {
        // 库还不存在时删一条 = 什么都没发生（不要顺手建一个空库出来）。
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return false }
        let changed = try open().tombstone(id: id, at: at)
        guard changed > 0 else { throw NoteStorageFailure.noteNotFound(id.uuidString) }
        return true
    }

    /// 一条笔记的墓碑时刻（`nil` = 没有这条 或 还没删）。
    public func deletedAt(id: UUID) throws -> Date? {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return nil }
        return try open().deletedAt(id: id)
    }

    /// **含墓碑**的全部笔记（同步面专用：删除那一条路要还能读到那行）。
    public func loadIncludingDeleted() throws -> [Note] {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return [] }
        return try open().notesIncludingDeleted()
    }

    // MARK: - 回收站（`FR-NTS-NOTE-TRASH-001`）

    /// 回收站的全部条目（含已清除的收据）。**库不存在 ⇒ 空表**（不顺手建库 —— 与 `todos()` 同口径）。
    public func trashedEntries() throws -> [NoteTrashEntry] {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return [] }
        return try open().trashedEntries()
    }

    /// 从回收站恢复一条。`nil` = 这条不在回收站里 / 已彻底清除（内容没了，恢复只能造出空笔记）。
    @discardableResult
    public func restoreFromTrash(id: UUID, at: Date) throws -> NoteRestoreOutcome? {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return nil }
        return try open().restoreFromTrash(id: id, at: at)
    }

    /// 彻底清除一条（内容清空、墓碑留着传播、回收站那一行留收据）。
    @discardableResult
    public func purgeFromTrash(id: UUID, at: Date) throws -> Int {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return 0 }
        return try open().purgeFromTrash(id: id, at: at)
    }

    // MARK: - 归档（`FR-NTS-NOTE-ORG-001` ③）

    /// 归档 / 取消归档（**只动归档位**：不刷新 `updatedAt`、不产生版本）。
    @discardableResult
    public func setArchived(id: UUID, _ archived: Bool) throws -> Int {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return 0 }
        return try open().setArchived(archived, id: id)
    }

    /// 归档里有几条（左栏那一行的数字）。
    public func archivedCount() throws -> Int {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return 0 }
        return try open().archivedCount()
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

/// `NoteBodyMigrationStore` 的 SQLite 落地：把迁移执行器接到 `NoteDatabase`。
///
/// 写走 `NoteDatabase.setNoteSpans` —— 那是**全仓唯一**写 `spans` 列的地方（片 `WY-1a` 立的单一
/// 写入口，`WY-2a` 把它接到编辑面、本片把它接到迁移面）：迁移不另开一条写路，就不会出现
/// 「权威源换了、`body` 投影还是旧的」这种半新半旧。
struct NoteBodyMigrationDatabaseStore: NoteBodyMigrationStore {
    let database: NoteDatabase

    func legacyRows() throws -> [NoteBodyMigrationRunner.Row] {
        try database.legacyBodyRows()
    }

    func storedSpans(id: UUID) throws -> String? {
        try database.noteSpans(id: id)
    }

    func alreadyMigratedCount() throws -> Int {
        try database.migratedSpanCount()
    }

    @discardableResult
    func writeSpans(_ spans: String, body: String, id: UUID) throws -> Int {
        try database.setNoteSpans(spans, body: body, id: id)
    }
}
