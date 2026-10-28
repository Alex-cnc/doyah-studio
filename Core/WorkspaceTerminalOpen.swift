import Foundation

/// 「在终端中打开」（`FR-STD-WS-FS-003`：与「在访达中显示」并列的那一条）。
///
/// 只做**一件事**：算出「该让哪个程序、带哪些参数、在哪个目录里开」——
/// 真正拉起进程的那一步在 `App/WorkspaceStore`（Core 不起进程：判据要能在无界面环境里跑）。
///
/// 两条口径：
///   ① **文件开它所在的目录**（终端里 `cd` 到父目录才看得见这个文件；`cd` 到文件本身是错的）；
///      目录就开它自己；
///   ② **路径原样当一个参数传**（不拼字符串、不加引号）：`/usr/bin/open` 收的是 argv，
///      路径里的空格、引号、`$` 都是普通字符。自己拼 shell 引号是这条路上最经典的一处注入面。
public enum WorkspaceTerminalOpen {

    /// 一次「打开」的完整计划（`tool` + `arguments`）。
    public struct Plan: Equatable, Sendable {
        public let tool: String
        public let arguments: [String]

        public init(tool: String, arguments: [String]) {
            self.tool = tool
            self.arguments = arguments
        }

        /// 会被打开的那个目录（= 最后一个参数）。
        public var directoryPath: String { arguments.last ?? "" }
    }

    /// 走 `/usr/bin/open`（绝对路径：不靠 `PATH`，GUI 进程的 `PATH` 与终端里不一样）。
    public static let tool = "/usr/bin/open"

    /// 该在哪个目录里开：目录 = 它自己；文件 = 它所在的目录。
    public static func directory(for url: URL, isDirectory: Bool) -> URL {
        isDirectory ? url : url.deletingLastPathComponent()
    }

    /// 计划（**纯函数**，判据钉这里）。
    public static func plan(for url: URL, isDirectory: Bool) -> Plan {
        Plan(
            tool: tool,
            arguments: ["-a", "Terminal", directory(for: url, isDirectory: isDirectory).path]
        )
    }

    /// 从相对路径取计划：**解析不出来的路径不给计划**（`nil`）——
    /// 相对路径可能来自缓存 / 书签 / 模型输出，不能让 `../..` 把终端开到工作区外面去。
    /// 传 `""`（或只有空白）表示工作区根本身；`..` 那类逃逸一律 `nil`，**不当作根**。
    public static func plan(relativePath: String, isDirectory: Bool, in workspaceURL: URL) -> Plan? {
        let trimmed = relativePath.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return plan(for: workspaceURL, isDirectory: true) }
        guard let url = WorkspaceTree.resolve(relativePath: trimmed, in: workspaceURL) else { return nil }
        return plan(for: url, isDirectory: isDirectory)
    }
}
