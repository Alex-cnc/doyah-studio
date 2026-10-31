//
//  AgentWebTools.swift
//  DoyahCore
//
//  联网工具的实现面（详设 §3.27）：`web_search` 与 `fetch_url`。
//
//  三件事在这里定死，视图与循环都不许另说：
//  ① **后端可配**：DuckDuckGo HTML（免 key，默认）/ Tavily（填 key 启用）；`auto` = 有 key 走 Tavily。
//  ② **失败三态分开**：`notConfigured` / `unavailable(原因)` / `noResults` —— 「没配后端」「被限流或网络不通」
//     「通但零命中」是三句不同的话。混成一句「没找到」会让模型以为世上没有这东西，然后开始编。
//  ③ **抓取边界**（`NFR-AGT-TOOL-INGEST-001`）：只许 `http(s)`，拒环回 / 私网 / 链路本地 / `.local`，
//     20 秒超时，响应体 2 MB 封顶，重定向落地后**再校验一次**（跳板常这么绕）。
//

import Foundation

// MARK: - 失败形态

/// 联网失败的三种说法（`FR-AGT-TOOL-INGEST-004` ③ 要求分开说）。
public enum AgentWebFailure: Error, Equatable, Sendable {
    /// 没配后端（当前不该出现：DDG 是内置默认；留给「用户显式关掉全部后端」）
    case notConfigured
    /// 配了但用不了：限流 / 网络不通 / 鉴权失败 —— **带原始原因**
    case unavailable(String)
    /// 抓取边界拦下（SSRF、非 http(s)、体量超限…）
    case blocked(String)
    /// 通了，但确实零命中
    case noResults

    /// 给人和模型看的读数（审计与回灌共用一处，免得两处口径漂）。
    public var message: String {
        switch self {
        case .notConfigured:
            return "检索不可用：还没有配置检索后端（设置 → 智能体 → 联网检索）"
        case .unavailable(let reason):
            return "检索不可用：\(reason)"
        case .blocked(let reason):
            return "抓取被拒：\(reason)"
        case .noResults:
            return "检索通了，但确实没有结果"
        }
    }
}

// MARK: - 命中

public struct AgentWebHit: Equatable, Sendable {
    public var title: String
    public var url: String
    public var snippet: String

    public init(title: String, url: String, snippet: String) {
        self.title = title
        self.url = url
        self.snippet = snippet
    }
}

// MARK: - 配置

public struct AgentWebSearchConfig: Equatable, Sendable {

    public enum Backend: String, Codable, Equatable, Sendable, CaseIterable {
        /// 有 Tavily key 走 Tavily，否则走 DDG
        case auto
        case duckduckgo
        /// 国内可达的内置后端（DDG 在境内常常整个域名不通；Bing 走 `cn.bing.com` 能出结果）
        case bing
        case tavily
    }

    public var backend: Backend
    /// Tavily 的 API key。**永不进日志、不进审计、不回显**（`FR-AGT-TOOL-INGEST-004`「不做」栏）。
    public var tavilyAPIKey: String?

    public init(backend: Backend = .auto, tavilyAPIKey: String? = nil) {
        self.backend = backend
        self.tavilyAPIKey = tavilyAPIKey
    }

    /// 配置解析后的实际后端（**不是可选值**：`none` 本身是一档，`switch` 才不会漏分支）。
    public enum Resolved: Equatable, Sendable {
        case duckduckgo
        case bing
        case tavily
        /// 选了 Tavily 却没填 key ⇒ 就是「没配」，不许悄悄换成别的后端
        case none
    }

    /// 这个配置下真正用哪个后端。`auto` 的判据只看「有没有 key」，不看网络（网络好不好是运行期的事）。
    public var resolved: Resolved {
        switch backend {
        case .auto:
            return (tavilyAPIKey?.isEmpty == false) ? .tavily : .duckduckgo
        case .tavily:
            return (tavilyAPIKey?.isEmpty == false) ? .tavily : .none
        case .duckduckgo:
            return .duckduckgo
        case .bing:
            return .bing
        }
    }

    /// 设置面板上那一行「当前后端」的读数。
    public var displayName: String {
        switch resolved {
        case .tavily: return "Tavily"
        case .duckduckgo: return backend == .auto ? "DuckDuckGo → Bing（自动）" : "DuckDuckGo（内置）"
        case .bing: return "Bing 国内（内置）"
        case .none: return "未配置"
        }
    }
}

