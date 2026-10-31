//
//  AgentWebToolsTests.swift
//  DoyahCoreTests
//
//  联网工具的判据（详设 §3.27 `T-3.27-01` ~ `T-3.27-07`）。
//  全部用假传输 —— 单测不联网（`FR-STD-ALL-BLD-003` ④）。
//

import XCTest
@testable import DoyahCore

/// 假传输：把「发请求」换成固定回包，顺带把请求记下来供断言。
final class FakeWebTransport: HTTPTransport, @unchecked Sendable {

    var status: Int = 200
    var body: Data = Data()
    var headers: [String: String] = [:]
    private(set) var requests: [URLRequest] = []
    /// 模拟重定向落地：响应里的 URL 与请求不同（抓取边界要在落地后再校验一次）。
    var finalURL: URL?

    init(status: Int = 200, body: String = "", headers: [String: String] = [:]) {
        self.status = status
        self.body = Data(body.utf8)
        self.headers = headers
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let url = finalURL ?? request.url!
        let response = HTTPURLResponse(url: url, statusCode: status,
                                       httpVersion: "HTTP/1.1", headerFields: headers)!
        return (body, response)
    }
}

final class AgentWebToolsTests: XCTestCase {

    // MARK: - T-3.27-05：抓取边界（**负例必须判红**）

    func testFetchRefusesLoopbackPrivateAndFileURLs() async {
        for target in ["http://127.0.0.1/admin",
                       "http://10.0.0.5/",
                       "http://192.168.1.1/",
                       "http://172.20.0.1/",
                       "http://169.254.169.254/latest/meta-data/",
                       "http://localhost:8080/",
                       "http://printer.local/",
                       "file:///etc/passwd",
                       "http://[::1]/"] {
            guard let url = URL(string: target) else { return XCTFail("样例地址写错了：\(target)") }
            XCTAssertNotNil(AgentWebGuard.check(url), "\(target) 必须被判红")
        }
        // 正例：正常公网地址放行（否则上一条只证明「什么都拦」）
        XCTAssertNil(AgentWebGuard.check(URL(string: "https://example.com/a")!))
    }

    func testFetchBlocksRedirectThatLandsInsideTheNetwork() async {
        let transport = FakeWebTransport(status: 200, body: "<html><body>secret</body></html>",
                                         headers: ["Content-Type": "text/html"])
        transport.finalURL = URL(string: "http://127.0.0.1:9000/")!
        let tools = AgentWebTools(transport: transport, health: AgentWebBackendHealth(ttl: 300))

        switch await tools.fetch(urlString: "https://example.com/redirect") {
        case .success:
            XCTFail("重定向落到本机地址时必须拒 —— 跳板就是这么绕的")
        case .failure(let failure):
            if case .blocked = failure {} else { XCTFail("应当是 blocked，实际 \(failure)") }
        }
    }

    // MARK: - T-3.27-01：DDG 空配置可搜

