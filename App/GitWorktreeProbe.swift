import Foundation
import DoyahCore

/// 读 **一次** git 的失败档（`FR-STD-WS-VCS-001`）。
///
/// 分档而不是一个 `nil`：界面上「没选工作区」「这台机器没装 git」「这个目录不是仓库」
/// 「git 超时」是四句不同的话；压成一个布尔就只能说「读不到」，用户不知道下一步该做什么。
enum GitProbeFailure: Error, Equatable {
    /// 没有工作区（面板据此说「先选一个工作区」）。
    case noWorkspace
    /// 起不来进程（多半没装 git / PATH 里没有）。
    case noGit
    /// 目录不是 Git 仓库（没有 `.git`）。
    case notARepository
    /// 超时（仓库太大或磁盘很忙）。
    case timeout
    /// git 起来了但退出码非 0。
    case exitCode(Int32)
}

/// `git status` / `git diff` 的唯一执行点。
///
/// 三条边界（与 `GitStatusProbe` 同源，本文件是它的超集）：
/// - **只读**：只跑 `status` / `diff`，绝不 `add` / `commit` / `push` / `checkout`；
/// - **有超时**：一个巨型仓库不该把界面卡住（拿不到就如实报超时，不假装干净）；
/// - **路径原样**：`-c core.quotePath=false` 让 git 直接给 UTF-8 路径，
///   否则非 ASCII 路径会被写成 `"\346\226\207"` 那种转义形态（界面上没法读）。
enum GitWorktreeProbe {

    enum RunResult {
        case finished(exitCode: Int32, output: String)
        case timeout
        /// 进程起不来。
        case unavailable
    }

    /// 跑一次 git（可带超时）。`arguments` 不含 `git` 自身与 `-C <root>` —— 这里统一加。
    static func run(_ arguments: [String], root: String, timeout: TimeInterval = 3) -> RunResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-c", "core.quotePath=false", "-C", root] + arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return .unavailable
        }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if process.isRunning {
            process.terminate()
            // 掐掉之后还要收尸，否则僵尸进程会留在表里。
            process.waitUntilExit()
            return .timeout
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return .finished(exitCode: process.terminationStatus,
                         output: String(data: data, encoding: .utf8) ?? "")
    }

    /// 读一次仓库状态（分支 / ahead-behind / 改动清单）。
    static func loadStatus(root: String?) -> Result<GitWorktreeStatus, GitProbeFailure> {
        guard let root, !root.isEmpty else { return .failure(.noWorkspace) }
        switch run(["status", "--porcelain=v1", "--branch"], root: root, timeout: 3) {
        case .unavailable:
            return .failure(.noGit)
        case .timeout:
            return .failure(.timeout)
        case .finished(let code, let output):
            // **先看能不能解析**：不是仓库时 git 把话写在 stderr 上、stdout 是空的，
            // 退出码 128 与「别的失败」在界面上一句话分不开 —— 用解析结果分档更诚实。
            guard let status = GitWorktreeStatus.parse(porcelain: output) else {
                return .failure(.notARepository)
            }
            if code != 0 { return .failure(.exitCode(code)) }
            return .success(status)
        }
    }

    /// 读一个文件的逐行差异。
    ///
    /// - `staged = true`：看**暂存区相对 HEAD**（`git diff --cached`）；
    /// - `staged = false`：看**工作区相对暂存区**（`git diff`）；
    /// - 未跟踪的文件：git 没有两侧可比，改走 `--no-index /dev/null <path>`（
    ///   **它的退出码 1 是「有差异」，不是失败** —— 当作失败就等于「新增文件永远看不到内容」）。
    /// - `request`：忽略空白 / 上下文行数（`FR-STD-WS-VCS-002`）。开关由 `GitDiffRequest`
    ///   插进参数（**`--` 之前**），这里不自己拼 —— 两处各拼一次就会「开关亮着、差异没变」。
    static func loadDiff(root: String, entry: GitWorktreeEntry, staged: Bool,
                         request: GitDiffRequest = GitDiffRequest()) -> Result<GitDiffDocument, GitProbeFailure> {
        let base: [String]
        var allowExitOne = false
        if entry.isUntracked {
            base = ["diff", "--no-color", "--no-ext-diff", "--no-index", "--", "/dev/null", entry.path]
            allowExitOne = true
        } else if staged {
            base = ["diff", "--no-color", "--no-ext-diff", "--cached", "--", entry.path]
        } else {
            base = ["diff", "--no-color", "--no-ext-diff", "--", entry.path]
        }
        let arguments = request.applying(to: base)
        switch run(arguments, root: root, timeout: 8) {
        case .unavailable:
            return .failure(.noGit)
        case .timeout:
            return .failure(.timeout)
        case .finished(let code, let output):
            if code != 0 && !(allowExitOne && code == 1) {
                return .failure(.exitCode(code))
            }
            return .success(GitUnifiedDiff.parse(output))
        }
    }
}
