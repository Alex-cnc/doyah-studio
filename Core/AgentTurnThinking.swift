import Foundation

// MARK: - 一轮一个思考区（详设 §3.33.4）

/// 思考区里的**一段**（= 本轮里一个步骤的思考文本）。
///
/// 为什么要有「段」这一层：主人 beta1.0.7 的口径是「多个步骤的思考合一起」——
/// 一轮只有**一个**思考区，但步骤边界不能丢（不然五步的思考连成一坨，
/// 看不出「这是第二步时改的主意」）。段是**区内**的分隔单位，不是第二个折叠层。
public struct AgentThinkingSegment: Equatable, Sendable, Identifiable {

    /// 步骤序号（轮内 1-based，连续：1、2、3…）。渲染成「第 N 步」那行淡分隔。
    public let step: Int
    /// 这一步的思考文本（思考段 + 过程独白，已按「思考段在前」拼好）。
    public let text: String

    public var id: Int { step }

    public init(step: Int, text: String) {
        self.step = step
        self.text = text
    }
}

/// **一轮的思考区**（详设 §3.33.4）：本轮所有步骤的思考文本，按发生顺序累积成一个区。
///
/// ## 改前是什么样（beta1.0.7 真机）
///
/// > 「多个步骤的思考应该是合一起的啊，现在是分成了一块一块的」
///
/// 改前 `AgentChatView.transcript` 在**逐条消息的 `ForEach` 里**调 `thinkingZone(message…)`
/// ⇒ 每个 step 的叙述各拿一个 `AgentThinkingZone`：五步就是五块 200pt 的折叠块，
/// 屏幕上一块一块，读的人要在块与块之间自己接上下文。
///
/// ## 现在
///
/// · **一轮 = 一个区**：本轮的段全在这一个 `segments` 里，顺序即发生顺序；
/// · **区内仍分段**：步骤边界是**轻分隔**（发丝 + 极小字「第 N 步」），不是二级折叠头；
/// · **折展作用于整轮**：区只有一处抬头，点一下折的就是整轮；
/// · **工具块不在这里**：工具调用是**动作**不是思考，仍按调用 / 步骤各自成块（`AgentToolBlockRole`）。
///
/// 为什么要做成纯数据（而不是在视图里现拼）：判据要能数「页面上有几个思考区」、
/// 要能核「段序 == 步序」（`Tests/AgentTurnThinkingTests` 与端上探针
/// `AgentTurnThinkingZoneProbeTests`）；写在视图里就只能靠人眼数块。
public struct AgentTurnThinkingZone: Equatable, Sendable {

    /// 这一轮的轮首消息 id（用户提问；没有提问的轮用本轮第一条消息）。
    /// 手动态（sticky）按它分轮 —— 与 `AgentThinkingManualState.turnKey` 同一把钥匙。
    public let turnKey: UUID

    /// 思考区挂在哪条消息上：本轮**第一条过程消息**（助手或工具）的下标。
    ///
    /// 挂过程开始的地方而不是最后一条：区里装的是整轮的过程，摆在过程开始处读起来才是
    /// 「先想，再动手」；挂最后一条会让它落到结论底下，看起来像「事后总结」。
    public let anchorIndex: Int

    /// 本轮的段（发生顺序）。
    public let segments: [AgentThinkingSegment]

    public init(turnKey: UUID, anchorIndex: Int, segments: [AgentThinkingSegment]) {
        self.turnKey = turnKey
        self.anchorIndex = anchorIndex
        self.segments = segments
    }

    /// 本轮步数（折起来那一行里的「N 步」= 真有思考的步骤数）。
    public var stepCount: Int { segments.count }

    /// 整区文本（段间空一行）—— 与段视图**同一份**内容，判据用它核对顺序。
    public var text: String { segments.map(\.text).joined(separator: "\n\n") }

    public var isEmpty: Bool { segments.isEmpty }
}

/// **一轮的边界**（详设 §3.33.4）：`startIndex...endIndex` 是这一轮的全部消息。
///
/// 为什么单拎出来：轮的定义本来只在 `AgentChatTurnShape`（切分点），但「这一轮从哪条到哪条」
/// 有两处要用（思考段聚合 / 三行汇总的用量），各自再写一遍 `while ... role != .user`
/// 就等于第二份轮定义 —— 迟早两处对不上（一条消息算进这一轮、却不算进那一轮的用量）。
public struct AgentTurnSpan: Equatable, Sendable {

    /// 轮首下标（用户提问；没有提问的轮 = 本轮第一条消息）。
    public let startIndex: Int
    /// 末条下标（含）。
    public let endIndex: Int
    /// 轮首那条消息的 id（手动态 / 用量都按它分轮）。
    public let turnKey: UUID
    /// 过程信息（思考区 / 三行汇总）该挂的位置：本轮**第一条非用户消息**。
    /// `nil` = 这一轮只有提问、还没有任何回复。
    public let anchorIndex: Int?

    public init(startIndex: Int, endIndex: Int, turnKey: UUID, anchorIndex: Int?) {
        self.startIndex = startIndex
        self.endIndex = endIndex
        self.turnKey = turnKey
        self.anchorIndex = anchorIndex
    }

