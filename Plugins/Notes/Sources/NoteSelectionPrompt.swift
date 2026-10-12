import Foundation

// 批量多选与拖拽的**规则那一半** —— 队列 `L-97` 界面半第五片（④ 的最后两件：批量多选 + 拖拽）。
//
// 契约出处 = `DoyahNotes/Docs/核心契约.md` §2.12：
//   · 第 1 条：架 → 笔记本 → **笔记**，层层有归属、**笔记不直接属于架** —— 所以拖拽的落点**只有笔记本行**
//     （架行与「全部」行不接落点：接了就表示笔记能挂在架上，那是契约不允许的形状）；
//   · 第 4 条：移动**只改归属、不刷新 `updatedAt`**（落库那一半在 `NoteLibrary.move`，本片不碰）。
//
// 四条口径写在这里，视图与 `AppState` 只许引用：
//
//   ① **修饰键语义**（`NoteSelectionRule.clicked`）：无修饰 = 单选 + 打开编辑（原来的行为）；
//      ⌘ = 切换这一条（锚点跟到它）；⇧ = 从锚点连选到这一条（**闭区间**、锚点不动，可以连着往外扩）。
//      ⇧ 而锚点已不在可见次序里（范围换了 / 那条被删了）⇒ **退化成单选、且不打开编辑** ——
//      猜一个起点猜错，就是把用户没打算选的笔记选上（宁可不选，不许替用户选）。
//
//   ② **选中集合必须随时对着可见列表收一遍**（`pruned`）：范围切了 / 搜出别的结果 / 那条被删了，
//      集合里就会留着界面上看不见的条目 —— 那时「已选 3 条」里有 1 条不在屏幕上，批量移动
//      会带走一条用户看不见的笔记（`L-50` 同族：看不见却生效是最坏的一种）。**空列表 ⇒ 空集合**。
//
//   ③ **拖一条时带走哪些**（`draggedNoteIDs`）：这一条**在选中集合里且集合不止一条** ⇒ 拖**整捆**
//      （顺序 = 可见次序）；否则**只拖这一条** —— 不许「顺手把没选中的行也带上」。
//
//   ④ **落点计划**（`NoteDropRule.plan`）：认不出的目标 uid ⇒ 默认笔记本（与树上 / 移动菜单同一条兜底）；
//      已经在目标里的那几条**不算要动的**（整捆都已在 ⇒ `isNoop`：界面给一句人话、不写库）。
//
// 本片**不落库、不碰存储**（那半第 164 轮已落：`NoteDatabase.move`，`ON CONFLICT` 不含归属列）——
// 这里只有可单测的纯函数、载荷编解码与文案键。

/// 行上读到的修饰键（视图从当前事件取；Core 不认识 AppKit）。
public struct NoteSelectionModifiers: OptionSet, Sendable, Equatable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let command = NoteSelectionModifiers(rawValue: 1 << 0)
    public static let shift = NoteSelectionModifiers(rawValue: 1 << 1)
}

/// 一次点击之后：选中集合、新的锚点、要不要打开编辑面（`nil` = 不动编辑面）。
public struct NoteSelectionOutcome: Equatable, Sendable {
    public let selection: Set<UUID>
    public let anchor: UUID?
    public let edited: UUID?

    public init(selection: Set<UUID>, anchor: UUID?, edited: UUID?) {
        self.selection = selection
        self.anchor = anchor
        self.edited = edited
    }
}

/// 多选规则（**唯一出处**）。
public enum NoteSelectionRule {

    /// 一次点击的结果。`ordered` = 当前**看得见**的次序（⇧ 的范围只在看得见的行之间发生）。
    public static func clicked(
        _ id: UUID,
        modifiers: NoteSelectionModifiers,
        ordered: [UUID],
        selection: Set<UUID>,
        anchor: UUID?
    ) -> NoteSelectionOutcome {
        if modifiers.contains(.command) {
            var next = selection
            if next.contains(id) { next.remove(id) } else { next.insert(id) }
            return NoteSelectionOutcome(selection: next, anchor: id, edited: nil)
        }
        if modifiers.contains(.shift),
           let anchor,
           let from = ordered.firstIndex(of: anchor),
           let to = ordered.firstIndex(of: id) {
            let range = from <= to ? ordered[from...to] : ordered[to...from]
            return NoteSelectionOutcome(selection: Set(range), anchor: anchor, edited: nil)
        }
        // 无修饰点击；或 ⇧ 而没有可用的锚点。两种都是单选，但只有**无修饰**那一种打开编辑面。
        let opensEditor = !modifiers.contains(.shift)
        return NoteSelectionOutcome(selection: [id], anchor: id, edited: opensEditor ? id : nil)
    }

