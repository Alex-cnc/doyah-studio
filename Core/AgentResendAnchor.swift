import Foundation

/// 「重发这一条」的**锚点判定**（§9.1.16 ③）。
///
/// 语义：重发**不是**把那条助手消息改一遍，而是**以它对应的那次提问为锚，再跑一轮**，
/// 旧轮原样留在转写里（人要看的是「同样的问题，这次会不会做得不一样」）。
///
/// 于是要回答的问题只有一个：**这条助手消息是哪次提问的产物** ——
/// 往前找最近的一条 `.user` 消息。找不到就**不重发**（不猜、不拿最后一条输入代替）。
public enum AgentResendAnchor {

    /// 从 `assistantID` 往回找最近的一条用户提问文本；找不到返回 `nil`。
    public static func userPrompt(before assistantID: UUID, in messages: [AgentChatMessage]) -> String? {
        guard let index = messages.firstIndex(where: { $0.id == assistantID }) else { return nil }
        guard index > messages.startIndex else { return nil }
        for message in messages[..<index].reversed() where message.role == .user {
            return message.text
        }
        return nil
    }
}
