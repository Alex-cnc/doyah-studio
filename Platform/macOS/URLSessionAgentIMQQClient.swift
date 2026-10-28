import Foundation
import DoyahCore

/// QQ 开放平台的 REST 出口（`AgentIMQQHTTPClient` 的真实现：取 token、取网关地址）。
///
/// 为什么单独一个文件：`Scripts/check-network-egress.py` 按**文件**登记出网面 ——
/// 一个文件只做一件事，登记理由才写得清（`Scripts/network-egress-whitelist.json` 的 `outOfFace`）。
/// 这一层**不认识凭据也不认识 token**：进来什么样、出去什么样，token 只在请求头里过一手。
public struct URLSessionAgentIMQQClient: AgentIMQQHTTPClient, AgentIMOutboundHTTPClient {

    private let session: URLSession

    public init(timeout: TimeInterval = 15) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout * 2
        // 没网时立刻失败：让面板马上说「连不上 QQ 的接口」，而不是挂 15 秒假装在忙。
        configuration.waitsForConnectivity = false
        self.session = URLSession(configuration: configuration)
    }

    public func post(_ url: URL,
                     json body: [String: String],
                     headers: [String: String]) async throws -> AgentIMHTTPResponse {
        guard let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]),
              let payload = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotParseResponse)
        }
        return try await post(url, payload: payload, headers: headers)
    }

    /// 发消息那条路用这一版：正文里 `msg_type` / `msg_seq` 是**数字**，
    /// 走 `[String: String]` 会被迫写成 `"0"` / `"1"` —— 服务端按类型校验会直接拒。
    public func post(_ url: URL,
                     payload: String,
                     headers: [String: String]) async throws -> AgentIMHTTPResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data(payload.utf8)
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return try await perform(request)
    }

    public func get(_ url: URL, headers: [String: String]) async throws -> AgentIMHTTPResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return try await perform(request)
    }

    private func perform(_ request: URLRequest) async throws -> AgentIMHTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return AgentIMHTTPResponse(status: http.statusCode,
                                   body: String(data: data, encoding: .utf8) ?? "")
    }
}

/// 装配缝用的工厂：宿主只说「要一个系统实现」，**不出现出网 API 的名字**。
///
/// 由头：`Scripts/check-network-egress.py` 纪律③ —— 装配缝文件（`App/AppState.swift`）里
/// `URLSession` 只许出现在「注入 transport」那两处；直接在那一层 new 一个客户端会判红。
/// 与 `AgentIMSocketFactories.webSocket()` 同一个做法。
public enum AgentIMQQClients {
    public static func system(timeout: TimeInterval = 15) -> any AgentIMQQHTTPClient {
        URLSessionAgentIMQQClient(timeout: timeout)
    }

    /// 发消息那条路的出口（同一个实现，只是取用时的协议不同 —— 装配缝里不出现出网 API 的名字）。
    public static func outbound(timeout: TimeInterval = 15) -> any AgentIMOutboundHTTPClient {
        URLSessionAgentIMQQClient(timeout: timeout)
    }
}
