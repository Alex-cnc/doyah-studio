import XCTest
import DoyahCore
import DoyahPlatform

/// `NFR-ALL-GATE-AI-007` ②（密钥不落配置文件 / 重启可取回 / 可明确清除）与
/// `NFR-ALL-GATE-SEC-001` 的**真实现**判据：跑在 `FileAgentSecretStore`（0600 文件后端）上，
/// 不是假件。为什么放平台目标：Core 不许 import Security / 文件权限 API，而这条要量的正是
/// 「文件在盘上的权限位」与「同一个目录里那份配置有没有密钥」。
final class AgentSecretStorageContractTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-secrets-\\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    private func permissions(_ url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }

    /// 密钥落在 0600 的独立文件里；**换一个实例读回**（= 重启）仍在；目录 0700。
    func testKeySurvivesRestartInA0600FileOutsideTheConfigurationFile() throws {
        let sentinel = "sk-platform-abcdef0123456789"
        try FileAgentSecretStore(directoryURL: directory).setAPIKey(sentinel)

        let secretsFile = directory.appendingPathComponent("secrets.json")
        XCTAssertEqual(try permissions(secretsFile) & 0o777, 0o600, "密钥文件必须 0600")
        XCTAssertEqual(try permissions(directory) & 0o777, 0o700, "目录必须 0700")

        let afterRestart = FileAgentSecretStore(directoryURL: directory)
        XCTAssertEqual(try afterRestart.apiKey(), sentinel, "重启后必须取得回")

        let raw = try String(contentsOf: secretsFile, encoding: .utf8)
        XCTAssertTrue(raw.contains(sentinel))
    }

    /// 同一个目录里的 `agent.json` 里找不到这把密钥，也找不到密钥字段。
    func testConfigurationFileInTheSameDirectoryHasNoKey() async throws {
        let sentinel = "sk-platform-abcdef0123456789"
        try FileAgentSecretStore(directoryURL: directory).setAPIKey(sentinel)
        try await AgentConfigurationStore(directoryURL: directory).save(.default)

        let raw = try String(contentsOf: directory.appendingPathComponent("agent.json"),
                             encoding: .utf8)
        XCTAssertFalse(raw.contains(sentinel), "配置里不许有密钥值")
        for forbidden in ["\"apiKey\"", "\"api_key\"", "\"password\"", "\"authorization\""] {
            XCTAssertFalse(raw.contains(forbidden), "配置里不许有 \(forbidden) 字段")
        }
    }

    /// 可明确清除：删掉之后重启读回是 `nil`（不是「读不到就当作空串」那种含糊）。
    func testDeleteIsExplicitAndSurvivesRestart() throws {
        let store = FileAgentSecretStore(directoryURL: directory)
        try store.setAPIKey("sk-to-be-removed")
        try store.deleteAPIKey()
        XCTAssertNil(try FileAgentSecretStore(directoryURL: directory).apiKey())
    }

    // MARK: - 多档（`FR-AGT-LINK-CHAN-001` ⑥ · 2026-11-08 beta1.1）

    /// 一档一把：同目录下两个 `entryKey` 互不覆盖；删一档不动另一档；老槽位 `agent.api-key` 仍可读。
    /// 覆盖范围：只判「条目隔离 + 删除隔离 + 老槽位兼容」；不判界面（那在 UI 用例里）。
    func testEachProfileKeepsItsOwnKeyAndDeletingOneLeavesTheOther() throws {
        let defaultStore = FileAgentSecretStore(directoryURL: directory)          // agent.api-key（老单档）
        let alpha = FileAgentSecretStore(directoryURL: directory,
                                         entryKey: AgentProfile.defaultSecretKey(for: "alpha"))
        let beta = FileAgentSecretStore(directoryURL: directory,
                                        entryKey: AgentProfile.defaultSecretKey(for: "beta"))

        try defaultStore.setAPIKey("sk-legacy-0001")
        try alpha.setAPIKey("sk-alpha-0002")
        try beta.setAPIKey("sk-beta-0003")

        XCTAssertEqual(try alpha.apiKey(), "sk-alpha-0002")
        XCTAssertEqual(try beta.apiKey(), "sk-beta-0003")
        XCTAssertEqual(try defaultStore.apiKey(), "sk-legacy-0001", "老槽位不许被新档挤掉")

        try alpha.deleteAPIKey()
        XCTAssertNil(try alpha.apiKey(), "删掉的那一档要真空")
        XCTAssertEqual(try beta.apiKey(), "sk-beta-0003", "删一档不许连坐另一档")
        XCTAssertEqual(try defaultStore.apiKey(), "sk-legacy-0001")

        // 反例：把 beta 的 key 写到默认实例上 ⇒ 必须有办法判出来（条目不同 = 值不同）
        try FileAgentSecretStore(directoryURL: directory).setAPIKey("sk-overwritten")
        XCTAssertEqual(try beta.apiKey(), "sk-beta-0003", "默认实例写盘不许覆盖档位条目")
    }
}
