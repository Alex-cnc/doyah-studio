import Foundation

/// 把一段成文答复审成「逐条结论 + 出处 + 能不能当交付物」
/// （`FR-AGT-QUAL-VERIFY-003` 不确定性表达 + `FR-AGT-QUAL-VERIFY-004` 断言可溯源）。
///
/// 为什么要有这一层：`AgentClaim` / `AgentAnswerProvenance` 只是**契约**（一条结论长什么样、
/// 什么算合格）。契约齐了不等于真用上 —— 缺的就是这一处「从真实运行里取证据、把答复切成结论、
/// 逐条判它指不指得到东西」。没有它，`isDeliverable` 永远是调用方自己填的，等于没人判。
///
/// 三条口径（都不许放宽）：
/// 1. **出处的唯一合法来源 = 本轮真做过的动作**（循环里 `executedTools` 那批）。
///    模型自己在正文里写一个从没读过的路径，不算出处 —— 那正是「把猜测说成事实」的形状。
/// 2. **退出码不知道就不能标「已验证」**：本轮的 `executedTools` 只带调用、不带结果行，
///    所以命令类出处一律记「推断」，等哪天结果行随结果带出来再升格（不许在这里假装知道）。
/// 3. **找不到出处的结论不进交付物**（004 ③），但仍要在提示里点名几条 —— 静默丢弃与
///    静默放行同样是骗人。
///
/// 文本口径（L-47）：本文件不出现用户可见的字面文案，人话一律走 `LKey` + 语言形参。
public struct AgentAnswerEvidence: Equatable, Sendable {

    /// 本轮真做过的那件事本身（作为结论的出处）。
    public var basis: AgentClaimBasis
    /// 正文里可能用来指它的写法：完整引用 + 它的末段（文件名 / 命令名）。
    ///
    /// 两个都要：完整路径给人复制，末段给人读（模型常写「改了 Package.swift」，不写全路径）。
    public var aliases: [String]

    public init(basis: AgentClaimBasis, aliases: [String]) {
        self.basis = basis
        self.aliases = aliases.filter { !$0.isEmpty }
    }

    /// 正文里出现这个写法算不算「指到了这件事」。
    ///
    /// 完整引用算**精确**命中（那件事真发生过、写的也是它）；末段只算**弱**命中
    /// （同名文件在别处的可能性真实存在，所以只能算推断）。
    func match(_ haystack: String) -> MatchQuality? {
        guard let first = aliases.first else { return nil }
        let full = first.lowercased()
        if !full.isEmpty, haystack.contains(full) { return .exact }
        for alias in aliases.dropFirst() {
            let weak = alias.lowercased()
            // 太短的末段（a.sh / x）遍地都是，当前缀匹配会大面积假命中 —— 不当出处。
            if weak.count >= 4, haystack.contains(weak) { return .weak }
        }
        return nil
    }

    enum MatchQuality { case exact, weak }
}

/// 从本轮实际发生过的工具调用里取出处。
public enum AgentEvidenceLedger {

    /// 参数里可能是「路径 / 命令 / 链接」的键（按优先级）。
    ///
    /// 只认这几种：它们在工具声明里就是同一件事的不同叫法，多认一个键就等于多认一种出处，
    /// 而出处是给人复核用的 —— 认错了比不认更糟。
    static let pathKeys = ["path", "file_path", "filePath", "file", "dir", "directory"]
    static let urlKeys = ["url", "link", "href"]
    static let commandKeys = ["command", "cmd", "script"]

    /// `executedTools` → 出处清单（去重、保序：同一处只在第一次出现时记一条）。
    public static func collect(executedTools: [AgentToolInvocation]) -> [AgentAnswerEvidence] {
        var out: [AgentAnswerEvidence] = []
        var seen = Set<AgentClaimBasis>()
        for invocation in executedTools {
            guard let evidence = evidence(for: invocation) else { continue }
            if seen.contains(evidence.basis) { continue }
            seen.insert(evidence.basis)
            out.append(evidence)
        }
        return out
    }

    static func evidence(for invocation: AgentToolInvocation) -> AgentAnswerEvidence? {
        let args = arguments(invocation.argumentsJSON)
        let name = invocation.name.lowercased()
        let isURLTool = name.contains("url") || name.contains("fetch") || name.contains("http")
        let isCommandTool = name.contains("command") || name.contains("shell") || name.contains("code")

        if isURLTool, let url = firstValue(in: args, keys: urlKeys) {
            return AgentAnswerEvidence(basis: .documentLink(url: url), aliases: [url])
        }
        if isCommandTool, let command = firstValue(in: args, keys: commandKeys) {
            // 退出码不知道 ⇒ 只能算推断（`AgentClaimBasis.commandOutput(exitCode: nil)`）。
            return AgentAnswerEvidence(basis: .commandOutput(command: command, exitCode: nil),
                                       aliases: [command, command.split(separator: " ").first.map(String.init) ?? command])
        }
        if let path = firstValue(in: args, keys: pathKeys) {
            return AgentAnswerEvidence(basis: .file(path: path, line: nil), aliases: [path, basename(path)])
        }
        // 既不是路径也不是命令的调用（例如 search 的关键词）不产出出处 ——
        // 「查过什么词」不能证明任何一条结论。
        return nil
    }

