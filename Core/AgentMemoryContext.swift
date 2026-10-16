import Foundation

/// 记忆的**派生索引**（`FR-AI-29` ⑤：「索引是可重建的派生缓存，事实源不因它而变」）。
///
/// 这份文件存在的意义只有一条：**把「事实源」和「为了快而抄的一份」分开**。
/// 所以它必须满足两件可断言的事 ——
/// 1. 删掉它**不丢任何数据**：`AgentMemoryIndexer.build` 是**纯函数**，从事实源（`AgentMemoryStore.entries`）
///    重算即可，且给同一个 `builtAt` 每次得到**逐字节一致**的内容；
/// 2. 它**只增不改语义**：条目增删后重建，索引跟着变；而事实源一字不动。
///
/// 键集合同样是白名单（结构上没有承载结果集行数据的字段），与事实源一条口径。
public struct AgentMemoryIndex: Codable, Equatable, Sendable {

    public static let keyWhitelist: Set<String> = ["workspace", "builtAt", "items"]

    /// 索引里的一条（**只是事实源那几个键的投影**，不新造信息）。
    public struct Item: Codable, Equatable, Sendable {

        public static let keyWhitelist: Set<String> = [
            "id", "kind", "connection", "fingerprint", "firstSeenAt", "lastUsedAt", "useCount",
        ]

        public var id: String
        public var kind: String
        public var connection: String
        public var fingerprint: String
        public var firstSeenAt: Date
        public var lastUsedAt: Date
        public var useCount: Int

        public init(id: String,
                    kind: String,
                    connection: String,
                    fingerprint: String,
                    firstSeenAt: Date,
                    lastUsedAt: Date,
                    useCount: Int) {
            self.id = id
            self.kind = kind
            self.connection = connection
            self.fingerprint = fingerprint
            self.firstSeenAt = firstSeenAt
            self.lastUsedAt = lastUsedAt
            self.useCount = useCount
        }

        public var memoryKind: MemoryKind? { MemoryKind(rawValue: kind) }
    }

    public var workspace: String
    /// 建立时刻（**注入**，不读钟 —— 否则「重建后逐字节一致」这条判据无法对拍）。
    public var builtAt: Date
    /// 按（最近用到倒序、id 升序）排好的条目投影。
    public var items: [Item]

    public init(workspace: String, builtAt: Date, items: [Item]) {
        self.workspace = workspace
        self.builtAt = builtAt
        self.items = items
    }

    public var entryCount: Int { items.count }
    public var ids: [String] { items.map(\.id) }
    public var isEmpty: Bool { items.isEmpty }

    public func count(of kind: MemoryKind) -> Int {
        items.filter { $0.memoryKind == kind }.count
    }

    public func item(id: String) -> Item? { items.first { $0.id == id } }
}

/// 从事实源**重算**索引（**纯函数**：同样的输入 ⇒ 同样的输出）。
public enum AgentMemoryIndexer {

    public static func build(workspace: String, entries: [AgentMemoryEntry], builtAt: Date) -> AgentMemoryIndex {
        let items = entries
            .sorted { lhs, rhs in
                if lhs.lastUsedAt != rhs.lastUsedAt { return lhs.lastUsedAt > rhs.lastUsedAt }
                return lhs.id < rhs.id
            }
            .map { entry in
                AgentMemoryIndex.Item(id: entry.id,
                                      kind: entry.kind,
                                      connection: entry.connection,
                                      fingerprint: entry.fingerprint,
                                      firstSeenAt: entry.firstSeenAt,
                                      lastUsedAt: entry.lastUsedAt,
                                      useCount: entry.useCount)
            }
        return AgentMemoryIndex(workspace: workspace, builtAt: builtAt, items: items)
    }

    /// 索引文件的**确定形态**（键排序 + 缩进）：同一份输入两次写出的字节逐位一致，可 diff、可进版本库。
    public static func data(_ index: AgentMemoryIndex) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = AgentStoredDate.encoding
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(index)
    }

    public static func decode(_ data: Data) throws -> AgentMemoryIndex {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = AgentStoredDate.decoding
        return try decoder.decode(AgentMemoryIndex.self, from: data)
    }
}

/// 派生索引的落盘 / 读取 / 重建（**只碰索引文件，事实源一字不动**）。
extension AgentMemoryStore {

    /// 索引在不在盘上（删掉它 = 让下一次读走重建这条路，这正是「可重建」要能被证明的动作）。
    public func hasIndex(workspace: String) -> Bool {
        readIndexData(workspace: workspace) != nil
    }

