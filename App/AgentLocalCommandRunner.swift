import Foundation
import DoyahCore

/// `run_command` 的执行器（`FR-AI-20`）—— **真起进程的那一侧**。
///
/// ## 为什么在 `App/` 不在 `Core/`
///
/// 历史原因：当年 `Core` 还想跨到 watchOS（`Process` 不存在）。2026-10-26 已确认 `Package.swift`
/// 只声明 `.macOS(.v14)`，进程执行本体（超时 / 取消 / 截断）落在 `Core/AgentCommandExecutor.swift`；
/// 本件退化成一层薄适配（把 `AgentCommandRun` 折成 `AgentCommandResult`，并把「超时 / 取消」写进 stderr
/// 让回灌文本别假装成功）。
///
/// ## 它**不**负责什么（都在别处、且只有一处）
///
/// · 白名单 / 高危判定 / 逐次审批 —— `AgentCommandPolicy`（Core）与 `AgentWorkspaceTools.prepareCommand`；
/// · 什么时候该起进程 —— `AgentStandardDispatcher` 的 `.runCommand` 分支（先出单、再看指纹有没有批准）。
///
/// 本件只做一件事：把**已经批准过的** argv 起起来，把 stdout / stderr / 退出码**如实**带回来，
/// 不吞、不美化、不替子进程编一句"成功"。
struct AgentLocalCommandRunner: AgentCommandRunner {

    /// 2026-10-26：改走 `Core/AgentCommandExecutor`（`FR-AGT-TOOL-SYS-003/004`）——
    /// 带 **60s 超时可配 / 可取消 / 输出截断可见 / 越界工作目录不起进程**；
    /// 老实现「读管道到 EOF 再等退出」在子进程狂输出 + 挂住时会永远等下去，没有上限。
    var limits = AgentCommandLimits()

    /// 有它就在**真 shell**（PTY）里跑：状态延续、脚本原样、终端面板里看得见。
    /// 没注入（单测 / 未开工作区）⇒ 退回独立进程那条老路，行为与改动前一致。
    var shell: AgentShellSession?

    /// argv → 一行 shell 命令。**每个参数单独加引号**：参数里的空格 / 引号 / `$` 不许多义。
    static func shellLine(executable: String, arguments: [String]) -> String {
        ([executable] + arguments).map(shellQuote).joined(separator: " ")
    }

    static func shellQuote(_ raw: String) -> String {
        let safe = raw.allSatisfy { $0.isLetter || $0.isNumber || "-_./=:@%+,".contains($0) }
        if !raw.isEmpty, safe { return raw }
        return "'" + raw.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    func run(executable: String, arguments: [String], workingDirectory: URL) async -> AgentCommandResult {
        if let shell {
            let line = Self.shellLine(executable: executable, arguments: arguments)
            return await shell.run(command: line, timeout: limits.timeoutSeconds)
        }
        let executor = AgentCommandExecutor()
        do {
            let run = try executor.run(executable: executable, arguments: arguments,
                                       workingDirectory: workingDirectory, limits: limits)
            return AgentCommandResult(
                exitCode: run.exitCode,
                standardOutput: run.standardOutput,
                standardError: run.standardError + (run.terminatedEarly
                    ? (run.timedOut ? "\n[命令超时 \(Int(run.limitsTimeoutHint))s 被终止]" : "\n[命令被取消]")
                    : ""))
        } catch {
            // 起不来就如实说"起不来"，**不要**编一个退出码 0 出来。
            return AgentCommandResult(exitCode: -1, standardOutput: "",
                                      standardError: "起进程失败：\(error)")
        }
    }
}