// MARK: - 抓取边界

public enum AgentWebGuard {

    /// 允许的协议：只有这两个。`file:` / `data:` / `javascript:` 一律不进网络层。
    static let allowedSchemes: Set<String> = ["http", "https"]

    /// 拦下就返回原因，放行返回 nil。
    public static func check(_ url: URL) -> AgentWebFailure? {
        guard let scheme = url.scheme?.lowercased(), allowedSchemes.contains(scheme) else {
            return .blocked("只允许 http / https（收到的是 \(url.scheme ?? "空")）")
        }
        guard let host = url.host?.lowercased(), !host.isEmpty else {
            return .blocked("地址里没有主机名")
        }
        if let reason = blockedHostReason(host) { return .blocked(reason) }
        return nil
    }

    /// 主机名/IP 层面的黑名单。**只做网络层判断**：不解析 DNS 之后再拦转发地址（那是另一层的事），
    /// 所以这里把常见的私网字面量与 `.local` 直接挡住，够用且可单测。
    public static func blockedHostReason(_ host: String) -> String? {
        var name = host
        if name.hasPrefix("["), name.hasSuffix("]") { name = String(name.dropFirst().dropLast()) }  // [::1]
        if name == "localhost" { return "本机地址不允许抓取" }
        if name.hasSuffix(".local") { return "局域网域名不允许抓取" }
        if name.contains(":") {   // IPv6
            let lower = name.lowercased()
            if lower == "::1" || lower == "::" { return "本机地址不允许抓取" }
            if lower.hasPrefix("fe80") { return "链路本地地址不允许抓取" }
            if lower.hasPrefix("fc") || lower.hasPrefix("fd") { return "内网地址不允许抓取" }
            return nil
        }
        let parts = name.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, name.split(separator: ".").count == 4 else { return nil }  // 不是 IPv4
        let (a, b) = (parts[0], parts[1])
        if a == 127 { return "本机地址不允许抓取" }
        if a == 10 { return "内网地址不允许抓取" }
        if a == 172, (16...31).contains(b) { return "内网地址不允许抓取" }
        if a == 192, b == 168 { return "内网地址不允许抓取" }
        if a == 169, b == 254 { return "链路本地地址不允许抓取" }
        if a == 0 { return "非法地址" }
        return nil
    }
}

// MARK: - 后端

public protocol AgentWebSearchBackend: Sendable {
    var name: String { get }
    func search(query: String, limit: Int) async throws -> [AgentWebHit]
}

/// 内置默认：DuckDuckGo 的 HTML 端点。免 key、开箱可用；代价是被限流时会返回 429 或空页。
public struct DuckDuckGoBackend: AgentWebSearchBackend {

    private let transport: any HTTPTransport
    public let name = "DuckDuckGo"

    public init(transport: any HTTPTransport) {
        self.transport = transport
    }

    public func search(query: String, limit: Int) async throws -> [AgentWebHit] {
        var request = URLRequest(url: URL(string: "https://html.duckduckgo.com/html/")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/x-www-form-urlencoded; charset=utf-8",
                         forHTTPHeaderField: "Content-Type")
        request.setValue("DoyahStudio/1.0", forHTTPHeaderField: "User-Agent")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) ?? query
        request.httpBody = Data("q=\(encoded)".utf8)

        let (data, response) = try await transport.send(request)
        if response.statusCode == 429 {
            throw AgentWebBackendError.rateLimited
        }
        guard (200...299).contains(response.statusCode) else {
            throw AgentWebBackendError.httpStatus(response.statusCode)
        }
        let html = String(decoding: data, as: UTF8.self)
        return DuckDuckGoParser.hits(in: html, limit: limit)
    }
}

/// 内置备用：`cn.bing.com`。**为什么需要它**：2026-10-31 在这台机器上实测，
/// `duckduckgo.com` 与 `api.tavily.com` 都整个域名不通（`curl` 12 秒超时），只有 `cn.bing.com` 回 200。
/// 一个在国内用不了的默认后端等于没有后端。
public struct BingBackend: AgentWebSearchBackend {

