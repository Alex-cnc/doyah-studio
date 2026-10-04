import Foundation

/// 「提醒」那一区在界面上该长什么样 —— 队列 `L-100` 落法 ④（一键挂提醒）的**界面入口半**。
///
/// ## 为什么在 `ReminderPresentation` 之外再加一层
///
/// `ReminderPresentation` 回答的是三个**单点问题**：能不能挂（`attachment`）、排不排
/// （`notificationDecision`）、那句话怎么说（`summary` / `nextText`）。而界面上那一区要的是
/// **一份合成答案**：四个档位 + 当前选中档 + 已经挂着的那一条是哪一档 + 那一句人话 + 权限那一档的话
/// + 「挂提醒」这枚按钮该不该能按。
///
/// 四个问题各调一次到视图里，就会多出两处**只有视图有**的口径：
///  ① 「已经挂着的那一条是**哪一档**」——库里没有档位列（也不该有：档位是派生量），视图自己比一遍
///     就会在改档位枚举时漏改一处，症状是「明明挂着，四个档位却一个都没选中」；
///  ② 「没有提醒时那一份 `plan` 是什么」——视图各写一遍就会出现有的地方 `nil`、有的地方拿默认值，
///     权限那一格的话也就跟着飘。
///
/// 所以合成**只此一处**，视图只读结果。
///
/// ## 三条纪律（与 `ReminderPresentation` 同一条）
///
///  ① **不读系统时钟、不读系统时区**：`now` 与 `zoneOffsetMillis` 都从参数进来（形状判据钉住
///     四个 token —— 系统时钟 / 系统时区 / 平台日历 / 通知框架 —— 在本文件里零命中）；
///  ② **不碰库、不碰通知框架**：落库只有门面一条路，投递只有 `App/` 那一层的适配器一条路；
///  ③ **不抛错**：认不出的东西一律「当没给」（`existingPreset` 回 `nil`），照实显示，不编。
public struct ReminderEntry: Equatable, Sendable {

    /// 档位空间（**唯一来源** `ReminderPreset.allCases` —— 界面不许自己列一遍）。
    public var presets: [ReminderPreset]

    /// 当前选中的档位（界面状态；默认档由 Core 给）。
    public var preset: ReminderPreset

    /// 当前档位下**能不能挂**（不能挂 ⇒ 带原因键，界面据它说一句人话）。
    public var attachment: ReminderAttachment

    /// 已经挂着的那一条的规则（没有 ⇒ `nil`）。
    public var spec: ReminderSpec?

    /// 已有那条的**档位回显**（重算不出来 ⇒ `nil`：界面上一档都不选中，但仍照实显示那条规则）。
    public var existingPreset: ReminderPreset?

    /// 已有那条的**求解结果**（没有 ⇒ 规则认不出那一档）—— 「下次 …」那一句的输入。
    public var plan: ReminderPlan

    /// 系统通知权限那一档（端侧唯一的读数处把值传进来）。
    public var permission: ReminderPermission

    /// 该不该把这条提醒交给系统通知。
    public var decision: ReminderNotificationDecision

    /// 这一条任务上**已经挂着**一条提醒吗。
    public var hasReminder: Bool { spec != nil }

    /// 当前档位算得出规则吗（「挂提醒」这枚按钮的灰着条件）。
    public var canAttach: Bool { attachment.spec != nil }

    /// 合成一区的状态（**唯一的合成处**）。
    ///
    /// `plan` 由 `existing` 与 `now` 现算（**不落库** —— 同一个原因见 `ReminderSchedule`：存下来就有
    /// 两个事实源）；没有 `existing` 时给一个「规则认不出」的 `plan`，让 `decision` 也有一格确定的答案
    /// （界面在没有提醒时不画那一句，但它**不该是随机的**）。
    public static func make(
        dueAt: Date?,
        preset: ReminderPreset,
        existing: ReminderSpec?,
        permission: ReminderPermission,
        now: Date,
        zoneOffsetMillis: Int
    ) -> ReminderEntry {
        let nowMoment = ReminderPresentation.moment(of: now, zoneOffsetMillis: zoneOffsetMillis)
        let plan: ReminderPlan = existing.map {
            ReminderSchedule.next(spec: $0, fromDate: nowMoment.date, fromMinute: nowMoment.minute)
        } ?? ReminderPlan(ok: false, state: .invalid, code: ReminderCode.invalid, due: .none)
        return ReminderEntry(
            presets: ReminderPreset.allCases,
            preset: preset,
            attachment: ReminderPresentation.attachment(
                dueAt: dueAt, preset: preset, zoneOffsetMillis: zoneOffsetMillis
            ),
            spec: existing,
            existingPreset: existing.flatMap {
                ReminderPresentation.preset(of: $0, dueAt: dueAt, zoneOffsetMillis: zoneOffsetMillis)
            },
            plan: plan,
            permission: permission,
            decision: ReminderPresentation.notificationDecision(
                permission: permission, plan: plan, zoneOffsetMillis: zoneOffsetMillis
            )
        )
    }
}
