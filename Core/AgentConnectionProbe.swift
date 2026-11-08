import Foundation

/// 一次「测试连接」的结论（`FR-AI-32` 多档配置面的第 ④ 条）。
///
/// 为什么不是 `Bool` / 一句错误串：四种结局对用户要做的事**完全不同** ——
/// 401 = 换 Key，超时 = 查网络 / 代理 / 端点地址，非 JSON = 端点不是 OpenAI 兼容接口，
/// 成功 = 这一档可以用了。把四件事压成一句「失败」，用户只能靠猜。
///
/// **一个都不许省略**：`notAttempted` 是第五档 —— 总开关关着 / 配置不全 / 配额超限时
/// **一个字节都没发**，这时候说「连接失败」是撒谎（失败的是前提，不是网络）。
public enum AgentConnectionOutcome: Equatable, Sendable {
    /// 端点回了可解析的模型结果。
    case success(model: String, millis: Int)
    /// 端点拒绝凭据（HTTP 401 / 403）。
    case unauthorized(statusCode: Int)
    /// 超时：期限内没有任何响应。
    case timedOut(seconds: TimeInterval)
    /// 有响应但不是模型结果（非 JSON / 缺 `[DONE]` / 其它非 2xx 码）。
    case unexpected(statusCode: Int?, detail: String?)
    /// **没有发请求**（总开关关 / 配置不全 / 缺密钥 / 配额超限 / 封条拒绝）。原因原样带上。
    case notAttempted(reason: String)

    /// 是否算「这一档能用」。
    public var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    /// 一句人话（界面直接显示；语言由调用方给）。
    public func line(language: AppLanguage) -> String {
        switch self {
        case .success(let model, let millis):
            return LocalizedStrings.format(.agentConnectionSuccess, language: language, model, Int64(millis))
        case .unauthorized(let statusCode):
            return LocalizedStrings.format(.agentConnectionUnauthorized, language: language, Int64(statusCode))
        case .timedOut(let seconds):
            return LocalizedStrings.format(.agentConnectionTimeout, language: language, Int64(seconds.rounded()))
        case .unexpected(let statusCode, let detail):
            let code: String = statusCode.map(String.init) ?? "?"
            return LocalizedStrings.format(.agentConnectionUnexpected, language: language,
                                           code, detail ?? "")
        case .notAttempted(let reason):
            return LocalizedStrings.format(.agentConnectionNotAttempted, language: language, reason)
        }
    }
}

/// 测试连接：**真发一次最小请求**，四档结局各自认出来（`FR-AI-32`）。
///
/// 三条纪律（与 Agent 循环同源，这里只是把「认结局」搬到 Core 好单测）：
/// 1. 走**同一个流式出口**：`HTTPStreamingTransport`（生产是 `EgressRecordingStreamingTransport`
///    包着 `URLSessionStreamingTransport` —— 与聊天循环那条路同一层装饰器，测试连接也留痕），
///    请求**仍由 `OpenAICompatibleClient.makeURLRequest` 造**（端点补 `/chat/completions`、
///    `Authorization: Bearer`、请求体形状只此一处），SSE 用**同一个** `LLMStreamDecoder` 解；
/// 2. **不吞状态码**：非 2xx 直接按码分档（401·403 = 凭据，其它 = 端点有响应但不对）——
///    这一层刻意不走 `OpenAICompatibleStreamingClient.stream`（它把状态码折进 `LLMError`，
///    测连接需要的正是「到底几号」与「正文说了什么」）；
/// 3. **不抛错**：所有结局收敛成 `AgentConnectionOutcome`，界面拿到的永远是一句话而不是异常。
public enum AgentConnectionProbe {

    /// 这探针用的最小请求体：只要端点走通一次，不追求模型回答得漂亮。
    ///
    /// 两段都是**给模型读的提示词**（不本地化 —— 模型侧不跟界面语言走），所以走语言表的
    /// `defaultText` 取简体中文槽位，而不是在 Core 里写字面量（语言只有一个来源）。
    public static var probeSystemPrompt: String {
        LocalizedStrings.defaultText(.agentConnectionProbeSystemPrompt)
    }

