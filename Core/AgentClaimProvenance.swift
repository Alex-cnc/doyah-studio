import Foundation

/// 结论的可信度与出处（`FR-AGT-QUAL-VERIFY-003` 不确定性表达 + `FR-AGT-QUAL-VERIFY-004` 断言可溯源）。
///
/// 为什么这两条落成同一处：它们说的是同一件事的两面 —— **这条结论凭什么成立**。
/// 003 管「凭得住多少」（已验证 / 推断 / 没验证 + 把握度），004 管「凭什么」（出处能不能复核）。
/// 分成两个类型就会出现「标了已验证、却没有出处」这种自相矛盾的答案。
///
/// 口径（逐条对 SRS 验收要点）：
/// · 003 ① **能区分「已验证」与「推断」** ⇒ 状态是必填字段，渲染必带标签，不许默认成「已验证」。
/// · 003 ② **把握低时给替代方案** ⇒ `confidence` 低于阈值（或状态是「没验证」）而没给替代方案 = 缺陷。
/// · 003 ③ **无法确认时明确说「没验证」** ⇒ 「没验证」是一个独立状态（不是「低把握的已验证」）。
/// · 004 ① 关键结论旁有出处 ⇒ `bases` 随结论一起走，渲染在结论下方。
/// · 004 ② 出处可点击或可复制执行 ⇒ `AgentClaimBasis.isCopyable` + `copyableText`。
/// · 004 ③ 找不到出处的结论不得写入交付物 ⇒ `AgentAnswerProvenance.isDeliverable` 逐条判空出处。
///
/// 文本口径（L-47）：**语言一律作形参传进来**，本文件不出现用户可见的字面文案。
public enum AgentClaimStatus: String, CaseIterable, Equatable, Sendable {
    /// 已验证：读到了原文 / 跑过了命令，结论与出处一一对应。
    case verified
    /// 推断：出处是真的，但从出处走到这条结论还有一步推理。
    case inferred
    /// 没验证：没读到 / 没跑 / 跑失败 —— 说清就是合格，装成事实才是缺陷。
    case unverified

    var labelKey: LKey {
        switch self {
        case .verified: return .agentClaimVerified
        case .inferred: return .agentClaimInferred
        case .unverified: return .agentClaimUnverified
        }
    }
}

/// 一条结论的出处。四种形状对应四类可复核的东西。
public enum AgentClaimBasis: Equatable, Hashable, Sendable {
    /// 文件里的一行（`line == nil` 指整份文件）。
    case file(path: String, line: Int?)
    /// 一条命令的输出（带上退出码，失败的命令不能当「已验证」的出处而不说）。
    case commandOutput(command: String, exitCode: Int?)
    /// 日志里的一行。
    case log(path: String, line: Int?)
    /// 文档链接。
    case documentLink(url: String)

    /// 给人看的出处（**可复制执行**：文件路径带行号、命令就是那条命令）。
    public var reference: String {
        switch self {
        case let .file(path, line): return line.map { "\(path):\($0)" } ?? path
        case let .commandOutput(command, exitCode):
            return exitCode.map { "cmd:\(command) exit=\($0)" } ?? "cmd:\(command)"
        case let .log(path, line): return line.map { "\(path):\($0)" } ?? path
        case let .documentLink(url): return url
        }
    }

    /// 004 ② ：能不能被人拿去自己复核（复制到终端 / 编辑器 / 浏览器）。
    /// 四种都给了具体可定位的东西，所以恒为真 —— 这个属性存在的意义是让「新增一种出处」
    /// 必须当场回答这个问题，而不是默默混进渲染里。
    public var isCopyable: Bool { !copyableText.isEmpty }

    /// 复制到剪贴板的内容（文件类给「路径:行号」，命令类只给命令本身）。
    public var copyableText: String {
        switch self {
        case let .file(path, line): return line.map { "\(path):\($0)" } ?? path
        case let .commandOutput(command, _): return command
        case let .log(path, line): return line.map { "\(path):\($0)" } ?? path
        case let .documentLink(url): return url
        }
    }
}

/// 一条结论的缺陷（机器码，人话交给渲染层）。
public enum AgentClaimDefect: String, Equatable, Sendable {
    /// 空结论。
    case emptyStatement
    /// 说「已验证」却给不出任何出处 —— 最该拦的一类（把猜测说成事实）。
    case verifiedWithoutBasis
    /// 交付物里的结论没有出处。
    case missingBasis
    /// 把握低（或「没验证」）却没给替代方案。
    case lowConfidenceWithoutAlternative
}

