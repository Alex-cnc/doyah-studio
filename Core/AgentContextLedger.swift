import Foundation

/// 上下文里的一段是什么（`FR-AGT-KNOW-MEM-009`）。
public enum AgentContextSegmentKind: String, Equatable, Sendable, CaseIterable {
    case systemPrompt
    case memory
    case projectRule
    case file
    case toolResult
    case history
    case other
}

/// 账本的一行：**这一段是谁、占多少字、估多少 token、占几成、有没有被截**。
public struct AgentContextLedgerRow: Equatable, Sendable {
    public var kind: AgentContextSegmentKind
    public var title: String
    public var characters: Int
    public var estimatedTokens: Int
    /// 占总量比例（0…1）；总量为 0 时为 0。
    public var share: Double
    public var truncated: Bool

    public init(kind: AgentContextSegmentKind, title: String, characters: Int,
                estimatedTokens: Int, share: Double, truncated: Bool) {
        self.kind = kind
        self.title = title
        self.characters = characters
        self.estimatedTokens = estimatedTokens
        self.share = share
        self.truncated = truncated
    }
}

/// 上下文预算账本：**只读的一份读数**，不参与装配（装配仍在 `AgentContextAssembler`）。
public struct AgentContextLedger: Equatable, Sendable {
    public var rows: [AgentContextLedgerRow]
    public var totalTokens: Int
    public var budgetTokens: Int
    /// 因预算被整段丢掉的标题（**逐条点名**，不静默）。
    public var droppedTitles: [String]
    /// 丢完还超（该说「超了」而不是假装没超）。
    public var isOverBudget: Bool

    public var isEmpty: Bool { rows.isEmpty }
}

/// token 估算（**只用于账本读数**，不是计费口径；口径写在这里，别处不许各算一遍）。
///
/// - CJK 字符按 **1 字 = 1 token**（偏保守地高估一点点）；
/// - 其余字符按 **4 字 = 1 token** 向上取整；
/// 估不准不装准：账本只回答「谁占得多」，不回答「账单是多少」。
public enum AgentTokenEstimator {

    public static func tokens(_ text: String) -> Int {
        var cjk = 0
        var other = 0
        for ch in text {
            if let scalar = ch.unicodeScalars.first,
               ch.unicodeScalars.count == 1,
               (0x4E00...0x9FFF).contains(scalar.value)
                || (0x3400...0x4DBF).contains(scalar.value)
                || (0xF900...0xFAFF).contains(scalar.value) {
                cjk += 1
            } else {
                other += 1
            }
        }
        return cjk + (other + 3) / 4
    }
}

public enum AgentContextLedgerBuilder {

    /// 参考段来自 `AgentContextReference`，额外段（系统提示 / 历史 / 工具结果）由调用方以纯文本给。
    public static func build(references: [AgentContextReference],
                             extra: [(kind: AgentContextSegmentKind, title: String, text: String)] = [],
                             limits: AgentContextLimits = AgentContextLimits(),
                             budgetTokens: Int = 32_000) -> AgentContextLedger {
        var rows: [AgentContextLedgerRow] = []

        // 参考段：**借用装配那一处**的裁剪结果（同一套口径，不另算一遍）。
        for reference in references {
            let section = AgentContextAssembler.section(for: reference, limits: limits)
            rows.append(AgentContextLedgerRow(kind: kind(of: reference),
                                              title: section.title,
                                              characters: section.outgoing.count,
                                              estimatedTokens: AgentTokenEstimator.tokens(section.outgoing),
                                              share: 0,
                                              truncated: section.truncated))
        }
        // 额外段：调用方给什么算什么（系统提示、历史、工具结果）。
        for item in extra {
            rows.append(AgentContextLedgerRow(kind: item.kind,
                                              title: item.title,
                                              characters: item.text.count,
                                              estimatedTokens: AgentTokenEstimator.tokens(item.text),
                                              share: 0,
                                              truncated: false))
        }

        var dropped: [String] = []
        var kept = rows
        var total = kept.reduce(0) { $0 + $1.estimatedTokens }

        // 超预算：**从最后一段开始整段丢**（与装配「先保证前面」的口径一致），逐条点名。
        while total > budgetTokens, kept.count > 1, let last = kept.popLast() {
            dropped.insert(last.title, at: 0)
            total -= last.estimatedTokens
        }

        let isOverBudget = total > budgetTokens
        let denominator = max(total, 1)
        let withShare = kept.map { row -> AgentContextLedgerRow in
            var copy = row
            copy.share = Double(row.estimatedTokens) / Double(denominator)
            return copy
        }

        return AgentContextLedger(rows: withShare,
                                  totalTokens: total,
                                  budgetTokens: budgetTokens,
                                  droppedTitles: dropped,
                                  isOverBudget: isOverBudget)
    }

    /// 段类型按**来源**判，不按标题字符串猜。
    public static func kind(of reference: AgentContextReference) -> AgentContextSegmentKind {
        switch reference {
        case .projectRule: return .projectRule
        case .terminalTail, .schemaSummary, .gitState: return .toolResult
        case .file(let path, _): return path.hasPrefix(AgentMemoryContext.pathScheme + "://") ? .memory : .file
        case .directory, .selection: return .file
        case .activeTab: return .other
        }
    }

    /// 人读的一行（界面与「为什么它占这么多」共用同一句）。
    public static func describe(_ row: AgentContextLedgerRow) -> String {
        let percent = Int((row.share * 100).rounded())
        let suffix = row.truncated ? "（已截断）" : ""
        return "\(row.title) · \(row.estimatedTokens) token · \(percent)%\(suffix)"
    }
}
