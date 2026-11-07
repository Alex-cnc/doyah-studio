import Foundation

/// 结论出处**上屏**的投影（`FR-AGT-QUAL-VERIFY-003` 不确定性表达 + `FR-AGT-QUAL-VERIFY-004` 断言可溯源）。
///
/// 为什么还要这一层（`AgentClaim.rendered` 已经能出文本）：那一段是**一段连续文字**，
/// 界面拿到的是一整块 —— 想给「已验证 / 推断 / 没验证」三档不同的行首字形、想让
/// 界面上每条结论各自占一行、想让人能只复制**某一条的出处**，都得先有**逐行结构化**的形态。
/// 直接把 `rendered` 的结果按 `\n` 切开不行：出处行里的路径本身可能带换行以外的东西，
/// 而「这一行是结论还是出处」这个信息切开就没了。
///
/// 口径（逐条对验收要点）：
/// · 003 ① 三态必现：每条结论行都带自己的档位字形与标签，**不许**默认成「已验证」；
/// · 003 ③ 「没验证」是独立一档（`?`），不是「低把握的已验证」；
/// · 004 ① 出处跟在结论下面一行（缩进 `↳`），不是挤在结论句尾；
/// · 004 ② 每条出处自带 `copyableBasis`（复制到终端 / 编辑器就能复核）；
/// · 同一条结论里重复的同一出处只出一行（`uniqueBases` 的口径在 Core，界面不再去重一次）。
///
/// 文本口径（L-47）：**语言一律作形参传进来**，本文件不出现用户可见的字面文案 ——
/// 文案全部取自 `LocalizedStrings` 既有的 `agentClaim*` 键，不新增键。
public struct AgentClaimTraceRow: Equatable, Sendable {

    public enum Kind: String, Equatable, Sendable {
        /// 一条结论（带档位与把握）。
        case claim
        /// 一条出处（跟在上一条结论下面）。
        case basis
        /// 一条替代方案（把握低时才有）。
        case alternative
    }

    public var kind: Kind
    /// 只有 `.claim` 行有档位；出处与替代方案行是 `nil`（它们本身不表达把握）。
    public var status: AgentClaimStatus?
    /// 行文本（已含档位标签 / 「出处：」/「备选：」的本地化前缀）。
    public var text: String
    /// 只有 `.claim` 行有：本条结论的把握百分比（0…100，四舍五入到整数）。
    public var confidencePercent: Int?
    /// 本条结论（或它所依附的那条结论）能不能进交付物。
    /// 出处的可交付性跟着它的结论走 —— 一条没出处的结论不会因为旁边有个好出处就变合格。
    public var isDeliverable: Bool
    /// 只有 `.basis` 行有：这一条出处可复制的文本。
    public var copyableBasis: String?

    public init(kind: Kind,
                status: AgentClaimStatus? = nil,
                text: String,
                confidencePercent: Int? = nil,
                isDeliverable: Bool = true,
                copyableBasis: String? = nil) {
        self.kind = kind
        self.status = status
        self.text = text
        self.confidencePercent = confidencePercent
        self.isDeliverable = isDeliverable
        self.copyableBasis = copyableBasis
    }
}

public enum AgentClaimTrace {

    /// 三档的行首字形。**不是文案**（语言无关），所以不占本地化键。
    /// 选这三个的理由：`✓` 与 `?` 在小字号下一眼能分；`≈` 表示「出处是真的，但还差一步推理」，
    /// 比再用一个勾（会与「已验证」混）或一个问号（会与「没验证」混）都准。
    public static func glyph(for status: AgentClaimStatus) -> String {
        switch status {
        case .verified: return "✓"
        case .inferred: return "≈"
        case .unverified: return "?"
        }
    }

