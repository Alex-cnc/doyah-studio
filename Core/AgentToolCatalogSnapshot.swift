import Foundation

/// **注册表唯一真源 + 可见性由 profile 决定**（详设 §3.22 · `FR-AGT-CORE-LOOP-005/-011` · 本端计划 P1-10）。
///
/// 三条不许踩的线：
/// ① 每个工具只有**一处**声明（同名两处 ⇒ 装载期直接拒绝，不取后者）；
/// ② 可见性只决定「能不能被发现与调用」，**不决定实现是哪一份**（终端壳与图形壳指向同一 fingerprint）；
/// ③ 「没登记」与「本 profile 不可见」是**两种提示**，不许把后者伪装成前者。
public enum AgentProfileKind: String, Codable, Sendable, CaseIterable {
    case terminalShell
    case graphicalShell
    case subagent
}

public enum AgentToolSource: String, Codable, Sendable {
    case builtin
    case mcp
}

public struct AgentToolCatalogEntry: Equatable, Sendable {
    public var name: String
    public var source: AgentToolSource
    public var visible: Bool
    /// 实现身份：同一工具在两个壳里必须相同 —— 壳只决定看得见，不决定能力。
    public var fingerprint: String

    public init(name: String, source: AgentToolSource, visible: Bool, fingerprint: String) {
        self.name = name
        self.source = source
        self.visible = visible
        self.fingerprint = fingerprint
    }
}

public enum AgentToolCatalogRefusal: Error, Equatable, Sendable {
    /// 名字未登记 —— 「没有这个工具」。
    case toolNotRegistered(String)
    /// 已登记但本 profile 不可见 —— 与上一条是**不同信息**。
    case toolNotVisibleInProfile(String, AgentProfileKind)
    /// schema 未取回就调用 —— 先取 schema 再调。
    case schemaNotFetched(String)
}

public enum AgentToolCatalogError: Error, Equatable, Sendable {
    /// 同名两处声明：停装载，不取后者。
    case duplicateDeclaration(String)
}

public struct ToolCatalogSnapshot: Equatable, Sendable {
    public var entries: [AgentToolCatalogEntry]
    public var omittedCount: Int
    /// 注册表指纹（装载那一刻定下；会话期内不可变，重载才变）。
    public var registryFingerprint: String

    public init(entries: [AgentToolCatalogEntry], omittedCount: Int, registryFingerprint: String) {
        self.entries = entries
        self.omittedCount = omittedCount
        self.registryFingerprint = registryFingerprint
    }

    public func entry(named name: String) -> AgentToolCatalogEntry? {
        entries.first { $0.name == name }
    }

    public var visibleNames: [String] {
        entries.filter(\.visible).map(\.name)
    }
}

/// 装载一次注册表 + 每 profile 的可见白名单（空集 = 继承全量）。
public struct AgentToolCatalog: Sendable {
    private let definitions: [AgentToolDefinition]
    private let visibility: [AgentProfileKind: Set<String>]
    /// `nil` = schema 全部视为已取回；否则只认集合里的（`FR-AGT-CORE-LOOP-010` 的按需发现）。
    private let schemaFetched: Set<String>?
    public let registryFingerprint: String

    /// - Throws: `AgentToolCatalogError.duplicateDeclaration(name)` —— 装载期即拒。
    public init(registry: AgentToolRegistry,
                visibility: [AgentProfileKind: Set<String>] = [:],
                schemaFetched: Set<String>? = nil) throws {
        var seen = Set<String>()
        for definition in registry.definitions {
            guard seen.insert(definition.name).inserted else {
                throw AgentToolCatalogError.duplicateDeclaration(definition.name)
            }
        }
        self.definitions = registry.definitions
        self.visibility = visibility
        self.schemaFetched = schemaFetched
        self.registryFingerprint = registry.definitions.map(\.fingerprint).joined(separator: "|")
    }

    private func isVisible(_ definition: AgentToolDefinition, in profile: AgentProfileKind) -> Bool {
        guard definition.enabled else { return false }
        guard let allow = visibility[profile], !allow.isEmpty else { return true }
        return allow.contains(definition.name)
    }

    /// 不可变快照：同一 profile 同一指纹 ⇒ 同一内容（幂等）。
    public func snapshot(for profile: AgentProfileKind) -> ToolCatalogSnapshot {
        let entries = definitions.compactMap { definition -> AgentToolCatalogEntry? in
            let visible = isVisible(definition, in: profile)
            // 不可见的工具不进快照（快照是「这一壳能用的目录」）—— 但 resolve 会区分「不可见 vs 没登记」。
            guard visible else { return nil }
            return AgentToolCatalogEntry(name: definition.name,
                                         source: definition.capability == .mcpTool ? .mcp : .builtin,
                                         visible: true,
                                         fingerprint: definition.fingerprint)
        }
        let omitted = definitions.count - entries.count
        return ToolCatalogSnapshot(entries: entries, omittedCount: omitted, registryFingerprint: registryFingerprint)
    }

    /// 解析一次调用：四种拒绝各有各的说法。
    public func resolve(_ name: String, for profile: AgentProfileKind) -> Result<AgentToolCatalogEntry, AgentToolCatalogRefusal> {
        guard let definition = definitions.first(where: { $0.name == name }) else {
            return .failure(.toolNotRegistered(name))
        }
        guard isVisible(definition, in: profile) else {
            return .failure(.toolNotVisibleInProfile(name, profile))
        }
        if let fetched = schemaFetched, !fetched.contains(name) {
            return .failure(.schemaNotFetched(name))
        }
        return .success(AgentToolCatalogEntry(name: definition.name,
                                             source: definition.capability == .mcpTool ? .mcp : .builtin,
                                             visible: true,
                                             fingerprint: definition.fingerprint))
    }

    /// 同一工具在两个壳里是否指向同一实现（判据 T-3.22-03 的直接依据）。
    public func sharesImplementation(_ name: String, _ a: AgentProfileKind, _ b: AgentProfileKind) -> Bool {
        guard let ea = try? resolve(name, for: a).get(), let eb = try? resolve(name, for: b).get() else {
            return false
        }
        return ea.fingerprint == eb.fingerprint
    }
}
