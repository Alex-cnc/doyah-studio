import Foundation

/// 对话记忆（`FR-AI-29` / 概要设计 §3.51 不变量 26）：**跨会话的长期记忆**。
///
/// 需求原文的六条验收要点与这里的落点一一对应：
/// ① **可逐条检视 + 回答「为什么记了它」**（可读理由**带实际数字**）——`AgentMemoryReasons.describe`
///    **不另造第二套口径**，它把条目组装成 `QueryMemory.Memory` 后**直接调 `FR-AI-15` 的
///    `MemoryExplanation.describe`**（连标签都沿用那一份：`MemoryExplanation` / `MemoryKind` /
///    `RetentionPolicy` / `MemoryStats` 全是既有件）。
/// ② **删除立即生效且可验证** —— 事实源是逐步重写（原子替换）的，删掉的那一条**下一次读就没了**；
///    派生索引重建后也不再出现；组装上下文时用的是读回的事实，于是**不再进上下文**。
/// ③ **按工作区（与连接）隔离** —— 「一工作区一文件」（+ 头一行声明工作区，与 `AgentSessionStore`
///    同一套归属校验），连接是条目上的字段、可按连接筛。
/// ④ **键集合是白名单，结构上没有承载结果集行数据的字段，密钥片段被挡** —— `keyWhitelist` 是
///    断言面（不是注释）；写入前过 `AgentMemoryIntake`（复用 `AgentContextBoundary` 的行数据 /
///    密钥判定），命中即**拒收**并报数；读回时**键落在白名单之外的行一律跳过并计数**。
/// ⑤ **索引是可重建的派生缓存** —— 见 `Core/AgentMemoryContext.swift` 的 `AgentMemoryIndex`。
/// ⑥ **坏文件 / 认不出的条目跳过并计数** —— `AgentMemoryLoadResult` 有逐类读数，不许静默吞。
///
/// 硬约束（本文件的设计理由）：**不改任何既有文件** —— 需要新增能力时一律照既有件组合，
/// 例如不新增 `AgentContextReference` 的第 7 个 case（那要改 `Core/AgentContext.swift`），
/// 而是走既有的 `.file` 通道（见 `AgentMemoryContext.references`）。
public enum AgentMemory {

    /// 目录名（与 `AgentSessionStore` 同一处：`Application Support/DoyahStudio/<这个>`)。
    public static let directoryName = "agent-memory"

    /// 事实源（工作区长期记忆）的文件扩展名。
    public static let factFileExtension = "jsonl"

    /// 派生索引的文件后缀（与事实源同名不同后缀，一眼能看出谁是派生的）。
    public static let indexFileSuffix = ".index.json"

    /// 路径 → 文件名用的安全化（只留字母 / 数字 / `-` / `_`）。
    /// 与 `AgentSessionStore.sanitized` 同一套形状，但它那一份是会话存储的内部实现细节，
    /// 这里自带一份，免得两处语义被后来的改动绑在一起。
    public static func sanitized(_ name: String) -> String {
        name.map { character in
            character.isLetter || character.isNumber || character == "-" || character == "_" ? character : "_"
        }.reduce(into: "") { $0.append($1) }
    }

    /// 日键（跨天分布 / 理由里的「跨 N 天」用），口径同 `QueryMemory.dayKey`。
    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    /// 从「首次见到」到「最近用到」之间的日键集合（含两端）。
    ///
    /// 为什么给集合而不是一个 `Int`：`MemoryStats(memory:)` 读的就是 `days.count`
    /// （`FR-AI-15` 的「跨 N 天」）—— 这里造出同一形状，理由里的天数才是**同一口径算的**。
    static func dayKeys(from first: Date, to last: Date, calendar: Calendar = .current) -> Set<String> {
        let start = calendar.startOfDay(for: first)
        let end = calendar.startOfDay(for: last)
        guard start <= end else { return [dayKey(first, calendar: calendar)] }
        var result: Set<String> = []
        var cursor = start
        // 有界循环：跨天极少（一条记忆的两端），上限兜底防坏值把这里变成死循环。
        var guardCounter = 0
        while cursor <= end && guardCounter < 4000 {
            result.insert(dayKey(cursor, calendar: calendar))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
            guardCounter += 1
        }
        return result
    }
}

