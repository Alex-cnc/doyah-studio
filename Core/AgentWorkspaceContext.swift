import Foundation

/// 工作区侧的上下文事实（`FR-AI-22`）：**App 只负责把事实填进来，怎么裁由这里定**。
///
/// 为什么这么切：文件 / 选中 / 终端尾部三类都跟 UI 强耦合（`NSTextView` 选区、终端屏缓冲、
/// 页签正文），一旦把"取数"和"裁剪"写在一处，裁得对不对就只能靠人眼在界面上看。
/// 拆开后，裁剪规则（带不带、留头还是留尾、超限怎么标）是**纯函数**，可以逐条断言。
/// 注意：**刻意不是 `Equatable`** —— 里面是元组（`(path:text:)`），
/// 元组不自动合成 `Equatable`；判据要比就比具体字段，别退回到"比整个结构"。
public struct AgentWorkspaceFacts: Sendable {

    /// 当前打开的文件（路径 + 正文）。
    public var activeFile: (path: String, text: String)?
    /// 编辑器里的选中范围（路径 + 选中正文 + 起始行号，1 起）。
    public var selection: (path: String, text: String, firstLine: Int?)?
    /// 终端面板的尾部文本（**整屏或回滚区都可以**，裁剪由这里做）。
    public var terminalText: String?
    /// 工作区根目录（给"我现在在哪个树里"用）。
    public var workspacePath: String?
    /// 根目录条目（已按名字排好序；不给就不列 —— 本处不自己去碰文件系统）。
    public var workspaceEntries: [String]?

    public init(activeFile: (path: String, text: String)? = nil,
                selection: (path: String, text: String, firstLine: Int?)? = nil,
                terminalText: String? = nil,
                workspacePath: String? = nil,
                workspaceEntries: [String]? = nil) {
        self.activeFile = activeFile
        self.selection = selection
        self.terminalText = terminalText
        self.workspacePath = workspacePath
        self.workspaceEntries = workspaceEntries
    }
}

/// 把工作区事实翻成上下文引用（`FR-AI-22` ①）。
///
/// 四条口径（每条都是为了"别把没用的东西塞给模型，也别把有用的东西悄悄丢掉"）：
/// 1. **空就是空**：正文为空白 ⇒ 这一段不带（不塞一个空壳占预算）；
/// 2. **有选中就先把选中放前**（用户指哪儿看哪儿），**当前文件同时带上**（选中脱离文件没意义），
///    但如果选中就是整份文件（长度相同）⇒ 只带一次，不重复；
/// 3. **终端只留尾部**（最有用的在末尾）；行数先裁，再由 `AgentContextAssembler` 按字符裁；
/// 4. **目录只在没有打开文件时带**（否则本来就知道自己在哪个树里，白占预算）。
public enum AgentWorkspaceContext {

    /// 终端尾部保留的最大行数（先按行裁，再按字符裁 —— 两道都过）。
    public static let maxTerminalLines = 60
    /// 目录条目上限。
    public static let maxDirectoryEntries = 80

    public static func references(from facts: AgentWorkspaceFacts) -> [AgentContextReference] {
        var out: [AgentContextReference] = []

        // ① 选中 —— 放最前：用户「就这段」的意思最明确
        if let selection = facts.selection,
           !selection.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            out.append(.selection(path: selection.path, text: selection.text,
                                  firstLine: selection.firstLine))
        }

        // ② 当前文件 —— 与选中内容完全相同就不再重复带
        if let file = facts.activeFile,
           !file.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           file.text != facts.selection?.text {
            out.append(.file(path: file.path, text: file.text))
        }

        // ③ 终端尾部
        if let raw = facts.terminalText, !raw.isEmpty {
            let tail = tailLines(of: raw, keeping: maxTerminalLines)
            if !tail.isEmpty { out.append(.terminalTail(text: tail)) }
        }

        // ④ 目录（只在没有文件时）
        if facts.activeFile == nil, let path = facts.workspacePath, let entries = facts.workspaceEntries {
            let capped = Array(entries.prefix(maxDirectoryEntries))
            if !capped.isEmpty { out.append(.directory(path: path, entries: capped)) }
        }

        return out
    }

    /// 取最后 `keeping` 行；末尾的空行去掉（终端底部常是空白行）。
    static func tailLines(of text: String, keeping: Int) -> String {
        guard keeping > 0 else { return "" }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeLast()
        }
        guard lines.count > keeping else { return lines.joined(separator: "\n") }
        return lines.suffix(keeping).joined(separator: "\n")
    }
}
