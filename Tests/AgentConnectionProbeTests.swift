import XCTest
@testable import DoyahCore

/// 「测试连接」的四档结局（`FR-AI-32` 判据 ④）与 `/models` 模型候选取舍（判据 ⑤）。
///
/// 四档：成功 / 401 凭据 / 超时 / 非 JSON（或其它码）。每一档都断言**发给用户的那句话**
/// 说的是同一件事 —— 只看 `case` 不看文案，界面把四档都写成「失败」也照样绿。
///
/// 传输层用 `HTTPStreamingTransport`（与聊天循环同一层）：测连接走的是**流式出口**
/// （`EgressRecordingStreamingTransport` 包着 `URLSessionStreamingTransport`），
/// 所以这里的假传输层也照同一个协议实现，断言才有意义。
final class AgentConnectionProbeTests: XCTestCase {

    private let language = AppLanguage.simplifiedChinese

    /// 可编排的假流式传输层（不发真网络）：按剧本回状态码 + 正文行，或抛一个指定的 `URLError`。
    private final class StubTransport: HTTPStreamingTransport, @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: [URLRequest] = []
        private let result: Result<(Int, [String]), URLError>

        init(status: Int = 200, lines: [String] = []) {
            self.result = .success((status, lines))
        }

        init(status: Int, body: String) {
            self.result = .success((status, [body]))
        }

        init(urlError: URLError) {
            self.result = .failure(urlError)
        }

        var requests: [URLRequest] {
            lock.lock(); defer { lock.unlock() }
            return recorded
        }

