import Foundation

// 查询历史两处**破坏性动作**的界面那一半（队列 `HIST-2` · 契约 `DR-02`「持久化历史 ·
// **可清空 / 单条删除**」· SRS `FR-EDIT-10` v3.326 扩写）。
//
// 形态照抄 `Core/NotebookRemovalPrompt.swift` 的单条删除那一节（同一条形态、同一条理由）：
//   ① **动作与顺序只有一处**（`clearActions` / `deleteActions`）—— 页签里的两枚按钮、
//      工具条时钟菜单那条路、判据自己，三处消费者各写一遍就会出现「按钮这条路先问、
//      菜单那条直接删」这种一半有的行为（本工程同族事故见 `L-143` / `L-172`）；
//   ② **界面只画**：要动什么（`QueryHistoryRemovalTarget`）与标题 / 正文由调用方算好挂上来，
//      视图不自己数条数、也不自己拼句子；
//   ③ **取消 = 库一个字节不动**：只有确认步（`AppState.confirmHistoryRemoval()`）才落库 ——
//      这就是「破坏性操作先问一次」那句话的机械形状。
//
// **判据的落点**（`TestsUISnapshot/QueryHistoryPaneProbeTests.swift`）：挂请求之后历史条数不变，
// 确认之后才减（清空 ⇒ 0 / 单条 ⇒ 少 1）。视图两处 UI（页签内 + 时钟菜单）**都不许绕过**这层。

/// 确认框里的一个动作。**只有 `clear` / `delete` 会真的动库**。
public enum QueryHistoryRemovalAction: String, CaseIterable, Sendable, Equatable {

    /// 清空全部历史（`DR-02`：可清空）。
    case clear
    /// 删掉一条历史（`DR-02`：单条删除）。
    case delete
    /// 什么都不做（按 ESC / 点框外也是它）。**库一个字节不动**。
    case cancel

    /// 这个动作会不会真的动库（`deletesContent` 是事实，不是样式）。
    public var deletesContent: Bool { self != .cancel }
}

/// 这一次要动的是哪一片：全部 / 某一条。
public enum QueryHistoryRemovalTarget: Equatable, Sendable {

    /// 清空全部。
    case all
    /// 删一条（按 id；id 与 `QueryHistory.id` 同一把钥匙）。
    case one(UUID)

    /// 会动几条（清空按**当前条数**算；单条恒 1）—— 确认框正文要写出来的那个数。
    public func count(inHistory total: Int) -> Int {
        switch self {
        case .all: return total
        case .one: return 1
        }
    }
}

/// **挂在界面上的那一个（清空 / 删除）请求**（确认框读它）。
public struct QueryHistoryRemovalRequest: Identifiable, Equatable, Sendable {

    public let id: UUID
    public let target: QueryHistoryRemovalTarget
    /// 单条时那条 SQL 的**单行摘要**（确认框正文里写出来；清空时为空串）。
    public let subject: String
    /// 确认框里的动作，**顺序就是呈现顺序**。
    public let actions: [QueryHistoryRemovalAction]

    public init(
        id: UUID = UUID(),
        target: QueryHistoryRemovalTarget,
        subject: String = "",
        actions: [QueryHistoryRemovalAction]
    ) {
        self.id = id
        self.target = target
        self.subject = subject
        self.actions = actions
    }

    /// 这个请求里有这个动作吗（界面按它决定画哪几枚按钮，别自己硬写两枚）。
    public func offers(_ action: QueryHistoryRemovalAction) -> Bool { actions.contains(action) }
}

/// 清空 / 单条删除确认框的规则（**唯一出处**）。
public enum QueryHistoryRemovalPrompt {

    /// 清空那一档的动作与顺序 —— **只此一处**。
    ///
    /// 为什么破坏档在前、「取消」在最后：「取消」不是第三个业务选择，它是**退出口**
    /// （按 ESC / 点框外也是它）—— 业务上只有「清」与「不清」两件。
    public static let clearActions: [QueryHistoryRemovalAction] = [.clear, .cancel]

    /// 单条删除那一档的动作与顺序。
    public static let deleteActions: [QueryHistoryRemovalAction] = [.delete, .cancel]

    /// 这一档的确认框标题键。
    public static func titleKey(for target: QueryHistoryRemovalTarget) -> LKey {
        switch target {
        case .all: return .historyClearConfirmTitle
        case .one: return .historyDeleteConfirmTitle
        }
    }

    /// 这一档的确认框正文键。
    public static func messageKey(for target: QueryHistoryRemovalTarget) -> LKey {
        switch target {
        case .all: return .historyClearConfirmMessage
        case .one: return .historyDeleteConfirmMessage
        }
    }

    /// 某个动作的**按钮标题键**（视图不自己选词）。
    public static func actionTitleKey(_ action: QueryHistoryRemovalAction) -> LKey {
        switch action {
        case .clear: return .historyClear
        case .delete: return .commonDelete
        case .cancel: return .commonCancel
        }
    }

    /// 从「要动什么」造出「挂在界面上的请求」。
    public static func request(
        target: QueryHistoryRemovalTarget,
        subject: String = ""
    ) -> QueryHistoryRemovalRequest {
        QueryHistoryRemovalRequest(
            target: target,
            subject: subject,
            actions: target == .all ? clearActions : deleteActions
        )
    }
}
