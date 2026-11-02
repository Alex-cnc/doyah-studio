import XCTest
@testable import DoyahCore

/// `AC-ALL-GATE-AI-001`：关闭智能体总开关后，**外发流量为 0**。
///
/// 判据怎么才算数（不是「看起来没发」）：
///   ① **在 `URLSession` 的边界上计量** —— 装一个 `URLProtocol` 记每一次真正开始加载的请求。
///      封条关着时它必须收到 **0** 条；同一套装置在封条松开时必须收到请求（正向对照），
///      否则「0 条」可能只是「那个 protocol 压根没装上」的假绿。
///   ② **逐条入口走一遍** —— 模型整段 / 模型流式 / 带外发日志的包装层 / 自然语言生成 SQL /
///      数据任务规格 / 网页搜索 / 网页抓取，封条关着时全部被拒，且底层计量器一次都没被调用。
///   ③ **清单判据** —— Core / App / CLI 里不许有人自己 `URLSession(...)` 另开一个出口；
///      有的话这一层的封条就绕得过去（真正要守住的是「所有智能体 HTTP 都走那两条运输」）。
///
/// 覆盖范围（**声明边界**，覆盖不到的按规矩记未知、不记通过）：
///   · ✅ 走到 `URLSessionTransport` / `URLSessionStreamingTransport` 的每一条智能体出网；
///   · ❌ 真抓包（`tcpdump` / 系统网络栈）未做 —— 这里量的是 URLSession 层；
///   · ❌ 平台层 IM socket（`URLSessionAgentIMQQClient`）与笔记云同步（`CloudAuth`）各自有开关，
///     不归本判据（它们是「通道 / 同步」的开关，不是智能体总开关）。
final class AgentEgressSealTests: XCTestCase {

    override func setUp() {
        super.setUp()
        AgentEgressSeal.shared.setOpen(false)
        CountingURLProtocol.reset()
    }

