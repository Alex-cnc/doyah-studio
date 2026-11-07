import Foundation

/// 「哪一段是结论」—— 助手正文里**过程独白**与**最终结论**的切分（详设 §3.33）。
///
/// ## 为什么需要这一层（真机缺陷 2026-11-07）
///
/// 人类主人在装好的 beta1.0.3 上问：「Doyah Agent 里输出的『我先读一下……再……』
/// 这是思考过程吗？」—— 是。模型把**过程独白**写在正文里（不是 `thinking` 栏），
/// 界面照单全收地铺成正文 ⇒ 要读的结论被一段「我先…再…」挤到下面。
///
/// 于是正文要分两块：**过程独白**（折叠、限高）与**结论**（完整呈现）。
///
/// ## 判定规则（刻意小、可逐条复述、可判红）
///
/// 1. **按段切**：空行分段；围栏代码块（``` / ~~~）**永不切开**（切了就等于把结论
///    的代码块撕成两半）。
/// 2. **一段是不是过程独白**，两个信号任一成立：
///    a. **过程自述开头**：去掉列表符号 / 标题井号 / 引用号之后，以下面这些词开头——
///       「我先」「我要先」「让我先 / 让我看 / 让我读 / 让我查」「我来看 / 我来读 / 我来查」
///       「先看 / 先读 / 先查 / 先确认」「接下来我」「然后我」「现在我先」「我首先」，
///       英文 `Let me` / `I'll` / `I will` / `I'm going to` / `First,` / `Now let me`。
///    b. **续接式独白**：含省略号（`…` 或 `...`）**且**含「再 / then」（「我先读一下 A……
///       再决定改哪里」这种把话留到下一步的收尾），且不含围栏代码块。
///       单看省略号不算（结论里也常见），单看「再」也不算（结论里更多）。
/// 3. **结论 = 末尾那一段连续的非独白段**：从最后一段往前收，遇到独白段就停。
///    末段自己就是独白时**仍按结论给它**（不许把整条消息折成 0 —— 那比铺开更坏）。
/// 4. **段内再切一句**：结论段若以过程自述开头（「我先读一下 A。」后面接结论），
///    把开头那几句自述挪进独白；剩下为空就不切（宁可不切，也不许切没）。
///
/// 判据：`Tests/AgentAnswerSplitTests`（规则逐条）；端上读数在
/// `TestsUISnapshot/AgentChatNarrationProbeTests`。
public struct AgentAnswerSplit: Equatable, Sendable {
    /// 过程独白（`nil` = 这一条没有独白，整段都是结论）。
    public var narration: String?
    /// 结论（**至少一段**：末段永远是结论，见规则 3）。
    public var conclusion: String
    /// 整条都是独白（没有可信的结论段）—— 界面此时仍把结论段画出来，但可以标注一句。
    public var isNarrationOnly: Bool

    public init(narration: String? = nil, conclusion: String, isNarrationOnly: Bool = false) {
        self.narration = narration
        self.conclusion = conclusion
        self.isNarrationOnly = isNarrationOnly
    }

