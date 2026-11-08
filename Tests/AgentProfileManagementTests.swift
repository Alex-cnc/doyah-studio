import XCTest
@testable import DoyahCore

/// 多 Provider / 多模型的**配置面**（`FR-AI-32`）判据 —— 增删复制改名、独立密钥、切档即生效、迁移、上限。
///
/// 与 `AgentProfileTests` 的分工：那一份判**数据模型**（两档并存、镜像、老配置迁移）；
/// 这一份判**配置面的操作**（复制 / 改名 / 删除的结论 / 上限）与**切档后真发出去的请求**
/// 是不是这一档的端点 / 模型 / 密钥（判据 ①③⑤）。
final class AgentProfileManagementTests: XCTestCase {

    // MARK: - 夹具

    /// 记录**真发出去的那一条请求**（判据 ① 要逐字对 URL / 模型 / Authorization）。
    /// 走流式出口（与生产同一条路），回来一段可解析的 SSE 收尾。
    private final class RecordingTransport: HTTPStreamingTransport, @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: [URLRequest] = []
        private let status: Int

        init(status: Int = 200) { self.status = status }

        var requests: [URLRequest] {
            lock.lock(); defer { lock.unlock() }
            return recorded
        }

        func stream(_ request: URLRequest) async throws -> (HTTPURLResponse, AsyncThrowingStream<Data, Error>) {
            lock.lock(); recorded.append(request); lock.unlock()
            let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                          httpVersion: "HTTP/1.1",
                                          headerFields: ["Content-Type": "text/event-stream"])!
            let stream = AsyncThrowingStream<Data, Error> { continuation in
                continuation.yield(Data(#"data: {"model":"probe","choices":[{"delta":{"content":"ok"}}]}"# .utf8))
                continuation.yield(Data("\n\n".utf8))
                continuation.yield(Data("data: [DONE]\n\n".utf8))
                continuation.finish()
            }
            return (response, stream)
        }
    }