    override func tearDown() {
        AgentEgressSeal.shared.setOpen(false)
        CountingURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - 封条本体

    /// 默认必须是**关**：进程还没读到配置之前，「不发」是唯一安全的答案。
    func testSealIsClosedByDefault() {
        XCTAssertFalse(AgentEgressSeal().isOpen)
        XCTAssertFalse(AgentEgressSeal.shared.isOpen)
    }

    /// 配置是唯一真值源：`isEnabled` 一变，封条同批变。
    func testApplyingConfigurationMirrorsTheMasterSwitch() {
        let seal = AgentEgressSeal()
        seal.apply(AgentConfiguration(isEnabled: true, endpoint: "https://api.example.com/v1", model: "m"))
        XCTAssertTrue(seal.isOpen)
        seal.apply(AgentConfiguration(isEnabled: false, endpoint: "https://api.example.com/v1", model: "m"))
        XCTAssertFalse(seal.isOpen)
    }

    // MARK: - ① URLSession 边界计量

    /// 封条关着：整段那条路一个请求都不许开始加载；松开后同样的调用必须打出去（正向对照）。
    func testNonStreamingTransportStartsNoRequestWhileClosed() async throws {
        let session = makeCountingSession()
        let transport = URLSessionTransport(session: session)

        do {
            _ = try await transport.send(try OpenAICompatibleClient.makeURLRequest(makeRequest()))
            XCTFail("封条关着时不该有返回")
        } catch let error as LLMError {
            XCTAssertEqual(error, .disabled)
        }
        XCTAssertEqual(CountingURLProtocol.count, 0, "封条关着时 URLSession 收到 \(CountingURLProtocol.count) 条请求")

        AgentEgressSeal.shared.setOpen(true)
        let (data, response) = try await transport.send(try OpenAICompatibleClient.makeURLRequest(makeRequest()))
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertFalse(data.isEmpty)
        XCTAssertEqual(CountingURLProtocol.count, 1, "正向对照失败：计量装置没装上，前面那条 0 不能作数")
    }

    /// 流式那条路（聊天循环与「测试连接」的唯一出口）同样一字节不发。
    func testStreamingTransportStartsNoRequestWhileClosed() async throws {
        let session = makeCountingSession()
        let transport = URLSessionStreamingTransport(session: session)
        let request = try OpenAICompatibleClient.makeURLRequest(
            makeRequest(stream: true)
        )

        do {
            _ = try await transport.stream(request)
            XCTFail("封条关着时不该有返回")
        } catch let error as LLMError {
            XCTAssertEqual(error, .disabled)
        }
        XCTAssertEqual(CountingURLProtocol.count, 0)

        AgentEgressSeal.shared.setOpen(true)
        let (response, stream) = try await transport.stream(request)
        XCTAssertEqual(response.statusCode, 200)
        var bytes = 0
        for try await chunk in stream { bytes += chunk.count }
        XCTAssertGreaterThan(bytes, 0)
        XCTAssertEqual(CountingURLProtocol.count, 1, "正向对照失败")
    }

    // MARK: - ② 带外发日志的包装层：记 `denied`，不往下发

    func testRecordingTransportLogsDeniedAndNeverReachesTheNetwork() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentEgressSealTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = EgressLog(directoryURL: directory)
        let counted = CountingTransport(response: (Data("{}".utf8), makeHTTPResponse()))
        let wrapped = EgressRecordingTransport(
            origin: "判据 · 封条",
            wrapped: counted,
            log: log
        )

        do {
            _ = try await wrapped.send(makeURLRequest())
            XCTFail("封条关着时不该有返回")
        } catch let error as LLMError {
            XCTAssertEqual(error, .disabled)
        }

        XCTAssertEqual(counted.count, 0, "封条关着时底层运输被调用了 \(counted.count) 次")
        let entries = try await log.entries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.outcome, .denied, "被拦下的请求必须记 denied —— 记成 allowed 就是日志自己说谎")
        XCTAssertEqual(entries.first?.origin, "判据 · 封条")
    }

    // MARK: - ③ 逐条入口

    /// 每条智能体出网入口在封条关着时都必须被拦住，且底层计量器一次都没被碰过。
    func testEveryAgentEntryPointRefusesWhileClosed() async throws {
        let counted = CountingTransport(response: (Data("{}".utf8), makeHTTPResponse()))
        let countedClient = CountingClient()
        let configuration = AgentConfiguration(
            isEnabled: false,
            endpoint: "https://api.example.com/v1",
            model: "test-model"
        )

        // 自然语言 → SQL（闸门在客户端之前就判掉）。
        await assertRefused {
            try await AgentSQLGenerator.generate(
                request: .init(instruction: "查最近的订单", schema: .init()),
                configuration: configuration,
                apiKey: "sk-test",
                client: countedClient
            )
        }
        XCTAssertEqual(countedClient.count, 0)

        // 规格说明 → 数据任务定义。
        await assertRefused {
            try await DataTaskSpecGenerator.generate(
                request: .init(specs: "每天归档一次"),
                configuration: configuration,
                apiKey: "sk-test",
                client: countedClient
            )
        }
        XCTAssertEqual(countedClient.count, 0)

        // 直接构造模型的调用（编辑区辅助 / 连接测试那一层最终都落在这条路上）。
        // 走**真实运输**（App 里的装配就是 `URLSessionTransport`）—— 封条装在运输里，
        // 拿假运输来判会得到「没拦住」的假红（假运输本来就不归封条管）。
        CountingURLProtocol.reset()
        let client = OpenAICompatibleClient(
            transport: URLSessionTransport(session: makeCountingSession())
        )
        await assertThrowsDisabled { _ = try await client.complete(makeRequest()) }
        XCTAssertEqual(CountingURLProtocol.count, 0, "封条关着时 URLSession 收到 \(CountingURLProtocol.count) 条请求")

        // 网页工具（联网抓取）：生产装配用的也是 `URLSessionTransport` ⇒ 在同一个边界上计量。
        CountingURLProtocol.reset()
        let web = AgentWebTools(
            config: AgentWebSearchConfig(backend: .duckduckgo),
            transport: URLSessionTransport(session: makeCountingSession()),
            health: AgentWebBackendHealth(ttl: 0)
        )
        let search = await web.search(query: "swift", limit: 3)
        switch search {
        case .success: XCTFail("封条关着时不该搜出结果")
        case .failure(let failure): XCTAssertFalse(failure.message.isEmpty)
        }
        let fetch = await web.fetch(urlString: "https://example.com")
        switch fetch {
        case .success: XCTFail("封条关着时不该抓到页面")
        case .failure(let failure): XCTAssertFalse(failure.message.isEmpty)
        }

        XCTAssertEqual(CountingURLProtocol.count, 0, "封条关着时网页工具发了 \(CountingURLProtocol.count) 条请求")
    }

    // MARK: - ④ 清单判据：不许另开出口

    /// Core / App / CLI 里不许自己 `URLSession(...)`。真正的保证在**运输层收口**：
    /// 只要有人新开一条独立 URLSession，封条就绕得过去 —— 这条判据把那条路堵在源码上。
    func testNoAgentSourceOpensItsOwnURLSession() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        var offenders: [String] = []
        for folder in ["Core", "App", "CLI"] {
            let base = root.appendingPathComponent(folder)
            let enumerator = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil)
            while let url = enumerator?.nextObject() as? URL {
                guard url.pathExtension == "swift" else { continue }
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                for (index, line) in text.components(separatedBy: .newlines).enumerated() {
                    let code = line.trimmingCharacters(in: .whitespaces)
                    if code.hasPrefix("//") { continue }
                    guard code.contains("URLSession(") else { continue }
                    offenders.append("\(folder)/\(url.lastPathComponent):\(index + 1) \(code)")
                }
            }
        }
        XCTAssertEqual(offenders, [], "这些地方自己开了 URLSession，封条绕得过去：\n" + offenders.joined(separator: "\n"))
    }

    // MARK: - 装置

    private func makeRequest(stream: Bool = false) -> LLMRequest {
        LLMRequest(
            endpoint: URL(string: "https://api.example.com/v1")!,
            model: "test-model",
            apiKey: "sk-test",
            timeoutSeconds: 5,
            systemPrompt: "你是助手。",
            userPrompt: "回一句。",
            stream: stream
        )
    }

    private func makeURLRequest() -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.example.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        return request
    }

    private func makeHTTPResponse() -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://api.example.com/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
    }

    private func makeCountingSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CountingURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func assertRefused<T>(_ operation: () async throws -> T,
                                  file: StaticString = #filePath,
                                  line: UInt = #line) async {
        do {
            _ = try await operation()
            XCTFail("封条关着时不该有结果", file: file, line: line)
        } catch let error as LLMError {
            XCTAssertEqual(error, .disabled, file: file, line: line)
        } catch {
            XCTFail("应当以 .disabled 拒绝，实际是 \(error)", file: file, line: line)
        }
    }

    private func assertThrowsDisabled(_ operation: () async throws -> Void,
                                      file: StaticString = #filePath,
                                      line: UInt = #line) async {
        do {
            try await operation()
            XCTFail("封条关着时不该成功", file: file, line: line)
        } catch let error as LLMError {
            XCTAssertEqual(error, .disabled, file: file, line: line)
        } catch {
            XCTFail("应当以 .disabled 拒绝，实际是 \(error)", file: file, line: line)
        }
    }
}

