import XCTest
@testable import DoyahCore

/// 云C · 账号认证（`IR-18`）与**令牌入 Keychain 抽象层**的机械复核。
///
/// 本文件不连真网：出网面注入假应答（`FakeTransport`），令牌存储注入**内存版**实现
/// （`InMemoryTokenStore`，它 conform 的 `NoteSyncTokenStore` 就是 macOS 侧
/// `KeychainNoteSyncTokenStore` 要 conform 的**同一个 Keychain 抽象层**）。
/// 真网络与真钥匙串的读数另在卡上 comment 留痕（判据③）。
final class NoteSyncAuthTests: XCTestCase {

    // MARK: 夹具

    /// 与真实环境一致的验收环境 ID（`doyah-notes` 的环境，见卡片与接入台账）。
    private let environmentID = "doyah-notes-db00-d6el2lr50a6ef27"

    private func makeClient(
        transport: FakeTransport,
        store: InMemoryTokenStore,
        now: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> CloudAuthClient {
        CloudAuthClient(
            endpoints: CloudAuthEndpoints(environmentID: environmentID),
            transport: transport,
            store: store,
            now: { now }
        )
    }

    private func tokenResponse(
        access: String,
        refresh: String,
        expiresIn: Int = 7200,
        subject: String = "2108540229640167426"
    ) -> CloudAuthHTTPResponse {
        let json = """
        {"token_type":"Bearer","access_token":"\(access)","refresh_token":"\(refresh)",\
        "expires_in":\(expiresIn),"sub":"\(subject)"}
        """
        return CloudAuthHTTPResponse(status: 200, body: Data(json.utf8))
    }

    /// 与真跑实测**同形**的凭据错应答（HTTP 400 · `error_code = 4043`）。
    private func invalidCredentialsResponse() -> CloudAuthHTTPResponse {
        let json = """
        {"code":"INVALID_USERNAME_OR_PASSWORD","error":"invalid_username_or_password",\
        "error_code":4043,"error_description":"Username or password incorrect."}
        """
        return CloudAuthHTTPResponse(status: 400, body: Data(json.utf8))
    }

    // MARK: ① 成功 ⇒ 令牌写入 Keychain 抽象层且可读回

    func testSignInSuccessWritesTokenIntoKeychainAbstractionAndReadsBack() throws {
        let transport = FakeTransport(responses: [tokenResponse(access: "access-aaa", refresh: "refresh-aaa")])
        let store = InMemoryTokenStore()
        let client = makeClient(transport: transport, store: store)

        let session = try client.signIn(username: "doyahcloudctest01", password: "pw-not-real")

        // 写入抽象层：从存储里读回来必须与返回值逐字一致（令牌只经存储、不另抄一份）。
        XCTAssertEqual(session.accessToken, "access-aaa")
        XCTAssertEqual(session.refreshToken, "refresh-aaa")
        XCTAssertEqual(session.tokenType, "Bearer")
        XCTAssertEqual(session.expiresIn, 7200)
        XCTAssertEqual(session.subject, "2108540229640167426")

        let stored = try XCTUnwrap(try store.session(), "登录成功后抽象层里必须有会话")
        XCTAssertEqual(stored, session)
        XCTAssertEqual(try client.currentSession(), session)
    }

    // MARK: ② 口令错 ⇒ 明确失败态，且不留半个会话

    func testSignInWrongPasswordYieldsExplicitFailureAndLeavesNoSession() throws {
        let transport = FakeTransport(responses: [invalidCredentialsResponse()])
        let store = InMemoryTokenStore()
        let client = makeClient(transport: transport, store: store)

        XCTAssertThrowsError(try client.signIn(username: "doyahcloudctest01", password: "wrong")) { error in
            XCTAssertEqual(error as? CloudAuthError, .invalidCredentials)
        }
        // 失败不许落一份会话（否则下一次刷新会拿一个不存在的会话去换）。
        XCTAssertNil(try store.session())
        XCTAssertNil(try client.currentSession())
    }

    // MARK: ③ 发出去的形状 = CloudBase 官方 HTTP 面

    func testSignInRequestShapeMatchesCloudBaseHTTPFace() throws {
        let transport = FakeTransport(responses: [tokenResponse(access: "a", refresh: "r")])
        let client = makeClient(transport: transport, store: InMemoryTokenStore())

        _ = try client.signIn(username: "doyahcloudctest01", password: "pw-not-real")

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(
            request.url.absoluteString,
            "https://\(environmentID).api.tcloudbasegateway.com/auth/v1/signin"
        )
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.headers["Content-Type"], "application/json")
        XCTAssertEqual(request.headers["Accept"], "application/json")

        let body = try XCTUnwrap(request.body)
        let decoded = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: body) as? [String: String]
        )
        XCTAssertEqual(decoded["username"], "doyahcloudctest01")
        XCTAssertEqual(decoded["password"], "pw-not-real")
        XCTAssertEqual(decoded.count, 2)
    }

    // MARK: ④ 刷新用已存的 refresh 换新令牌并覆盖存回

    func testRefreshRotatesTokensUsingStoredRefreshToken() throws {
        let store = InMemoryTokenStore()
        try store.setSession(
            NoteSyncSession(
                accessToken: "old-access",
                refreshToken: "old-refresh",
                expiresIn: 1,
                subject: "2108540229640167426",
                obtainedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
        )
        let transport = FakeTransport(responses: [tokenResponse(access: "new-access", refresh: "new-refresh")])
        let client = makeClient(transport: transport, store: store)

        let refreshed = try client.refresh()

        XCTAssertEqual(refreshed.accessToken, "new-access")
        XCTAssertEqual(try store.session()?.refreshToken, "new-refresh")

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(
            request.url.absoluteString,
            "https://\(environmentID).api.tcloudbasegateway.com/auth/v1/token"
        )
        XCTAssertEqual(request.method, "POST")
        let body = try XCTUnwrap(request.body)
        let decoded = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: body) as? [String: String]
        )
        XCTAssertEqual(decoded["grant_type"], "refresh_token")
        XCTAssertEqual(decoded["refresh_token"], "old-refresh")
    }

    func testRefreshWithoutStoredSessionFailsExplicitly() throws {
        let transport = FakeTransport(responses: [])
        let client = makeClient(transport: transport, store: InMemoryTokenStore())

        XCTAssertThrowsError(try client.refresh()) { error in
            XCTAssertEqual(error as? CloudAuthError, .notAuthenticated)
        }
        XCTAssertTrue(transport.requests.isEmpty, "没有本地会话就不该发出任何请求")
    }

    // MARK: ⑤ 登出：通知服务端撤销 + 清掉本地会话

    func testSignOutRevokesServerSessionAndClearsLocalSession() throws {
        let store = InMemoryTokenStore()
        try store.setSession(
            NoteSyncSession(
                accessToken: "access-aaa",
                refreshToken: "refresh-aaa",
                expiresIn: 7200,
                subject: "2108540229640167426"
            )
        )
        let transport = FakeTransport(responses: [CloudAuthHTTPResponse(status: 200, body: Data("{}".utf8))])
        let client = makeClient(transport: transport, store: store)

        try client.signOut()

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(
            request.url.absoluteString,
            "https://\(environmentID).api.tcloudbasegateway.com/auth/v1/revoke"
        )
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.headers["Authorization"], "Bearer access-aaa")
        let body = try XCTUnwrap(request.body)
        let decoded = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: body) as? [String: String]
        )
        XCTAssertEqual(decoded["refresh_token"], "refresh-aaa")

        XCTAssertNil(try store.session(), "登出后本地不许再留会话")
    }

    func testSignOutClearsLocalSessionEvenWhenServerRevokeFails() throws {
        let store = InMemoryTokenStore()
        try store.setSession(
            NoteSyncSession(
                accessToken: "access-aaa",
                refreshToken: "refresh-aaa",
                expiresIn: 7200,
                subject: "2108540229640167426"
            )
        )
        // 服务端撤销这一路返回 500 —— 本地会话仍必须清掉（离线登出）。
        let transport = FakeTransport(responses: [CloudAuthHTTPResponse(status: 500, body: Data())])
        let client = makeClient(transport: transport, store: store)

        try client.signOut()

        XCTAssertNil(try store.session())
    }

    // MARK: ⑥ 过期判断以**本地收令牌时刻**为基准

    func testSessionExpiryUsesLocalObtainTime() {
        let obtained = Date(timeIntervalSince1970: 1_700_000_000)
        let session = NoteSyncSession(
            accessToken: "a",
            refreshToken: "r",
            expiresIn: 7200,
            subject: "u",
            obtainedAt: obtained
        )

        XCTAssertEqual(session.expiresAt, obtained.addingTimeInterval(7200))
        XCTAssertFalse(session.isExpired(now: obtained.addingTimeInterval(7199)))
        XCTAssertTrue(session.isExpired(now: obtained.addingTimeInterval(7200)))
        // leeway：提前 60 s 就判过期（给刷新留余量）。
        XCTAssertTrue(session.isExpired(now: obtained.addingTimeInterval(7200 - 60), leeway: 60))
    }
}

// MARK: - 测试替身

/// 出网替身：按队列吐预设应答，并**记下发出过的每个请求**（形状复核用）。
private final class FakeTransport: CloudAuthTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var queued: [CloudAuthHTTPResponse]
    private var recorded: [CloudAuthHTTPRequest] = []

    init(responses: [CloudAuthHTTPResponse]) {
        self.queued = responses
    }

    var requests: [CloudAuthHTTPRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func send(_ request: CloudAuthHTTPRequest) throws -> CloudAuthHTTPResponse {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(request)
        guard !queued.isEmpty else {
            throw CloudAuthError.transport("no queued response")
        }
        return queued.removeFirst()
    }
}

/// 令牌存储替身：内存版，与 macOS 的 `KeychainNoteSyncTokenStore` 同一个抽象层。
private final class InMemoryTokenStore: NoteSyncTokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: NoteSyncSession?

    func setSession(_ session: NoteSyncSession) throws {
        lock.lock()
        defer { lock.unlock() }
        value = session
    }

    func session() throws -> NoteSyncSession? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func deleteSession() throws {
        lock.lock()
        defer { lock.unlock() }
        value = nil
    }
}
