import Foundation

/// **知识治理**（`FR-AGT-KNOW-MEM-002/003/004/005` / 本端计划 P3-3~6）：
/// 记忆与技能候选都必须**可检视、可解释、可删除**，且**删除即真删**。
///
/// 「真删」的口径：删完在集合里查不到、导出里也不出现 —— 不是打一个 `deleted: true` 标记继续留着。
public enum AgentMemoryKind: String, Codable, Sendable, CaseIterable {
    /// 用户偏好（「回答用中文」这类）。
    case preference
    /// 事实（产品/环境/仓库口径）。
    case fact
    /// 约束（不许改某目录、只读模式…）。
    case constraint
    /// 技能候选（从对话里参数化抽出来的可复用步骤）。
    case skillCandidate
}

public struct AgentMemoryItem: Equatable, Sendable, Identifiable {
    public var id: String
    public var kind: AgentMemoryKind
    /// 归一化后的键（同一键只留一条）。
    public var key: String
    public var value: String
    /// 来源（哪一轮、哪句话）：解释时要说得出「从哪来」。
    public var source: String
    public var createdAt: Date

    public init(id: String, kind: AgentMemoryKind, key: String, value: String, source: String, createdAt: Date = Date()) {
        self.id = id
        self.kind = kind
        self.key = key
        self.value = value
        self.source = source
        self.createdAt = createdAt
    }
}

public enum AgentMemoryGovernanceError: Error, Equatable, Sendable {
    case notFound(String)
    case emptyValue
    case emptyKey
}

public struct AgentMemoryGovernance: Sendable {
    private(set) var items: [AgentMemoryItem]

    public init(items: [AgentMemoryItem] = []) {
        self.items = items
    }

    // MARK: 检视

    /// 全部条目（按 kind、再按 key 稳定排序 —— 两次导出逐字相同）。
    public func list() -> [AgentMemoryItem] {
        items.sorted { lhs, rhs in
            if lhs.kind.rawValue != rhs.kind.rawValue { return lhs.kind.rawValue < rhs.kind.rawValue }
            return lhs.key < rhs.key
        }
    }

    public func list(kind: AgentMemoryKind) -> [AgentMemoryItem] {
        list().filter { $0.kind == kind }
    }

    public func item(id: String) -> AgentMemoryItem? {
        items.first { $0.id == id }
    }

    /// **可解释**：一句话说清「这条是什么、从哪来、什么时候」。
    public func explain(id: String) -> String? {
        guard let item = item(id: id) else { return nil }
        return "\(item.kind.rawValue)/\(item.key) = \(item.value) ← \(item.source)"
    }

    // MARK: 写入（同键覆盖，不留副本）

    @discardableResult
    public mutating func upsert(kind: AgentMemoryKind, key: String, value: String,
                                source: String, id: String? = nil,
                                createdAt: Date = Date()) throws -> AgentMemoryItem {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw AgentMemoryGovernanceError.emptyKey }
        guard !trimmedValue.isEmpty else { throw AgentMemoryGovernanceError.emptyValue }
        items.removeAll { $0.kind == kind && $0.key == trimmedKey }
        let item = AgentMemoryItem(id: id ?? "\(kind.rawValue):\(trimmedKey)",
                                   kind: kind, key: trimmedKey, value: trimmedValue,
                                   source: source, createdAt: createdAt)
        items.append(item)
        return item
    }

    // MARK: 删除（真删）

    /// 删一条：返回是否真删掉。删完 `item(id:)` 必为 nil。
    @discardableResult
    public mutating func delete(id: String) -> Bool {
        let before = items.count
        items.removeAll { $0.id == id }
        return items.count != before
    }

    /// 按类别清空（「忘掉所有偏好」这类请求）—— 同样真删。
    @discardableResult
    public mutating func deleteAll(kind: AgentMemoryKind) -> Int {
        let before = items.count
        items.removeAll { $0.kind == kind }
        return before - items.count
    }

    // MARK: 技能候选（参数化抽取）

    /// 从一串「做过的步骤」里抽技能候选：把**具体参数**换成占位符，只留步骤骨架。
    ///
    /// 例：`["swift test --filter AgentX", "swift test --filter AgentY"]`
    ///   ⇒ 候选「swift test --filter <name>」（出现 2 次以上才算候选）。
    public func skillCandidates(from commands: [String], minimumOccurrences: Int = 2,
                                source: String = "run-history") -> [AgentMemoryItem] {
        var patterns: [String: Int] = [:]
        for command in commands {
            let pattern = Self.parameterize(command)
            patterns[pattern, default: 0] += 1
        }
        return patterns
            .filter { $0.value >= minimumOccurrences }
            .sorted { $0.key < $1.key }   // 稳定输出
            .map { pattern, count in
                AgentMemoryItem(id: "skill:\(pattern)", kind: .skillCandidate,
                                key: pattern, value: "used \(count) times", source: source)
            }
    }

    /// 把一串命令里「看起来像具体值」的 token 换成占位符（纯文本、可判据）。
    public static func parameterize(_ command: String) -> String {
        let tokens = command.split(separator: " ").map(String.init)
        var out: [String] = []
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            let previous = index > 0 ? tokens[index - 1] : ""
            if previous.hasPrefix("-") && !token.hasPrefix("-") && !token.hasPrefix("/") {
                out.append("<value>")
            } else if token.hasPrefix("/") {
                out.append("<path>")
            } else if token.hasSuffix(".swift") || token.hasSuffix(".kt") {
                out.append("<file>")
            } else {
                out.append(token)
            }
            index += 1
        }
        return out.joined(separator: " ")
    }

    /// 导出（给界面「可检视」用）：每行一条，稳定排序。
    public func export() -> String {
        list().map { "\($0.kind.rawValue)\t\($0.key)\t\($0.value)\t\($0.source)" }.joined(separator: "\n")
    }
}