    func testDuckDuckGoParsesRealHTMLShape() async {
        let html = """
        <div class="result">
          <a rel="nofollow" class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fswift.org%2F&amp;rut=abc">Swift.org</a>
          <a class="result__snippet" href="#">Swift 是一门通用编程语言</a>
        </div>
        <div class="result">
          <a rel="nofollow" class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fdeveloper.apple.com%2F&amp;rut=def">Apple Developer</a>
          <a class="result__snippet" href="#">文档与工具</a>
        </div>
        """
        let transport = FakeWebTransport(status: 200, body: html, headers: ["Content-Type": "text/html"])
        let tools = AgentWebTools(config: AgentWebSearchConfig(backend: .auto), transport: transport,
                                  health: AgentWebBackendHealth(ttl: 300))

        switch await tools.search(query: "swift", limit: 5) {
        case .success(let hits):
            XCTAssertEqual(hits.count, 2)
            XCTAssertEqual(hits[0].title, "Swift.org")
            XCTAssertEqual(hits[0].url, "https://swift.org/", "`uddg` 必须解回真实地址，不能留 DDG 的跳转壳")
            XCTAssertEqual(hits[0].snippet, "Swift 是一门通用编程语言")
            XCTAssertEqual(hits[1].url, "https://developer.apple.com/")
        case .failure(let failure):
            XCTFail("应当搜到，实际 \(failure)")
        }
        // 请求真的是 POST 到 html 端点、带表单体
        let request = try? XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request?.httpMethod, "POST")
        XCTAssertEqual(request?.url?.host, "html.duckduckgo.com")
        XCTAssertEqual(String(data: request?.httpBody ?? Data(), encoding: .utf8), "q=swift")
    }

    // MARK: - T-3.27-02 / 03：Tavily

    func testTavilyIsChosenOnlyWhenKeyIsPresent() {
        XCTAssertEqual(AgentWebSearchConfig(backend: .auto).resolved, .duckduckgo)
        XCTAssertEqual(AgentWebSearchConfig(backend: .auto, tavilyAPIKey: "tvly-x").resolved, .tavily)
        // 选了 Tavily 却没 key ⇒ 未配置（**不许**悄悄回落 DDG 让人以为在用付费后端）
        XCTAssertEqual(AgentWebSearchConfig(backend: .tavily).resolved, .none)
        XCTAssertEqual(AgentWebSearchConfig(backend: .tavily).displayName, "未配置")
    }

    func testTavilyUnauthorizedIsReportedAsAuthenticationFailure() async {
        let transport = FakeWebTransport(status: 401, body: #"{"error":"invalid api key"}"#)
        let tools = AgentWebTools(config: AgentWebSearchConfig(backend: .tavily, tavilyAPIKey: "bad"),
                                  transport: transport, health: AgentWebBackendHealth(ttl: 300))
        switch await tools.search(query: "x", limit: 3) {
        case .success:
            XCTFail("401 应当失败")
        case .failure(let failure):
            XCTAssertTrue(failure.message.contains("鉴权失败"), "要说是鉴权失败，不能写成「搜索失败」：\(failure.message)")
        }
    }

    func testTavilyMapsResults() async {
        let body = #"{"results":[{"title":"A","url":"https://a.example","content":"甲"},{"title":"B","url":"https://b.example","content":"乙"}]}"#
        let transport = FakeWebTransport(status: 200, body: body, headers: ["Content-Type": "application/json"])
        let tools = AgentWebTools(config: AgentWebSearchConfig(backend: .tavily, tavilyAPIKey: "tvly-ok"),
                                  transport: transport, health: AgentWebBackendHealth(ttl: 300))
        switch await tools.search(query: "q", limit: 5) {
        case .success(let hits):
            XCTAssertEqual(hits.map(\.url), ["https://a.example", "https://b.example"])
            XCTAssertEqual(hits.first?.snippet, "甲")
        case .failure(let failure):
            XCTFail("应当成功：\(failure)")
        }
    }

    // MARK: - T-3.27-04：零命中 ≠ 出错

    func testZeroHitsIsNoResultsNotAnError() async {
        let transport = FakeWebTransport(status: 200, body: "<html><body>no results</body></html>",
                                         headers: ["Content-Type": "text/html"])
        let tools = AgentWebTools(transport: transport, health: AgentWebBackendHealth(ttl: 300))
        switch await tools.search(query: "zzzz-not-found", limit: 5) {
        case .success:
            XCTFail("零命中不该走 success")
        case .failure(let failure):
            XCTAssertEqual(failure, .noResults)
            XCTAssertTrue(failure.message.contains("确实没有结果"))
        }
    }

    func testRateLimitedSaysSoInsteadOfNoResults() async {
        let transport = FakeWebTransport(status: 429, body: "")
        let tools = AgentWebTools(transport: transport, health: AgentWebBackendHealth(ttl: 300))
        switch await tools.search(query: "x", limit: 1) {
        case .success:
            XCTFail("429 应当失败")
        case .failure(let failure):
            XCTAssertNotEqual(failure, .noResults, "被限流不许说成「没有结果」")
            XCTAssertTrue(failure.message.contains("限流"))
        }
    }

    // MARK: - T-3.27-07：抓取结果与截断

    func testFetchConvertsHTMLToTextAndReportsTruncation() async {
        let html = "<html><head><style>p{color:red}</style><script>var x=1</script></head>"
            + "<body><h1>标题</h1><p>第一段</p><p>第二段</p></body></html>"
        let transport = FakeWebTransport(status: 200, body: html, headers: ["Content-Type": "text/html"])
        let tools = AgentWebTools(transport: transport, health: AgentWebBackendHealth(ttl: 300))

        switch await tools.fetch(urlString: "https://example.com/post") {
        case .success(let page):
            XCTAssertFalse(page.text.contains("var x=1"), "脚本不该进正文")
            XCTAssertFalse(page.text.contains("color:red"), "样式不该进正文")
            XCTAssertTrue(page.text.contains("标题"))
            XCTAssertTrue(page.text.contains("第二段"))
            XCTAssertFalse(page.truncated)
            XCTAssertEqual(page.finalURL.absoluteString, "https://example.com/post")
        case .failure(let failure):
            XCTFail("应当抓到：\(failure)")
        }
    }

    func testFetchRefusesNonTextContent() async {
        let transport = FakeWebTransport(status: 200, body: "PNG...",
                                         headers: ["Content-Type": "image/png"])
        let tools = AgentWebTools(transport: transport, health: AgentWebBackendHealth(ttl: 300))
        switch await tools.fetch(urlString: "https://example.com/a.png") {
        case .success:
            XCTFail("图片不该当正文抓回来")
        case .failure(let failure):
            if case .blocked = failure {} else { XCTFail("应当是 blocked，实际 \(failure)") }
        }
    }

    // MARK: - 注册表接线（注册 ≠ 可用）

    func testBothWebToolsAreRegisteredAndEnabled() {
        let registry = AgentToolRegistry.standard
        for name in ["web_search", "fetch_url"] {
            guard let definition = registry.definition(named: name) else {
                return XCTFail("\(name) 没登记")
            }
            XCTAssertTrue(definition.enabled, "\(name) 登记了但没启用 —— 等于没有（今天就是栽在这上面）")
        }
        XCTAssertEqual(registry.definition(named: "web_search")?.capability, .webSearch)
        XCTAssertEqual(registry.definition(named: "fetch_url")?.capability, .fetchURL)
    }
}

