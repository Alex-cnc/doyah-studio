import Foundation

/// **旧工具结果的折叠**（`NFR-AI-08` ③ 的另一半：不丢「我做过什么」，只丢「正文」）。
///
/// 由头（2026-11-04 真机 + 2026-11-06 复测）：一轮 19 分钟里模型请求 94 次、工具调用 385 次，
/// 而**同一个文件被 `read_file` 读了 22 次**。根因不是「模型笨」，是**上下文管理器把旧结果整条丢掉**：
/// `AgentContextCompressor` 超预算时从最老的条目开始丢，只留一行「earlier observations folded」——
/// 于是模型**不记得自己读过哪些文件**，只能重读；重读又把上下文顶回上限，再丢再读，越跑越慢。
///
/// 这一层换成**降级而不是删掉**：
/// · 最近 `keepRecent` 条**原样保留**（当下的结果是下一跳最要紧的输入）；
/// · 短条目（错误码 / 退出码 / 写回执，≤ `verbatimCharacters`）**原样保留** —— 那是结论的证据，不是正文；
/// · 又旧又长的（文件正文 / 搜索命中 / 网页正文）折成**一条一行的台账**：
///   `file:Core/AgentLoop.swift（94,601B·读过 2 次）` —— 认得出「这是什么、多大、在哪」，
///   但不再重发正文，并明说「要某一段就用 offset/limit 重读」；
/// · 台账条数有上限（`maxLedgerLines`），超出部分如实报一句「另有 N 条更早的已折叠」。
///
/// 纯函数：给定 (条目, 策略) ⇒ 结果只由入参决定，不读钟、不读盘。判据因此可以逐条断言。
public struct AgentObservationDigestPolicy: Equatable, Sendable {

    /// **最近这么多条**一律原样，**更老的**才折叠（2026-11-06：由 6 收到 4）。
    ///
    /// 收到 4 的理由：`read_file` 现在一次只给一屏（6KB），4 条 ≈ 24KB ≈ 6k token —— 与折叠之前的
    /// 峰值持平，但**认得出 100 多个读过的路径**（旧实现只剩 5 条）。再往上加，省下来的 token
    /// 又要被最近几条吃回去。
    public var keepRecent: Int
    /// 单条正文不超过这个字符数就**一律原样**（错误码 / 退出码 / 写回执都在这档）。
    public var verbatimCharacters: Int
    /// 折叠后一条摘要的字符上限（够认出「这是什么、多大」）。
    public var digestCharacters: Int
    /// 台账最多留几行（按**最近**的留；更早的并成一句计数，不假装还在）。
    ///
    /// 100 行 ≈ 7KB ≈ 1.8k token：足够放下「这一轮读过哪些文件」，又不至于把省下来的钱吃回去。
    public var maxLedgerLines: Int

    public init(keepRecent: Int = 4,
                verbatimCharacters: Int = 600,
                digestCharacters: Int = 220,
                maxLedgerLines: Int = 100) {
        self.keepRecent = max(0, keepRecent)
        self.verbatimCharacters = max(0, verbatimCharacters)
        self.digestCharacters = max(1, digestCharacters)
        self.maxLedgerLines = max(1, maxLedgerLines)
    }

    /// 产品默认：最近 6 条原样 + 短条目原样 + 40 行台账。
    public static let standard = AgentObservationDigestPolicy()
}

/// 一次折叠的读数（`R-63` ③：压了几条、丢了哪些、省了多少 —— 都要报得出来）。
public struct AgentObservationDigestReport: Equatable, Sendable {

    public var didFold: Bool
    public var foldedEntries: Int
    public var keptEntries: Int
    public var ledgerLines: Int
    /// 台账之外还有多少条更早的（**如实报数**，不假装还在）。
    public var beyondLedger: Int
    public var charactersBefore: Int
    public var charactersAfter: Int
    public var estimatedTokensSaved: Int
    /// 被折叠条目的逐条摘要（头几条；「丢了哪些」要答得出来）。
    public var digests: [String]
    /// 插进观察段的那一行说明。
    public var marker: String?

