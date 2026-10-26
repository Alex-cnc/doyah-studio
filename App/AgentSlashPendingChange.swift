import Foundation
import DoyahCore

/// 一条**待批**的斜杠配置变更（`FR-AGT-UX-CONV-015`「改配置照走审批」在界面侧的载体）。
///
/// 为什么复用一个 `AgentApproval` 而不是另造一套状态机：本产品的审批语义只有一份
/// （`AgentAudit.swift` 的 `AgentApproval`）—— 待批 → 批准 / 拒绝 → 执行 / 失败。
/// 斜杠命令改的是配置、工具调改动的是文件，**审批这件事没有第二种做法**；
/// 再造一个小状态机迟早出现「工具那边能拒、命令这边拒不了」。
struct AgentSlashPendingChange: Identifiable, Equatable {
    let id: UUID
    let kind: AgentSlashCommandKind
    let argument: String
    /// 那一行审计（单行，参数已折平 —— 见 `AgentSlashCommand.auditLine`）。
    let auditLine: String
    var approval: AgentApproval

    /// 从 effect + 审批单装一条。非 `.configChange` 的 effect ⇒ `nil`（那是别的东西，不该等审批）。
    init?(effect: AgentSlashCommandEffect, approval: AgentApproval) {
        guard case let .configChange(kind, argument) = effect else { return nil }
        self.id = approval.id
        self.kind = kind
        self.argument = argument
        self.auditLine = effect.auditLine
        self.approval = approval
    }
}

/// `/theme <参数>` 的参数解析。
///
/// 为什么在 App 而不在 Core：**参数是给人打的字**（`深色` / `dark` / `跟随系统`），
/// 属界面语言面；放进 Core 会让「中文字面量」棘轮多记几行，而这几行本来就不是给人看的状态文案
/// —— 它是**输入的别名表**。别名只做等价映射，不猜：认不出就返回 `nil`，由调用方如实说「这个值不认」。
enum AgentSlashThemeArgument {
    static func preference(from argument: String) -> AppearancePreference? {
        switch argument.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "深色", "暗色", "深", "dark", "alwaysdark":
            return .alwaysDark
        case "浅色", "亮色", "浅", "light", "alwayslight":
            return .alwaysLight
        case "跟随系统", "系统", "自动", "system", "auto", "followsystem":
            return .followSystem
        default:
            return nil
        }
    }
}
