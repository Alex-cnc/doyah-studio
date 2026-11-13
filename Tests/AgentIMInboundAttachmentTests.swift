import XCTest
@testable import DoyahCore

/// `T-3.25-13` / `T-3.25-14` / `T-3.25-15`：
/// 入站附件（解析 + 落地 + 回执）、主动消息失败三档、最小命令层。
final class AgentIMInboundAttachmentTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dsh-im-att-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    // MARK: - 解析

    func testParsesAttachmentsFromFrame() {
        let data: [String: Any] = [
            "attachments": [
                ["content_type": "image/png", "filename": "图.png", "size": 2048, "url": "https://x/1.png"],
                ["content_type": "text/plain", "filename": "a.txt", "size": 10, "url": "file:///etc/passwd"]
            ]
        ]
        let parsed = AgentIMInboundAttachmentParser.parse(data)
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed[0].filename, "图.png")
        XCTAssertNil(parsed[0].note)
        XCTAssertEqual(parsed[1].note, "unsupportedScheme", "`file://` 一律不取（外部输入不许读本机文件）")
        XCTAssertNil(parsed[1].remoteURL)
    }

    func testFilenameIsSanitizedAgainstTraversal() {
        XCTAssertEqual(AgentIMInboundAttachmentParser.sanitizedFilename("../../etc/passwd"), "passwd")
        XCTAssertEqual(AgentIMInboundAttachmentParser.sanitizedFilename("a/../b"), "b")
        XCTAssertEqual(AgentIMInboundAttachmentParser.sanitizedFilename("   "), "attachment")
    }

    func testStoredAttachmentLandsWithOwnerOnlyPermissions() async throws {
        let store = AgentIMInboundAttachmentStore(directory: root) { _ in Data("hello".utf8) }
        let stored = await store.store([AgentIMInboundAttachment(filename: "a.txt",
                                                                remoteURL: URL(string: "https://x/a.txt"))])
        let path = try XCTUnwrap(stored.first?.localPath)
        XCTAssertTrue(path.hasPrefix(root.path))
        let attrs = try FileManager.default.attributesOfItem(atPath: path)
        let permissions = (attrs[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(permissions, 0o600, "附件落盘只许本人读写")
    }

    func testDownloadFailureIsReportedInReceipt() async {
        struct Boom: Error {}
        let store = AgentIMInboundAttachmentStore(directory: root) { _ in throw Boom() }
        let stored = await store.store([AgentIMInboundAttachment(filename: "b.png",
                                                                remoteURL: URL(string: "https://x/b.png"))])
        XCTAssertNil(stored.first?.localPath)
        XCTAssertEqual(stored.first?.note, "downloadFailed")
        let receipt = AgentIMAttachmentReceipt.line(for: stored, language: .simplifiedChinese)
        XCTAssertTrue(receipt?.contains("b.png") == true)
        XCTAssertTrue(receipt?.contains("没取到") == true, "取不到也要说，不许静默")
    }

    func testOversizeAttachmentIsNotDownloaded() async {
        let store = AgentIMInboundAttachmentStore(directory: root, maxBytes: 4) { _ in Data(repeating: 1, count: 100) }
        let stored = await store.store([AgentIMInboundAttachment(filename: "big.bin",
                                                                remoteURL: URL(string: "https://x/big"))])
        XCTAssertEqual(stored.first?.note, "tooLarge")
    }

    func testReceiptListsEveryFileWithSize() async {
        let store = AgentIMInboundAttachmentStore(directory: root) { _ in Data(repeating: 0, count: 2048) }
        let stored = await store.store([
            AgentIMInboundAttachment(filename: "a.png", remoteURL: URL(string: "https://x/a")),
            AgentIMInboundAttachment(filename: "b.pdf", remoteURL: URL(string: "https://x/b"))
        ])
        let receipt = try? XCTUnwrap(AgentIMAttachmentReceipt.line(for: stored, language: .simplifiedChinese))
        XCTAssertTrue(receipt?.contains("2") == true)
        XCTAssertTrue(receipt?.contains("a.png") == true)
        XCTAssertTrue(receipt?.contains("2.0 KB") == true)
    }

    // MARK: - 主动消息失败三档（`T-3.25-14`）

    func testFailureClassesAreDistinct() {
        XCTAssertEqual(AgentIMDeliveryFailure.classify(status: 400, code: "40093002"), .quota(code: "40093002"))
        XCTAssertEqual(AgentIMDeliveryFailure.classify(status: 500, code: "40093001"), .transient(code: "40093001"))
        XCTAssertEqual(AgentIMDeliveryFailure.classify(status: nil, code: nil), .network)
        XCTAssertEqual(AgentIMDeliveryFailure.classify(status: 403, code: "123"), .other(code: "123"))
    }

    func testQuotaIsPermanentAndNotRetried() {
        XCTAssertTrue(AgentIMDeliveryFailure.quota(code: "40093002").isPermanent)
        XCTAssertFalse(AgentIMDeliveryFailure.quota(code: "40093002").shouldRetry)
        XCTAssertTrue(AgentIMDeliveryFailure.transient(code: "40093001").shouldRetry)
        XCTAssertTrue(AgentIMDeliveryFailure.network.shouldRetry)
    }

    func testOutcomeMapsToFailureClass() {
        XCTAssertNil(AgentIMDeliveryFailure.classify(AgentIMSendOutcome.delivered(messageID: "m")))
        XCTAssertEqual(AgentIMDeliveryFailure.classify(.networkFailed), .network)
        XCTAssertEqual(AgentIMDeliveryFailure.classify(.rateLimited), .quota(code: "rateLimited"))
        XCTAssertEqual(AgentIMDeliveryFailure.classify(.rejected(status: 400, code: "40093002")),
                       .quota(code: "40093002"))
    }

    // MARK: - 命令层（`T-3.25-15`）

    func testStopAndStatusAreRecognised() {
        XCTAssertEqual(AgentIMCommand.parse("/stop"), .stop)
        XCTAssertEqual(AgentIMCommand.parse(" /STOP "), .stop)
        XCTAssertEqual(AgentIMCommand.parse("/status"), .status)
        XCTAssertEqual(AgentIMCommand.parse("／status"), .status, "全角斜杠也认（手机输入法常见）")
    }

    func testWholeWordOnly() {
        XCTAssertEqual(AgentIMCommand.parse("/stopwatch"), .unknown("stopwatch"),
                       "半个词不算命令 —— 打错一个字不能误停")
        XCTAssertNil(AgentIMCommand.parse("stop"), "没有斜杠就是普通消息")
        XCTAssertNil(AgentIMCommand.parse("帮我 /stop 一下？"), "句中出现的斜杠不抢话")
    }

    func testUnknownCommandIsNamedBack() {
        XCTAssertEqual(AgentIMCommand.parse("/restart"), .unknown("restart"))
    }

    func testBotSuffixIsTolerated() {
        XCTAssertEqual(AgentIMCommand.parse("/stop@doyahbot", botSuffix: "DoyahBot"), .stop)
        XCTAssertEqual(AgentIMCommand.parse("/stop@other", botSuffix: "DoyahBot"), .unknown("stop@other"))
    }
}
