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
    /// 本条命令的原文（洗输出时要把它的回显剔掉）。
    private var pendingCommand = ""
    private var pendingDeadline: DispatchTime?
    /// 诊断落盘只做一次（每条命令）。
    private var dumpedDiagnostics = false

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

        // 用**追加观察者**而不是占用 `onOutput` 槽：终端页签也要看同一份输出，
        // 谁后挂都不该把对方顶掉。
        session.addOutputObserver { [weak self] data in
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
        if ok {
            // **关掉回显**：PTY 默认会把我们写进去的整段脚本原样吐回来，而那段里就含哨兵字面量
            //（`printf '\n__DOYAH_AGENT_DONE_x:%d\n'`）—— 2026-10-31 实测：开回显时第一条命令
            // 立刻被「自己写的那行」判成已完成，退出码解析成 -1，模型以为失败就一直重试。
            // 关掉之后缓冲里只剩程序输出与哨兵结果行；命令本身由 `run` 直接喂给显示面。
            // **必须用 `\r` 提交行，不是 `\n`**：PTY 的行规程按 CR 收行（`ICRNL` 把 CR 折成 NL），
            // 只发 `\n` 时命令被原样打在提示符后面、**不会执行** —— 于是回收永远等不到哨兵，
            // 60 秒超时后模型重试同一条（2026-10-31 实测：`python3 hello.py` 连试三次、每次 60.2s）。
            session.write(text: "stty -echo 2>/dev/null; unset HISTFILE\r")
        }
        lock.lock()
        started = ok
        startFailed = !ok
        lock.unlock()
        StartupLog.write("AgentShell 启动\(ok ? "成功" : "失败")：\(workingDirectory)\(ok ? "" : " · " + (session.lastError ?? ""))")
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
            pendingCommand = command
            buffer = ""
            dumpedDiagnostics = false
            pendingDeadline = DispatchTime.now() + timeout
            lock.unlock()

            // 关回显后，命令本身要自己喂给显示面（否则页签里只剩输出，看不出敲了什么）。
            onOutput?(Data(("❯ " + command + "\n").utf8))
            StartupLog.write("AgentShell 写入命令：\(command.prefix(60))（哨兵 \(echo.sentinel)）")
            // 先掐断可能悬着的续行 / 未闭合引号，再写这一条（理由见 `AgentShellProtocol.reset`）。
            session.write(text: AgentShellProtocol.reset)
            session.write(text: echo.text)

            // 超时看门狗：到点还没等到哨兵 ⇒ 打断（Ctrl-C）+ 如实回「超时」。
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.expire(sentinel: echo.sentinel, timeout: timeout)
            }
        }
    }

    // MARK: - 内部

    private func script(command: String, sentinel: String) -> (text: String, sentinel: String) {
        // 拼法与理由见 `AgentShellProtocol`：括号粘贴包住三行、粘贴外一次回车提交。
        (AgentShellProtocol.script(command: command, sentinel: sentinel), sentinel + ":")
    }

    private func ingest(_ data: Data) {
        guard let chunk = String(data: data, encoding: .utf8) else { return }
        lock.lock()
        if pendingSentinel != nil {
            // 逐块留痕：等不到哨兵时，只有「读到了几块、每块多少字节」能说明是 shell 没执行、
            // 还是执行了但读循环断了（2026-10-31 这一单就是靠它定位的）。
            StartupLog.write("AgentShell 读 \(data.count)B：\(chunk.prefix(50).debugDescription)")
        }
        buffer += chunk
        if buffer.count > bufferLimit {
            buffer = String(buffer.suffix(bufferLimit / 2))
        }
        let sentinel = pendingSentinel
        let echo = pendingEcho
        let commandText = pendingCommand
        let continuation = pending
        var result: AgentCommandResult?
        if let sentinel, pending != nil,
           let hit = AgentShellProtocol.completion(in: buffer, sentinel: String(sentinel.dropLast())) {
            StartupLog.write("AgentShell 哨兵命中 exit=\(hit.exitCode)｜缓冲 \(buffer.count)B")
        } else if pending != nil, buffer.count > 4096, !dumpedDiagnostics {
            // 等不到哨兵时留一份现场（每条命令只落一次），下次不必再靠猜。
            dumpedDiagnostics = true
            try? buffer.write(toFile: "/tmp/doyah-shell-buffer.txt", atomically: true, encoding: .utf8)
        }
        if let sentinel, let continuation,
           let done = AgentShellProtocol.completion(in: buffer, sentinel: String(sentinel.dropLast())) {
            let exitCode = done.exitCode
            var body = done.body
            buffer = ""
            pending = nil
            pendingSentinel = nil
            pendingEcho = ""
            pendingCommand = ""
            pendingDeadline = nil
            lock.unlock()
            // 回显剔除 + 洗成正文（PTY 会把写进去的脚本用 zle 逐字重绘一遍）。
            let clean = AgentShellProtocol.cleanOutput(body, echo: echo, command: commandText)
            StartupLog.write("AgentShell 结果 exit=\(exitCode)｜stdout=" + clean.prefix(120).debugDescription)
            result = AgentCommandResult(exitCode: exitCode,
                                        standardOutput: clean,
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
        // 诊断用：把整段缓冲落盘，超时后才能看清 shell 到底回了什么（含 zle 重绘的转义序列）。
        try? body.write(toFile: "/tmp/doyah-shell-timeout.txt", atomically: true, encoding: .utf8)
        StartupLog.write("AgentShell 超时（\(Int(timeout))s），发 Ctrl-C 打断；缓冲尾部＝"
                         + String(buffer.suffix(300)).debugDescription)
        session.write(text: "\u{03}")   // Ctrl-C：把还挂着的命令打断
        let text = AgentShellProtocol.cleanOutput(body)
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
            exitCode: exitCode, standardOutput: AgentShellProtocol.stripControl(body), standardError: note))
    }

}
