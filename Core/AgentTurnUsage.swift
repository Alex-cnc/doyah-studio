import Foundation

// MARK: - 一轮的三行汇总（详设 §3.33.4 契约六~八）

/// **一轮的用量读数**（详设 §3.33.4）：页面上那三行汇总（`Thinking` / `Tool calls` / `Σ total`）的**唯一**数据源。
///
/// ## 三个数各是什么（口径写死在这里，代码与详设同一份）
///
/// · `thinkingTokens` = **合并后那一个思考区**的文本 token 数（= 本轮所有段的文本
///   `joined(separator: "\n\n")`，与 `AgentTurnThinking` 给视图的段**同一份**字 ——
///   所以「Thinking 行 == 合并后区的 token 合计」是恒等式，不是两次独立估算）；
/// · `toolTokens` = 本轮工具过程行的文本 token 数（`▸ 名 · 摘要 ✓ · 0.5s` 这些行），
///   `toolCallCount` = 这些行里**调用**的条数；
/// · `outputTokens` = 本轮结论正文（末条助手消息的 `split.conclusion`）的 token 数。
///
/// `totalTokens` **定义**为三者之和（`thinking + tools + output`）—— 判据③ 断言的就是这条等式。
///
/// ## 为什么不用端点回报的 usage 当 `Σ`
///
/// 端点给的是**整个请求**的用量（系统提示 + 历史 + 工具 schema + 输出），分母与本轮
/// 「产出的三段」不是同一个；直接拿来当 Σ，等式 `Σ == thinking + tools + output` 立刻不成立，
/// 而那正是主人要的读数口径（「合计是哪几项相加」必须说得清）。所以回报值只作**旁证**
/// 存进 `reportedTotal`（tooltip 里对照用），**不进** 三行里的任何一个数。
///
/// ## 估算口径（数字前那个 `~`）
///
/// 端点**没有**分项 usage（没有「这一步思考用了多少」这种字段），所以三项一律走仓库既有的
/// 那一套估算器 `AgentTokenEstimator.tokens(_:)`（汉字/中日韩 1 字 = 1 token，其余 4 字符 = 1 token）
/// —— 与上下文账本（`AgentContextLedgerBuilder`）**同一套**口径，不在这里另立一套。
/// 估算值一律带 `~`；只有端点真给了分项数才允许去掉波浪号（`isEstimated == false`）。
public struct AgentTurnUsage: Equatable, Sendable {

    /// 本轮思考（合并后的那一个区）的 token 数。
    public let thinkingTokens: Int
    /// 本轮工具调用的**次数**（不是行数：一行就是一次调用，解析不出的过程行也算一次）。
    public let toolCallCount: Int
    /// 这些工具过程的 token 合计。
    public let toolTokens: Int
    /// 本轮结论正文的 token 数。
    public let outputTokens: Int
    /// 这些数是不是估算出来的（`true` ⇒ 显示时数字前带 `~`）。
    public let isEstimated: Bool
    /// 端点回报的这一轮总用量（提示词 + 输出）；`nil` = 端点没报。**不进 Σ**，只作旁证。
    public let reportedTotal: Int?

    public init(thinkingTokens: Int,
                toolCallCount: Int,
                toolTokens: Int,
                outputTokens: Int,
                isEstimated: Bool = true,
                reportedTotal: Int? = nil) {
        self.thinkingTokens = max(0, thinkingTokens)
        self.toolCallCount = max(0, toolCallCount)
        self.toolTokens = max(0, toolTokens)
        self.outputTokens = max(0, outputTokens)
        self.isEstimated = isEstimated
        self.reportedTotal = reportedTotal
    }

    /// 本轮 token 合计 = **thinking + tools + output**（判据③ 的等式，改口径先改这里）。
    public var totalTokens: Int { thinkingTokens + toolTokens + outputTokens }

    /// 空轮（一个数都没有）：界面上不画三行（契约②：零占位）。
    public var isEmpty: Bool {
        thinkingTokens == 0 && toolTokens == 0 && outputTokens == 0 && toolCallCount == 0
    }
}

/// 把一轮的消息读成 `AgentTurnUsage`（详设 §3.33.4）。轮切分走 `AgentChatTurnShape`（只有一处定义）。
public enum AgentTurnUsageReader {

    /// 每一轮一条读数，键 = 本轮轮首消息下标（与 `AgentTurnThinking.zones(...)` 的轮划分**同一刀**）。
    public static func usage(in messages: [AgentChatMessage],
                             includeReasoning: Bool) -> [Int: AgentTurnUsage] {
        guard !messages.isEmpty else { return [:] }
        let finals = AgentChatTurnShape.finalAssistantIndices(in: messages)
        let zones = AgentTurnThinking.zones(in: messages, includeReasoning: includeReasoning)
        let zoneByTurn = Dictionary(uniqueKeysWithValues: zones.map { ($0.turnKey, $0) })

        var result: [Int: AgentTurnUsage] = [:]
        for span in AgentTurnSpans.spans(in: messages) {
            var thinkingTokens = 0
            if let zone = zoneByTurn[span.turnKey] {
                // **与思考区同一份文本**：这里不重新拼段，直接用聚合结果 ⇒ ① 的读数不会分家。
                thinkingTokens = AgentTokenEstimator.tokens(zone.text)
            }
            var toolTokens = 0
            var toolCalls = 0
            var outputTokens = 0
            for index in span.startIndex...span.endIndex {
                let message = messages[index]
                switch message.role {
                case .tool:
                    toolTokens += AgentTokenEstimator.tokens(message.text)
                    toolCalls += Self.callCount(message.text)
                case .assistant where finals.contains(index):
                    let split = AgentAnswerClassifier.split(message.text)
                    outputTokens += AgentTokenEstimator.tokens(split.conclusion)
                default:
                    break
                }
            }
            result[span.startIndex] = AgentTurnUsage(thinkingTokens: thinkingTokens,
                                                     toolCallCount: toolCalls,
                                                     toolTokens: toolTokens,
                                                     outputTokens: outputTokens)
        }
        return result
    }

    /// 这一轮里该并进「Tool calls」那一行的工具文本（按发生顺序）。
    ///
    /// 与 `usage(...)` 同一个轮划分；视图据此把工具行**收进**那一行（不并进思考区、也不另铺）。
    public static func toolTexts(in messages: [AgentChatMessage]) -> [Int: [String]] {
        guard !messages.isEmpty else { return [:] }
        var result: [Int: [String]] = [:]
        for span in AgentTurnSpans.spans(in: messages) {
            result[span.startIndex] = (span.startIndex...span.endIndex)
                .filter { messages[$0].role == .tool }
                .map { messages[$0].text }
        }
        return result
    }

    private static func rawLineCount(_ text: String) -> Int {
        text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
    }

    /// 一条工具消息里有**几次调用**：Core 自己写的过程行以 `▸ ` 开头（`AgentChat.progressBullet`），
    /// 一次调用一行。`Core` 不能引用界面层的 `AgentToolLines`（那是 App 的解析器，模块依赖只朝一个方向），
    /// 所以这里只认 Core 自己那个前缀；认不出（一条 `▸` 都没有）⇒ 按非空行数兜底，**不报 0 次**。
    static func callCount(_ text: String) -> Int {
        let bullet = "▸ "
        let lines = text.components(separatedBy: "\n")
        let calls = lines.filter { $0.hasPrefix(bullet) }.count
        return calls > 0 ? calls : max(1, rawLineCount(text))
    }
}
