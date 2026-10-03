import Foundation

// 删除处置的**界面那一半**：确认框的动作、顺序、每句文案的键 —— 队列 `L-97` 界面半第二片（③ 删除确认框）。
//
// 契约出处：`DoyahNotes/Docs/核心契约.md` **§2.12 第 3 条（删除处置）** ——
//   删笔记本：一并删 / **移到默认笔记本**（**默认取后者**）；
//   删架：一并删 / **笔记本整架移到默认架**（**默认取后者**）；
//   **非空时写明「将影响多少笔记本与多少条笔记」**。
//
// 这一片**不算计划、不写库**（那两半分别在 `Core/Notebook.swift` 与 `Core/NoteStorage/*`，
// 第 162 / 164 / 168 轮已落）—— 它只做「把一份计划摆到界面上要说的话」。
//
// 为什么单独一个纯类型（而不是在视图里就地写三个按钮 + 一句 if）：
//   ① **动作与顺序只有一处**：树上的行、将来的菜单路、判据自己，三处消费者；写在视图里
//      就会出现「按钮这条路按契约默认档、菜单那条一律删干净」这种一半有的行为（本工程同族
//      事故见 `L-143` 复盘与 `L-172` 的 `WorkspaceClosePolicy`）；
//   ② **影响面那句要按实际数字选形状**（空 / 只有笔记 / 只有笔记本 / 两个都有）—— 这是一个
//      可判定的判断，视图各写一遍 `if` 迟早出现「将影响 0 条笔记」这种胡说；
//   ③ **默认容器删不掉**：计划本身返回 `nil`（`NotebookDirectory.removalPlan`），界面该给的是
//      「不能删」那句人话 —— 而不是一个点了没反应的菜单项。

/// 确认框里的一个动作。
public enum ContainerRemovalAction: String, CaseIterable, Sendable, Equatable {

    /// **契约默认档**：移到默认容器（删笔记本 → 默认笔记本；删架 → 整架移到默认架）。不删内容。
    case moveToDefault
    /// 破坏档：里面的东西一并删掉。
    case deleteTogether
    /// 什么都不做（macOS 确认框里的退出口，按 ESC 也是它）。
    case cancel

    /// 这个动作对应哪条落库档位；`nil` = 不落库（取消）。
    public var policy: ContainerRemovalPolicy? {
        switch self {
        case .moveToDefault: return .moveToDefault
        case .deleteTogether: return .deleteTogether
        case .cancel: return nil
        }
    }

    /// 这个动作会不会**删掉内容**（界面据此给破坏色；`deletesContent` 是事实，不是样式）。
    public var deletesContent: Bool { self == .deleteTogether }
}

/// 确认框正文的**形状**（「非空时写明将影响多少笔记本与多少条笔记」那句话的四种形态）。
///
/// 为什么是枚举而不是「拼好的字符串」：Core 不产文案（`字由调用方给定`，见
/// `Docs/概要设计.md` §7 与 `Scripts/check-core-localization.py`）—— 这里给的是
/// **键 + 数字**，由宿主层交给语言表。四种形态各自的键分开，是为了让「一个数 / 两个数」
/// 在中英两侧都能自然成句，而不是硬塞两个数进去读成「将影响 0 个笔记本」。
public enum ContainerRemovalSummary: Equatable, Sendable {

    /// 里外都是空的（0 笔记本 0 笔记）：不写数字，照实说「不影响任何东西」。
    case empty
    /// 只有笔记受影响（删一个笔记本一定落在这一档 —— 删笔记本不牵动别的笔记本）。
    case notes(Int)
    /// 只有笔记本受影响（删空架：整架搬走，一条笔记都不改挂）。
    case notebooks(Int)
    /// 两者都受影响（删架 + 一并删档）。
    case notebooksAndNotes(notebooks: Int, notes: Int)

    /// 这个形状对应的文案键。
    public var key: LKey {
        switch self {
        case .empty: return .notesRemoveSummaryEmpty
        case .notes: return .notesRemoveSummaryNotes
        case .notebooks: return .notesRemoveSummaryNotebooks
        case .notebooksAndNotes: return .notesRemoveSummaryBoth
        }
    }

