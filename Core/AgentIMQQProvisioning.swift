import Foundation

/// QQ 通道的**凭据口径**（`FR-AGT-LINK-CHAN-003` ★0，2026-10-28 主人拍板）。
///
/// 主人的原话：「既然指明了是 QQ 通道，为什么还要用户填 wss 地址？按道理只要 QQ 扫码或者输入机器人
/// AppID 和 AppSecret 就可以啊。」⇒ 从本片起**地址由程序自己取**，用户只给三样：
/// AppID + App Secret + 环境（正式 / 沙箱）。
///
/// 链条（全在本文件，一处实现，面板不再问地址）：
/// `POST bots.qq.com/app/getAppAccessToken` 取 `access_token`
/// → `GET api.sgroup.qq.com/gateway` 取 `wss` 地址（取不到用官方常量）
/// → Identify `op=2` 带 `token = "QQBot <access_token>"` → 心跳 `op=1` → 断线 `op=6` 恢复
/// → **到期前刷新** token。
public enum AgentIMQQEnvironment: String, Codable, CaseIterable, Equatable, Sendable {

    case production
    case sandbox

    /// 取 access_token 的端点：两个环境同一个（官方口径）。
    public var tokenEndpoint: URL {
        Self.constant("https://bots.qq.com/app/getAppAccessToken")
    }

    /// REST 基址（取网关地址、发消息都在这条域下）。
    public var apiBase: URL {
        switch self {
        case .production: return Self.constant("https://api.sgroup.qq.com")
        case .sandbox: return Self.constant("https://sandbox.api.sgroup.qq.com")
        }
    }

    /// 取 `wss` 地址的那一格。
    public var gatewayEndpoint: URL {
        apiBase.appendingPathComponent("gateway")
    }

    /// REST 取不到网关地址时用的**固定地址**（官方文档给的常量；每个环境各一条）。
    /// 取不到还用常量，是为了「网络抖一下就连不上」不至于变成「配置错」。
    public var websocketFallback: URL {
        switch self {
        case .production: return Self.constant("wss://api.sgroup.qq.com/websocket/")
        case .sandbox: return Self.constant("wss://sandbox.api.sgroup.qq.com/websocket/")
        }
    }

    /// 认不出就给空值：盘上被手改成别的词时当「没选」，不默认成正式（选错 = 消息一条都不来，
    /// 而面板会显示「已连接」）。
    public static func of(raw: String?) -> AgentIMQQEnvironment? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return AgentIMQQEnvironment(rawValue: trimmed)
    }

    /// 常量 URL（字面量写错 = 代码写错，不是用户输入问题）。
    static func constant(_ text: String) -> URL {
        guard let url = URL(string: text) else {
            preconditionFailure("写死的常量 URL 认不出：\(text)")
        }
        return url
    }
}

/// 一次 HTTP 往返的读数（**只留状态与正文**，不留请求头 —— token 不许跟着日志走）。
public struct AgentIMHTTPResponse: Equatable, Sendable {

    public var status: Int
    public var body: String

    public init(status: Int, body: String) {
        self.status = status
        self.body = body
    }

    public var isSuccess: Bool { (200..<300).contains(status) }
}

/// 出网的那一层（真实现走 `URLSession`，判据用假的一根根喂 —— 判据不碰网络）。
public protocol AgentIMQQHTTPClient: Sendable {
    func post(_ url: URL, json body: [String: String], headers: [String: String]) async throws -> AgentIMHTTPResponse
    func get(_ url: URL, headers: [String: String]) async throws -> AgentIMHTTPResponse
}