    private let transport: any HTTPTransport
    public let name = "Bing"

    public init(transport: any HTTPTransport) {
        self.transport = transport
    }

    public func search(query: String, limit: Int) async throws -> [AgentWebHit] {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) ?? query
        let urlString = "https://cn.bing.com/search?q=\(encoded)&count=\(max(limit, 10))&setlang=zh-Hans"
        guard let url = URL(string: urlString) else { throw AgentWebBackendError.malformed }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        // Bing 对「非浏览器 UA」会回一个没有结果的页（实测 `DoyahStudio/1.0` 只有 0 条 `b_algo`）。
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
                         + "(KHTML, like Gecko) Version/17.0 Safari/605.1.15",
                         forHTTPHeaderField: "User-Agent")
        request.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await transport.send(request)
        if response.statusCode == 429 { throw AgentWebBackendError.rateLimited }
        guard (200...299).contains(response.statusCode) else {
            throw AgentWebBackendError.httpStatus(response.statusCode)
        }
        let html = String(decoding: data, as: UTF8.self)
        let hits = BingParser.hits(in: html, limit: limit)
        if hits.isEmpty {
            // 零命中要分清楚：**真的没结果**，还是**拿回来的根本不是结果页**（风控 / 验证 / 区域跳转）。
            // 这两种情况给模型的话不一样，日志里也得留证据（否则以后只会看到一句「没有结果」）。
            let isResultsPage = html.contains("b_results")
            throw isResultsPage
                ? AgentWebBackendError.emptyPage("页面 \(html.count) 字节，含 b_results 但没有一个可解析的结果块；开头：\(html.prefix(160))")
                : AgentWebBackendError.notAResultsPage(String(html.prefix(120)))
        }
        return hits
    }
}

/// Bing 结果页的解析（`<li class="b_algo">` 块；独立出来才好喂固定 HTML 单测）。
public enum BingParser {

    public static func hits(in html: String, limit: Int) -> [AgentWebHit] {
        var out: [AgentWebHit] = []
        // **按 `b_algo` 切块，不依赖属性顺序**：Bing 的 `<li>` 属性会变（`class` / `data-id` / `iid=…`），
        // 早先按 `<li class="b_algo"` 精确切，换个属性顺序就整页 0 命中（2026-10-31 现场踩到）。
        let blocks = blocks(in: html)
        for block in blocks {
            guard let href = firstMatch(#"href="(https?://[^"]+)""#, in: block) else { continue }
            let titleHTML = firstMatch(#"<h2[^>]*>(.*?)</h2>"#, in: block) ?? ""
            let snippetHTML = firstMatch(#"<p[^>]*>(.*?)</p>"#, in: block) ?? ""
            let title = DuckDuckGoParser.stripTags(titleHTML)
            guard !title.isEmpty || !snippetHTML.isEmpty else { continue }
            out.append(AgentWebHit(title: title.isEmpty ? href : title,
                                   url: DuckDuckGoParser.decodeEntities(href),
                                   snippet: DuckDuckGoParser.stripTags(snippetHTML)))
            if out.count >= limit { break }
        }
        return out
    }

    /// 把页面切成一个个结果块：从每处 `b_algo` 起，到下一处 `b_algo` 止。
    static func blocks(in html: String) -> [String] {
        let marker = "b_algo"
        var ranges: [Range<String.Index>] = []
        var searchStart = html.startIndex
        while let found = html.range(of: marker, range: searchStart..<html.endIndex) {
            ranges.append(found.lowerBound..<html.endIndex)
            searchStart = found.upperBound
        }
        guard !ranges.isEmpty else { return [] }
        var out: [String] = []
        for (index, range) in ranges.enumerated() {
            let end = index + 1 < ranges.count ? ranges[index + 1].lowerBound : html.endIndex
            let block = String(html[range.lowerBound..<end])
            out.append(block.count > 6000 ? String(block.prefix(6000)) : block)
        }
        return out
    }

    static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern,
                                                   options: [.dotMatchesLineSeparators, .caseInsensitive])
        else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let r = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }
}

/// 可选后端：Tavily。质量稳、有配额、要 key。
public struct TavilyBackend: AgentWebSearchBackend {

    private let transport: any HTTPTransport
    private let apiKey: String
    public let name = "Tavily"

