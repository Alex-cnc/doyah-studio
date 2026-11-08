import Foundation

/// 「这一句话是谁发起的」（`FR-AGT-LINK-CHAN-003` ②：权限与桌面端同一套）。
///
/// 为什么需要显式的来源：审批层里有一条**代签**路径（任务范围内不问人，`AgentScopeGate`），
/// 它默认「人刚说了一句‘把这个修好’」。IM 发来的那句话同样是人的话，但发起那一刻
/// **人不在桌面前**，看不到弹出的审批单 —— 所以来源必须是个显式参数，
/// 而不是靠调用方「记得别代签」。
public enum AgentIMActionOrigin: String, Equatable, Sendable, CaseIterable {
    case desktop
    case im
}

/// 一次动作该不该放行（**只有两档**：直接做 / 去桌面批）。
public enum AgentIMGateVerdict: Equatable, Sendable {
    /// 普通读写：与桌面同一套规则（有授权就按授权走）。
    case autoApprovable
    /// 一律要桌面点一下（不可逆 / 对外发送 / 凭据 / 越界）。
    case requiresDesktopApproval(reason: AgentIMGateReason)
}

/// 「为什么要桌面批」的四档（人话在语言表；回给手机那一句也用它）。
public enum AgentIMGateReason: String, Equatable, Sendable, CaseIterable {
    /// 删除 / 覆盖 / 改写历史。
    case irreversible
    /// 对外发送（发出去收不回）。
    case outbound
    /// 口令 / 凭据（读到即泄）。
    case credential
    /// 工作区之外。
    case outsideWorkspace

    /// 从审批层那套危险面翻过来（一处映射，不另立一套分类）。
    public init?(_ hazard: AgentApprovalHazard) {
        switch hazard {
        case .ordinary: return nil
        case .destructive: self = .irreversible
        case .outbound: self = .outbound
        case .credential: self = .credential
        case .outsideWorkspace: self = .outsideWorkspace
        }
    }

    public var textKey: LKey {
        switch self {
        case .irreversible: return .agentIMGateIrreversible
        case .outbound: return .agentIMGateOutbound
        case .credential: return .agentIMGateCredential
        case .outsideWorkspace: return .agentIMGateOutsideWorkspace
        }
    }
}

/// IM 通道的审批闸（纯函数，判据直接打它）。
///
/// 一条硬规矩：**不可逆 / 对外发送 / 凭据 / 越界这四档，任何来源都不代签** ——
/// 不是「IM 更严」，而是这四档本来就不许被「本会话内 / 总是允许」覆盖
/// （`AgentApprovalHazard.allowsGrant` 只有 `ordinary` 为真）。这里把它做成
/// **发起侧也能查的一问**：代签路径在放行之前问一次，答案不对就出审批单。
public struct AgentIMOriginGate: Equatable, Sendable {

    public var origin: AgentIMActionOrigin

    public init(origin: AgentIMActionOrigin) {
        self.origin = origin
    }

    /// 这一次动作能不能不问人。
    ///
    /// `hasStoredGrant` = 盘上/会话里已经有针对「工具 + 作用域」的授权。
    /// **四档危险面一律不认它**（历史遗留、手改文件、旧版本写下的都算）——
    /// 这与 `AgentApprovalGrantBook.isGranted` 同一条纪律，这里是它在放行口的那一问。
    /// 参数**有意不参与判定**：留着它，是为了让调用点把「手上确实有一条授权」这件事
    /// 显式交进来，而不是在别处悄悄把风险档抹平。
    public func decide(hazard: AgentApprovalHazard, hasStoredGrant: Bool = false) -> AgentIMGateVerdict {
        guard let reason = AgentIMGateReason(hazard) else { return .autoApprovable }
        return .requiresDesktopApproval(reason: reason)
    }
}

/// 被挡下时**回给手机**的那一句（人话，不是「操作失败」）。
public enum AgentIMGateText {

    public static func reply(reason: AgentIMGateReason, language: AppLanguage) -> String {
        LocalizedStrings.format(.agentIMReplyNeedsDesktopApproval, language: language,
                                LocalizedStrings.text(reason.textKey, language: language))
    }
}