// MARK: - 国内可达的备用后端（`auto` 链）

final class AgentWebFallbackTests: XCTestCase {

    /// 传输替身：按 host 决定成败 —— 用来验「DDG 不通就换 Bing」。
    final class RoutingTransport: HTTPTransport, @unchecked Sendable {
        var calls: [String] = []
        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            let host = request.url?.host ?? ""
            calls.append(host)
            if host.contains("duckduckgo") {
                throw URLError(.timedOut)
            }
            let html = """
            <li class="b_algo"><h2><a href="https://www.swift.org/">Swift.org</a></h2>
            <p>Swift 是一门通用编程语言</p></li>
            """
            let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                           httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Type": "text/html"])!
            return (Data(html.utf8), response)
        }
    }

    func testAutoFallsBackToBingWhenDuckDuckGoIsUnreachable() async {
        let transport = RoutingTransport()
        let tools = AgentWebTools(config: AgentWebSearchConfig(backend: .auto), transport: transport,
                                  health: AgentWebBackendHealth(ttl: 300))
        switch await tools.search(query: "swift", limit: 3) {
        case .success(let hits):
            XCTAssertEqual(hits.first?.url, "https://www.swift.org/")
            XCTAssertEqual(transport.calls, ["html.duckduckgo.com", "cn.bing.com"], "先试 DDG、不通再换 Bing")
        case .failure(let failure):
            XCTFail("应当由 Bing 兜住：\(failure)")
        }
    }

    func testExplicitBackendIsNotSwappedSilently() async {
        let transport = RoutingTransport()
        let tools = AgentWebTools(config: AgentWebSearchConfig(backend: .duckduckgo), transport: transport,
                                  health: AgentWebBackendHealth(ttl: 300))
        switch await tools.search(query: "swift", limit: 3) {
        case .success:
            XCTFail("显式选了 DDG 就不许偷偷换 Bing")
        case .failure:
            XCTAssertEqual(transport.calls, ["html.duckduckgo.com"])
        }
    }
}

// MARK: - 熔断（不通就记住，别每次都等满 20 秒）

final class AgentWebCircuitBreakerTests: XCTestCase {

    func testDeadBackendIsSkippedOnTheNextCall() async {
        let transport = AgentWebFallbackTests.RoutingTransport()
        let health = AgentWebBackendHealth(ttl: 300)
        let tools = AgentWebTools(config: AgentWebSearchConfig(backend: .auto),
                                  transport: transport, health: health)

        _ = await tools.search(query: "first", limit: 3)
        XCTAssertEqual(transport.calls, ["html.duckduckgo.com", "cn.bing.com"])

        _ = await tools.search(query: "second", limit: 3)
        XCTAssertEqual(transport.calls, ["html.duckduckgo.com", "cn.bing.com", "cn.bing.com"],
                       "DDG 已被熔断 ⇒ 第二次不该再等它 20 秒")
    }
}

// MARK: - Bing 解析：属性顺序变了也要认

final class BingParserTests: XCTestCase {

    func testParsesBlocksRegardlessOfAttributeOrder() {
        let html = """
        <ol id="b_results">
          <li class="b_algo" data-id iid=SERP.5321>
            <h2><a href="https://www.swift.org/blog/">Swift Blog</a></h2>
            <p>Swift 官方博客</p>
          </li>
          <li class="b_algo" iid=SERP.5322 data-id>
            <h2><a href="https://www.swift.org/documentation/">Documentation</a></h2>
            <p>官方文档</p>
          </li>
        </ol>
        """
        let hits = BingParser.hits(in: html, limit: 5)
        XCTAssertEqual(hits.count, 2, "属性顺序不同不该让整页变 0 命中")
        XCTAssertEqual(hits.first?.url, "https://www.swift.org/blog/")
        XCTAssertEqual(hits[1].title, "Documentation")
    }

    func testEmptyResultsPageIsNotMistakenForResults() {
        let hits = BingParser.hits(in: "<ol id=\"b_results\"></ol>", limit: 5)
        XCTAssertTrue(hits.isEmpty)
    }
}
