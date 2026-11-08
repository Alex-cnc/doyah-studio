import Foundation
import DoyahCore
import DoyahPlatform

/// 五环自检里「真连一次」的那三环（握手 / 收一帧 / 发一帧）**共用一条连接**。
///
/// 为什么要共用：三环各开一条连接，第二次握手会被网关当成另一个会话（`READY` 里给的
/// `session_id` 不同），「收一帧」收的是自己的 Hello 而不是会话里的事件 —— 读数会变成
/// 一条好看但没意义的绿。这里按**一次真实连接**的顺序量：
/// 建连 → Identify → 第一帧（握手成功）→ 第二帧（收一帧）→ 发一次心跳（发一帧）。
///
/// 它是 actor：三环由 `AgentIMSelfCheckRunner` 顺序调用，但探针闭包在并发域里，
/// 「开过没 / socket 是谁」必须串行改。
actor AgentIMSelfCheckLiveSession {

    private let provision: @Sendable () async throws -> AgentIMQQProvisioning
    private let makeSocket: AgentIMSocketFactory
    private let language: AppLanguage
    private let timeout: TimeInterval

    private var socket: (any AgentIMSocket)?
    private var started = false

    init(provision: @escaping @Sendable () async throws -> AgentIMQQProvisioning,
         makeSocket: @escaping AgentIMSocketFactory,
         language: AppLanguage,
         timeout: TimeInterval = 6) {
        self.provision = provision
        self.makeSocket = makeSocket
        self.language = language
        self.timeout = max(1, timeout)
    }

    /// ③ 握手：建连 + Identify + 等到第一帧。
    func handshake() async -> AgentIMSelfCheckStep {
        guard !started else {
            return .fail("probeOrder", LocalizedStrings.text(.agentIMSelfCheckNotRun, language: language))
        }
        started = true
        let provisioning: AgentIMQQProvisioning
        do {
            provisioning = try await provision()
        } catch let problem as AgentIMQQProvisionProblem {
            return .fail(problem.code, AgentIMQQProvisionText.line(for: problem, language: language))
        } catch {
            return .fail("tokenUnavailable",
                         LocalizedStrings.text(.agentIMQQNetworkFailed, language: language))
        }
        let sock = makeSocket(provisioning.gateway.url, provisioning.token.authorizationHeaders)
        socket = sock
        do {
            try await sock.open()
        } catch {
            await sock.close()
            socket = nil
            return .fail("connectFailed",
                         LocalizedStrings.text(.agentIMTestOpenFailed, language: language))
        }
        do {
            try await sock.send(AgentIMQQHandshake.identifyFrame(token: provisioning.token))
        } catch {
            await sock.close()
            socket = nil
            return .fail("sendFailed",
                         LocalizedStrings.text(.agentIMTestSendFailed, language: language))
        }
        guard let frame = await nextFrame(from: sock) else {
            await sock.close()
            socket = nil
            return .fail("noResponse",
                         LocalizedStrings.format(.agentIMTestNoResponse, language: language,
                                                 Int64(timeout.rounded(.up))))
        }
        return .pass(LocalizedStrings.format(.agentIMSelfCheckHandshakeDetail, language: language,
                                             Self.sessionDigest(frame)))
    }

    /// ④ 收一帧：握手之后网关继续发来的下一帧（Hello / 心跳应答 / 任何事件）。
    func receive() async -> AgentIMSelfCheckStep {
        guard let sock = socket else {
            return .fail("notConnected", LocalizedStrings.text(.agentIMSelfCheckNotRun, language: language))
        }
        guard let frame = await nextFrame(from: sock) else {
            return .fail("noResponse",
                         LocalizedStrings.format(.agentIMTestNoResponse, language: language,
                                                 Int64(timeout.rounded(.up))))
        }
        return .pass(LocalizedStrings.format(.agentIMSelfCheckReceiveDetail, language: language,
                                             Self.frameKind(frame)))
    }

    /// ⑤ 发一帧：发一次心跳。**量的是发送路径通**（写出成功），不是「对方收到了」——
    /// 这一环的读数必须说清这一点，别把「写进 socket」说成「送到手机」。
    func send() async -> AgentIMSelfCheckStep {
        guard let sock = socket else {
            return .fail("notConnected", LocalizedStrings.text(.agentIMSelfCheckNotRun, language: language))
        }
        let frame = AgentIMQQHandshake.heartbeatFrame(sequence: nil)
        do {
            try await sock.send(frame)
        } catch {
            return .fail("sendFailed",
                         LocalizedStrings.text(.agentIMTestSendFailed, language: language))
        }
        return .pass(LocalizedStrings.format(.agentIMSelfCheckSendDetail, language: language,
                                             "\(frame.count) B"))
    }

    func close() async {
        await socket?.close()
        socket = nil
    }

    // MARK: - 内部

    /// 丢一帧 vs 到点：先到的那个算数（与 `AgentIMConnectivityProbe` 同一口径）。
    private func nextFrame(from sock: any AgentIMSocket) async -> String? {
        let seconds = timeout
        return await withTaskGroup(of: String?.self) { group in
            group.addTask { (try? await sock.receive()) ?? nil }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    /// `READY` 里的 `session_id` 尾 8 位（没有就报 op）—— 读数要能对账，但不能太长。
    static func sessionDigest(_ frame: String) -> String {
        guard let data = frame.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "op=?"
        }
        let body = root["d"] as? [String: Any]
        let session = (body?["session_id"] as? String) ?? (root["session_id"] as? String) ?? ""
        if !session.isEmpty { return String(session.suffix(8)) }
        // 老口径（自建中继）：op 字段就够说明「收到的是哪一类帧」。
        return (root["op"] as? String) ?? "op=?"
    }

    static func frameKind(_ frame: String) -> String {
        guard let data = frame.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "\(frame.count) B"
        }
        let op = (root["op"] as? Int).map(String.init) ?? (root["op"] as? String) ?? "?"
        let type = root["t"] as? String
        return type.map { "op=\(op) · \($0)" } ?? "op=\(op)"
    }
}