// MARK: - 一条记忆

/// 一条长期记忆。
///
/// **这是一条「我知道什么」的短摘要，不是数据本身** —— 结构上没有承载结果集行数据的字段
/// （同 `NFR-AI-01` / `AgentSessionTurn` 的做法：类型里没有那个位置，而不是靠写入方自觉）。
public struct AgentMemoryEntry: Codable, Equatable, Sendable, Identifiable {

    /// 允许出现的键（判据按这一份对账；加字段必须同时改这里 —— 不是注释，是断言面）。
    public static let keyWhitelist: Set<String> = [
        "id", "workspace", "connection", "kind", "note", "fingerprint",
        "firstSeenAt", "lastUsedAt", "useCount",
    ]

    /// 稳定 id。
    public var id: String
    /// 归属工作区（隔离的第一层）。
    public var workspace: String
    /// 归属连接（隔离的第二层：同一工作区里，生产库的记忆不流进测试库）。
    public var connection: String
    /// 类别（取值 = `MemoryKind` 的词表；**认不出的取值即「认不出的条目」**，跳过并计数）。
    public var kind: String
    /// 记忆正文（短摘要；写入前过 `AgentMemoryIntake`，读回时进上下文还要过 `AgentContextBoundary`）。
    public var note: String
    /// 粗指纹（聚类依据，用 `QueryMemory.coarseFingerprint`）—— 与 `FR-AI-15` 的「聚类依据（粗指纹）」同源。
    public var fingerprint: String
    /// 首次见到。
    public var firstSeenAt: Date
    /// 最近用到。
    public var lastUsedAt: Date
    /// 累计用到多少次（重复记同一条 ⇒ 累计，而不是又长一条）。
    public var useCount: Int

    public init(id: String,
                workspace: String,
                connection: String,
                kind: String,
                note: String,
                fingerprint: String,
                firstSeenAt: Date,
                lastUsedAt: Date,
                useCount: Int) {
        self.id = id
        self.workspace = workspace
        self.connection = connection
        self.kind = kind
        self.note = note
        self.fingerprint = fingerprint
        self.firstSeenAt = firstSeenAt
        self.lastUsedAt = lastUsedAt
        self.useCount = useCount
    }

    /// 认出来的类别（`nil` = 认不出 ⇒ 该条不进结果，计进 `unknownEntries`）。
    public var memoryKind: MemoryKind? { MemoryKind(rawValue: kind) }

    public var isRecognized: Bool { memoryKind != nil }
}

/// 事实源的第一行：**这份记忆属于哪个工作区**（照 `AgentSessionHeader` 的做法规避「看不到 = 空」）。
public struct AgentMemoryHeader: Codable, Equatable, Sendable {

    public static let keyWhitelist: Set<String> = ["workspace"]

    public var workspace: String

    public init(workspace: String) {
        self.workspace = workspace
    }
}

// MARK: - 上限

/// 写入上限（`FR-AI-29`：「写入有上限」）。
///
/// 两条都是**有界**的：条数（超出按**最近最少用**挤出并如实报数）与单条正文字符数（超出截断并报数）。
/// 做成可配的显式对象而不是散落的常量：判据才能用一组小上限把边界逼出来（同 `AgentContextLimits` 的做法）。
public struct AgentMemoryLimits: Equatable, Sendable {

    public var maxEntriesPerWorkspace: Int
    public var maxNoteCharacters: Int

    public init(maxEntriesPerWorkspace: Int = 200, maxNoteCharacters: Int = 200) {
        self.maxEntriesPerWorkspace = maxEntriesPerWorkspace
        self.maxNoteCharacters = maxNoteCharacters
    }

