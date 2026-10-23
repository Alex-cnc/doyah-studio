import Foundation

/// 对话面板**空态**的显示判据（§9.1.16 ⑦）。
///
/// 为什么单独抽一条判据而不是写在视图里：空态最容易出的错不是「没画」，
/// 而是**该消失的时候还在** —— 流式已经开始、卡片已经出现、或者正在跑却先给一句
/// 「先说一句你要做什么」，都会让人以为自己的消息没发出去。
public enum AgentChatEmptyStateGate {

    /// 只有「一条消息都没有、一张卡都没有、也没在跑」时才画空态。
    ///
    /// 正在跑（`isRunning`）时不画：那一瞬面板里已有过程块，再叠一句起手话等于自相矛盾。
    public static func shouldShow(messageCount: Int, cardCount: Int, isRunning: Bool) -> Bool {
        messageCount == 0 && cardCount == 0 && !isRunning
    }
}
