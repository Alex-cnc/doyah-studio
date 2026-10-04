import Foundation

// 容器编辑（**新建 / 重命名 / 排序**）的界面那一半 —— 队列 `L-97` 界面半第四片（①）。
//
// 契约出处 = `DoyahNotes/Docs/核心契约.md` **§2.12**：
//   · 第 2 条：默认架 / 默认笔记本「**不可删、可改名**」⇒ 改名对默认容器**同样可用**；
//   · 排序位（`sortOrder`）是**界面数据**（不进交换面的语义判定）⇒ 排序只写这一列。
//
// 三条口径写在这里（视图与 `AppState` 只许引用，不许各写一遍）：
//
//   ① **名字的洗净与「算不算一个名字」只有一处**（`ContainerNameRule`）。界面把「确定」灰着
//      的那条判据与 `AppState` 的守卫必须是**同一条判断**（`L-50` 那一课：两处各写一遍必分家，
//      症状是「按钮灰着但回车能提交」或反过来「满色可点、点下去静默无反应」）。
//
//   ② **新建笔记本落在哪个架**（`NotebookCreation.destinationShelfUid`）由**当前范围**决定，
//      排序位 = **该架内现有条数**（不是全局条数 —— 按全局计数会让新笔记本在架里跳到很后面，
//      而它在界面上明明是最后一个）。
//
//   ③ **排序 = 相邻一步 + 整层重排**（`ContainerReorder.plan`）：不是「交换两条的 `sort_order`」——
//      库里 `sort_order` 相同的两条（历史的默认容器都写 0）交换同一个数是**空操作**，界面上就是
//      「点了上移、什么都没动」（`L-50` 同族：可点却无反应是最坏的一种）。整层按可见次序重写成
//      `0..<n` 之后，相邻一步**一定生效**，顺带把重号的历史数据归一掉。
//
// 本片**不落库、不碰界面**（落库在 `Core/NoteStorage/*`，界面在 `App/Views/NotesPanel.swift`）——
// 这里只有可单测的纯函数与文案键。

/// 名字规则（**唯一出处**）：洗净 + 「算不算一个名字」。
///
/// **允许重名**（本片的裁决，写在这里不让它变成沉默的事实）：身份是 `uid`（契约 §2.11
/// 「指纹不是身份」同族口径），名字是给人看的标签、不是主键。禁止重名会在「同一个名字放在两个架里」
/// 这种正常用法上凭空造出一条错；界面上同名笔记本靠**架分组 / 缩进**区分（与移动菜单按架分组同一条路）。
public enum ContainerNameRule {

    /// 洗净：去掉首尾空白与换行。**只动两端** —— 名字中间的空白是用户打的，不许改写。
    public static func sanitized(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 洗净之后还剩下东西，才算一个名字（全空白 ⇒ 不算）。
    public static func isAcceptable(_ raw: String) -> Bool {
        !sanitized(raw).isEmpty
    }
}

/// 一次容器编辑的**模式**：新建与重命名走同一个弹框，但不是同一件事
/// （新建要落点、要排序位；重命名要保住 `created_at` / `is_default` / `sort_order`）。
public enum ContainerEditMode: String, Sendable, Equatable, CaseIterable {
    /// 新建一个笔记本（落到某个架里）。
    case createNotebook
    /// 改一个已有容器（架或笔记本）的名字。
    case rename
}

/// 挂在界面上的那**一次**编辑请求（弹框读它，`nil` = 没在编辑）。
public struct ContainerEditRequest: Identifiable, Equatable, Sendable {

    /// 重命名时 = 被改容器的 uid；新建时 = **目标架的 uid**。
    public let id: String
    public let mode: ContainerEditMode
    /// 重命名时 = 被改的容器种类；新建时恒为 `.notebook`。
    public let kind: NotebookContainerKind
    /// 重命名时的原名（弹框里预填它）；新建时为空串。
    public let currentName: String
    /// 新建时 = 目标架 uid；重命名时为 `nil`。
    public let destinationShelfUid: String?
    /// 是不是默认容器。**不影响能不能改名**（契约 §2.12 第 2 条：可改名）——
    /// 留着是为了让界面能如实写「默认容器删不掉、但可以改名」，而不是拿它当一道闸。
    public let isDefault: Bool

    public init(
        id: String,
        mode: ContainerEditMode,
        kind: NotebookContainerKind,
        currentName: String,
        destinationShelfUid: String?,
        isDefault: Bool
    ) {
        self.id = id
        self.mode = mode
        self.kind = kind
        self.currentName = currentName
        self.destinationShelfUid = destinationShelfUid
        self.isDefault = isDefault
    }
}

/// **新建笔记本**的落点与排序位（唯一出处）。
public enum NotebookCreation {