    public init(didFold: Bool = false,
                foldedEntries: Int = 0,
                keptEntries: Int = 0,
                ledgerLines: Int = 0,
                beyondLedger: Int = 0,
                charactersBefore: Int = 0,
                charactersAfter: Int = 0,
                estimatedTokensSaved: Int = 0,
                digests: [String] = [],
                marker: String? = nil) {
        self.didFold = didFold
        self.foldedEntries = foldedEntries
        self.keptEntries = keptEntries
        self.ledgerLines = ledgerLines
        self.beyondLedger = beyondLedger
        self.charactersBefore = charactersBefore
        self.charactersAfter = charactersAfter
        self.estimatedTokensSaved = estimatedTokensSaved
        self.digests = digests
        self.marker = marker
    }

    public static let none = AgentObservationDigestReport()
}

public enum AgentObservationDigester {

    /// 折叠后的观察条目（**顺序不变**：老的在前）。
    ///
    /// 返回值分两段，因为**下两层的处置不一样**：
    /// · `prefix`（说明行 + 台账）是**认得出来的事实**（「我读过哪些文件、多大」），
    ///   后面的超预算压缩器**不许动它** —— 丢了它模型就会重读，那是这一整套要治的病；
    /// · `recent`（最近几条原样）才是压缩器可以按预算丢的那一段。
    ///
    /// - Parameters:
    ///   - observations: 累积的观察（`AgentLoop` 里那一段，一行一条）。
    ///   - policy: 策略（阈值是参数，不是契约）。
    public static func fold(_ observations: [String],
                            policy: AgentObservationDigestPolicy = .standard)
    -> (prefix: [String], recent: [String], entries: [String], report: AgentObservationDigestReport) {
        let before = joinedLength(observations)
        guard observations.count > policy.keepRecent else {
            var report = AgentObservationDigestReport.none
            report.keptEntries = observations.count
            report.charactersBefore = before
            report.charactersAfter = before
            return ([], observations, observations, report)
        }

        let boundary = observations.count - policy.keepRecent
        var ledger: [(key: String, line: String)] = []
        var folded: [String] = []
        var foldedCharacters = 0

        for entry in observations[..<boundary] {
            // 短条目**原样留着**：错误码 / 退出码 / 写回执是结论的证据，折掉就等于把证据折没了。
            if entry.count <= policy.verbatimCharacters { continue }
            folded.append(entry)
            foldedCharacters += entry.count
            let key = ledgerKey(of: entry)
            if let index = ledger.firstIndex(where: { $0.key == key }) {
                // 同一个文件读过多次 ⇒ 合成一行，并记下次数（「读过 2 次」比两行同名更有用）。
                let count = occurrenceCount(in: ledger[index].line) + 1
                ledger[index].line = ledgerLine(key: key, entry: entry, count: count)
            } else {
                ledger.append((key, ledgerLine(key: key, entry: entry, count: 1)))
            }
        }

        guard !folded.isEmpty else {
            var report = AgentObservationDigestReport.none
            report.keptEntries = observations.count
            report.charactersBefore = before
            report.charactersAfter = before
            return ([], observations, observations, report)
        }

        // 台账有上限：留**最近**的（老的那几条离当下最远，信息价值最低），超出的只报数。
        var beyond = 0
        if ledger.count > policy.maxLedgerLines {
            beyond = ledger.count - policy.maxLedgerLines
            ledger = Array(ledger.suffix(policy.maxLedgerLines))
        }

        let marker = markerText(foldedEntries: folded.count,
                                ledgerLines: ledger.count,
                                beyondLedger: beyond)
        let kept = Array(observations[boundary...])
        let prefix = [marker] + ledger.map(\.line)
        let entries = prefix + kept
        let after = joinedLength(entries)

        let report = AgentObservationDigestReport(
            didFold: true,
            foldedEntries: folded.count,
            keptEntries: kept.count,
            ledgerLines: ledger.count,
            beyondLedger: beyond,
            charactersBefore: before,
            charactersAfter: after,
            // 省下的量 = 折掉的正文 − 台账 + 说明那一截（可以是负数，如实给）。
            estimatedTokensSaved: AgentContextCompressor.estimatedTokens(characters: max(0, before - after)),
            digests: folded.suffix(8).map { digest(of: $0, budget: policy.digestCharacters) },
            marker: marker)
        return (prefix, kept, entries, report)
    }