    /// 假的钥匙串：**条目键 → 密钥**的一张表。
    /// 用字典而不是真钥匙串（单测不该碰用户的系统凭据），但条目键完全照生产口径
    /// （`agent.api-key.<档 id>`）—— 判据 ③ 判的就是「两档是不是同一条目」。
    private final class KeyMap: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String: String]
        init(_ items: [String: String]) { self.items = items }

        func value(for key: String) -> String? {
            lock.lock(); defer { lock.unlock() }
            return items[key]
        }

        func set(_ value: String, for key: String) {
            lock.lock(); defer { lock.unlock() }
            items[key] = value
        }
    }

    /// 三档：端点 / 模型 / 密钥条目各不相同。
    private func threeProfiles() -> AgentConfiguration {
        let a = AgentProfile(id: "p1", name: "便宜本机", presetID: "ollama",
                             endpoint: "http://127.0.0.1:11434/v1", model: "qwen2.5:7b")
        let b = AgentProfile(id: "p2", name: "云端写作", presetID: "deepseek",
                             endpoint: "https://api.deepseek.com/v1", model: "deepseek-v4.1-flash")
        let c = AgentProfile(id: "p3", name: "代码", presetID: "openai",
                             endpoint: "https://api.openai.com/v1", model: "gpt-4.1")
        return AgentConfiguration(isEnabled: true, profiles: [a, b, c], activeProfileID: "p1")
    }

    // MARK: - ① 切到第 2 档 ⇒ 发出去的请求逐字对应该档

    func testSwitchingToTheSecondProfileSendsItsOwnEndpointModelAndKey() async throws {
        var configuration = threeProfiles()
        let keys = ["agent.api-key.p1": "sk-local",
                    "agent.api-key.p2": "sk-deepseek-second",
                    "agent.api-key.p3": "sk-openai-third"]
        let store = KeyMap(keys)

        // 当前档 = p1
        let firstTransport = RecordingTransport()
        let firstProfile = try XCTUnwrap(configuration.activeProfile)
        _ = await AgentConnectionProbe.run(profile: firstProfile,
                                           apiKey: store.value(for: firstProfile.secretKey),
                                           transport: firstTransport)
        let firstRequest = try XCTUnwrap(firstTransport.requests.first)
        XCTAssertEqual(firstRequest.url?.absoluteString, "http://127.0.0.1:11434/v1/chat/completions")
        XCTAssertEqual(firstRequest.value(forHTTPHeaderField: "Authorization"), "Bearer sk-local")

        // 切到第 2 档 —— 下一次请求就必须换人（不许重启才生效）
        XCTAssertTrue(configuration.setActiveProfile(id: "p2"), "切档被拒")
        let secondTransport = RecordingTransport()
        let secondProfile = try XCTUnwrap(configuration.activeProfile)
        XCTAssertEqual(secondProfile.id, "p2", "当前档没换成第 2 档")
        let outcome = await AgentConnectionProbe.run(profile: secondProfile,
                                                     apiKey: store.value(for: secondProfile.secretKey),
                                                     transport: secondTransport)
        XCTAssertTrue(outcome.isSuccess, "第 2 档测试连接没成功：\(outcome)")

        let request = try XCTUnwrap(secondTransport.requests.first, "一次请求都没发出来")
        XCTAssertEqual(request.url?.absoluteString,
                       "https://api.deepseek.com/v1/chat/completions",
                       "请求 URL 还是上一档的（判红）")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"),
                       "Bearer sk-deepseek-second",
                       "Authorization 还是上一档的 Key（判红）")
        let body = try XCTUnwrap(request.httpBody)
        let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(payload["model"] as? String, "deepseek-v4.1-flash",
                       "请求体里的模型不是第 2 档的（判红）")
        print("🧪 判据①读数：URL=\(request.url?.absoluteString ?? "-") "
              + "model=\(payload["model"] as? String ?? "-") "
              + "auth=\(request.value(forHTTPHeaderField: "Authorization") ?? "-")")
    }

    // MARK: - ② 删当前档 ⇒ 回落到剩余第一档；删最后一档 ⇒ 拒绝并说明

    func testDeletingTheActiveProfileFallsBackAndTheLastOneIsRefused() throws {
        var configuration = threeProfiles()
        let deletion = configuration.deleteProfile(id: "p1")
        guard case .deleted(let fellBackTo) = deletion else {
            return XCTFail("删当前档没有被认成「删掉了」：\(deletion)")
        }
        XCTAssertEqual(configuration.profiles.map(\.id), ["p2", "p3"])
        XCTAssertEqual(configuration.activeProfileID, "p2", "当前档没回落到剩余第一档")
        XCTAssertEqual(fellBackTo?.id, "p2", "回落到哪一档没有说出来（界面就提示不了）")

        // 删的不是当前档 ⇒ 当前档一个字不动，也不该报「回落」
        let other = configuration.deleteProfile(id: "p3")
        guard case .deleted(let noFallback) = other else {
            return XCTFail("删非当前档的结论错了：\(other)")
        }
        XCTAssertNil(noFallback, "删的不是当前档，却报了回落")
        XCTAssertEqual(configuration.activeProfileID, "p2")

        // 只剩一档 ⇒ 拒绝，并说明为什么
        XCTAssertEqual(configuration.deleteProfile(id: "p2"), .refusedLastProfile)
        XCTAssertEqual(configuration.profiles.count, 1, "最后一档被删掉了")
        XCTAssertEqual(configuration.profiles.first?.id, "p2")
        XCTAssertEqual(configuration.deleteProfile(id: "不存在"), .notFound)
        // 老接口（`removeProfile`）与新的结论型接口口径一致
        var one = AgentConfiguration(endpoint: "http://127.0.0.1:11434/v1", model: "m")
        XCTAssertFalse(one.removeProfile(id: one.profiles[0].id), "最后一档不许删")
        print("🧪 判据②读数：删当前档回落 → \(fellBackTo?.name ?? "-")；"
              + "最后一档 → refusedLastProfile；剩 \(configuration.profiles.count) 档")
    }

    // MARK: - ③ 密钥独立：改第 2 档的 Key 不动第 1 档的条目

    func testEachProfileKeepsItsOwnSecretKeyEntry() throws {
        let configuration = threeProfiles()
        let keys = configuration.profiles.map(\.secretKey)
        XCTAssertEqual(Set(keys).count, 3, "两档共用同一条钥匙串条目（判红）：\(keys)")
        XCTAssertEqual(keys, ["agent.api-key.p1", "agent.api-key.p2", "agent.api-key.p3"])

        let store = KeyMap(["agent.api-key.p1": "sk-one",
                                 "agent.api-key.p2": "sk-two"])
        store.set("sk-two-rotated", for: "agent.api-key.p2")
        XCTAssertEqual(store.value(for: "agent.api-key.p1"), "sk-one",
                       "改第 2 档的 Key 把第 1 档的条目也改了（判红）")
        XCTAssertEqual(store.value(for: "agent.api-key.p2"), "sk-two-rotated")

        // 复制出来的档**不许**沿用原档的条目键（否则两档的 Key 从此共命运）
        var copySource = configuration
        let copy = try XCTUnwrap(copySource.duplicateProfile(id: "p2", name: "云端写作 副本"))
        XCTAssertNotEqual(copy.secretKey, "agent.api-key.p2", "复制出来的档沿用了原档的钥匙串条目（判红）")
        XCTAssertEqual(copy.secretKey, AgentProfile.defaultSecretKey(for: copy.id))
        print("🧪 判据③读数：条目 = \(keys)；副本条目 = \(copy.secretKey)")
    }

    // MARK: - 复制 / 改名 / 上限

    func testDuplicateCopiesNonSecretFieldsAndMovesActive() throws {
        var configuration = threeProfiles()
        let copy = try XCTUnwrap(configuration.duplicateProfile(id: "p2", name: "云端写作 副本"))
        XCTAssertEqual(configuration.profiles.map(\.id), ["p1", "p2", copy.id, "p3"],
                       "副本没紧跟原档插入")
        XCTAssertEqual(copy.endpoint, "https://api.deepseek.com/v1")
        XCTAssertEqual(copy.model, "deepseek-v4.1-flash")
        XCTAssertEqual(copy.presetID, "deepseek")
        XCTAssertEqual(copy.name, "云端写作 副本")
        XCTAssertEqual(configuration.activeProfileID, copy.id, "复制之后没切到副本")

        // 改名：空名拒绝，正常名只动这一档
        XCTAssertFalse(configuration.renameProfile(id: copy.id, name: "   "))
        XCTAssertEqual(configuration.profiles.first { $0.id == copy.id }?.name, "云端写作 副本")
        XCTAssertTrue(configuration.renameProfile(id: copy.id, name: "  写作专用  "))
        XCTAssertEqual(configuration.profiles.first { $0.id == copy.id }?.name, "写作专用")
        XCTAssertEqual(configuration.profiles.first { $0.id == "p1" }?.name, "便宜本机", "改名动了别档")
    }

    func testProfileCountIsCappedAtTwenty() {
        var configuration = AgentConfiguration(profiles: [AgentProfile(id: "seed", name: "seed")])
        for index in 1..<AgentConfiguration.maximumProfileCount {
            XCTAssertTrue(configuration.addProfile(AgentProfile(id: "p\(index)", name: "p\(index)")))
        }
        XCTAssertEqual(configuration.profiles.count, AgentConfiguration.maximumProfileCount)
        XCTAssertFalse(configuration.canAddProfile)
        XCTAssertFalse(configuration.addProfile(AgentProfile(id: "overflow", name: "overflow")),
                       "到上限还加进去了（判红）")
        XCTAssertEqual(configuration.profiles.count, AgentConfiguration.maximumProfileCount)
        XCTAssertNil(configuration.duplicateProfile(id: "seed", name: "copy"), "到上限还能复制（判红）")
        print("🧪 上限读数：\(configuration.profiles.count) 档后拒绝加档")
    }

    // MARK: - ⑤ 重启后 profiles 与 activeProfileID 保留

    func testProfilesAndActiveIDSurviveAReload() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-profile-reload-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = AgentConfigurationStore(directoryURL: directory)
        var configuration = threeProfiles()
        XCTAssertTrue(configuration.setActiveProfile(id: "p3"))
        XCTAssertTrue(configuration.renameProfile(id: "p3", name: "代码专用"))
        try await store.save(configuration)

        // 「重启」= 新建一个读同一目录的 store
        let reloaded = try await AgentConfigurationStore(directoryURL: directory).load()
        XCTAssertEqual(reloaded.profiles.map(\.id), ["p1", "p2", "p3"])
        XCTAssertEqual(reloaded.activeProfileID, "p3")
        XCTAssertEqual(reloaded.activeProfile?.name, "代码专用")
        XCTAssertEqual(reloaded.profiles.map(\.secretKey),
                       ["agent.api-key.p1", "agent.api-key.p2", "agent.api-key.p3"],
                       "重启后每档的钥匙串条目键变了 —— 已存的 Key 就读不回来了")
        XCTAssertEqual(reloaded.model, "gpt-4.1")

        let location = await store.fileLocation()
        let json = try String(contentsOf: location, encoding: .utf8)
        XCTAssertTrue(json.contains("\"activeProfileID\" : \"p3\""), "盘上没有当前档：\(json.prefix(200))")
        XCTAssertFalse(json.contains("\"endpoint\" : \"https://api.deepseek.com/v1\",\n  \"model\""),
                       "还写了老的单档镜像字段（两个真值源会漂移）")
        print("🧪 判据⑤读数：重载后 \(reloaded.profiles.count) 档 / active=\(reloaded.activeProfileID ?? "-")")
    }

    // MARK: - 老单档迁移（界面能直接编辑那一档）

    func testLegacySingleProfileIsEditableAndKeepsTheLegacyKey() throws {
        let legacy = #"{"isEnabled":true,"endpoint":"https://api.deepseek.com/v1","model":"deepseek-v4-pro","timeoutSeconds":42}"#
        var configuration = try JSONDecoder().decode(AgentConfiguration.self, from: Data(legacy.utf8))
        let id = try XCTUnwrap(configuration.activeProfile?.id)
        XCTAssertEqual(id, "default")
        XCTAssertEqual(configuration.activeProfile?.secretKey, AgentProfile.legacySecretKey)
        // 迁移来的档与新建档一样可改名 / 复制 / 加档
        XCTAssertTrue(configuration.renameProfile(id: id, name: "老配置"))
        XCTAssertNotNil(configuration.duplicateProfile(id: id, name: "老配置 副本"))
        XCTAssertEqual(configuration.profiles.count, 2)
        XCTAssertEqual(configuration.profiles[0].secretKey, AgentProfile.legacySecretKey,
                       "复制之后老档的条目键被改了 —— 已存的 Key 读不回来")
    }
}
