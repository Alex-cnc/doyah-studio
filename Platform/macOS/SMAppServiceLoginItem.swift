import Foundation
import ServiceManagement

import DoyahCore

/// macOS 侧的登录项实现：`SMAppService.mainApp`（macOS 13+）。
///
/// **为什么在平台模块**：`import ServiceManagement` 只有 Apple 平台有。
/// Core 只留协议与决策（`LaunchAtLogin.swift`），Linux / Windows 各自给等价实现。
///
/// **如实说明的三条边界**（都写进台账，别让下一个人以为是 bug）：
/// 1. 未签名 / 不在标准位置的调试构建，注册可能直接抛 `ErrorDomain=SMAppServiceErrorDomain Code=1`。
///    这时状态报 `.failed`，**不许**在界面上画成「已开启」。
/// 2. macOS 13+ 可能返回「需要用户批准」（`requiresApproval`）—— 那时只能引导用户去
///    「系统设置 → 通用 → 登录项」，再注册一次不会有不同结局。
/// 3. 本条只负责「登录即启动」；「启动后常驻、关窗不终止通道」的判定在
///    `BackgroundResidency`，两者组合起来才满足 `NFR-ALL-GATE-REL-006`。
public final class SMAppServiceLoginItem: LoginItemRegistering {

    public init() {}

    public var status: LaunchAtLoginStatus {
        guard #available(macOS 13.0, *) else { return .unavailable }
        let service = SMAppService.mainApp
        switch service.status {
        case .enabled:
            return .enabled
        case .notRegistered:
            return .disabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .unavailable
        @unknown default:
            return .failed
        }
    }

    public func register() throws {
        guard #available(macOS 13.0, *) else { throw LaunchAtLoginError.unsupported }
        do {
            try SMAppService.mainApp.register()
        } catch {
            throw LaunchAtLoginError.registrationFailed(String(describing: error))
        }
    }

    public func unregister() throws {
        guard #available(macOS 13.0, *) else { throw LaunchAtLoginError.unsupported }
        do {
            try SMAppService.mainApp.unregister()
        } catch {
            throw LaunchAtLoginError.registrationFailed(String(describing: error))
        }
    }

    /// 应用决策：读当前状态 → 算计划 → 执行 → 返回执行后的真实状态。
    /// 失败不抛给调用方（界面只关心「最终成没成」），但状态一定如实反映。
    @discardableResult
    public func apply(desired: Bool) -> LaunchAtLoginStatus {
        let plan = LaunchAtLoginDecision.plan(desired: desired, current: status)
        switch plan.action {
        case .register:
            try? register()
        case .unregister:
            try? unregister()
        case .requestApproval, .none:
            break
        }
        return status
    }
}
