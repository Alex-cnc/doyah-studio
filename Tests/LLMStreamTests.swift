import XCTest
@testable import DoyahCore

/// `FR-AI-16` 第一片（网关扩展：流式 SSE + `tools` / `tool_choice` + 用量）的机械判据。
final class LLMStreamTests: XCTestCase {

    // MARK: - 夹具

    private func sse(_ payloads: [String]) -> Data {
        Data(payloads.map { "data: \($0)\n\n" }.joined().utf8)
    }

    private func chunk(_ json: String) -> String {
        "data: \(json)\n\n"
    }

    private let fullStream = [
        #"{"model":"qwen2.5-7b","choices":[{"delta":{"role":"assistant","content":"你好"}}]}"#,
        #"{"choices":[{"delta":{"content":"，世界"}}]}"#,
        #"{"choices":[{"delta":{"content":"。"},"finish_reason":"stop"}],"usage":{"prompt_tokens":11,"completion_tokens":7,"total_tokens":18}}"#,
        "[DONE]",
    ]

    private func request(tools: [LLMTool]? = nil,
                         toolChoice: LLMToolChoice? = nil,
                         stream: Bool = false,
                         apiKey: String? = nil) -> LLMRequest {
        LLMRequest(endpoint: URL(string: "http://127.0.0.1:11434/v1")!,
                   model: "qwen2.5-7b",
                   apiKey: apiKey,
                   systemPrompt: "你是助手。",
                   userPrompt: "你好",
                   tools: tools,
                   toolChoice: toolChoice,
                   stream: stream)
    }