        func stream(_ request: URLRequest) async throws -> (HTTPURLResponse, AsyncThrowingStream<Data, Error>) {
            lock.lock(); recorded.append(request); lock.unlock()
            switch result {
            case .failure(let error):
                throw error
            case .success(let (status, lines)):
                let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                              httpVersion: "HTTP/1.1",
                                              headerFields: ["Content-Type": "text/event-stream"])!
                let stream = AsyncThrowingStream<Data, Error> { continuation in
                    for line in lines { continuation.yield(Data(line.utf8)) }
                    continuation.finish()
                }
                return (response, stream)
            }
        }
    }

    /// `/models` 走的是**非流式** `HTTPTransport`（一次 GET，没有 SSE），另给一个假实现。
    private final class StubHTTPTransport: HTTPTransport, @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: [URLRequest] = []
        private let result: Result<(Int, String), URLError>

        init(status: Int = 200, body: String = "") { self.result = .success((status, body)) }
        init(urlError: URLError) { self.result = .failure(urlError) }

        var requests: [URLRequest] {
            lock.lock(); defer { lock.unlock() }
            return recorded
        }

        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            lock.lock(); recorded.append(request); lock.unlock()
            switch result {
            case .failure(let error):
                throw error
            case .success(let (status, body)):
                let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                              httpVersion: "HTTP/1.1",
                                              headerFields: ["Content-Type": "application/json"])!
                return (Data(body.utf8), response)
            }
        }
    }

    private func profile(endpoint: String = "https://api.deepseek.com/v1",
                         model: String = "deepseek-v4.1-flash",
                         timeout: TimeInterval = 60) -> AgentProfile {
        AgentProfile(id: "p", name: "p", presetID: "deepseek",
                     endpoint: endpoint, model: model, timeoutSeconds: timeout)
    }

    /// 一段正常收尾的 SSE（正文一块 + `[DONE]`）。
    private static let successChunks = [
        #"data: {"model":"deepseek-v4.1-flash","choices":[{"delta":{"content":"ok"}}]}"# + "\n\n",
        "data: [DONE]\n\n",
    ]

    // MARK: - ① 成功

    func testSuccessIsReportedAsSuccessWithTheModelAndMilliseconds() async {
        let transport = StubTransport(status: 200, lines: Self.successChunks)
        let outcome = await AgentConnectionProbe.run(profile: profile(), apiKey: "sk-ok", transport: transport)
        guard case .success(let model, let millis) = outcome else {
            return XCTFail("成功那一路没认成 success：\(outcome)")
        }
        XCTAssertEqual(model, "deepseek-v4.1-flash")
        XCTAssertGreaterThanOrEqual(millis, 0)
        let line = outcome.line(language: language)
        XCTAssertTrue(line.contains("连接成功"), "给用户的那句话不是「成功」：\(line)")
        XCTAssertTrue(line.contains("deepseek-v4.1-flash"), "成功那一行没写用了哪个模型：\(line)")
        let request = transport.requests.first
        XCTAssertEqual(request?.url?.absoluteString, "https://api.deepseek.com/v1/chat/completions")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Authorization"), "Bearer sk-ok")
        let body = try? XCTUnwrap(request?.httpBody)
        let payload = body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        XCTAssertEqual(payload?["model"] as? String, "deepseek-v4.1-flash", "请求体里的模型不是这一档的")
        XCTAssertEqual(payload?["stream"] as? Bool, true, "流式出口必须带 stream: true")
        print("🧪 测试连接·成功：\(line)")
    }

    // MARK: - ② 401 凭据

    func testUnauthorizedIsItsOwnOutcomeNotAGenericFailure() async {
        let body = #"{"error":{"message":"Incorrect API key provided","type":"invalid_request_error"}}"#
        let transport = StubTransport(status: 401, body: body)
        let outcome = await AgentConnectionProbe.run(profile: profile(), apiKey: "sk-wrong", transport: transport)
        XCTAssertEqual(outcome, .unauthorized(statusCode: 401))
        let line = outcome.line(language: language)
        XCTAssertTrue(line.contains("401"), "那一行没说状态码：\(line)")
        XCTAssertTrue(line.contains("API Key") || line.contains("凭据"), "那一行没说「是凭据的事」：\(line)")
        print("🧪 测试连接·401：\(line)")
    }

    // MARK: - ③ 超时

    func testTimeoutIsRecognisedAsTimeoutAndSaysHowLongItWaited() async {
        let transport = StubTransport(urlError: URLError(.timedOut))
        let outcome = await AgentConnectionProbe.run(profile: profile(timeout: 12), apiKey: "sk", transport: transport)
        XCTAssertEqual(outcome, .timedOut(seconds: 12))
        let line = outcome.line(language: language)
        XCTAssertTrue(line.contains("12"), "那一行没写等了多久：\(line)")
        XCTAssertTrue(line.contains("超时"), "那一行不是「超时」：\(line)")
        print("🧪 测试连接·超时：\(line)")
    }

    // MARK: - ④ 非 JSON / 其它码

    func testNonJSONBodyIsReportedAsUnexpectedWithTheStatusCode() async {
        let transport = StubTransport(status: 200, body: "<html><body>gateway</body></html>")
        let outcome = await AgentConnectionProbe.run(profile: profile(), apiKey: "sk", transport: transport)
        guard case .unexpected(let statusCode, let detail) = outcome else {
            return XCTFail("非 JSON 正文没认成 unexpected：\(outcome)")
        }
        XCTAssertEqual(statusCode, 200)
        XCTAssertFalse((detail ?? "").isEmpty, "没留下可读原因")
        let line = outcome.line(language: language)
        XCTAssertTrue(line.contains("200"), "那一行没说状态码：\(line)")
        print("🧪 测试连接·非 JSON：\(line)")
    }

    func testOtherErrorCodesAreAlsoUnexpectedAndKeepTheEndpointMessage() async {
        let transport = StubTransport(status: 502, body: #"{"message":"upstream down"}"#)
        let outcome = await AgentConnectionProbe.run(profile: profile(), apiKey: "sk", transport: transport)
        guard case .unexpected(let statusCode, let detail) = outcome else {
            return XCTFail("其它非 2xx 码没认成 unexpected：\(outcome)")
        }
        XCTAssertEqual(statusCode, 502)
        XCTAssertEqual(detail, "upstream down", "端点自己那句错误没被带出来：\(detail ?? "-")")
    }

    // MARK: - 前提不成立 ⇒ 一个字节都不发

    func testMissingEndpointOrModelSendsNothingAndSaysSo() async {
        let transport = StubTransport(status: 200, lines: Self.successChunks)
        let noEndpoint = await AgentConnectionProbe.run(
            profile: profile(endpoint: "", model: "m"), apiKey: "sk", transport: transport)
        guard case .notAttempted(let reason) = noEndpoint else {
            return XCTFail("空端点没被认成「没试」：\(noEndpoint)")
        }
        XCTAssertTrue(reason.contains("端点"), "没说清缺的是端点：\(reason)")

        let noModel = await AgentConnectionProbe.run(
            profile: profile(model: "  "), apiKey: "sk", transport: transport)
        guard case .notAttempted = noModel else {
            return XCTFail("空模型名没被认成「没试」：\(noModel)")
        }
        XCTAssertTrue(transport.requests.isEmpty, "前提都不成立还发了 \(transport.requests.count) 条请求")
        let line = noModel.line(language: language)
        XCTAssertTrue(line.contains("没有发出请求"), "那一行把「没试」说成了别的事：\(line)")
    }

    // MARK: - ⑤ 模型候选：拉到了 / 拉不到（都不是错误）

    func testModelListIsParsedFromTheOpenAICompatibleShape() async throws {
        let body = #"{"object":"list","data":[{"id":"deepseek-v4.1-flash"},{"id":"deepseek-v4-pro"},{"id":"deepseek-v4.1-flash"}]}"#
        let transport = StubHTTPTransport(status: 200, body: body)
        let outcome = await AgentModelListProbe.run(profile: profile(), apiKey: "sk-list", transport: transport)
        XCTAssertEqual(outcome, .listed(["deepseek-v4.1-flash", "deepseek-v4-pro"]),
                       "清单没解析出来 / 没去重：\(outcome)")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://api.deepseek.com/v1/models")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-list")
        XCTAssertTrue(outcome.line(language: language).contains("2"), "那一行没写拉到几个")
        print("🧪 模型候选·拉到：\(outcome.line(language: language))")
    }

    func testModelListFailureFallsBackToTypingInsteadOfAnError() async {
        let unauthorized = await AgentModelListProbe.run(
            profile: profile(), apiKey: "sk", transport: StubHTTPTransport(status: 401, body: ""))
        guard case .unavailable(.unauthorized(let code)) = unauthorized else {
            return XCTFail("401 没认出是凭据：\(unauthorized)")
        }
        XCTAssertEqual(code, 401)

        let malformed = await AgentModelListProbe.run(
            profile: profile(), apiKey: "sk", transport: StubHTTPTransport(status: 200, body: "not-json"))
        XCTAssertEqual(malformed, .unavailable(.malformed))

        let timedOut = await AgentModelListProbe.run(
            profile: profile(timeout: 5), apiKey: "sk", transport: StubHTTPTransport(urlError: URLError(.timedOut)))
        XCTAssertEqual(timedOut, .unavailable(.timedOut(seconds: 5)))

        // 三句结论都是「拉不到 + 原因 + 可以手填」，不是错误弹框
        for outcome in [unauthorized, malformed, timedOut] {
            XCTAssertTrue(outcome.models.isEmpty)
            let line = outcome.line(language: language)
            XCTAssertTrue(line.contains("手填"), "那一行没给出退路（手填）：\(line)")
        }
        print("🧪 模型候选·拉不到：\(malformed.line(language: language))")
    }

    func testPresetDeclaresWhetherTheEndpointSupportsModelListing() {
        XCTAssertTrue(AgentProviderCatalog.preset(id: "deepseek")?.supportsModelListing == true)
        XCTAssertFalse(AgentProviderCatalog.preset(id: "volcano")?.supportsModelListing == true,
                       "火山方舟的模型标识要接入点 ID，不该声明支持 /models")
        XCTAssertFalse(AgentProviderCatalog.custom.supportsModelListing,
                       "「自定义」没有端点，试都不用试")
        XCTAssertTrue(AgentProviderCatalog.preset(id: "vllm")?.supportsModelListing == true,
                      "本地 vLLM 有 /v1/models")
    }

    /// 端点已带 `/models` 时不许叠加成 `/models/models`。
    func testModelsURLDoesNotDoubleThePath() {
        let direct = URL(string: "https://example.com/v1/models")!
        XCTAssertEqual(AgentModelListProbe.modelsURL(from: direct).absoluteString,
                       "https://example.com/v1/models")
        let base = URL(string: "https://example.com/v1/")!
        XCTAssertEqual(AgentModelListProbe.modelsURL(from: base).absoluteString,
                       "https://example.com/v1/models")
    }
}
