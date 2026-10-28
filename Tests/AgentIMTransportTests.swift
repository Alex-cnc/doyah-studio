import XCTest
@testable import DoyahCore

/// `FR-AGT-LINK-CHAN-003` 传输层的判据：连、心跳、退避、补发、签名。
final class AgentIMTransportTests: XCTestCase {

    // MARK: - 假件

    /// 可推可关的收帧信箱（模拟对端推帧 / 断开）。
    private actor Mailbox {
        private var buffer: [String] = []
        private var waiters: [CheckedContinuation<String, Error>] = []
        private var closed = false

        func push(_ frame: String) {
            if let waiter = waiters.first {
                waiters.removeFirst()
                waiter.resume(returning: frame)
            } else {
                buffer.append(frame)
            }
        }

        func next() async throws -> String {
            if !buffer.isEmpty { return buffer.removeFirst() }
            if closed { throw CancellationError() }
            return try await withCheckedThrowingContinuation { continuation in
                waiters.append(continuation)
            }
        }

        func close() {
            closed = true
            for waiter in waiters { waiter.resume(throwing: CancellationError()) }
            waiters.removeAll()
        }
    }

    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var _sent: [String] = []
        private var _opens = 0
        private var _closes = 0
        private var _headers: [[String: String]] = []
        private var _delays: [TimeInterval] = []

        func sent(_ text: String) { lock.lock(); _sent.append(text); lock.unlock() }
        func opened() { lock.lock(); _opens += 1; lock.unlock() }
        func closed() { lock.lock(); _closes += 1; lock.unlock() }
        func handshook(_ headers: [String: String]) { lock.lock(); _headers.append(headers); lock.unlock() }
        func delayed(_ seconds: TimeInterval) { lock.lock(); _delays.append(seconds); lock.unlock() }