    public init(transport: any HTTPTransport, apiKey: String) {
        self.transport = transport
        self.apiKey = apiKey
    }

    public func search(query: String, limit: Int) async throws -> [AgentWebHit] {
        var request = URLRequest(url: URL(string: "https://api.tavily.com/search")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("DoyahStudio/1.0", forHTTPHeaderField: "User-Agent")
        let body: [String: Any] = ["api_key": apiKey,
                                   "query": query,
                                   "max_results": limit,
                                   "search_depth": "basic",
                                   "include_answer": false]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await transport.send(request)
        if response.statusCode == 401 || response.statusCode == 403 {
            throw AgentWebBackendError.unauthorized
        }
        if response.statusCode == 429 { throw AgentWebBackendError.rateLimited }
        guard (200...299).contains(response.statusCode) else {
            throw AgentWebBackendError.httpStatus(response.statusCode)
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = root["results"] as? [[String: Any]] else {
            throw AgentWebBackendError.malformed
        }
        return results.prefix(limit).compactMap { item in
            guard let url = item["url"] as? String, !url.isEmpty else { return nil }
            return AgentWebHit(title: (item["title"] as? String) ?? url,
                               url: url,
                               snippet: (item["content"] as? String) ?? "")
        }
    }
}

public enum AgentWebBackendError: Error, Equatable, Sendable {
    case rateLimited
    case unauthorized
    case httpStatus(Int)
    case malformed
    /// 拿到的是结果页，但这一页确实没有结果
    case emptyPage(String)
    /// 拿回来的压根不是结果页（风控 / 验证 / 区域跳转）
    case notAResultsPage(String)

    /// 翻成人话 —— 「被限流」「鉴权失败」「服务器 500」是三件事，不许都写成「搜索失败」。
    public var readable: String {
        switch self {
        case .rateLimited: return "被限流（429），稍后再试"
        case .unauthorized: return "Tavily 鉴权失败：key 无效或已过期"
        case .httpStatus(let code): return "服务返回 HTTP \(code)"
        case .malformed: return "返回内容无法解析"
        case .emptyPage(let detail): return "返回了结果页但没有可解析的条目（\(detail)）"
        case .notAResultsPage(let head): return "返回的不是结果页（可能被风控）：\(head)"
        }
    }
}

/// DDG HTML 的解析（独立出来是为了能喂一段固定 HTML 单测，不联网）。
public enum DuckDuckGoParser {

    public static func hits(in html: String, limit: Int) -> [AgentWebHit] {
        let pattern = #"<a[^>]*class="[^"]*result__a[^"]*"[^>]*href="([^"]+)"[^>]*>(.*?)</a>"#
        let snippetPattern = #"class="[^"]*result__snippet[^"]*"[^>]*>(.*?)</a>"#
        let titles = matches(pattern: pattern, in: html)
        let snippets = matches(pattern: snippetPattern, in: html)
        var out: [AgentWebHit] = []
        for (index, pair) in titles.prefix(limit).enumerated() {
            guard let url = realURL(from: pair[0]) else { continue }
            let title = stripTags(pair[1])
            let snippet = index < snippets.count ? stripTags(snippets[index][0]) : ""
            out.append(AgentWebHit(title: title.isEmpty ? url : title, url: url, snippet: snippet))
        }
        return out
    }

    /// DDG 的结果链接是 `//duckduckgo.com/l/?uddg=<真实地址>&rut=…`，要解回真实地址。
    static func realURL(from href: String) -> String? {
        var text = decodeEntities(href)
        if text.hasPrefix("//") { text = "https:" + text }
        guard let comps = URLComponents(string: text) else { return nil }
        if let target = comps.queryItems?.first(where: { $0.name == "uddg" })?.value,
           let decoded = target.removingPercentEncoding {
            return decoded
        }
        return text
    }

    static func matches(pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern,
                                                   options: [.dotMatchesLineSeparators, .caseInsensitive]) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).map { match in
            (1..<match.numberOfRanges).map { index in
                guard let r = Range(match.range(at: index), in: text) else { return "" }
                return String(text[r])
            }
        }
    }

