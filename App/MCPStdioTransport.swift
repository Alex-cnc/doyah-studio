import Foundation
import DoyahCore

/// **真起进程的那一侧**：用户自配的 `stdio` MCP server（`FR-AI-21`）。
///
/// ## 为什么在 `App/` 不在 `Core/`
///
/// 与 `AgentLocalCommandRunner` 同一条理由：`Process` 在 watchOS 上没有，放进 `Core/` 会把它
/// 变成假的「跨平台件」。Core 只留协议（`MCPClientTransport`）与判定（`MCPClientBridge`）。
///
/// ## 它**不**负责什么
///
/// · 校验配置 / 决定要不要起 —— `MCPClientConfiguration.plan(for:)`（关掉的一条连计划都没有）；
/// · 握手 / `tools/list` / `tools/call` 的顺序 —— `MCPClientBridge`；
/// · 改名 / 补参数 —— 谁也不做（需求 ①：原样透传）。
///
/// 本件只做：把**已经决定要起**的 argv 起起来，按行收发，然后把「起不来 / 断了 / 超时」如实带回去。
final class MCPStdioTransport: MCPClientTransport {

    private let plan: MCPStdioPlan
    private var process: Process?
    private var writeHandle: FileHandle?
    private var readHandle: FileHandle?

    private let condition = NSCondition()
    private var buffer = Data()
    private var closed = false
    /// 子进程 stderr 的最后一段（连不上 / 崩了时把它带进原因里 —— 用户的"为什么"就在这里）。
    private var stderrText = ""

    init(plan: MCPStdioPlan) {
        self.plan = plan
    }

    func open() -> MCPTransportFailure? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: plan.executable)
        process.arguments = plan.arguments
        // **环境变量原样生效**（验收 ②）：合并已在 `MCPClientConfiguration.plan` 一处做完
        // （继承环境 ⊕ 配置 env，配置胜）；这里只照单下发，不再自己拼一次。
        process.environment = plan.environment

        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        do {
            try process.run()
        } catch {
            // 起不来就如实说哪条命令起不来 —— 不编一个"已连接"的状态出来。
            return .spawnFailed("\(plan.executable): \(error.localizedDescription)")
        }

        self.process = process
        self.writeHandle = input.fileHandleForWriting
        self.readHandle = output.fileHandleForReading

        // 读线程：**按行**攒（JSON-RPC 行分隔传输，一行一条报文）。
        let reader = output.fileHandleForReading
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            while true {
                let data = reader.availableData
                if data.isEmpty { break }
                guard let self else { return }
                self.condition.lock()
                self.buffer.append(data)
                self.condition.broadcast()
                self.condition.unlock()
            }
            guard let self else { return }
            self.condition.lock()
            self.closed = true
            self.condition.broadcast()
            self.condition.unlock()
        }

        // stderr 只留最后 4KB（诊断用，不刷内存）。
        let err = errors.fileHandleForReading
        DispatchQueue.global(qos: .utility).async { [weak self] in
            while true {
                let data = err.availableData
                if data.isEmpty { break }
                guard let self else { return }
                self.condition.lock()
                self.stderrText.append(String(decoding: data, as: UTF8.self))
                if self.stderrText.utf8.count > 4096 {
                    self.stderrText = String(self.stderrText.suffix(2048))
                }
                self.condition.unlock()
            }
        }
        return nil
    }

    func send(_ line: String) -> MCPTransportFailure? {
        guard let writeHandle else { return .writeFailed("noProcess") }
        var payload = Data(line.utf8)
        payload.append(0x0A)
        do {
            try writeHandle.write(contentsOf: payload)
            return nil
        } catch {
            return .writeFailed(error.localizedDescription)
        }
    }

    func receive() -> Result<String, MCPTransportFailure> {
        condition.lock()
        defer { condition.unlock() }
        let deadline = Date().addingTimeInterval(plan.timeoutSeconds)
        while true {
            if let index = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer[buffer.startIndex..<index]
                buffer.removeSubrange(buffer.startIndex...index)
                let line = String(decoding: lineData, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if line.isEmpty { continue }
                return .success(line)
            }
            if closed {
                let tail = stderrText.trimmingCharacters(in: .whitespacesAndNewlines)
                return .failure(.exited(tail))
            }
            if !condition.wait(until: deadline) {
                return .failure(.timeout(seconds: plan.timeoutSeconds))
            }
        }
    }

    func close() {
        try? writeHandle?.close()
        process?.terminate()
        process = nil
        writeHandle = nil
        readHandle = nil
        condition.lock()
        closed = true
        condition.broadcast()
        condition.unlock()
    }
}