    public static let standard = AgentMemoryLimits()
}

// MARK: - 写入意图

/// 要记的一条（调用方给的东西；还没过闸、还没有 id 与指纹）。
public struct AgentMemoryDraft: Equatable, Sendable {

    public var workspace: String
    public var connection: String
    public var kind: MemoryKind
    public var note: String

    public init(workspace: String, connection: String, kind: MemoryKind, note: String) {
        self.workspace = workspace
        self.connection = connection
        self.kind = kind
        self.note = note
    }
}

// MARK: - 入闸（④ 的第一道）

/// 写入前的闸：**结果集行数据与密钥片段一律挡下**，并且**报数**（不静默改写）。
///
/// 判定物**就是既有那一套**（`AgentContextBoundary` 的行数据 / 密钥启发式）—— 同样是
/// 「与外发边界同一套口径，不另造第二套」：进不了记忆的东西，也就无所谓外发。
public enum AgentMemoryIntake {

    /// 拒收的理由（**机器形态**，不是一句人话：人话由带语言的渲染层给，本层不带语言上下文）。
    public enum Rejection: Equatable, Sendable {
        /// 正文空。
        case emptyNote
        /// 看起来是结果集行 / 表格行：挡下 N 处。
        case rowLikeContent(count: Int)
        /// 含密钥 / 令牌片段：挡下 N 处。
        case secretFragment(count: Int)
        /// 目标工作区的事实源属于**别的工作区**（归属不符 ⇒ 不落盘，不静默落到别人家）。
        case workspaceMismatch
        /// 目标工作区的事实源坏了（有内容却找不到头一行）⇒ **不覆盖**（那会把读不出来的东西
        /// 悄悄清掉）：如实拒收，让调用方先处置。
        case sourceUnreadable
    }

    public struct Verdict: Equatable, Sendable {
        /// 过闸后的正文（已截断；拒收时 = 原文，调用方别拿它落盘）。
        public var note: String
        /// 粗指纹（聚类依据）。
        public var fingerprint: String
        public var rejections: [Rejection]
        /// 因上限被截掉的字数（> 0 时如实报出）。
        public var truncatedCharacters: Int

        public var isAccepted: Bool { rejections.isEmpty }
    }

    /// 判定 + 归一（**纯函数**，不碰盘）。
    public static func review(_ draft: AgentMemoryDraft,
                             limits: AgentMemoryLimits = .standard) -> Verdict {
        let trimmed = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Verdict(note: trimmed, fingerprint: "", rejections: [.emptyNote], truncatedCharacters: 0)
        }

        // 与上下文边界**同一套**判定（行数据启发式 + 密钥启发式）。
        let boundary = AgentContextBoundary.filter(trimmed)
        var rejections: [Rejection] = []
        if boundary.redactedRows > 0 { rejections.append(.rowLikeContent(count: boundary.redactedRows)) }
        if boundary.redactedSecrets > 0 { rejections.append(.secretFragment(count: boundary.redactedSecrets)) }

        var note = boundary.text
        var truncated = 0
        if note.count > limits.maxNoteCharacters {
            truncated = note.count - limits.maxNoteCharacters
            note = String(note.prefix(limits.maxNoteCharacters))
        }
        return Verdict(note: note,
                       fingerprint: QueryMemory.coarseFingerprint(note),
                       rejections: rejections,
                       truncatedCharacters: truncated)
    }
}

// MARK: - 读回结果

/// 读回一个工作区的记忆：**跳过与坏掉都要报数**（不静默丢，`FR-AI-29` ⑥）。
public struct AgentMemoryLoadResult: Equatable, Sendable {

