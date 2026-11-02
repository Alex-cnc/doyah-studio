import XCTest
@testable import DoyahCore

/// `NFR-ALL-GATE-SEC-008` 的判据：**统一**外发日志 —— 三类出网（智能体 / 浏览器 / 外部程序）
/// 都进同一份账，且条数与类别一一对应。
///
/// 为什么这一族必须存在（2026-11-02 实测的真缺口）：
/// 盘上早有 `EgressLog` 与 `EgressRecordingTransport`，但**装饰器只包住了两个生成器**
/// （生成 SQL / 数据任务规格）。产品里出网次数最多的一条路 —— 聊天循环与「测试连接」用的
/// 流式传输 —— 只过封条、不进日志；联网检索（`AgentWebTools`）、备份（`pg_dump` / `pg_restore`）
/// 与 `ssh` 隧道同样一条记录都没有。也就是说：日志看着有东西，**恰恰漏掉了最大的一类**，
/// 「所有离开本机的网络请求都写进同一份日志」这句承诺当场不成立。
///
/// 判据只认**盘上读回来**的记录（不是内存里现造的对象）—— 这份日志的全部价值就在「真的落盘」。
final class EgressUnifiedLogTests: XCTestCase {

    private var log: EgressLog!

    override func setUpWithError() throws {
        log = EgressTestSupport.temporaryLog("EgressUnifiedLogTests")
        // 这一族判「记什么」而不是「发不发」：封条开着，装饰器才会真的往下发并记 `allowed`。
        AgentEgressSeal.shared.setOpen(true)
    }

    override func tearDown() async throws {
        AgentEgressSeal.shared.setOpen(false)
        if let log { await EgressTestSupport.remove(log) }
        log = nil
    }

    // MARK: - 判据 ①「零外发 ⇒ 日志为空」

    /// 关闭智能体、没开浏览器时：**没有任何人发起** ⇒ 日志一条都不该有，连文件都不该出现。
    ///
    /// 这一条看着平凡，却是整份日志的前提：如果「什么都没做」也能长出记录，
    /// 那么「有记录」就再也不能证明「有出网」。
    func testNothingAttemptedMeansEmptyLog() async throws {
        AgentEgressSeal.shared.setOpen(false)

        // 三条缝**都在**，只是没人调用它们（与真实启动后的形状一致）。
        _ = EgressRecordingStreamingTransport(
            origin: "智能体 · 对话循环",
            wrapped: StubStreamingTransport(status: 200),
            log: log
        )
        _ = EgressRecordingProcessRunner(
            origin: "数据库 · 备份 / 恢复（外部程序）",
            wrapped: StubProcessRunner(exitCode: 0),
            log: log
        )

        let count = try await log.count()
        XCTAssertEqual(count, 0, "没人发起出网时日志必须为空")
        let path = await log.fileLocation().path
        XCTAssertFalse(FileManager.default.fileExists(atPath: path), "一条记录都没有时不该凭空落一个文件出来")
    }

    // MARK: - 流式传输：与整段请求同一条纪律

    /// **发出之前**就记（进程在途中被杀也留得下痕迹）。
    /// 断言方式：被包住的那层被调用那一刻，**盘上**已经有且只有那一条 `allowed`。
    func testStreamingTransportRecordsBeforeSending() async throws {
        let probe = SendTimeProbe(fileURL: await log.fileLocation())
        let transport = EgressRecordingStreamingTransport(
            origin: "智能体 · 对话循环",
            wrapped: StubStreamingTransport(status: 200) { probe.record() },
            log: log
        )
        let request = URLRequest(url: URL(string: "https://api.example.com/v1/chat/completions?api_key=sk-secret")!)

        _ = try await transport.stream(request)

        XCTAssertEqual(probe.linesWhenSent, 1, "发请求那一刻盘上就该有那一条（先记后发）")

        let all = try await log.entries()
        XCTAssertEqual(all.count, 1, "一次成功出网一条记录")
        XCTAssertEqual(all.first?.kind, .agentModel)
        XCTAssertEqual(all.first?.outcome, .allowed)
        XCTAssertEqual(all.first?.origin, "智能体 · 对话循环")
        XCTAssertEqual(all.first?.target, "https://api.example.com/v1/chat/completions", "目标要净化掉 query（密钥不进日志）")
        XCTAssertFalse(all.first?.target.contains("sk-secret") ?? true)
    }

