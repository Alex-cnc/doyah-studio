import Foundation
import DoyahCore

/// 真 WebSocket 适配（`URLSessionWebSocketTask`）—— `FR-AGT-LINK-CHAN-003` 传输层的**线**。
///
/// 分工写清：
/// · 连接状态机、心跳、退避、补发都在 `DoyahCore.AgentIMTransport` 里（与平台无关，判据用假 socket）；
/// · 这一件只负责「怎么把一帧真的发出去、怎么真的收回来」，于是换成别的传输（长轮询 / 自研 TCP）
///   也不必动 Core；
/// · 握手头（AppID / 时间戳 / nonce / 签名）由 `AgentIMGatewaySigner` 算好，这里**只往里塞**。
public final class URLSessionAgentIMSocket: AgentIMSocket, @unchecked Sendable {

    private let session: URLSession
    private let task: URLSessionWebSocketTask

    public init(url: URL, headers: [String: String], timeoutSeconds: TimeInterval = 20) {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeoutSeconds
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeoutSeconds
        let session = URLSession(configuration: configuration)
        self.session = session
        self.task = session.webSocketTask(with: request)
    }

    public func open() async throws {
        task.resume()
    }

    public func send(_ text: String) async throws {
        try await task.send(.string(text))
    }

    public func receive() async throws -> String {
        let message = try await task.receive()
        switch message {
        case .string(let text):
            return text
        case .data(let data):
            return String(decoding: data, as: UTF8.self)
        @unknown default:
            return ""
        }
    }

    public func close() async {
        task.cancel(with: .goingAway, reason: nil)
        session.invalidateAndCancel()
    }
}

/// 工厂的**生产实现**（`AgentIMSocketFactory` 是闭包类型别名，不能扩展 ⇒ 放一个命名空间）。
public enum AgentIMSocketFactories {
    /// 真 WebSocket。测试与判据**不许**用它（要假 socket 才谈得上稳定）。
    public static func webSocket(timeoutSeconds: TimeInterval = 20) -> AgentIMSocketFactory {
        { url, headers in
            URLSessionAgentIMSocket(url: url, headers: headers, timeoutSeconds: timeoutSeconds)
        }
    }
}
