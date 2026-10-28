import Foundation

/// `FR-STD-WS-VCS-002` 的**请求面**：这一份差异是「怎么取」的 —— 忽略空白 / 上下文行数。
///
/// 为什么把它做成 Core 里的纯值、而不是在 `GitWorktreeProbe` 里各拼一份字符串：
/// 界面上说「已忽略空白」，取数那一路就得**真的**带了 `-w`。两处各拼一次，
/// 改了一处就变成「开关亮着、差异没变」—— 这种缺陷在编译期一个字都不会响，
/// 只能靠眼睛比对两份界面。
///
/// 一条硬口径：**开关必须插在 `--` 之前**。`--` 之后全是 pathspec，
/// 把 `-w` 插在后面 ⇒ git 把它当成一个叫 `-w` 的路径（`fatal: ambiguous argument`），
/// 而这条错在界面上只会显示成「差异读不出来」。判据钉住这一条（`Tests/GitDiffRequestTests`）。
public struct GitDiffRequest: Equatable, Sendable {

    /// 忽略空白（`git diff -w`）：纯空白的改动不算改动。
    public var ignoresWhitespace: Bool
    /// 上下文行数（`git diff -U<n>`）；`0` = 交给 git 的缺省（不传 `-U`）。
    public var contextLines: Int

    /// git 自己的缺省上下文（3 行）—— 与今天看到的完全一致，不是我们另定的一档。
    public static let defaultContextLines = 3
    /// 界面可选的上下文档位：3 = git 缺省 / 12 / 40（后两档才有值得折叠的长段）。
    public static let contextSteps = [3, 12, 40]

    public init(ignoresWhitespace: Bool = false, contextLines: Int = defaultContextLines) {
        self.ignoresWhitespace = ignoresWhitespace
        self.contextLines = max(0, contextLines)
    }

    /// 本请求要加的开关（顺序固定：`-w` 在 `-U` 之前）。
    public var switches: [String] {
        var output: [String] = []
        if ignoresWhitespace { output.append("-w") }
        if contextLines > 0 { output.append("-U\(contextLines)") }
        return output
    }

    /// 把开关插进一份已经写好的 git 参数（**`--` 之前**）。
    public func applying(to arguments: [String]) -> [String] {
        let switches = self.switches
        guard !switches.isEmpty else { return arguments }
        if let separator = arguments.firstIndex(of: "--") {
            var output = arguments
            output.insert(contentsOf: switches, at: separator)
            return output
        }
        return arguments + switches
    }
}
