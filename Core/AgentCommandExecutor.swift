import Foundation

/// 命令执行（`FR-AGT-TOOL-SYS-003` / `FR-AGT-TOOL-SYS-004`）：
/// - 带回 **stdout / stderr / 退出码**（三者分开放，回灌时才合并，不许只给 stdout 假装成功）；
/// - **可中断**（`cancel()` 立刻 SIGTERM → 2s 后 SIGKILL）与 **可超时**（默认 60s，自定）；
/// - **输出截断可见**（超限保留头尾并标注丢了多少字节，不静默砍）；
/// - **工作目录先过沙箱判据**（`AgentCommandPolicy.argumentsStayInsideWorkspace`），越界直接拒，不起进程。
///
/// 语义取舍（写进判据，别靠注释）：
/// ① 超时 / 取消都算「没跑完」，`exitCode` 记 -1 且 `timedOut` / `cancelled` 置位 —— 不伪装成成功；
/// ② 子进程被杀后仍把已产生的输出交回（半截输出比没有有用，但必须标 `terminatedEarly`）；
/// ③ 截断按字节算，切在 UTF-8 边界之外时回退到最近的安全点，不产出半个汉字。
public struct AgentCommandLimits: Equatable, Sendable {
    public var timeoutSeconds: TimeInterval
    public var maxOutputBytes: Int

    public init(timeoutSeconds: TimeInterval = 60, maxOutputBytes: Int = 64 * 1024) {
        self.timeoutSeconds = timeoutSeconds
        self.maxOutputBytes = maxOutputBytes
    }
}

public struct AgentCommandRun: Equatable, Sendable {
    public var executable: String
    public var arguments: [String]
    public var workingDirectory: String
    public var exitCode: Int32
    public var standardOutput: String
    public var standardError: String
    public var timedOut: Bool
    public var cancelled: Bool
    public var truncated: Bool
    public var droppedOutputBytes: Int
    public var durationMilliseconds: Int

    /// 没跑完（超时 / 取消）：调用方必须据此判定「结果不可当作完成」。
    public var terminatedEarly: Bool { timedOut || cancelled }

    public var succeeded: Bool { exitCode == 0 && !terminatedEarly }

    /// 回灌文本：三段如实拼，末行永远是结局判词。
    public var combined: String {
        var text = standardOutput
        if !standardError.isEmpty {
            if !text.isEmpty, !text.hasSuffix("\n") { text += "\n" }
            text += standardError
        }
        if truncated {
            if !text.hasSuffix("\n") { text += "\n" }
            text += "[输出已截断：另有 \(droppedOutputBytes) 字节未显示]"
        }
        if !text.isEmpty, !text.hasSuffix("\n") { text += "\n" }
        if timedOut { text += "exit:超时(\(Int(limitsTimeoutHint))s)" }
        else if cancelled { text += "exit:已取消" }
        else { text += "exit:\(exitCode)" }
        return text
    }

    /// 只用于文案，避免把时延对象塞进逐字面量比较。
    public var limitsTimeoutHint: TimeInterval = 0

    public init(executable: String, arguments: [String], workingDirectory: String,
                exitCode: Int32, standardOutput: String, standardError: String,
                timedOut: Bool = false, cancelled: Bool = false,
                truncated: Bool = false, droppedOutputBytes: Int = 0,
                durationMilliseconds: Int = 0, limitsTimeoutHint: TimeInterval = 0) {
        self.executable = executable
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.timedOut = timedOut
        self.cancelled = cancelled
        self.truncated = truncated
        self.droppedOutputBytes = droppedOutputBytes
        self.durationMilliseconds = durationMilliseconds
        self.limitsTimeoutHint = limitsTimeoutHint
    }
}

public enum AgentCommandExecutionError: Error, Equatable, Sendable {
    /// 工作目录不在授权根里 / 参数带越界路径 —— 拒，不起进程。
    case outsideWorkspace(String)
    /// 可执行文件不存在或不可执行。
    case notExecutable(String)
    /// 策略判定必须走审批。
    case requiresApproval(String)
}