    /// 按计划算出来的两个数**选形状** —— 只此一处。
    ///
    /// 两个数都取「受影响」口径（被删的 + 被改挂的，见 `ContainerRemovalPlan`）：
    /// 删架走默认档时一个笔记本都不删、整架却都要改挂 —— 只数「被删的」会让确认框说
    /// 「将影响 0 个笔记本」，而事实是整架都会动（第 168 轮实测）。
    public static func make(notebookCount: Int, noteCount: Int) -> ContainerRemovalSummary {
        switch (notebookCount, noteCount) {
        case (0, 0): return .empty
        case (0, let notes): return .notes(notes)
        case (let notebooks, 0): return .notebooks(notebooks)
        default: return .notebooksAndNotes(notebooks: notebookCount, notes: noteCount)
        }
    }
}

/// **挂在界面上的那一个删除请求**（确认框读它）。`id` = 容器 uid。
public struct ContainerRemovalRequest: Identifiable, Equatable, Sendable {

    public let id: String
    public let kind: NotebookContainerKind
    /// 容器名（确认框标题要写出来 —— 「要删除「工作」吗」与「要删除「笔记本」吗」不是一回事）。
    public let containerName: String
    /// 现算出来的处置计划（树上点删除那一刻从库里算的；落库前 `NoteLibrary` 会**再算一次**）。
    public let plan: ContainerRemovalPlan
    /// 确认框里的动作，**顺序就是呈现顺序**（默认档在最前）。
    public let actions: [ContainerRemovalAction]

    public init(
        id: String,
        kind: NotebookContainerKind,
        containerName: String,
        plan: ContainerRemovalPlan,
        actions: [ContainerRemovalAction]
    ) {
        self.id = id
        self.kind = kind
        self.containerName = containerName
        self.plan = plan
        self.actions = actions
    }

    /// 这个请求里有这个动作吗（界面按它决定画哪些按钮，别自己硬写三个）。
    public func offers(_ action: ContainerRemovalAction) -> Bool { actions.contains(action) }

    /// 影响面那句的形状（由计划的两个数算出来）。
    public var summary: ContainerRemovalSummary {
        ContainerRemovalSummary.make(
            notebookCount: plan.affectedNotebookCount,
            noteCount: plan.affectedNoteCount
        )
    }
}

/// 删除确认框的规则（**唯一出处**）。
public enum ContainerRemovalPrompt {

    /// 确认框里的动作与顺序 —— **只此一处**。
    ///
    /// 为什么「取消」在最后：它在 macOS 的确认框里是**退出口**（按 ESC 也是它），
    /// 不是第三个业务选择；业务上的两个选择只有「移到默认容器」与「一并删除」。
    /// 为什么默认档在最前：契约 §2.12 第 3 条写明**默认都取后者**（不删内容的那一档）——
    /// 界面的按钮次序是这句话的落点，排错了就是让用户默认走进破坏档。
    public static let confirmActions: [ContainerRemovalAction] = [.moveToDefault, .deleteTogether, .cancel]

    /// 确认框标题（容器名作实参：`%@`）。
    public static let titleKey: LKey = .notesRemoveConfirmTitle

    /// 默认容器删不掉时给的那句人话（容器名作实参：`%@`）。
    public static let notAllowedKey: LKey = .notesRemoveDefaultNotAllowed

    /// 某个动作在某种容器上的**按钮标题键**。
    ///
    /// 两个维度都得对：「移到默认笔记本」与「笔记本整架移到默认架」不是同一件事 ——
    /// 用一句「移动」糊过去，用户就不知道删掉这个架之后架里的笔记本去哪了。
    public static func titleKey(for action: ContainerRemovalAction, kind: NotebookContainerKind) -> LKey {
        switch action {
        case .moveToDefault:
            return kind == .notebook ? .notesRemoveMoveToDefaultNotebook : .notesRemoveMoveToDefaultShelf
        case .deleteTogether:
            return kind == .notebook ? .notesRemoveDeleteNotebookTogether : .notesRemoveDeleteShelfTogether
        case .cancel:
            return .notesRemoveCancel
        }
    }

    /// 树上那一行「删除」菜单项的文字。
    public static func menuTitleKey(for kind: NotebookContainerKind) -> LKey {
        kind == .notebook ? .notesRemoveNotebookMenu : .notesRemoveShelfMenu
    }

    /// 从一份现算的计划造出「挂在界面上的请求」。
    public static func request(plan: ContainerRemovalPlan, containerName: String) -> ContainerRemovalRequest {
        ContainerRemovalRequest(
            id: plan.removedContainerUid,
            kind: plan.removedContainerKind,
            containerName: containerName,
            plan: plan,
            actions: confirmActions
        )
    }
}