    /// 逐行投影：结论行 + 它的出处行 + （必要时）替代方案行，**顺序与答复里出现顺序一致**。
    public static func rows(for provenance: AgentAnswerProvenance) -> [AgentClaimTraceRow] {
        var out: [AgentClaimTraceRow] = []
        for claim in provenance.claims {
            let deliverable = claim.defects.isEmpty
            let percent = Int((claim.confidence * 100).rounded())
            out.append(AgentClaimTraceRow(kind: .claim,
                                          status: claim.status,
                                          text: claim.statement,
                                          confidencePercent: percent,
                                          isDeliverable: deliverable))
            for basis in claim.uniqueBases {
                out.append(AgentClaimTraceRow(kind: .basis,
                                              text: basis.reference,
                                              isDeliverable: deliverable,
                                              copyableBasis: basis.isCopyable ? basis.copyableText : nil))
            }
            for alternative in claim.alternatives
            where !alternative.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                out.append(AgentClaimTraceRow(kind: .alternative,
                                              text: alternative,
                                              isDeliverable: deliverable))
            }
        }
        return out
    }

    /// 台账**机器头**：`claims:<总>/<已核>/<推断>/<未核>`。
    ///
    /// 为什么首行不是那句人话汇总（2026-11-07 改）：这段文本要落进消息流（会话回看 / 导出 /
    /// 复制都靠它），而界面**要把它折成一行**、还要在「有未核断言」时另起一行告警 ——
    /// 折多少、告什么警，取决于**三个计数**，不是取决于那句话怎么措辞。塞一句人话当首行，
    /// 界面就只能去解析译文（切个语言就认不出，等于把判据绑在文案上）。
    /// 机器头是语言无关的定值，`AgentClaimAudit.parse` 反解回来即可；
    /// 人话那两行（汇总 / 告警）由界面按当前语言现算（L-47）。
    public static let headerPrefix = "claims:"

    /// 机器头（计数就是 `AgentAnswerProvenance` 的那三个数，不另算一份）。
    public static func header(for provenance: AgentAnswerProvenance) -> String {
        headerPrefix + [provenance.claims.count,
                        provenance.verifiedCount,
                        provenance.inferredCount,
                        provenance.unverifiedCount]
            .map(String.init)
            .joined(separator: "/")
    }

    /// 上屏用的整块文本：**机器头一行** + 逐行。
    ///
    /// **一条结论都没有 ⇒ `nil`**（不出「0 条结论」这种噪音：那时该说的话是「这轮没有可核的断言」，
    /// 而那句话由调用方按自己的上下文说，不属于这里）。
    ///
    /// 结论行 = `字形 [档位] 结论正文`；出处行 = 缩进 + `出处：…`；替代方案行 = 缩进 + `备选：…`。
    /// 缩进用两个半角空格（等宽字体下与行首字形列对齐，不引入新的宽度令牌）。
    ///
    /// **首行是机器头**（见 `header(for:)`）：界面据此把整块折成一行、并按计数出告警；
    /// 其余行原样留着 —— 它们就是展开区要逐行画的那些行。
    public static func block(for provenance: AgentAnswerProvenance,
                            language: AppLanguage) -> String? {
        guard !provenance.claims.isEmpty else { return nil }
        var lines: [String] = [header(for: provenance)]
        for row in rows(for: provenance) {
            switch row.kind {
            case .claim:
                let label = LocalizedStrings.text(
                    row.status?.labelKey ?? AgentClaimStatus.unverified.labelKey,
                    language: language)
                let glyph = glyph(for: row.status ?? .unverified)
                lines.append("\(glyph) [\(label)] \(row.text)")
            case .basis:
                lines.append("  " + LocalizedStrings.format(.agentClaimBasisLine,
                                                             language: language, row.text))
            case .alternative:
                lines.append("  " + LocalizedStrings.format(.agentClaimAlternativeLine,
                                                             language: language, row.text))
            }
        }
        return lines.joined(separator: "\n")
    }
}

/// 断言台账的**折叠投影**（2026-11-07 人类主人：「结论竟然折叠起来，却把 29 个 claims 全展开放屏幕上，
/// 而且我也不懂这些 claims 有什么用」）。
///
/// ## 它是什么、不是什么
///
/// claims 不是阅读内容，是**审计台账**（每条 = 「这句话我有没有依据」）。默认全展 = 把内部台账
/// 糊在结论上：29 条断言 + 每条下面的出处行，一屏全被它占满，真正要看的结论反而被折起来。
///
/// 所以这一层只回答三件事，界面按它画**一行**：
/// · 有几个（`total`）、几个已核（`verifiedCount`）、几个没依据（`unverifiedCount`）；
/// · `headline` —— 那一行人话（「29 条断言 · 已核 21 / 未核 8 · 展开看依据」）；
/// · `warning` —— **只有存在没依据的断言时**才有的那一行告警（全部已核 ⇒ `nil`，不许出现「0 条」噪音）。
///
/// 展开之后要逐条看，`sections` 就是**按档位分组**的行（组内保持答复顺序）：
/// 界面把每组画一个组头 + 它的行，并在外面套高度上限 —— 29 条也好 300 条也好，
/// 占的屏高是常量（判据 `TestsUISnapshot/AgentChatAnswerPriorityProbeTests`）。
///
/// 语言一律作形参传进来（L-47）：本文件不出现用户可见的字面文案。
public struct AgentClaimAudit: Equatable, Sendable {

    /// 一行（**已经是上屏文本**：机器头之后那些行就是 `AgentClaimTrace.block` 产出的行）。
    public struct Line: Equatable, Sendable {
        public var text: String
        /// 只有结论行有档位；出处 / 备选行是 `nil`（它们本身不表达把握）。
        public var status: AgentClaimStatus?

        public init(text: String, status: AgentClaimStatus? = nil) {
            self.text = text
            self.status = status
        }
    }

    /// 一个档位一组（组头画「已验证 (21)」，组内是这些行）。
    public struct Section: Equatable, Sendable {
        public var status: AgentClaimStatus
        public var lines: [Line]

        public init(status: AgentClaimStatus, lines: [Line]) {
            self.status = status
            self.lines = lines
        }

