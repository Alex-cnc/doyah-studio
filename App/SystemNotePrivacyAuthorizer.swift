import Foundation
import LocalAuthentication
import DoyahCore

/// 私密笔记的**二次验证**（`FR-NTS-NOTE-PRIVACY-001`「需二次验证才可查看」）。
///
/// 为什么走 `LocalAuthentication` 而不是自制密码框：
///   · 需求原文「防的是别人拿到你解锁着的设备随手翻」—— 系统验证（Touch ID / 登录密码）
///     正是「证明现在操作的是本人」这件事的平台口径；
///   · 自制密码要自己管盐、管重试、管遗忘，**每一件都可能比不加密更危险**。
///
/// 失败方向：`evaluatePolicy` 抛错（用户取消 / 没通过 / 设备不支持）一律**拒绝**，不降级放行 ——
/// 这是保护挡位，「看不见」才是安全的那一边（与 `DenyingNotePrivacyAuthorizer` 同一条口径）。
struct SystemNotePrivacyAuthorizer: NotePrivacyAuthorizing {

    func authorize(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = nil
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // 设备没有任何可用验证方式（没设密码且没有生物识别）：**拒绝**，不给「那就直接看吧」。
            return false
        }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }
}