    static func arguments(_ json: String) -> [String: Any] {
        let text = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object
    }

    static func firstValue(in args: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = args[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    static func basename(_ path: String) -> String {
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        return trimmed.split(separator: "/").last.map(String.init) ?? trimmed
    }
}

/// 答复 → 逐条结论（带出处）。纯函数，不碰磁盘、不碰时钟。
public enum AgentAnswerAuditor {

    /// 一句话短到只剩标点、或本身就是提问，都不算「结论」。
    ///
    /// 提问不是断言：把「要我继续吗？」算成一条没出处的结论，会让每次反问都变成一次交付失败。
    static let minimumStatementLength = 4

    /// 把成文答复切成结论句。
    ///
    /// 切法：代码块（``` 之间）整段跳过（那是证据不是结论）· 标题行与表格分隔行跳过 ·
    /// 行内按 `。！？!?` 与句点切 · 去掉行首的列表符号与序号 · 以问号收尾的整句跳过 ·
    /// **替代方案行不算结论**（它们归属上一条结论，见 `segments(in:)`）。
    public static func statements(in answer: String) -> [String] {
        segments(in: answer).compactMap { segment in
            if case let .statement(text) = segment { return text }
            return nil
        }
    }

    /// 答复里按文档顺序切出的两种东西：结论句 与 替代方案行（`FR-AGT-QUAL-VERIFY-003` ②）。
    ///
    /// 为什么要有这一层：替代方案是**跟着某一条结论**的（`AgentClaim.alternatives`），
    /// 平铺成两串就再也对不上「这条备选是给哪条结论的」。切完顺序仍在，归属由此确定。
    enum Segment: Equatable {
        case statement(String)
        case alternative(String)
    }

    static func segments(in answer: String) -> [Segment] {
        var out: [Segment] = []
        var inFence = false
        for rawLine in answer.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                inFence.toggle()
                continue
            }
            if inFence || line.isEmpty { continue }
            if line.hasPrefix("#") { continue }
            // 表格分隔行 |---|:--:| 不是结论。
            if line.hasPrefix("|"), line.allSatisfy({ "|-: ".contains($0) }) { continue }
            // 替代方案行：整行归属**上一条**结论（不再当结论切句，也不自成一条断言）。
            if let alternative = AgentAlternativeProtocol.alternative(in: line) {
                out.append(.alternative(alternative))
                continue
            }
            for piece in splitSentence(line) {
                let cleaned = stripListMarker(piece)
                guard cleaned.count >= minimumStatementLength else { continue }
                if cleaned.hasSuffix("?") || cleaned.hasSuffix("？") { continue }
                out.append(.statement(cleaned))
            }
        }
        return out
    }

    static func splitSentence(_ line: String) -> [String] {
        var pieces: [String] = []
        var current = ""
        for character in line {
            current.append(character)
            if "。！？!?".contains(character) {
                // 英文省略号 / 小数点的句点不当分隔符：只有「空格 + 句点 + 空格或结尾」才算。
                pieces.append(current)
                current = ""
            }
        }
        if !current.isEmpty { pieces.append(current) }
        return pieces
    }

    static func stripListMarker(_ text: String) -> String {
        var current = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let markers = ["- ", "* ", "• ", "+ "]
        while true {
            let before = current
            for marker in markers where current.hasPrefix(marker) {
                current = String(current.dropFirst(marker.count))
            }
            // 有序列表：1. / 12) 之类（数字前缀 + 分隔符）。
            let digits = current.prefix { $0.isNumber }
            if !digits.isEmpty, digits.count <= 3 {
                let rest = current.dropFirst(digits.count)
                if rest.hasPrefix(". ") || rest.hasPrefix(") ") || rest.hasPrefix("、") {
                    current = String(rest.dropFirst(rest.hasPrefix("、") ? 1 : 2))
                }
            }
            current = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if current == before { break }
        }
        return current
    }

    /// 主入口：答复 + 本轮出处 ⇒ 逐条结论的账。
    ///
    /// 替代方案（`FR-AGT-QUAL-VERIFY-003` ②）在这里**挂到它前面那条结论上**：
    /// 归属按文档顺序定，没有归属的（出现在任何结论之前的备选行）如实忽略 ——
    /// 宁可少一条，也不凭空造一条结论来接它。
    public static func audit(answer: String, evidence: [AgentAnswerEvidence]) -> AgentAnswerProvenance {
        var claims: [AgentClaim] = []
        for segment in segments(in: answer) {
            switch segment {
            case let .statement(text):
                claims.append(claim(for: text, evidence: evidence))
            case let .alternative(text):
                guard var last = claims.popLast() else { continue }
                // 同一条结论下重复贴同一句备选是噪音（模型常把同一句写两遍）。
                if !last.alternatives.contains(text) { last.alternatives.append(text) }
                claims.append(last)
            }
        }
        return AgentAnswerProvenance(claims: claims)
    }

