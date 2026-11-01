import Foundation

/// DAP 会话传输层（`FR-STD-WS-TOOL-003` 第二片）：真起适配器、按 `seq` 对账、超时如实报。
///
/// 第一片（`DAPCore.swift`）只管口径；这一片负责**把字节在进程里来回搬**，仍不做任何 UI。
/// 三条纪律：
/// 1. **读不阻塞写** —— 用 `readabilityHandler` 收字节，按 `Content-Length` 切片；
/// 2. **请求必有时限** —— 适配器不说 DAP 时，宁可 5 秒后报「超时」也不挂着不返回；
/// 3. **失败要能说清是哪一步** —— 缺适配器 / 启动即退（带退出码）/ 超时 / 对端关闭，
///    四种分开报，别统一成一句 "debug failed"。
public final class DAPClient {

    /// 失败原因（与 `DebugUnavailableReason` 一一对应，UI 直接拿 `sentence` 显示）。
    public enum Failure: Error, Equatable {
        case adapterNotFound(path: String)
        case adapterExited(code: Int32)
        case timeout(command: String, seconds: Int)
        case closed(command: String)
        case protocolBroken(String)
    }

    /// 事件回调（`initialized` / `stopped` / `terminated` / `output` …）。
    public typealias EventHandler = (String, [String: Any]) -> Void

    private let adapterPath: String
    private let adapterArguments: [String]
    private let timeoutSeconds: Int

    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var buffer = Data()

    private let lock = NSLock()
    private var nextSeq = 1
    private var pending: [Int: (Result<[String: Any], Failure>) -> Void] = [:]
    private var eventHandler: EventHandler?
    private var adapterOutputTail: String = ""

    public init(adapterPath: String, adapterArguments: [String] = [], timeoutSeconds: Int = 5) {
        self.adapterPath = adapterPath
        self.adapterArguments = adapterArguments
        self.timeoutSeconds = timeoutSeconds
    }

    public var isRunning: Bool { process?.isRunning ?? false }

    public func onEvent(_ handler: @escaping EventHandler) {
        lock.lock(); eventHandler = handler; lock.unlock()
    }

    // MARK: - 起停

    public func start() throws {
        guard FileManager.default.isExecutableFile(atPath: adapterPath) else {
            throw Failure.adapterNotFound(path: adapterPath)
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: adapterPath)
        task.arguments = adapterArguments
        let input = Pipe(), output = Pipe(), errors = Pipe()
        task.standardInput = input
        task.standardOutput = output
        task.standardError = errors

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard let self else { return }
            if chunk.isEmpty { return }
            self.consume(chunk)
        }
        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard let self, !chunk.isEmpty else { return }
            self.lock.lock()
            self.adapterOutputTail = String(decoding: chunk, as: UTF8.self).suffix(400).description
            self.lock.unlock()
        }
        task.terminationHandler = { [weak self] proc in
            guard let self else { return }
            self.lock.lock()
            let waiting = self.pending
            self.pending.removeAll()
            let tail = self.adapterOutputTail
            self.lock.unlock()
            let code = proc.terminationStatus
            for (_, completion) in waiting {
                // 适配器带着请求一起死了：如果 stderr 有明显线索，附在协议错误里，否则报退出码
                if tail.isEmpty {
                    completion(.failure(.adapterExited(code: code)))
                } else {
                    completion(.failure(.protocolBroken("适配器退出（码 \(code)）：\(tail)")))
                }
            }
        }

        do {
            try task.run()
        } catch {
            throw Failure.adapterNotFound(path: adapterPath)
        }
        process = task
        stdinPipe = input
        stdoutPipe = output
    }

    public func stop() {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminate()
        process = nil
        lock.lock()
        let waiting = pending
        pending.removeAll()
        lock.unlock()
        for (_, completion) in waiting { completion(.failure(.closed(command: "disconnect"))) }
    }

    // MARK: - 请求 / 响应

    /// 发一条请求并等响应；超时按 `timeoutSeconds`。
    public func request(_ command: String, _ arguments: [String: Any] = [:]) throws -> [String: Any] {
        guard let stdin = stdinPipe?.fileHandleForWriting else {
            throw Failure.adapterExited(code: -1)
        }
        let seq: Int = {
            lock.lock(); defer { lock.unlock() }
            let value = nextSeq; nextSeq += 1; return value
        }()
        var message: [String: Any] = ["seq": seq, "type": "request", "command": command]
        if !arguments.isEmpty { message["arguments"] = arguments }
        let body = try JSONSerialization.data(withJSONObject: message)

        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<[String: Any], Failure> = .failure(.closed(command: command))
        lock.lock()
        pending[seq] = { value in result = value; semaphore.signal() }
        lock.unlock()

        stdin.write(DAPFrame.encode(body: body))

        if semaphore.wait(timeout: .now() + .seconds(timeoutSeconds)) == .timedOut {
            lock.lock(); pending.removeValue(forKey: seq); lock.unlock()
            throw Failure.timeout(command: command, seconds: timeoutSeconds)
        }
        switch result {
        case .success(let payload):
            if let success = payload["success"] as? Bool, success == false {
                let text = payload["message"] as? String ?? "适配器未说明原因"
                throw Failure.protocolBroken("\(command) 被拒：\(text)")
            }
            return payload
        case .failure(let failure):
            throw failure
        }
    }

    // MARK: - 收字节

    private func consume(_ chunk: Data) {
        lock.lock()
        buffer.append(chunk)
        let bodies = DAPFrame.decode(&buffer)
        lock.unlock()

        for body in bodies {
            guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
                continue  // 单条坏包不该把整场调试判死
            }
            switch object["type"] as? String {
            case "response":
                guard let requestSeq = object["request_seq"] as? Int else { continue }
                lock.lock()
                let completion = pending.removeValue(forKey: requestSeq)
                lock.unlock()
                completion?(.success(object))
            case "event":
                let name = object["event"] as? String ?? ""
                lock.lock(); let handler = eventHandler; lock.unlock()
                handler?(name, object["body"] as? [String: Any] ?? [:])
            default:
                continue
            }
        }
    }
}

