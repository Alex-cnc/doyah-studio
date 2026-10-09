import Foundation

/// 活动栏的**视图切换项**（FR-EDIT-32）。
///
/// 为什么把「切视图」与「动作」分成两个类型（`ActivityBarItem` / `ActivityBarAction`）：
/// 它们在同一根窄条上，但语义完全不同 —— 切换项有**选中态**、会变右侧面板；
/// 动作（设置 / 账户）没有选中态，只是按钮。混成一个枚举，
/// 迟早会出现"设置被选中了、右侧面板变成设置页"这种结构性问题。
public enum ActivityBarItem: String, CaseIterable, Sendable, Identifiable {
    // **顺序 = 栏上的上下位置**（2026-09-25 需求提出者：「活动栏排序调整一下：工作区在最上面」）。
    // `allCases` 的顺序就是显示顺序，所以"谁在上面"只由这里的声明顺序决定 ——
    // 别在视图里再排一次（两处顺序迟早不一致）。
    case workspace
    case database
    /// 笔记（DOYAH-01）：**Standard 版只有它**（许可证决定显示哪几项）。
    case notes
    /// 周报（Retro）：**不挂授权 ⇒ 全档可见**（片 `M7-HOST` · 派单 `T-20261009-080`）。
    ///
    /// 为什么不给它能力位：`M7` 判据 ① 要的是「**活动栏 Retro 入口可见**」，
    /// 而 Retro 是「报告阅读器」，不是按档位卖的区（三档里卖的是workspace / database / notes）。
    /// 于是它的可见性判据 = 「恒真」这一条（见 `LicensePresentation.activityItems`），
    /// `LicenseCapabilities` 的能力位**一个都不加**（加一个就等于改了卖点矩阵）。
    case retro

    public var id: String { rawValue }

    /// SF Symbol 名。窄条上图标就是全部信息量，所以选型要保证剪影可辨。
    public var symbolName: String {
        switch self {
        case .database: return "cylinder.split.1x2"
        case .workspace: return "folder"
        case .notes: return "note.text"
        case .retro: return "newspaper"
        }
    }

    /// 悬停提示与无障碍标签。
    public var titleKey: LKey {
        switch self {
        case .database: return .activityDatabase
        case .workspace: return .activityWorkspace
        case .notes: return .activityNotes
        case .retro: return .activityRetro
        }
    }

    /// 切换视图的菜单项文案（⇧⌘ 之外还给 ⌘1 / ⌘2）。
    public var menuKey: LKey {
        switch self {
        case .database: return .menuViewDatabase
        case .workspace: return .menuViewWorkspace
        case .notes: return .menuViewNotes
        case .retro: return .menuViewRetro
        }
    }

    /// 持久化键：与工程内其它 UI 偏好同一套 `ui.` 前缀。
    public static let storageKey = "ui.activityBarItem"

    /// 由持久化的 id 解析；**未知值一律回退到数据库视图**而不是报错
    /// （配置被手改、或将来删掉某个视图时，界面都必须照常起来）。
    public static func resolve(id: String?) -> ActivityBarItem {
        guard let id, !id.isEmpty else { return .database }
        return ActivityBarItem(rawValue: id) ?? .database
    }

    /// 菜单快捷键：⌘1 / ⌘2 / ⌘3（与 VS Code 的"按序号切视图"同一习惯）。
    ///
    /// 序号**跟着栏上的顺序**走：栏上第一项就是 ⌘1。写死成"数据库 = ⌘1"会让
    /// "按序号切视图"这条习惯失灵（用户按 ⌘1 期待的是最上面那个）。
    ///
    /// 正因为如此，序号**必须由"当前栏上可见的那几项"算**，不能写死在项上：
    /// 栏上有哪几项由许可证决定（Standard 只有笔记），Standard 下笔记就是 ⌘1，
    /// Ultra 下它才是 ⌘3。传可见列表进来，两处顺序就不可能不一致。
    /// 不可见 = 没有序号（返回 nil）—— 快捷键不该指向一个栏上不存在的视图。
    public static func shortcutIndex(
        of item: ActivityBarItem,
        in visibleItems: [ActivityBarItem]
    ) -> Int? {
        guard let position = visibleItems.firstIndex(of: item) else { return nil }
        return position + 1
    }
}

/// **窗口标题**（FR-EDIT-37，2026-09-30 需求提出者）。
///
/// 需求原话：「软件主界面的标题就是一个 Doyah Studio 太浪费了，应该在活动栏来回切换时标题要跟着变
/// 成 Doyah Studio - Workspace，Doyah Studio - Database，Doyah Studio - Notes，Doyah Studio - Retro
/// 这种，标题后面居中可以放一个长长的搜索栏」。
///
/// 三条口径：
///  ① **品牌段不翻译**（产品名），**视图名走语言表** ⇒ 中文界面出「Doyah Studio - 数据库」、
///     英文界面出「Doyah Studio - Database」（他给的那组英文正是英文界面的形状）；
///  ② **标题由活动栏项派生**（`ActivityBarItem.titleKey`），这里不另存一份视图名 ——
///     将来 Retro 模块进活动栏那天，标题自动跟上，不需要再改这个文件；
///  ③ 拼装在 Core 而**文案不在 Core**：两段都由调用方从语言表取（R-45 的棘轮压着 Core 里的中文字面量）。
///
/// 品牌名与视图名之间的分隔符也收在这里：两处各写一遍「 - 」迟早会漂。
public enum WindowTitle {
    public static let separator = " - "

    /// `Doyah Studio - Database`。
    public static func text(brand: String, suffix: String) -> String {
        brand + separator + suffix
    }
}

/// 活动栏底部的**动作**（不是视图）。
public enum ActivityBarAction: String, CaseIterable, Sendable, Identifiable {
    case account
    case settings

    public var id: String { rawValue }

    public var symbolName: String {
        switch self {
        case .account: return "person.crop.circle"
        case .settings: return "gearshape"
        }
    }

    public var titleKey: LKey {
        switch self {
        case .account: return .activityAccount
        case .settings: return .activitySettings
        }
    }
}
