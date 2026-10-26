import Foundation

/// **上下文压缩落地**（`FR-AGT-KNOW-CTX-002` / 本端计划 P3-2）：超预算按**段优先级**截断并标记。
///
/// 三条判据：
/// ① 截断处**可见**（报告里点名丢了哪几段 + 一句标记）；
/// ② 两次压缩结果**一致**（纯函数、稳定排序，不许靠 Map 遍历顺序）；
/// ③ 高优先级段（约束 / 决策 / 待办）先保，低优先级（冗长正文 / 重复工具结果）先丢。
public enum AgentContextSectionPriority: Int, Comparable, Sendable, CaseIterable {
    /// 灵魂条款 / 审批结论 / 未完成待办 —— **永不丢**。
    case critical = 0
    /// 决策与被采纳的方案。
    case high = 1
    /// 常规上下文（文件片段、查询结果）。
    case normal = 2
    /// 冗长正文 / 重复工具结果 —— 先丢。
    case low = 3

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct AgentContextBudgetedSection: Equatable, Sendable {
    public var id: String
    public var priority: AgentContextSectionPriority
    public var body: String

    public init(id: String, priority: AgentContextSectionPriority, body: String) {
        self.id = id
        self.priority = priority
        self.body = body
    }

    public var characterCount: Int { body.count }
}

public struct AgentContextTruncationReport: Equatable, Sendable {
    public var keptIDs: [String]
    public var droppedIDs: [String]
    public var charactersBefore: Int
    public var charactersAfter: Int
    /// 界面可见的截断标记（空串 = 没截）。
    public var marker: String
    /// 有段因预算被丢 ⇒ true。
    public var didTruncate: Bool { !droppedIDs.isEmpty }

    public init(keptIDs: [String], droppedIDs: [String], charactersBefore: Int,
                charactersAfter: Int, marker: String) {
        self.keptIDs = keptIDs
        self.droppedIDs = droppedIDs
        self.charactersBefore = charactersBefore
        self.charactersAfter = charactersAfter
        self.marker = marker
    }
}

public enum AgentContextPriorityTruncator {

    /// 按优先级截断到 `maxCharacters`。
    ///
    /// 顺序：`critical` 无条件保留（即使因此超预算 —— 宁可超，也不丢约束）；
    /// 其余按 `(priority, 原序)` 依次装入，装不下的丢。
    public static func truncate(_ sections: [AgentContextBudgetedSection],
                                maxCharacters: Int) -> (kept: [AgentContextBudgetedSection],
                                                        report: AgentContextTruncationReport) {
        let before = sections.reduce(0) { $0 + $1.characterCount }
        var kept: [AgentContextBudgetedSection] = []
        var dropped: [AgentContextBudgetedSection] = []
        var used = 0

        // critical 先全部保留（原序）
        for section in sections where section.priority == .critical {
            kept.append(section)
            used += section.characterCount
        }
        // 其余按优先级升序、同优先级按原序
        let ordered = sections.enumerated()
            .filter { $0.element.priority != .critical }
            .sorted { lhs, rhs in
                if lhs.element.priority != rhs.element.priority {
                    return lhs.element.priority < rhs.element.priority
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)

        for section in ordered {
            if used + section.characterCount <= maxCharacters {
                kept.append(section)
                used += section.characterCount
            } else {
                dropped.append(section)
            }
        }

        // 输出按**原序**（确定性：同一输入两次结果逐字相同）
        let keptIDs = sections.map(\.id).filter { id in kept.contains { $0.id == id } }
        let droppedIDs = sections.map(\.id).filter { id in dropped.contains { $0.id == id } }
        let after = kept.reduce(0) { $0 + $1.characterCount }
        let marker = droppedIDs.isEmpty ? "" : "[truncated \(droppedIDs.count) sections: \(droppedIDs.joined(separator: ","))]"
        let report = AgentContextTruncationReport(keptIDs: keptIDs,
                                                  droppedIDs: droppedIDs,
                                                  charactersBefore: before,
                                                  charactersAfter: after,
                                                  marker: marker)
        return (sections.filter { keptIDs.contains($0.id) }, report)
    }
}