    private func body(_ request: LLMRequest) throws -> [String: Any] {
        let data = try OpenAICompatibleClient.makeBody(request)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    // MARK: - 判据 ①：外发请求体带 `stream: true` + `tools`（条数相等）+ `tool_choice` 取值合法

    func testRequestBodyCarriesStreamToolsAndLegalToolChoice() throws {
        let tools = [
            LLMTool(name: "read_file", description: "读文件",
                    parametersJSON: #"{"type":"object","properties":{"path":{"type":"string"}}}"#),
            LLMTool(name: "search", description: "搜索",
                    parametersJSON: #"{"type":"object","properties":{"query":{"type":"string"}}}"#),
        ]
        let payload = try body(request(tools: tools, toolChoice: .automatic, stream: true))

        XCTAssertEqual(payload["stream"] as? Bool, true)
        let sent = payload["tools"] as? [[String: Any]]
        XCTAssertEqual(sent?.count, tools.count, "条数必须等于注册表启用的条数（一条不多、一条不少）")
        let first = (sent?.first?["function"]) as? [String: Any]
        XCTAssertEqual(first?["name"] as? String, "read_file")
        XCTAssertNotNil(first?["parameters"], "参数 schema 原样透传")
        XCTAssertEqual(payload["tool_choice"] as? String, "auto")
        XCTAssertTrue(LLMToolChoice.allowedStringValues.contains(payload["tool_choice"] as? String ?? ""))
    }

    /// 指名工具走对象形态；且字符串档拒绝集合外的值。
    func testNamedToolChoiceShapeAndRejection() throws {
        let payload = try body(request(tools: [LLMTool(name: "search", description: "s", parametersJSON: "{}")],
                                      toolChoice: .function("search")))
        let choice = payload["tool_choice"] as? [String: Any]
        XCTAssertEqual(choice?["type"] as? String, "function")
        XCTAssertEqual((choice?["function"] as? [String: Any])?["name"] as? String, "search")
        XCTAssertNil(LLMToolChoice(rawValue: "whatever"), "集合外的取值要拒绝，不猜")
    }

    /// **默认不变**：不带新参数 ⇒ 请求体里 `stream: false`，且**没有** `tools` / `tool_choice` 两个键。
    func testDefaultRequestIsByteCompatibleWithBefore() throws {
        let payload = try body(request())
        XCTAssertEqual(payload["stream"] as? Bool, false)
        XCTAssertNil(payload["tools"])
        XCTAssertNil(payload["tool_choice"])
    }

    // MARK: - 判据 ②：逐块拼接 = 整段逐字一致（含把一行切成两块）

    func testChunkedParsingMatchesTheWholeStreamVerbatim() throws {
        var whole = LLMStreamDecoder()
        _ = whole.feed(sse(fullStream))
        try whole.finish()

        // 逐字节喂（最坏的切法：每一行都被切开）
        var byteWise = LLMStreamDecoder()
        for byte in sse(fullStream) { _ = byteWise.feed(Data([byte])) }
        try byteWise.finish()

        XCTAssertEqual(whole.text, "你好，世界。")
        XCTAssertEqual(byteWise.text, whole.text, "逐块边界被切开也必须逐字一致")
        XCTAssertTrue(byteWise.sawDone)
        XCTAssertEqual(whole.assembledToolCalls.count, 0)
    }

    /// `data: [DONE]` 之后**不再读**：后续字节不产生事件、不改文本。
    func testNothingIsReadAfterDone() throws {
        var decoder = LLMStreamDecoder()
        _ = decoder.feed(sse(fullStream))
        let after = decoder.feed(Data(chunk(#"{"choices":[{"delta":{"content":"不该出现"}}]}"#).utf8))

        XCTAssertTrue(after.isEmpty, "[DONE] 之后不许再产生事件")
        XCTAssertEqual(decoder.text, "你好，世界。")
    }

    /// 同一块里 `[DONE]` 之后的部分也不读。
    func testTrailingBytesInTheSameChunkAreIgnored() throws {
        var decoder = LLMStreamDecoder()
        let data = Data((chunk(#"{"choices":[{"delta":{"content":"A"}}]}"#) + chunk("[DONE]")
                         + chunk(#"{"choices":[{"delta":{"content":"B"}}]}"#)).utf8)
        _ = decoder.feed(data)
        XCTAssertEqual(decoder.text, "A")
        XCTAssertTrue(decoder.sawDone)
    }

    // MARK: - 判据 ⑥：中途断流 ⇒ 标失败并给可读原因，**不把半截当完整**

    func testInterruptedStreamThrowsInsteadOfReturningAHalfReply() {
        var decoder = LLMStreamDecoder()
        _ = decoder.feed(sse(Array(fullStream.dropLast())))    // 没有 `[DONE]`

        XCTAssertThrowsError(try decoder.finish()) { error in
            guard case LLMError.transport(let message) = error else {
                return XCTFail("应当是可读的 transport 失败，实际 = \(error)")
            }
            XCTAssertTrue(message.contains("[DONE]"), "原因里要写清「没收到 data: [DONE]」，实际 = \(message)")
            XCTAssertTrue(message.contains("中断"))
        }
    }

    // MARK: - 工具调用分片 + 用量

    func testToolCallFragmentsAreAssembledAndUsageIsReported() throws {
        var decoder = LLMStreamDecoder()
        let pieces = [
            #"{"model":"m-1","choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","function":{"name":"read_file","arguments":"{\"pa"}}]}}]}"#,
            #"{"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"th\":\"a.txt\"}"}}]}}]}"#,
            #"{"choices":[{"delta":{},"finish_reason":"tool_calls"}],"usage":{"prompt_tokens":4,"completion_tokens":9,"total_tokens":13}}"#,
            "[DONE]",
        ]
        var events: [LLMStreamEvent] = []
        for piece in pieces { events.append(contentsOf: decoder.feed(Data(chunk(piece).utf8))) }
        events.append(contentsOf: try decoder.finish())

        let calls = decoder.assembledToolCalls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.name, "read_file")
        XCTAssertEqual(calls.first?.id, "call_1")
        XCTAssertEqual(calls.first?.arguments, #"{"path":"a.txt"}"#, "分片参数要拼成完整 JSON")

        guard case .usage(let usage, let model)? = events.first(where: {
            if case .usage = $0 { return true } else { return false }
        }) else { return XCTFail("要有用量事件") }
        XCTAssertEqual(model, "m-1", "用量要带上**实际模型**")
        XCTAssertEqual(usage.promptTokens, 4)
        XCTAssertEqual(usage.completionTokens, 9)

        guard case .finished(let reason)? = events.first(where: {
            if case .finished = $0 { return true } else { return false }
        }) else { return XCTFail("要有结束原因") }
        XCTAssertEqual(reason, "tool_calls")
        XCTAssertTrue(decoder.sawAnyEvent)
    }

    /// 坏块跳过、不打断整条流（后面还能收到）。
    func testMalformedChunksDoNotKillTheStream() throws {
        var decoder = LLMStreamDecoder()
        _ = decoder.feed(Data((chunk("{ 这不是 JSON") + chunk(#"{"choices":[{"delta":{"content":"X"}}]}"#)
                               + chunk("[DONE]")).utf8))
        try decoder.finish()
        XCTAssertEqual(decoder.text, "X")
    }

    // MARK: - 判据 ④：本地端点请求**不带** `Authorization` 头

    func testLocalEndpointRequestCarriesNoAuthorizationHeader() throws {
        let urlRequest = try OpenAICompatibleClient.makeURLRequest(request(stream: true))
        XCTAssertNil(urlRequest.value(forHTTPHeaderField: "Authorization"),
                     "本地端点免 key：不许带 Authorization")

        let withKey = try OpenAICompatibleClient.makeURLRequest(request(apiKey: "sk-test"))
        XCTAssertEqual(withKey.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        // 密钥只进头，不进体（不许被日志 / 审计顺走）
        let text = String(data: withKey.httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertFalse(text.contains("sk-test"))
    }
}
