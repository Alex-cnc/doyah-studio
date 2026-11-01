import XCTest
import Darwin
@testable import DoyahCore

/// SSH 隧道的**运行时**那一段（FR-CONN-18 判据 ②/④）：真起进程、真探端口、真收进程。
///
/// **本机没有跳板机（22 端口无 sshd），所以这里不假装验过握手。** 验的是我们这一侧的接线：
///   · 就绪判定走**真端口探测**：假 ssh 只要在本机 `-L` 那个地址上开监听，`start` 就必须报就绪；
///   · 收尾不留残留：`stop()` 之后转发进程必须真的没了、端口必须真的关掉（判据 ④「无残留进程」）；
///   · 失败如实分类：真 `/usr/bin/ssh` 连一个没人监听的端口 ⇒ `.processExited`，诊断里是 ssh 的原话，
///     且**口令不许出现在诊断里**（口令只经 askpass 临时文件走，握完手立刻删）；
///   · 外部杀掉 ssh 时状态要能如实改判（`markDeadIfExited`）—— 判据 ② 的前提。
///
/// **未验（如实登记）**：真跳板机上的密码 / 私钥握手、`-L` 建起来之后的**字节**是否真被转发
/// （那是 `ssh` 自己的事，没有跳板机就验不了）。
final class SSHTunnelRuntimeTests: XCTestCase {

    // MARK: - 装配

