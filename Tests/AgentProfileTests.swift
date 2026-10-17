import XCTest
@testable import DoyahCore

/// 模型**多档**（`FR-AI-32`）的判据。
///
/// 由头（人类主人 2026-10-17 原话）：「模型接入这里要修改：可以接入多个模型，目前看是不是只能配置一个」。
final class AgentProfileTests: XCTestCase {

    private func makeTwoProfileConfiguration() -> AgentConfiguration {
        let local = AgentProfile(id: "local", name: "local", presetID: "ollama",
                                 endpoint: "http://127.0.0.1:11434/v1", model: "qwen2.5:7b")
        let cloud = AgentProfile(id: "cloud", name: "cloud", presetID: "deepseek",
                                 endpoint: "https://api.deepseek.com/v1", model: "deepseek-v4-pro")
        return AgentConfiguration(isEnabled: true, profiles: [local, cloud], activeProfileID: "local")
    }

    /// ① 两档并存，切换当前档 ⇒ 镜像（端点 / 模型）跟着变。
    func testTwoProfilesCoexistAndSwitchingMovesTheMirrors() {
        var configuration = makeTwoProfileConfiguration()
        XCTAssertEqual(configuration.profiles.count, 2)
        XCTAssertEqual(configuration.model, "qwen2.5:7b", "当前档 = local")
        XCTAssertTrue(configuration.setActiveProfile(id: "cloud"))
        XCTAssertEqual(configuration.model, "deepseek-v4-pro", "切档后模型名跟着换")
        XCTAssertEqual(configuration.endpoint, "https://api.deepseek.com/v1")
        XCTAssertFalse(configuration.setActiveProfile(id: "不存在"), "切到不存在的档 ⇒ 拒绝")
        XCTAssertEqual(configuration.model, "deepseek-v4-pro", "拒绝后当前档不许被动过")
    }

    /// ② 改当前档**不动**别档（各档独立）。
    func testEditingOneProfileDoesNotTouchTheOther() {
        var configuration = makeTwoProfileConfiguration()
        var edited = configuration.activeProfile!
        edited.model = "qwen2.5:14b"
        configuration.updateProfile(edited)
        XCTAssertEqual(configuration.profiles.first { $0.id == "cloud" }?.model, "deepseek-v4-pro",
                       "改 local 档不许动 cloud 档")
        XCTAssertEqual(configuration.model, "qwen2.5:14b")
    }

    /// ③ 老 `agent.json`（只有一组端点 / 模型）⇒ **原地迁移成第 1 档**，且沿用旧条目键（已存的 key 不丢）。
    func testLegacyConfigurationMigratesIntoOneProfileKeepingTheLegacySecretKey() throws {
        let legacy = #"{"isEnabled":true,"endpoint":"https://api.deepseek.com/v1","model":"deepseek-v4-pro","timeoutSeconds":42}"#
        let configuration = try JSONDecoder().decode(AgentConfiguration.self, from: Data(legacy.utf8))
        XCTAssertEqual(configuration.profiles.count, 1, "老配置 = 一档")
        XCTAssertEqual(configuration.activeProfile?.id, "default")
        XCTAssertEqual(configuration.model, "deepseek-v4-pro", "端点 / 模型一个字都不许丢")
        XCTAssertEqual(configuration.timeoutSeconds, 42)
        XCTAssertEqual(configuration.activeProfile?.secretKey, AgentProfile.legacySecretKey,
                       "迁移来的档必须沿用旧条目键 agent.api-key —— 否则用户已存的密钥读不回来")
    }

    /// ④ 新形状往返：档清单与当前档都要原样保留。
    func testProfileRoundTripKeepsProfilesAndActiveID() throws {
        let original = makeTwoProfileConfiguration()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AgentConfiguration.self, from: data)
        XCTAssertEqual(decoded.profiles, original.profiles)
        XCTAssertEqual(decoded.activeProfileID, "local")
        XCTAssertEqual(decoded.model, "qwen2.5:7b")
    }

    /// ⑤ **缺配置只挡那一档**：切到没配好的档才阻断，切回配好的档又放行。
    func testAnIncompleteProfileBlocksOnlyItself() {
        var configuration = makeTwoProfileConfiguration()
        XCTAssertTrue(configuration.issues.isEmpty, "local 档配好了")
        configuration.addProfile(AgentProfile(id: "blank", name: "blank"), makeActive: true)
        XCTAssertFalse(configuration.issues.isEmpty, "空档 ⇒ 阻断（它自己）")
        XCTAssertTrue(configuration.setActiveProfile(id: "local"))
        XCTAssertTrue(configuration.issues.isEmpty, "切回配好的档 ⇒ 又放行（别档的毛病不背在它身上）")
    }

    /// ⑥ 一档一把钥匙串条目键；**删到空档被拒**（没有档 = 没有可用的配置）。
    func testSecretKeysArePerProfileAndTheLastProfileCannotBeRemoved() {
        let configuration = makeTwoProfileConfiguration()
        XCTAssertEqual(configuration.profiles[0].secretKey, "agent.api-key.local")
        XCTAssertEqual(configuration.profiles[1].secretKey, "agent.api-key.cloud")
        XCTAssertNotEqual(configuration.profiles[0].secretKey, configuration.profiles[1].secretKey,
                          "一档一把，互不覆盖")

        var one = AgentConfiguration(endpoint: "http://127.0.0.1:11434/v1", model: "m")
        XCTAssertFalse(one.removeProfile(id: "default"), "最后一档不许删")
        XCTAssertEqual(one.profiles.count, 1)
    }
}
