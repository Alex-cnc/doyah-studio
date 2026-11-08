import Foundation

/// 把**流式运输**当成「一次整段往返」来用（`FR-AI-32` 测试连接那一条的传输适配）。
///
/// 为什么需要这一层：产品里对模型的出网只有**两条真实出口** —— 整段（`URLSessionTransport`）
/// 与流式（`URLSessionStreamingTransport`）。统一外发日志（`NFR-ALL-GATE-SEC-008`）要求
/// 「测试连接」与聊天循环走**同一条流式缝**（那条缝才是过封条 + 进日志的那一份）；
/// 而「测试连接」只需要一句话的结论，不需要逐块事件。
///
/// 于是：请求仍走流式运输（封条与留痕装饰器都在它外面），这一层只把块流收成一段字节、
/// 交给 `HTTPTransport` 的调用方。语义与 `URLSessionTransport.send` 等价 ——
/// 非 2xx **不在这里抛**（由上层映射成同一套结局）。
public struct HTTPTransportOverStreaming: HTTPTransport {

    private let wrapped: any HTTPStreamingTransport

    public init(wrapped: any HTTPStreamingTransport) {
        self.wrapped = wrapped
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (response, stream) = try await wrapped.stream(request)
        var body = Data()
        for try await chunk in stream {
            body.append(chunk)
        }
        return (body, response)
    }
}