// MARK: - 会话门面

/// 一次最小调试会话：`initialize` → `launch` → `setBreakpoints` → （等 `stopped`）。
///
/// 只包到「停下来了、能读变量」为止 —— 单步与断点面板留给 UI 片。
public final class DAPSession {

    public struct StoppedLocation: Equatable {
        public let threadId: Int
        public let file: String
        public let line: Int
        public let reason: String
    }

    public enum Outcome: Equatable {
        case stopped(StoppedLocation)
        case terminated(reason: String)
        case timedOut(seconds: Int)
    }

    private let client: DAPClient
    private let lock = NSLock()
    private var lastEvent: (name: String, body: [String: Any])?

    public init(client: DAPClient) {
        self.client = client
        client.onEvent { [weak self] name, body in
            guard let self else { return }
            self.lock.lock(); self.lastEvent = (name, body); self.lock.unlock()
        }
    }

    /// 跑到「停止」或「结束」为止；一次都不停且超时 ⇒ `.timedOut`（如实报，不假装在跑）。
    public func runUntilStop(program: String, breakpoints: [String: [Int]], waitSeconds: Int = 20) throws -> Outcome {
        try client.start()
        _ = try client.request("initialize", ["adapterID": "lldb", "linesStartAt1": true, "pathFormat": "path"])
        _ = try client.request("launch", ["program": program, "stopOnEntry": false, "console": "internalConsole"])
        for (path, lines) in breakpoints {
            _ = try client.request("setBreakpoints", [
                "source": ["path": path],
                "breakpoints": lines.map { ["line": $0] },
            ])
        }
        _ = try client.request("configurationDone")

        return try waitForStop(waitSeconds: waitSeconds)
    }

    /// 读停住那一帧的变量（名 = 值，值取 `value`/`description`）。
    public func variables(threadId: Int) throws -> [String: String] {
        let stack = try client.request("stackTrace", ["threadId": threadId])
        guard let frames = bodyOf(stack)["stackFrames"] as? [[String: Any]],
              let frameId = frames.first?["id"] as? Int else { return [:] }
        let scopes = try client.request("scopes", ["frameId": frameId])
        guard let scopeList = bodyOf(scopes)["scopes"] as? [[String: Any]] else { return [:] }
        var out: [String: String] = [:]
        for scope in scopeList.prefix(2) {           // 只看前两个作用域（局部 + 全局），够判「能不能读」
            guard let reference = scope["variablesReference"] as? Int, reference > 0 else { continue }
            let vars = try client.request("variables", ["variablesReference": reference])
            for item in bodyOf(vars)["variables"] as? [[String: Any]] ?? [] {
                guard let name = item["name"] as? String else { continue }
                out[name] = (item["value"] as? String) ?? (item["description"] as? String) ?? ""
            }
        }
        return out
    }

    /// 单步 / 继续：DAP 里 `next`（步过）/ `stepIn`（步入）/ `stepOut`（步出）/ `continue`（继续）。
    ///
    /// 四条都是「发一条请求 + 等 `stopped` 事件」—— 事件可能先于响应到达，所以**先等事件**：
    /// 拿响应当作「发出去了」，拿事件当作「停下来了」。二者混为一谈会出现「响应一到就以为停了」的假停。
    public enum Step: String {
        case over = "next"
        case into = "stepIn"
        case out = "stepOut"
        case resume = "continue"
    }

    public func step(_ kind: Step, threadId: Int, waitSeconds: Int = 15) throws -> Outcome {
        _ = try client.request(kind.rawValue, ["threadId": threadId])
        return try waitForStop(waitSeconds: waitSeconds)
    }

    /// 等下一次 `stopped` / `terminated`；等不到就如实报超时。
    public func waitForStop(waitSeconds: Int = 15) throws -> Outcome {
        let deadline = Date().addingTimeInterval(TimeInterval(waitSeconds))
        while Date() < deadline {
            lock.lock(); let event = lastEvent; lastEvent = nil; lock.unlock()
            guard let (name, body) = event else {
                Thread.sleep(forTimeInterval: 0.05)
                continue
            }
            switch name {
            case "stopped":
                let threadId = body["threadId"] as? Int ?? 0
                let reason = body["reason"] as? String ?? "unknown"
                let frame = try topFrame(threadId: threadId)
                return .stopped(StoppedLocation(threadId: threadId, file: frame.file, line: frame.line, reason: reason))
            case "terminated", "exited":
                return .terminated(reason: body["reason"] as? String ?? name)
            default:
                continue
            }
        }
        return .timedOut(seconds: waitSeconds)
    }

    public func disconnect() {
        _ = try? client.request("disconnect", ["terminateDebuggee": true])
        client.stop()
    }

    /// 取响应里的 `body`（DAP 的 body 是任意 JSON 对象，必须先落到 `[String: Any]` 才能下标）。
    private func bodyOf(_ payload: [String: Any]) -> [String: Any] {
        (payload["body"] as? [String: Any]) ?? [:]
    }

    private func topFrame(threadId: Int) throws -> (file: String, line: Int) {
        let stack = try client.request("stackTrace", ["threadId": threadId])
        guard let frames = bodyOf(stack)["stackFrames"] as? [[String: Any]],
              let first = frames.first,
              let line = first["line"] as? Int else { return ("", 0) }
        let file = (first["source"] as? [String: Any])?["path"] as? String ?? ""
        return (file, line)
    }
}