    /// 有没有独白要折（`nil` 与空白都算没有）。
    public var hasNarration: Bool {
        guard let narration else { return false }
        return !narration.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public enum AgentAnswerClassifier {

    /// 规则 2a 的过程自述开头（去掉标记符号之后比对；英文大小写不敏感）。
    public static let narrationOpeners: [String] = [
        "我先", "我要先", "我得先", "我需要先",
        "让我先", "让我看", "让我读", "让我查", "让我确认",
        "我来看", "我来读", "我来查", "我来确认", "我先看", "我先读", "我先查",
        "我再看", "我再读", "我再查", "再看", "再读",
        "先看", "先读", "先查", "先确认", "先看一下", "先读一下",
        "接下来我", "接下来，我", "然后我", "现在我先", "我首先", "首先我",
        "let me", "i'll", "i will", "i'm going to", "i am going to",
        "first,", "first i", "now let me",
    ]

    /// 规则 2b 的续接线索（必须**同时**有省略号才算独白）。
    public static let continuationCues: [String] = ["再", "then"]

    // MARK: - 切分

    /// 一条助手正文 → 独白 / 结论。
    public static func split(_ text: String) -> AgentAnswerSplit {
        let all = blocks(text)
        guard !all.isEmpty else { return AgentAnswerSplit(conclusion: text) }

        if all.count == 1 {
            let only = all[0]
            let trimmed = splitLeadingNarration(only)
            return AgentAnswerSplit(narration: trimmed.narration,
                                    conclusion: trimmed.rest,
                                    isNarrationOnly: isNarrationParagraph(only))
        }

        // 末段以过程自述开头时，先把开头那几句自述摘出来（规则 4）。
        var narrationParts: [String] = []
        var lastBlock = all[all.count - 1]
        if let split = splitLeadingNarration(lastBlock).narration {
            narrationParts.append(split)
            lastBlock = splitLeadingNarration(lastBlock).rest
        }

        var head = Array(all.dropLast())
        // 结论 = 末尾那一段连续的非独白段（规则 3）。
        var start = head.count
        while start > 0 && !isNarrationParagraph(head[start - 1]) { start -= 1 }
        narrationParts.append(contentsOf: head[..<start])
        var conclusionBlocks = Array(head[start...])
        conclusionBlocks.append(lastBlock)

        // 末段自己是独白、前面也没有结论段 ⇒ 结论**仍取末段**（规则 3 的兜底）。
        if conclusionBlocks.count == 1 && isNarrationParagraph(lastBlock) {
            let entire = all.joined(separator: "\n\n")
            return AgentAnswerSplit(narration: nil, conclusion: entire, isNarrationOnly: true)
        }

        let narration = narrationParts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        let conclusion = conclusionBlocks
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        return AgentAnswerSplit(narration: narration.isEmpty ? nil : narration,
                                conclusion: conclusion.isEmpty ? lastBlock : conclusion,
                                isNarrationOnly: false)
    }

    /// 规则 1：空行分段，围栏代码块不切开。
    public static func blocks(_ text: String) -> [String] {
        var blocks: [String] = []
        var current: [String] = []
        var inFence = false
        func flush() {
            let joined = current.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty { blocks.append(joined) }
            current.removeAll()
        }
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
                current.append(line)
                continue
            }
            if !inFence && trimmed.isEmpty {
                flush()
                continue
            }
            current.append(line)
        }
        flush()
        return blocks
    }

    /// 规则 2：这一段是不是过程独白。
    public static func isNarrationParagraph(_ paragraph: String) -> Bool {
        let text = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        if startsWithNarrationOpener(text) { return true }
        // 规则 2b：省略号 + 续接词，且不是代码块（代码块里的 `...` 与 `then` 是代码）。
        guard !containsFence(text) else { return false }
        let hasEllipsis = text.contains("…") || text.contains("...")
        guard hasEllipsis else { return false }
        let lowered = text.lowercased()
        return continuationCues.contains { lowered.contains($0) }
    }

