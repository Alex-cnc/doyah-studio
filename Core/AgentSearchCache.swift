import Foundation

/// **同一轮里的搜索缓存**（2026-11-07 真机读数：一轮 26 步 / 149.6 秒、56 次工具调用，其中
/// `search` 被反复调用，参数是**近义改写**：`会话时间太长` / `会话超时` / `会话时间` / `会话` /
/// `界面错误` / `界面` …… 每个 1.4–1.8 秒，因为每一次都是**全仓扇扫**。
///
/// 为什么精确去重（`AgentRepeatGuard` 按 (工具, 参数) 比对）拦不住：换个词就是另一条参数。
/// 这一层按**词的语义包含关系**认领：
/// · 同一个词再搜 ⇒ 直接命中（毫秒级，不再扫盘）；
/// · 已搜过 `会话时间太长`，再搜 `会话时间` ⇒ 从缓存命中里挑出含这个子串的那些，
///   标注 `cached` + `partial`（**覆盖不全**，够给结论就够用；要全量再单独搜一次）；
/// · 缓存只在**同一轮**里有意义：`AgentWorkspaceTools` 每轮新造一份，写 / 执行则立即作废。
///
/// 口径只在 `WorkspaceSearch` 那一处（`normalize` / `matches`）：这一层不另写一套包含判断。
public final class AgentSearchCache: @unchecked Sendable {

    public struct Policy: Equatable, Sendable {
        /// 存活时间：超过就当没缓存过（默认 60 秒 —— 一轮里够用，也不会让上一轮的结果冒充这一轮）。
        public var ttl: TimeInterval
        /// 最多记多少条词（防止一路搜下去把内存吃光）。
        public var maxEntries: Int

        public init(ttl: TimeInterval = 60, maxEntries: Int = 64) {
            self.ttl = ttl
            self.maxEntries = maxEntries
        }
    }

    /// 一次缓存命中（针对一个词）。
    public struct Hit: Equatable, Sendable {
        /// 缓存里那一次搜索的**原词**（界面 / 回灌要说清「这是从哪次搜索捡来的」）。
        public var source: String
        /// `true` = 词完全一致；`false` = 包含关系（缓存的是更宽或更窄的词）⇒ 覆盖不全。
        public var exact: Bool
        public var fileNames: [String]
        public var contentHits: [String]
        public var truncated: Bool

        public init(source: String, exact: Bool, fileNames: [String],
                    contentHits: [String], truncated: Bool) {
            self.source = source
            self.exact = exact
            self.fileNames = fileNames
            self.contentHits = contentHits
            self.truncated = truncated
        }
    }

    private struct Entry {
        var query: String
        var normalized: String
        var fileNames: [String]
        var contentHits: [String]
        var truncated: Bool
        var at: Date
    }

    public let policy: Policy
    private var entries: [Entry] = []
    private let lock = NSLock()

    public init(policy: Policy = Policy()) {
        self.policy = policy
    }

    /// 查：按给出的词逐个找缓存（先精确、再包含关系）；没有的**不返回**（调用方去扫盘）。
    ///
    /// 返回的键是**归一后的词**（与 `WorkspaceSearch.normalize` 同一口径），值是该词的命中。
    public func lookup(_ queries: [String], at now: Date = Date()) -> [String: Hit] {
        lock.lock(); defer { lock.unlock() }
        pruneLocked(now: now)

        var hits: [String: Hit] = [:]
        for query in queries {
            let word = WorkspaceSearch.normalize(query: query)
            guard !word.isEmpty, let entry = bestEntryLocked(for: word) else { continue }
            // 包含关系要**再筛一遍**：缓存的是更长的词时，它的命中必然含更短的词（筛完不丢）；
            // 缓存的是更短的词时，只能留下**同时含这次这个词**的那些行（这就是「部分」的含义）。
            hits[word] = Hit(source: entry.query,
                             exact: entry.normalized == word,
                             fileNames: entry.fileNames.filter { Self.contains($0, word: word) },
                             contentHits: entry.contentHits.filter { Self.contains($0, word: word) },
                             truncated: entry.truncated)
        }
        return hits
    }

    /// 记一次搜索（同一个词覆盖旧条目）。
    public func store(query: String, fileNames: [String], contentHits: [String],
                      truncated: Bool, at now: Date = Date()) {
        lock.lock(); defer { lock.unlock() }
        let word = WorkspaceSearch.normalize(query: query)
        guard !word.isEmpty else { return }
        entries.removeAll { $0.normalized == word }
        entries.append(Entry(query: query, normalized: word, fileNames: fileNames,
                             contentHits: contentHits, truncated: truncated, at: now))
        if entries.count > policy.maxEntries {
            entries.removeFirst(entries.count - policy.maxEntries)
        }
    }

    /// 磁盘变了（写 / 执行）⇒ 旧命中一律作废。
    public func invalidate() {
        lock.lock(); defer { lock.unlock() }
        entries.removeAll()
    }

    /// 现在记着几条（读数口：探针 / 日志要能说「缓存有没有真被用上」）。
    public var count: Int {
        lock.lock(); defer { lock.unlock() }
        return entries.count
    }

    // MARK: - 内部

    private func bestEntryLocked(for word: String) -> Entry? {
        if let exact = entries.first(where: { $0.normalized == word }) { return exact }
        // 优先「更长且包含这个词」的那一条：越具体，筛完漏得越少。
        if let wider = entries.filter({ $0.normalized.contains(word) })
            .max(by: { $0.normalized.count < $1.normalized.count }) {
            return wider
        }
        // 反方向（缓存的是更短的词）：仍能捞出「同时含这次这个词」的一部分命中。
        return entries.filter { word.contains($0.normalized) }
            .max(by: { $0.normalized.count < $1.normalized.count })
    }

    private func pruneLocked(now: Date) {
        guard policy.ttl > 0 else { entries.removeAll(); return }
        entries.removeAll { now.timeIntervalSince($0.at) > policy.ttl }
    }

    private static func contains(_ text: String, word: String) -> Bool {
        WorkspaceSearch.matches(text, normalizedQuery: word)
    }
}
