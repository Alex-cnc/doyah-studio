import AppKit
import Foundation
import UserNotifications

/// 智能体主动通知的**系统出口**（`FR-AGT-UX-CONV-008`）。
///
/// ## 它只做执行，不做判定
///
/// 叫不叫、叫哪一档、人在不在看，全归 `Core/AgentNotifyPolicy`（阈值只有一份）；
/// 这里只把已经判好的一条投出去 —— 与提醒那一路（`ReminderDelivering`）同一条纪律：
/// **判定不写在适配器里**，否则「什么时候弹」会出现两套口径。
///
/// ## 如实登记的边界
///
/// ① **没授权时系统会静默丢弃**：本类不主动弹系统授权框（那是用户的选择，且首次弹框
///    应由用户动作触发 —— 与提醒那条一致）。页内提示条**照出**，所以「没收到系统通知」
///    不等于「什么都没告诉他」；
/// ② **到点响不响属人工点验**：无头 / 测试宿主里没有通知中心，只能力保「请求的形状对」
///    （`Bundle.main.bundleIdentifier` 为空时一路不投，`UNUserNotificationCenter.current()`
///    在没有 bundle 的进程里会抛 ObjC 异常）；
/// ③ 免打扰 / 通知渠道是系统设置面，本端不碰。
enum AgentNotificationPoster {

