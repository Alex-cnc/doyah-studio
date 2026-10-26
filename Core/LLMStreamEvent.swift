import Foundation

/// 流式（SSE）里一个可断言的事件（`FR-AI-16` 验收要点 ②⑥）。
public enum LLMStreamEvent: Equatable, Sendable {
    /// 正文增量（拼接用；**不逐字外发**，只有调用方决定怎么呈现）。
    case textDelta(String)
    /// **思考段增量**（`FR-AGT-UX-CONV-012` 的「显示思考段」要的源）。
    ///
    /// 兼容两种线上字段名（两家厂商各写一个，别指望统一）：
    /// `delta.reasoning_content`（DeepSeek / Moonshot 一类）与 `delta.reasoning`（OpenRouter 一类）。
    /// **没有这一段的模型永远不产生这个事件** ⇒ 界面那条「显示思考段」开关在它们身上是零占位，
    /// 这不是缺陷、是如实「本端拿不到」。思考段**不是**正文的一部分，不许并进 `textDelta`
    /// （并进去就会被当成答复交给用户、也会被写进会话文件）。
    case reasoningDelta(String)
    /// 工具调用增量（`id` / `name` 通常只在第一块出现，`arguments` 是**分片**要自己拼）。
    case toolCallDelta(index: Int, id: String?, name: String?, argumentsFragment: String)
    /// 用量（通常只在最后一块出现；带上**实际模型**）。
    case usage(LLMUsage, model: String?)
    /// 结束原因（`stop` / `tool_calls` / `length` …）。
    case finished(reason: String?)
    /// 假端点侧发送的 `data: [DONE]`。
    case done
}

/// SSE 解码器：**纯状态机**，不碰网络、不读时钟 ⇒ 可单测到「逐块边界被切开」这一层。
///
/// 三条口径（照 `FR-AI-16` 验收要点）：
/// 1. 逐块拼接的结果与整段发送**逐字一致**（含一行被切成两块的情况）；
/// 2. `data: [DONE]` 之后**不再读**（后续字节一律忽略，不产生事件）；
/// 3. **没读到 `[DONE]` 就结束 ⇒ 抛可读错误**（`finish()`），绝不把半截回复当完整回复。
public struct LLMStreamDecoder: Sendable {

    /// 已拼好的正文（供「逐字一致」断言与最终成文）。
    public private(set) var text = ""
    /// 已拼好的**思考段**（`FR-AGT-UX-CONV-012`；没有这一段模型的流里它恒为空串）。
    public private(set) var reasoning = ""
    /// 已拼好的工具调用（按 index 归并）。
    public private(set) var toolCalls: [ToolCallAccumulator] = []
    /// 是否收到了 `[DONE]`。
    public private(set) var sawDone = false
    /// 是否收到过任何事件（判断「半截」用）。思考段也算「收到过东西」——
    /// 一条只出了思考段就被掐断的流，报「什么都没收到」是错的。
    public var sawAnyEvent: Bool { !text.isEmpty || !reasoning.isEmpty || !toolCalls.isEmpty || sawDone }

    /// 工具调用的累积器（`arguments` 是分片，必须拼）。
    public struct ToolCallAccumulator: Equatable, Sendable {
        public var index: Int
        public var id: String?
        public var name: String?
        public var arguments = ""
    }

    private var buffer = Data()
    private var usage: LLMUsage?
    private var model: String?
    private var finishReason: String?

    public init() {}

    /// 喂一块**原始字节**（可能是任意切割，含把一行切成两块、把多字节字符切成两块）。
    ///
    /// 缓冲的是**字节**不是字符串：按 `\n` 切出**整行**再解码 —— 否则 UTF-8 多字节字符被切断时会丢字
    /// （判据 ② 的逐字节喂法正是为了抓这个）。
    public mutating func feed(_ chunk: Data) -> [LLMStreamEvent] {
        guard !sawDone else { return [] }        // 口径 2：[DONE] 之后不再读
        buffer.append(chunk)

        var events: [LLMStreamEvent] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            events.append(contentsOf: consume(line: String(decoding: lineData, as: UTF8.self)))
            if sawDone { break }                 // 同一块里 `[DONE]` 之后的部分也不读
        }
        return events
    }

    /// 流结束。**没见到 `[DONE]` ⇒ 抛**（如实说「中断」，不返回半截）。
    public mutating func finish() throws -> [LLMStreamEvent] {
        guard sawDone else {
            let already = text.isEmpty && reasoning.isEmpty && toolCalls.isEmpty
                ? "流在返回任何内容前中断"
                : "流在完成前中断（正文 \(text.count) 字 / 思考段 \(reasoning.count) 字 / 工具调用 \(toolCalls.count) 个）"
            throw LLMError.transport("\(already)：未收到 data: [DONE]。")
        }
        return []
    }

    /// 全部工具调用（拼好的参数）。
    public var assembledToolCalls: [(index: Int, id: String?, name: String?, arguments: String)] {
        toolCalls.map { ($0.index, $0.id, $0.name, $0.arguments) }
    }

    private mutating func consume(line: String) -> [LLMStreamEvent] {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("data:") else { return [] }   // `event:` / 注释 / 空行一律跳过
        let payload = trimmed.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)

        if payload == "[DONE]" {
            sawDone = true
            var events: [LLMStreamEvent] = []
            if let usage { events.append(.usage(usage, model: model)) }
            events.append(.finished(reason: finishReason))
            events.append(.done)
            return events
        }

        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []                                          // 坏块跳过（不打断整条流）
        }

        if let modelName = object["model"] as? String { model = modelName }
        if let usageObject = object["usage"] as? [String: Any] {
            // **同一个解析处**（`LLMUsage.parsed`）：流式与非流式不许各写一套用量解析
            // （否则缓存读数只会出现在其中一条路上，而症状是「有时有、有时没有」）。
            usage = LLMUsage.parsed(from: usageObject)
        }

        guard let choices = object["choices"] as? [[String: Any]], let first = choices.first else {
            return []
        }
        if let reason = first["finish_reason"] as? String { finishReason = reason }

        var events: [LLMStreamEvent] = []
        if let delta = first["delta"] as? [String: Any] {
            // **思考段先读**（`FR-AGT-UX-CONV-012`）：两种线上字段名都认，谁在就给谁。
            // 它与 `content` 是两个通道 —— 有模型**两个都发**（思考完再发正文），
            // 按 `else if` 串起来会丢掉其中一段，所以是两条独立的 `if`。
            if let reasoning = LLMResponse.reasoningText(of: delta) {
                self.reasoning += reasoning
                events.append(.reasoningDelta(reasoning))
            }
            if let content = delta["content"] as? String, !content.isEmpty {
                text += content
                events.append(.textDelta(content))
            }
            if let calls = delta["tool_calls"] as? [[String: Any]] {
                for call in calls {
                    let index = call["index"] as? Int ?? 0
                    let id = call["id"] as? String
                    let function = call["function"] as? [String: Any]
                    let name = function?["name"] as? String
                    let fragment = function?["arguments"] as? String ?? ""

                    if let position = toolCalls.firstIndex(where: { $0.index == index }) {
                        if let id { toolCalls[position].id = id }
                        if let name { toolCalls[position].name = name }
                        toolCalls[position].arguments += fragment
                    } else {
                        toolCalls.append(ToolCallAccumulator(index: index, id: id, name: name, arguments: fragment))
                    }
                    events.append(.toolCallDelta(index: index, id: id, name: name, argumentsFragment: fragment))
                }
            }
        }
        return events
    }
}
