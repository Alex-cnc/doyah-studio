import Foundation

/// 拉模型清单没拉到的**原因**（`FR-AI-32` 配置面第 ⑤ 条）。
///
/// 分档而不是一句串：超时要查网络 / 代理，401 要换 Key，非 JSON 说明端点不是 OpenAI 兼容接口，
/// 其它码是端点自己的事。界面把原因说给用户听，然后**退回手填**。
public enum AgentModelListFailure: Equatable, Sendable {
    case timedOut(seconds: TimeInterval)
    case unauthorized(statusCode: Int)
    case badStatus(code: Int, detail: String?)
    case malformed
    case transport(String)

    public func line(language: AppLanguage) -> String {
        switch self {
        case .timedOut(let seconds):
            return LocalizedStrings.format(.agentConnectionTimeout, language: language,
                                           Int64(seconds.rounded()))
        case .unauthorized(let statusCode):
            return LocalizedStrings.format(.agentConnectionUnauthorized, language: language,
                                           Int64(statusCode))
        case .badStatus(let code, let detail):
            let shown: String = detail ?? ""
            return LocalizedStrings.format(.agentConnectionUnexpected, language: language,
                                           String(code), shown)
        case .malformed:
            return LocalizedStrings.text(.agentModelListMalformed, language: language)
        case .transport(let message):
            return message
        }
    }
}

/// 从端点拉模型候选的结论。
///
/// **失败不是错误**：预设内置清单是起点，拉不到就退回手填 —— 所以这里没有 throw，
/// 也**没有**「错误」这一档，只有「拉到了 n 个」与「拉不到（原因）」两句话。
public enum AgentModelListOutcome: Equatable, Sendable {
    case listed([String])
    case unavailable(AgentModelListFailure)

    public var models: [String] {
        if case .listed(let models) = self { return models }
        return []
    }

    /// 一句话结论（界面显示在模型下拉旁边，**不弹框**）。
    public func line(language: AppLanguage) -> String {
        switch self {
        case .listed(let models):
            return LocalizedStrings.format(.agentModelListFetched, language: language, Int64(models.count))
        case .unavailable(let failure):
            return LocalizedStrings.format(.agentModelListUnavailable, language: language,
                                           failure.line(language: language))
        }
    }
}

/// 拉 `GET {endpoint}/models`（OpenAI 兼容的服务都提供这一条）。
///
/// 只做三件事：造请求、发出去、把 `data[].id` 收成清单。**收敛成结论、不抛错** ——
/// 用户点它只是想看看有哪些模型，拉不到不该变成一枚错误弹框。
public enum AgentModelListProbe {

    /// 模型清单路径（与 `OpenAICompatibleClient.chatCompletionsPath` 同一种拼法）。
    public static let modelsPath = "models"

    /// 把配置里的端点补成 `.../models`（已是该路径则不重复追加）。
    public static func modelsURL(from endpoint: URL) -> URL {
        let path = endpoint.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.hasSuffix(modelsPath) { return endpoint }
        return endpoint.appendingPathComponent(modelsPath)
    }

    public static func run(
        profile: AgentProfile,
        apiKey: String?,
        transport: any HTTPTransport = URLSessionTransport()
    ) async -> AgentModelListOutcome {
        let trimmed = profile.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let endpoint = URL(string: trimmed),
              let scheme = endpoint.scheme?.lowercased(), scheme == "http" || scheme == "https",
              endpoint.host?.isEmpty == false else {
            return .unavailable(.transport(AgentConfigurationIssue.emptyEndpoint.message))
        }
        let timeout = profile.timeoutSeconds > 0
            ? min(profile.timeoutSeconds, AgentConfiguration.maximumTimeoutSeconds)
            : AgentConfiguration.defaultTimeoutSeconds

        var request = URLRequest(url: modelsURL(from: endpoint))
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch let error as URLError {
            if error.code == .timedOut { return .unavailable(.timedOut(seconds: timeout)) }
            return .unavailable(.transport(error.localizedDescription))
        } catch let error as LLMError {
            return .unavailable(.transport(error.errorDescription ?? error.localizedDescription))
        } catch {
            return .unavailable(.transport(error.localizedDescription))
        }

        if response.statusCode == 401 || response.statusCode == 403 {
            return .unavailable(.unauthorized(statusCode: response.statusCode))
        }
        guard (200..<300).contains(response.statusCode) else {
            return .unavailable(.badStatus(code: response.statusCode,
                                           detail: OpenAICompatibleClient.errorMessage(from: data)))
        }
        guard let ids = parseModelIDs(data), !ids.isEmpty else {
            return .unavailable(.malformed)
        }
        return .listed(ids)
    }

    /// 解析 `{"data":[{"id":"..."}]}`；也认 `data: ["..."]` 与裸数组两种形状。
    /// 去重、保序、去空串 —— 服务端重复列同一个模型是很常见的。
    public static func parseModelIDs(_ data: Data) -> [String]? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        let raw: [Any]
        if let dictionary = object as? [String: Any], let list = dictionary["data"] as? [Any] {
            raw = list
        } else if let list = object as? [Any] {
            raw = list
        } else {
            return nil
        }
        var ids: [String] = []
        for entry in raw {
            let id: String?
            if let dictionary = entry as? [String: Any] {
                id = (dictionary["id"] as? String) ?? (dictionary["name"] as? String)
            } else {
                id = entry as? String
            }
            if let id {
                let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty, !ids.contains(trimmed) { ids.append(trimmed) }
            }
        }
        return ids
    }
}