/// 取 token / 取网关 / 刷新的失败原因（机器码；人话在 `AgentIMQQProvisionText`）。
///
/// 为什么带 `rejected(status:code:)` 这一档：QQ 侧返回 4xx 时正文里常有**它自己的**错误码。
/// 认识的（401 / 403 / 429 / 5xx）给可读原因；**不认识的把状态与码原样带出去** —— 编一句
/// 「网络错误」比贴码更误导（同 `AgentIMStatusText.reasonLine` 的口径）。
public enum AgentIMQQProvisionProblem: Error, Equatable, Sendable {
    case environmentMissing
    case appIDMissing
    case secretMissing
    /// 连不上 / 超时 / TLS（这一层分不出是哪一种，如实说「没连上」）。
    case networkFailed
    /// 2xx 了但正文不是 JSON（多半是被网关/代理拦回来一页 HTML）。
    case responseNotJSON
    /// 401：AppID 或 Secret 不对。
    case credentialsRejected
    /// 403：凭据对，但这个机器人没有权限（没开消息权限 / 没被拉进目标群）。
    case permissionDenied
    case rateLimited
    case serverFailed
    /// 2xx 了但没有 `access_token` 字段。
    case tokenMissing
    /// 其余非 2xx：状态与它给的码原样带出去（不替它编原因）。
    case rejected(status: Int, code: String?)

    /// 判据用：每一种都要有中英两句（带值的那一档取一个样本）。
    public static let textSamples: [AgentIMQQProvisionProblem] = [
        .environmentMissing, .appIDMissing, .secretMissing, .networkFailed, .responseNotJSON,
        .credentialsRejected, .permissionDenied, .rateLimited, .serverFailed,
        .tokenMissing, .rejected(status: 418, code: "100016"),
    ]
}

/// 一把 `access_token`（**只在内存里**：过期即换，绝不落盘、绝不打进日志/面板）。
public struct AgentIMQQToken: Equatable, Sendable {

    /// 原始 token（只在内存与请求头里出现；界面只许显示 `redactedPreview`）。
    public let value: String
    /// 官方给的寿命（秒；缺省按 7200 —— 这是官方文档的量级，取不到就按它保守估）。
    public let expiresIn: TimeInterval
    public let obtainedAt: Date

    public init(value: String, expiresIn: TimeInterval = 7200, obtainedAt: Date) {
        self.value = value
        self.expiresIn = max(1, expiresIn)
        self.obtainedAt = obtainedAt
    }

    public var expiresAt: Date { obtainedAt.addingTimeInterval(expiresIn) }

    /// 提前多久换：取「寿命的 20%」与 60 秒的较大者。
    /// 7200 秒 ⇒ 提前 24 分钟换（不是等它过期那一刻才换：过期后再换，那一跳的握手一定失败）。
    public func refreshLeadTime(minimum: TimeInterval = 60) -> TimeInterval {
        max(minimum, expiresIn * 0.2)
    }

    /// 要不要换（到期前 `refreshLeadTime` 之内就算要换）。
    public func needsRefresh(now: Date) -> Bool {
        now.addingTimeInterval(refreshLeadTime()) >= expiresAt
    }

    /// 握手 / REST 用的那个头（官方口径：`QQBot <access_token>`）。
    public var authorizationHeaders: [String: String] {
        [AgentIMQQHandshake.authorizationHeaderName: "QQBot \(value)"]
    }

    /// 面板能显示的那一小段：只有尾 4 位。
    public var redactedPreview: String {
        guard value.count > 4 else { return String(repeating: "*", count: max(1, value.count)) }
        return "…" + value.suffix(4)
    }
}

/// 网关地址是从哪来的（**取到的**与**用常量兜底的**、以及**用户自建中继**，面板要说不同的话）。
public struct AgentIMQQGatewayResolution: Equatable, Sendable {

    public enum Source: String, Equatable, Sendable {
        /// `GET /gateway` 真的取到了。
        case discovered
        /// REST 取不到 ⇒ 用该环境的固定地址（连接可能仍通，但要说清这一档）。
        case fallback
        /// 用户在「高级」里填了自建中继地址（不问官方网关）。
        case relay
    }

    public var url: URL
    public var source: Source
    /// 兜底时的原因码（`networkFailed` / `responseNotJSON` / `rejected(418)` …）。
    public var note: String?

    public init(url: URL, source: Source, note: String? = nil) {
        self.url = url
        self.source = source
        self.note = note
    }
}

