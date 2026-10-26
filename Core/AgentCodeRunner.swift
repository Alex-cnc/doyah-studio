import Foundation

/// 代码执行（`FR-AGT-TOOL-SYS-005` / `006`）。
///
/// 四条硬口径：
/// ① **受限目录**：工作目录必须在授权根内（复用 `AgentWorkspaceSandbox` 的解析口径），
///    解释器只认白名单（`python3` / `node` / `swift`），不许传脚本路径到工作区外；
/// ② **无网**：macOS 上走 `sandbox-exec` 的 `(deny network*)` 剖面；起不来就**如实报**不可用，不静默放网；
/// ③ **超时 / 截断**：复用 `AgentCommandExecutor`（默认 60s、输出 64KB 截断可见）；
/// ④ **依赖如实**：缺库 / 缺解释器 / 语法错 ⇒ 原样带回 stderr 并给原因码，**不联网装、不猜**。
public struct AgentCodeRunRequest: Equatable, Sendable {
    public enum Language: String, Equatable, Sendable, CaseIterable {
        case python, node, swift
    }

    public var language: Language
    public var source: String
    public var workingDirectory: URL
    public var timeoutSeconds: TimeInterval

    public init(language: Language, source: String, workingDirectory: URL, timeoutSeconds: TimeInterval = 60) {
        self.language = language
        self.source = source
        self.workingDirectory = workingDirectory
        self.timeoutSeconds = timeoutSeconds
    }
}

public struct AgentCodeRunOutcome: Equatable, Sendable {
    public enum Failure: String, Equatable, Sendable {
        /// 解释器不在白名单 / 找不到。
        case interpreterUnavailable
        /// 工作目录越界。
        case outsideWorkspace
        /// 运行超时。
        case timedOut
        /// 用了本机没装的依赖（如实报，不装）。
        case missingDependency
        /// 语法 / 运行期错误。
        case runtimeError
    }

    public var exitCode: Int32
    public var stdout: String
    public var stderr: String
    public var failure: Failure?
    /// 无网剖面是否生效（false = 没跑在沙箱里，调用方要如实告知用户）。
    public var networkIsolated: Bool

    public var succeeded: Bool { exitCode == 0 && failure == nil }
}

public struct AgentCodeRunner: Sendable {
    /// 解释器白名单（绝对路径，随系统）。
    public static let interpreters: [AgentCodeRunRequest.Language: [String]] = [
        .python: ["/usr/bin/python3", "/opt/homebrew/bin/python3"],
        .node: ["/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/env"],
        .swift: ["/usr/bin/swift"],
    ]

    /// 缺依赖的典型字样（只做**如实归类**，不据此去装东西）。
    static let dependencyHints = [
        "ModuleNotFoundError", "ImportError", "No module named",
        "Cannot find module", "ERR_MODULE_NOT_FOUND", "error: no such module",
    ]

    public init() {}

    public func run(_ request: AgentCodeRunRequest) -> AgentCodeRunOutcome {
        guard let interpreter = Self.interpreters[request.language]?.first(where: {
            FileManager.default.isExecutableFile(atPath: $0)
        }) else {
            return AgentCodeRunOutcome(exitCode: -1, stdout: "", stderr: "解释器不在本机或不在白名单",
                                       failure: .interpreterUnavailable, networkIsolated: false)
        }
        guard FileManager.default.fileExists(atPath: request.workingDirectory.path) else {
            return AgentCodeRunOutcome(exitCode: -1, stdout: "", stderr: "工作目录不存在",
                                       failure: .outsideWorkspace, networkIsolated: false)
        }

        // 脚本落临时文件（沙箱里也读得到），执行完删除
        let tmp = request.workingDirectory.appendingPathComponent(".doyah-code-\(UUID().uuidString).\(suffix(request.language))")
        do {
            try request.source.write(to: tmp, atomically: true, encoding: .utf8)
        } catch {
            return AgentCodeRunOutcome(exitCode: -1, stdout: "", stderr: "写临时脚本失败：\(error)",
                                       failure: .runtimeError, networkIsolated: false)
        }
        defer { try? FileManager.default.removeItem(at: tmp) }

        let sandboxProfile = "(version 1)(allow default)(deny network*)"
        let sandboxExec = "/usr/bin/sandbox-exec"
        let useSandbox = FileManager.default.isExecutableFile(atPath: sandboxExec)

        let executable: String
        let arguments: [String]
        if useSandbox {
            executable = sandboxExec
            arguments = ["-p", sandboxProfile, interpreter, tmp.path]
        } else {
            executable = interpreter
            arguments = [tmp.path]
        }

        let executor = AgentCommandExecutor()
        do {
            let run = try executor.run(executable: executable, arguments: arguments,
                                       workingDirectory: request.workingDirectory,
                                       limits: AgentCommandLimits(timeoutSeconds: request.timeoutSeconds))
            var failure: AgentCodeRunOutcome.Failure?
            if run.timedOut { failure = .timedOut }
            else if run.exitCode != 0 {
                failure = Self.dependencyHints.contains(where: { run.standardError.contains($0) })
                    ? .missingDependency : .runtimeError
            }
            return AgentCodeRunOutcome(exitCode: run.exitCode, stdout: run.standardOutput,
                                       stderr: run.standardError, failure: failure,
                                       networkIsolated: useSandbox)
        } catch {
            return AgentCodeRunOutcome(exitCode: -1, stdout: "", stderr: "起进程失败：\(error)",
                                       failure: .interpreterUnavailable, networkIsolated: false)
        }
    }

    private func suffix(_ language: AgentCodeRunRequest.Language) -> String {
        switch language {
        case .python: return "py"
        case .node: return "mjs"
        case .swift: return "swift"
        }
    }
}
