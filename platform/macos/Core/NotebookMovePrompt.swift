import Foundation

// 跨笔记本移动的**界面那一半**：目标清单 + 「能不能去」的规则 + 文案键 —— 队列 `L-97` 界面半第三片（④）。
//
// 契约出处 = `DoyahNotes/Docs/核心契约.md` §2.12 第 4 条：移动**只改归属、不刷新 `updatedAt`**
// （位置不是内容）。落库那一半第 164 轮已落（`NoteDatabase.move`，`ON CONFLICT` 不含归属列）。
//
// 两条口径写在这里，视图与 `AppState` 只许引用：
//   ① **当前所在的那一格不算候选**（`isCurrent`）—— 摘掉的是「点了什么都没发生」那一项
//      （`L-50`：可点却静默无反应是最坏的一种）；它仍在清单里，照实画「你现在在这儿」；
//   ② **一个可去的地方都没有**（库里只有一个笔记本）⇒ 清单非空却选不动 ⇒ 界面给一句人话，
//      而不是一个空菜单（空菜单会被读成「这个功能没做」）。
//
// `noteIDs` 是复数：单条移动与批量移动是**同一份规则**（当前格 = 选中的笔记都已在的那一格；
// 跨格时不标任何一格 —— 「一半在这、一半在那」没有单一当前格）。本片界面只接单条右键，
// 批量多选留给下一片（如实登记）。

public struct NotebookMoveTarget: Identifiable, Equatable, Sendable {

    /// 目标笔记本的 uid（也是菜单项的标识）。
    public let id: String
    public let name: String
    /// 它所在的架（菜单按架分组 —— 同名笔记本靠架名才分得清）。
    public let shelfUid: String
    public let shelfName: String
    /// 选中的这些笔记**是不是都已经在这个笔记本里**（是 ⇒ 这一项不给选）。
    public let isCurrent: Bool

    public init(id: String, name: String, shelfUid: String, shelfName: String, isCurrent: Bool) {
        self.id = id
        self.name = name
        self.shelfUid = shelfUid
        self.shelfName = shelfName
        self.isCurrent = isCurrent
    }

    /// 能不能选它 —— 规则只此一处（视图的 `.disabled` 读它，不许各写一遍判断）。
    public var isSelectable: Bool { !isCurrent }
}

/// 规则与文案键（**唯一出处**）：菜单标题、「没地方可去」那句话、当前格的后缀。
public enum NotebookMovePrompt {

    /// 笔记行右键里的那一项（菜单标题）。
    public static let menuTitleKey: LKey = .notesMoveMenu
    /// 一个可去的地方都没有时给的一句人话（菜单里那一项**灰着**，理由写在字面上）。
    public static let noTargetKey: LKey = .notesMoveNoOtherNotebook
    /// 目标那一行上「你现在在这儿」的后缀（当前格不给选，但照实画出来）。
    public static let currentMarkKey: LKey = .notesMoveCurrentMark

    /// 目标清单：**顺序 = 树上看到的顺序**（架排序位 → 笔记本排序位，与 `NotesNavigation` 同一份稳定排序）。
    ///
    /// 兜底与树同一条路（契约 §2.12 第 2 条）：缺归属行 / 认不出的 uid ⇒ 算默认笔记本 ——
    /// 走 `NotesNavigation.notebookUid(forNote:)`，本文件不另写一遍兜底。
    public static func targets(
        directory: NotebookDirectory,
        placements: [NotebookPlacement],
        noteIDs: [UUID]
    ) -> [NotebookMoveTarget] {
        let navigation = NotesNavigation(directory: directory, placements: placements)
        let current = Set(noteIDs.map { navigation.notebookUid(forNote: $0.uuidString) })
        // 只有一个当前格时才标「当前」；跨格批量移动一个都不标（没有单一当前格可标）。
        let marked = current.count == 1 ? current.first : nil
        return directory.sortedShelves.flatMap { shelf in
            directory.notebooks(inShelf: shelf.uid).map { notebook in
                NotebookMoveTarget(
                    id: notebook.uid,
                    name: notebook.name,
                    shelfUid: shelf.uid,
                    shelfName: shelf.name,
                    isCurrent: notebook.uid == marked
                )
            }
        }
    }

    /// 有没有可去的地方 —— 界面据此决定「画清单」还是「画那句话」。
    public static func hasDestination(_ targets: [NotebookMoveTarget]) -> Bool {
        targets.contains { $0.isSelectable }
    }
}

