import Foundation

// MARK: - 输入历史（详设 §3.35）

/// 对话输入框的**提交历史**（shell 式 ↑↓ 回填）。
///
/// 口径（详设 §3.35 契约 ④）：
/// - **只收提交成功的**（调用方在「真的发出去」那一刻记，挡下 / 空串不记）；
/// - **连续重复去重**（`A、A、B` ⇒ `A、B`）—— 连着问同一句话不该把历史撑成两条一样的；
/// - **空串不入库**（全空白也算空：回填一条空白等于把输入框清空）；
/// - **上限 200 条**（超出时挤掉最旧的，不是拒绝新的）。
///
/// 落盘顺序 = **旧 → 新**（`entries.last` 就是「最近一条」，↑ 第一次按到它）。
public struct AgentInputHistory: Codable, Equatable, Sendable {

    /// 历史上限。**是契约值**：改它等于改「能回填多少条」，判据里有一条钉着。
    public static let defaultLimit = 200

    /// 旧 → 新。
    public private(set) var entries: [String]

    /// 上限（`>= 0`；0 表示不留历史）。
    public private(set) var limit: Int

    public init(entries: [String] = [], limit: Int = AgentInputHistory.defaultLimit) {
        self.limit = max(0, limit)
        self.entries = AgentInputHistory.sanitize(entries, limit: max(0, limit))
    }

    public var isEmpty: Bool { entries.isEmpty }
    public var count: Int { entries.count }

    /// 最近一条（↑ 的第一次落点）。
    public var newest: String? { entries.last }

    /// 记一条。返回 **是否真的写进去了**（去重 / 空串 / 上限为 0 ⇒ `false`）。
    @discardableResult
    public mutating func record(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, limit > 0 else { return false }
        // 连续重复去重：只比**上一条**。隔开的重复（`A、B、A`）照样收 —— 那是真的又问了一次。
        if entries.last == normalized { return false }
        entries.append(normalized)
        if entries.count > limit {
            entries.removeFirst(entries.count - limit)
        }
        return true
    }

    /// 清空（`/clear` 一类动作；不进历史的那条命令自己调）。
    public mutating func removeAll() {
        entries.removeAll()
    }

    // MARK: - 归一化

    /// 载入时的清洗：**保留原顺序、丢掉空串、把连续重复并成一条、只留最后 `limit` 条**。
    ///
    /// 为什么要清洗而不信任盘上内容：这份文件是**跨版持久化**的，旧版本写进去的东西
    /// （或人手改坏的一行空白）不该让这一次的浏览多出一条「回到空」的假条目。
    private static func sanitize(_ raw: [String], limit: Int) -> [String] {
        guard limit > 0 else { return [] }
        var result: [String] = []
        for item in raw {
            let normalized = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { continue }
            if result.last == normalized { continue }
            result.append(normalized)
        }
        if result.count > limit {
            result.removeFirst(result.count - limit)
        }
        return result
    }

    // MARK: - Codable（带 version，旧文件缺限值时用默认值）

    private enum CodingKeys: String, CodingKey {
        case version
        case limit
        case entries
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedLimit = try container.decodeIfPresent(Int.self, forKey: .limit) ?? AgentInputHistory.defaultLimit
        let decodedEntries = try container.decodeIfPresent([String].self, forKey: .entries) ?? []
        self.init(entries: decodedEntries, limit: decodedLimit)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(1, forKey: .version)
        try container.encode(limit, forKey: .limit)
        try container.encode(entries, forKey: .entries)
    }
}

/// 输入历史的落盘（`agent-input-history.json`）。
///
/// 与 `WorkspaceHistoryStore` 同一套路：一个 JSON、按需读写、坏了不致命 ——
/// 但**不静默**（`load()` 抛错，由调用方决定要不要说出来）。
public struct AgentInputHistoryStore: Sendable {

    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// 默认位置：应用数据目录下的 `agent-input-history.json`。
    public static func standard(applicationSupport: URL? = nil) -> AgentInputHistoryStore {
        let base = applicationSupport ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return AgentInputHistoryStore(
            fileURL: base
                .appendingPathComponent(DoyahIdentity.applicationSupportDirectoryName, isDirectory: true)
                .appendingPathComponent("agent-input-history.json", isDirectory: false)
        )
    }

    /// 读取。文件不存在 = 空历史（第一次启动就是这种状态）。
    public func load() throws -> AgentInputHistory {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return AgentInputHistory() }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return AgentInputHistory() }
        return try JSONDecoder().decode(AgentInputHistory.self, from: data)
    }

    /// 写入（原子替换；目录不存在时先建）。
    public func save(_ history: AgentInputHistory) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(history).write(to: fileURL, options: .atomic)
    }
}

