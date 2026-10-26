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
    static func post(title: String, body: String) {
        guard let center = center else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content,
                                            trigger: nil)
        center.add(request)
    }

    /// 没有 bundle 标识的进程（`swift test` 宿主）里取中心会抛 ObjC 异常 ⇒ 先判。
    private static var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }
}