        /// 这一组里有几条断言（带上出处行的话会比 `lines.count` 少）。
        public var claimCount: Int { lines.filter { $0.status != nil }.count }
    }

    public var total: Int
    public var verifiedCount: Int
    public var inferredCount: Int
    public var unverifiedCount: Int
    /// 分组，顺序固定：已验证 → 推断 → 没验证；**空组不出现**（不画「没验证 (0)」）。
    public var sections: [Section]

    public init(total: Int,
                verifiedCount: Int,
                inferredCount: Int,
                unverifiedCount: Int,
                sections: [Section] = []) {
        self.total = total
        self.verifiedCount = verifiedCount
        self.inferredCount = inferredCount
        self.unverifiedCount = unverifiedCount
        self.sections = sections
    }

    /// 有没有「没依据」的断言 —— 界面据此决定那一行告警出不出。
    public var hasUnverified: Bool { unverifiedCount > 0 }

    // MARK: - 反解

    /// 从 `AgentClaimTrace.block` 的文本反解回折叠投影。**没有机器头 ⇒ `nil`**
    /// （别的时间线事件一律不归这里管，界面继续按 `noticeText` 原样画）。
    public static func parse(_ text: String) -> AgentClaimAudit? {
        let lines = text.components(separatedBy: "\n")
        guard let head = lines.first, let counts = counts(fromHeader: head) else { return nil }

        var buckets: [AgentClaimStatus: [Line]] = [:]
        var current: AgentClaimStatus?
        for line in lines.dropFirst() {
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            // 出处 / 备选行：两个半角空格起头（`block` 的缩进口径），挂在最近那条断言下。
            if line.hasPrefix("  ") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if let status = current {
                    buckets[status, default: []].append(Line(text: trimmed))
                }
                // 没有断言可挂的出处行不画（它凭什么成立？—— 上面那条已经没了，画出来是断章）。
                continue
            }
            // 结论行：行首字形就是档位（`glyph(for:)` 的逆映射）。认不出档位的行照样留在
            // 当前组里（宁可见一行没档位的原文，也不静默吞掉 —— 但绝不替它编一个档位）。
            let status = status(fromGlyphOf: line)
            current = status ?? current
            if let status {
                buckets[status, default: []].append(Line(text: line, status: status))
            } else if let fallback = current {
                buckets[fallback, default: []].append(Line(text: line))
            }
        }

        let sections = AgentClaimStatus.allCases.compactMap { status -> Section? in
            guard let lines = buckets[status], !lines.isEmpty else { return nil }
            return Section(status: status, lines: lines)
        }
        return AgentClaimAudit(total: counts.total,
                               verifiedCount: counts.verified,
                               inferredCount: counts.inferred,
                               unverifiedCount: counts.unverified,
                               sections: sections)
    }

    /// `claims:29/21/0/8` → 四个数。**四个都得在**（少一个就是格式变了，宁可不认）。
    static func counts(fromHeader header: String) -> (total: Int, verified: Int, inferred: Int, unverified: Int)? {
        guard header.hasPrefix(AgentClaimTrace.headerPrefix) else { return nil }
        let body = header.dropFirst(AgentClaimTrace.headerPrefix.count)
        let parts = body.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == 4, numbers.allSatisfy({ $0 >= 0 }) else { return nil }
        return (numbers[0], numbers[1], numbers[2], numbers[3])
    }

    static func status(fromGlyphOf line: String) -> AgentClaimStatus? {
        guard let first = line.first else { return nil }
        return AgentClaimStatus.allCases.first { AgentClaimTrace.glyph(for: $0) == String(first) }
    }

    // MARK: - 那一行 / 那一条告警

    /// 折叠那一行的人话：`29 条断言 · 已核 21 / 未核 0`。
    public func headline(language: AppLanguage) -> String {
        LocalizedStrings.format(.agentClaimAuditHeadline, language: language,
                                total, verifiedCount, unverifiedCount)
    }

    /// **有未核断言时**那一条告警：`8 条断言没有依据（共 29 条）`；全部已核 ⇒ `nil`。
    ///
    /// 为什么「共 N 条」也带上：只说「8 条没依据」，人不知道这 8 条是在 9 条里还是在 290 条里 ——
    /// 严重程度差一个量级。
    public func warning(language: AppLanguage) -> String? {
        guard hasUnverified else { return nil }
        return LocalizedStrings.format(.agentClaimAuditWarning, language: language,
                                       unverifiedCount, total)
    }

    /// 展开后每一组的组头：`已验证 (21)`。
    public func sectionTitle(_ section: Section, language: AppLanguage) -> String {
        LocalizedStrings.format(.agentClaimAuditSection, language: language,
                                LocalizedStrings.text(section.status.labelKey, language: language),
                                section.claimCount)
    }

    /// 展开 / 收起的那个入口文案。
    public func toggleHint(expanded: Bool, language: AppLanguage) -> String {
        LocalizedStrings.text(expanded ? .agentClaimAuditHintLess : .agentClaimAuditHintMore,
                              language: language)
    }
}

