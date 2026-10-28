import Foundation
import Crypto

/// IM 通道的**传输层**（`FR-AGT-LINK-CHAN-003` 里此前 0 行的那一半）。
///
/// 契约层（`AgentIMChannel.swift`）只管「同一会话 / 审批不放宽 / 未读不丢」；
/// 这一层只管**连得上、断了能自己接回来、心跳能判死**：
///
/// ① **连接状态机**：`idle → connecting → online → waiting(退避) → connecting …`，
///    每一档都带**原因与重试秒数**（界面照抄即可，不必自己猜）；
/// ② **心跳**：每 `heartbeatSeconds` 发一次 `ping`，连续 `maxMissedHeartbeats` 次没等到
///    `pong` ⇒ 判这条连接已死，主动断开重连（不是傻等 TCP 超时）；
/// ③ **退避**：默认 0.5 → 1 → 2 → 4 → 8 → 15 → 30 秒封顶，连上即归零；`stop()` 之后不再重连。
///
/// 凭据只经 `AgentIMCredentials` 出入（AppID 明文 + Secret 在钥匙串）；这一层只收一个
/// **已算好的签名器**，不认识钥匙串、也不落任何密钥。
public struct AgentIMTransportConfig: Equatable, Sendable {

    public var gatewayURL: URL
    /// 心跳间隔（秒）。
    public var heartbeatSeconds: TimeInterval
    /// 连续几次没等到 `pong` 判死。
    public var maxMissedHeartbeats: Int
    /// 退避阶梯（秒）；最后一项是封顶值。
    public var backoff: [TimeInterval]

    public init(gatewayURL: URL,
                heartbeatSeconds: TimeInterval = 30,
                maxMissedHeartbeats: Int = 2,
                backoff: [TimeInterval] = [0.5, 1, 2, 4, 8, 15, 30]) {
        self.gatewayURL = gatewayURL
        self.heartbeatSeconds = max(0.05, heartbeatSeconds)
        self.maxMissedHeartbeats = max(1, maxMissedHeartbeats)
        let ladder = backoff.filter { $0 > 0 }.sorted()
        self.backoff = ladder.isEmpty ? [1] : ladder
    }

    /// 第 `attempt` 次重连该等多久（attempt 从 1 起，超出阶梯就用封顶值）。
    public func delay(forAttempt attempt: Int) -> TimeInterval {
        let index = min(max(1, attempt), backoff.count) - 1
        return backoff[index]
    }
}

/// 连接状态（**机器形态**：界面要与不要都照这一份，不自己编）。
public enum AgentIMConnectionState: Equatable, Sendable {
    case idle
    case connecting(attempt: Int)
    /// `attempt` = 本次连上是第几次尝试（1 = 首次就成）。
    case online(attempt: Int)
    /// `reason` = 机器码（`connectFailed` / `sendFailed` / `receiveFailed` / `heartbeatLost`）。
    case waiting(reason: String, attempt: Int, retryIn: TimeInterval)
    case stopped(reason: String)

    public var isOnline: Bool { if case .online = self { return true }; return false }
}

/// 一帧收发的抽象（真实现走 WebSocket；判据用假的一根根喂）。
public protocol AgentIMSocket: Sendable {
    func open() async throws
    func send(_ text: String) async throws
    /// 收下一帧；对端关闭或出错就抛。
    func receive() async throws -> String
    func close() async
}

/// 建连工厂（把 URL 与握手头交出去）。
public typealias AgentIMSocketFactory = @Sendable (URL, [String: String]) -> any AgentIMSocket

/// 官方网关的**握手口径**（QQ 官方 `op` 码那一套）。
///
/// 为什么要有这一层：自建中继与官方网关是**两套口径** ——
/// 自建中继用本侧约定的 HMAC 头 + `{"op":"ping"}` 心跳；官方网关要 `Authorization: QQBot <token>`、
/// 连上先发 `op=2` Identify、心跳 `op=1`（带 `seq`）、断线 `op=6` 恢复。
/// 把它抽成一个结构注入传输层，两条路共用同一套连接状态机 / 退避 / 补发，只在「怎么握手」上分家。
public struct AgentIMGatewayHandshake: Sendable {

