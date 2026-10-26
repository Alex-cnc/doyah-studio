import Foundation

/// **语句级判定收口**（`FR-AGT-GUARD-PERM-004` / 本端计划 P2-4）：危险语句判红、注入内容不当指令。
///
/// 两件事分开：
/// ① `AgentSQLStatementJudge` —— 一条 SQL 该不该被拒 / 该不该走审批（纯文本判定，不连库）；
/// ② `AgentInjectionGuard` —— **来源决定它是不是指令**：只有用户输入是指令，
///    工具输出 / 文件 / 网页里的「ignore previous instructions」是**数据**，不许升级成命令。
public enum AgentSQLRisk: String, Equatable, Sendable, CaseIterable {
    case safe
    case needsApproval
    case blocked

    /// 取更严的那个（多语句 / 多判定合流时用）。
    public static func combine(_ risks: [AgentSQLRisk]) -> AgentSQLRisk {
        if risks.contains(.blocked) { return .blocked }
        if risks.contains(.needsApproval) { return .needsApproval }
        return .safe
    }
}

public enum AgentSQLStatementJudge {

    /// 拆语句（按 `;` 切，忽略空段）。引号内的分号本判据不处理 —— 那是切分器的活（详设 §3.12），
    /// 这里刻意保守：宁可多切一段，也不漏判一条危险语句。
    public static func statements(_ sql: String) -> [String] {
        sql.split(separator: ";").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    public static func judge(_ sql: String) -> AgentSQLRisk {
        let parts = statements(sql)
        guard !parts.isEmpty else { return .safe }
        return AgentSQLRisk.combine(parts.map(judgeSingle))
    }

    public static func judgeSingle(_ statement: String) -> AgentSQLRisk {
        let s = statement
            .uppercased()
            .split(whereSeparator: { $0.isWhitespace || $0 == "\n" })
            .joined(separator: " ")
        guard !s.isEmpty else { return .safe }

        // 直接判红：整库 / 整 schema / 清表 / 无 WHERE 的删除与更新
        if s.contains("DROP DATABASE") || s.contains("DROP SCHEMA") { return .blocked }
        if s.hasPrefix("TRUNCATE") { return .blocked }
        if s.hasPrefix("DELETE") && !s.contains(" WHERE ") { return .blocked }
        if s.hasPrefix("UPDATE") && !s.contains(" WHERE ") { return .blocked }
        // 提权 / 落盘 / 执行外部程序
        if s.contains("COPY ") && s.contains(" PROGRAM ") { return .blocked }
        if s.contains("PG_READ_FILE") || s.contains("PG_READ_BINARY_FILE") { return .blocked }

        // 走审批：结构变更与写入
        for keyword in ["INSERT", "UPDATE", "DELETE", "CREATE ", "ALTER ", "DROP ", "GRANT ", "REVOKE ", "REINDEX", "VACUUM FULL"] {
            if s.hasPrefix(keyword) { return .needsApproval }
        }
        // 只读查询
        for keyword in ["SELECT", "WITH", "EXPLAIN", "SHOW", "DESCRIBE", "PRAGMA", "VALUES", "TABLE "] {
            if s.hasPrefix(keyword) { return .safe }
        }
        // 认不出来的，按需审批（不按安全放行 —— 判据宁严）
        return .needsApproval
    }
}

/// 文本的**来源**：只有 `.userInput` 是指令。
public enum AgentTextOrigin: String, Sendable, CaseIterable {
    case userInput
    case toolOutput
    case fileContent
    case webContent
    case modelOutput
}

public struct AgentInjectionVerdict: Equatable, Sendable {
    /// 这段文本能不能被当成「要执行的指令」。
    public var isInstruction: Bool
    /// 里面是否有注入标记（数据里出现也算——只是不升级成指令）。
    public var flagged: Bool
    /// 命中的标记（审计用）。
    public var markers: [String]
}

public enum AgentInjectionGuard {

    /// 常见注入开场（小写匹配）。命中**不等于**执行：只让上层知道「这段数据想当指令」。
    static let markers: [String] = [
        "ignore previous instructions",
        "ignore all previous",
        "disregard the above",
        "you are now",
        "system prompt",
        "new instructions:",
        "忽略之前",
        "忽略上述",
        "你的新角色",
    ]

    public static func markers(in text: String) -> [String] {
        let lower = text.lowercased()
        return markers.filter { lower.contains($0) }
    }

    /// 判决：只有用户输入是指令；其余来源里的注入文本仍是数据。
    public static func verdict(_ text: String, origin: AgentTextOrigin) -> AgentInjectionVerdict {
        let hits = markers(in: text)
        return AgentInjectionVerdict(isInstruction: origin == .userInput,
                                     flagged: !hits.isEmpty,
                                     markers: hits)
    }

    public static func isInstruction(_ text: String, origin: AgentTextOrigin) -> Bool {
        verdict(text, origin: origin).isInstruction
    }

    /// 把非指令来源的文本包成「数据块」，让模型看得见边界（不删原文，用户可能要看）。
    public static func wrapAsData(_ text: String, origin: AgentTextOrigin) -> String {
        guard origin != .userInput else { return text }
        return "<<<DATA origin=\(origin.rawValue)>>>\n\(text)\n<<<END DATA>>>"
    }
}
