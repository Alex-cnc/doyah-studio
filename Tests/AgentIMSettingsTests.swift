import XCTest
@testable import DoyahCore

/// `FR-AGT-LINK-CHAN-003` **配置面**的判据：地址 / 标识校验、状态行四档、入站策略、测试连接四档。
///
/// 这一族的由来（2026-10-28 主人原话「怎么连配置IM通道的界面都没有呢？」）：此前这一节
/// 只有 AppID / Secret 两格 + 一句「传输层未实现」—— 于是「配齐了没」「连没连上」没有任何一处
/// 说得清。本片把这三件事各收成**一处判定**（`AgentIMReadiness` / `AgentIMStatusKind` /
/// `AgentIMInboundPolicy`），界面只搬结论。
final class AgentIMSettingsTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-im-settings-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - 假件

    private final class MemorySecret: AgentIMSecretStore, @unchecked Sendable {
        private var values: [AgentIMChannelCredentialKind: String] = [:]
        func setSecret(_ secret: String, for kind: AgentIMChannelCredentialKind) throws { values[kind] = secret }
        func secret(for kind: AgentIMChannelCredentialKind) throws -> String? { values[kind] }
        func deleteSecret(for kind: AgentIMChannelCredentialKind) throws { values[kind] = nil }
    }

    private struct ProbeError: Error {}

    private final class ProbeSocket: AgentIMSocket, @unchecked Sendable {
        private let lock = NSLock()
        private var _closed = 0
        private var _sent: [String] = []

        private let openFails: Bool
        private let sendFails: Bool
        private let answer: String?

        init(openFails: Bool = false, sendFails: Bool = false, answer: String? = nil) {
            self.openFails = openFails
            self.sendFails = sendFails
            self.answer = answer
        }

        var closeCount: Int { lock.lock(); defer { lock.unlock() }; return _closed }
        var sentFrames: [String] { lock.lock(); defer { lock.unlock() }; return _sent }

        func open() async throws {
            if openFails { throw ProbeError() }
        }

        func send(_ text: String) async throws {
            lock.lock(); _sent.append(text); lock.unlock()
            if sendFails { throw ProbeError() }
        }

        func receive() async throws -> String {
            if let answer { return answer }
            // 网关连上了却一句话都不回（握手口径不对的典型现场）：这里挂住，让超时那一档先到。
            try await Task.sleep(nanoseconds: 2_000_000_000)
            return ""
        }

        func close() async {
            lock.lock(); _closed += 1; lock.unlock()
        }
    }

    /// 记下工厂被怎么调用（URL 与握手头有没有真的传到线上）。
    private final class SocketFactoryRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var _urls: [URL] = []
        private var _headers: [[String: String]] = []
        private let socket: ProbeSocket

        init(socket: ProbeSocket) { self.socket = socket }

        var urls: [URL] { lock.lock(); defer { lock.unlock() }; return _urls }
        var headers: [[String: String]] { lock.lock(); defer { lock.unlock() }; return _headers }

        func factory() -> AgentIMSocketFactory {
            { [self] url, headers in
                lock.lock(); _urls.append(url); _headers.append(headers); lock.unlock()
                return socket
            }
        }
    }

    // MARK: - 地址与标识的校验

    func testRelayURLRequiresWebSocketSchemeAndAllowsEmpty() throws {
        // 空 = 合法的「走官方」（★0 之后地址由程序取），所以空不是缺项、也不报错。
        XCTAssertNil(try AgentIMSettingsValidator.normalizedRelayURL(""))
        XCTAssertNil(try AgentIMSettingsValidator.normalizedRelayURL("   "))
        XCTAssertEqual(try AgentIMSettingsValidator.normalizedRelayURL("wss://gateway.example/ws")?.absoluteString,
                       "wss://gateway.example/ws")
        XCTAssertEqual(try AgentIMSettingsValidator.normalizedRelayURL("ws://127.0.0.1:8080")?.absoluteString,
                       "ws://127.0.0.1:8080")
        XCTAssertThrowsError(try AgentIMSettingsValidator.normalizedRelayURL("https://gateway.example/ws")) {
            XCTAssertEqual($0 as? AgentIMSettingsProblem, .relayURLNotWebSocket)
        }
    }

    func testRelayURLRejectsMissingHostAndInnerWhitespace() {
        XCTAssertThrowsError(try AgentIMSettingsValidator.normalizedRelayURL("ws://")) {
            XCTAssertEqual($0 as? AgentIMSettingsProblem, .relayURLMissingHost)
        }
        XCTAssertThrowsError(try AgentIMSettingsValidator.normalizedRelayURL("ws://gate way/ws")) {
            XCTAssertEqual($0 as? AgentIMSettingsProblem, .relayURLHasWhitespace)
        }
        XCTAssertThrowsError(try AgentIMSettingsValidator.normalizedRelayURL("gateway.example")) {
            XCTAssertEqual($0 as? AgentIMSettingsProblem, .relayURLNotWebSocket)
        }
    }

    func testRelayURLTrimsSurroundingWhitespace() throws {
        let url = try AgentIMSettingsValidator.normalizedRelayURL("  wss://gateway.example/ws \n")
        XCTAssertEqual(url?.absoluteString, "wss://gateway.example/ws")
    }


    func testProblemsOnlyCoverTheRelayAddress() {
        // 地址留空 = 合法（走官方）；填错才报，且一次只报第一条。
        XCTAssertTrue(AgentIMSettingsValidator.problems(in: .empty).isEmpty)
        XCTAssertEqual(AgentIMSettingsValidator.problems(in: AgentIMChannelSettings(
            environment: .production, relayURL: "http://gateway.example")),
                       [.relayURLNotWebSocket])
        XCTAssertTrue(AgentIMSettingsValidator.problems(in: AgentIMChannelSettings(
            environment: .sandbox, relayURL: "wss://gateway.example/ws")).isEmpty)
    }

    func testNormalizedSettingsTrimsRelayAndKeepsEnvironment() throws {
        let clean = try AgentIMSettingsValidator.normalized(
            AgentIMChannelSettings(environment: .sandbox,
                                   relayURL: " wss://gateway.example/ws ",
                                   receiveTasks: true))
        XCTAssertEqual(clean, AgentIMChannelSettings(environment: .sandbox,
                                                     relayURL: "wss://gateway.example/ws",
                                                     receiveTasks: true))
        // 留空的自建中继存成空串（不是 nil、也不是空白串）。
        XCTAssertEqual(try AgentIMSettingsValidator.normalized(
            AgentIMChannelSettings(environment: .production, relayURL: "   ")).relayURL, "")
    }

    // MARK: - 持久化（非敏感面进配置文件、Secret 不进）

    private func makeStore(_ secrets: MemorySecret) -> AgentIMCredentialStore {
        AgentIMCredentialStore(directoryURL: directory, secretStore: secrets)
    }

    func testSettingsPersistAndSecretStaysOutOfTheFile() throws {
        let secrets = MemorySecret()
        let store = makeStore(secrets)
        try store.save(appID: "123456", secret: "qq-secret-value", for: .qq)
        try store.save(settings: AgentIMChannelSettings(environment: .sandbox,
                                                        relayURL: "wss://relay.example/ws",
                                                        receiveTasks: true),
                       for: .qq)

        let reopened = makeStore(secrets)
        XCTAssertEqual(reopened.settings(for: .qq),
                       AgentIMChannelSettings(environment: .sandbox,
                                              relayURL: "wss://relay.example/ws",
                                              receiveTasks: true))
        XCTAssertEqual(reopened.appID(for: .qq), "123456")
        XCTAssertEqual(try reopened.secret(for: .qq), "qq-secret-value")

        let bytes = try String(contentsOf: reopened.fileURL(for: .qq), encoding: .utf8)
        XCTAssertFalse(bytes.contains("qq-secret-value"), "Secret 不许出现在配置文件里")
        // 按 JSON 取值（不按字面串比 URL：`JSONEncoder` 会把 `/` 转义成 `\/`）
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(bytes.utf8)) as? [String: Any])
        XCTAssertEqual(object["environment"] as? String, "sandbox")
        XCTAssertEqual(object["relayURL"] as? String, "wss://relay.example/ws")
        XCTAssertEqual(object["receiveTasks"] as? Bool, true)
        XCTAssertEqual(object["appID"] as? String, "123456")
        // ★0 之后这两格作废：再往盘上写就是第二份真相。
        XCTAssertNil(object["gatewayURL"])
        XCTAssertNil(object["botIdentifier"])
    }

    func testSavingAppIDDoesNotWipeSettings() throws {
        let secrets = MemorySecret()
        let store = makeStore(secrets)
        try store.save(settings: AgentIMChannelSettings(environment: .production,
                                                        relayURL: "wss://relay.example/ws",
                                                        receiveTasks: true),
                       for: .qq)
        // 只改 AppID（面板上「只填了 AppID 就点保存」的那条路）
        try store.save(appID: "654321", secret: nil, for: .qq)
        XCTAssertEqual(store.settings(for: .qq).environment, .production)
        XCTAssertEqual(store.settings(for: .qq).relayURL, "wss://relay.example/ws")
        XCTAssertTrue(store.settings(for: .qq).receiveTasks)
        XCTAssertEqual(store.appID(for: .qq), "654321")
    }

    func testSavingSecretDoesNotWipeSettingsOrAppID() throws {
        // 主人点名的那一条：**只改 AppID 不冲掉 AppSecret**，反过来也一样。
        let secrets = MemorySecret()
        let store = makeStore(secrets)
        try store.save(appID: "123456", secret: "qq-secret-value", for: .qq)
        try store.save(settings: AgentIMChannelSettings(environment: .sandbox, receiveTasks: true), for: .qq)
        try store.save(appID: "123456", secret: "rotated-secret", for: .qq)
        XCTAssertEqual(try store.secret(for: .qq), "rotated-secret")
        XCTAssertEqual(store.settings(for: .qq).environment, .sandbox)
        XCTAssertTrue(store.settings(for: .qq).receiveTasks)
    }

    func testLegacyGatewayURLIsReadAsRelayAddress() throws {
        // 2026-10-28 之前用户在「网关端点」那一格手填的 wss 地址：读成自建中继（语义正好对上），
        // 不许升级一次就把人填过的东西吞掉。但**再保存一次**就迁成新形状（旧键从盘上消失）。
        let secrets = MemorySecret()
        let store = makeStore(secrets)
        try Data(#"{"appID":"123456","gatewayURL":"wss://old.example/ws","botIdentifier":"doyah-bot"}"#.utf8)
            .write(to: store.fileURL(for: .qq))
        XCTAssertEqual(store.settings(for: .qq).relayURL, "wss://old.example/ws")
        XCTAssertNil(store.settings(for: .qq).environment, "老文件没有环境 ⇒ 未配置（不默认成正式）")

        try store.save(settings: AgentIMChannelSettings(environment: .production), for: .qq)
        XCTAssertEqual(store.settings(for: .qq).relayURL, "")
        let bytes = try String(contentsOf: store.fileURL(for: .qq), encoding: .utf8)
        XCTAssertFalse(bytes.contains("botIdentifier"))
    }

    func testOldFileWithOnlyAppIDStillLoads() throws {
        let secrets = MemorySecret()
        let store = makeStore(secrets)
        // 2026-10-27 之前落下的形状：只有 appID
        try Data(#"{"appID":"123456"}"#.utf8).write(to: store.fileURL(for: .qq))
        XCTAssertEqual(store.settings(for: .qq), .empty)
        XCTAssertEqual(store.appID(for: .qq), "123456")
    }

    func testInvalidSettingsWriteNothing() throws {
        let secrets = MemorySecret()
        let store = makeStore(secrets)
        XCTAssertThrowsError(try store.save(settings: AgentIMChannelSettings(
            environment: .production, relayURL: "http://gateway.example"), for: .qq)) {
            XCTAssertEqual($0 as? AgentIMSettingsProblem, .relayURLNotWebSocket)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL(for: .qq).path),
                       "校验失败时配置文件一个字节都不许出现")
    }

    // MARK: - 配齐了没 / 状态行

    func testReadinessListsMissingFieldsInOrder() {
        // ★0 之后只要三样：环境 / AppID / Secret（地址由程序取，不是用户填的项）。
        XCTAssertEqual(AgentIMReadiness.evaluate(settings: .empty, appID: nil, secretConfigured: false).missing,
                       [.environment, .appID, .secret])

        let ready = AgentIMReadiness.evaluate(
            settings: AgentIMChannelSettings(environment: .production, relayURL: ""),
            appID: "123456", secretConfigured: true)
        XCTAssertTrue(ready.isReady)
        XCTAssertTrue(ready.isConfigured)
    }

    func testReadinessDoesNotAskForAnAddressAnyMore() {
        // 反例：把「没填地址」当缺项 = 又回到 ★0 要删掉的那一格。
        let readiness = AgentIMReadiness.evaluate(
            settings: AgentIMChannelSettings(environment: .production),
            appID: "123456", secretConfigured: true)
        XCTAssertTrue(readiness.isReady, "不填任何地址也必须能配齐")
        XCTAssertFalse(AgentIMConfigField.allCases.contains { $0.rawValue.contains("gateway") },
                       "配齐判定里不该再有地址这一项")
        // 环境没选 = 缺项（选错环境消息一条都不来，而面板会显示「已连接」）。
        XCTAssertEqual(AgentIMReadiness.evaluate(settings: AgentIMChannelSettings(),
                                                 appID: "123456", secretConfigured: true).missing,
                       [.environment])
    }


    func testStatusKindNeverShowsGreenWhileUnconfigured() {
        // 传输层说在线、配置却缺项 ⇒ 面板必须写「未配置」（不许出现「未配置」+「已连接」并存）
        let readiness = AgentIMReadiness(missing: [.secret])
        let kind = AgentIMStatusKind.of(readiness: readiness, connection: .online(attempt: 1))
        XCTAssertEqual(kind, .unconfigured([.secret]))
        XCTAssertFalse(kind.isOnline)
    }

    func testStatusLineNamesMissingFields() {
        let kind = AgentIMStatusKind.of(readiness: AgentIMReadiness(missing: [.environment, .secret]),
                                        connection: .idle)
        let zh = AgentIMStatusText.line(for: kind, language: .simplifiedChinese)
        XCTAssertTrue(zh.contains("环境"), zh)
        XCTAssertTrue(zh.contains("App Secret"), zh)
        let en = AgentIMStatusText.line(for: kind, language: .english)
        XCTAssertTrue(en.contains("Environment"), en)
        XCTAssertFalse(en.contains(where: { $0.unicodeScalars.contains { $0.value >= 0x4E00 && $0.value <= 0x9FFF } }), en)
    }

    func testWaitingLineIncludesReasonAndRoundedUpSeconds() {
        let kind = AgentIMStatusKind.waiting(reason: "heartbeatLost", retryIn: 2.2)
        let zh = AgentIMStatusText.line(for: kind, language: .simplifiedChinese)
        XCTAssertTrue(zh.contains("心跳超时"), zh)
        XCTAssertTrue(zh.contains("3 秒"), zh)
        XCTAssertFalse(zh.contains("%d"), zh)
    }

    func testUnknownReasonCodeIsEchoedNotInvented() {
        let line = AgentIMStatusText.reasonLine("gatewaySaidNo", language: .simplifiedChinese)
        XCTAssertTrue(line.contains("gatewaySaidNo"), line)
        // 认识的码不许把机器码贴出来（贴码 = 没翻）
        XCTAssertFalse(AgentIMStatusText.reasonLine("connectFailed", language: .simplifiedChinese)
            .contains("connectFailed"))
    }

    func testEverySettingsProblemHasBothLanguages() {
        for problem in AgentIMSettingsProblem.allCases {
            let zh = AgentIMSettingsProblemText.line(for: problem, language: .simplifiedChinese)
            let en = AgentIMSettingsProblemText.line(for: problem, language: .english)
            XCTAssertFalse(zh.isEmpty)
            XCTAssertTrue(zh.unicodeScalars.contains { $0.value >= 0x4E00 && $0.value <= 0x9FFF }, "\(problem) 缺中文")
            XCTAssertFalse(en.isEmpty)
            XCTAssertNotEqual(zh, problem.rawValue, "\(problem) 没走语言表")
        }
    }

    // MARK: - 入站策略（开关关掉一条都不收）

    func testInboundDroppedWhenReceiveTasksOffEvenWhileOnline() {
        let ready = AgentIMReadiness(missing: [])
        XCTAssertEqual(AgentIMInboundPolicy.decide(receiveTasks: false, readiness: ready, connection: .online(attempt: 1)),
                       .notEnabled)
        XCTAssertEqual(AgentIMInboundPolicy.decide(receiveTasks: false, readiness: ready, connection: .idle),
                       .notEnabled)
    }

    func testInboundRequiresReadyAndOnline() {
        let ready = AgentIMReadiness(missing: [])
        XCTAssertEqual(AgentIMInboundPolicy.decide(receiveTasks: true, readiness: ready, connection: .idle),
                       .notConnected)
        XCTAssertEqual(AgentIMInboundPolicy.decide(receiveTasks: true,
                                                   readiness: AgentIMReadiness(missing: [.appID]),
                                                   connection: .online(attempt: 1)),
                       .notConfigured)
        XCTAssertNil(AgentIMInboundPolicy.decide(receiveTasks: true, readiness: ready, connection: .online(attempt: 1)))
    }

    // MARK: - 测试连接（四档，只有收到帧才算通）

    func testProbeReportsOpenFailureAndClosesSocket() async {
        let socket = ProbeSocket(openFails: true)
        let recorder = SocketFactoryRecorder(socket: socket)
        let outcome = await AgentIMConnectivityProbe.run(makeSocket: recorder.factory(),
                                                         url: URL(string: "wss://gateway.example/ws")!,
                                                         headers: ["x-app-id": "123456"],
                                                         receiveTimeout: 0.05)
        XCTAssertEqual(outcome, .openFailed)
        XCTAssertFalse(outcome.isReachable)
        XCTAssertEqual(socket.closeCount, 1, "失败路径也要关 socket（否则每次测试漏一条连接）")
        XCTAssertEqual(recorder.urls.first?.absoluteString, "wss://gateway.example/ws")
        XCTAssertEqual(recorder.headers.first?["x-app-id"], "123456")
    }

    func testProbeReportsSendFailure() async {
        let socket = ProbeSocket(sendFails: true)
        let recorder = SocketFactoryRecorder(socket: socket)
        let outcome = await AgentIMConnectivityProbe.run(makeSocket: recorder.factory(),
                                                         url: URL(string: "wss://gateway.example/ws")!,
                                                         headers: [:],
                                                         receiveTimeout: 0.05)
        XCTAssertEqual(outcome, .sendFailed)
        XCTAssertEqual(socket.sentFrames, [AgentIMTransport.pingFrame])
        XCTAssertEqual(socket.closeCount, 1)
    }

    func testProbeReportsNoResponseWhenGatewayStaysSilent() async {
        // `open` 与 `send` 都成功但一帧都不回 —— 这正是「地址对、握手口径错」的样子：
        // 只判 open 会把这一档画成绿。
        let socket = ProbeSocket()
        let recorder = SocketFactoryRecorder(socket: socket)
        let outcome = await AgentIMConnectivityProbe.run(makeSocket: recorder.factory(),
                                                         url: URL(string: "wss://gateway.example/ws")!,
                                                         headers: [:],
                                                         receiveTimeout: 0.05)
        XCTAssertEqual(outcome, .noResponse)
        XCTAssertFalse(outcome.isReachable)
        XCTAssertEqual(socket.closeCount, 1)
    }

    func testProbeReportsReachableOnlyWhenAFrameArrives() async {
        let socket = ProbeSocket(answer: #"{"op":"pong"}"#)
        let recorder = SocketFactoryRecorder(socket: socket)
        let outcome = await AgentIMConnectivityProbe.run(makeSocket: recorder.factory(),
                                                         url: URL(string: "wss://gateway.example/ws")!,
                                                         headers: [:],
                                                         receiveTimeout: 1)
        XCTAssertEqual(outcome, .reachable)
        XCTAssertTrue(outcome.isReachable)
        XCTAssertEqual(socket.closeCount, 1)
    }

    func testProbeLinesSayWhatIsMissingInBothLanguages() {
        let zh = AgentIMConnectivityProbe.line(for: .noResponse, receiveTimeout: 6, language: .simplifiedChinese)
        XCTAssertTrue(zh.contains("6 秒"), zh)
        let en = AgentIMConnectivityProbe.line(for: .openFailed, receiveTimeout: 6, language: .english)
        XCTAssertFalse(en.isEmpty)
        XCTAssertFalse(en.contains(where: { $0.unicodeScalars.contains { $0.value >= 0x4E00 && $0.value <= 0x9FFF } }), en)
    }

    // MARK: - 接线锚点（Core 有判定、界面必须真的接上）

    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testSettingsSheetShowsConfigStatusAndTestButton() throws {
        let sheet = try source("App/Views/AgentSettingsSheet.swift")
        XCTAssertTrue(sheet.contains("AgentIMStatusText.line(for:"), "面板必须画 Core 给的状态行")
        XCTAssertTrue(sheet.contains("$imReceiveTasks"), "面板必须有「接收任务」开关")
        XCTAssertTrue(sheet.contains("appState.testAgentIMConnection()"), "面板必须有「测试连接」")
        XCTAssertTrue(sheet.contains("appState.connectAgentIM()"), "面板必须有连接入口")
        XCTAssertTrue(sheet.contains("appState.disconnectAgentIM()"), "面板必须有断开入口")
        XCTAssertFalse(sheet.contains("agentIMTransportPending"),
                       "「传输层未实现」那句话必须随本片作废（留着就是假话）")
        // ★0（2026-10-28）：地址那一格删掉、换成环境；面板要说清程序取到的是哪个地址。
        XCTAssertTrue(sheet.contains("$imEnvironment"), "面板必须能选环境")
        XCTAssertTrue(sheet.contains("appState.agentIMGatewayLine"), "必须把程序取到的地址画出来")
    }

    func testAppStateWiresProbeInboundPolicyAndRealSocket() throws {
        let state = try source("App/AppState.swift")
        XCTAssertTrue(state.contains("AgentIMConnectivityProbe.run("), "测试连接必须真发一帧")
        // 入站策略的调用点**随「真跑」搬进了那条唯一链**（`AgentIMInboundRunner.handle`）——
        // AppState 不再自己判一档（自己判 = 第二条链，两条迟早不一致）。锚点跟着机制走，
        // 并保留「必须先过策略」这一条：它现在钉在链上。
        XCTAssertTrue(state.contains("AgentIMInboundRunner("), "入站必须走那条唯一链")
        let runner = try source("Core/AgentIMInboundRun.swift")
        XCTAssertTrue(runner.contains("AgentIMInboundPolicy.decide("), "入站必须先过策略")
        XCTAssertTrue(state.contains("AgentIMSocketFactories.webSocket("), "真通路用 WebSocket 适配层")
        XCTAssertTrue(state.contains("agentIMTransport"), "传输层要由 AppState 持有（连上后不随面板关掉）")
        // ★0：面板那一层不许自己拼地址，一切经 Core 的取 token / 取网关。
        XCTAssertTrue(state.contains("provisionAgentIM()"), "连接与测试都只走一条准备链")
        XCTAssertFalse(state.contains("normalizedGatewayURL"), "旧口径（用户填地址）必须清干净")
    }
}
