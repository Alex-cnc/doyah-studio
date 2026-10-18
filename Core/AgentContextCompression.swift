import Foundation

/// `NFR-AI-08` ③（**压缩半**）：上下文超限时的**有损但如实**压缩。
///
/// 契约只钉两件事，压缩算法与阈值是参数：
/// 1. **有损** —— 该丢的丢，不能因为「怕丢」就把超限的正文照发（那会撞模型窗口）；
/// 2. **如实** —— 丢了**几条**、丢了**哪些**（逐条摘要）、大约**省了多少 token**，都要报得出来
///    （`R-63` ③ 的负例：压缩后既不报、又不答「丢了哪些」）。
///
/// 形状是**纯函数**：给定「已有正文长度 + 观察条目 + 预算」⇒ 结果只由入参决定，不读钟、不读盘。
/// 判据因此可以逐条断言（`Tests/AgentContextCompressionTests.swift`），不必真连一个模型。
///
/// 边界：**只压「上一次执行结果」这一类累积条目**（循环里唯一会无限长的那一段）。
/// 用户原话与系统提示词**一个字都不动** —— 压掉「用户问了什么」会让模型答非所问。
public struct AgentContextCompressionBudget: Equatable, Sendable {

    /// 提示词字符预算（含系统提示词 + 用户原话 + 观察段）。**超过它才动手**。
    public var maxPromptCharacters: Int
    /// 最近这么多个条目**一律不动**（当下的执行结果是下一跳最要紧的输入）。
    public var keepRecentEntries: Int
    /// 条目少于这个数**不动**（刚起头的对话压掉就是净损失）。
    public var minimumEntries: Int

    public init(maxPromptCharacters: Int = 24_000,
                keepRecentEntries: Int = 4,
                minimumEntries: Int = 6) {
        self.maxPromptCharacters = maxPromptCharacters
        self.keepRecentEntries = keepRecentEntries
        self.minimumEntries = minimumEntries
    }
}

/// 一次压缩的读数 —— **三个数都要报得出来**（压了几条 / 丢了哪些 / 约省多少 token）。
public struct AgentContextCompressionReport: Equatable, Sendable {

    /// 这次到底压了没有（`false` 时后面几个数一律为 0 —— 不虚报）。
    public var didCompress: Bool
    /// 被压掉的条目数。
    public var compressedEntries: Int
    /// 留下来的条目数。
    public var keptEntries: Int
    /// 压掉的条目原文字符数合计。
    public var droppedCharacters: Int
    /// 压掉那部分的**估算** token 数（口径见 `AgentContextCompressor.estimatedTokens(characters:)`）。
    public var estimatedTokensSaved: Int
    /// 这一跳提示词字符数（压之前 / 压之后）。
    public var promptCharactersBefore: Int
    public var promptCharactersAfter: Int
    /// 丢掉的条目**逐条摘要**（`R-63` ③：要答得出「丢了哪些」）。
    public var droppedDigests: [String]
    /// 压完仍然超预算 —— **如实说**（不假装压够了）。
    public var stillOverBudget: Bool
    /// 插进提示词的那一行（`nil` = 没压）。模型据此知道「早期结果被折叠过」。
    public var marker: String?

    public init(didCompress: Bool = false,
                compressedEntries: Int = 0,
                keptEntries: Int = 0,
                droppedCharacters: Int = 0,
                estimatedTokensSaved: Int = 0,
                promptCharactersBefore: Int = 0,
                promptCharactersAfter: Int = 0,
                droppedDigests: [String] = [],
                stillOverBudget: Bool = false,
                marker: String? = nil) {
        self.didCompress = didCompress
        self.compressedEntries = compressedEntries
        self.keptEntries = keptEntries
        self.droppedCharacters = droppedCharacters
        self.estimatedTokensSaved = estimatedTokensSaved
        self.promptCharactersBefore = promptCharactersBefore
        self.promptCharactersAfter = promptCharactersAfter
        self.droppedDigests = droppedDigests
        self.stillOverBudget = stillOverBudget
        self.marker = marker
    }

    /// 没有压缩时的读数（**全 0**，不是 `nil` —— 调用方不必自己拼一个空壳）。
    public static let none = AgentContextCompressionReport()
}

/// 一轮里**累计**的压缩读数（循环每压一次就 `absorb` 一次）—— 结果里那几个数就是它。
///
/// 单独一个类型而不是散在循环里的几个 `var`：**累计口径只有一处**
/// （压了几条累加、省下多少累加、丢了哪些追加），六个 return 各贴一次同样的四行容易漏一个。
public struct AgentCompressionTally: Equatable, Sendable {

    public var entries: Int
    public var estimatedTokensSaved: Int
    public var digests: [String]

    public init(entries: Int = 0, estimatedTokensSaved: Int = 0, digests: [String] = []) {
        self.entries = entries
        self.estimatedTokensSaved = estimatedTokensSaved
        self.digests = digests
    }

    /// 并进一次压缩的读数（没压的那次传进来是**加法单位元**：什么都不会变）。
    public mutating func absorb(_ report: AgentContextCompressionReport) {
        guard report.didCompress else { return }
        entries += report.compressedEntries
        estimatedTokensSaved += report.estimatedTokensSaved
        digests.append(contentsOf: report.droppedDigests)
    }

