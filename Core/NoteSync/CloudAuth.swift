import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// 云C · 账号认证（`IR-18`）+ 令牌入 Keychain。
//
// 契约依据（只读）：`DoyahNotes/Docs/需求规范书.md` §6.4 账号行（**首版 = 用户名 + 密码**）
// 与 §6.4.2 `IR-18`「注册 / 登录 / 刷新会话 / 登出；**令牌存 Keychain，不落明文文件**」。
//
// 接口面纪律（§6.4「接口面纪律」条）：网络调用只出现在**共享逻辑层的同步模块**内 ——
// 本文件就是那个模块（`Core/NoteSync/`），界面侧不直接触碰网络。
//
// 为什么 Core 只留协议、真实现放平台侧：
//   · 本文件里只有**口令换令牌**这一条 HTTP 面（平台中立：`URLSession` 在 Linux 上走
//     `FoundationNetworking`，不引任何 Apple 专属模块）；
//   · **令牌怎么存**是平台的事（macOS = 系统钥匙串，见 `Platform/macOS/KeychainSecretStore.swift`
//     的 `KeychainNoteSyncTokenStore`）⇒ Core 只声明 `NoteSyncTokenStore` 这个**Keychain 抽象层**。
//   · 客户端只持 **publishable key**（`Authorization: Bearer <publishable key>` 用于数据面），
//     **任何 secret 不进 App**：本文件里没有、也不该有服务端密钥。

// MARK: - 会话凭证

/// 一次账号会话的凭证（`IR-18`）。
///
/// **不落明文文件**：本类型只在内存与 `NoteSyncTokenStore`（macOS = 系统钥匙串）之间传递 ——
/// 不写进普通文件，不进日志，也不进错误信息（`CloudAuthError` 一律不带令牌本体）。
///
/// 字段名对齐 CloudBase 官方 HTTP 应答（`/auth/v1/signin` 的 `access_token` / `refresh_token` /
/// `expires_in` / `token_type` / `sub`）—— 见 `CloudAuthTokenPayload` 的 `CodingKeys`。
public struct NoteSyncSession: Codable, Equatable, Sendable {
    /// 访问令牌：`Authorization: Bearer <accessToken>` 用。
    public let accessToken: String
    /// 刷新令牌：换新 access 用；登出时交给服务端撤销。
    public let refreshToken: String
    /// 令牌类型（CloudBase 返回 `Bearer`）。
    public let tokenType: String
    /// 有效期（秒）。
    public let expiresIn: Int
    /// 归属主键：云端 `uid`（RLS 以它为准，见 §6.4 身份与归属条）。
    public let subject: String
    /// 拿到这一份凭证的**本地时刻** —— 过期判断以它为基准，不用墙钟漂移过的服务端时刻。
    public let obtainedAt: Date

    public init(
        accessToken: String,
        refreshToken: String,
        tokenType: String = "Bearer",
        expiresIn: Int,
        subject: String,
        obtainedAt: Date = Date()
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.tokenType = tokenType
        self.expiresIn = expiresIn
        self.subject = subject
        self.obtainedAt = obtainedAt
    }

    /// 到期时刻。
    public var expiresAt: Date {
        obtainedAt.addingTimeInterval(TimeInterval(expiresIn))
    }

    /// 是否已过期。`leeway` 留出提前刷新的余量（正数 = 提前判过期）。
    public func isExpired(now: Date = Date(), leeway: TimeInterval = 0) -> Bool {
        now.addingTimeInterval(leeway) >= expiresAt
    }
}

/// **令牌存储抽象层**（Keychain 抽象层）。
///
/// Core 只声明行为；实现按平台给：
///   · macOS → `Platform/macOS/KeychainSecretStore.swift` 的 `KeychainNoteSyncTokenStore`（系统钥匙串）；
///   · 其它平台 → 待建（契约与 macOS 侧一致：**不落明文文件**、可被明确清除、不进日志）。
public protocol NoteSyncTokenStore: Sendable {
    func setSession(_ session: NoteSyncSession) throws
    func session() throws -> NoteSyncSession?
    func deleteSession() throws
}

// MARK: - 网络面（平台中立的最小形状）

/// 一次 CloudBase HTTP 调用的最小请求面。
///
/// 为什么不直接用 `URLRequest`：测试要能**机械复核发出去的形状**（方法 / URL / 请求头 / 请求体），
/// 而不必起真网络；`URLRequest` 是 Foundation 的具体类型、不便做等值断言。
public struct CloudAuthHTTPRequest: Equatable, Sendable {
    public var method: String
    public var url: URL
    public var headers: [String: String]
    public var body: Data?

    public init(method: String, url: URL, headers: [String: String] = [:], body: Data? = nil) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }
}

/// 一次 CloudBase HTTP 调用的最小应答面（只要状态码与响应体）。
public struct CloudAuthHTTPResponse: Sendable {
    public var status: Int
    public var body: Data

    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }
}

