import Foundation

/// **首页可配置（默认落页）** —— `FR-NTS-ALL-HOME-001` · 概设 §15.17【契约】。
///
/// 口径照四书原文搬，改这里等于改条文（**先改条文，再改这一段**）：
///  ① **只有两个取值**：待办 / 笔记 —— 存储原值钉死 `todo` / `notes`（跨端同一份偏好，
///     各端不许另起名字，也不许把「打开就待办 / 打开就笔记」写成端内常量）；
///  ② **未设置 ⇒ 待办**（`defaultPage`）：新装与老用户同一条路，默认值不随版本漂移；
///  ③ 值是**用户偏好**，键 `notes.home`；
///  ④ **页内切换不写回**：切屏是会话状态，只有设置里显式改才落这一格
///     （需求 §3.5.18「不做」那一条：不是「记住上次所在页」）。
///
/// 为什么键与解析都收在这里、而不是「设置面板写一处、启动读另一处」：
/// 键名或取值一漂，症状是「设置里改了、重启没变」或者「一端改了另一端照旧」——
/// 界面上没有报错，只有两个文件对不上。落法与 `LanguagePreference` 同形
/// （一处键 + 一处解析），机器判据在 `Tests/NoteLandingPageTests`。
public enum NoteLandingPage: String, CaseIterable, Sendable {
    /// 待办（默认档：不改老用户体感）。
    case todos = "todo"
    /// 笔记。
    case notes = "notes"

    /// 设置面板与启动读取共用的存储键（契约 §15.17 钉死 `notes.home`）。
    public static let storageKey = "notes.home"

    /// 未设置过时的落页 —— **待办**。全文只有这一处默认值常量。
    public static let defaultPage: NoteLandingPage = .todos

    /// 这一档对应笔记区里的哪一屏。
    ///
    /// 为什么不直接在界面里 `page == .todos ? .todos : .notes`：那一句一旦漏在视图里，
    /// 「偏好 → 首屏」就有了第二份实现，改档位时只改一处就会漂。
    public var module: NotesModule {
        switch self {
        case .todos: return .todos
        case .notes: return .notes
        }
    }

    /// 由存储原值解析。**没存过 / 空串 / 认不出的坏值一律落默认档** ——
    /// 不抛错、也不落第三处：一个读不懂的字符串不该把「打开落在哪」变成随机。
    public static func resolve(stored: String?) -> NoteLandingPage {
        guard let stored, let page = NoteLandingPage(rawValue: stored) else {
            return defaultPage
        }
        return page
    }

    /// 读偏好 = 冷启动落页判定的**唯一入口**（界面层不许自己去读 `UserDefaults`）。
    public static func load(from defaults: UserDefaults = .standard) -> NoteLandingPage {
        resolve(stored: defaults.string(forKey: storageKey))
    }

    /// 写偏好 = 设置面板的**唯一写入口**（页内切换不许调它，见类型注释 ④）。
    public static func store(_ page: NoteLandingPage, in defaults: UserDefaults = .standard) {
        defaults.set(page.rawValue, forKey: storageKey)
    }
}