    /// 这个工作区看得到的记忆（按最近用到倒序，稳定）。
    public var entries: [AgentMemoryEntry]
    /// 解析不出来 / **键落在白名单之外**的行数（后者尤其重要：手改文件塞进来的行一律不认）。
    public var skippedLines: Int
    /// 认不出的条目数（形如合法、但 `kind` 不在 `MemoryKind` 词表里）。
    public var unknownEntries: Int
    /// 归属不是本工作区的条目数（按隔离口径**看不到**，但也如实计入读数）。
    public var foreignEntries: Int
    /// 读不了的文件的份数（非 UTF-8 / 读不出）。
    public var skippedFiles: Int
    /// 有内容但**找不到头一行**（事实源被截断 / 被重写坏了）。
    public var missingHeader: Bool
    /// 头一行声明的工作区与请求的不符（⇒ **看不到**，不当成「空」）。
    public var workspaceMismatch: Bool

    public init(entries: [AgentMemoryEntry] = [],
                skippedLines: Int = 0,
                unknownEntries: Int = 0,
                foreignEntries: Int = 0,
                skippedFiles: Int = 0,
                missingHeader: Bool = false,
                workspaceMismatch: Bool = false) {
        self.entries = entries
        self.skippedLines = skippedLines
        self.unknownEntries = unknownEntries
        self.foreignEntries = foreignEntries
        self.skippedFiles = skippedFiles
        self.missingHeader = missingHeader
        self.workspaceMismatch = workspaceMismatch
    }

    /// 有没有「跳过 / 认不出 / 归属不符」的读数（判据与界面据此如实说「有 N 条没读进来」）。
    public var hasSkippedReadings: Bool {
        skippedLines > 0 || unknownEntries > 0 || foreignEntries > 0 || skippedFiles > 0
            || missingHeader || workspaceMismatch
    }
}

/// 一次写入的结果（三条读数都要能报出来：收了没有 / 是新增还是合并 / 挤掉了谁）。
public struct AgentMemoryWriteResult: Equatable, Sendable {

    public var accepted: Bool
    public var entry: AgentMemoryEntry?
    public var rejections: [AgentMemoryIntake.Rejection]
    /// 与既有条目（同工作区 + 同连接 + 同指纹）合并了 ⇒ 累计次数 +1，不再长一条。
    public var merged: Bool
    /// 因上限被挤出的条目 id（**最近最少用**先出）。
    public var evictedIDs: [String]
    /// 因上限被截掉的字数。
    public var truncatedCharacters: Int

    public init(accepted: Bool,
                entry: AgentMemoryEntry? = nil,
                rejections: [AgentMemoryIntake.Rejection] = [],
                merged: Bool = false,
                evictedIDs: [String] = [],
                truncatedCharacters: Int = 0) {
        self.accepted = accepted
        self.entry = entry
        self.rejections = rejections
        self.merged = merged
        self.evictedIDs = evictedIDs
        self.truncatedCharacters = truncatedCharacters
    }
}

// MARK: - 可检视的一条（①）

/// 「逐条列出 + 为什么记了它」：**理由一定带实际数字**，且与 `FR-AI-15` 同一套口径。
public struct AgentMemoryExplanation: Equatable, Sendable {

    public var id: String
    public var workspace: String
    public var connection: String
    public var kind: MemoryKind
    public var useCount: Int
    public var isPinned: Bool
    /// `MemoryExplanation.describe` 的**原样产出**（`FR-AI-15` 的那四行；本层一字不改写）。
    public var lines: [String]
    /// 按 `FR-AI-15` 的生命周期判定，这一条**仍然该记着**（`false` = 该被遗忘，不再进上下文）。
    public var isRetained: Bool

    public init(id: String,
                workspace: String,
                connection: String,
                kind: MemoryKind,
                useCount: Int,
                isPinned: Bool,
                lines: [String],
                isRetained: Bool) {
        self.id = id
        self.workspace = workspace
        self.connection = connection
        self.kind = kind
        self.useCount = useCount
        self.isPinned = isPinned
        self.lines = lines
        self.isRetained = isRetained
    }

    /// 「为什么记了它 / 为什么它被忘了」那一行（标签由 `MemoryExplanation` 给）。
    public var reasonLine: String? { lines.last }
}

