import XCTest
@testable import DoyahCore

/// `FR-AI-30` ①（回边：失败分级与重试 / 退避）—— 提案 `0009` B 片的四条机械判据。
///
/// 纪律：**不读时钟、不真等**（休眠器注入）；**不发真请求**（假客户端 / 假传输）。
final class LLMRetryTests: XCTestCase {

    // MARK: - 夹具

    /// 脚本化假客户端：按序吐出预设结局，并记下每次收到的请求。
    private final class ScriptedClient: LLMClient, @unchecked Sendable {
        private let lock = NSLock()
        private var script: [Result<LLMResponse, LLMError>]
        private var seen: [LLMRequest] = []

        init(_ script: [Result<LLMResponse, LLMError>]) {
            self.script = script
        }

        func complete(_ request: LLMRequest) async throws -> LLMResponse {
            lock.lock()
            seen.append(request)
            guard !script.isEmpty else {
                lock.unlock()
                throw LLMError.transport("脚本已用尽")
            }
            let next = script.removeFirst()
            lock.unlock()
            switch next {
            case .success(let response): return response
            case .failure(let error): throw error
            }
        }

        var attempts: Int {
            lock.lock(); defer { lock.unlock() }
            return seen.count
        }
    }

    /// 每次都失败的假客户端（用于上限触达）。
    private final class AlwaysFailingClient: LLMClient, @unchecked Sendable {
        private let lock = NSLock()
        private let error: LLMError
        private var seen = 0

        init(_ error: LLMError) { self.error = error }

        func complete(_ request: LLMRequest) async throws -> LLMResponse {
            lock.lock(); seen += 1; lock.unlock()
            throw error
        }

        var attempts: Int {
            lock.lock(); defer { lock.unlock() }
            return seen
        }
    }

    /// 休眠记录器：策略表要求等多久，这里就记多久（不真睡）。
    private final class SleepRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var slept: [TimeInterval] = []

        func record(_ seconds: TimeInterval) {
            lock.lock(); slept.append(seconds); lock.unlock()
        }

        var recorded: [TimeInterval] {
            lock.lock(); defer { lock.unlock() }
            return slept
        }
    }

    /// 记录 URLRequest 的假传输：`statuses` 里 `0` 表示「连接断开」。
    private final class RecordingTransport: HTTPTransport, @unchecked Sendable {
        static let successBody = Data(
            #"{"model":"m","choices":[{"message":{"content":"ok"},"finish_reason":"stop"}],"usage":{"total_tokens":1}}"#.utf8
        )

        private let lock = NSLock()
        private var statuses: [Int]
        private var requests: [URLRequest] = []

        init(_ statuses: [Int]) { self.statuses = statuses }

        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            lock.lock()
            requests.append(request)
            let status = statuses.isEmpty ? 200 : statuses.removeFirst()
            lock.unlock()

            if status == 0 { throw URLError(.cannotConnectToHost) }
            let body = status == 200 ? Self.successBody : Data(#"{"error":{"message":"boom"}}"#.utf8)
            let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                           httpVersion: "HTTP/1.1", headerFields: nil)!
            return (body, response)
        }

        var seen: [URLRequest] {
            lock.lock(); defer { lock.unlock() }
            return requests
        }
    }

    private static let ok = LLMResponse(text: "ok", model: "m", usage: .unknown, finishReason: "stop")

    private func makeRequest(apiKey: String? = "sk-test") -> LLMRequest {
        LLMRequest(endpoint: URL(string: "http://127.0.0.1:11434/v1")!,
                   model: "local-model",
                   apiKey: apiKey,
                   systemPrompt: "s",
                   userPrompt: "u")
    }

    // MARK: - 判据 1：429 → 500 → 断连 ⇒ 尝试 4 次、休眠序列 = 策略表

    func testRetryableSequenceAttemptsFourTimesAndSleepsFollowTheTable() async throws {
        let client = ScriptedClient([
            .failure(.httpStatus(code: 429, message: "slow down")),
            .failure(.httpStatus(code: 500, message: "boom")),
            .failure(.transport("connection reset")),
            .success(Self.ok)
        ])
        let sleeps = SleepRecorder()
        let retrying = RetryingLLMClient(base: client,
                                        sleeper: { await sleeps.record($0) })

        let response = try await retrying.complete(makeRequest())

        XCTAssertEqual(response.text, "ok")
        XCTAssertEqual(client.attempts, 4, "1 次初试 + 3 次重试")
        XCTAssertEqual(sleeps.recorded, [0.5, 2, 2], "休眠序列必须逐项等于策略表（超出表长用表尾）")
    }

    // MARK: - 判据 2：上限触达 ⇒ 如实停（报「重试 N 次后仍失败」+ 最后一次原因）

    func testExhaustionStopsHonestlyAndCarriesTheLastReason() async throws {
        let failure = LLMError.httpStatus(code: 503, message: "unavailable")
        let client = AlwaysFailingClient(failure)
        let sleeps = SleepRecorder()
        let retrying = RetryingLLMClient(base: client, sleeper: { await sleeps.record($0) })

        do {
            _ = try await retrying.complete(makeRequest())
            XCTFail("上限触达时必须抛错，不得返回半成品")
        } catch let error as LLMRetryExhausted {
            XCTAssertEqual(error.attempts, 4)
            XCTAssertEqual(error.retries, 3)
            XCTAssertEqual(error.lastError, failure, "最后一次原因要原样带上，不许吞")
            let text = error.errorDescription ?? ""
            XCTAssertTrue(text.contains("重试 3 次后仍失败"), "实际文案：\(text)")
            XCTAssertTrue(text.contains("503"), "实际文案：\(text)")
        }

        XCTAssertEqual(client.attempts, 4)
        XCTAssertEqual(sleeps.recorded, [0.5, 2, 2])
    }

    // MARK: - 判据 3：403 / 配额 ⇒ 一次都不重试

    func testForbiddenAndQuotaAreNeverRetried() async throws {
        for failure in [LLMError.forbidden("闸门拒绝"), LLMError.quotaExceeded("今日配额已用尽")] {
            let client = AlwaysFailingClient(failure)
            let sleeps = SleepRecorder()
            let retrying = RetryingLLMClient(base: client, sleeper: { await sleeps.record($0) })

            do {
                _ = try await retrying.complete(makeRequest())
                XCTFail("不可重试的失败不该返回响应")
            } catch let error as LLMError {
                XCTAssertEqual(error, failure, "不可重试档要原样抛出，不包成上限触达")
            }

            XCTAssertEqual(client.attempts, 1, "\(failure) 不该被重试")
            XCTAssertEqual(sleeps.recorded, [])
        }
    }

    // MARK: - 判据 4：本地端点（免 key）重试时每次都无 Authorization 头

    func testRetriesAgainstLocalEndpointCarryNoAuthorizationHeader() async throws {
        let transport = RecordingTransport([500, 429, 200])
        let base = OpenAICompatibleClient(transport: transport)
        let retrying = RetryingLLMClient(base: base, sleeper: { _ in })

        let response = try await retrying.complete(makeRequest(apiKey: nil))

        XCTAssertEqual(response.text, "ok")
        XCTAssertEqual(transport.seen.count, 3, "两次失败 + 一次成功")
        for (index, request) in transport.seen.enumerated() {
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"),
                         "第 \(index + 1) 次尝试带了 Authorization —— 本地端点免 key 被重试破坏了")
        }
    }
}