    /// 把选中集合收一遍：只留**还在可见列表里**的那些（空列表 ⇒ 空集合）。
    public static func pruned(_ selection: Set<UUID>, within visible: [UUID]) -> Set<UUID> {
        selection.intersection(visible)
    }

    /// 拖这一条时带走哪些（见口径 ③）。
    public static func draggedNoteIDs(clicked id: UUID, selection: Set<UUID>, ordered: [UUID]) -> [UUID] {
        if selection.count > 1, selection.contains(id) {
            return ordered.filter { selection.contains($0) }
        }
        return [id]
    }
}

/// 拖拽载荷：一串笔记 id（`String` —— SwiftUI 的 `draggable` / `dropDestination` 直接吃它）。
///
/// 编码与解码**只此一处**：视图不许自己拼字符串。拼法与解法不一致的症状是「拖过去什么都没发生」，
/// 而拖拽失败**没有任何报错** —— 属于最难查的一类。
public enum NoteDragPayload {

    /// 前缀：与普通文本拖拽区分开（不认识的前缀 ⇒ 空数组，**不猜**）。
    public static let scheme = "doyah-note-ids:"

    public static func encode(_ noteIDs: [UUID]) -> String {
        scheme + noteIDs.map(\.uuidString).joined(separator: ",")
    }

    public static func decode(_ raw: String) -> [UUID] {
        guard raw.hasPrefix(scheme) else { return [] }
        let body = String(raw.dropFirst(scheme.count))
        guard !body.isEmpty else { return [] }
        return body.split(separator: ",").compactMap { UUID(uuidString: String($0)) }
    }
}

/// 一次落点要写的东西（纯逻辑算出来的计划，本身不写库）。
public struct NoteDropPlan: Equatable, Sendable {
    public let targetNotebookUid: String
    public let targetNotebookName: String
    /// 真正要动的那些（已经待在目标里的**不在其中**）。
    public let movingNoteIDs: [UUID]
    /// 拖过来的这一捆里已经在目标里的条数（界面据此如实交代）。
    public let alreadyThereCount: Int

    public init(
        targetNotebookUid: String,
        targetNotebookName: String,
        movingNoteIDs: [UUID],
        alreadyThereCount: Int
    ) {
        self.targetNotebookUid = targetNotebookUid
        self.targetNotebookName = targetNotebookName
        self.movingNoteIDs = movingNoteIDs
        self.alreadyThereCount = alreadyThereCount
    }

    /// 一个都不用动（整捆都已经在目标里）—— 界面据此给一句人话、**不写库**。
    public var isNoop: Bool { movingNoteIDs.isEmpty }
}

/// 落点规则（**唯一出处**）。
public enum NoteDropRule {

    /// 能接落点的容器种类：**只有笔记本**（契约 §2.12 第 1 条：笔记不直接属于架）。
    /// 界面据此决定在哪一行挂 `.dropDestination` —— 架行 / 「全部」行不接。
    public static func acceptsDrop(kind: NotebookContainerKind) -> Bool {
        kind == .notebook
    }

    /// 落点计划：解析目标 → 摘出真正要动的那些。
    /// 归属解析走 `NotesNavigation.notebookUid(forNote:)`（缺归属 / 认不出 ⇒ 默认笔记本），
    /// 本文件不另写一遍兜底 —— 与树上、与移动菜单必须是同一条路。
    public static func plan(
        noteIDs: [UUID],
        toNotebook notebookUid: String,
        directory: NotebookDirectory,
        placements: [NotebookPlacement]
    ) -> NoteDropPlan {
        let target = directory.resolvedNotebookUid(notebookUid)
        let navigation = NotesNavigation(directory: directory, placements: placements)
        let moving = noteIDs.filter { navigation.notebookUid(forNote: $0.uuidString) != target }
        return NoteDropPlan(
            targetNotebookUid: target,
            targetNotebookName: directory.notebook(uid: target)?.name ?? "",
            movingNoteIDs: moving,
            alreadyThereCount: noteIDs.count - moving.count
        )
    }
}

/// 文案键（唯一出处）。
public enum NoteSelectionPrompt {
    /// 右键里那一项（批量时）：移动选中的 N 条…（`%d` = 条数）。
    public static let moveSelectionKey: LKey = .notesMoveSelectedMenu
    /// 列表上方那一行「已选 N 条」（`%d` = 条数）。
    public static let countKey: LKey = .notesSelectionCount
    /// 整捆都已经在那一格里时给的人话（`%@` = 目标笔记本名）。
    public static let alreadyThereKey: LKey = .notesDropAlreadyThere
    /// 行上的悬停提示（可拖到左边的笔记本上）。
    public static let dragHintKey: LKey = .notesDragHint
}
