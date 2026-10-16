import Foundation
import DoyahCore

/// `run_command` 的执行器（`FR-AI-20`）—— **真起进程的那一侧**。
///
/// ## 为什么在 `App/` 不在 `Core/`
///
/// `Process` 在 watchOS 上不存在。放进 `Core/` 会把它变成"跨平台件"，那是假的 —— 于是这一侧
/// 只能落在 macOS/iOS 的 App 层。（`Core/` 只保留**协议**与**策略**，这两件都是纯逻辑、可单测。）
///
/// ## 它**不**负责什么（都在别处、且只有一处）
///
/// · 白名单 / 高危判定 / 逐次审批 —— `AgentCommandPolicy`（Core）与 `AgentWorkspaceTools.prepareCommand`；
/// · 什么时候该起进程 —— `AgentStandardDispatcher` 的 `.runCommand` 分支（先出单、再看指纹有没有批准）。
///
/// 本件只做一件事：把**已经批准过的** argv 起起来，把 stdout / stderr / 退出码**如实**带回来，
/// 不吞、不美化、不替子进程编一句"成功"。
struct AgentLocalCommandRunner: AgentCommandRunner {

    func run(executable: String, arguments: [String], workingDirectory: URL) -> AgentCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory

        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        do {
            try process.run()
        } catch {
            // 起不来就如实说"起不来"，**不要**编一个退出码 0 出来。
            return AgentCommandResult(exitCode: -1, standardOutput: "",
                                      standardError: "起进程失败：\(error.localizedDescription)")
        }

        // 顺序要紧：**先把两个管道读到 EOF（= 子进程关掉了写端）再等退出**。反过来的话，
        // 子进程输出一多就会写满管道被阻塞、父进程却在 `waitUntilExit` 上等它结束 ⇒ 经典死锁。
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return AgentCommandResult(
            exitCode: process.terminationStatus,
            standardOutput: String(decoding: outData, as: UTF8.self),
            standardError: String(decoding: errData, as: UTF8.self)
        )
    }
}
