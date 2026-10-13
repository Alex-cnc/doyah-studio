import Foundation

/// 流式**传输层**抽象（`FR-AI-16` 第二片）。
///
/// 与 `HTTPTransport` **分开**：既有那个契约是「一次拿回整段」，既有假实现都按它写；
/// 为了流式去改它，等于把这一族判据全部推翻重写。这里另开一条**能力通道**，
/// 老的假实现一行不用动，老判据继续有效。
public protocol HTTPStreamingTransport: Sendable {
    /// 返回（状态码 + 头，块流）。**非 2xx 不在这里抛** —— 统一由上层映射成同一套 `LLMError`。
    func stream(_ request: URLRequest) async throws -> (HTTPURLResponse, AsyncThrowingStream<Data, Error>)
}

/// 流式模型客户端（`FR-AI-16` ① ② ⑥ 的传输半）。
public protocol LLMStreamingClient: Sendable {
    /// 逐块产出事件。**没收到 `data: [DONE]` 就结束 ⇒ 以 `LLMError.transport` 结束**，
    /// 绝不把半截回复当完整回复（验收要点 ⑥）。
    func stream(_ request: LLMRequest) async throws -> AsyncThrowingStream<LLMStreamEvent, Error>
}

/// OpenAI 兼容的流式客户端：**请求体强制 `stream: true`**（调用方忘了设也不会退化成整段请求）。
public struct OpenAICompatibleStreamingClient: LLMStreamingClient {

    private let transport: any HTTPStreamingTransport

    public init(transport: any HTTPStreamingTransport = URLSessionStreamingTransport()) {
        self.transport = transport
    }

    public func stream(_ request: LLMRequest) async throws -> AsyncThrowingStream<LLMStreamEvent, Error> {
        var streamRequest = request
        streamRequest.stream = true
        let urlRequest = try OpenAICompatibleClient.makeURLRequest(streamRequest)

        let (response, chunks) = try await transport.stream(urlRequest)
        guard (200..<300).contains(response.statusCode) else {
            // 头已经回来了，成败此刻就定得下来 ⇒ 如实抛同一套错误（不静默当空流）。
            throw LLMError.httpStatus(code: response.statusCode, message: nil)
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                var decoder = LLMStreamDecoder()
                do {
                    for try await chunk in chunks {
                        for event in decoder.feed(chunk) { continuation.yield(event) }
                        if decoder.sawDone { break }        // 口径 2：`[DONE]` 之后不再读
                    }
                    for event in try decoder.finish() { continuation.yield(event) }
                    continuation.finish()
                } catch let error as LLMError {
                    continuation.finish(throwing: error)
                } catch {
                    continuation.finish(throwing: LLMError.transport(error.localizedDescription))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// 真实实现：`URLSession` 的逐字节读。**按行冲刷** —— SSE 的语义单位就是行，
/// 一次一行给上去，解码器那侧既不用囤整段，也能在断流时第一时间发现。
public struct URLSessionStreamingTransport: HTTPStreamingTransport {

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func stream(_ request: URLRequest) async throws -> (HTTPURLResponse, AsyncThrowingStream<Data, Error>) {
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.transport("响应不是 HTTP 响应。")
        }

        let stream = AsyncThrowingStream<Data, Error> { continuation in
            let task = Task {
                var buffer = Data()
                do {
                    for try await byte in bytes {
                        buffer.append(byte)
                        if byte == 0x0A {
                            continuation.yield(buffer)
                            buffer.removeAll(keepingCapacity: true)
                        }
                    }
                    if !buffer.isEmpty { continuation.yield(buffer) }   // 收尾那半行也要给出去
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: LLMError.transport(error.localizedDescription))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        return (http, stream)
    }
}