    /// 规则 4：把一段开头的过程自述切下来。切不出（或切完为空）⇒ `narration == nil`。
    public static func splitLeadingNarration(_ paragraph: String) -> (narration: String?, rest: String) {
        let spans = sentenceSpans(paragraph)
        guard spans.count > 1 else { return (nil, paragraph) }
        var count = 0
        while count < spans.count - 1 && isNarrationParagraph(spans[count].text) {
            count += 1
        }
        guard count > 0 else { return (nil, paragraph) }
        let cut = spans[count - 1].end
        let narration = String(paragraph[..<cut]).trimmingCharacters(in: .whitespacesAndNewlines)
        let rest = String(paragraph[cut...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !narration.isEmpty, !rest.isEmpty else { return (nil, paragraph) }
        return (narration, rest)
    }

    /// 句子切分（中文标点 / 换行 / 省略号都算断点；连着的标点算同一句）。
    public static func sentenceSpans(_ paragraph: String) -> [(text: String, end: String.Index)] {
        var spans: [(text: String, end: String.Index)] = []
        var start = paragraph.startIndex
        var index = paragraph.startIndex
        while index < paragraph.endIndex {
            let character = paragraph[index]
            if isSentenceTerminator(character) {
                var end = paragraph.index(after: index)
                while end < paragraph.endIndex, isSentenceTerminator(paragraph[end]) {
                    end = paragraph.index(after: end)
                }
                let text = String(paragraph[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { spans.append((text, end)) }
                start = end
                index = end
                continue
            }
            index = paragraph.index(after: index)
        }
        let tail = String(paragraph[start...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { spans.append((tail, paragraph.endIndex)) }
        return spans
    }

    static func isSentenceTerminator(_ character: Character) -> Bool {
        character == "。" || character == "！" || character == "？" || character == "；"
            || character == "…" || character == "\n" || character == "!" || character == "?"
    }

    // MARK: - 私有

    static func startsWithNarrationOpener(_ paragraph: String) -> Bool {
        let head = normalizedHead(paragraph).lowercased()
        return narrationOpeners.contains { head.hasPrefix($0.lowercased()) }
    }

    /// 去掉 Markdown 的列表符号 / 标题井号 / 引用号 / 数字编号，再看开头。
    static func normalizedHead(_ paragraph: String) -> String {
        var text = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
        var trimming = true
        while trimming {
            trimming = false
            if let first = text.first, "#>-*•+".contains(first) {
                text.removeFirst()
                text = text.trimmingCharacters(in: .whitespaces)
                trimming = true
                continue
            }
            // 数字编号 `1.` / `1)` / `2、`
            let digits = text.prefix { $0.isNumber }
            if !digits.isEmpty, digits.count <= 2 {
                let rest = text.dropFirst(digits.count)
                if let separator = rest.first, separator == "." || separator == ")" || separator == "、" {
                    text = String(rest.dropFirst()).trimmingCharacters(in: .whitespaces)
                    trimming = true
                }
            }
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    static func containsFence(_ text: String) -> Bool {
        text.components(separatedBy: "\n").contains {
            let trimmed = $0.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")
        }
    }
}

/// 一轮里**哪一条助手消息是结论**（详设 §3.33）。
///
/// 缺陷原话：「多个连续 assistant 段落中非最后一段」被当成正文铺出来。一轮（两次用户
/// 提问之间）里助手常常吐好几条：每跳一条「我先看一下…」，最后一条才是答案。
/// 于是判定口径只能是**轮内位置**，不是文本长相：轮内**最后一条**助手消息 = 结论，
/// 其余 = 中间叙述（进思考区）。
///
/// 为什么不用「文本长度 / 有没有代码块」来猜：那是启发式，同一条消息可能既长又有代码块
/// 却仍然是过程（「我改完了，接着跑测试」）。位置是**确定的事实**，猜会引出第二个答案。
public enum AgentChatTurnShape {

    /// 每一条助手消息在本轮里是不是**最后一条**（`true` = 结论，`false` = 中间叙述）。
    /// 返回的集合只含 `.assistant` 的下标；用户提问切分轮次。
    public static func finalAssistantIndices(in messages: [AgentChatMessage]) -> Set<Int> {
        var result: Set<Int> = []
        var index = 0
        while index < messages.count {
            // 一轮 = 从上一条用户提问之后到最后一条助手消息。
            var last: Int?
            var cursor = index
            while cursor < messages.count, messages[cursor].role != .user {
                if messages[cursor].role == .assistant { last = cursor }
                cursor += 1
            }
            if let last { result.insert(last) }
            index = max(cursor + 1, index + 1)
        }
        return result
    }

    /// 一轮的**起点下标**（每条用户提问都是一个新轮次的轮首），按出现顺序。
    ///
    /// 为什么要有这个口：`AgentChatTurnShape` 是「什么算一轮」的**唯一**定义处 ——
    /// 结论判定（`finalAssistantIndices`）、思考区的最后一轮判定（`isInLastTurn`）、
    /// 以及 §3.34 的「当前轮用户问题吸顶」都从这份切分取数。谁要「当前轮」，
    /// 就拿 `turnStartIndices(...).last`，**不许**在别处写第二份「最后一条用户消息」。
    public static func turnStartIndices(in messages: [AgentChatMessage]) -> [Int] {
        messages.indices.filter { messages[$0].role == .user }
    }

    /// 第 `index` 条消息是否属于**最后一轮**（最后一轮 = 最后一次用户提问之后）。
    ///
    /// 思考区的默认形态看的就是这个：只有最后一轮才可能「正在跑」（`running`），
    /// 更早的轮次一律是终态 —— 否则回看旧会话时每一段思考都会展开，把对话区铺满。
    public static func isInLastTurn(in messages: [AgentChatMessage], at index: Int) -> Bool {
        guard messages.indices.contains(index) else { return false }
        for cursor in (index + 1)..<messages.count where messages[cursor].role == .user {
            return false
        }
        return !messages.isEmpty
    }
}

/// 思考区的两种阶段（详设 §3.33「思考区三态」）。
public enum AgentThinkingPhase: String, Sendable {
    /// 本轮未结束：思考区**默认展开**（限高 + 内部滚动，可流式增量）。
    case running
    /// 任一终态（完成 / 失败 / 取消）：**自动折成一行摘要**。
    case finished
}

/// 思考区「展开 / 折叠」的**唯一判定**（详设 §3.33）。
///
/// 三态是主人 2026-11-07 拍的产品决策：
/// 1. **运行中** ⇒ 展开（否则「思考过程」这四个字就是个摆设）；
/// 2. **终态** ⇒ 自动折成一行摘要（否则一轮 12 步的过程会把结论挤下去）；
/// 3. **用户手动动过** ⇒ 以用户为准，且**本轮内保持**（sticky）—— 不许每帧 /
///    每个新事件又折回去；新轮开始才回到「按阶段默认」。
///
/// 为什么单独做成纯函数：这三条要能逐条判红（`Tests/AgentAnswerSplitTests` 与端上
/// `AgentChatNarrationProbeTests`），写在视图里就只能靠人点。
public struct AgentThinkingFold: Equatable, Sendable {

    /// 给定阶段与用户手动态，这一格该不该展开。
    /// `manual`: `nil` = 没动过（按阶段默认）；`true` = 手动展开；`false` = 手动收起。
    public static func isExpanded(phase: AgentThinkingPhase, manual: Bool?) -> Bool {
        if let manual { return manual }
        return phase == .running
    }
}

/// 用户对思考区的**手动态**（sticky）与它的**轮次作用域**。
///
/// 两个都必须：只记 `manual` 而不记是哪一轮，下一轮一开始就沿用了上一轮的选择
/// （「上一轮我展开过 ⇒ 这一轮也默认展开」），那等于没有默认形态；反过来每帧清掉
/// 就等于点不动（SwiftUI 每次重绘都会重算 body）。
public struct AgentThinkingManualState: Equatable, Sendable {

    public private(set) var turnKey: UUID?
    public private(set) var manual: Bool?

    public init(turnKey: UUID? = nil, manual: Bool? = nil) {
        self.turnKey = turnKey
        self.manual = manual
    }

    /// 记下「当前是哪一轮」。**换了轮次就清空手动态**（回到按阶段默认）。
    public mutating func register(turnKey: UUID?) {
        guard self.turnKey != turnKey else { return }
        self.turnKey = turnKey
        manual = nil
    }

    /// 用户点了一下（`nil` 表示恢复「按阶段默认」）。
    public mutating func set(_ manual: Bool?) {
        self.manual = manual
    }

    /// 给当前轮次用的手动态。
    public func manual(for turnKey: UUID?) -> Bool? {
        self.turnKey == turnKey ? manual : nil
    }
}