    /// 封条关着：**记录成 `denied` 且一个字节都不往下发**（「想发但没发出去」必须可审计）。
    func testStreamingTransportRecordsDeniedAndSendsNothingWhenSealClosed() async throws {
        AgentEgressSeal.shared.setOpen(false)
        let probe = SendTimeProbe(fileURL: await log.fileLocation())
        let transport = EgressRecordingStreamingTransport(
            origin: "智能体 · 对话循环",
            wrapped: StubStreamingTransport(status: 200) { probe.record() },
            log: log
        )

        do {
            _ = try await transport.stream(URLRequest(url: URL(string: "https://api.example.com/v1/chat/completions")!))
            XCTFail("封条关着时不该有流回来")
        } catch {
            // 期望抛错（与封条同一句话）
        }

        XCTAssertNil(probe.linesWhenSent, "被拦下的请求不许碰到真正的运输层")

        let all = try await log.entries()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.outcome, .denied)
    }

    /// 非 2xx：传输层不抛（契约如此），但日志必须记成失败 —— 否则「发了、被拒了」长得像成功。
    func testStreamingTransportRecordsNon2xxAsFailure() async throws {
        let transport = EgressRecordingStreamingTransport(
            origin: "智能体 · 测试连接",
            wrapped: StubStreamingTransport(status: 500),
            log: log
        )
        _ = try await transport.stream(URLRequest(url: URL(string: "https://api.example.com/v1/chat/completions")!))

        let all = try await log.entries()
        XCTAssertEqual(all.count, 2, "先记发出、再记失败")
        // 顺序不判：时间戳是秒精度，同一秒内两条的先后由排序稳定性决定（判它就等于判实现细节）。
        XCTAssertEqual(all.filter { $0.outcome == .allowed }.count, 1)
        XCTAssertEqual(all.filter { $0.outcome == .failed }.first?.detail, "HTTP 500")
    }

    func testStreamingTransportRecordsThrowAsFailure() async throws {
        let transport = EgressRecordingStreamingTransport(
            origin: "智能体 · 对话循环",
            wrapped: ThrowingStreamingTransport(),
            log: log
        )
        do {
            _ = try await transport.stream(URLRequest(url: URL(string: "https://api.example.com/v1/chat/completions")!))
            XCTFail("应当把底层错误抛给上层")
        } catch {
            // 期望
        }
        let all = try await log.entries()
        XCTAssertEqual(all.filter { $0.outcome == .allowed }.count, 1)
        XCTAssertEqual(all.filter { $0.outcome == .failed }.count, 1)
        XCTAssertEqual(all.filter { $0.outcome == .failed }.first?.origin, "智能体 · 对话循环")
    }

    // MARK: - 外部程序

    func testProcessRunnerRecordsOneEntryOnSuccess() async throws {
        let runner = EgressRecordingProcessRunner(
            origin: "数据库 · 备份 / 恢复（外部程序）",
            wrapped: StubProcessRunner(exitCode: 0),
            log: log
        )
        let code = try await runner.run(executable: "pg_dump",
                                        arguments: ["-h", "db.example.com"],
                                        environment: [:]) { _ in }
        XCTAssertEqual(code, 0)

        let all = try await log.entries()
        XCTAssertEqual(all.count, 1, "成功一次出网一条记录")
        XCTAssertEqual(all.first?.kind, .externalProgram)
        XCTAssertEqual(all.first?.outcome, .allowed)
        XCTAssertEqual(all.first?.target, "pg_dump", "只记程序名，不抄 argv（argv 里常有连接串）")
        XCTAssertFalse((all.first?.detail ?? "").contains("db.example.com"), "argv 里的主机名不该进日志")
    }

    func testProcessRunnerRecordsFailureForNonZeroExit() async throws {
        let runner = EgressRecordingProcessRunner(
            origin: "数据库 · 备份 / 恢复（外部程序）",
            wrapped: StubProcessRunner(exitCode: 3),
            log: log
        )
        _ = try await runner.run(executable: "/opt/homebrew/bin/pg_restore", arguments: [], environment: [:]) { _ in }

        let all = try await log.entries()
        XCTAssertEqual(all.filter { $0.outcome == .allowed }.count, 1)
        XCTAssertEqual(all.filter { $0.outcome == .failed }.first?.detail, "退出码 3")
    }

    func testProcessRunnerRecordsLaunchFailure() async throws {
        let runner = EgressRecordingProcessRunner(
            origin: "数据库 · 备份 / 恢复（外部程序）",
            wrapped: ThrowingProcessRunner(),
            log: log
        )
        do {
            _ = try await runner.run(executable: "pg_dump", arguments: [], environment: [:]) { _ in }
            XCTFail("起不来就该抛")
        } catch {
            // 期望
        }
        let all = try await log.entries()
        XCTAssertEqual(all.filter { $0.outcome == .allowed }.count, 1, "起进程之前先记一条")
        XCTAssertEqual(all.filter { $0.outcome == .failed }.count, 1)
    }

    /// `ssh` 隧道：**起进程那一刻就是一次出网**，必须留一条（目标 = 跳板机，不是数据库）。
    ///
    /// 用 `/usr/bin/true` 当 ssh：这一条判的是「起进程这件事被记下来了」，
    /// 不判握手 —— 真握手要一台跳板机（记在证据的「未验证」里）。
    func testTunnelSpawnIsRecordedAsExternalProgram() async throws {
        let tunnelLog = EgressTestSupport.temporaryLog("egress-tunnel")
        defer { Task { await EgressTestSupport.remove(tunnelLog) } }

        let tunnel = SSHTunnelProcess(
            config: SSHTunnelConfig(host: "jump.example.com", port: 22, username: "alice", authentication: .agent),
            target: SSHTunnelTarget(host: "10.0.0.9", port: 5432),
            localPort: 55_991,
            knownHostsPath: NSTemporaryDirectory() + "doyah-egress-known-hosts-\(UUID().uuidString)",
            executable: "/usr/bin/true",
            isPortOpen: { _, _ in false },
            egressLog: tunnelLog
        )
        _ = try? await tunnel.start(timeout: 1, language: .simplifiedChinese)

        let recorded = try await tunnelLog.entries()
        let spawns = recorded.filter { $0.kind == .externalProgram }
        XCTAssertEqual(spawns.count, 1, "起一次 ssh ⇒ 一条外部程序记录")
        XCTAssertEqual(spawns.first?.target, "ssh://jump.example.com:22", "目标是跳板机，口令与用户名不进去")
        XCTAssertEqual(spawns.first?.outcome, .allowed)
    }

    // MARK: - 判据 ②：三类一一对应

    /// 用**假端点**分别触发智能体 / 浏览器 / 外部程序各一次 ⇒ 日志里每类恰好一条，
    /// 没有第四类，也没有多出来的记录。
    func testThreeKindsAreRecordedOneToOne() async throws {
        // ① 智能体（流式，与聊天循环同一条缝）
        let agent = EgressRecordingStreamingTransport(
            origin: "智能体 · 对话循环",
            wrapped: StubStreamingTransport(status: 200),
            log: log
        )
        _ = try await agent.stream(URLRequest(url: URL(string: "https://api.example.com/v1/chat/completions")!))

        // ② 浏览器（导航决策 → 记录，与真引擎同一条路）
        let transition = BrowserSession.navigate(
            page: BrowserPage(),
            to: URL(string: "https://example.org/page"),
            origin: "浏览器 · 页签 1",
            isUserInitiated: true
        )
        await BrowserSession.record(transition, origin: "浏览器 · 页签 1", log: log)

        // ③ 外部程序（备份那条缝）
        let runner = EgressRecordingProcessRunner(
            origin: "数据库 · 备份 / 恢复（外部程序）",
            wrapped: StubProcessRunner(exitCode: 0),
            log: log
        )
        _ = try await runner.run(executable: "pg_dump", arguments: [], environment: [:]) { _ in }

        let all = try await log.entries()
        XCTAssertEqual(all.count, 3, "三次触发 ⇒ 三条记录（条数与类别一一对应）")
        let expected: [EgressKind: Int] = [.agentModel: 1, .browser: 1, .externalProgram: 1, .updateCheck: 0]
        for kind in EgressKind.allCases {
            XCTAssertEqual(all.filter { $0.kind == kind }.count, expected[kind] ?? 0,
                           "\(kind.rawValue) 这一类的条数不对")
        }
        XCTAssertEqual(Set(all.map(\.origin)).count, 3, "三类来源必须能从日志里分开")
        XCTAssertEqual(Set(all.map(\.target)), [
            "https://api.example.com/v1/chat/completions",
            "https://example.org/page",
            "pg_dump"
        ])
        XCTAssertTrue(all.allSatisfy { $0.outcome == .allowed })
    }

    // MARK: - 生产接线（判据不许只在测试里成立）

    /// 装饰器只写在测试里不算数：**它们必须真的接在产品的装配点上**。
    /// 这一条只判「源树里接线在位」，判不了运行时行为 —— 那是上面那些用例的事。
    func testProductionWiringIsInTheSourceTree() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let appState = try String(contentsOf: root.appendingPathComponent("App/AppState.swift"), encoding: .utf8)
        let tunnel = try String(contentsOf: root.appendingPathComponent("Core/SSHTunnelProcess.swift"), encoding: .utf8)

        // 聊天循环与「测试连接」两个流式客户端各包一层 ⇒ 至少两处构造。
        let streamingSites = appState.components(separatedBy: "EgressRecordingStreamingTransport(").count - 1
        XCTAssertGreaterThanOrEqual(streamingSites, 2, "聊天循环与测试连接都必须包留痕装饰器")
        XCTAssertTrue(appState.contains("origin: \"智能体 · 对话循环\""))
        XCTAssertTrue(appState.contains("origin: \"智能体 · 测试连接\""))
        XCTAssertTrue(appState.contains("origin: \"智能体 · 联网检索\""), "联网检索（AgentWebTools）必须留痕")
        XCTAssertTrue(appState.contains("var backupRunner: any ExternalProcessRunner = EgressRecordingProcessRunner("),
                      "备份 / 恢复的执行器必须包留痕装饰器")
        XCTAssertTrue(tunnel.contains("kind: .externalProgram") && tunnel.contains("\"ssh://"),
                      "起 ssh 就是出网，隧道必须留痕")
    }
}