/// 一次「准备连接」的全部产物（token + 地址），`AppState` 拿它去建传输层。
public struct AgentIMQQProvisioning: Equatable, Sendable {
    public var token: AgentIMQQToken
    public var gateway: AgentIMQQGatewayResolution
    public init(token: AgentIMQQToken, gateway: AgentIMQQGatewayResolution) {
        self.token = token
        self.gateway = gateway
    }
}

/// 取 token → 取地址 的唯一实现处。
public struct AgentIMQQProvisioner: Sendable {

    private let client: any AgentIMQQHTTPClient
    private let now: @Sendable () -> Date

    public init(client: any AgentIMQQHTTPClient,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.client = client
        self.now = now
    }

    /// 一次准备齐（**面板与连接按钮都只调这一个**：两处各写一遍，迟早出现「测通了、连不上」）。
    public func prepare(appID: String,
                        secret: String,
                        environment: AgentIMQQEnvironment,
                        relayOverride: URL? = nil) async throws -> AgentIMQQProvisioning {
        let cleanAppID = appID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanAppID.isEmpty else { throw AgentIMQQProvisionProblem.appIDMissing }
        guard !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentIMQQProvisionProblem.secretMissing
        }
        let token = try await requestToken(appID: cleanAppID, secret: secret, environment: environment)
        let gateway: AgentIMQQGatewayResolution
        if let relayOverride {
            // 自建中继：用户明确给了地址 ⇒ 不问官方网关（问了也不该用它的答复）。
            gateway = AgentIMQQGatewayResolution(url: relayOverride, source: .relay)
        } else {
            gateway = await resolveGateway(token: token, environment: environment)
        }
        return AgentIMQQProvisioning(token: token, gateway: gateway)
    }

    // MARK: - token

    public func requestToken(appID: String, secret: String,
                             environment: AgentIMQQEnvironment) async throws -> AgentIMQQToken {
        let response: AgentIMHTTPResponse
        do {
            response = try await client.post(environment.tokenEndpoint,
                                             json: ["appId": appID, "clientSecret": secret],
                                             headers: ["Content-Type": "application/json"])
        } catch {
            throw AgentIMQQProvisionProblem.networkFailed
        }
        if let problem = Self.problem(for: response) { throw problem }
        guard let object = Self.jsonObject(response.body) else {
            throw AgentIMQQProvisionProblem.responseNotJSON
        }
        guard let value = (object["access_token"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { throw AgentIMQQProvisionProblem.tokenMissing }
        return AgentIMQQToken(value: value,
                              expiresIn: Self.expiresIn(from: object),
                              obtainedAt: now())
    }

    // MARK: - 网关地址

    /// 取 `wss` 地址。**取不到不抛错** —— 用该环境的固定地址并记下原因（`source = fallback`）：
    /// 网络抖一下不该被说成「配置错」。真连不通由传输层与「测试连接」如实报。
    public func resolveGateway(token: AgentIMQQToken,
                               environment: AgentIMQQEnvironment) async -> AgentIMQQGatewayResolution {
        let response: AgentIMHTTPResponse
        do {
            response = try await client.get(environment.gatewayEndpoint,
                                            headers: token.authorizationHeaders)
        } catch {
            return AgentIMQQGatewayResolution(url: environment.websocketFallback,
                                              source: .fallback,
                                              note: "networkFailed")
        }
        if let problem = Self.problem(for: response) {
            return AgentIMQQGatewayResolution(url: environment.websocketFallback,
                                              source: .fallback,
                                              note: Self.note(problem))
        }
        guard let object = Self.jsonObject(response.body),
              let text = (object["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: text), url.host != nil else {
            return AgentIMQQGatewayResolution(url: environment.websocketFallback,
                                              source: .fallback,
                                              note: "responseNotJSON")
        }
        return AgentIMQQGatewayResolution(url: url, source: .discovered)
    }

    // MARK: - 读数解析

    /// 非 2xx → 可读原因（**只认状态码**；正文里的码原样带出去，不替它编含义）。
    static func problem(for response: AgentIMHTTPResponse) -> AgentIMQQProvisionProblem? {
        if response.isSuccess { return nil }
        switch response.status {
        case 401: return .credentialsRejected
        case 403: return .permissionDenied
        case 429: return .rateLimited
        default:
            if response.status >= 500 { return .serverFailed }
            return .rejected(status: response.status, code: errorCode(in: response.body))
        }
    }

    /// 正文里的 `code`（QQ 侧失败时常是 `{"code":100016,"message":"…"}`）；没有就 nil。
    static func errorCode(in body: String) -> String? {
        guard let object = jsonObject(body) else { return nil }
        if let number = object["code"] as? Int { return String(number) }
        if let text = object["code"] as? String, !text.isEmpty { return text }
        return nil
    }

    static func jsonObject(_ body: String) -> [String: Any]? {
        ProvisionerSupport.jsonObject(body)
    }

    /// `expires_in` 官方给的是**字符串**，但数字也得认（一份实现两种形状都读）。
    static func expiresIn(from object: [String: Any]) -> TimeInterval {
        if let number = object["expires_in"] as? Int { return TimeInterval(number) }
        if let number = object["expires_in"] as? Double { return TimeInterval(number) }
        if let text = object["expires_in"] as? String, let number = Double(text) { return number }
        return 7200
    }

    /// 原因码的**机器写法**（写进 `note`，面板翻人话）。
    static func note(_ problem: AgentIMQQProvisionProblem) -> String {
        switch problem {
        case .rejected(let status, let code):
            return code.map { "rejected(\(status),\($0))" } ?? "rejected(\(status))"
        case .environmentMissing: return "environmentMissing"
        case .appIDMissing: return "appIDMissing"
        case .secretMissing: return "secretMissing"
        case .networkFailed: return "networkFailed"
        case .responseNotJSON: return "responseNotJSON"
        case .credentialsRejected: return "credentialsRejected"
        case .permissionDenied: return "permissionDenied"
        case .rateLimited: return "rateLimited"
        case .serverFailed: return "serverFailed"
        case .tokenMissing: return "tokenMissing"
        }
    }
}

/// token 的**唯一持有处**：内存缓存 + 到期前换 + **单飞**（几个调用方同时要换时只发一次请求）。
///
/// 为什么不落盘：`access_token` 是短期凭据，写进配置面就等于把「钥匙串里只放 Secret」这条纪律破了。
/// 为什么单飞：传输层每一跳重连都要头，若每次都去换，重连风暴会变成「一分钟被 QQ 限流」。
public actor AgentIMQQTokenVault {

    private var token: AgentIMQQToken?
    private var inFlight: Task<AgentIMQQToken, Error>?

    public init() {}

    public func cached() -> AgentIMQQToken? { token }

    public func reset() {
        token = nil
        inFlight?.cancel()
        inFlight = nil
    }

    /// 要一把能用的 token：还新鲜就直接给，快到期就换，同时来的几个调用方共用一次请求。
    public func current(now: Date = Date(),
                        forceRefresh: Bool = false,
                        fetch: @escaping @Sendable () async throws -> AgentIMQQToken) async throws -> AgentIMQQToken {
        if !forceRefresh, let token, !token.needsRefresh(now: now) { return token }
        if let inFlight { return try await inFlight.value }
        let task = Task { try await fetch() }
        inFlight = task
        do {
            let fresh = try await task.value
            token = fresh
            inFlight = nil
            return fresh
        } catch {
            inFlight = nil
            // 换不到：只要还没**过期**就继续用 —— 「因为换不到新 token 就断线」比「用旧 token 再试一次」更糟。
            // （注意判的是「过期」，不是「该换了」：该换却没换到的这段时间里，旧 token 仍然能握手。）
            if let token, now < token.expiresAt { return token }
            throw error
        }
    }
}

/// QQ 官方网关的**帧口径**（`op` 码与鉴权头）。
///
/// 为什么要单独一处：自建中继那套 `{"op":"ping"}` 的中继约定与官方数字 op 码是两套东西，
/// 混在一个 `switch` 里迟早把 `op=2` 与 `"op":"message"` 认成同一个。官方路径全走这里。
public enum AgentIMQQHandshake {

    public static let authorizationHeaderName = "Authorization"

    /// 群与 C2C 消息事件（官方 intents 位；本轮只订这一类：聊天里派活要的就是它）。
    public static let intentsC2CAndGroup = 1 << 25

    public enum Op: Int, Sendable {
        case dispatch = 0
        case heartbeat = 1
        case identify = 2
        case resume = 6
        case reconnect = 7
        case invalidSession = 9
        case hello = 10
        case heartbeatAck = 11
    }

    public static func identifyFrame(token: AgentIMQQToken,
                                    intents: Int = intentsC2CAndGroup) -> String {
        encode([
            "op": Op.identify.rawValue,
            "d": [
                "token": "QQBot \(token.value)",
                "intents": intents,
                "shard": [0, 1],
                "properties": ["$os": "macOS", "$device": "DoyahStudio"],
            ],
        ])
    }

    /// 心跳：第一跳还没有 `seq`（官方接受 `null`），之后带最后一帧的 `s`。
    public static func heartbeatFrame(sequence: Int?) -> String {
        encode(["op": Op.heartbeat.rawValue, "d": sequence ?? NSNull()])
    }

    /// 断线恢复（`op=6`）：带 sessionID 与最后的 `seq`，官方据此补发漏掉的事件。
    public static func resumeFrame(token: AgentIMQQToken, sessionID: String, sequence: Int) -> String {
        encode([
            "op": Op.resume.rawValue,
            "d": ["token": "QQBot \(token.value)", "session_id": sessionID, "seq": sequence],
        ])
    }

    public static func op(of frame: String) -> Int? {
        guard let object = ProvisionerSupport.jsonObject(frame) else { return nil }
        if let number = object["op"] as? Int { return number }
        if let text = object["op"] as? String { return Int(text) }
        return nil
    }

    /// `op=10` 的 `d.heartbeat_interval`（官方给毫秒，这里换秒）。认不出给 nil。
    public static func heartbeatInterval(of frame: String) -> TimeInterval? {
        guard op(of: frame) == Op.hello.rawValue,
              let object = ProvisionerSupport.jsonObject(frame),
              let data = object["d"] as? [String: Any] else { return nil }
        if let millis = data["heartbeat_interval"] as? Int { return TimeInterval(millis) / 1000 }
        if let millis = data["heartbeat_interval"] as? Double { return millis / 1000 }
        return nil
    }

    /// 一帧的 `s`（官方 seq：心跳与恢复都要带它）；没有或不是数字 ⇒ nil。
    public static func sequence(of frame: String) -> Int? {
        guard let object = ProvisionerSupport.jsonObject(frame) else { return nil }
        if let number = object["s"] as? Int { return number }
        if let text = object["s"] as? String { return Int(text) }
        return nil
    }

    /// 官方帧 → 契约层的入站帧。
    ///
    /// 认得出的事件：C2C 私聊与群里 @ 机器人（这两种都是「聊天里派活」）；其余事件 `.unknown(op:)`
    /// —— **不假装懂**（也不静默丢：调用方要能记一条）。
    public static func decode(_ text: String, receivedAt: Date = Date()) -> AgentIMInboundFrame? {
        guard let object = ProvisionerSupport.jsonObject(text),
              let code = (object["op"] as? Int) ?? Int(object["op"] as? String ?? "") else { return nil }
        switch Op(rawValue: code) {
        case .heartbeatAck:
            return .pong
        case .hello:
            return .unknown(op: "hello")
        case .reconnect:
            return .unknown(op: "reconnect")
        case .invalidSession:
            return .unknown(op: "invalidSession")
        case .dispatch:
            return dispatch(object, receivedAt: receivedAt)
        default:
            return .unknown(op: String(code))
        }
    }

    private static func dispatch(_ object: [String: Any], receivedAt: Date) -> AgentIMInboundFrame? {
        guard let event = object["t"] as? String,
              let data = object["d"] as? [String: Any] else { return .unknown(op: "dispatch") }
        // **READY 要留 session_id**：断线后 Resume 靠它。以前这一帧被当成 `unknown` 丢掉了。
        if event == "READY" {
            if let sessionID = data["session_id"] as? String, !sessionID.isEmpty {
                return .ready(sessionID: sessionID)
            }
            return .unknown(op: "READY")
        }
        guard let text = (data["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let messageID = data["id"] as? String else {
            return .unknown(op: event)
        }
        let author = data["author"] as? [String: Any]
        let sender = (author?["user_openid"] as? String)
            ?? (author?["member_openid"] as? String)
            ?? (author?["id"] as? String)
            ?? ""
        let chatID = (data["group_openid"] as? String) ?? sender
        guard !chatID.isEmpty, !sender.isEmpty else { return .unknown(op: event) }
        // 私聊 / 群各一对端点 ⇒ 这一档必须在这里定死（回话走错端点 = 404 或打给别人）。
        let kind: AgentIMChatKind = (data["group_openid"] as? String) == nil ? .c2c : .group
        switch event {
        case "C2C_MESSAGE_CREATE", "GROUP_AT_MESSAGE_CREATE", "AT_MESSAGE_CREATE":
            return .message(AgentIMInboundMessage(platformMessageID: messageID,
                                                  chatID: chatID,
                                                  senderID: sender,
                                                  text: text,
                                                  receivedAt: receivedAt,
                                                  chatKind: kind))
        default:
            return .unknown(op: event)
        }
    }

    private static func encode(_ object: [String: Any]) -> String {
        ProvisionerSupport.encode(object)
    }
}

/// JSON 进出的**最小工具**（键序固定：判据按串比时不至于今天一样明天不一样）。
enum ProvisionerSupport {

    static func jsonObject(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func encode(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
}

/// 取 token / 取地址 失败的人话（`language` 由调用方给：语言只有一个来源）。
public enum AgentIMQQProvisionText {

    public static func line(for problem: AgentIMQQProvisionProblem, language: AppLanguage) -> String {
        switch problem {
        case .environmentMissing: return LocalizedStrings.text(.agentIMQQEnvironmentMissing, language: language)
        case .appIDMissing: return LocalizedStrings.text(.agentIMQQAppIDMissing, language: language)
        case .secretMissing: return LocalizedStrings.text(.agentIMQQSecretMissing, language: language)
        case .networkFailed: return LocalizedStrings.text(.agentIMQQNetworkFailed, language: language)
        case .responseNotJSON: return LocalizedStrings.text(.agentIMQQResponseNotJSON, language: language)
        case .credentialsRejected: return LocalizedStrings.text(.agentIMQQCredentialsRejected, language: language)
        case .permissionDenied: return LocalizedStrings.text(.agentIMQQPermissionDenied, language: language)
        case .rateLimited: return LocalizedStrings.text(.agentIMQQRateLimited, language: language)
        case .serverFailed: return LocalizedStrings.text(.agentIMQQServerFailed, language: language)
        case .tokenMissing: return LocalizedStrings.text(.agentIMQQTokenMissing, language: language)
        case .rejected(let status, let code):
            return LocalizedStrings.format(.agentIMQQRejected, language: language,
                                          Int64(status), code ?? "—")
        }
    }

    /// token 那一行（面板只显示尾 4 位；本体永远不出 Core）。
    /// 句子的拼法收在 Core：界面那一层只搬结论（同一句话出现两处就会漂成两种说法）。
    public static func tokenLine(redacted: String, language: AppLanguage) -> String {
        LocalizedStrings.format(.agentIMTokenPreview, language: language, redacted)
    }

    /// 地址这一档的人话（**取到的 / 兜底的 / 自建中继**说不同的话：
    /// 只说「已连接」，用户永远不知道自己在用哪个地址）。
    public static func gatewayLine(for resolution: AgentIMQQGatewayResolution,
                                   language: AppLanguage) -> String {
        switch resolution.source {
        case .discovered:
            return LocalizedStrings.format(.agentIMQQGatewayDiscovered, language: language,
                                          resolution.url.absoluteString)
        case .fallback:
            return LocalizedStrings.format(.agentIMQQGatewayFallback, language: language,
                                          resolution.note ?? "—",
                                          resolution.url.absoluteString)
        case .relay:
            return LocalizedStrings.format(.agentIMQQGatewayRelay, language: language,
                                          resolution.url.absoluteString)
        }
    }
}
