import XCTest
@testable import DoyahCore

/// `FR-AGT-LINK-CHAN-003` 的**配置面**判据（凭据放哪儿、怎么算「配了」）。
///
/// 传输层不在这里判（那要真 AppID/Secret 才能跑）；这里钉的是三条不该被改掉的纪律：
/// ① **Secret 只进不出**：对外只有「长度 + 尾 4」，本体只在 `secret(for:)` 一个口子；
/// ② **配置文件不含 Secret**（按字节复核）；
/// ③ **校验失败什么都不落盘**（不留半截凭据）。
final class AgentIMCredentialsTests: XCTestCase {

    private var root: URL!
    private var secrets: InMemoryIMSecretStore!
    private var store: AgentIMCredentialStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dsh-im-creds-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        secrets = InMemoryIMSecretStore()
        store = AgentIMCredentialStore(directoryURL: root, secretStore: secrets)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    // ① 什么都没配：不假装配过（AppID 与 Secret 各自独立报）
    func testUnconfiguredStatusIsHonest() throws {
        let status = try store.status(for: .qq)
        XCTAssertNil(status.appID)
        XCTAssertFalse(status.secretConfigured)
        XCTAssertNil(status.secretLength)
        XCTAssertNil(status.secretTail)
        XCTAssertFalse(status.isComplete)
    }

    // ② 存进去再读：AppID 明文读回；Secret 只给长度与尾 4
    func testSaveThenStatusExposesOnlyTail() throws {
        let status = try store.save(appID: "102345678", secret: "s3cr3t-value-8891", for: .qq)
        XCTAssertEqual(status.appID, "102345678")
        XCTAssertTrue(status.secretConfigured)
        XCTAssertEqual(status.secretLength, "s3cr3t-value-8891".count)
        XCTAssertEqual(status.secretTail, "8891")
        XCTAssertTrue(status.isComplete)
        // 本体没在 status 里出现（尾 4 只有 4 位）
        XCTAssertNotEqual(status.secretTail, "s3cr3t-value-8891")
    }

    // ③ 配置文件**只有 AppID**：按字节复核，里面找不到 Secret
    func testConfigFileNeverContainsSecret() throws {
        let secret = "never-write-me-4821"
        _ = try store.save(appID: "102345678", secret: secret, for: .qq)
        let text = try String(contentsOf: store.fileURL(for: .qq), encoding: .utf8)
        XCTAssertFalse(text.contains(secret))
        XCTAssertFalse(text.contains("4821"))
        XCTAssertTrue(text.contains("102345678"))
    }

    // ④ Secret 传 nil = 只改 AppID，既有的那把不动（面板留空的语义）
    func testNilSecretKeepsExistingSecret() throws {
        _ = try store.save(appID: "100001", secret: "keep-me-0001", for: .qq)
        let writesAfterFirst = secrets.writeCount
        let status = try store.save(appID: "100002", secret: nil, for: .qq)
        XCTAssertEqual(status.appID, "100002")
        XCTAssertEqual(try store.secret(for: .qq), "keep-me-0001")
        XCTAssertEqual(secrets.writeCount, writesAfterFirst, "传 nil 不该再写一次密钥")
    }

    // ⑤ 清除：密钥与配置文件一起清（不留「看着配过、其实连不上」的半截状态）
    func testClearRemovesSecretAndFile() throws {
        _ = try store.save(appID: "100001", secret: "abc-0001", for: .qq)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL(for: .qq).path))
        try store.clear(for: .qq)
        XCTAssertNil(try store.secret(for: .qq))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL(for: .qq).path))
        XCTAssertFalse(try store.status(for: .qq).isComplete)
    }

    // ⑥ AppID 粘错（把 Secret 粘进 AppID 那一格）：被拒，且**一个字节都不落** ——
    //    Secret 也不许先写进去（顺序错了就会留下「配了一半」）
    func testNonNumericAppIDIsRejectedWithoutWritingAnything() throws {
        XCTAssertThrowsError(try store.save(appID: "abcdEFGH1234", secret: "abc-0001", for: .qq)) { error in
            XCTAssertEqual(error as? AgentIMCredentialProblem, .appIDNotNumeric)
        }
        XCTAssertNil(try store.secret(for: .qq))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL(for: .qq).path))
    }

    // ⑦ 首尾空白 / 换行被规范化（粘贴与 `echo` 是常态，不该因此报错）
    func testAppIDAndSecretAreNormalized() throws {
        let status = try store.save(appID: "  100001\n", secret: "abc-0001\n", for: .qq)
        XCTAssertEqual(status.appID, "100001")
        XCTAssertEqual(try store.secret(for: .qq), "abc-0001")
    }

    // ⑧ Secret 内部有空白：被拒（多半是粘贴带进来的；存下去只会在握手时莫名失败）
    func testSecretWithInnerWhitespaceIsRejected() throws {
        XCTAssertThrowsError(try store.save(appID: "100001", secret: "abc 0001", for: .qq)) { error in
            XCTAssertEqual(error as? AgentIMCredentialProblem, .secretContainsWhitespace)
        }
        XCTAssertNil(try store.secret(for: .qq))
    }

    // ⑨ 空 Secret 与空 AppID 各自有原因（面板要能说清是哪一格没填）
    func testEmptyInputsHaveDistinctReasons() {
        XCTAssertThrowsError(try AgentIMCredentialStore.normalizedAppID("   ")) { error in
            XCTAssertEqual(error as? AgentIMCredentialProblem, .appIDEmpty)
        }
        XCTAssertThrowsError(try AgentIMCredentialStore.normalizedSecret(" \n ")) { error in
            XCTAssertEqual(error as? AgentIMCredentialProblem, .secretEmpty)
        }
    }

    // ⑩ 盘上手改坏（AppID 写成空串）⇒ 当作没配，不把空串当凭据
    func testEmptyAppIDOnDiskCountsAsUnconfigured() throws {
        _ = try store.save(appID: "100001", secret: "abc-0001", for: .qq)
        let fileURL = store.fileURL(for: .qq)
        try Data("{\"appID\":\"   \"}".utf8).write(to: fileURL, options: .atomic)
        XCTAssertNil(try store.status(for: .qq).appID)
    }
}

/// 判据用的内存密钥存储（不进钥匙串：判据不该依赖签名与授权）。
private final class InMemoryIMSecretStore: AgentIMSecretStore, @unchecked Sendable {

    private let lock = NSLock()
    private var values: [AgentIMChannelCredentialKind: String] = [:]
    private var writes = 0

    var writeCount: Int {
        lock.lock(); defer { lock.unlock() }
        return writes
    }

    func setSecret(_ secret: String, for kind: AgentIMChannelCredentialKind) throws {
        lock.lock(); defer { lock.unlock() }
        values[kind] = secret
        writes += 1
    }

    func secret(for kind: AgentIMChannelCredentialKind) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return values[kind]
    }

    func deleteSecret(for kind: AgentIMChannelCredentialKind) throws {
        lock.lock(); defer { lock.unlock() }
        values.removeValue(forKey: kind)
    }
}
