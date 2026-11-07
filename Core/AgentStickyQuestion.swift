import Foundation

/// 「当前轮用户问题**吸顶一行**」的唯一判定（详设 §3.34）。
///
/// ## 由头（人类主人真机 beta1.0.4）
///
/// > 「用户发出的问题被滚动的输出冲掉了，有时候要滚到前面去才能看到。
/// >  应该跟 hermes 一样：如果输出的文字太多，用户这句话就挂在最顶端。」
///
/// ## 为什么单独做成 Core 的纯值
///
/// 这件事只有两个判断：
/// ① **钉哪一条** —— 哪一条用户消息算「当前轮」；
/// ② **钉不钉** —— 那条消息是不是已经滚出了视口顶。
///
/// 两个都必须能逐条判红（`Tests/AgentStickyQuestionTests.swift` 与端上
/// `TestsUISnapshot/AgentChatStickyQuestionProbeTests.swift`）。写在视图里就只能靠人拖滚动条。
///
/// ② 的两个输入都是**同一套坐标**（内容坐标，自内容顶算起，单位 pt）：
/// `viewportTop` = 视口顶在内容坐标里的位置（就是滚动偏移），
/// `questionTop` = 那条用户消息顶边在内容坐标里的位置。
/// 两者都**不含吸顶条本身**（吸顶条是滚动区外的兄弟视图，不参与内容布局）——
/// 否则「条一出现 ⇒ 内容位移 ⇒ 判定翻转 ⇒ 条消失」会自激。
public struct AgentStickyQuestion: Equatable, Sendable {

    /// 当前轮（= 最后一轮）的**轮首用户消息**。
    public let messageID: UUID
    /// 它在 `messages` 里的下标（判据与排障用；视图不拿它做下标访问）。
    public let index: Int
    /// 原话（吸顶条显示的是它的**一行化**形式）。
    public let text: String

    /// 「算不算滚出视口顶」的容差（pt）：0.5 = 不到一个像素。恰好贴顶（`viewportTop == questionTop`）
    /// 时消息**还看得见**，按契约② 条必须消失 —— 所以等号不能算「滚出去了」。
    public static let offsetTolerance: CGFloat = 0.5

    /// 吸顶条高度：**一行**（= 列表行高 20pt，契约① 要求 ≤ 28pt）。
    /// 视图（`AgentStickyQuestionBar`）与判据读同一个数。
    public static let barHeight: CGFloat = Metrics.listRowHeight

    public init(messageID: UUID, index: Int, text: String) {
        self.messageID = messageID
        self.index = index
        self.text = text
    }

    /// **当前轮** = `AgentChatTurnShape` 切出来的最后一轮的轮首用户消息。
    ///
    /// 为什么走 `AgentChatTurnShape` 而不是在视图里写一句
    /// `messages.last(where: { $0.role == .user })`：一轮的定义只许有一处（同一份定义还被
    /// 「哪一条助手消息是结论」「哪一条属于最后一轮」用着）。视图里再来一份，等于把
    /// 「什么算一轮」变成两个可能不相同的答案 —— 那正是 §3.33 立轮次概念时要避免的。
    ///
    /// 还没有任何用户提问 ⇒ `nil`（没有可钉的东西，条不出现）。
    public static func currentTurn(in messages: [AgentChatMessage]) -> AgentStickyQuestion? {
        guard let index = AgentChatTurnShape.turnStartIndices(in: messages).last,
              messages.indices.contains(index) else { return nil }
        let message = messages[index]
        guard message.role == .user else { return nil }
        return AgentStickyQuestion(messageID: message.id, index: index, text: message.text)
    }

    /// 钉不钉（契约① / ② / ④ 的判定本体）。
    ///
    /// **只与几何有关**：跑没跑完、这一轮是成功还是失败，都不改这个答案 ——
    /// 「本轮结束不立刻消失，只在进入下一轮或滚回本轮范围时才换 / 消」（契约④）。
    public static func shouldStick(viewportTop: CGFloat, questionTop: CGFloat) -> Bool {
        viewportTop > questionTop + offsetTolerance
    }

    /// 吸顶条那一行的字：**一行化**（空白折成单个空格、去掉首尾与换行）。
    ///
    /// 为什么要折：契约①⑤ 要求「无论问题多长，条只占一行」。`Text` 的 `lineLimit(1)`
    /// 只能挡住显示，挡不住测量 —— 200 字里带一串换行时，行高仍按多行算。
    /// 折平之后这一行的文本永远是单行，视图再用 `lineLimit(1)` + 省略号兜住宽度。
    public static func lineText(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