/// 一次「检视」（`FR-AI-29` ①）。
public struct AgentMemoryInspection: Equatable, Sendable {

    public var workspace: String
    public var entries: [AgentMemoryEntry]
    /// 与 `entries` 逐条对齐的解释（条数相等 —— 「逐条列出」与「逐条解释」不会错位）。
    public var explanations: [AgentMemoryExplanation]
    public var skippedLines: Int
    public var unknownEntries: Int
    public var foreignEntries: Int
    public var skippedFiles: Int
    public var missingHeader: Bool
    public var workspaceMismatch: Bool

    public init(workspace: String,
                entries: [AgentMemoryEntry] = [],
                explanations: [AgentMemoryExplanation] = [],
                skippedLines: Int = 0,
                unknownEntries: Int = 0,
                foreignEntries: Int = 0,
                skippedFiles: Int = 0,
                missingHeader: Bool = false,
                workspaceMismatch: Bool = false) {
        self.workspace = workspace
        self.entries = entries
        self.explanations = explanations
        self.skippedLines = skippedLines
        self.unknownEntries = unknownEntries
        self.foreignEntries = foreignEntries
        self.skippedFiles = skippedFiles
        self.missingHeader = missingHeader
        self.workspaceMismatch = workspaceMismatch
    }
}

// MARK: - 理由（① 的口径来源）

/// 「为什么记了它 / 为什么它被忘了」——**不另造第二套**。
///
/// 这里只做**组装**：把一条记忆拼成 `QueryMemory.Memory`（`FR-AI-15` 吃的那个形状）、
/// 交给 `RetentionPolicy.evaluate` 出判定、再交给 `MemoryExplanation.describe` 出四行。
/// 于是「带实际数字的可读理由」这件事**只有一个实现**，两条需求不会各说各话。
public enum AgentMemoryReasons {

    /// 组装成 `FR-AI-15` 的统计量（`runCount` ↔ 累计用到次数，`days` ↔ 两端之间的日键集合）。
    public static func stats(for entry: AgentMemoryEntry, calendar: Calendar = .current) -> MemoryStats {
        MemoryStats(
            runCount: entry.useCount,
            dayCount: AgentMemory.dayKeys(from: entry.firstSeenAt, to: entry.lastUsedAt, calendar: calendar).count,
            variantCount: 1,
            lastExecutedAt: entry.lastUsedAt,
            connections: [entry.connection]
        )
    }

    /// 组装成 `QueryMemory.Memory`（`latestSQL` 位置放**记忆正文** —— 它与「最近原文」是同一个语义位置）。
    public static func memory(for entry: AgentMemoryEntry, calendar: Calendar = .current) -> QueryMemory.Memory {
        QueryMemory.Memory(
            fingerprint: entry.fingerprint,
            latestSQL: entry.note,
            variantCount: 1,
            runCount: entry.useCount,
            days: AgentMemory.dayKeys(from: entry.firstSeenAt, to: entry.lastUsedAt, calendar: calendar),
            connections: [entry.connection],
            lastExecutedAt: entry.lastUsedAt
        )
    }

    /// 逐条解释（认不出的类别 ⇒ `nil`；这类条目本来就不进结果，只计进 `unknownEntries`）。
    public static func describe(entry: AgentMemoryEntry,
                                now: Date,
                                calendar: Calendar = .current) -> AgentMemoryExplanation? {
        guard let kind = entry.memoryKind else { return nil }
        let raw = memory(for: entry, calendar: calendar)
        let verdict = RetentionPolicy.standard.evaluate(kind: kind, stats: stats(for: entry, calendar: calendar), now: now)
        return AgentMemoryExplanation(
            id: entry.id,
            workspace: entry.workspace,
            connection: entry.connection,
            kind: kind,
            useCount: entry.useCount,
            isPinned: kind == .pinned,
            lines: MemoryExplanation.describe(memory: raw, kind: kind, verdict: verdict),
            isRetained: !verdict.shouldForget
        )
    }
}

