import XCTest
@testable import DoyahCore

/// `T-3.25-12`：**原生媒体出站** —— 先上传换句柄再发，三类失败分开，链接不代下载（需求 ⑫）。
final class AgentIMQQMediaTests: XCTestCase {

    private final class FakeClient: AgentIMMediaHTTPClient, @unchecked Sendable {
        private let lock = NSLock()
        private var _uploads: [Data] = []
        private var _payloads: [String] = []
        private let uploadResponses: [AgentIMHTTPResponse]
        private let sendResponse: AgentIMHTTPResponse
        private let throwsOnUpload: Bool
        private var cursor = 0

        init(uploadResponses: [AgentIMHTTPResponse],
             sendResponse: AgentIMHTTPResponse = AgentIMHTTPResponse(status: 200, body: #"{"id":"m-1"}"#),
             throwsOnUpload: Bool = false) {
            self.uploadResponses = uploadResponses
            self.sendResponse = sendResponse
            self.throwsOnUpload = throwsOnUpload
        }

        var uploads: [Data] { lock.lock(); defer { lock.unlock() }; return _uploads }
        var payloads: [String] { lock.lock(); defer { lock.unlock() }; return _payloads }

        func postMultipart(_ url: URL, body: Data, contentType: String,
                           headers: [String: String]) async throws -> AgentIMHTTPResponse {
            lock.lock()
            _uploads.append(body)
            let index = min(cursor, uploadResponses.count - 1)
            cursor += 1
            lock.unlock()
            if throwsOnUpload { throw URLError(.cannotConnectToHost) }
            return uploadResponses[index]
        }

        func post(_ url: URL, payload: String, headers: [String: String]) async throws -> AgentIMHTTPResponse {
            lock.lock(); _payloads.append(payload); lock.unlock()
            return sendResponse
        }
    }

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dsh-im-media-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    private func makeFile(_ name: String, bytes: Int = 32) throws -> String {
        let url = root.appendingPathComponent(name)
        try Data(repeating: 7, count: bytes).write(to: url)
        return url.path
    }

    private func sender(_ client: FakeClient, retries: Bool = true) -> AgentIMQQMediaSender {
        AgentIMQQMediaSender(
            client: client,
            environment: .sandbox,
            sequences: AgentIMReplySeqLedger(directory: root),
            token: { AgentIMQQToken(value: "tok", expiresIn: 7200, obtainedAt: Date()) },
            retriesTransient: retries,
            retryDelay: 0)
    }

    private let target = AgentIMOutboundTarget(kind: .c2c, openID: "user-1")

    func testImageUploadsThenSendsTypeSevenWithFileInfo() async throws {
        let client = FakeClient(uploadResponses: [AgentIMHTTPResponse(status: 200, body: #"{"file_info":"fi-abc"}"#)])
        let outcome = await sender(client).send(path: try makeFile("a.png"),
                                               target: target, entryID: "e1", replyTo: "msg-1")
        XCTAssertTrue(outcome.isDelivered, "\(outcome)")
        XCTAssertEqual(client.uploads.count, 1)
        let payload = try XCTUnwrap(ProvisionerSupport.jsonObject(try XCTUnwrap(client.payloads.first)))
        XCTAssertEqual(payload["msg_type"] as? Int, 7)
        let media = try XCTUnwrap(payload["media"] as? [String: Any])
        XCTAssertEqual(media["file_info"] as? String, "fi-abc")
    }

    func testMultipartCarriesFileTypeAndFileName() async throws {
        let client = FakeClient(uploadResponses: [AgentIMHTTPResponse(status: 200, body: #"{"file_info":"fi"}"#)])
        _ = await sender(client).send(path: try makeFile("报告.pdf"),
                                      target: target, entryID: "e2", replyTo: nil)
        let body = String(decoding: try XCTUnwrap(client.uploads.first), as: UTF8.self)
        XCTAssertTrue(body.contains("name=\"file_type\""), body)
        XCTAssertTrue(body.contains("4"), "pdf 按文件类型（4）发")
        XCTAssertTrue(body.contains("报告.pdf"), "文件名要原样带上")
        XCTAssertTrue(body.contains("name=\"file\""))
    }

    func testQuotaCodeIsNotRetried() async throws {
        let client = FakeClient(uploadResponses: [
            AgentIMHTTPResponse(status: 400, body: #"{"code":40093002,"message":"quota"}"#)
        ])
        let outcome = await sender(client).send(path: try makeFile("a.png"),
                                               target: target, entryID: "e3", replyTo: nil)
        XCTAssertEqual(outcome, .rateLimited, "当日配额用尽要单独一档，且不许重试")
        XCTAssertEqual(client.uploads.count, 1, "配额失败重试也没用 —— 只许打一次")
        XCTAssertTrue(client.payloads.isEmpty, "上传都没成，不许再发消息")
    }

    func testTransientCodeIsRetriedExactlyOnce() async throws {
        let client = FakeClient(uploadResponses: [
            AgentIMHTTPResponse(status: 500, body: #"{"code":40093001,"message":"chunk failed"}"#),
            AgentIMHTTPResponse(status: 200, body: #"{"file_info":"fi-2"}"#)
        ])
        let outcome = await sender(client).send(path: try makeFile("a.png"),
                                               target: target, entryID: "e4", replyTo: nil)
        XCTAssertTrue(outcome.isDelivered, "\(outcome)")
        XCTAssertEqual(client.uploads.count, 2, "瞬时失败重试一次，不是无限重试")
    }

    func testNetworkFailureIsItsOwnClass() async throws {
        let client = FakeClient(uploadResponses: [AgentIMHTTPResponse(status: 200, body: "{}")],
                                throwsOnUpload: true)
        let outcome = await sender(client).send(path: try makeFile("a.png"),
                                               target: target, entryID: "e5", replyTo: nil)
        XCTAssertEqual(outcome, .networkFailed)
    }

    func testLinkIsRefusedWithoutAnyRequest() async {
        let client = FakeClient(uploadResponses: [AgentIMHTTPResponse(status: 200, body: "{}")])
        let outcome = await sender(client).send(path: "https://example.com/a.png",
                                               target: target, entryID: "e6", replyTo: nil)
        XCTAssertEqual(outcome, .notReady(code: "linkNotAllowed"),
                       "链接不代下载 —— 这是需求 ⑫ 的负例")
        XCTAssertEqual(client.uploads.count, 0, "拒收要在出网之前")
    }

    func testMissingFileIsReportedNotSilentlySkipped() async {
        let client = FakeClient(uploadResponses: [AgentIMHTTPResponse(status: 200, body: "{}")])
        let outcome = await sender(client).send(path: root.appendingPathComponent("nope.png").path,
                                               target: target, entryID: "e7", replyTo: nil)
        XCTAssertEqual(outcome, .notReady(code: "mediaUnreadable"))
        XCTAssertEqual(client.uploads.count, 0)
    }

    func testKindIsInferredFromExtension() {
        XCTAssertEqual(AgentIMMediaKind.inferred(fromPath: "a.PNG"), .image)
        XCTAssertEqual(AgentIMMediaKind.inferred(fromPath: "a.mp4"), .video)
        XCTAssertEqual(AgentIMMediaKind.inferred(fromPath: "a.mp3"), .voice)
        XCTAssertEqual(AgentIMMediaKind.inferred(fromPath: "a.bin"), .file)
    }
}
