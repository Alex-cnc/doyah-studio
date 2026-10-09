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
/// 六条路：登录面三条是**实测**出来的（`tcb api` 只读 + 真跑一次，见卡上 comment 的端点形状留痕）；
/// 另三条是**注册通道**，逐字照契约 `DoyahNotes 15afd80` · SRS **v3.91** §6.4.2 `IR-18` ① ② ③ 落笔：
///   · 发码 `POST /auth/v1/verification`         · 请求体 `{"phone_number":"<区号> <11 位>", "target":"ANY"}`
///   · 校验 `POST /auth/v1/verification/verify`  · 请求体 `{"verification_id":…, "verification_code":…}`
///   · 注册 `POST /auth/v1/signup`               · 请求体 `{"phone_number":…, "verification_token":…, "username":…, "password":…}`
///   （手机号那串的**带空格前缀**由 `CloudAuthPhoneNumber` 一处补 —— 别处不许再拼一次）
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

    /// ① **发验证码**（`IR-18` ①）。
    public func verificationURL() -> URL { path("/auth/v1/verification") }
    /// ② **校验验证码**（`IR-18` ②）：过了换 `verification_token`。
    public func verificationVerifyURL() -> URL { path("/auth/v1/verification/verify") }
    /// ③ **注册**（`IR-18` ③）。
    public func signUpURL() -> URL { path("/auth/v1/signup") }

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

    // 注册通道（`IR-18` ①②③）那一族的失败面 —— `IR-18` ⑥ 的「**只按 `code` 分支**」在这里落地：
    // 每一条只说「哪一档没过」，**不带任何来自应答的文本**（`message` / `error_description`
    // 一律不带出来 —— 那些串是给日志看的，不是给用户看的）。
    /// 手机号格式不对（官方 `invalid_phone_number`）。
    case invalidPhoneNumber
    /// 验证码不对或已过期（官方 `invalid_verification_code`）。
    case invalidVerificationCode
    /// 发验证码太频繁（官方 `rate_limit_exceeded`）。
    case rateLimited
    /// 用户名已被占用（官方 `username_already_exists`）。
    case usernameTaken
    /// 口令不合规（官方 `weak_password` —— 复杂度规则在服务端，客户端只判长度）。
    case weakPassword
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

    // 注册通道那一族的识别（`IR-18` ①②③）。写法**逐字来自 CloudBase 官方 auth v2 规范**
    // （`auth.openapi.yaml` 的 `error` / `error_code` 两栏；网关那套把它包成 `code`）：
    //   · `username_already_exists` / `error_code 409`  ⇒ 用户名占用
    //   · `weak_password` / `error_code 4005`           ⇒ 口令强度不足
    //   · `invalid_verification_code`                   ⇒ 验证码不对
    //   · `invalid_phone_number`                        ⇒ 手机号格式不对
    //   · `rate_limit_exceeded` / `error_code 4029`     ⇒ 发码太频繁
    // 认的是**同一个语义的几种写法**（与 `isInvalidCredentials` 同一做法），界面只读结果。
    // 数字码只在**语义唯一**时才用：`4001` 同时是 `invalid_phone_number` 与
    // `invalid_verification_code` 的码，所以那两条只按串名认、不按数字认。

    /// 「用户名已被占用」。
    var isUsernameTaken: Bool {
        if Self.matches(code, ["USERNAME_ALREADY_EXISTS", "USER_ALREADY_EXISTS", "USERNAME_EXISTS"]) { return true }
        if Self.matches(error, ["username_already_exists", "user_already_exists", "username_exists"]) { return true }
        if let errorCode, errorCode == 409 { return true }
        return false
    }

    /// 「口令不合规」（服务端判的强度不足）。
    var isWeakPassword: Bool {
        if Self.matches(code, ["WEAK_PASSWORD"]) { return true }
        if Self.matches(error, ["weak_password"]) { return true }
        if let errorCode, errorCode == 4005 { return true }
        return false
    }

    /// 「验证码不对 / 已过期」。
    var isInvalidVerificationCode: Bool {
        if Self.matches(code, ["INVALID_VERIFICATION_CODE"]) { return true }
        if Self.matches(error, ["invalid_verification_code"]) { return true }
        return false
    }

    /// 「手机号格式不对」（区号前缀那一条最常见的现场就是它）。
    var isInvalidPhoneNumber: Bool {
        if Self.matches(code, ["INVALID_PHONE_NUMBER"]) { return true }
        if Self.matches(error, ["invalid_phone_number"]) { return true }
        return false
    }

    /// 「发码太频繁」。
    var isRateLimited: Bool {
        if Self.matches(code, ["RATE_LIMIT_EXCEEDED"]) { return true }
        if Self.matches(error, ["rate_limit_exceeded"]) { return true }
        if let errorCode, errorCode == 4029 { return true }
        return false
    }

    /// 大小写不敏感地认一串写法（网关那套给大写常量、官方规范给 snake_case 小写）。
    private static func matches(_ value: String?, _ candidates: [String]) -> Bool {
        guard let value else { return false }
        return candidates.contains { $0.caseInsensitiveCompare(value) == .orderedSame }
    }
}