// MARK: - 计量装置

/// 在 `URLSession` 上数「真正开始加载的请求」。
///
/// 为什么不用假 `HTTPTransport` 顶替：假运输只证明「调用方没调我」，证明不了
/// 「URLSession 没被碰」—— 而判据要的是后者（封条装在**运输里面**，不是调用方）。
final class CountingURLProtocol: URLProtocol {

    private static let lock = NSLock()
    private static var requests: [URLRequest] = []

    static var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return requests.count
    }

    static func reset() {
        lock.lock()
        requests = []
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        Self.lock.unlock()

        let body = Data("data: {\"choices\":[{\"delta\":{\"content\":\"ok\"}}]}\n\ndata: [DONE]\n\n".utf8)
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://api.example.com")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// 数「底层运输被调了几次」的假运输。
private struct CountingTransport: HTTPTransport {
    let response: (Data, HTTPURLResponse)
    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        var count: Int { lock.lock(); defer { lock.unlock() }; return value }
        func bump() { lock.lock(); value += 1; lock.unlock() }
    }
    private let counter = Counter()

    init(response: (Data, HTTPURLResponse)) {
        self.response = response
    }

    var count: Int { counter.count }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        counter.bump()
        return response
    }
}

/// 数「模型被调了几次」的假客户端。
private final class CountingClient: LLMClient, @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        lock.lock(); value += 1; lock.unlock()
        return LLMResponse(text: "{}")
    }
}