/// 出网传输抽象：真实现 = `URLSessionCloudAuthTransport`；测试 = 注入假应答。
public protocol CloudAuthTransport: Sendable {
    func send(_ request: CloudAuthHTTPRequest) throws -> CloudAuthHTTPResponse
}

// MARK: - 端点口径

/// CloudBase「自建账号 · 用户名 + 密码」HTTP 面的端点（`http-api-cloudbase` · **国内站**）。
///
/// 基址即官方网关口径 `https://{envId}.api.tcloudbasegateway.com`，账号面挂在 `/auth/v1/**`——
/// 三条路都是**实测**出来的（`tcb api` 只读 + 真跑一次，见卡上 comment 的端点形状留痕）：
///   · 登录 `POST /auth/v1/signin`  · 请求体 `{"username":…, "password":…}`
///   · 刷新 `POST /auth/v1/token`   · 请求体 `{"grant_type":"refresh_token", "refresh_token":…}`
///   · 登出 `POST /auth/v1/revoke`  · 请求体 `{"refresh_token":…}` + 请求头 `Authorization: Bearer <access>`
///
/// **不用 Web SDK 流程**（§6.4：native App 走 HTTP 面）—— 因此这里没有 `session` 包壳，
/// 应答就是官方 HTTP 的裸 JSON（`access_token` / `refresh_token` / …，见 `CloudAuthTokenPayload`）。
public struct CloudAuthEndpoints: Sendable {
    /// 国内站网关域名后缀（国际站是 `.api.intl.tcloudbasegateway.com`；本环境是国内站）。
    public static let domesticHostSuffix = ".api.tcloudbasegateway.com"

    public let baseURL: URL

    public init(baseURL: URL) {
        self.baseURL = baseURL
    }

    /// 按环境 ID 组基址（`doyah-notes-db00-d6el2lr50a6ef27` ⇒ 网关基址）。
    public init(environmentID: String) {
        self.baseURL = URL(string: "https://\(environmentID)\(Self.domesticHostSuffix)")!
    }

    public func signInURL() -> URL { path("/auth/v1/signin") }
    public func refreshURL() -> URL { path("/auth/v1/token") }
    public func revokeURL() -> URL { path("/auth/v1/revoke") }

    private func path(_ relative: String) -> URL {
        URL(string: relative, relativeTo: baseURL)!.absoluteURL
    }
}

// MARK: - 错误

/// 账号认证的错误面。
///
/// **不带用户可见文案**（不硬编码中文）：界面侧按分支给本地化文案。
/// **也不带任何令牌本体**：`transport` 只放一句技术描述，绝不放请求头或响应体。
public enum CloudAuthError: Error, Equatable, Sendable {
    /// 用户名或密码错（CloudBase `error_code = 4043` / `INVALID_USERNAME_OR_PASSWORD`）。
    case invalidCredentials
    /// 本地没有会话，无从刷新。
    case notAuthenticated
    /// 服务端返回了非 2xx，且不是「凭据错」这一类。
    case server(code: String, status: Int)
    /// 2xx 但响应体不符合预期形状（解不出令牌字段）。
    case malformedResponse
    /// 出网层失败（连不上 / 超时 / 非 HTTP 应答），payload 只放技术描述。
    case transport(String)
}

// MARK: - 应答形状

/// CloudBase 令牌应答（`/auth/v1/signin` 与 `/auth/v1/token` 同形）。
struct CloudAuthTokenPayload: Decodable {
    let tokenType: String
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let sub: String

    enum CodingKeys: String, CodingKey {
        case tokenType = "token_type"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case sub
    }

    func makeSession(obtainedAt: Date) -> NoteSyncSession {
        NoteSyncSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            tokenType: tokenType,
            expiresIn: expiresIn,
            subject: sub,
            obtainedAt: obtainedAt
        )
    }
}

/// CloudBase 错误应答（400 / 401 / 403 那一族）。
struct CloudAuthErrorPayload: Decodable {
    let code: String?
    let error: String?
    let errorCode: Int?
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case code
        case error
        case errorCode = "error_code"
        case errorDescription = "error_description"
    }

    /// 「用户名或密码错」的三种写法任取其一都算（服务端历史上用过不同字段）。
    var isInvalidCredentials: Bool {
        if let code, code == "INVALID_USERNAME_OR_PASSWORD" { return true }
        if let error, error.lowercased() == "invalid_username_or_password" { return true }
        if let errorCode, errorCode == 4043 { return true }
        return false
    }
}

// MARK: - 客户端

/// 账号认证客户端：登录 / 刷新 / 登出（`IR-18`）。
///
/// 组成（全部注入，便于机械复核）：端点口径 · 出网传输 · 令牌存储抽象层 · 时钟。
public final class CloudAuthClient: @unchecked Sendable {
    public let endpoints: CloudAuthEndpoints

    private let transport: CloudAuthTransport
    private let store: NoteSyncTokenStore
    private let now: @Sendable () -> Date

    public init(
        endpoints: CloudAuthEndpoints,
        transport: CloudAuthTransport,
        store: NoteSyncTokenStore,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.endpoints = endpoints
        self.transport = transport
        self.store = store
        self.now = now
    }