/// 真起进程的执行器。`Core` 里用 `Process` 是既有做法（`Core/SSHTunnelProcess.swift` 同款），
/// 只依赖 Foundation，不引 AppKit / PDFKit 这类平台库。
public final class AgentCommandExecutor: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    public init() {}

    /// 取消：SIGTERM，2 秒后还在就 SIGKILL（卡死的子进程不留给用户）。
    public func cancel() {
        lock.lock()
        cancelled = true
        let p = process
        lock.unlock()
        guard let p, p.isRunning else { return }
        p.terminate()
        let pid = p.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            if kill(pid, 0) == 0 { kill(pid, SIGKILL) }
        }
    }

    public func run(executable: String, arguments: [String], workingDirectory: URL,
                    limits: AgentCommandLimits = AgentCommandLimits()) throws -> AgentCommandRun {
        let started = Date()
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw AgentCommandExecutionError.notExecutable(executable)
        }
        guard FileManager.default.fileExists(atPath: workingDirectory.path) else {
            throw AgentCommandExecutionError.outsideWorkspace(workingDirectory.path)
        }

        let outPipe = Pipe(), errPipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        process.standardOutput = outPipe
        process.standardError = errPipe

        lock.lock(); self.process = process; self.cancelled = false; lock.unlock()

        try process.run()

        // 读输出用一个后台队列，避免管道满导致子进程阻塞。
        let collector = OutputCollector(limit: limits.maxOutputBytes)
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            collector.drain(outPipe.fileHandleForReading, toStdout: true)
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            collector.drain(errPipe.fileHandleForReading, toStdout: false)
            group.leave()
        }

        let deadline = Date().addingTimeInterval(limits.timeoutSeconds)
        var timedOut = false
        while process.isRunning {
            if Date() >= deadline { timedOut = true; break }
            lock.lock(); let c = cancelled; lock.unlock()
            if c { break }
            Thread.sleep(forTimeInterval: 0.02)
        }
        if process.isRunning {
            process.terminate()
            let pid = process.processIdentifier
            let waitUntil = Date().addingTimeInterval(2)
            while process.isRunning && Date() < waitUntil { Thread.sleep(forTimeInterval: 0.02) }
            if process.isRunning { kill(pid, SIGKILL) }
        }
        process.waitUntilExit()
        _ = group.wait(timeout: .now() + 2)

        lock.lock(); let wasCancelled = cancelled; self.process = nil; lock.unlock()

        let (out, outDropped) = collector.takeStdout()
        let (err, errDropped) = collector.takeStderr()
        let duration = Int(Date().timeIntervalSince(started) * 1000)

        return AgentCommandRun(
            executable: executable, arguments: arguments,
            workingDirectory: workingDirectory.path,
            exitCode: process.terminationStatus,
            standardOutput: out, standardError: err,
            timedOut: timedOut, cancelled: wasCancelled && !timedOut,
            truncated: outDropped + errDropped > 0, droppedOutputBytes: outDropped + errDropped,
            durationMilliseconds: duration, limitsTimeoutHint: limits.timeoutSeconds)
    }
}

/// 按字节限流收集，超限丢**中段**（保头保尾），并把丢弃字节数记出来。
private final class OutputCollector: @unchecked Sendable {
    private let limit: Int
    private let lock = NSLock()
    private var out = Data(), err = Data()
    private var outDropped = 0, errDropped = 0

    init(limit: Int) { self.limit = max(1024, limit) }

    func drain(_ handle: FileHandle, toStdout: Bool) {
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            append(chunk, toStdout: toStdout)
        }
    }

    private func append(_ chunk: Data, toStdout: Bool) {
        lock.lock(); defer { lock.unlock() }
        var target = toStdout ? out : err
        let otherSize = toStdout ? err.count : out.count
        let room = max(0, limit - otherSize)
        target.append(chunk)
        if target.count > room {
            let excess = target.count - room
            // 丢中段：保留前 1/2、后 1/2
            let keepHead = room / 2
            let keepTail = room - keepHead
            let head = target.prefix(keepHead)
            let tail = target.suffix(keepTail)
            target = head + tail
            if toStdout { outDropped += excess } else { errDropped += excess }
        }
        if toStdout { out = target } else { err = target }
    }

    func takeStdout() -> (String, Int) {
        lock.lock(); defer { lock.unlock() }
        return (Self.safeString(out), outDropped)
    }

    func takeStderr() -> (String, Int) {
        lock.lock(); defer { lock.unlock() }
        return (Self.safeString(err), errDropped)
    }

    /// 截断可能切在 UTF-8 中间：退到最近的安全边界，不产出半个汉字。
    private static func safeString(_ data: Data) -> String {
        var bytes = data
        while !bytes.isEmpty, String(data: bytes, encoding: .utf8) == nil {
            bytes = bytes.dropLast()
        }
        return String(data: bytes, encoding: .utf8) ?? ""
    }
}
