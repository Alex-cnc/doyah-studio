import Foundation

/// **授权粒度**（`FR-AI-34` · 配套"秘书要把咖啡泡好"那条）。
///
/// 病在哪儿：从前每个写盘 / 每条命令都要人手批一次 —— 用户成了"每一步都在场"的瓶颈，
/// 他自己说的是"我被完全绑架了"。而秘书不会问你美式还是拿铁。
///
/// 但"少问"不能变成"乱来"，所以这里划三条线：
/// 1. **范围**：只在本次任务授权内代签（默认还要求在工作区里 —— 沙箱在工具层已挡）；
/// 2. **例外**：受保护路径（`.git/` `.secrets/` `.doyah/` 等）与**超过上限**的次数，一律转人工；
/// 3. **留痕**：每一次代签都记一条（谁、什么、为什么、哪一次任务）—— 事后可审，且**可被推翻**。
///
/// 判据口径：`AgentScopeGate.judge` 是纯函数 —— 给同样的输入必须给同样的结论（可测）。
public struct AgentTaskScope: Equatable, Sendable {

    public enum Mode: String, Codable, Equatable, Sendable, CaseIterable {
        /// 每个动作都问（老行为）。
        case askEachAction
        /// 任务范围内自动代签（默认）：不可逆 / 受保护 / 超上限 才回来问。
        case taskScope
    }

    public var mode: Mode
    /// 一次任务里最多代签多少次（防跑飞；超了转人工）。
    public var maxAutoApprovals: Int
    /// 这些路径片段一旦出现在待批内容里 ⇒ **不代签**（改为问人）。
    public var protectedFragments: [String]

    public init(mode: Mode = .taskScope,
                maxAutoApprovals: Int = 40,
                protectedFragments: [String] = AgentTaskScope.defaultProtectedFragments) {
        self.mode = mode
        self.maxAutoApprovals = maxAutoApprovals
        self.protectedFragments = protectedFragments
    }

    /// 老行为（每个动作都问）。
    public static let askEach = AgentTaskScope(mode: .askEachAction)
    /// 默认：任务范围内代签。
    public static let `default` = AgentTaskScope()

    /// 受保护片段 —— 这些一动就是"不可逆或伤及根本"，**多少钱都不代签**。
    public static let defaultProtectedFragments = [
        ".git/", ".gitignore",
        ".secrets/", "credentials.json",
        ".doyah/",
        "Package.swift",
        "Scripts/build-app.sh",
        "Scripts/verify-core.sh"
    ]
}

/// 代签结论（**理由必须能说出口** —— 说不出理由的代签就是越权）。
public enum AgentScopeVerdict: Equatable, Sendable {
    case autoApproved(reason: String)
    case needsHuman(reason: String)
}

public enum AgentScopeGate {

    /// 纯函数：这一次动作，能不能在任务范围内代签。
    public static func judge(tool: String, preview: String,
                             autoApprovedCount: Int,
                             scope: AgentTaskScope) -> AgentScopeVerdict {
        guard scope.mode == .taskScope else {
            return .needsHuman(reason: "askEachAction")
        }
        // ① 上限（防跑飞：一百次写盘不该是"任务范围内"）
        if autoApprovedCount >= scope.maxAutoApprovals {
            return .needsHuman(reason: "over-auto-approval-limit")
        }
        // ② 受保护路径（不可逆或伤根本 —— 一律问人）
        for fragment in scope.protectedFragments where preview.contains(fragment) {
            return .needsHuman(reason: "protected:\(fragment)")
        }
        // ③ 范围内代签：理由写清"是哪一类动作、在什么范围内"
        return .autoApproved(reason: "task-scope:\(tool)")
    }
}