    /// 假 ssh：不握手、不转发，只在本机 `127.0.0.1:<port>` 上监听并睡到被杀。
    /// 真 ssh 建好 `-L` 之后的样子就是「这个端口通了、进程还在」，就绪判定量的正是这两件事。
    private func makeListenerStub(port: Int) throws -> String {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("doyah-ssh-stub-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = directory.appendingPathComponent("ssh")
        let body = """
        #!/bin/sh
        # 假 ssh（探针用）：在固定端口上开监听并一直活着
        exec /usr/bin/env python3 -c "
        import socket, time
        s = socket.socket()
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.bind(('127.0.0.1', \(port)))
        s.listen(8)
        time.sleep(120)
        "
        """
        try Data(body.utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        return script.path
    }

    private func freePort() -> Int {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return 0 }
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { return 0 }
        var result = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &result) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &length)
            }
        }
        guard named == 0 else { return 0 }
        return Int(UInt16(bigEndian: result.sin_port))
    }

    private func probe(host: String, port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(port).bigEndian)
        inet_pton(AF_INET, host, &address.sin_addr)
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }

    private func tunnel(
        localPort: Int,
        executable: String,
        config: SSHTunnelConfig,
        password: String? = nil
    ) -> SSHTunnelProcess {
        SSHTunnelProcess(
            config: config,
            target: SSHTunnelTarget(host: "10.0.0.9", port: 5432),
            localPort: localPort,
            knownHostsPath: NSTemporaryDirectory() + "doyah-runtime-known-hosts-\(UUID().uuidString)",
            password: password,
            executable: executable,
            isPortOpen: { [weak self] host, port in self?.probe(host: host, port: port) ?? false }
        )
    }

    // MARK: - 就绪判定 + 无残留（判据 ④）

    func testReadyFollowsTheRealPortAndStopLeavesNoProcessBehind() async throws {
        let port = freePort()
        XCTAssertGreaterThan(port, 1024, "没拿到可用的本机端口 —— 这条用例的前提没成立")
        let executable = try makeListenerStub(port: port)
        let tunnel = tunnel(
            localPort: port,
            executable: executable,
            config: SSHTunnelConfig(host: "jump.example.com", username: "alice", authentication: .agent)
        )

        let readyPort = try await tunnel.start(timeout: 10, language: .simplifiedChinese)
        XCTAssertEqual(readyPort, port)
        XCTAssertEqual(tunnel.currentState, .ready(localPort: port), "端口通了就该报就绪")
        XCTAssertTrue(tunnel.isAlive, "报了就绪就必须有活着的转发进程")
        XCTAssertTrue(probe(host: "127.0.0.1", port: port), "就绪之后本机端口必须真的通")
        XCTAssertNotNil(tunnel.processIdentifier)

        tunnel.stop()
        XCTAssertEqual(tunnel.currentState, .stopped)
        XCTAssertFalse(tunnel.isAlive, "stop() 之后不许留活着的进程（判据 ④）")
        XCTAssertNil(tunnel.processIdentifier)

        // 端口关闭是异步的：给一点时间，最终必须关掉（否则下一次连接会撞到别人的监听）。
        var closed = false
        for _ in 0..<40 {
            if !probe(host: "127.0.0.1", port: port) { closed = true; break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(closed, "stop() 之后本机端口还开着 —— 会留下一个「看着通、其实是别人的」端口")
    }

    /// 端口被占着时不许报就绪（状态栏那次实测踩到的坑，运行时版）。
    func testBusyPortFailsFastWithoutStartingAnything() async throws {
        let port = freePort()
        XCTAssertGreaterThan(port, 1024)
        let executable = try makeListenerStub(port: port)
        let busy = tunnel(
            localPort: port,
            executable: executable,
            config: SSHTunnelConfig(host: "jump", username: "alice", authentication: .agent)
        )
        // 先把端口占上（用假 ssh 自己占）
        let occupy = Process()
        occupy.executableURL = URL(fileURLWithPath: executable)
        try occupy.run()
        defer { occupy.terminate() }
        for _ in 0..<40 where !probe(host: "127.0.0.1", port: port) {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        do {
            _ = try await busy.start(timeout: 3, language: .simplifiedChinese)
            XCTFail("端口已被占用时不该报就绪")
        } catch let error as SSHTunnelError {
            XCTAssertEqual(error, .portInUse(port))
        }
        XCTAssertFalse(busy.isAlive, "端口被占时我们自己的 ssh 一个都不该起")
    }

    // MARK: - 失败分类 + 口令不外泄（判据 ②/④）

    /// 真 `/usr/bin/ssh`、真失败：连一个没人监听的端口 ⇒ `.processExited`，诊断里是 ssh 的原话。
    ///
    /// 顺带钉住两条：① 口令**不许**出现在诊断里（诊断面是给人看、给日志抄的）；
    /// ② askpass 临时目录（0600 口令文件所在）用完必须删掉 —— 它留在盘上就是明文口令。
    func testRealSSHFailureIsClassifiedAndLeavesNoSecretBehind() async throws {
        guard !probe(host: "127.0.0.1", port: 22) else {
            throw XCTSkip("本机 22 端口有 sshd —— 这条用例要的是一个一定会被拒的端口")
        }
        let port = freePort()
        XCTAssertGreaterThan(port, 1024)
        let secret = "s3cr3t-do-not-leak-\(UUID().uuidString.prefix(8))"
        let config = SSHTunnelConfig(host: "127.0.0.1", port: 22, username: "nobody", authentication: .password)
        let tunnel = self.tunnel(localPort: port, executable: "/usr/bin/ssh", config: config, password: secret)

        let leftoversBefore = Set(tunnelTemporaryDirectories())

        do {
            _ = try await tunnel.start(timeout: 10, language: .simplifiedChinese)
            XCTFail("127.0.0.1:22 没有 sshd，隧道不该报成功")
        } catch let error as SSHTunnelError {
            guard case .processExited(let reason) = error else {
                return XCTFail("失败分类不对：\(error)")
            }
            XCTAssertFalse(reason.isEmpty)
            XCTAssertTrue(
                reason.lowercased().contains("ssh") || reason.lowercased().contains("refused"),
                "诊断里应当带着 ssh 的原话，实际：\(reason)"
            )
            XCTAssertFalse(reason.contains(secret), "口令出现在诊断里了：\(reason)")
        }
        if case .failed(let reason) = tunnel.currentState {
            XCTAssertFalse(reason.contains(secret), "状态里的原因带着口令：\(reason)")
        } else {
            XCTFail("失败之后状态应当是 .failed，实际：\(tunnel.currentState)")
        }
        XCTAssertFalse(tunnel.isAlive)

        // 口令临时目录（doyah-tunnel-*）不许留在盘上。
        let leftoversAfter = Set(tunnelTemporaryDirectories())
        XCTAssertEqual(leftoversAfter.subtracting(leftoversBefore), [], "askpass 临时目录没清干净")
    }

    // MARK: - 外部杀掉 ssh（判据 ② 的前提）

    func testMarkDeadIfExitedTurnsAStaleReadyStateIntoFailed() async throws {
        let port = freePort()
        XCTAssertGreaterThan(port, 1024)
        let executable = try makeListenerStub(port: port)
        let tunnel = tunnel(
            localPort: port,
            executable: executable,
            config: SSHTunnelConfig(host: "jump", username: "alice", authentication: .agent)
        )
        _ = try await tunnel.start(timeout: 10, language: .simplifiedChinese)
        XCTAssertEqual(tunnel.currentState, .ready(localPort: port))

        // 还活着的时候**不许**改判（否则一句无关的报错会被说成隧道问题）。
        XCTAssertFalse(tunnel.markDeadIfExited(language: .simplifiedChinese))

        let pid = try XCTUnwrap(tunnel.processIdentifier)
        kill(pid, SIGKILL)
        for _ in 0..<60 where tunnel.isAlive {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertFalse(tunnel.isAlive, "SIGKILL 之后进程还在？")
        XCTAssertEqual(
            tunnel.currentState, .ready(localPort: port),
            "外部杀进程时状态会停在 ready —— 这正是 `markDeadIfExited` 要兜的那个洞"
        )

        XCTAssertTrue(tunnel.markDeadIfExited(language: .simplifiedChinese), "进程没了就该改判")
        guard case .failed(let reason) = tunnel.currentState else {
            return XCTFail("改判后的状态应当是 .failed，实际：\(tunnel.currentState)")
        }
        XCTAssertTrue(reason.contains("ssh"), "改判的理由里应当说清是 ssh 退出了：\(reason)")
        XCTAssertFalse(tunnel.markDeadIfExited(language: .simplifiedChinese), "已经改判过就不许反复改")
    }

    // MARK: - 辅助

    private func tunnelTemporaryDirectories() -> [String] {
        let root = NSTemporaryDirectory()
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []
        return names.filter { $0.hasPrefix("doyah-tunnel-") }.map { root + $0 }
    }
}
