import Foundation

/// 登录项（`NFR-ALL-GATE-REL-006`）的**纯决策层**。
///
/// 为什么决策要单独放在 Core：注册登录项要碰 `ServiceManagement`（平台库），
/// 而「什么时候该注册、什么时候该提示用户去系统设置、注册失败要不要重试」
/// 是产品口径 —— 口径要能在 Linux / Windows 上被同一批用例验证，
/// 所以这里只有纯函数，真实注册走 `LoginItemRegistering` 的实现。
public enum LaunchAtLoginStatus: String, Equatable, Sendable {
    /// 已注册并生效：开机（登录）即启动。
    case enabled
    /// 未注册。
    case disabled
    /// 系统要求用户在「系统设置 → 通用 → 登录项」里手动允许（macOS 13+ 的可能结局）。
    case requiresApproval
    /// 当前平台/构建不支持（例如未签名调试包、非 macOS 端）。
    case unavailable
    /// 上一次操作失败（`detail` 说明原因，不许吞掉）。
    case failed
}

/// 一次同步动作的计划：要么做一件事，要么什么都不做并说明原因。
public struct LaunchAtLoginPlan: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        case register
        case unregister
        case requestApproval
        case none
    }

    public let action: Action
    /// 给界面看的一句话（中英文案由调用方按 `action` 决定，`reason` 只进日志）。
    public let reason: String

    public init(action: Action, reason: String) {
        self.action = action
        self.reason = reason
    }
}

public enum LaunchAtLoginDecision {
    /// 用户想要的终态 + 系统当前状态 ⇒ 这次该做什么。
    ///
    /// 四条硬规则（都有用例）：
    /// 1. **不重复注册**：已经是 `enabled` 就什么都不做（重复 `register` 在 macOS 上会抛错）。
    /// 2. **要求批准时不再注册**：`requiresApproval` 只能提示用户去系统设置，
    ///    再注册一次会得到同一个结局，界面会变成「点了没反应」。
    /// 3. **关掉就要真的关掉**：`enabled` + 用户不要 ⇒ `unregister`；不能只改本地开关。
    /// 4. **不可用 / 失败不许假装成功**：`unavailable` / `failed` 一律 `none`，
    ///    由调用方把原因显示出来，不许把开关画成「已开启」。
    public static func plan(desired: Bool, current: LaunchAtLoginStatus) -> LaunchAtLoginPlan {
        if current == .unavailable {
            return LaunchAtLoginPlan(action: .none, reason: "本构建不支持登录项（未签名或非 macOS）")
        }
        if desired {
            switch current {
            case .enabled:
                return LaunchAtLoginPlan(action: .none, reason: "已经是登录项，不重复注册")
            case .disabled:
                return LaunchAtLoginPlan(action: .register, reason: "未注册 ⇒ 注册")
            case .requiresApproval:
                return LaunchAtLoginPlan(action: .requestApproval, reason: "系统要求用户手动允许")
            case .failed:
                return LaunchAtLoginPlan(action: .register, reason: "上次失败 ⇒ 再试一次注册")
            case .unavailable:
                return LaunchAtLoginPlan(action: .none, reason: "本构建不支持登录项")
            }
        }
        switch current {
        case .enabled, .failed:
            return LaunchAtLoginPlan(action: .unregister, reason: "用户关掉了 ⇒ 注销登录项")
        case .disabled, .requiresApproval:
            return LaunchAtLoginPlan(action: .none, reason: "本来就不是登录项")
        case .unavailable:
            return LaunchAtLoginPlan(action: .none, reason: "本构建不支持登录项")
        }
    }
}

/// 真实注册器要实现的接口（macOS 实现在 `Platform/macOS/SMAppServiceLoginItem.swift`）。
public protocol LoginItemRegistering: AnyObject {
    var status: LaunchAtLoginStatus { get }
    func register() throws
    func unregister() throws
}

public enum LaunchAtLoginError: Error, Equatable {
    case unsupported
    case registrationFailed(String)
}
