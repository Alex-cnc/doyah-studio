import Foundation

/// 工具按需发现（`FR-AGT-CORE-LOOP-010`）。
///
/// 口径（三句）：
/// ① 模型**先检索目录**（`search`）再**取回 schema**（`fetchSchema`），最后才 `call`；
/// ② **没取回 schema 就调用 ⇒ 拒**（`schemaNotFetched`），不是靠提示词求它别乱调；
/// ③ 目录空 / 查不到 ⇒ **如实说没有**（`emptyCatalog` / `noMatch`），不许编一个像模像样的工具出来。
public struct AgentToolDescriptor: Equatable, Sendable {
    public var id: String
    public var summary: String
    public var tags: [String]
    /// 参数 schema（JSON 文本；`fetchSchema` 才交出去）。
    public var schemaJSON: String

    public init(id: String, summary: String, tags: [String] = [], schemaJSON: String) {
        self.id = id
        self.summary = summary
        self.tags = tags
        self.schemaJSON = schemaJSON
    }
}

public enum AgentToolDiscoveryError: Error, Equatable, Sendable {
    case emptyCatalog
    case noMatch(String)
    case unknownTool(String)
    /// 没取 schema 就想调 —— 循环里最常见的一类「看着像在干活」。
    case schemaNotFetched(String)
}

public struct AgentToolCall: Equatable, Sendable {
    public var toolID: String
    public var argumentsJSON: String
    public init(toolID: String, argumentsJSON: String) {
        self.toolID = toolID
        self.argumentsJSON = argumentsJSON
    }
}

/// 目录 + 会话内「已取回 schema」的记账。
public struct AgentToolDiscovery: Sendable {
    private let catalog: [AgentToolDescriptor]
    private var fetched: Set<String> = []

    public init(catalog: [AgentToolDescriptor]) {
        self.catalog = catalog
    }

    /// 检索：按 id / 摘要 / 标签做包含匹配，大小写不敏感；空查询返回全部摘要级条目。
    public func search(_ query: String) throws -> [AgentToolDescriptor] {
        guard !catalog.isEmpty else { throw AgentToolDiscoveryError.emptyCatalog }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return catalog }
        let hits = catalog.filter { tool in
            tool.id.lowercased().contains(q)
                || tool.summary.lowercased().contains(q)
                || tool.tags.contains { $0.lowercased().contains(q) }
        }
        guard !hits.isEmpty else { throw AgentToolDiscoveryError.noMatch(query) }
        return hits
    }

    /// 取 schema：取回后本会话记为可用。
    public mutating func fetchSchema(_ id: String) throws -> AgentToolDescriptor {
        guard let tool = catalog.first(where: { $0.id == id }) else {
            throw AgentToolDiscoveryError.unknownTool(id)
        }
        fetched.insert(id)
        return tool
    }

    public func hasFetchedSchema(_ id: String) -> Bool { fetched.contains(id) }

    /// 调用：**没取 schema 一律拒**；取过才放行（真正的执行由调度器接）。
    public func authorize(_ call: AgentToolCall) throws -> AgentToolCall {
        guard catalog.contains(where: { $0.id == call.toolID }) else {
            throw AgentToolDiscoveryError.unknownTool(call.toolID)
        }
        guard fetched.contains(call.toolID) else {
            throw AgentToolDiscoveryError.schemaNotFetched(call.toolID)
        }
        return call
    }
}
