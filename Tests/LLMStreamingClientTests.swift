import XCTest
@testable import DoyahCore

/// `FR-AI-16` 第二片（流式传输半）的机械判据：① 请求体带 `stream: true` · ② 逐块拼接一致 ·
/// ⑥ 中途断流 ⇒ 标失败且**不把半截当完整** · 非 2xx 当场如实抛 · 本地端点无 `Authorization`。
final class LLMStreamingClientTests: XCTestCase {

    /// 按脚本吐块的假流式传输（记录请求，便于核对请求体与请求头）。
    private final class ScriptedStreamingTransport: HTTPStreamingTransport, @unchecked Sendable {
        private let status: Int
        private let chunks: [Data]
        private(set) var recorded: [URLRequest] = []

        init(status: Int = 200, chunks: [Data]) {
            self.status = status
            self.chunks = chunks
        }

        func stream(_ request: URLRequest) async throws -> (HTTPURLResponse, AsyncThrowingStream<Data, Error>) {
            recorded.append(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                           httpVersion: "HTTP/1.1", headerFields: nil)!
            let body = chunks
            let stream = AsyncThrowingStream<Data, Error> { continuation in
                for chunk in body { continuation.yield(chunk) }
                continuation.finish()
            }
            return (response, stream)
        }
    }

    private let fullChunks: [Data] = [
        Data(#"data: {"model":"qwen2.5-7b","choices":[{"delta":{"content":"你好"}}]}"#.utf8) + Data("\n\n".utf8),
        Data(#"data: {"choices":[{"delta":{"content":"，世界"}}]}"#.utf8) + Data("\n\n".utf8),
        Data(#"data: {"choices":[{"delta":{"content":"。"},"finish_reason":"stop"}],"usage":{"prompt_tokens":11,"completion_tokens":7,"total_tokens":18}}"#.utf8) + Data("\n\n".utf8),
        Data("data: [DONE]\n\n".utf8),
    ]

    private var request: LLMRequest {
        LLMRequest(endpoint: URL(string: "http://127.0.0.1:11434/v1")!,
                   model: "qwen2.5-7b",
                   systemPrompt: "你是助手。",
                   userPrompt: "你好")
    }

    private func collect(_ stream: AsyncThrowingStream<LLMStreamEvent, Error>) async throws -> [LLMStreamEvent] {
        var events: [LLMStreamEvent] = []
        for try await event in stream { events.append(event) }
        return events
    }

    // MARK: - ① 请求体强制流式 + ④ 本地端点无 Authorization

    func testStreamingRequestForcesStreamFlagAndCarriesNoAuthorizationLocally() async throws {
        let transport = ScriptedStreamingTransport(chunks: fullChunks)
        _ = try await collect(try await OpenAICompatibleStreamingClient(transport: transport).stream(request))

        guard let sent = transport.recorded.first else { return XCTFail("假端点应当收到一次请求") }
        let body = try JSONSerialization.jsonObject(with: sent.httpBody ?? Data()) as? [String: Any]
        XCTAssertEqual(body?["stream"] as? Bool, true, "流式路径必须带 stream: true（调用方没设也不许退化）")
        XCTAssertNil(sent.value(forHTTPHeaderField: "Authorization"), "本地端点免 key：流式请求也不许带")
        XCTAssertEqual(transport.recorded.count, 1)
    }

    // MARK: - ② 逐块拼接 = 整段逐字一致（端到端）

    func testEventsAssembleTheSameTextAsTheWholeStream() async throws {
        let transport = ScriptedStreamingTransport(chunks: fullChunks)
        let events = try await collect(try await OpenAICompatibleStreamingClient(transport: transport).stream(request))

        let text = events.compactMap { if case .textDelta(let piece) = $0 { return piece } else { return nil } }.joined()
        XCTAssertEqual(text, "你好，世界。")

        guard case .usage(let usage, let model)? = events.last(where: {
            if case .usage = $0 { return true } else { return false }
        }) else { return XCTFail("要有用量事件") }
        XCTAssertEqual(model, "qwen2.5-7b")
        XCTAssertEqual(usage.totalTokens, 18)
        XCTAssertEqual(events.last, .done, "最后一个事件应当是 done")
    }

    // MARK: - ⑥ 中途断流 ⇒ 抛可读失败（不返回半截）

    func testInterruptedStreamFinishesByThrowingNotByReturningHalfAText() async throws {
        let transport = ScriptedStreamingTransport(chunks: Array(fullChunks.dropLast()))   // 少了 [DONE]
        var received: [LLMStreamEvent] = []

        do {
            for try await event in try await OpenAICompatibleStreamingClient(transport: transport).stream(request) {
                received.append(event)
            }
            XCTFail("断流必须抛，不许正常结束")
        } catch let error as LLMError {
            guard case .transport(let message) = error else {
                return XCTFail("应当是 transport 失败，实际 = \(error)")
            }
            XCTAssertTrue(message.contains("[DONE]"), "原因要写清没收到 [DONE]，实际 = \(message)")
        }
        let text = received.compactMap { if case .textDelta(let piece) = $0 { return piece } else { return nil } }.joined()
        XCTAssertEqual(text, "你好，世界。", "已收到的增量照给（调用方自己决定怎么处置）")
        XCTAssertFalse(received.contains(.done), "断流不许出现 done —— 那是「完整」的标志")
    }

    // MARK: - 非 2xx ⇒ 当场如实抛（不静默当空流）

    func testNonSuccessStatusThrowsBeforeAnyEvent() async throws {
        let transport = ScriptedStreamingTransport(status: 429, chunks: [Data("data: [DONE]\n\n".utf8)])
        do {
            _ = try await collect(try await OpenAICompatibleStreamingClient(transport: transport).stream(request))
            XCTFail("429 必须抛")
        } catch let error as LLMError {
            guard case .httpStatus(let code, _) = error else {
                return XCTFail("应当是 httpStatus，实际 = \(error)")
            }
            XCTAssertEqual(code, 429)
        }
    }

    // MARK: - `[DONE]` 之后不再读（端到端再证一次）

    func testNothingIsEmittedAfterDone() async throws {
        let transport = ScriptedStreamingTransport(chunks: fullChunks + [Data(#"data: {"choices":[{"delta":{"content":"不该出现"}}]}"#.utf8) + Data("\n\n".utf8)])
        let events = try await collect(try await OpenAICompatibleStreamingClient(transport: transport).stream(request))

        XCTAssertEqual(events.last, .done)
        let text = events.compactMap { if case .textDelta(let piece) = $0 { return piece } else { return nil } }.joined()
        XCTAssertEqual(text, "你好，世界。", "[DONE] 之后的块不许再产出事件")
    }
}
