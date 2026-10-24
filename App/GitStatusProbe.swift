import Foundation
import DoyahCore

/// 从工作区根目录读一次仓库状态（`FR-AGT-KNOW-CTX-001` 的取数半）。
///
/// 解析全在 `AgentGitFacts.parse(porcelain:)`（Core，纯函数、可单测）；这里只负责**跑一次 git**。
/// 三条边界：
/// - 机器上没装 git / 不是仓库 / 超时 ⇒ 返回 `nil`，**不编**一个空分支；
/// - 只读命令（`status --porcelain`），不碰工作树；
/// - 超时 1.5 秒：一个巨型仓库不该把对话卡住（拿不到就当没有，界面照常）。
enum GitStatusProbe {

    static func facts(root: String?) -> AgentGitFacts? {
        guard let root, !root.isEmpty else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", root, "status", "--porcelain=v1", "--branch"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        // 1.5 秒上限（读不完就掐掉，当作「没有仓库信息」）。
        let deadline = Date().addingTimeInterval(1.5)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if process.isRunning {
            process.terminate()
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0,
              let text = String(data: data, encoding: .utf8) else { return nil }
        return AgentGitFacts.parse(porcelain: text)
    }
}
