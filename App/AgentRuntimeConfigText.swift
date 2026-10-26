import Foundation
import DoyahCore

/// 配置被拒时的**人话**（`FR-AGT-OPS-OBS-002` 第三条验收要点：「非法配置拒绝保存并说明」）。
///
/// 为什么单开一件：`AgentConfigError` 里带着「允许什么」（`allowed`）是 Core 的机器码措辞，
/// 而界面要的是「哪一项、填了多少、允许什么」三样齐的一句中文。两处各拼一半会漂移，
/// 所以人话只在这里拼，`AppState` 只负责把结果转给面板。
enum AgentConfigRejectionText {

    static func line(for error: AgentConfigError) -> String {
        switch error {
        case let .unknownKey(key):
            return L(.agentConfigUnknownKey, key)
        case let .outOfRange(key, value, allowed):
            return L(.agentConfigOutOfRange, key, value, allowed)
        case .missingReason:
            return L(.agentConfigMissingReason)
        }
    }

    /// 载入降级的原因码也翻一句（原因码本身是 ASCII 机器码，原样放在括号里方便排查）。
    static func degradedLine(for state: AgentRuntimeConfigFile.LoadState) -> String? {
        guard case let .degraded(reason) = state else { return nil }
        return L(.agentRuntimeDegraded, reason)
    }

    /// 留痕那几行的展示（「最近改动」最多三条 —— 面板不是审计面板，看最近的够用）。
    static func historyLines(_ changes: [AgentConfigChange], limit: Int = 3) -> [String] {
        guard limit > 0 else { return [] }
        return changes.suffix(limit).reversed().map(\.summaryLine)
    }
}

/// 插件没装上时的**人话**（`FR-AGT-LINK-EXT-003` 装卸面板那一侧）。
///
/// Core 那边只给 ASCII 机器码（可 grep、可断言），面板要的是「为什么装不上」一句中文。
/// 两处各拼一句必然漂移，所以人话只在这里拼；认不出的码**原样显示**，
/// 不去猜一个「大概是这样」的结论 —— 猜错比不猜更坏。
enum AgentExtensionRejectionText {

    static func line(for code: String) -> String {
        guard let rejection = AgentExtensionRejection(rawValue: code) else { return code }
        switch rejection {
        case .manifestUnreadable: return L(.agentExtensionRejectionManifestUnreadable)
        case .slotUnknown: return L(.agentExtensionRejectionSlotUnknown)
        case .slotIsKernelFacet: return L(.agentExtensionRejectionSlotIsKernelFacet)
        case .providesKernelFacet: return L(.agentExtensionRejectionProvidesKernelFacet)
        case .permissionNotDeclared: return L(.agentExtensionRejectionPermissionNotDeclared)
        case .providesEmpty: return L(.agentExtensionRejectionProvidesEmpty)
        case .hookNotTighteningOnly: return L(.agentExtensionRejectionHookNotTighteningOnly)
        case .idEmpty: return L(.agentExtensionRejectionIDEmpty)
        }
    }
}
