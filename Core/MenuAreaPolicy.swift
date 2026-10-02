import Foundation

/// 菜单项 ↔ 活动栏分区的**归属表**（2026-10-02 需求提出者口径）。
///
/// 需求原话：「**菜单显示应该与活动栏当前的选择相关联**，比如用户选了数据库才会有 file 菜单里的
/// 新建查询。现在不关联，导致新建了一个查询，界面还是停留在 workspace」。
///
/// ## 两条纪律，别混成一条
///
/// ① **显示**（本文件 + `MainMenuLocalizer.syncAreaVisibility`）：只属于某个区的命令，
///    只在**那个区被选中时**出现在菜单里；
/// ② **动作**（`AppState.newQueryTab()` / `DoyahStudioCommands` 里那个浏览器页签按钮）：
///    命令一旦执行，先把界面**切到它所属的区** —— 只做①的话，用快捷键、命令面板或
///    历史习惯仍会「建在看不见的地方」（他实测到的就是这个症状）。
///
/// ## 为什么表在 Core、改菜单的动作在 App
///
/// 表是**纯映射**（键 → 区），可判据化、与 AppKit 无关；动 `NSMenuItem` 的那一半只能在 App 侧
/// （`.commands {}` 的叶子项 SwiftUI 不重建 ⇒ 条件菜单项在这儿不成立，见 `MainMenuLocalizer`）。
///
/// ## 表外的键 = 与区无关
///
/// 语言 / 外观 / 设置 / 关于这类**应用级**命令不属于任何区，任何区都显示 —— 所以这里**没有**兜底
/// 「默认归某个区」的分支：漏登记的后果是「该项到处都显示」（回到改动前的行为），不是「被藏起来
/// 找不到」。这一条是刻意选的：**藏错东西比多显示一项糟得多**。
public enum MenuAreaPolicy {

    /// 菜单项文案键 → 它所属的活动栏区（`nil` = 与区无关、任何区都显示）。
    public static func owner(of key: LKey) -> ActivityBarItem? {
        switch key {
        // 「文件 · 新建」那一组（`DoyahStudioCommands`）：页签长在哪个区，命令就归哪个区。
        case .menuNewQuery: return .database
        case .menuNewBrowserTab: return .workspace
        // 笔记本身就是一个区（DOYAH-01）⇒ 它只在笔记区显示。
        case .menuNotes: return .notes
        default: return nil
        }
    }

    /// 当前选中区下，这一项**该不该出现在菜单里**。
    public static func isVisible(key: LKey, in area: ActivityBarItem) -> Bool {
        guard let owner = owner(of: key) else { return true }
        return owner == area
    }

    /// 表里**登记过的**键（判据用来钉住「表不许悄悄变空 / 悄悄多一行」，也用来对账菜单键表）。
    ///
    /// 顺序 = `owner(of:)` 里的登记顺序；判据会断言它与 `MenuLocalization.menuKeys` 有交集，
    /// 免得将来有人把菜单键改名、表却照旧 —— 那种漂移的表现是「联动静默失效」。
    public static var registeredKeys: [LKey] {
        [.menuNewQuery, .menuNewBrowserTab, .menuNotes]
    }
}

public extension Notification.Name {
    /// 活动栏选中区变了（`object` = 落定后的 `ActivityBarItem`）。
    ///
    /// 为什么走通知而不是让菜单层持有 `AppState`：菜单栏那一层（`MainMenuLocalizer`）是 AppKit 的
    /// 东西，它**不订阅视图模型**；而选中区的**唯一写入口**是 `AppState.selectActivityItem(_:)`，
    /// 在那里发一条广播，两边就不必互相认识。
    static let doyahActivityItemChanged = Notification.Name("doyah.activityItemChanged")
}