    /// 每次建连要带的头（token 可能刚换过 ⇒ 每次现取，不缓存）。
    public var authorizationHeaders: @Sendable () async -> [String: String]
    /// 连上之后第一帧（Identify）；nil = 不发。
    public var identify: @Sendable () async -> String?
    /// 心跳帧（参数 = 最后一帧的 `seq`，第一跳没有）。
    public var heartbeat: @Sendable (Int?) async -> String
    /// 从一帧里取 `seq`（官方 `s` 字段）；取不到 nil。
    public var sequence: @Sendable (String) -> Int?
    /// 帧的解析（官方口径）。
    public var decode: @Sendable (String, Date) -> AgentIMInboundFrame?

    public init(authorizationHeaders: @escaping @Sendable () async -> [String: String],
                identify: @escaping @Sendable () async -> String?,
                heartbeat: @escaping @Sendable (Int?) async -> String,
                sequence: @escaping @Sendable (String) -> Int?,
                decode: @escaping @Sendable (String, Date) -> AgentIMInboundFrame?) {
        self.authorizationHeaders = authorizationHeaders
        self.identify = identify
        self.heartbeat = heartbeat
        self.sequence = sequence
        self.decode = decode
    }
}

/// 网关签名（`appID + timestamp + nonce + body` 的 HMAC-SHA256）。**只算不存**。
public struct AgentIMGatewaySigner: Sendable {

    public let appID: String
    private let secret: String

    public init(appID: String, secret: String) {
        self.appID = appID
        self.secret = secret
    }

    /// 一次握手 / 一次发送要带的头。
    public func headers(timestamp: Int, nonce: String, body: String) -> [String: String] {
        let message = "\(appID)\n\(timestamp)\n\(nonce)\n\(body)"
        let key = SymmetricKey(data: Data(secret.utf8))
        let code = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
        return [
            "X-App-ID": appID,
            "X-Timestamp": String(timestamp),
            "X-Nonce": nonce,
            "X-Signature": Data(code).map { String(format: "%02x", $0) }.joined(),
        ]
    }

    /// 判据与自检用：签名串的**形状**（不含密钥）。
    public func signaturePreview(timestamp: Int, nonce: String, body: String) -> String {
        headers(timestamp: timestamp, nonce: nonce, body: body)["X-Signature"] ?? ""
    }
}

/// 一帧入站的解析结果（**坏帧不静默丢**：返回 `nil`，由调用方如实记一条）。
public enum AgentIMInboundFrame: Equatable, Sendable {
    case message(AgentIMInboundMessage)
    case pong
    case unknown(op: String)

    /// 宽松解析：认 `op=message`（要 `platformMessageID` / `chatID` / `senderID` / `text`）
    /// 与 `op=pong`；其余 op 原样交回（**不假装懂**）。
    public static func decode(_ text: String, receivedAt: Date = Date()) -> AgentIMInboundFrame? {
        guard let data = text.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let op = root["op"] as? String else { return nil }
        switch op {
        case "pong":
            return .pong
        case "message":
            guard let id = root["platformMessageID"] as? String,
                  let chatID = root["chatID"] as? String,
                  let sender = root["senderID"] as? String,
                  let body = root["text"] as? String else { return nil }
            return .message(AgentIMInboundMessage(platformMessageID: id, chatID: chatID,
                                                  senderID: sender, text: body,
                                                  receivedAt: receivedAt))
        default:
            return .unknown(op: op)
        }
    }
}

public enum AgentIMTransportError: String, Error, Equatable, Sendable {
    case notConnected
    case sendFailed
}