// MARK: - 存储（事实源）

/// 长期记忆的**事实源**：一工作区一文件（追加式 JSONL，形状同 `AgentSessionStore` / `AgentCheckpoint`）。
///
/// 与它们的三点差别，都是需求逼出来的：
/// - **删除要立即生效**（②）⇒ 删除走「重读 → 去掉那一条 → **原子整写**」，而不是追加墓碑；
///   于是「删掉即不再进上下文」不依赖任何后续清理动作（事实源自己就是干净的）。
/// - **写入有上限**（④ 的那半句「写入有上限」）⇒ 超额按**最近最少用**挤出并报数。
/// - **索引是派生缓存**（⑤）⇒ 索引另存一份文件（`*.index.json`），**事实源不因它而变**。
public struct AgentMemoryStore: Sendable {

    public var directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// 默认目录：与其余本机数据同一处（不另开文件体系）。
    public static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("DoyahStudio", isDirectory: true)
            .appendingPathComponent(AgentMemory.directoryName, isDirectory: true)
    }

    public func factFileURL(workspace: String) -> URL {
        directory.appendingPathComponent("\(AgentMemory.sanitized(workspace)).\(AgentMemory.factFileExtension)")
    }

    public func indexFileURL(workspace: String) -> URL {
        directory.appendingPathComponent("\(AgentMemory.sanitized(workspace))\(AgentMemory.indexFileSuffix)")
    }

    // MARK: - 写

    /// 记一条（过闸 → 合并或新增 → 上限挤出 → **原子落盘**）。
    @discardableResult
    public func record(_ draft: AgentMemoryDraft,
                       limits: AgentMemoryLimits = .standard,
                       at date: Date = Date(),
                       id: String = UUID().uuidString) throws -> AgentMemoryWriteResult {
        let verdict = AgentMemoryIntake.review(draft, limits: limits)
        guard verdict.isAccepted else {
            return AgentMemoryWriteResult(accepted: false, rejections: verdict.rejections,
                                          truncatedCharacters: verdict.truncatedCharacters)
        }

        let loaded = entries(workspace: draft.workspace)
        if loaded.workspaceMismatch {
            // 归属不符：**写不进去**（不静默落到别人家的工作区里）。
            return AgentMemoryWriteResult(accepted: false, rejections: [.workspaceMismatch],
                                          truncatedCharacters: verdict.truncatedCharacters)
        }
        if loaded.missingHeader || loaded.skippedFiles > 0 {
            // 事实源坏了就先别写（覆盖它 = 把读不出来的东西悄悄清掉）。
            return AgentMemoryWriteResult(accepted: false, rejections: [.sourceUnreadable],
                                          truncatedCharacters: verdict.truncatedCharacters)
        }

        var entries = loaded.entries
        var merged = false
        var working: AgentMemoryEntry

        if let index = entries.firstIndex(where: {
            $0.fingerprint == verdict.fingerprint && $0.connection == draft.connection
        }) {
            var existing = entries[index]
            existing.note = verdict.note
            existing.lastUsedAt = date
            existing.useCount += 1
            entries[index] = existing
            working = existing
            merged = true
        } else {
            working = AgentMemoryEntry(id: id,
                                       workspace: draft.workspace,
                                       connection: draft.connection,
                                       kind: draft.kind.rawValue,
                                       note: verdict.note,
                                       fingerprint: verdict.fingerprint,
                                       firstSeenAt: date,
                                       lastUsedAt: date,
                                       useCount: 1)
            entries.append(working)
        }

        // 上限：**最近最少用**先出（同刻按首次见到、再按 id —— 稳定，不许随遍历顺序抖动）。
        var evicted: [String] = []
        if limits.maxEntriesPerWorkspace >= 0, entries.count > limits.maxEntriesPerWorkspace {
            let overflow = entries.count - limits.maxEntriesPerWorkspace
            let lru = entries.sorted { lhs, rhs in
                if lhs.lastUsedAt != rhs.lastUsedAt { return lhs.lastUsedAt < rhs.lastUsedAt }
                if lhs.firstSeenAt != rhs.firstSeenAt { return lhs.firstSeenAt < rhs.firstSeenAt }
                return lhs.id < rhs.id
            }
            // 刚写进来的这一条**永远不被挤出**（否则「记了它」当场不成立）。
            let doomed = Set(lru.filter { $0.id != working.id }.prefix(overflow).map(\.id))
            if !doomed.isEmpty {
                entries.removeAll { doomed.contains($0.id) }
                evicted = doomed.sorted()
            }
        }

        try write(entries: entries, workspace: draft.workspace)
        return AgentMemoryWriteResult(accepted: true,
                                     entry: entries.first { $0.id == working.id },
                                     merged: merged,
                                     evictedIDs: evicted,
                                     truncatedCharacters: verdict.truncatedCharacters)
    }

    // MARK: - 删

    /// 按 id 删一条；返回是否真的删掉了（没这条时为 `false`，调用方据此如实汇报）。
    @discardableResult
    public func remove(id: String, workspace: String) throws -> Bool {
        let loaded = entries(workspace: workspace)
        guard !loaded.workspaceMismatch else { return false }
        let remaining = loaded.entries.filter { $0.id != id }
        guard remaining.count != loaded.entries.count else { return false }
        try write(entries: remaining, workspace: workspace)
        return true
    }

    /// 整层清空该工作区的记忆；返回清掉了多少条（**只作用于事实源** —— 索引是派生的，
    /// 照「索引是可重建的派生缓存」这条口径，清空后重建索引自然也是一层空）。
    @discardableResult
    public func removeAll(workspace: String) throws -> Int {
        let loaded = entries(workspace: workspace)
        guard !loaded.workspaceMismatch else { return 0 }
        let count = loaded.entries.count
        guard count > 0 else { return 0 }
        try write(entries: [], workspace: workspace)
        return count
    }

    // MARK: - 读

    /// 读回一个工作区的记忆。
    ///
    /// - Parameter connection: 传了就**只看那个连接**的记忆（同工作区内的第二层隔离）。
    public func entries(workspace: String,
                        connection: String? = nil,
                        calendar: Calendar = .current) -> AgentMemoryLoadResult {
        let url = factFileURL(workspace: workspace)
        guard FileManager.default.fileExists(atPath: url.path) else { return AgentMemoryLoadResult() }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            // 坏文件：跳过并计数，**不让整个记忆层不可用**（⑥）。
            return AgentMemoryLoadResult(skippedFiles: 1)
        }

        var header: AgentMemoryHeader?
        var entries: [AgentMemoryEntry] = []
        var skippedLines = 0
        var unknownEntries = 0
        var foreignEntries = 0

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                skippedLines += 1
                continue
            }
            let keys = Set(object.keys)

            // 先认条目（头一行**只**有 workspace 一个键，条目的键集是白名单，两者不重叠）。
            if keys.isSubset(of: AgentMemoryEntry.keyWhitelist), keys.count > 1,
               let entry = try? Self.decoder.decode(AgentMemoryEntry.self, from: data) {
                if entry.workspace != workspace {
                    // 别人家的条目：看不到，但如实计入读数。
                    foreignEntries += 1
                    continue
                }
                if entry.memoryKind == nil {
                    // 认不出的条目（kind 不在词表里）：跳过并计数（⑥）。
                    unknownEntries += 1
                    continue
                }
                entries.append(entry)
                continue
            }

            if keys == AgentMemoryHeader.keyWhitelist,
               let decoded = try? Self.decoder.decode(AgentMemoryHeader.self, from: data) {
                if header == nil { header = decoded }
                continue
            }

            // 键落在白名单之外（例如手改文件塞进来一个 rows 字段）⇒ 不认这一行并计数。
            skippedLines += 1
        }

        guard let header else {
            // 有内容却找不到头一行：**不当作空**，如实报「头找不着」。
            return AgentMemoryLoadResult(entries: [],
                                         skippedLines: skippedLines,
                                         unknownEntries: unknownEntries,
                                         foreignEntries: foreignEntries,
                                         missingHeader: true)
        }
        guard header.workspace == workspace else {
            // 别人的工作区 ⇒ **看不到**（不是「空会话」那一侧的语义）—— ③ 的负例方向。
            return AgentMemoryLoadResult(entries: [],
                                         skippedLines: skippedLines,
                                         unknownEntries: unknownEntries,
                                         foreignEntries: foreignEntries,
                                         workspaceMismatch: true)
        }
        let filtered = connection.map { wanted in entries.filter { $0.connection == wanted } } ?? entries
        return AgentMemoryLoadResult(entries: ordered(filtered),
                                     skippedLines: skippedLines,
                                     unknownEntries: unknownEntries,
                                     foreignEntries: foreignEntries)
    }

    /// 该工作区**有哪些连接**留下过记忆（可检视 / 隔离的第二层读数）。
    public func connections(workspace: String) -> [String] {
        Array(Set(entries(workspace: workspace).entries.map(\.connection))).sorted()
    }

    // MARK: - 检视（①：逐条列出 + 逐条解释）

    public func inspect(workspace: String,
                        connection: String? = nil,
                        now: Date,
                        calendar: Calendar = .current) -> AgentMemoryInspection {
        let loaded = entries(workspace: workspace, connection: connection, calendar: calendar)
        let explanations = loaded.entries.compactMap { AgentMemoryReasons.describe(entry: $0, now: now, calendar: calendar) }
        return AgentMemoryInspection(workspace: workspace,
                                     entries: loaded.entries,
                                     explanations: explanations,
                                     skippedLines: loaded.skippedLines,
                                     unknownEntries: loaded.unknownEntries,
                                     foreignEntries: loaded.foreignEntries,
                                     skippedFiles: loaded.skippedFiles,
                                     missingHeader: loaded.missingHeader,
                                     workspaceMismatch: loaded.workspaceMismatch)
    }

    // MARK: - 内部

    /// 稳定顺序：最近用到在前，同刻按 id（不许随字典遍历顺序抖）。
    private func ordered(_ entries: [AgentMemoryEntry]) -> [AgentMemoryEntry] {
        entries.sorted { lhs, rhs in
            if lhs.lastUsedAt != rhs.lastUsedAt { return lhs.lastUsedAt > rhs.lastUsedAt }
            return lhs.id < rhs.id
        }
    }

    /// 整份重写（头一行 + 各条）：**原子替换** ⇒ 盘上不留半截文件，
    /// 「删掉的立刻不见」也正是靠这里（事实源自己就是干净的）。
    private func write(entries: [AgentMemoryEntry], workspace: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var payload = try Self.encoder.encode(AgentMemoryHeader(workspace: workspace))
        payload.append(0x0A)
        for entry in ordered(entries) {
            payload.append(try Self.encoder.encode(entry))
            payload.append(0x0A)
        }
        try payload.write(to: factFileURL(workspace: workspace), options: .atomic)
    }

    /// 索引文件（派生缓存）的原子写 —— 由 `AgentMemoryIndex` 那一侧调用。
    func writeIndexData(_ data: Data, workspace: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: indexFileURL(workspace: workspace), options: .atomic)
    }

    func readIndexData(workspace: String) -> Data? {
        try? Data(contentsOf: indexFileURL(workspace: workspace))
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        // 与 `AgentSessionStore` / `AgentCheckpoint` **同一处口径**（`AgentStoredDate`）：日期逐位往返。
        encoder.dateEncodingStrategy = AgentStoredDate.encoding
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = AgentStoredDate.decoding
        return decoder
    }()
}