    static func stripTags(_ text: String) -> String {
        let noTags = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return decodeEntities(noTags)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func decodeEntities(_ text: String) -> String {
        var out = text
        let table = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
                     "&#39;": "'", "&apos;": "'", "&nbsp;": " "]
        for (entity, value) in table { out = out.replacingOccurrences(of: entity, with: value) }
        return out
    }
}

// MARK: - 抓取

public enum AgentWebFetcher {

    public static let maxBytes = 2_000_000
    public static let timeout: TimeInterval = 20

    /// 抓一个页面并转成纯文本。**每一条边界都在这里**（详设 §3.27「抓取边界」）。
    public static func fetch(urlString: String,
                             transport: any HTTPTransport,
                             maxBytes: Int = AgentWebFetcher.maxBytes) async throws -> AgentWebPage {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw AgentWebBackendError.malformed
        }
        if let refusal = AgentWebGuard.check(url) { throw AgentWebFetchError.blocked(refusal) }

        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue("DoyahStudio/1.0", forHTTPHeaderField: "User-Agent")
        // 不带 Cookie、不带凭据、不带 Referer —— 抓取不是浏览器会话。
        let (data, response) = try await transport.send(request)

        // 重定向落地后再校验一次：跳板常把内网地址放在第二跳。
        if let finalURL = response.url, finalURL != url,
           let refusal = AgentWebGuard.check(finalURL) {
            throw AgentWebFetchError.blocked(refusal)
        }
        guard (200...299).contains(response.statusCode) else {
            throw AgentWebBackendError.httpStatus(response.statusCode)
        }
        let mime = response.value(forHTTPHeaderField: "Content-Type") ?? ""
        guard mime.isEmpty || mime.contains("text") || mime.contains("json")
                || mime.contains("xml") || mime.contains("html") else {
            throw AgentWebFetchError.unsupportedType(mime)
        }

        let total = data.count
        let slice = data.prefix(maxBytes)
        let raw = String(decoding: slice, as: UTF8.self)
        let text = (mime.contains("html") || raw.contains("<html") || raw.contains("<!DOCTYPE"))
            ? htmlToText(raw)
            : raw
        return AgentWebPage(finalURL: response.url ?? url,
                            text: text,
                            totalBytes: total,
                            truncated: total > maxBytes)
    }