    /// 立刻投递一条（`trigger: nil` = 马上）。标识每次新起一个：智能体通知不是「可撤销的排期」，
    /// 撤不掉也不该被后一条覆盖。
    ///
    /// **投递前必须先要授权**（人类主人 2026-11-03 实测：「系统设置-通知列表里找不到 DoyahStudio」）：
    /// 原来这里直接 `center.add(request)`，从未调过 `requestAuthorization` ⇒
    /// ① 系统静默丢弃这条通知；② 应用**根本不会出现在「系统设置 → 通知」的列表里**
    /// （macOS 只在应用请求过授权之后才登记它）。所以用户既收不到、也找不到开关去授权。
    static func post(title: String, body: String) {
        guard let center = center else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content,
                                            trigger: nil)
        // **角标不在这里置**（2026-11-03 人类主人实机点验：「跑完 ⌘H 隐藏，Dock 没有角标」的根因）：
        // 本方法只在这条通知**真该出**时才被调用（`plan.system != nil`），而那一格被
        // `paneIsVisible`（= `NSApp.isActive`）那道闸拦住 ⇒ **App 在前台跑完时一次都不会走到这里**，
        // 把角标写在这儿等于「只有后台完成才可能有角标」。现在角标跟着收尾回调走
        // （`AgentChatModel.taskFinishedSink` → `markTaskFinished()`），与弹不弹通知无关。
        Task {
            // 首次会弹系统授权框；用户已决定过则是空操作（不会反复打扰）。
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            try? await center.add(request)
        }
    }

    /// **回到前台后清角标**（谁在 `applicationDidBecomeActive` 里调一次）。
    ///
    /// ⚠️ 用 `acknowledgeResultSeen()` 更好：这一条是**硬清**（不看有没有结果没看），
    /// 只留给退出 / 测试这类「确定没有人要看」的场合。
    @MainActor
    static func clearDockBadge() {
        unseenResult = false
        let had = NSApplication.shared.dockTile.badgeLabel != nil
        NSApplication.shared.dockTile.badgeLabel = nil
        if had { StartupLog.write("角标：已清（硬清）") }
    }

    /// 有没有一条「结果还没被人看见」—— Dock 角标的语义就是这一位。
    @MainActor
    static var hasUnseenResult: Bool { unseenResult }

    /// **App 被激活了一次**（宿主在 `didBecomeActive` 里调；`chatPaneOnScreen` = 人正看着对话页）。
    ///
    /// 判定放在这里而不是视图里，是为了「激活」与「看见」两个概念的差别**有判据可测**：
    /// 激活但没把对话页摆到眼前 ⇒ 不动角标。
    @MainActor
    static func appDidBecomeActive(chatPaneOnScreen: Bool) {
        guard chatPaneOnScreen else { return }
        acknowledgeResultSeen()
    }

    /// **看见结果了 ⇒ 收讫**（宿主在「App 激活 **且** 人正看着对话页」时调）。
    ///
    /// 为什么不能像原来那样「一激活就清」（2026-11-04 主人第二次报「⌘H 后跑完没角标」）：
    /// `didBecomeActive` 不等于「人看见那条结论」—— 切回来拿个文件、系统弹框把 App 顶到前台、
    /// 通知授权框把窗口拎起来，都会发这条通知。旧写法在这些时刻把角标**刚置上就抹掉**，
    /// 人回来时 Dock 上什么都没有。现在只有**真的把对话页摆到眼前**才算收讫。
    @MainActor
    static func acknowledgeResultSeen() {
        guard unseenResult else { return }
        unseenResult = false
        NSApplication.shared.dockTile.badgeLabel = nil
        StartupLog.write("角标：已清（人回到对话页，看过了）")
    }

    /// 「有一条结果还没被人看见」——置角标 / 收讫的唯一一位真值。
    @MainActor
    private static var unseenResult = false

    /// **这一轮收尾了 ⇒ 置 Dock 角标**（`FR-AGT-UX-CONV-008` 的兜底出口）。
    ///
    /// 归口在「收尾」而不是「投通知」这一条回调里，是 2026-11-03 人类主人实机点验的直接结论：
    /// 他跑完长任务 `⌘H` 隐藏应用，Dock 上**什么都没有**。根因不是权限也不是签名 ——
    /// 是置角标那句原来写在 `post()` 里，而 `post()` 只在 `plan.system != nil` 时才被调用，
    /// 那一格又被 `paneIsVisible`（= `NSApp.isActive`）挡住 ⇒ 在前台跑完时**一次都不走到**。
    ///
    /// 两条判据分开：`AgentNotifyPolicy` 判「要不要打扰他」（前台不弹、短任务不弹），
    /// 这一格判「有没有结果待看」—— **不判前台后台**，置上就等着他回来。
    /// 清角标走 `acknowledgeResultSeen()`（人真的看见那一页才清）。
    @MainActor
    static func markTaskFinished() {
        unseenResult = true
        let app = NSApplication.shared
        let tile = app.dockTile
        tile.badgeLabel = "1"
        // 留读数：主人说「看不到角标」时，先确认这句到底有没有被调到、以及置上读回来是什么
        // （`AgentChatModel.finish()` → sink → 这里；2026-11-04 加）。
        StartupLog.write("角标：置 1（前台=\(app.isActive) 隐藏=\(app.isHidden) "
            + "策略=\(app.activationPolicy().rawValue) 读回=\(tile.badgeLabel ?? "nil")）")
    }

    /// **启动即申请一次授权**（人类主人 2026-11-03 实测：任务跑完没弹框）。
    ///
    /// 为什么不能在 `post` 里申请：`post` 只在「面板不可见 / App 不在前台」时才会被调用
    /// （`agentChat.paneIsVisible = { NSApp.isActive }` 那条闸），用户盯着屏幕跑任务时
    /// **一次都不会走到这里** ⇒ 永远不会申请授权 ⇒ 系统设置里永远看不到本应用。
    @MainActor
    static func requestAuthorizationIfNeeded() {
        guard let center = center else { return }
        Task {
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .notDetermined else { return }
            do {
                _ = try await center.requestAuthorization(options: [.alert, .sound])
                StartupLog.write("通知授权：已请求（用户动作由系统弹框决定）")
            } catch {
                StartupLog.write("通知授权：请求失败 \(error.localizedDescription)")
            }
        }
    }

    /// 没有 bundle 标识的进程（`swift test` 宿主）里取中心会抛 ObjC 异常 ⇒ 先判。
    private static var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }
}
