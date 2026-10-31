import Foundation
import DoyahCore

/// **Agent 自己的那条 shell**（`FR-AI-20` 的执行面，2026-10-31 改）。
///
/// ## 为什么要有它
///
/// 主人原话：「你执行工具不是在 Terminal 中执行吗，包括自己编的 python 脚本」。
/// 改之前 `run_command` 走 `AgentCommandExecutor`：`Process` + argv **直接起进程**，
/// 于是有三件事同时不成立 ——
///   1. **看不见**：命令不在终端面板里，人只能在对话里看结果；
///   2. **不延续**：每条命令都是新进程，上一条的 `cd` / `export` / 临时变量全丢；
///   3. **脚本受限**：多行脚本只能自己拼 `sh -c`，交互式命令（要回话的那种）根本跑不了。
///
/// 现在命令进**一条真实的 PTY shell**（`TerminalSession`，`forkpty`）：
/// 在 shell 里跑 ⇒ 状态延续、heredoc / 管道 / 变量都成立；输出按**哨兵行**切段回收，
/// 同时把同一份字节喂给终端面板里的「Agent」页签（看见的就是它真的在敲什么）。
///
/// ## 与终端页签那条 shell 的关系
///
/// **两条，不共用**：页签那条是人手敲的（光标、输入、历史都属于人）；这一条是机器敲的。
/// 合成一条会让「Agent 正在敲」和「我正在敲」抢同一个光标 —— 那是另一件事，别顺手做。
///
/// ## 回收协议（这里只有一处）
///
/// 写进去的是一段脚本：
/// ```
/// <用户那条命令>
/// __doyah_ec=$?
/// printf '\n<SENTINEL>:%d\n' "$__doyah_ec"
/// ```
/// 读到 `<SENTINEL>:<退出码>` 就算这一条跑完。**回显要剔掉**（PTY 会把我们写进去的
/// 那一整段原样回显一遍），否则结果里会夹着命令本身。
final class AgentShellSession: @unchecked Sendable {

    /// 启动目录（工作区根）。命令的 `cwd` 由**起 shell 那一刻**决定，之后随 `cd` 走。
    let workingDirectory: String
    /// 输出镜像（主线程回调）：终端面板「Agent」页签吃这一份。
    var onOutput: ((Data) -> Void)?

    private let lock = NSLock()
    /// 这条会话本身。给终端面板的「Agent」页签挂显示用
    /// （页签只显示、不启动、不终止 —— 谁建谁管）。
    let session = TerminalSession()
    private var started = false
    private var startFailed = false
    /// 回收缓冲（只留最近一段，防长跑命令把内存吃光）。
    private var buffer = ""
    private let bufferLimit = 512 * 1024
    /// 当前这一条的等待者（同一时刻只有一条在跑，见 `run`）。
    private var pending: CheckedContinuation<AgentCommandResult, Never>?
    private var pendingSentinel: String?
    private var pendingEcho = ""
    private var pendingDeadline: DispatchTime?

    init(workingDirectory: String) {
        self.workingDirectory = workingDirectory
    }

    /// 起一次（幂等）。起不来就返回 false，调用方**如实**回「shell 起不来」。
    @discardableResult
    func startIfNeeded() -> Bool {
        lock.lock()
        if started { lock.unlock(); return true }
        if startFailed { lock.unlock(); return false }
        lock.unlock()

        session.onOutput = { [weak self] data in
            guard let self else { return }
            self.ingest(data)
            self.onOutput?(data)
        }
        session.onExit = { [weak self] code in
            self?.finish(exitCode: code, note: "shell 已退出（\(code)）")
        }
        let ok = session.start(columns: 120, rows: 32,
                               shell: nil, loginShell: true,
                               workingDirectory: workingDirectory)
        lock.lock()
        started = ok
        startFailed = !ok
        lock.unlock()
        return ok
    }

