import Foundation

// **跨架移动**（把一个笔记本从一个架挪到另一个架）的界面那一半：目标清单 + 「能不能去」的规则 + 文案键
// —— 队列 `L-97` 界面半第六片（落法 ① 的第四格「跨架移动」）。
//
// 与 `NotebookMovePrompt`（笔记跨笔记本）是**同族不同物**：那一份搬的是**笔记**（改 `notebook_uid`），
// 这一份搬的是**笔记本**（改 `shelf_uid`）。两件事共用三条口径，所以形状刻意保持一致：
//
//   ① **当前所在的那一格不算候选**（`isCurrent`）—— 摘掉的是「点了什么都没发生」那一项
//      （`L-50`：可点却静默无反应是最坏的一种）；它仍在清单里，照实画「你现在在这儿」；
//   ② **一个可去的地方都没有**（库里只有一个架）⇒ 清单非空却选不动 ⇒ 界面给一句人话，
//      而不是一个空菜单（空菜单会被读成「这个功能没做」）；
//   ③ **顺序 = 树上看到的顺序**（架排序位）—— 与 `NotesNavigation` / `NotebookMovePrompt`
//      同一份稳定排序，本文件不另排一遍。
//
// 落库那一半在 `NoteDatabase.move(notebookUid:toShelf:)`：只改 `shelf_uid` + 排序位，
// **不碰** `created_at` / `is_default` —— 挪架不是改名、也不是删（契约 §2.12 第 2 条：
// 默认容器不可删、可改名）。
//
// 本文件**不落库、不碰界面**（界面在 `App/Views/NotesPanel.swift`）—— 只有可单测的纯函数与文案键。

/// 跨架移动菜单里的一项（一个候选目标架）。
public struct NotebookShelfMoveTarget: Identifiable, Equatable, Sendable {

    /// 目标架的 uid（也是菜单项的标识）。
    public let id: String
    public let name: String
    /// 这个笔记本**是不是已经在这个架里**（是 ⇒ 这一项不给选，但仍照实画出来）。
    public let isCurrent: Bool

    public init(id: String, name: String, isCurrent: Bool) {
        self.id = id
        self.name = name
        self.isCurrent = isCurrent
    }

    /// 能不能选它 —— 规则只此一处（视图的 `.disabled` 读它，不许各写一遍判断）。
    public var isSelectable: Bool { !isCurrent }
}

/// 规则与文案键（**唯一出处**）：菜单标题、「没地方可去」那句话、当前架的后缀、落点判定。
public enum NotebookShelfMovePrompt {

    /// 笔记本行右键里的那一项（菜单标题）。
    public static let menuTitleKey: LKey = .notesMoveShelfMenu
    /// 一个可去的地方都没有时给的一句人话（菜单里那一项**灰着**，理由写在字面上）。
    public static let noTargetKey: LKey = .notesMoveNoOtherShelf
    /// 目标那一行上「你现在在这儿」的后缀（当前架不给选，但照实画出来）。
    public static let currentMarkKey: LKey = .notesMoveShelfCurrentMark

    /// 目标清单：**顺序 = 树上看到的顺序**（架排序位），与树上同一份稳定排序（`sortedShelves`）。
    ///
    /// 认不出的笔记本（已删 / uid 拼错）⇒ **空清单**：没有「它现在在哪个架」这件事，
    /// 也就谈不上「挪到别的架」；界面据此画那句人话，而不是造一个全部可点的菜单。
    public static func targets(notebookUid: String, directory: NotebookDirectory) -> [NotebookShelfMoveTarget] {
        guard let notebook = directory.notebook(uid: notebookUid) else { return [] }
        return directory.sortedShelves.map { shelf in
            NotebookShelfMoveTarget(id: shelf.uid, name: shelf.name, isCurrent: shelf.uid == notebook.shelfUid)
        }
    }

    /// 有没有可去的地方 —— 界面据此决定「画清单」还是「画那句话」。
    public static func hasDestination(_ targets: [NotebookShelfMoveTarget]) -> Bool {
        targets.contains { $0.isSelectable }
    }

    /// **落点判定**（唯一出处）：认得出的目标架才回它的 uid，下列情形一律 `nil`：
    ///
    ///   · **认不出的笔记本** —— 没有「它现在在哪个架」这件事；
    ///   · **已经在该架** —— 位置不是内容，白写一次库只是把「点了没反应」从界面挪到库里；
    ///   · **认不出的目标架** —— **不兜底到默认架**（与 `NoteLibrary.createNotebook` 同一条：
    ///     「挪到一个已经不存在的架里」与「挪到默认架里」是两件事，前者该让调用方知道目标没了）。
    ///
    /// `AppState.moveNotebook` 用它做落库前的守卫；视图的 `.disabled` 读的是清单里的 `isSelectable`
    /// —— 两者是同一条判断的两种说法（清单那一项由**同一个** `isCurrent` 算出来）。
    public static func moveDestination(
        notebookUid: String,
        targetShelfUid: String,
        directory: NotebookDirectory
    ) -> String? {
        guard let notebook = directory.notebook(uid: notebookUid) else { return nil }
        guard let shelf = directory.shelf(uid: targetShelfUid) else { return nil }
        guard notebook.shelfUid != shelf.uid else { return nil }
        return shelf.uid
    }
}