    /// 新建笔记本落在哪个架：在某个架里 ⇒ **那个架**；在某个笔记本里 ⇒ **它所属的架**；
    /// 「全部」⇒ **默认架**（契约里那个不可删的落点 —— 与「新建笔记落默认笔记本」同一条口径）。
    ///
    /// 认不出的范围（指向已被删掉的容器）**也走默认架**：与 `NotesNavigation.normalized` 把范围
    /// 回落「全部」同一处置 —— 用户此刻看到的就是「全部」，那就该按「全部」的落点办事。
    /// 库里连一个架都没有（还没走过一次性迁移）⇒ `nil`：界面给一句人话，**不弹一个落不了地的框**。
    public static func destinationShelfUid(for scope: NotesScope, directory: NotebookDirectory) -> String? {
        switch scope {
        case .shelf(let uid):
            if let shelf = directory.shelf(uid: uid) { return shelf.uid }
        case .notebook(let uid):
            if let notebook = directory.notebook(uid: uid) { return notebook.shelfUid }
        case .all:
            break
        }
        return directory.defaultShelf?.uid ?? directory.sortedShelves.first?.uid
    }

    /// 新笔记本的排序位 = **该架内现有条数**（`NotebookDirectory.nextSortOrder` 是唯一那一处实现，
    /// 这里只做转交 —— 界面不许自己数一遍）。
    public static func sortOrder(inShelf shelfUid: String, directory: NotebookDirectory) -> Int {
        directory.nextSortOrder(inShelf: shelfUid)
    }

    /// 现在能不能新建（有架可落）。视图据此灰着那个入口。
    public static func canCreate(in directory: NotebookDirectory) -> Bool {
        !directory.shelves.isEmpty
    }

    /// 新建弹框的标题。
    public static let titleKey: LKey = .notesNewNotebookTitle
    /// 入口（树上那个「＋」/ 右键那一项）的文字。
    public static let menuTitleKey: LKey = .notesNewNotebook
    /// 名字输入框的占位（与重命名共用一个 —— 两个框里要的都是「一个名字」）。
    public static let namePlaceholderKey: LKey = .notesEditNamePlaceholder
    /// 一个架都没有时给的那句人话（**不弹框**）。
    public static let noShelfKey: LKey = .notesNewNotebookNoShelf
}

/// 排序方向（界面上的「上移 / 下移」）。
public enum ContainerReorderDirection: String, Sendable, Equatable, CaseIterable {
    case up
    case down

    /// 这一步的文案键。
    public var titleKey: LKey {
        self == .up ? .notesMoveUp : .notesMoveDown
    }
}

/// 一个容器要写的排序位（落库用）。
public struct ContainerSortOrder: Equatable, Sendable {

    public let uid: String
    public let sortOrder: Int

    public init(uid: String, sortOrder: Int) {
        self.uid = uid
        self.sortOrder = sortOrder
    }
}

/// 排序规则（**唯一出处**）：同一层的可见次序 → 相邻一步 → 整层重排。
///
/// 「同一层」= 架之间一层、**同一个架里的笔记本**之间一层 —— 笔记本不跨架排序
/// （跨架挪是「移动」那一件事，归 `NotebookDirectory.move` 与 `NotebookMovePrompt`，不是排序）。
public enum ContainerReorder {

    /// 某个容器所在那一层的**可见次序**：与树上看到的次序**同一份来源**
    /// （`NotebookDirectory` 的稳定排序），不另立一套。认不出的 uid ⇒ 空（没有可挪的东西）。
    public static func order(
        kind: NotebookContainerKind,
        containerUid: String,
        directory: NotebookDirectory
    ) -> [String] {
        switch kind {
        case .shelf:
            return directory.sortedShelves.map(\.uid)
        case .notebook:
            guard let notebook = directory.notebook(uid: containerUid) else { return [] }
            return directory.notebooks(inShelf: notebook.shelfUid).map(\.uid)
        }
    }

    /// 挪一步要写的排序位（**整层重排**）：先把可见次序按索引重写成 `0..<n`，再交换相邻两项。
    /// 挪不动（已在最前 / 已在最后 / uid 认不出 / 层里只有它一个）⇒ `nil`
    /// —— 视图据此灰着那一项，`AppState` 据此不写库（两条路读同一个答案）。
    public static func plan(
        kind: NotebookContainerKind,
        containerUid: String,
        direction: ContainerReorderDirection,
        directory: NotebookDirectory
    ) -> [ContainerSortOrder]? {
        var order = self.order(kind: kind, containerUid: containerUid, directory: directory)
        guard let index = order.firstIndex(of: containerUid) else { return nil }
        let target = direction == .up ? index - 1 : index + 1
        guard order.indices.contains(target) else { return nil }
        order.swapAt(index, target)
        return order.enumerated().map { ContainerSortOrder(uid: $0.element, sortOrder: $0.offset) }
    }

    /// 能不能往这个方向挪一步（视图的 `.disabled` 读它）。
    public static func canMove(
        kind: NotebookContainerKind,
        containerUid: String,
        direction: ContainerReorderDirection,
        directory: NotebookDirectory
    ) -> Bool {
        plan(kind: kind, containerUid: containerUid, direction: direction, directory: directory) != nil
    }
}

/// 重命名与「编辑弹框」共用的文案键。
public enum ContainerEditPrompt {

    /// 树上右键「重命名…」那一项。
    public static let menuTitleKey: LKey = .notesRenameMenu
    /// 重命名弹框的标题。
    public static let titleKey: LKey = .notesRenameTitle
    /// 弹框里的确认按钮（与取消一起，两个模式共用）。
    public static let confirmKey: LKey = .notesEditConfirm
    public static let cancelKey: LKey = .notesEditCancel
}