    /// 读索引。**读不出来就是 `nil`** —— 派生缓存坏掉不该让记忆层不可用，重建就是了。
    public func loadIndex(workspace: String) -> AgentMemoryIndex? {
        guard let data = readIndexData(workspace: workspace) else { return nil }
        return try? AgentMemoryIndexer.decode(data)
    }

    /// **重建**：从事实源重算并落盘，返回重建出来的那一份。
    ///
    /// 归属不符（头一行声明的是别的工作区）⇒ 不重建，如实抛错（照 `record` 的口径：
    /// 不属于本工作区的东西，本工作区不动它）。
    @discardableResult
    public func rebuildIndex(workspace: String, builtAt: Date = Date()) throws -> AgentMemoryIndex {
        let loaded = entries(workspace: workspace)
        if loaded.workspaceMismatch {
            throw AgentMemoryIndexError.workspaceMismatch(workspace: workspace)
        }
        let index = AgentMemoryIndexer.build(workspace: workspace, entries: loaded.entries, builtAt: builtAt)
        try writeIndexData(try AgentMemoryIndexer.data(index), workspace: workspace)
        return index
    }

    /// 删掉派生缓存（**不碰事实源**）。返回是否真删到了东西。
    @discardableResult
    public func removeIndex(workspace: String) -> Bool {
        let url = indexFileURL(workspace: workspace)
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        do {
            try FileManager.default.removeItem(at: url)
            return true
        } catch {
            // 删不掉：如实回答（调用方据此说话，不假装删了）。
            return false
        }
    }
}

public enum AgentMemoryIndexError: Error, Equatable, Sendable {
    case workspaceMismatch(workspace: String)
}

/// 记忆**进上下文**的唯一入口（`FR-AI-29` ②：「删掉即不再进上下文」）。
///
/// **为什么产出 `references` 而不自己拼提示词**：上下文由 `AgentContextAssembler` 统一装配
/// （截断、边界过滤、外发预览都在那一处），谁绕过它谁就在数据边界上开第二个口子。
///
/// **为什么用 `.file` 这一支**：`AgentContextReference` 的六类里没有「记忆」这一类，而
/// `Core/AgentContext.swift` 不在本次改动的允许面内（硬约束：只新增文件、不改既有文件）。
/// `.file` 是六类中**唯一「给一段自由文本」**的通道，于是用 `memory://<工作区>/<类别>/<id>`
/// 这个自解释的 URI 当路径 —— 模型在段标题上就看得出这是什么、哪一档。
///
/// 两道过滤，都是既有件：
/// 1. 放进来的只有**认得出类别**且**按 `FR-AI-15` 口径仍然该记着**的条目（该忘的不进上下文）；
/// 2. 正文再走一遍 `AgentContextBoundary`（`.file` 那支自带）—— 万一有条目绕过了写入闸，
///    结果集行数据仍会在**外发前**被挡下并计进 `redactedRows`。
public enum AgentMemoryContext {

    /// URI 方案名（ASCII 小写，自解释）。
    public static let pathScheme = "memory"

    public static func uri(for entry: AgentMemoryEntry) -> String {
        "\(pathScheme)://\(AgentMemory.sanitized(entry.workspace))/\(entry.kind)/\(AgentMemory.sanitized(entry.id))"
    }

    public static func reference(for entry: AgentMemoryEntry) -> AgentContextReference {
        .file(path: uri(for: entry), text: entry.note)
    }

    /// 本次要挂上去的记忆引用。
    ///
    /// - Parameter limit: 最多挂几条（超出的**不挂**，也不静默改写正文 —— 排序是稳定的，
    ///   所以「挂哪几条」可逐条对拍）。
    public static func references(from entries: [AgentMemoryEntry],
                                 now: Date,
                                 calendar: Calendar = .current,
                                 limit: Int = 8) -> [AgentContextReference] {
        let usable = entries
            .filter { $0.memoryKind != nil }
            .filter { entry in
                guard let explanation = AgentMemoryReasons.describe(entry: entry, now: now, calendar: calendar) else {
                    return false
                }
                return explanation.isRetained
            }
            .sorted { lhs, rhs in
                if lhs.lastUsedAt != rhs.lastUsedAt { return lhs.lastUsedAt > rhs.lastUsedAt }
                return lhs.id < rhs.id
            }
        return usable.prefix(max(0, limit)).map(reference(for:))
    }
}
