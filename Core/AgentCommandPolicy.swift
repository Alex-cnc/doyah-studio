import Foundation

/// `run_command` 的命令白名单（`FR-AI-20` ④：非白名单命令**被拒**）。
///
/// 三条口径：
/// 1. **自己拆词，不经过 shell** —— 因此 `;` `|` `&` `` ` `` `$` `>` `<` 这些控制字符一律视为非法；
///    「白名单命令 + 参数里塞一个 `;`」是最典型的绕过，必须在**词法层**挡掉，而不是指望下游。
/// 2. **可执行名必须是裸名字**（不许含 `/`）—— 否则 `/bin/sh`、`./evil` 这类直接越过白名单。
/// 3. **看起来像路径的参数**（绝对路径 / 含 `..`）必须落在工作区内 —— 命令的工作目录由调用方钉在
///    工作区根，参数再指向外面就等于把沙箱绕开了（复用 `AgentWorkspaceSandbox` 判定）。
public struct AgentCommandPolicy: Equatable, Sendable {

    /// 允许的可执行名（裸名，不含路径）。
    public var allowedExecutables: Set<String>
    /// 参数个数上限（挡住「一条命令带一千个参数」这种形态）。
    public var maxArgumentCount: Int

    public init(allowedExecutables: Set<String>, maxArgumentCount: Int = 32) {
        self.allowedExecutables = allowedExecutables
        self.maxArgumentCount = maxArgumentCount
    }

    public enum Verdict: Equatable, Sendable {
        case allowed(executable: String, arguments: [String])
        case refused(AgentToolRefusal, detail: String)
    }

    /// 标准白名单：只读查看 + 版本控制查询 + 本机构建工具。
    /// **刻意保守**：`rm` / `mv` / `chmod` / `sed -i` 这类能改盘的都不在表里（要改盘走 `write_file`）。
    public static let standard = AgentCommandPolicy(allowedExecutables: [
        "ls", "cat", "head", "tail", "wc", "grep", "find", "pwd", "file", "sort", "uniq",
        "git", "swift", "python3", "node", "make",
    ])

    /// 控制字符：出现即拒（不经过 shell，就没有「引号包住就安全」这一说）。
    /// **引号与反斜杠不在其中**（概设 §18.1）：不经 shell 时它们只是字面量，
    /// 把它们当控制字符会误伤 `grep -c "FR-AGT" x.md` 这类合法只读命令（实测被拒 29 次）。
    static let forbidden = Set(";|&`$><\n\r".map { $0 })

    /// 分词：按空白拆词，**引号内的空白不拆**，引号本身剥掉。
    ///
    /// 不经 shell 就没有 shell 的分词器，这几件事必须自己做：
    /// ① 引号分组（`"a b"` 是一个参数）；② 剥掉引号（否则 `grep "x"` 会去搜带引号的字面量）；
    /// ③ **未闭合引号返回 nil** —— 必须由调用方拒掉，不许静默截断成半个参数。
    /// 反斜杠**不做转义**（概设：只是字面量），要传特殊字符请用引号。
    static func tokenize(_ command: String) -> [String]? {
        var words: [String] = []
        var current = ""
        var quote: Character?
        for character in command {
            if let opener = quote {
                if character == opener { quote = nil } else { current.append(character) }
                continue
            }
            if character == "\"" || character == "'" {
                quote = character
                continue
            }
            if character == " " || character == "\t" {
                if !current.isEmpty { words.append(current); current = "" }
                continue
            }
            current.append(character)
        }
        guard quote == nil else { return nil }
        if !current.isEmpty { words.append(current) }
        return words
    }

    public func assess(_ command: String) -> Verdict {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .refused(.emptyQuery, detail: command) }

        for character in trimmed where Self.forbidden.contains(character) {
            return .refused(.commandNotAllowed, detail: "control-character:\(character)")
        }

        guard let words = Self.tokenize(trimmed) else {
            return .refused(.commandNotAllowed, detail: "unterminated-quote")
        }
        guard let executable = words.first else { return .refused(.emptyQuery, detail: command) }
        guard !executable.contains("/") else {
            return .refused(.commandNotAllowed, detail: "executable-is-a-path:\(executable)")
        }
        guard allowedExecutables.contains(executable) else {
            return .refused(.commandNotAllowed, detail: executable)
        }

        let arguments = Array(words.dropFirst())
        guard arguments.count <= maxArgumentCount else {
            return .refused(.commandNotAllowed, detail: "too-many-arguments:\(arguments.count)")
        }
        return .allowed(executable: executable, arguments: arguments)
    }

    /// 参数里的「像路径」的那部分要落在工作区内（`root` 由调用方给）。
    public func argumentsStayInsideWorkspace(_ arguments: [String], root: URL) -> AgentToolRefusal? {
        for argument in arguments where argument.hasPrefix("/") || argument.contains("..") {
            if case .outside = AgentWorkspaceSandbox.resolve(argument, in: root) {
                return .outsideWorkspace
            }
        }
        return nil
    }
}

/// 执行器（**注入**：单测用假执行器，不真起进程）。
public protocol AgentCommandRunner: Sendable {
    /// **异步**：命令可能跑在一次真实的 shell 会话里（`AgentShellSession`），
    /// 也可能跑在独立进程里（`AgentCommandExecutor`）。同步签名会把主 actor 钉住一整个命令时长
    /// （2026-10-31：命令在 Terminal 里执行这件事要求能 await）。
    func run(executable: String, arguments: [String], workingDirectory: URL) async -> AgentCommandResult
}

public struct AgentCommandResult: Equatable, Sendable {
    public var exitCode: Int32
    public var standardOutput: String
    public var standardError: String

    public init(exitCode: Int32, standardOutput: String, standardError: String) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    /// 供回灌的合并文本（**如实**带退出码，不许只给 stdout 假装成功）。
    public var combined: String {
        var text = standardOutput
        if !standardError.isEmpty { text += standardError }
        if exitCode != 0 { text += "exit:\(exitCode)" }
        return text
    }
}