    /// 在这条 shell 里跑一条命令，等哨兵行出来。
    ///
    /// **同一时刻只受理一条**：第二条进来时上一条还没回收 ⇒ 如实回「上一条还在跑」，
    /// 不排队（排队会让两条命令的输出在同一段缓冲里串起来，回收就分不清谁是谁）。
    func run(command: String, timeout: TimeInterval) async -> AgentCommandResult {
        guard startIfNeeded() else {
            return AgentCommandResult(exitCode: -1, standardOutput: "",
                                      standardError: "Agent shell 起不来：\(session.lastError ?? "未知原因")")
        }
        let sentinel = "__DOYAH_AGENT_DONE_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12)
        let echo = script(command: command, sentinel: String(sentinel))

        return await withCheckedContinuation { (continuation: CheckedContinuation<AgentCommandResult, Never>) in
            lock.lock()
            if pending != nil {
                lock.unlock()
                continuation.resume(returning: AgentCommandResult(
                    exitCode: -1, standardOutput: "",
                    standardError: "上一条命令还在跑（同一时刻只跑一条）"))
                return
            }
            pending = continuation
            pendingSentinel = echo.sentinel
            pendingEcho = echo.text
            buffer = ""
            pendingDeadline = DispatchTime.now() + timeout
            lock.unlock()

            session.write(text: echo.text)

            // 超时看门狗：到点还没等到哨兵 ⇒ 打断（Ctrl-C）+ 如实回「超时」。
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.expire(sentinel: echo.sentinel, timeout: timeout)
            }
        }
    }

    // MARK: - 内部

    private func script(command: String, sentinel: String) -> (text: String, sentinel: String) {
        // 命令原样放进去（人写的是什么就是什么）；退出码由紧跟着的一行取。
        // 结尾那个空行保证：命令本身不以换行结尾时，哨兵行也不会粘在最后一行上。
        let text = command + "\n__doyah_ec=$?\nprintf '\\n\(sentinel):%d\\n' \"$__doyah_ec\"\n"
        return (text, sentinel + ":")
    }

    private func ingest(_ data: Data) {
        guard let chunk = String(data: data, encoding: .utf8) else { return }
        lock.lock()
        buffer += chunk
        if buffer.count > bufferLimit {
            buffer = String(buffer.suffix(bufferLimit / 2))
        }
        let sentinel = pendingSentinel
        let echo = pendingEcho
        let continuation = pending
        var result: AgentCommandResult?
        if let sentinel, let continuation, let range = buffer.range(of: sentinel) {
            let after = buffer[range.upperBound...]
            let codeLine = after.prefix { $0 != "\n" }
            let exitCode = Int32(codeLine.trimmingCharacters(in: .whitespaces)) ?? -1
            var body = String(buffer[..<range.lowerBound])
            buffer = ""
            pending = nil
            pendingSentinel = nil
            pendingEcho = ""
            pendingDeadline = nil
            lock.unlock()
            // 回显剔除：PTY 会把写进去的那一整段原样吐回来一遍。
            body = Self.stripEcho(body, echo: echo)
            result = AgentCommandResult(exitCode: exitCode,
                                        standardOutput: Self.stripControl(body),
                                        standardError: "")
            continuation.resume(returning: result!)
            return
        }
        lock.unlock()
    }

    private func expire(sentinel: String, timeout: TimeInterval) {
        lock.lock()
        guard pendingSentinel == sentinel, let continuation = pending else { lock.unlock(); return }
        var body = buffer
        buffer = ""
        pending = nil
        pendingSentinel = nil
        pendingEcho = ""
        pendingDeadline = nil
        lock.unlock()
        session.write(text: "\u{03}")   // Ctrl-C：把还挂着的命令打断
        let text = Self.stripControl(Self.stripEcho(body, echo: ""))
        continuation.resume(returning: AgentCommandResult(
            exitCode: 124, standardOutput: text,
            standardError: "\n[命令超时 \(Int(timeout))s 被终止]"))
    }

    private func finish(exitCode: Int32, note: String) {
        lock.lock()
        let continuation = pending
        pending = nil
        pendingSentinel = nil
        pendingEcho = ""
        let body = buffer
        buffer = ""
        lock.unlock()
        continuation?.resume(returning: AgentCommandResult(
            exitCode: exitCode, standardOutput: Self.stripControl(body), standardError: note))
    }

    /// 把回显那一段剔掉：优先按整段精确匹配；匹配不上（换行被 PTY 重排过）就按行剔。
    static func stripEcho(_ body: String, echo: String) -> String {
        if !echo.isEmpty, let range = body.range(of: echo) {
            return String(body[range.upperBound...])
        }
        let echoed = Set(echo.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) })
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false)
        var dropped = 0
        var out: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if dropped < 3, echoed.contains(trimmed) || trimmed.hasPrefix("__doyah_ec=$?")
                || trimmed.hasPrefix("printf '") {
                dropped += 1
                continue
            }
            out.append(String(line))
        }
        return out.joined(separator: "\n")
    }

    /// 去掉 ANSI 转义与控制字符（提示符配色、`\r`），留下人能读的正文。
    static func stripControl(_ text: String) -> String {
        var out = ""
        var iterator = Array(text)
        var index = 0
        while index < iterator.count {
            let ch = iterator[index]
            if ch == "\u{1B}" {
                index += 1
                if index < iterator.count, iterator[index] == "[" {
                    index += 1
                    while index < iterator.count, !(iterator[index].isLetter || iterator[index] == "m") {
                        index += 1
                    }
                }
                index += 1
                continue
            }
            if ch == "\r" { index += 1; continue }
            out.append(ch)
            index += 1
        }
        return out.trimmingCharacters(in: CharacterSet(charactersIn: "\n"))
    }
}