    static func claim(for statement: String, evidence: [AgentAnswerEvidence]) -> AgentClaim {
        let haystack = statement.lowercased()
        var bases: [AgentClaimBasis] = []
        var best: AgentAnswerEvidence.MatchQuality?
        for item in evidence {
            guard let quality = item.match(haystack) else { continue }
            bases.append(item.basis)
            if best == nil || quality == .exact { best = quality }
            if quality == .exact { continue }
        }
        guard let quality = best, !bases.isEmpty else {
            // 指不到任何本轮做过的事 ⇒ 如实记「没验证」，并把把握压到最低档。
            return AgentClaim(statement: statement, status: .unverified, bases: [],
                              confidence: unverifiedConfidence)
        }
        let status = status(for: quality, bases: bases)
        return AgentClaim(statement: statement, status: status, bases: bases,
                          confidence: status == .verified ? verifiedConfidence : inferredConfidence)
    }

    /// 「没验证」那一档的把握：低到必然触发「必须给替代方案」的判据 ——
    /// 这是有意的：一句指不到出处的断言，本来就该被要求补出处或改成推断。
    static let unverifiedConfidence = 0.2
    static let inferredConfidence = 0.7
    static let verifiedConfidence = 0.98

    /// 精确命中也可能只到「推断」：命令类出处的退出码本轮没带出来（见文件头第 2 条）。
    static func status(for quality: AgentAnswerEvidence.MatchQuality,
                       bases: [AgentClaimBasis]) -> AgentClaimStatus {
        guard quality == .exact else { return .inferred }
        let allCommandsWithoutExit = bases.allSatisfy { basis in
            if case let .commandOutput(_, exitCode) = basis { return exitCode == nil }
            return false
        }
        return allCommandsWithoutExit ? .inferred : .verified
    }
}

extension AgentAnswerProvenance {

    /// 合格结论（逐条无缺陷）。
    public var deliverableClaims: [AgentClaim] { claims.filter { $0.defects.isEmpty } }

    /// 只由合格结论拼成的交付内容（004 ③：缺出处的不许写入）。
    public func deliverableText(language: AppLanguage) -> String {
        deliverableClaims.map { $0.rendered(language: language) }.joined(separator: "\n\n")
    }
}

/// 一次「能不能交出去」的判定。
///
/// 与 `AgentAnswerProvenance.isDeliverable` 分开的理由：那个是**账**（有几条不合格），
/// 这个是**动作**（交出去的正文是哪一段、拦下几条、界面上挂什么条）。混成一个类型
/// 就会出现「知道不合格、但没人真的把不合格的段落摘掉」—— 那正是 004 ③ 原本要防的事。
public struct AgentDeliverableDecision: Equatable, Sendable {

    public enum Outcome: Equatable, Sendable {
        /// 每条结论都指得到出处。
        case deliverable
        /// 有一部分被拦下（正文只含合格的）。
        case partiallyWithheld(count: Int)
        /// 一句可交付的结论都没有（全是没出处的，或者压根没有断言）。
        case nothing
    }

    public var outcome: Outcome
    public var deliverableText: String
    public var withheld: [AgentClaim]
    public var provenance: AgentAnswerProvenance

    public init(provenance: AgentAnswerProvenance, language: AppLanguage) {
        self.provenance = provenance
        let withheld = provenance.undeliverable
        self.withheld = withheld
        self.deliverableText = provenance.deliverableText(language: language)
        if withheld.isEmpty {
            outcome = provenance.claims.isEmpty ? .nothing : .deliverable
        } else {
            outcome = provenance.deliverableClaims.isEmpty ? .nothing : .partiallyWithheld(count: withheld.count)
        }
    }

    public var isDeliverable: Bool { outcome == .deliverable }

    /// 界面那一行（页内提示条形状，复用 `AgentNotification`，不另造弹窗）。
    ///
    /// 全合格时不给条（没消息就是好消息）；**只要拦下了就点名几条** —— 拦下但不说话，
    /// 人会以为答案里本来就只有那些。两个不合格档都出：交出一部分（`partiallyWithheld`）
    /// 与一句都交不出（`nothing`）。后者更该说 —— 那正是「整段答案都没出处」的样子。
    public func notice(language: AppLanguage) -> AgentNotification? {
        guard !withheld.isEmpty else { return nil }
        return AgentNotification(
            title: LocalizedStrings.text(.agentClaimWithheldTitle, language: language),
            body: LocalizedStrings.format(.agentClaimWithheldBody, language: language, withheld.count),
            mustInterrupt: false)
    }
}
