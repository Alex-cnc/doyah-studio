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

    func testGatewayURLRequiresWebSocketScheme() throws {
        XCTAssertEqual(try AgentIMSettingsValidator.normalizedGatewayURL("wss://gateway.example/ws").absoluteString,
                       "wss://gateway.example/ws")
        XCTAssertEqual(try AgentIMSettingsValidator.normalizedGatewayURL("ws://127.0.0.1:8080").absoluteString,
                       "ws://127.0.0.1:8080")
        XCTAssertThrowsError(try AgentIMSettingsValidator.normalizedGatewayURL("https://gateway.example/ws")) {
            XCTAssertEqual($0 as? AgentIMSettingsProblem, .gatewayURLNotWebSocket)
        }
    }

    func testGatewayURLRejectsEmptyHostAndInnerWhitespace() {
        XCTAssertThrowsError(try AgentIMSettingsValidator.normalizedGatewayURL("   ")) {
            XCTAssertEqual($0 as? AgentIMSettingsProblem, .gatewayURLMissing)
        }
        XCTAssertThrowsError(try AgentIMSettingsValidator.normalizedGatewayURL("ws://")) {
            XCTAssertEqual($0 as? AgentIMSettingsProblem, .gatewayURLMissingHost)
        }
        XCTAssertThrowsError(try AgentIMSettingsValidator.normalizedGatewayURL("ws://gate way/ws")) {
            XCTAssertEqual($0 as? AgentIMSettingsProblem, .gatewayURLHasWhitespace)
        }
        XCTAssertThrowsError(try AgentIMSettingsValidator.normalizedGatewayURL("gateway.example")) {
            XCTAssertEqual($0 as? AgentIMSettingsProblem, .gatewayURLNotWebSocket)
        }
    }

    func testGatewayURLTrimsSurroundingWhitespace() throws {
        let url = try AgentIMSettingsValidator.normalizedGatewayURL("  wss://gateway.example/ws \n")
        XCTAssertEqual(url.absoluteString, "wss://gateway.example/ws")
    }

    func testBotIdentifierRules() throws {
        XCTAssertEqual(try AgentIMSettingsValidator.normalizedBotIdentifier("  doyah-bot  "), "doyah-bot")
        XCTAssertThrowsError(try AgentIMSettingsValidator.normalizedBotIdentifier("  ")) {
            XCTAssertEqual($0 as? AgentIMSettingsProblem, .botIdentifierEmpty)
        }
        XCTAssertThrowsError(try AgentIMSettingsValidator.normalizedBotIdentifier("doyah bot")) {
            XCTAssertEqual($0 as? AgentIMSettingsProblem, .botIdentifierHasWhitespace)
        }
        let tooLong = String(repeating: "a", count: AgentIMSettingsValidator.maxBotIdentifierLength + 1)
        XCTAssertThrowsError(try AgentIMSettingsValidator.normalizedBotIdentifier(tooLong)) {
            XCTAssertEqual($0 as? AgentIMSettingsProblem, .botIdentifierTooLong)
        }
        let atLimit = String(repeating: "a", count: AgentIMSettingsValidator.maxBotIdentifierLength)
        XCTAssertEqual(try AgentIMSettingsValidator.normalizedBotIdentifier(atLimit), atLimit)
    }

    func testProblemsListAllInStableOrder() {
        let settings = AgentIMChannelSettings(gatewayURL: "http://gateway.example", botIdentifier: "", receiveTasks: true)
        XCTAssertEqual(AgentIMSettingsValidator.problems(in: settings),
                       [.gatewayURLNotWebSocket, .botIdentifierEmpty])
        XCTAssertEqual(AgentIMSettingsValidator.problems(in: .empty),
                       [.gatewayURLMissing, .botIdentifierEmpty])
        XCTAssertTrue(AgentIMSettingsValidator.problems(in: AgentIMChannelSettings(
            gatewayURL: "wss://gateway.example/ws", botIdentifier: "doyah-bot")).isEmpty)
    }

    func testNormalizedSettingsTrimsAndKeepsToggle() throws {
        let clean = try AgentIMSettingsValidator.normalized(
            AgentIMChannelSettings(gatewayURL: " wss://gateway.example/ws ", botIdentifier: " doyah-bot ", receiveTasks: true))
        XCTAssertEqual(clean, AgentIMChannelSettings(gatewayURL: "wss://gateway.example/ws",
                                                     botIdentifier: "doyah-bot",
                                                     receiveTasks: true))
    }

    // MARK: - 持久化（非敏感面进配置文件、Secret 不进）

    private func makeStore(_ secrets: MemorySecret) -> AgentIMCredentialStore {
        AgentIMCredentialStore(directoryURL: directory, secretStore: secrets)
    }

    func testSettingsPersistAndSecretStaysOutOfTheFile() throws {
        let secrets = MemorySecret()
        let store = makeStore(secrets)
        try store.save(appID: "123456", secret: "qq-secret-value", for: .qq)
        try store.save(settings: AgentIMChannelSettings(gatewayURL: "wss://gateway.example/ws",
                                                        botIdentifier: "doyah-bot",
                                                        receiveTasks: true),
                       for: .qq)

        let reopened = makeStore(secrets)
        XCTAssertEqual(reopened.settings(for: .qq),
                       AgentIMChannelSettings(gatewayURL: "wss://gateway.example/ws",
                                              botIdentifier: "doyah-bot",
                                              receiveTasks: true))
        XCTAssertEqual(reopened.appID(for: .qq), "123456")
        XCTAssertEqual(try reopened.secret(for: .qq), "qq-secret-value")

        let bytes = try String(contentsOf: reopened.fileURL(for: .qq), encoding: .utf8)
        XCTAssertFalse(bytes.contains("qq-secret-value"), "Secret 不许出现在配置文件里")
        // 按 JSON 取值（不按字面串比 URL：`JSONEncoder` 会把 `/` 转义成 `\/`）
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(bytes.utf8)) as? [String: Any])
        XCTAssertEqual(object["gatewayURL"] as? String, "wss://gateway.example/ws")
        XCTAssertEqual(object["botIdentifier"] as? String, "doyah-bot")
        XCTAssertEqual(object["receiveTasks"] as? Bool, true)
        XCTAssertEqual(object["appID"] as? String, "123456")
    }

    func testSavingAppIDDoesNotWipeSettings() throws {
        let secrets = MemorySecret()
        let store = makeStore(secrets)
        try store.save(settings: AgentIMChannelSettings(gatewayURL: "wss://gateway.example/ws",
                                                        botIdentifier: "doyah-bot",
                                                        receiveTasks: true),
                       for: .qq)
        // 只改 AppID（面板上「只填了 AppID 就点保存」的那条路）
        try store.save(appID: "654321", secret: nil, for: .qq)
        XCTAssertEqual(store.settings(for: .qq).gatewayURL, "wss://gateway.example/ws")
        XCTAssertEqual(store.settings(for: .qq).botIdentifier, "doyah-bot")
        XCTAssertTrue(store.settings(for: .qq).receiveTasks)
        XCTAssertEqual(store.appID(for: .qq), "654321")
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
            gatewayURL: "http://gateway.example", botIdentifier: "doyah-bot"), for: .qq)) {
            XCTAssertEqual($0 as? AgentIMSettingsProblem, .gatewayURLNotWebSocket)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL(for: .qq).path),
                       "校验失败时配置文件一个字节都不许出现")
    }

    // MARK: - 配齐了没 / 状态行

    func testReadinessListsMissingFieldsInOrder() {
        XCTAssertEqual(AgentIMReadiness.evaluate(settings: .empty, appID: nil, secretConfigured: false).missing,
                       [.gatewayURL, .botIdentifier, .appID, .secret])

        let ready = AgentIMReadiness.evaluate(
            settings: AgentIMChannelSettings(gatewayURL: "wss://gateway.example/ws", botIdentifier: "doyah-bot"),
            appID: "123456", secretConfigured: true)
        XCTAssertTrue(ready.isReady)
        XCTAssertTrue(ready.isConfigured)
    }

    func testReadinessTreatsUnparseableGatewayAsMissing() {
        // 非空但写成 http:// ⇒ 仍然算缺（否则面板说「配齐了」，一按连接就静默失败）
        let readiness = AgentIMReadiness.evaluate(
            settings: AgentIMChannelSettings(gatewayURL: "http://gateway.example", botIdentifier: "doyah-bot"),
            appID: "123456", secretConfigured: true)
        XCTAssertEqual(readiness.missing, [.gatewayURL])
        XCTAssertFalse(readiness.isReady)
    }

    func testStatusKindNeverShowsGreenWhileUnconfigured() {
        // 传输层说在线、配置却缺项 ⇒ 面板必须写「未配置」（不许出现「未配置」+「已连接」并存）
        let readiness = AgentIMReadiness(missing: [.secret])
        let kind = AgentIMStatusKind.of(readiness: readiness, connection: .online(attempt: 1))
        XCTAssertEqual(kind, .unconfigured([.secret]))
        XCTAssertFalse(kind.isOnline)
    }

    func testStatusLineNamesMissingFields() {
        let kind = AgentIMStatusKind.of(readiness: AgentIMReadiness(missing: [.gatewayURL, .secret]),
                                        connection: .idle)
        let zh = AgentIMStatusText.line(for: kind, language: .simplifiedChinese)
        XCTAssertTrue(zh.contains("网关端点"), zh)
        XCTAssertTrue(zh.contains("App Secret"), zh)
        let en = AgentIMStatusText.line(for: kind, language: .english)
        XCTAssertTrue(en.contains("Gateway endpoint"), en)
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
    }

    func testAppStateWiresProbeInboundPolicyAndRealSocket() throws {
        let state = try source("App/AppState.swift")
        XCTAssertTrue(state.contains("AgentIMConnectivityProbe.run("), "测试连接必须真发一帧")
        XCTAssertTrue(state.contains("AgentIMInboundPolicy.decide("), "入站必须先过策略")
        XCTAssertTrue(state.contains("AgentIMSocketFactories.webSocket("), "真通路用 WebSocket 适配层")
        XCTAssertTrue(state.contains("agentIMTransport"), "传输层要由 AppState 持有（连上后不随面板关掉）")
    }
}