    // MARK: 登录

    /// 用**用户名 + 密码**登录（§6.4 账号行首版口径）。成功 ⇒ 会话**写入令牌存储**并返回。
    @discardableResult
    public func signIn(username: String, password: String) throws -> NoteSyncSession {
        let body = try encodeBody(["username": username, "password": password])
        let response = try send(
            CloudAuthHTTPRequest(method: "POST", url: endpoints.signInURL(), body: body)
        )
        return try storeToken(from: response)
    }

    // MARK: 刷新

    /// 用已存会话的刷新令牌换新令牌，并**覆盖**存回去。
    @discardableResult
    public func refresh() throws -> NoteSyncSession {
        guard let current = try store.session() else {
            throw CloudAuthError.notAuthenticated
        }
        let body = try encodeBody([
            "grant_type": "refresh_token",
            "refresh_token": current.refreshToken,
        ])
        let response = try send(
            CloudAuthHTTPRequest(method: "POST", url: endpoints.refreshURL(), body: body)
        )
        return try storeToken(from: response)
    }

    // MARK: 登出

    /// 登出：请服务端撤销刷新令牌，**然后**清掉本地会话。
    ///
    /// 本地清理**放在最后且不依赖网络结果** —— 登出的语义是「本机不再持有会话」；
    /// 网络失败（离线登出）不该让本机继续留着令牌。
    public func signOut() throws {
        defer { try? store.deleteSession() }
        guard let current = try store.session() else { return }
        let body = try? encodeBody(["refresh_token": current.refreshToken])
        _ = try? send(
            CloudAuthHTTPRequest(
                method: "POST",
                url: endpoints.revokeURL(),
                headers: ["Authorization": "Bearer \(current.accessToken)"],
                body: body
            )
        )
    }

    // MARK: 读

    /// 本地会话（读存储；不存在即 `nil`）。
    public func currentSession() throws -> NoteSyncSession? {
        try store.session()
    }

    /// 只清本地会话，不惊动服务端（换账号 / 存储损坏时的兜底）。
    public func clearLocalSession() throws {
        try store.deleteSession()
    }

    // MARK: 内部

    private func send(_ request: CloudAuthHTTPRequest) throws -> CloudAuthHTTPResponse {
        var headers = request.headers
        headers["Content-Type"] = "application/json"
        headers["Accept"] = "application/json"
        let outgoing = CloudAuthHTTPRequest(
            method: request.method,
            url: request.url,
            headers: headers,
            body: request.body
        )
        do {
            return try transport.send(outgoing)
        } catch let error as CloudAuthError {
            throw error
        } catch {
            throw CloudAuthError.transport(String(describing: error))
        }
    }

    private func storeToken(from response: CloudAuthHTTPResponse) throws -> NoteSyncSession {
        switch response.status {
        case 200...299:
            guard let payload = try? JSONDecoder().decode(CloudAuthTokenPayload.self, from: response.body),
                  !payload.accessToken.isEmpty,
                  !payload.refreshToken.isEmpty else {
                throw CloudAuthError.malformedResponse
            }
            let session = payload.makeSession(obtainedAt: now())
            try store.setSession(session)
            return session
        case 400, 401, 403:
            let payload = try? JSONDecoder().decode(CloudAuthErrorPayload.self, from: response.body)
            if payload?.isInvalidCredentials == true {
                throw CloudAuthError.invalidCredentials
            }
            let code = payload?.code ?? payload?.error ?? "UNKNOWN"
            throw CloudAuthError.server(code: code, status: response.status)
        default:
            throw CloudAuthError.server(code: "HTTP_\(response.status)", status: response.status)
        }
    }

    private func encodeBody(_ object: [String: String]) throws -> Data {
        do {
            return try JSONEncoder().encode(object)
        } catch {
            throw CloudAuthError.malformedResponse
        }
    }
}

// MARK: - 真出网传输

/// `URLSession` 版的传输实现（平台中立：Linux 上走 `FoundationNetworking`）。
///
/// 协议是同步的（`throws -> response`），所以这里用信号量把异步 `dataTask` 收成同步 ——
/// `URLSession(dataTask)` 的回调不在调用线程上跑，因此不会自堵。
public final class URLSessionCloudAuthTransport: CloudAuthTransport, @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: CloudAuthHTTPRequest) throws -> CloudAuthHTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }

        let semaphore = DispatchSemaphore(value: 0)
        var outcome: Result<CloudAuthHTTPResponse, Error> =
            .failure(CloudAuthError.transport("no response"))
        session.dataTask(with: urlRequest) { data, response, error in
            defer { semaphore.signal() }
            if let error {
                outcome = .failure(error)
                return
            }
            guard let http = response as? HTTPURLResponse else {
                outcome = .failure(CloudAuthError.transport("non-http response"))
                return
            }
            outcome = .success(CloudAuthHTTPResponse(status: http.statusCode, body: data ?? Data()))
        }.resume()
        semaphore.wait()
        return try outcome.get()
    }
}
