import XCTest
@testable import DoyahCore

/// 契约 §3.4.8 / §6.3 的判据：**令牌自动续期**。
///
/// 四件事各一条用例（缺一条就还是「每次同步报 token 过期」）：
///   ① 未到期不续期（续期会被服务端当成轮换，白打一次）；
///   ② 到点（调用方给 60 秒余量）先续期再取令牌；
///   ③ 业务面 401 ⇒ 续期一次并重放**一次**，第二次仍 401 抛出、不再续期；
///   ④ 并发同时过期 ⇒ 续期**只发生一次**（单飞）。
final class NoteSyncTokenRefreshTests: XCTestCase {

    // MARK: 假传输

    /// 按顺序回放应答；记录每次请求（含认证头），线程安全。
    private final class RecordingTransport: CloudAuthTransport, @unchecked Sendable {
        private let lock = NSLock()
        private var responses: [CloudAuthHTTPResponse]
        private(set) var requests: [CloudAuthHTTPRequest] = []

        init(_ responses: [CloudAuthHTTPResponse]) { self.responses = responses }

        func send(_ request: CloudAuthHTTPRequest) throws -> CloudAuthHTTPResponse {
            lock.lock()
            defer { lock.unlock() }
            requests.append(request)
            if responses.count > 1 {
                return responses.removeFirst()
            }
            return responses[0]
        }

        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return requests.count
        }

        var authorizationHeaders: [String] {
            lock.lock()
            defer { lock.unlock() }
            return requests.compactMap { $0.headers["Authorization"] }
        }
    }

    /// 记录续期次数，并「换发」一个新令牌。
    private final class TokenBox: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var refreshes = 0
        var token: String

        init(_ token: String) { self.token = token }

        func refresh() -> String {
            lock.lock()
            defer { lock.unlock() }
            refreshes += 1
            token = "access-\(refreshes)"
            return token
        }

        var refreshCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return refreshes
        }
    }

    private func response(_ status: Int, body: String = "[]") -> CloudAuthHTTPResponse {
        CloudAuthHTTPResponse(status: status, body: Data(body.utf8))
    }

    private func makeService(
        transport: CloudAuthTransport,
        box: TokenBox,
        expiring: Bool,
        refreshDelayMicros: UInt32 = 0
    ) throws -> CloudSyncService {
        try CloudSyncService(
            endpoints: CloudSyncEndpoints(environmentID: "doyah-notes-test-env"),
            transport: transport,
            stateStore: MemoryCloudSyncStateStore(),
            tokenProvider: { box.token },
            tokenRefresher: {
                if refreshDelayMicros > 0 { usleep(refreshDelayMicros) }
                return box.refresh()
            },
            tokenExpiring: { expiring },
            now: { Date(timeIntervalSince1970: 1_790_000_000) }
        )
    }

    // MARK: ① 未到期不续期

    func testFreshTokenDoesNotRefresh() throws {
        let transport = RecordingTransport([response(200)])
        let box = TokenBox("access-0")
        let service = try makeService(transport: transport, box: box, expiring: false)

        _ = try service.pull()

        XCTAssertEqual(box.refreshCount, 0, "未到期时不该续期（续期的副作用是服务端令牌轮换）")
        XCTAssertEqual(transport.authorizationHeaders, ["Bearer access-0"])
    }

    // MARK: ② 到点先续期

    func testExpiringTokenRefreshesBeforeRequest() throws {
        let transport = RecordingTransport([response(200)])
        let box = TokenBox("access-0")
        let service = try makeService(transport: transport, box: box, expiring: true)

        _ = try service.pull()

        XCTAssertEqual(box.refreshCount, 1)
        XCTAssertEqual(transport.authorizationHeaders, ["Bearer access-1"],
                       "业务请求必须用续期后的新令牌，不能拿旧令牌先撞一次 401")
    }

    // MARK: ③ 401 续期一次并重放一次

    func testUnauthorizedRetriesOnceWithFreshToken() throws {
        let transport = RecordingTransport([response(401), response(200)])
        let box = TokenBox("access-0")
        // expiring=false：模拟「本地时钟还没到点，但服务端已经判过期」
        let service = try makeService(transport: transport, box: box, expiring: false)

        let page = try service.fetchPage(token: "stale")

        XCTAssertEqual(page.count, 0)
        XCTAssertEqual(box.refreshCount, 1)
        XCTAssertEqual(transport.count, 2, "401 之后必须重放一次")
        XCTAssertEqual(transport.authorizationHeaders.last, "Bearer access-1")
    }

    func testSecondUnauthorizedDoesNotRefreshAgain() throws {
        let transport = RecordingTransport([response(401), response(401)])
        let box = TokenBox("access-0")
        let service = try makeService(transport: transport, box: box, expiring: false)

        XCTAssertThrowsError(try service.fetchPage(token: "stale")) { error in
            guard case CloudSyncError.server(_, let status) = error else {
                return XCTFail("应抛 server(401)，实得 \(error)")
            }
            XCTAssertEqual(status, 401)
        }
        XCTAssertEqual(transport.count, 2, "最多重放一次，不做第三次")
        XCTAssertEqual(box.refreshCount, 1, "第二次 401 不再续期 —— 那是「需要重新登录」")
    }

    // MARK: ④ 并发单飞

    func testConcurrentExpiryRefreshesOnce() throws {
        let transport = RecordingTransport([response(200)])
        let box = TokenBox("access-0")
        let service = try makeService(
            transport: transport, box: box, expiring: true, refreshDelayMicros: 60_000
        )

        let group = DispatchGroup()
        for _ in 0..<8 {
            DispatchQueue.global().async(group: group) {
                _ = try? service.pull()
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 10), .success)

        XCTAssertEqual(box.refreshCount, 1, "8 个并发请求同时过期，续期必须只发生一次")
    }
}
