import XCTest
@testable import DoyahCore

/// DAP 传输层（`FR-STD-WS-TOOL-003` 第二片）。
///
/// 用**假适配器**（一个按 DAP 说话的小脚本）测传输，不依赖 lldb：
/// 真适配器还要用 `DOYAH_DAP_SMOKE=1` 另跑一遍（`DAPSmokeTests`），两者分开 ——
/// 否则「本机没装 lldb」会把传输层的绿/红搅在一起。
final class DAPClientTests: XCTestCase {

    // MARK: - 假适配器

    private static let fakeAdapter = #"""
#!/usr/bin/env python3
import json, os, sys, time

MODE = os.environ.get("FAKE_DAP_MODE", "normal")
PROGRAM = os.environ.get("FAKE_DAP_PROGRAM", "/tmp/program")

def read_message():
    length = None
    while True:
        line = sys.stdin.buffer.readline()
        if not line:
            return None
        line = line.decode("utf-8").strip()
        if not line:
            break
        if line.lower().startswith("content-length:"):
            length = int(line.split(":")[1])
    if length is None:
        return None
    return json.loads(sys.stdin.buffer.read(length).decode("utf-8"))

def send(obj):
    body = json.dumps(obj).encode("utf-8")
    sys.stdout.buffer.write(b"Content-Length: %d\r\n\r\n" % len(body) + body)
    sys.stdout.buffer.flush()

if MODE == "exit":
    sys.stderr.write("adapter blew up\n")
    sys.exit(3)

seq = 0
LINE = 7
while True:
    msg = read_message()
    if msg is None:
        break
    if MODE == "silent":
        continue
    seq += 1
    cmd = msg.get("command")
    if cmd == "initialize":
        send({"seq": seq, "type": "response", "request_seq": msg["seq"], "success": True,
              "command": cmd, "body": {"supportsConfigurationDoneRequest": True}})
        send({"seq": seq, "type": "event", "event": "initialized"})
    elif cmd == "launch":
        send({"seq": seq, "type": "response", "request_seq": msg["seq"], "success": True, "command": cmd})
    elif cmd == "setBreakpoints":
        send({"seq": seq, "type": "response", "request_seq": msg["seq"], "success": True, "command": cmd,
              "body": {"breakpoints": [{"verified": True, "line": 7}]}})
    elif cmd == "configurationDone":
        send({"seq": seq, "type": "response", "request_seq": msg["seq"], "success": True, "command": cmd})
        send({"seq": seq, "type": "event", "event": "stopped", "body": {"reason": "breakpoint", "threadId": 1}})
    elif cmd in ("next", "stepIn", "stepOut", "continue"):
        send({"seq": seq, "type": "response", "request_seq": msg["seq"], "success": True, "command": cmd})
        if cmd == "next":
            LINE += 1
        send({"seq": seq, "type": "event", "event": "stopped",
              "body": {"reason": "step" if cmd != "continue" else "breakpoint", "threadId": 1}})
    elif cmd == "stackTrace":
        send({"seq": seq, "type": "response", "request_seq": msg["seq"], "success": True, "command": cmd,
              "body": {"stackFrames": [{"id": 11, "line": LINE, "name": "main",
                                        "source": {"path": PROGRAM}}]}})
    elif cmd == "scopes":
        send({"seq": seq, "type": "response", "request_seq": msg["seq"], "success": True, "command": cmd,
              "body": {"scopes": [{"name": "Locals", "variablesReference": 5},
                                  {"name": "Globals", "variablesReference": 0}]}})
    elif cmd == "variables":
        send({"seq": seq, "type": "response", "request_seq": msg["seq"], "success": True, "command": cmd,
              "body": {"variables": [{"name": "total", "value": "42"},
                                     {"name": "label", "value": "\"hi\""}]}})
    elif cmd == "disconnect":
        send({"seq": seq, "type": "response", "request_seq": msg["seq"], "success": True, "command": cmd})
        break
    else:
        send({"seq": seq, "type": "response", "request_seq": msg["seq"], "success": False,
              "command": cmd, "message": "unsupported"})
"""#

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("dap-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func adapter(mode: String) throws -> String {
        let url = tempDir.appendingPathComponent("fake-dap-\(mode).py")
        try Self.fakeAdapter.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        setenv("FAKE_DAP_MODE", mode, 1)
        return url.path
    }

    // MARK: - 正常会话

    func testMinimalSessionStopsAtBreakpointAndReadsVariables() throws {
        setenv("FAKE_DAP_PROGRAM", "/tmp/hello.c", 1)
        let session = DAPSession(client: DAPClient(adapterPath: try adapter(mode: "normal")))
        let program = "/tmp/hello.c"

        let outcome = try session.runUntilStop(program: program, breakpoints: [program: [7]], waitSeconds: 8)
        guard case .stopped(let location) = outcome else {
            return XCTFail("应停在断点，实际：\(outcome)")
        }
        XCTAssertEqual(location.line, 7)
        XCTAssertEqual(location.file, program)
        XCTAssertEqual(location.reason, "breakpoint")

        let variables = try session.variables(threadId: location.threadId)
        XCTAssertEqual(variables["total"], "42", "变量要能读到值：\(variables)")
        XCTAssertEqual(variables["label"], "\"hi\"")
        session.disconnect()
    }

    func testStepOverMovesToNextLineAndStillStops() throws {
        setenv("FAKE_DAP_PROGRAM", "/tmp/hello.c", 1)
        let session = DAPSession(client: DAPClient(adapterPath: try adapter(mode: "normal")))
        let program = "/tmp/hello.c"
        guard case .stopped(let first) = try session.runUntilStop(program: program, breakpoints: [program: [7]], waitSeconds: 8) else {
            return XCTFail("第一停没停住")
        }
        XCTAssertEqual(first.line, 7)

        guard case .stopped(let second) = try session.step(.over, threadId: first.threadId, waitSeconds: 8) else {
            return XCTFail("单步后应再次停住")
        }
        XCTAssertEqual(second.line, 8, "步过应前进一行")
        XCTAssertEqual(second.reason, "step")
        session.disconnect()
    }

    /// 事件先于响应到达时，不许把「响应回来」当成「停下来了」（假停）。假适配器就是先发响应再发事件，
    /// 这里额外核一次：步进返回的必须是事件里的行号，而不是上一次的缓存。
    func testStepDoesNotReturnStaleLine() throws {
        setenv("FAKE_DAP_PROGRAM", "/tmp/hello.c", 1)
        let session = DAPSession(client: DAPClient(adapterPath: try adapter(mode: "normal")))
        let program = "/tmp/hello.c"
        guard case .stopped(let first) = try session.runUntilStop(program: program, breakpoints: [program: [7]], waitSeconds: 8) else {
            return XCTFail("第一停没停住")
        }
        for expected in [8, 9] {
            guard case .stopped(let stop) = try session.step(.over, threadId: first.threadId, waitSeconds: 8) else {
                return XCTFail("单步后应停住")
            }
            XCTAssertEqual(stop.line, expected, "连续步过的行号必须递增，不许返回旧值")
        }
        session.disconnect()
    }

    // MARK: - 失败要分开报（判据：不许统一成一句 debug failed）

    func testMissingAdapterIsReportedAsNotFound() {
        let client = DAPClient(adapterPath: "/nonexistent/lldb-dap-xyz")
        XCTAssertThrowsError(try client.start()) { error in
            XCTAssertEqual(error as? DAPClient.Failure, .adapterNotFound(path: "/nonexistent/lldb-dap-xyz"))
        }
    }

    func testAdapterExitingImmediatelyIsReportedWithTail() throws {
        let client = DAPClient(adapterPath: try adapter(mode: "exit"), timeoutSeconds: 5)
        var failure: DAPClient.Failure?
        do {
            try client.start()
            _ = try client.request("initialize", [:])
        } catch let error as DAPClient.Failure {
            failure = error
        } catch {
            return XCTFail("非预期错误：\(error)")
        }
        guard let failure else { return XCTFail("应报错，实际没报") }
        switch failure {
        case .adapterExited(let code):
            XCTAssertNotEqual(code, 0)
        case .protocolBroken(let text):
            XCTAssertTrue(text.contains("adapter blew up"), "要把适配器自己的话带出来：\(text)")
        default:
            XCTFail("应是退出类失败，实际：\(failure)")
        }
    }

    func testSilentAdapterTimesOutInsteadOfHanging() throws {
        let client = DAPClient(adapterPath: try adapter(mode: "silent"), timeoutSeconds: 1)
        try client.start()
        let started = Date()
        XCTAssertThrowsError(try client.request("initialize", [:])) { error in
            guard case .timeout(let command, let seconds)? = error as? DAPClient.Failure else {
                return XCTFail("应报超时，实际：\(error)")
            }
            XCTAssertEqual(command, "initialize")
            XCTAssertEqual(seconds, 1)
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 5, "超时必须真的在 1 秒左右返回，不许挂着")
        client.stop()
    }

    func testRejectedCommandSurfacesAdapterMessage() throws {
        let client = DAPClient(adapterPath: try adapter(mode: "normal"), timeoutSeconds: 5)
        try client.start()
        _ = try client.request("initialize", [:])
        XCTAssertThrowsError(try client.request("bogusCommand", [:])) { error in
            guard case .protocolBroken(let text)? = error as? DAPClient.Failure else {
                return XCTFail("应报协议层拒绝，实际：\(error)")
            }
            XCTAssertTrue(text.contains("bogusCommand"), "要说清是哪条命令被拒：\(text)")
            XCTAssertTrue(text.contains("unsupported"), "要带适配器原话：\(text)")
        }
        client.stop()
    }
}