// MARK: - 浏览状态机

/// 方向键里的哪一支（界面与判据共用一套字面量）。
public enum AgentComposerArrow: String, Sendable, Equatable, CaseIterable {
    case up
    case down
}

/// ↑↓ 浏览历史的**状态机**（纯值类型，无 IO、无 AppKit）。
///
/// 三条不变量（详设 §3.35 契约 ②⑤）：
/// 1. **草稿只在开始浏览的那一拍存一次**：`up` 从「不在浏览」进入时把当时的输入整段记下；
/// 2. **走到最旧就停**（再 ↑ 返回 `nil`，不循环到最新）；
/// 3. **回到草稿才退出浏览**（在最新一条上再 ↓ ⇒ 返回那份草稿；之后 ↓ 一律 `nil`）。
///
/// 返回 `nil` 的语义固定为「**这次按键不该被历史吃掉**」—— 调用方据此把键交还系统
/// （光标该怎么动就怎么动），不是「回填空串」。
public struct AgentInputHistoryNavigator: Equatable, Sendable {

    /// 开始浏览前的输入（`nil` = 还没开始浏览）。
    public private(set) var draft: String?

    /// 当前停在哪一条（`0` = 最旧；`nil` = 不在浏览）。
    public private(set) var index: Int?

    public init() {}

    public var isBrowsing: Bool { index != nil }

    /// ↑：往旧的一条走。返回**要填进输入框的文字**。
    public mutating func up(current: String, history: AgentInputHistory) -> String? {
        guard !history.isEmpty else { return nil }
        if index == nil {
            draft = current
            index = history.entries.count - 1
            return history.entries[history.entries.count - 1]
        }
        guard let currentIndex = index else { return nil }
        guard currentIndex > 0 else { return nil }   // 最旧了：停在原地，不循环
        index = currentIndex - 1
        return history.entries[currentIndex - 1]
    }

    /// ↓：往新的一条走；已经在新的一条上再按 ⇒ **回草稿并退出浏览**。
    ///
    /// 不在浏览（草稿态）时一律 `nil` —— 契约 ⑤「到草稿态再按 ↓ 什么都不做」。
    public mutating func down(current: String, history: AgentInputHistory) -> String? {
        guard let currentIndex = index else { return nil }
        if currentIndex + 1 < history.entries.count {
            index = currentIndex + 1
            return history.entries[currentIndex + 1]
        }
        // 最新一条上再 ↓ ⇒ 回草稿、退出浏览。`draft` 正常必有值；
        // 兜底取当前文本（等价于「这一步什么都不改」），不许凭空清空输入。
        let restored = draft ?? current
        draft = nil
        index = nil
        return restored
    }

    /// 退出浏览（发送 / 清空输入后调）：草稿一并丢掉，下一次 ↑ 重新记当时的输入。
    public mutating func reset() {
        draft = nil
        index = nil
    }
}

// MARK: - 方向键归属

/// 「这一次 ↑↓ 该归历史、还是归光标」的**唯一判定**（纯函数）。
///
/// 硬约束（详设 §3.35 契约 ①）：**不抢光标**。只有两处边界让历史接管：
/// - ↑ 且光标在**首行行首**（偏移 0）；
/// - ↓ 且光标在**末行行末**（偏移 == 文本长度）。
///
/// 其余位置（多行文本中间、有选区、输入法组字）一律交还系统光标移动 ——
/// 抢掉光标移动比没有历史更烦，所以这一条按「默认交出」写，而不是按「默认接管」。
public enum AgentComposerArrowRouter {

    /// - Parameters:
    ///   - caret: 光标 UTF-16 偏移（`NSTextView.selectedRange().location` 那套）。
    ///   - selectionLength: 选中长度（`> 0` ⇒ 有选区，方向键该改选区，不归历史）。
    ///   - overlayOpen: 候选浮层是否开着（斜杠命令候选条，`§3.35` 契约 ⑥：浮层开着时 ↑↓ 归浮层）。
    public static func takesHistory(_ arrow: AgentComposerArrow,
                                    text: String,
                                    caret: Int,
                                    selectionLength: Int = 0,
                                    overlayOpen: Bool = false) -> Bool {
        guard !overlayOpen else { return false }
        guard selectionLength == 0 else { return false }
        let length = (text as NSString).length
        guard caret >= 0, caret <= length else { return false }
        switch arrow {
        case .up: return caret == 0
        case .down: return caret == length
        }
    }
}