/// 传输层本体：连、心跳、退避、补发。**不认识钥匙串**（凭据由 `AgentIMCredentials` 给）。
public actor AgentIMTransport {

    public static let pingFrame = #"{"op":"ping"}"#

    private let config: AgentIMTransportConfig
    private let signer: AgentIMGatewaySigner
    private let makeSocket: AgentIMSocketFactory
    private let nowFn: @Sendable () -> Date
    private let sleepFn: @Sendable (TimeInterval) async -> Void
    /// 官方握手口径（nil = 自建中继那套：HMAC 头 + `{"op":"ping"}`）。
    private let handshake: AgentIMGatewayHandshake?

    private var loopTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var socket: (any AgentIMSocket)?
    private var stopped = false
    private var missedHeartbeats = 0
    /// 这一轮是不是被心跳判死的（决定重连原因写 `heartbeatLost` 还是 `receiveFailed`）。
    private var lostHeartbeat = false
    private var resultQueue: AgentIMResultQueue?
    private var inboundHandler: (@Sendable (AgentIMInboundFrame) async -> Void)?
    private var stateHandler: (@Sendable (AgentIMConnectionState) async -> Void)?
    /// 官方网关最后一帧的 `seq`（心跳 `op=1` 与恢复 `op=6` 都要带它）。
    private var lastSequence: Int?

    public private(set) var state: AgentIMConnectionState = .idle
    /// 成功建连几次（读数用：重连有没有真的发生过，看它）。
    public private(set) var openAttempts = 0
    /// 当前这一轮连续失败次数（成功即归零）。
    public private(set) var consecutiveFailures = 0

    public init(config: AgentIMTransportConfig,
                signer: AgentIMGatewaySigner,
                makeSocket: @escaping AgentIMSocketFactory,
                now: @escaping @Sendable () -> Date = { Date() },
                sleep: @escaping @Sendable (TimeInterval) async -> Void = { seconds in
                    try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
                },
                handshake: AgentIMGatewayHandshake? = nil) {
        self.config = config
        self.signer = signer
        self.makeSocket = makeSocket
        self.nowFn = now
        self.sleepFn = sleep
        self.handshake = handshake
    }

    // MARK: - 接线

    public func onInbound(_ handler: @escaping @Sendable (AgentIMInboundFrame) async -> Void) {
        inboundHandler = handler
    }

    public func onStateChange(_ handler: @escaping @Sendable (AgentIMConnectionState) async -> Void) {
        stateHandler = handler
    }

    /// 接上待投递队列：每次连上**先补发没 ack 的**，投递成功才 ack（契约层 ③ 的落点）。
    public func attachResultQueue(_ queue: AgentIMResultQueue) {
        resultQueue = queue
    }

    public func snapshot() -> (state: AgentIMConnectionState, openAttempts: Int,
                               consecutiveFailures: Int, missedHeartbeats: Int) {
        (state, openAttempts, consecutiveFailures, missedHeartbeats)
    }

    // MARK: - 起停

    public func start() {
        guard loopTask == nil else { return }
        stopped = false
        loopTask = Task { [weak self] in await self?.runLoop() }
    }

    public func stop(reason: String = "stopped") async {
        stopped = true
        heartbeatTask?.cancel()
        heartbeatTask = nil
        await socket?.close()
        socket = nil
        loopTask?.cancel()
        loopTask = nil
        await publish(.stopped(reason: reason))
    }

    // MARK: - 发送

    public func send(_ text: String) async throws {
        guard state.isOnline, let sock = socket else {
            throw AgentIMTransportError.notConnected
        }
        do {
            try await sock.send(text)
        } catch {
            throw AgentIMTransportError.sendFailed
        }
    }

    /// 一条要带签名的外发帧（签名头随帧交出；**不含密钥**）。
    public func signedEnvelope(_ text: String) -> (frame: String, headers: [String: String]) {
        let timestamp = Int(nowFn().timeIntervalSince1970)
        let nonce = UUID().uuidString
        return (text, signer.headers(timestamp: timestamp, nonce: nonce, body: text))
    }

    /// 补发未投递结果；返回这次真的送出去几条。
    @discardableResult
    public func replayPending() async -> Int {
        guard let queue = resultQueue, state.isOnline else { return 0 }
        var delivered = 0
        for entry in queue.pending() {
            do {
                try await send(entry.text)
                try queue.ack(id: entry.id)
                delivered += 1
            } catch {
                break
            }
        }
        return delivered
    }

    // MARK: - 主循环

    private func runLoop() async {
        while !stopped {
            consecutiveFailures += 1
            let attempt = consecutiveFailures
            await publish(.connecting(attempt: attempt))

            // 官方路径的头每次现取（token 可能刚换过）；自建中继走 HMAC 签名头。
            let headers: [String: String]
            if let handshake {
                headers = await handshake.authorizationHeaders()
            } else {
                let timestamp = Int(nowFn().timeIntervalSince1970)
                let nonce = UUID().uuidString
                headers = signer.headers(timestamp: timestamp, nonce: nonce, body: "")
            }
            let sock = makeSocket(config.gatewayURL, headers)
            socket = sock

            do {
                try await sock.open()
                // 官方网关：连上**先 Identify**（不发这一帧，后面什么事件都收不到）。
                if let handshake {
                    if let identify = await handshake.identify() {
                        try await sock.send(identify)
                    }
                }
            } catch {
                await socket?.close()
                socket = nil
                if stopped { return }
                await waitBeforeRetry(reason: "connectFailed", attempt: attempt)
                continue
            }

            openAttempts += 1
            missedHeartbeats = 0
            lostHeartbeat = false
            consecutiveFailures = 0
            await publish(.online(attempt: attempt))
            await replayPending()
            startHeartbeat(on: sock)

            var reason = "receiveFailed"
            while !stopped {
                if missedHeartbeats >= config.maxMissedHeartbeats {
                    reason = "heartbeatLost"
                    break
                }
                do {
                    let frame = try await sock.receive()
                    if let handshake, let sequence = handshake.sequence(frame) {
                        lastSequence = sequence
                    }
                    let decoded = handshake?.decode(frame, nowFn())
                        ?? AgentIMInboundFrame.decode(frame, receivedAt: nowFn())
                    guard let decoded else { continue }
                    if case .pong = decoded { missedHeartbeats = 0 }
                    if let handler = inboundHandler { await handler(decoded) }
                } catch {
                    reason = stopped ? "stopped" : (lostHeartbeat ? "heartbeatLost" : "receiveFailed")
                    break
                }
            }

            heartbeatTask?.cancel()
            heartbeatTask = nil
            await socket?.close()
            socket = nil
            if stopped { return }
            await waitBeforeRetry(reason: reason, attempt: max(1, attempt))
        }
    }

    private func waitBeforeRetry(reason: String, attempt: Int) async {
        let delay = config.delay(forAttempt: attempt)
        await publish(.waiting(reason: reason, attempt: attempt, retryIn: delay))
        await sleepFn(delay)
    }

    private func startHeartbeat(on sock: any AgentIMSocket) {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self, config] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.sleepFn(config.heartbeatSeconds)
                if Task.isCancelled { return }
                let alive = await self.ping(sock)
                if !alive { return }
            }
        }
    }

    /// 发一次心跳并记账。连丢到上限就**主动掐掉这条连接**（否则 `receive` 会一直挂着，
    /// 判死永远等不到）；被掐断之后主循环会按 `heartbeatLost` 走退避重连。
    private func ping(_ sock: any AgentIMSocket) async -> Bool {
        let frame: String
        if let handshake {
            frame = await handshake.heartbeat(lastSequence)
        } else {
            frame = AgentIMTransport.pingFrame
        }
        do {
            try await sock.send(frame)
        } catch {
            missedHeartbeats = config.maxMissedHeartbeats
            lostHeartbeat = true
            await sock.close()
            return false
        }
        missedHeartbeats += 1
        if missedHeartbeats >= config.maxMissedHeartbeats {
            lostHeartbeat = true
            await sock.close()
            return false
        }
        return true
    }

    private func publish(_ next: AgentIMConnectionState) async {
        state = next
        if let handler = stateHandler { await handler(next) }
    }
}
