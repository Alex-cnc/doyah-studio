import Foundation

/// 关闭一个工作区页签时的处置（`FR-EDIT-46`）。
///
/// ## 为什么单独一个纯类型
///
/// 这份判断有三处消费者 —— 页签条上的关闭按钮、将来可能有的 ⌘W 菜单路、以及判据自己。
/// 写在视图里就会出现「按钮这条路肯弹确认框、菜单那条直接关掉」这种一半有的行为
/// （本工程同族事故：两个编辑面的着色调度各写一份，见队列 `L-143` 的复盘）。
///
/// ## 口径（需求提出者 2026-10-03）
///
/// 原话：「**文件打开后被修改，点击关闭时提示必须先保存了才能关闭，这个逻辑有问题，
/// 我的期望：用户点击关闭按钮，发现有修改，弹出确认框让用户选择，是保存关闭还是不修改
/// 直接退出**」。
///
/// ⇒ 有未保存改动时**弹确认框**，给「保存并关闭」「不保存，直接关闭」两个动作；
/// 旧行为是**直接拒绝关闭**（只在消息条上给一句话），那是**阻塞**不是确认 ——
/// 用户被挡在门外，还得自己去猜要按什么。
///
/// 三条不变量（判据 `Tests/WorkspaceClosePolicyTests.swift` 逐条钉住）：
/// ① **干净页签不弹框**（多一次点击就是多一次打扰）；
/// ② **`.cancel` 永远不关页签**（取消 = 什么都没发生）；
/// ③ **保存失败就不关**（宁可关不掉，也不静默丢掉用户刚敲的代码 —— 这条与
///   「脏页签不许被静默丢弃」是同一件事的两面）。
public enum WorkspaceCloseAction: String, CaseIterable, Sendable, Equatable {
    /// 保存后关闭；**保存失败则不关**（见 `WorkspaceClosePolicy.keepsTab`）。
    case saveAndClose
    /// 丢弃改动直接关闭。
    case discardChanges
    /// 不关（继续编辑）。
    case cancel

    /// 这个动作会不会真的把页签关掉。
    public var closesTab: Bool { self != .cancel }
}

/// 一次关闭请求的处置计划。
public struct WorkspaceClosePlan: Equatable, Sendable {
    /// 要不要先弹确认框（= 有未保存改动）。
    public let needsConfirmation: Bool
    /// 确认框里给出的动作，**顺序就是呈现顺序**（默认动作在最前）。
    /// 不需要确认时为空数组（没有框可弹）。
    public let actions: [WorkspaceCloseAction]

    public init(needsConfirmation: Bool, actions: [WorkspaceCloseAction]) {
        self.needsConfirmation = needsConfirmation
        self.actions = actions
    }
}

/// 一次挂在界面上的关闭请求（确认框读它；`id` = 页签 id）。
public struct WorkspaceCloseRequest: Identifiable, Equatable, Sendable {
    public let id: UUID
    /// 页签标题（文件页 = 文件名），用于确认框的标题。
    public let title: String
    public let actions: [WorkspaceCloseAction]

    public init(id: UUID, title: String, actions: [WorkspaceCloseAction]) {
        self.id = id
        self.title = title
        self.actions = actions
    }

    /// 这个请求里有这个动作吗（界面按它决定画哪些按钮，别自己硬写三个）。
    public func offers(_ action: WorkspaceCloseAction) -> Bool {
        actions.contains(action)
    }
}

/// 关闭页签的规则（**唯一出处**）。
public enum WorkspaceClosePolicy {

    /// 确认框里的动作与顺序 —— **只此一处**。
    ///
    /// 「取消」排在最后：它在 macOS 的确认框里是**退出口**（按 ESC 也是它），
    /// 而不是第三个业务选择；业务上的两个选择只有「保存并关闭」与「不保存，直接关闭」。
    public static let confirmActions: [WorkspaceCloseAction] = [.saveAndClose, .discardChanges, .cancel]

    /// 点关闭按钮时怎么处置：干净页签**直接关**，脏页签**先问**。
    public static func plan(isDirty: Bool) -> WorkspaceClosePlan {
        isDirty
            ? WorkspaceClosePlan(needsConfirmation: true, actions: confirmActions)
            : WorkspaceClosePlan(needsConfirmation: false, actions: [])
    }

    /// 用户选了某个动作、且保存**已有结果**之后，页签还留着吗？
    ///
    /// - `.cancel` ⇒ 留（取消就是什么都没发生）。
    /// - `.saveAndClose` 而**保存失败** ⇒ 留（关掉就等于把改动丢了，而用户选的恰恰是"保存"）。
    /// - `.saveAndClose` 而保存成功 / `.discardChanges` ⇒ 关。
    public static func keepsTab(action: WorkspaceCloseAction, saveSucceeded: Bool) -> Bool {
        switch action {
        case .cancel:
            return true
        case .saveAndClose:
            return !saveSucceeded
        case .discardChanges:
            return false
        }
    }
}