    /// 把累计读数写进结果（六个 return 都经过它 —— 停在半路的那条也要报得出来）。
    public func applied(to base: AgentLoopResult) -> AgentLoopResult {
        var copy = base
        copy.compressedEntries = entries
        copy.estimatedTokensSaved = estimatedTokensSaved
        copy.compressedDigests = digests
        return copy
    }
}

public enum AgentContextCompressor {
    /// 逐条摘要的长度上限（一个字条目的「哪一条」由它回答）。
    public static let digestLength = 60

    /// **估算** token：`ceil(chars / 4)`。
    ///
    /// 口径写死在这里，只有一个出处。真实 token 数由端点在响应里报（`LLMUsage`）——
    /// 这里算的只是「省下来多少」的相对量，界面按 `≈` 展示，不当成账单真值。
    public static func estimatedTokens(characters: Int) -> Int {
        characters <= 0 ? 0 : (characters + 3) / 4
    }

    /// 一条观察的摘要（换行压成空格，超长截断；末尾不加省略号 —— 判据按前缀比对）。
    public static func digest(of entry: String) -> String {
        let flat = entry.split(whereSeparator: { $0.isNewline }).joined(separator: " ")
        let trimmed = flat.trimmingCharacters(in: .whitespaces)
        return trimmed.count <= digestLength ? trimmed : String(trimmed.prefix(digestLength))
    }

    /// 压缩。
    ///
    /// - Parameters:
    ///   - entries: 累积的观察条目（按发生顺序，**最老的在前面**）。
    ///   - baseCharacters: 观察段之外的提示词字符数（系统提示词 + 用户原话）。
    ///   - budget: 预算（阈值是参数，不是契约）。
    /// - Returns: 保留的条目（压缩时**首条是 marker**）+ 读数。
    public static func compress(entries: [String],
                                baseCharacters: Int,
                                budget: AgentContextCompressionBudget)
    -> (entries: [String], report: AgentContextCompressionReport) {
        let before = baseCharacters + joinedLength(entries)
        guard before > budget.maxPromptCharacters else {
            var report = AgentContextCompressionReport.none
            report.keptEntries = entries.count
            report.promptCharactersBefore = before
            report.promptCharactersAfter = before
            return (entries, report)
        }

        // 条目太少 / 没有可压的（全是「最近的」）⇒ **一条都不动**，但超预算这件事如实写进读数。
        let compressible = max(0, entries.count - max(0, budget.keepRecentEntries))
        guard entries.count >= budget.minimumEntries, compressible > 0 else {
            var report = AgentContextCompressionReport.none
            report.keptEntries = entries.count
            report.promptCharactersBefore = before
            report.promptCharactersAfter = before
            report.stillOverBudget = true
            return (entries, report)
        }

        // 按「够用就停」压：从最老的开始丢，压到落进预算为止（上限 = 可压条数）。
        var dropped = 0
        while dropped < compressible {
            let remaining = baseCharacters + joinedLength(Array(entries[dropped...]))
            // 留一行 marker 的位置（marker 由**压掉的条数**决定，先按当前 dropped 估一次）。
            let estimate = markerText(dropped: dropped + 1, firstDropped: entries.first ?? "")
            if remaining + estimate.count <= budget.maxPromptCharacters { break }
            dropped += 1
        }
        guard dropped > 0 else {
            var report = AgentContextCompressionReport.none
            report.keptEntries = entries.count
            report.promptCharactersBefore = before
            report.promptCharactersAfter = before
            return (entries, report)
        }

        let kept = Array(entries[dropped...])
        let droppedEntries = Array(entries[..<dropped])
        let droppedCharacters = droppedEntries.reduce(0) { $0 + $1.count }
        let marker = markerText(dropped: dropped, firstDropped: droppedEntries.first ?? "")
        let after = baseCharacters + joinedLength([marker] + kept)

        let report = AgentContextCompressionReport(
            didCompress: true,
            compressedEntries: dropped,
            keptEntries: kept.count,
            droppedCharacters: droppedCharacters,
            estimatedTokensSaved: estimatedTokens(characters: droppedCharacters),
            promptCharactersBefore: before,
            promptCharactersAfter: after,
            droppedDigests: droppedEntries.map(digest(of:)),
            stillOverBudget: after > budget.maxPromptCharacters,
            marker: marker
        )
        return ([marker] + kept, report)
    }

    // MARK: - 内部

    /// 条目按「一行一条」拼起来的长度（与 `AgentLoop` 的回灌段同一种拼法）。
    static func joinedLength(_ entries: [String]) -> Int {
        guard !entries.isEmpty else { return 0 }
        return entries.reduce(0) { $0 + $1.count } + (entries.count - 1)
    }

    /// 插进提示词的那一行 —— **英数形态**：它是发给模型的**系统侧记号**，不是给人看的界面文案
    /// （人话那一条走语言表，见 `LKey.agentStatusCompressed`）。
    static func markerText(dropped: Int, firstDropped: String) -> String {
        "[context compressed: \(dropped) earlier observations folded"
            + " · earliest: \(digest(of: firstDropped))"
            + " · the full text is in the session trail]"
    }
}