        var sentFrames: [String] { lock.lock(); defer { lock.unlock() }; return _sent }
        var opens: Int { lock.lock(); defer { lock.unlock() }; return _opens }
        var closes: Int { lock.lock(); defer { lock.unlock() }; return _closes }
        var handshakes: [[String: String]] { lock.lock(); defer { lock.unlock() }; return _headers }
        var delays: [TimeInterval] { lock.lock(); defer { lock.unlock() }; return _delays }
    }

    private final class FakeSocket: AgentIMSocket, @unchecked Sendable {
        let box = Mailbox()
        let recorder: Recorder
        /// 这一条连接：open 是否失败；收到 ping 是否自动回 pong（模拟健康的对端）。
        let failsOpen: Bool
        let answersPing: Bool

        init(recorder: Recorder, failsOpen: Bool = false, answersPing: Bool = true) {
            self.recorder = recorder
            self.failsOpen = failsOpen
            self.answersPing = answersPing
        }

        func open() async throws {
            recorder.opened()
            recorder.handshook([:])
            if failsOpen { throw CancellationError() }
        }

        func send(_ text: String) async throws {
            recorder.sent(text)
            if answersPing, text.contains("\"ping\"") { await box.push(#"{"op":"pong"}"#) }
        }

        func receive() async throws -> String { try await box.next() }

        func close() async {
            recorder.closed()
            await box.close()
        }
    }

    /// 每次建连给一条新 socket；按脚本决定第几条开始能连上。
    private final class Factory: @unchecked Sendable {
        private let lock = NSLock()
        private var _made: [FakeSocket] = []
        let recorder: Recorder
        /// 前 N 次 open 失败。
        var failingConnections: Int
        var answersPing: Bool
        var frames: [String]

        init(recorder: Recorder, failingConnections: Int = 0, answersPing: Bool = true,
             frames: [String] = []) {
            self.recorder = recorder
            self.failingConnections = failingConnections
            self.answersPing = answersPing
            self.frames = frames
        }

        func make() -> FakeSocket {
            lock.lock()
            let willFail = failingConnections > 0
            if willFail { failingConnections -= 1 }
            let socket = FakeSocket(recorder: recorder, failsOpen: willFail, answersPing: answersPing)
            _made.append(socket)
            let seeded = frames
            lock.unlock()
            for frame in seeded {
                Task { await socket.box.push(frame) }
                frames = []
            }
            return socket
        }

        var made: [FakeSocket] { lock.lock(); defer { lock.unlock() }; return _made }
    }

    private func transport(_ factory: Factory, recorder: Recorder,
                           heartbeat: TimeInterval = 30,
                           maxMissed: Int = 2,
                           backoff: [TimeInterval] = [0.5, 1, 2]) -> AgentIMTransport {
        AgentIMTransport(
            config: AgentIMTransportConfig(gatewayURL: URL(string: "wss://gateway.test/ws")!,
                                           heartbeatSeconds: heartbeat,
                                           maxMissedHeartbeats: maxMissed,
                                           backoff: backoff),
            signer: AgentIMGatewaySigner(appID: "12345678", secret: "s3cret"),
            makeSocket: { _, headers in
                recorder.handshook(headers)
                return factory.make()
            },
            // 记录退避档位；**真睡**（封顶 0.2 秒，别把测试拖成分钟级）——
            // 睡成空转会让心跳与重连在同一刻反复触发（判据会看到几千次建连）。
            sleep: { seconds in
                recorder.delayed(seconds)
                try? await Task.sleep(nanoseconds: UInt64(min(seconds, 0.2) * 1_000_000_000))
            })
    }

    private func waitUntil(_ timeout: TimeInterval = 2,
                           _ condition: @Sendable () async -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return await condition()
    }

    // ① 连上即 online，且握手带了签名头（AppID / 时间戳 / nonce / 签名）
    func testConnectsAndReportsOnlineWithSignedHandshake() async {
        let recorder = Recorder()
        let factory = Factory(recorder: recorder)
        let link = transport(factory, recorder: recorder)
        await link.start()
        let online = await waitUntil { await link.snapshot().state.isOnline }
        XCTAssertTrue(online)
        let handshake = recorder.handshakes.first ?? [:]
        XCTAssertEqual(handshake["X-App-ID"], "12345678")
        XCTAssertNotNil(handshake["X-Timestamp"])
        XCTAssertNotNil(handshake["X-Nonce"])
        XCTAssertEqual(handshake["X-Signature"]?.count, 64)
        await link.stop()
    }

    // ② 第一次连不上 ⇒ 按退避等 0.5 秒再来，第二次连上（attempt = 2）
    func testReconnectsAfterFailureWithBackoff() async {
        let recorder = Recorder()
        let factory = Factory(recorder: recorder, failingConnections: 1)
        let link = transport(factory, recorder: recorder)
        await link.start()
        let online = await waitUntil { await link.snapshot().state.isOnline }
        XCTAssertTrue(online)
        XCTAssertEqual(recorder.delays.first, 0.5, "第一次退避 = 阶梯第一档")
        XCTAssertEqual(factory.made.count, 2)
        let snapshot = await link.snapshot()
        XCTAssertEqual(snapshot.openAttempts, 1, "只有一次真建成")
        XCTAssertEqual(snapshot.consecutiveFailures, 0, "连上即归零")
        await link.stop()
    }

    // ③ stop 之后不再重连
    func testStopPreventsFurtherReconnects() async {
        let recorder = Recorder()
        let factory = Factory(recorder: recorder, failingConnections: 99)
        let link = transport(factory, recorder: recorder)
        await link.start()
        _ = await waitUntil { await link.snapshot().state.hasWaited }
        await link.stop(reason: "userStopped")
        let made = factory.made.count
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(factory.made.count, made, "停了就不许再建连")
        if case .stopped(let reason) = await link.snapshot().state {
            XCTAssertEqual(reason, "userStopped")
        } else {
            XCTFail("状态应为 stopped")
        }
    }

    // ④ 心跳按间隔发 ping（健康的对端回 pong ⇒ 一直在线）
    func testHeartbeatSendsPingFrames() async {
        let recorder = Recorder()
        let factory = Factory(recorder: recorder)
        let link = transport(factory, recorder: recorder, heartbeat: 0.05)
        await link.start()
        _ = await waitUntil { await link.snapshot().state.isOnline }
        let pinged = await waitUntil(2) {
            recorder.sentFrames.filter { $0.contains("\"ping\"") }.count >= 2
        }
        XCTAssertTrue(pinged, "没按间隔发心跳：\(recorder.sentFrames)")
        // 让 pong 落地再看：**健康连接不该被心跳判死**（判据看「有没有重连」，不看某一刻的计数）
        try? await Task.sleep(nanoseconds: 120_000_000)
        let snapshot = await link.snapshot()
        XCTAssertEqual(snapshot.missedHeartbeats, 0, "回了 pong 计数要归零")
        XCTAssertEqual(factory.made.count, 1, "健康连接不许重连")
        await link.stop()
    }

    // ⑤ 对端不回 pong ⇒ 连丢到上限判死，主动断开重连
    func testHeartbeatLossForcesReconnect() async {
        let recorder = Recorder()
        let factory = Factory(recorder: recorder, answersPing: false)
        let link = transport(factory, recorder: recorder, heartbeat: 0.05, maxMissed: 2)
        await link.start()
        let reconnected = await waitUntil(3) { factory.made.count >= 2 }
        XCTAssertTrue(reconnected, "心跳判死后没重连")
        XCTAssertTrue(recorder.sentFrames.filter { $0.contains("\"ping\"") }.count >= 2)
        await link.stop()
    }

    // ⑥ 入站消息交给上层（平台字段原样）
    func testInboundMessageIsDelivered() async {
        let recorder = Recorder()
        let factory = Factory(recorder: recorder, frames: [
            #"{"op":"message","platformMessageID":"m1","chatID":"c1","senderID":"u1","text":"看一下慢查询"}"#,
        ])
        let link = transport(factory, recorder: recorder)
        let received = XCTestExpectation(description: "inbound")
        await link.onInbound { frame in
            if case .message(let message) = frame, message.platformMessageID == "m1",
               message.text == "看一下慢查询" {
                received.fulfill()
            }
        }
        await link.start()
        await fulfillment(of: [received], timeout: 2)
        await link.stop()
    }

    // ⑦ 重连后先补发没 ack 的结果（契约层 ③）
    func testPendingResultsAreReplayedAndAcked() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("im-queue-\(UUID().uuidString)")
        let queue = AgentIMResultQueue(directory: dir)
        try queue.enqueue(chatID: "c1", text: "结果一", id: "r1")
        try queue.enqueue(chatID: "c1", text: "结果二", id: "r2")

        let recorder = Recorder()
        let factory = Factory(recorder: recorder)
        let link = transport(factory, recorder: recorder)
        await link.attachResultQueue(queue)
        await link.start()
        _ = await waitUntil { await link.snapshot().state.isOnline }
        let drained = await waitUntil(2) { queue.pending().isEmpty }
        XCTAssertTrue(drained, "没补发完：\(queue.pending())")
        XCTAssertTrue(recorder.sentFrames.contains("结果一"))
        XCTAssertTrue(recorder.sentFrames.contains("结果二"))
        await link.stop()
    }

    // ⑧ 签名：同输入同签名、换 nonce 变、**密钥不出现在任何头里**
    func testSignerIsDeterministicAndLeaksNothing() {
        let signer = AgentIMGatewaySigner(appID: "12345678", secret: "s3cret-T0KEN")
        let digest = signer.signaturePreview(timestamp: 1_700_000_000, nonce: "n1", body: "{}")
        let again = signer.signaturePreview(timestamp: 1_700_000_000, nonce: "n1", body: "{}")
        let other = signer.signaturePreview(timestamp: 1_700_000_000, nonce: "n2", body: "{}")
        XCTAssertEqual(digest, again)
        XCTAssertNotEqual(digest, other)
        XCTAssertEqual(digest.count, 64)
        let headers = signer.headers(timestamp: 1, nonce: "n", body: "x")
        for value in headers.values {
            XCTAssertFalse(value.contains("s3cret"), "密钥不许出现在外发头里")
        }
    }

    // ⑨ 退避阶梯：逐档递增、超出封顶不涨
    func testBackoffLadderAndCap() {
        let config = AgentIMTransportConfig(gatewayURL: URL(string: "wss://x.test/ws")!,
                                           backoff: [0.5, 1, 2, 4])
        XCTAssertEqual((1...6).map { config.delay(forAttempt: $0) }, [0.5, 1, 2, 4, 4, 4])
    }

    // ⑩ 坏帧不装懂：不是 JSON / 缺字段 ⇒ nil；不认识的 op 原样交出
    func testFrameDecodingRejectsBadFramesAndKeepsUnknownOps() {
        XCTAssertNil(AgentIMInboundFrame.decode("不是 JSON"))
        XCTAssertNil(AgentIMInboundFrame.decode(#"{"op":"message","chatID":"c"}"#))
        XCTAssertEqual(AgentIMInboundFrame.decode(#"{"op":"notice"}"#), .unknown(op: "notice"))
        XCTAssertEqual(AgentIMInboundFrame.decode(#"{"op":"pong"}"#), .pong)
    }
}

private extension AgentIMConnectionState {
    var hasWaited: Bool { if case .waiting = self { return true }; return false }
}