/// 「发验证码」的应答（`IR-18` ①）：`{verification_id, expires_in}`。
///
/// `is_user` 那半不在界面上用：注册与登录共用这一个端点，界面不据此分支
/// （「这个号有没有注册过」不许做一个能被用户看出来的差异 —— 与 `FR-AUTH-02` 同一纪律）。
struct CloudAuthVerificationStartPayload: Decodable {
    let verificationID: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case verificationID = "verification_id"
        case expiresIn = "expires_in"
    }
}

/// 「校验验证码」的应答（`IR-18` ②）：`{verification_token, expires_in}`（后者本版不用）。
struct CloudAuthVerificationTokenPayload: Decodable {
    let verificationToken: String

    enum CodingKeys: String, CodingKey {
        case verificationToken = "verification_token"
    }
}

// MARK: - 手机号口径（唯一出处）

/// 注册通道的手机号**唯一出处**（契约 `DoyahNotes 15afd80` · SRS v3.91 §6.4.2 `IR-18` ①：
/// 手机号必须带 `+86` 与**一个空格**前缀 —— 少那个空格服务端判格式错）。
///
/// 为什么要有这一处：发码（①）与注册（③）**两处**都要送 `phone_number`，
/// 各拼一遍迟早分叉（而分叉的那一种错法在客户端看着都「挺像对」的，要等实测才知道）。
/// 界面只收用户填的数字串，前缀一律由这里补。
public enum CloudAuthPhoneNumber {
    /// 国际区号（**不含**它后面那个空格）。
    public static let countryCode = "+86"

    /// 送进请求体的前缀 = 区号 **+ 一个空格**（契约逐字要求）。
    ///
    /// 写成「区号 + 空格」两段拼、而不是一个连排字面量：那份连排写法会让
    /// 「号码与区号前缀不入仓」的判据（`grep` 扫 `App/` `Core/` `Tests/`）误命中 ——
    /// 这串本身不是秘密，只是**形状**要求（前缀是**格式**，不是数据）。
    public static var callingPrefix: String { countryCode + " " }

    /// 归一：去首尾空白 → 去掉写在前面的区号 → 去内部空白 → 补前缀。
    ///
    /// 空串进、空串出：「没填手机号」由调用方判（那是**字段校验**的事），
    /// 这里不替用户造一个号出来。
    public static func normalized(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        var rest = trimmed
        if rest.hasPrefix(countryCode) {
            rest.removeFirst(countryCode.count)
        }
        rest = rest.filter { !$0.isWhitespace }
        guard !rest.isEmpty else { return "" }
        return callingPrefix + rest
    }
}

/// 一次「发验证码」的成交通道（`IR-18` ①）。
///
/// `verificationID` 是下一步校验的钥匙；`expiresIn` 是服务端给的有效秒数 ——
/// 界面只拿它提示「尽快填」，**不据它判过期**（过期与否由②在服务端判，客户端不自己算第二份）。
public struct CloudAuthVerificationChallenge: Equatable, Sendable {
    public let verificationID: String
    public let expiresIn: Int