    /// 一条观察的摘要 —— **按形状分**（`file:` 的正文对下一跳没有用，抬头才有用）。
    public static func digest(of entry: String, budget: Int) -> String {
        let firstLine = entry.split(whereSeparator: { $0.isNewline }).first.map(String.init) ?? entry
        let isBulkyBody = firstLine.hasPrefix("file:")
            || firstLine.hasPrefix("web:")
            || firstLine.hasPrefix("dir:")
            || firstLine.hasPrefix("mcp:")
        if isBulkyBody {
            return firstLine.count <= budget ? firstLine : String(firstLine.prefix(budget))
        }
        let flat = entry.split(whereSeparator: { $0.isNewline }).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return flat.count <= budget ? flat : String(flat.prefix(budget))
    }

    // MARK: - 内部

    /// 台账的合并键：同一个文件 / 同一个目录 / 同一个网页只占一行。
    static func ledgerKey(of entry: String) -> String {
        let firstLine = entry.split(whereSeparator: { $0.isNewline }).first.map(String.init) ?? entry
        // `file:<path>:<bytes>B…` ⇒ 键取到路径为止（字节数会随窗口变，不能进键）。
        if firstLine.hasPrefix("file:") {
            let rest = firstLine.dropFirst("file:".count)
            if let separator = rest.lastIndex(of: ":") { return "file:" + String(rest[..<separator]) }
            return firstLine
        }
        return String(firstLine.prefix(96))
    }

    /// 台账本体（一行）：**抬头形状与真回灌一致**（`file:<路径>:<字节>B`），后面接一句「正文已折叠」。
    ///
    /// 抬头保持原形是有意的：模型认「这个文件我读过」靠的就是这一行 —— 换成别的写法，
    /// 它读到同一路径时会当成没读过，于是又整篇重读（那就等于没折）。
    static func ledgerLine(key: String, entry: String, count: Int) -> String {
        let firstLine = entry.split(whereSeparator: { $0.isNewline }).first.map(String.init) ?? entry
        let times = count > 1 ? "·读过 \(count) 次" : ""
        // 抬头里自带字节数就沿用（`file:X.swift:9000B`），没有就补字符数。
        if firstLine.range(of: #":\d+B"#, options: .regularExpression) != nil,
           let head = firstLine.range(of: #":\d+B"#, options: .regularExpression) {
            return String(firstLine[..<head.upperBound])
                + " · 已折叠\(times)（正文不在本跳上下文里；要某段用 offset/limit 重读）"
        }
        if let bodyStart = firstLine.range(of: "（") {
            return String(firstLine[..<bodyStart.lowerBound]) + "（已折叠\(times)）"
        }
        return "\(key) · 已折叠\(times)（\(entry.count) 字符；要正文用 offset/limit 重读）"
    }

    static func occurrenceCount(in line: String) -> Int {
        guard let range = line.range(of: "·读过 ") else { return 1 }
        let rest = line[range.upperBound...]
        let digits = rest.prefix { $0.isNumber }
        return Int(digits) ?? 1
    }

    static func joinedLength(_ entries: [String]) -> Int {
        guard !entries.isEmpty else { return 0 }
        return entries.reduce(0) { $0 + $1.count } + (entries.count - 1)
    }

    /// 插进观察段的那一行 —— **英数形态**：发给模型的系统侧记号，不是界面文案。
    static func markerText(foldedEntries: Int, ledgerLines: Int, beyondLedger: Int) -> String {
        var text = "[earlier results folded: \(foldedEntries) entries -> \(ledgerLines) ledger lines"
            + " (path + size only; read a section again with read_file offset/limit, or search to locate it)"
        if beyondLedger > 0 { text += "; \(beyondLedger) older ones not listed" }
        return text + "]"
    }
}