    /// HTML → 纯文本：去脚本样式、去标签、解实体、压空白。够用就行 —— 不做完整 DOM 树。
    public static func htmlToText(_ html: String) -> String {
        var text = html
        for tag in ["script", "style", "noscript", "svg"] {
            text = text.replacingOccurrences(of: "<\(tag)[^>]*>.*?</\(tag)>",
                                             with: " ",
                                             options: [.regularExpression, .caseInsensitive])
        }
        text = text.replacingOccurrences(of: "<br[^>]*>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "</(p|div|li|h[1-6]|tr)>", with: "\n",
                                         options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        text = DuckDuckGoParser.decodeEntities(text)
        text = text.replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum AgentWebFetchError: Error, Equatable, Sendable {
    case blocked(AgentWebFailure)
    case unsupportedType(String)
}

public struct AgentWebPage: Equatable, Sendable {
    public var finalURL: URL
    public var text: String
    public var totalBytes: Int
    public var truncated: Bool

    public init(finalURL: URL, text: String, totalBytes: Int, truncated: Bool) {
        self.finalURL = finalURL
        self.text = text
        self.totalBytes = totalBytes
        self.truncated = truncated
    }
}

// MARK: - 后端健康（熔断）

/// 记住「这个后端刚才压根不通」，在 TTL 内不再浪费一次 20 秒超时。
///
/// 由头：2026-10-31 实测 —— 境内 DDG 每次都要等满 20 秒超时才换 Bing，
/// 一次搜索 21 秒；连着问三句就是一分多钟白等。**不通要记住，不是每次都重新撞墙**。
public actor AgentWebBackendHealth {

    public static let shared = AgentWebBackendHealth(ttl: 300)
    private let ttl: TimeInterval
    private var downUntil: [String: Date] = [:]

    public init(ttl: TimeInterval) { self.ttl = ttl }

    public func markDown(_ name: String, now: Date = Date()) { downUntil[name] = now.addingTimeInterval(ttl) }
    public func isDown(_ name: String, now: Date = Date()) -> Bool {
        guard let until = downUntil[name] else { return false }
        if until <= now { downUntil[name] = nil; return false }
        return true
    }
    public func reset() { downUntil.removeAll() }
}

// MARK: - 门面

/// 一个 `web_search` 调用要的全部依赖：配置 + 传输 + （可选的）审计口。
public struct AgentWebTools: Sendable {

    public var config: AgentWebSearchConfig
    public var transport: any HTTPTransport
    /// 后端健康台账（熔断用）；单测可注入一个干净的。
    public var health: AgentWebBackendHealth

    public init(config: AgentWebSearchConfig = AgentWebSearchConfig(),
                transport: any HTTPTransport = URLSessionTransport(),
                health: AgentWebBackendHealth = .shared) {
        self.config = config
        self.transport = transport
        self.health = health
    }

    public func search(query: String, limit: Int) async -> Result<[AgentWebHit], AgentWebFailure> {
        let cap = max(1, min(limit, 10))
        // `auto` = 先 DDG，网络不通就换 Bing（**只在「这个后端压根用不了」时换**；
        // 「通了但零命中」「Tavily 鉴权失败」都不换 —— 换了就成了骗人）。
        var reasons: [String] = []
        var alive: [any AgentWebSearchBackend] = []
        for backend in backends() {
            if await health.isDown(backend.name) {
                reasons.append("\(backend.name)：刚才不通，已跳过（5 分钟内不再试）")
                continue
            }
            alive.append(backend)
        }
        // 全都在熔断里 ⇒ 直接把原因说清楚，不再挨个撞墙。
        if alive.isEmpty { return .failure(.unavailable(reasons.joined(separator: "；"))) }
        for backend in alive {
            do {
                let hits = try await backend.search(query: query, limit: cap)
                return hits.isEmpty ? .failure(.noResults) : .success(hits)
            } catch let error as AgentWebBackendError {
                if case .emptyPage(let detail) = error { return .failure(.unavailable(detail)) }
                reasons.append("\(backend.name)：\(error.readable)")
                if error == .unauthorized || error == .rateLimited { break }   // 鉴权 / 限流不换后端
            } catch {
                reasons.append("\(backend.name)：\(error.localizedDescription)")
                // 网络层拿不到回应（超时 / 连不上）⇒ 熔断；解析失败之类的偶发错误不熔断。
                if (error as? URLError) != nil {
                    await health.markDown(backend.name)
                }
            }
        }
        if reasons.isEmpty { return .failure(.notConfigured) }
        return .failure(.unavailable(reasons.joined(separator: "；")))
    }

    public func fetch(urlString: String) async -> Result<AgentWebPage, AgentWebFailure> {
        do {
            return .success(try await AgentWebFetcher.fetch(urlString: urlString, transport: transport))
        } catch let error as AgentWebFetchError {
            switch error {
            case .blocked(let failure): return .failure(failure)
            case .unsupportedType(let mime): return .failure(.blocked("这类内容不抓：\(mime)"))
            }
        } catch let error as AgentWebBackendError {
            return .failure(.unavailable(error.readable))
        } catch {
            return .failure(.unavailable(error.localizedDescription))
        }
    }

    public func resolvedBackend() -> (any AgentWebSearchBackend)? {
        backends().first
    }

    /// 这次调用**按顺序**要试的后端。`auto` 是 [DDG, Bing]；显式选了谁就只有谁。
    public func backends() -> [any AgentWebSearchBackend] {
        // **按用户选的档位展开**（不是按解析结果）：`auto` 本身是一条链 [DDG, Bing]，
        // 而 `resolved` 只用于面板上那句话。两者混用会让 auto 悄悄退化成单后端。
        switch config.backend {
        case .auto:
            if let key = config.tavilyAPIKey, !key.isEmpty {
                return [TavilyBackend(transport: transport, apiKey: key)]
            }
            return [DuckDuckGoBackend(transport: transport), BingBackend(transport: transport)]
        default:
            break
        }
        switch config.resolved {
        case .duckduckgo:
            return [DuckDuckGoBackend(transport: transport)]
        case .bing:
            return [BingBackend(transport: transport)]
        case .tavily:
            guard let key = config.tavilyAPIKey, !key.isEmpty else { return [] }
            return [TavilyBackend(transport: transport, apiKey: key)]
        case .none:
            return []
        }
    }
}