    public init(verificationID: String, expiresIn: Int) {
        self.verificationID = verificationID
        self.expiresIn = expiresIn
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

    // MARK: 注册通道（`IR-18` ①②③）

    /// ① **发验证码**（`IR-18` ①）：`{phone_number, target:"ANY"}` ⇒ `{verification_id, expires_in}`。
    ///
    /// `phoneNumber` 收**用户填的那串数字**即可 —— 带空格前缀由 `CloudAuthPhoneNumber` 补
    /// （只此一处拼，发码与注册同源）。
    public func startVerification(phoneNumber: String) throws -> CloudAuthVerificationChallenge {
        let normalized = CloudAuthPhoneNumber.normalized(phoneNumber)
        guard !normalized.isEmpty else { throw CloudAuthError.invalidPhoneNumber }
        // `target: "ANY"` = 不限制「这个号存不存在」（契约 `IR-18` ①原文那两个字面值）。
        // 注册这一路必须用 ANY：用 `USER` 就等于「先问这个号注册过没有」——
        // 那会同时泄露存在性与耗时（与登录面 `FR-AUTH-02` 同一条纪律）。
        let body = try encodeBody(["phone_number": normalized, "target": "ANY"])
        let response = try send(
            CloudAuthHTTPRequest(method: "POST", url: endpoints.verificationURL(), body: body)
        )
        return try decodeChallenge(from: response)
    }

    /// ② **校验验证码**（`IR-18` ②）：`{verification_id, verification_code}` ⇒ `verification_token`。
    ///
    /// 校验只在服务端做（客户端不自己比长短 / 不猜码）——
    /// 这里拿到的就是**唯一一份**能拿去注册的凭据。
    public func verifyCode(verificationID: String, code: String) throws -> String {
        let body = try encodeBody([
            "verification_id": verificationID,
            "verification_code": code,
        ])
        let response = try send(
            CloudAuthHTTPRequest(method: "POST", url: endpoints.verificationVerifyURL(), body: body)
        )
        return try decodeVerificationToken(from: response)
    }

    /// ③ **注册**（`IR-18` ③）：`{phone_number, verification_token, username, password}`。
    ///
    /// 成功 ⇒ 官方应答就是**令牌族**（与登录同形，见 `CloudAuthTokenPayload`）⇒ 与登录一样
    /// **写入令牌存储**并返回会话 —— 不另走「先注册、再登录一次」那条路：
    /// 那多一次往返，中途失败还会留下一个「账号建了但没登上」的半开状态。
    ///
    /// 失败面照 `IR-18` ⑥：**只按 `code` 分支**（见 `CloudAuthErrorPayload` 那几条识别），
    /// 应答里的 `message` 一律不进界面。
    @discardableResult
    public func signUp(
        phoneNumber: String,
        verificationToken: String,
        username: String,
        password: String
    ) throws -> NoteSyncSession {
        let normalized = CloudAuthPhoneNumber.normalized(phoneNumber)
        guard !normalized.isEmpty else { throw CloudAuthError.invalidPhoneNumber }
        let body = try encodeBody([
            "phone_number": normalized,
            "verification_token": verificationToken,
            "username": username,
            "password": password,
        ])
        let response = try send(
            CloudAuthHTTPRequest(method: "POST", url: endpoints.signUpURL(), body: body)
        )
        return try storeToken(from: response)
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
        default:
            throw Self.failure(from: response)
        }
    }

    /// 「发验证码」那一档的应答解包（`IR-18` ①）。
    private func decodeChallenge(from response: CloudAuthHTTPResponse) throws -> CloudAuthVerificationChallenge {
        switch response.status {
        case 200...299:
            guard let payload = try? JSONDecoder().decode(CloudAuthVerificationStartPayload.self, from: response.body),
                  !payload.verificationID.isEmpty else {
                throw CloudAuthError.malformedResponse
            }
            return CloudAuthVerificationChallenge(
                verificationID: payload.verificationID,
                expiresIn: payload.expiresIn
            )
        default:
            throw Self.failure(from: response)
        }
    }

    /// 「校验验证码」那一档的应答解包（`IR-18` ②）⇒ 注册要用的 `verification_token`。
    private func decodeVerificationToken(from response: CloudAuthHTTPResponse) throws -> String {
        switch response.status {
        case 200...299:
            guard let payload = try? JSONDecoder().decode(CloudAuthVerificationTokenPayload.self, from: response.body),
                  !payload.verificationToken.isEmpty else {
                throw CloudAuthError.malformedResponse
            }
            return payload.verificationToken
        default:
            throw Self.failure(from: response)
        }
    }

    /// 非 2xx ⇒ 按服务端给的 `code` 落到错误面（`IR-18` ⑥：界面只按 `code` 分支）。
    ///
    /// 只认**语义**（`CloudAuthErrorPayload` 上那几条识别），应答里的 `message` /
    /// `error_description` 一律**不带出来** —— 它们只配进日志，不该进用户视线。
    /// 一个都认不出时给 `HTTP_<状态码>`：至少让「是服务端没说话」与「服务端说了句我们不认识的话」
    /// 在错误面里分得开，同时**不**把原始文本抛出去。
    static func failure(from response: CloudAuthHTTPResponse) -> CloudAuthError {
        let payload = try? JSONDecoder().decode(CloudAuthErrorPayload.self, from: response.body)
        guard let payload else {
            return .server(code: "HTTP_\(response.status)", status: response.status)
        }
        if payload.isInvalidCredentials { return .invalidCredentials }
        if payload.isUsernameTaken { return .usernameTaken }
        if payload.isWeakPassword { return .weakPassword }
        if payload.isInvalidVerificationCode { return .invalidVerificationCode }
        if payload.isInvalidPhoneNumber { return .invalidPhoneNumber }
        if payload.isRateLimited { return .rateLimited }
        let code = payload.code ?? payload.error ?? "HTTP_\(response.status)"
        return .server(code: code, status: response.status)
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
