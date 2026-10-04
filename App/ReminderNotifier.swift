import DoyahCore
import Foundation
import UserNotifications

/// 系统通知的**投递面**（队列 `L-100` 落法 ④：一键挂提醒 → 授权 → 到点投递）。
///
/// ## 为什么是一个协议
///
/// 契约（`DoyahNotes/Docs/核心契约.md` §2.10 末尾）把「系统通知怎么发（权限 / 通知渠道 / 后台唤起 /
/// 免打扰）」明确划给**各端适配层**。适配层的东西在这个工程里有两条硬纪律：
///
///  ① **判定不写在适配器里**：排不排由 `ReminderPresentation.notificationDecision` 说了算
///     （那一格已经有用例逐格钉住），适配器只做**执行**（读权限 / 问权限 / 排 / 撤）；
///  ② **界面不直接摸系统框架**：`AppState` 只认这个协议 —— 于是「谁去碰 `UNUserNotificationCenter`」
///     在源码上是一处，而不是散在各视图里。
///
/// ## 已知边界（如实登记）
///
///  ① **到点响不响属人工点验**：无头环境里没有通知权限、也没有通知中心，只能力保「请求的形状对」；
///  ② **免打扰 / 通知渠道**是系统设置面，本端如实不碰（契约把这几项一并划给适配层，
///     但它们是**用户选择**，不是应用能代替决定的）；
///  ③ `UNUserNotificationCenter.current()` 在**没有 bundle 标识**的进程里会抛 ObjC 异常
///     （`swift test` 这类宿主）⇒ 本文件先判 `Bundle.main.bundleIdentifier`，
///     读不出就一路回「未决」，**不让测试宿主崩**。
protocol ReminderDelivering: Sendable {

    /// 现在的权限那一档（读不出来 ⇒ 未决）。
    func permission() async -> ReminderPermission

    /// 问一次系统权限（用户已经选过 ⇒ 直接回那一档，不再弹框）。
    func requestPermission() async -> ReminderPermission

    /// 排上一条通知（`triggerEpochMillis` 由 Core 现算，这里只执行）。
    func schedule(id: UUID, title: String, body: String?, triggerEpochMillis: Int) async

    /// 撤掉一条已经排上的通知（**删了提醒却不撤** = 到点照样响）。
    func cancel(id: UUID) async
}

/// 走 `UserNotifications` 的实现（macOS 适配层）。
///
/// 权限档的映射：`.authorized` / `.provisional` / `.ephemeral` 都算**已授权**
/// （`provisional` 是「静默投递」那一档 —— 通知真的会到，只是不打扰；把它判成「未决」会让
/// 已经同意过的用户被反复问）；`.denied` ⇒ 被拒；`.notDetermined` 与任何将来新增的档 ⇒ **未决**
/// （与 `ReminderPermission.normalized` 同一条兜底纪律：排在安全侧）。
struct SystemReminderDeliverer: ReminderDelivering {

    func permission() async -> ReminderPermission {
        guard let center = Self.center else { return .notDetermined }
        let settings = await center.notificationSettings()
        return Self.permission(from: settings.authorizationStatus)
    }

    func requestPermission() async -> ReminderPermission {
        guard let center = Self.center else { return .notDetermined }
        let settings = await center.notificationSettings()
        // 用户已经选过 ⇒ **不再弹框**（`requestAuthorization` 对已决定的用户是空操作，
        // 但把它读成「刚刚问了」就会在界面上说错话）。
        if settings.authorizationStatus != .notDetermined {
            return Self.permission(from: settings.authorizationStatus)
        }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        let after = await center.notificationSettings()
        return Self.permission(from: after.authorizationStatus)
    }

    func schedule(id: UUID, title: String, body: String?, triggerEpochMillis: Int) async {
        guard let center = Self.center else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        if let body, !body.isEmpty { content.body = body }
        content.sound = .default
        // 触发面用**日历日时分**而不是「还有多少秒」：这台机器休眠 / 用户改时区之后，
        // 秒数那种会在错误的一刻响（`dateComponents` 由系统按当时日历解）。
        let date = Date(timeIntervalSince1970: Double(triggerEpochMillis) / 1000)
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: date
        )
        let request = UNNotificationRequest(
            identifier: id.uuidString,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
        try? await center.add(request)
    }

    func cancel(id: UUID) async {
        guard let center = Self.center else { return }
        center.removePendingNotificationRequests(withIdentifiers: [id.uuidString])
        center.removeDeliveredNotifications(withIdentifiers: [id.uuidString])
    }

    /// 没有 bundle 标识的进程（`swift test` 宿主）里取中心会抛 ObjC 异常 ⇒ 先判。
    private static var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }

    private static func permission(from status: UNAuthorizationStatus) -> ReminderPermission {
        switch status {
        case .authorized, .provisional, .ephemeral: return .authorized
        case .denied: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }
}