public struct AgentClaim: Equatable, Sendable {

    /// 「把握低」的分界：低于它就**必须**给替代方案（003 ②）。
    public static let lowConfidenceThreshold: Double = 0.6

    public var statement: String
    public var status: AgentClaimStatus
    public var bases: [AgentClaimBasis]
    /// 把握程度（0…1；构造时夹紧，不接受 1.4 这种值来冒充「很确定」）。
    public var confidence: Double
    /// 把握低时给的替代做法 / 另一种可能（可以是空的 —— 空就是缺陷，不是默认合法）。
    public var alternatives: [String]

    public init(statement: String,
                status: AgentClaimStatus,
                bases: [AgentClaimBasis] = [],
                confidence: Double,
                alternatives: [String] = []) {
        self.statement = statement
        self.status = status
        self.bases = bases
        self.confidence = min(1, max(0, confidence))
        self.alternatives = alternatives
    }

    /// 同一出处只标一次（「不是每条都加引用」—— 同一条结论里重复贴同一个路径是噪音）。
    public var uniqueBases: [AgentClaimBasis] {
        var seen = Set<AgentClaimBasis>()
        var out: [AgentClaimBasis] = []
        for basis in bases where !seen.contains(basis) {
            seen.insert(basis)
            out.append(basis)
        }
        return out
    }

    /// 是否需要给替代方案（003 ②）。
    public var needsAlternative: Bool {
        status == .unverified || confidence < AgentClaim.lowConfidenceThreshold
    }

    /// 逐条缺陷（空数组 = 这条结论合格）。
    public var defects: [AgentClaimDefect] {
        var out: [AgentClaimDefect] = []
        if statement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            out.append(.emptyStatement)
        }
        let unique = uniqueBases
        if unique.isEmpty { out.append(.missingBasis) }
        if status == .verified, unique.isEmpty { out.append(.verifiedWithoutBasis) }
        if needsAlternative, alternatives.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            out.append(.lowConfidenceWithoutAlternative)
        }
        return out
    }

    /// 给人看的一段：标签 + 结论 + 出处 + （必要时）替代方案。
    public func rendered(language: AppLanguage) -> String {
        let label = LocalizedStrings.text(status.labelKey, language: language)
        var lines = ["[\(label)] \(statement)"]
        let unique = uniqueBases
        if !unique.isEmpty {
            let refs = unique.map(\.reference).joined(separator: ", ")
            lines.append(LocalizedStrings.format(.agentClaimBasisLine, language: language, refs))
        }
        let usable = alternatives.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !usable.isEmpty {
            lines.append(LocalizedStrings.format(.agentClaimAlternativeLine, language: language,
                                                usable.joined(separator: "; ")))
        }
        return lines.joined(separator: "\n")
    }
}

/// 一整段答案的出处账：逐条结论 + 汇总 + **能不能交付**。
///
/// `isDeliverable == false` 的意思是：这段答案里有结论**指不到出处**（004 ③），
/// 或者把握低却没给替代方案（003 ②）—— 这种答案可以给人看（讨论中），但不能当交付物。
public struct AgentAnswerProvenance: Equatable, Sendable {

    public var claims: [AgentClaim]

    public init(claims: [AgentClaim]) {
        self.claims = claims
    }

    /// 不合格的结论（空 = 这段答案可作交付物）。
    public var undeliverable: [AgentClaim] {
        claims.filter { !$0.defects.isEmpty }
    }

    /// 004 ③：找不到出处的结论不得写入交付物。
    public var isDeliverable: Bool { undeliverable.isEmpty }

    public var verifiedCount: Int { claims.filter { $0.status == .verified }.count }
    public var inferredCount: Int { claims.filter { $0.status == .inferred }.count }
    public var unverifiedCount: Int { claims.filter { $0.status == .unverified }.count }

    /// 一行汇总（「N 条结论：已验证 A / 推断 B / 没验证 C」）。
    public func summary(language: AppLanguage) -> String {
        LocalizedStrings.format(.agentClaimSummaryLine, language: language,
                                claims.count, verifiedCount, inferredCount, unverifiedCount)
    }

    /// 整段渲染：汇总一行 + 逐条。
    public func rendered(language: AppLanguage) -> String {
        ([summary(language: language)] + claims.map { $0.rendered(language: language) })
            .joined(separator: "\n")
    }
}

