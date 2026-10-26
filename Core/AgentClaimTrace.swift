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

    /// 上屏用的整块文本：汇总一行 + 逐行。
    ///
    /// **一条结论都没有 ⇒ `nil`**（不出「0 条结论」这种噪音：那时该说的话是「这轮没有可核的断言」，
    /// 而那句话由调用方按自己的上下文说，不属于这里）。
    ///
    /// 结论行 = `字形 [档位] 结论正文`；出处行 = 缩进 + `出处：…`；替代方案行 = 缩进 + `备选：…`。
    /// 缩进用两个半角空格（等宽字体下与行首字形列对齐，不引入新的宽度令牌）。
    public static func block(for provenance: AgentAnswerProvenance,
                            language: AppLanguage) -> String? {
        guard !provenance.claims.isEmpty else { return nil }
        var lines: [String] = [provenance.summary(language: language)]
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