    /// 非 2xx 时最多读多少字节来取错误信息（多读无益，也不能把整段 HTML 收进内存）。
    static let errorBodyByteLimit = 64 * 1024

    /// 跑一次。`apiKey` 传 `nil` = 这一档没有 Key（本地端点合法，远端端点会 401）。
    public static func run(
        profile: AgentProfile,
        apiKey: String?,
        transport: any HTTPStreamingTransport = URLSessionStreamingTransport()
    ) async -> AgentConnectionOutcome {
        let trimmedEndpoint = profile.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = profile.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = URL(string: trimmedEndpoint)
        // 前提不成立 ⇒ **一个字节都不发**，如实说「没试」（不是「失败」）。
        guard let url,
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else {
            return .notAttempted(reason: AgentConfigurationIssue.emptyEndpoint.message)
        }
        guard !trimmedModel.isEmpty else {
            return .notAttempted(reason: AgentConfigurationIssue.emptyModel.message)
        }
        let timeout = profile.timeoutSeconds > 0
            ? min(profile.timeoutSeconds, AgentConfiguration.maximumTimeoutSeconds)
            : AgentConfiguration.defaultTimeoutSeconds

        var request = LLMRequest(endpoint: url, model: trimmedModel,
                                 apiKey: apiKey,
                                 timeoutSeconds: timeout,
                                 systemPrompt: probeSystemPrompt,
                                 userPrompt: LocalizedStrings.defaultText(.agentConnectionProbeUserPrompt))
        request.maxOutputTokens = 8
        request.stream = true

        let urlRequest: URLRequest
        do {
            urlRequest = try OpenAICompatibleClient.makeURLRequest(request)
        } catch {
            return .unexpected(statusCode: nil, detail: error.localizedDescription)
        }

        let started = Date()
        let response: HTTPURLResponse
        let chunks: AsyncThrowingStream<Data, Error>
        do {
            (response, chunks) = try await transport.stream(urlRequest)
        } catch let error as URLError {
            switch error.code {
            case .timedOut:
                return .timedOut(seconds: timeout)
            default:
                return .unexpected(statusCode: nil, detail: error.localizedDescription)
            }
        } catch let error as LLMError {
            // 封条关着 / 闸门拒绝：请求根本没出去 —— 这不是「连接失败」。
            return .notAttempted(reason: error.errorDescription ?? error.localizedDescription)
        } catch {
            return .unexpected(statusCode: nil, detail: error.localizedDescription)
        }

        if response.statusCode == 401 || response.statusCode == 403 {
            return .unauthorized(statusCode: response.statusCode)
        }
        guard (200..<300).contains(response.statusCode) else {
            let body = await collectBody(chunks)
            return .unexpected(statusCode: response.statusCode,
                               detail: OpenAICompatibleClient.errorMessage(from: body))
        }

        // 2xx：把 SSE 收完（同一个解码器）。**没见到 `data: [DONE]`** 说明端点回的不是模型流
        // （典型：反向代理的 HTML 错误页），如实归到 `unexpected` 而不是「成功」。
        var decoder = LLMStreamDecoder()
        do {
            for try await chunk in chunks {
                _ = decoder.feed(chunk)
                if decoder.sawDone { break }
            }
            _ = try decoder.finish()
        } catch let error as URLError {
            if error.code == .timedOut { return .timedOut(seconds: timeout) }
            return .unexpected(statusCode: response.statusCode, detail: error.localizedDescription)
        } catch {
            return .unexpected(statusCode: response.statusCode,
                               detail: (error as? LLMError)?.errorDescription ?? error.localizedDescription)
        }
        return .success(model: trimmedModel,
                        millis: Int(Date().timeIntervalSince(started) * 1000))
    }

    /// 读非 2xx 的正文（有条数上限），只为把端点自己那句话带给用户。
    private static func collectBody(_ chunks: AsyncThrowingStream<Data, Error>) async -> Data {
        var body = Data()
        do {
            for try await chunk in chunks {
                body.append(chunk)
                if body.count >= errorBodyByteLimit { break }
            }
        } catch {
            // 读不下去就不读：状态码已经够了，正文只是加分项。
        }
        return body
    }
}