    /// 这一轮是不是从 `index` 起（逐条消息的 `ForEach` 用它找「轮首那一行」）。
    public func contains(_ index: Int) -> Bool { (startIndex...endIndex).contains(index) }
}

/// 把消息切成轮（唯一实现；`AgentTurnThinking` 与 `AgentTurnUsageReader` 都读它）。
public enum AgentTurnSpans {

    public static func spans(in messages: [AgentChatMessage]) -> [AgentTurnSpan] {
        guard !messages.isEmpty else { return [] }
        var spans: [AgentTurnSpan] = []
        var start = 0
        while start < messages.count {
            var end = start
            while end + 1 < messages.count, messages[end + 1].role != .user { end += 1 }
            let anchor = (start...end).first { messages[$0].role != .user }
            spans.append(AgentTurnSpan(startIndex: start,
                                       endIndex: end,
                                       turnKey: messages[start].id,
                                       anchorIndex: anchor))
            start = end + 1
        }
        return spans
    }

    /// 这一条消息属于哪一轮（找不到 = `nil`）。
    public static func span(containing index: Int, in messages: [AgentChatMessage]) -> AgentTurnSpan? {
        spans(in: messages).first { $0.contains(index) }
    }
}

/// 把一轮的消息聚成**一个**思考区（详设 §3.33.4）。
///
/// 三件事都只在这里定义，视图与判据都读它：
/// 1. 「什么算一轮」—— 走 `AgentChatTurnShape`（轮的定义只许有一处）；
/// 2. 「哪段字进思考区」—— 思考段（开关打开时）+ 轮内中间叙述 + 末条结论里的独白；
/// 3. 「段序」—— 按消息出现顺序，步号 1-based 连续。
public enum AgentTurnThinking {

    /// 这是一条助手消息该进思考区的那段字（`nil` = 这条没有过程内容）。
    ///
    /// 口径与改前的 `AgentChatView.thinkingParts` **完全一致**，只是搬进 Core 好让判据也读它：
    /// · 思考段受 `display.thinking` 开关管（关 = 不画，但数据照收）；
    /// · 过程独白**不受**开关管（它既不能回正文，也不该被静默吞掉）；
    /// · 轮内非末条助手消息**整条**都是过程（位置判定）；
    /// · 末条（结论）只取 `AgentAnswerClassifier.split` 认出来的独白段；
    ///   整条都是独白时按兜底走正文，这里就不再放一遍（否则同一段字出现两次）。
    public static func segmentText(of message: AgentChatMessage,
                                   isFinalAssistant: Bool,
                                   includeReasoning: Bool) -> String? {
        guard message.role == .assistant else { return nil }
        var parts: [String] = []
        if includeReasoning,
           let thinking = message.thinking,
           !trimmed(thinking).isEmpty {
            parts.append(trimmed(thinking))
        }
        let text = trimmed(message.text)
        if !text.isEmpty {
            if isFinalAssistant {
                let split = AgentAnswerClassifier.split(message.text)
                if !split.isNarrationOnly, let narration = split.narration,
                   !trimmed(narration).isEmpty {
                    parts.append(trimmed(narration))
                }
            } else {
                parts.append(text)
            }
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "\n\n")
    }

    /// 全部轮次的思考区（按轮序）。空轮不产出（契约②：零占位）。
    public static func zones(in messages: [AgentChatMessage],
                             includeReasoning: Bool) -> [AgentTurnThinkingZone] {
        guard !messages.isEmpty else { return [] }
        let finals = AgentChatTurnShape.finalAssistantIndices(in: messages)
        var zones: [AgentTurnThinkingZone] = []
        for span in AgentTurnSpans.spans(in: messages) {
            var segments: [AgentThinkingSegment] = []
            for index in span.startIndex...span.endIndex where messages[index].role == .assistant {
                guard let text = segmentText(of: messages[index],
                                             isFinalAssistant: finals.contains(index),
                                             includeReasoning: includeReasoning) else { continue }
                segments.append(AgentThinkingSegment(step: segments.count + 1, text: text))
            }
            if let anchor = span.anchorIndex, !segments.isEmpty {
                zones.append(AgentTurnThinkingZone(turnKey: span.turnKey,
                                                   anchorIndex: anchor,
                                                   segments: segments))
            }
        }
        return zones
    }

    /// 给逐条消息的 `ForEach` 用：**只有轮首那条助手消息**会拿到区（其余拿不到）。
    ///
    /// 这就是判据①的机械保证：一个 `ForEach` 循环里，一輪最多命中一次 ⇒ 页面上
    /// `AgentThinkingZone` 实例数 == 轮数，不随步数长。
    public static func zonesByAnchorIndex(in messages: [AgentChatMessage],
                                          includeReasoning: Bool) -> [Int: AgentTurnThinkingZone] {
        var result: [Int: AgentTurnThinkingZone] = [:]
        for zone in zones(in: messages, includeReasoning: includeReasoning) {
            result[zone.anchorIndex] = zone
        }
        return result
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
