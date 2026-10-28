import Foundation

/// 一次检索命中的一条记忆。
public struct AgentMemoryHit: Equatable, Sendable {
    public var entry: AgentMemoryEntry
    /// 命中的不同词数（0 = 没命中，不会出现在结果里）。
    public var score: Int
    /// 命中了哪几个词（**命中理由**，界面与提示词直接引用这串）。
    public var matchedTerms: [String]

    public init(entry: AgentMemoryEntry, score: Int, matchedTerms: [String]) {
        self.entry = entry
        self.score = score
        self.matchedTerms = matchedTerms
    }

    /// 人话理由：「命中：迁移、对账（2 处）」；没命中时为空串（不会出现这种结果）。
    public var reason: String {
        guard !matchedTerms.isEmpty else { return "" }
        return "命中：" + matchedTerms.joined(separator: "、") + "（\(score) 处）"
    }
}

/// 相关性检索（`FR-AGT-KNOW-MEM-007`）。
///
/// 四条口径，每条都对应一类做松的方式：
/// 1. **宁可少给**：零命中的一律不返回（不靠「最近用过」凑数 —— 那样相关的不相关的一起进上下文）；
/// 2. **命中理由**：每条带命中词，能回答「为什么它在这儿」；
/// 3. **新而无关不许挤掉相关**：先按命中数排，**时间只做同分平手**；
/// 4. **挑不出就是空**：返回空数组，不塞一条「最接近的」—— 空是如实的读数。
public enum AgentMemoryRetrieval {

    /// 切词：ASCII 词按非字母数字切、小写归一；CJK 连续段取 **2 字滑动窗口**（不引第三方分词，够用且可对拍）。
    public static func terms(from query: String) -> [String] {
        var out: [String] = []
        var ascii = ""
        var cjk: [Character] = []

        func flushASCII() {
            if ascii.count >= 2 { out.append(ascii.lowercased()) }
            ascii = ""
        }
        func flushCJK() {
            if cjk.count == 1 { out.append(String(cjk[0])) }
            if cjk.count >= 2 {
                for i in 0..<(cjk.count - 1) { out.append(String(cjk[i...(i + 1)])) }
            }
            cjk = []
        }

        for ch in query {
            if ch.isASCII, ch.isLetter || ch.isNumber {
                flushCJK(); ascii.append(ch)
            } else if isCJK(ch) {
                flushASCII(); cjk.append(ch)
            } else {
                flushASCII(); flushCJK()
            }
        }
        flushASCII(); flushCJK()
        // 去重但保序（同一个词在查询里出现两次，不该让分数翻倍）。
        var seen = Set<String>()
        return out.filter { seen.insert($0).inserted }
    }

    static func isCJK(_ ch: Character) -> Bool {
        guard let scalar = ch.unicodeScalars.first, ch.unicodeScalars.count == 1 else { return false }
        switch scalar.value {
        case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0xF900...0xFAFF: return true
        default: return false
        }
    }

    /// 检索：只回命中项。`limit` 是**上界**，实际可能更少（宁可少给）。
    public static func retrieve(_ entries: [AgentMemoryEntry],
                                query: String,
                                limit: Int = 8) -> [AgentMemoryHit] {
        let lookup = terms(from: query)
        guard !lookup.isEmpty, limit > 0 else { return [] }

        let hits: [AgentMemoryHit] = entries.compactMap { entry in
            let lower = entry.note.lowercased()
            var matched: [String] = []
            for term in lookup where lower.contains(term) { matched.append(term) }
            guard !matched.isEmpty else { return nil }
            return AgentMemoryHit(entry: entry, score: matched.count, matchedTerms: matched)
        }

        return hits.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.entry.lastUsedAt != rhs.entry.lastUsedAt { return lhs.entry.lastUsedAt > rhs.entry.lastUsedAt }
            return lhs.entry.id < rhs.entry.id
        }.prefix(limit).map { $0 }
    }

    /// 引用形态（进上下文用），路径里带上命中理由的关键词，模型在段标题上就看得出为什么带它。
    public static func references(_ hits: [AgentMemoryHit]) -> [AgentContextReference] {
        hits.map { AgentMemoryContext.reference(for: $0.entry) }
    }
}

public extension AgentMemoryRetrieval {

    /// 进上下文的入口：**先按 `FR-AI-15` 滤掉该忘的，再按相关性挑**（两步都在 Core，界面不重挑）。
    ///
    /// 与既有 `AgentMemoryContext.references` 的差别只有一个：**带查询**。
    /// 因此它同样产出 `AgentContextReference`，不绕过 `AgentContextAssembler`。
    static func references(from entries: [AgentMemoryEntry],
                           query: String,
                           now: Date,
                           limit: Int = 8,
                           calendar: Calendar = .current) -> [AgentContextReference] {
        let retained = entries.filter { entry in
            guard entry.memoryKind != nil else { return false }
            guard let explanation = AgentMemoryReasons.describe(entry: entry, now: now, calendar: calendar) else {
                return false
            }
            return explanation.isRetained
        }
        return references(retrieve(retained, query: query, limit: limit))
    }
}