// MARK: - 夹具

/// 记「被包住那层被调用时，盘上已有几行」。直接数文件行数，避免在 actor 里等异步读表。
private final class SendTimeProbe: @unchecked Sendable {
    private let fileURL: URL
    private(set) var linesWhenSent: Int?

    init(fileURL: URL) { self.fileURL = fileURL }

    func record() {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { linesWhenSent = 0; return }
        linesWhenSent = text.split(separator: "\n").count
    }
}

private struct StubStreamingTransport: HTTPStreamingTransport {
    let status: Int
    var onStream: (@Sendable () -> Void)?

    init(status: Int, onStream: (@Sendable () -> Void)? = nil) {
        self.status = status
        self.onStream = onStream
    }

    func stream(_ request: URLRequest) async throws -> (HTTPURLResponse, AsyncThrowingStream<Data, Error>) {
        onStream?()
        let response = HTTPURLResponse(url: request.url ?? URL(string: "https://example.com")!,
                                       statusCode: status, httpVersion: nil, headerFields: nil)!
        return (response, AsyncThrowingStream { $0.finish() })
    }
}

private struct ThrowingStreamingTransport: HTTPStreamingTransport {
    struct Boom: Error {}
    func stream(_ request: URLRequest) async throws -> (HTTPURLResponse, AsyncThrowingStream<Data, Error>) {
        throw Boom()
    }
}

private struct StubProcessRunner: ExternalProcessRunner {
    let exitCode: Int32
    func run(executable: String, arguments: [String], environment: [String: String],
             onOutput: @escaping @Sendable (String) -> Void) async throws -> Int32 {
        exitCode
    }
}

private struct ThrowingProcessRunner: ExternalProcessRunner {
    func run(executable: String, arguments: [String], environment: [String: String],
             onOutput: @escaping @Sendable (String) -> Void) async throws -> Int32 {
        throw ExternalProcessError.launchFailed(executable: executable, reason: "test")
    }
}
