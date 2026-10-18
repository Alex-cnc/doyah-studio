import Foundation

/// 把「界面侧的一次现场读数」翻成工作区事实（`FR-AI-22` ②）。
///
/// 为什么单独一层：`AgentWorkspaceFacts` 是**事实的形状**，`AgentWorkspaceContext` 是**裁剪口径**，
/// 而「编辑器给的是一段 `NSRange`（UTF-16 偏移）、页签给的是一整篇正文」这两件事之间的换算
/// （选区取文字、越界怎么夹、起始行怎么算）**必须能逐条断言** —— 否则「用户选了三行，模型拿到别的三行」
/// 这种错只有人眼在对话框里看得见。
///
/// 三条口径（每条都对应一类真实错法）：
/// 1. **空选区不是选中**：`length == 0` 就是光标，不是「用户指了这儿」—— 带上它等于凭空塞一段空壳；
/// 2. **越界就夹到文档末尾**，不整体丢弃：编辑器重建 / 外部同步的瞬间，视图里的偏移可能比正文长一拍；
///    夹一下仍是用户最后选的那段，丢掉就变成「我明明选了」却没带上；
/// 3. **起始行由正文数出来**（1 起）：不信任编辑器另报的行号 —— 两份读数迟早对不上。
public enum AgentWorkspaceSnapshot {

    /// 现场读数 → 工作区事实。
    ///
    /// - Parameters:
    ///   - filePath: 当前打开的文件路径（Home / 对话页签时为 `nil`）。
    ///   - text: 该页的正文（模型里那份，不是编辑器内部的副本 —— 取数只认一个来源）。
    ///   - selection: 编辑器**此刻真实**的选区（`EditorCommandCenter.liveSelection`），UTF-16 偏移。
    ///   - terminalText: 终端面板当前屏幕文本（尾部裁剪由 `AgentWorkspaceContext` 做）。
    public static func facts(filePath: String? = nil,
                             text: String? = nil,
                             selection: NSRange? = nil,
                             terminalText: String? = nil,
                             workspacePath: String? = nil,
                             workspaceEntries: [String]? = nil) -> AgentWorkspaceFacts {
        let activeFile: (path: String, text: String)? = {
            guard let filePath, let text, !text.isEmpty else { return nil }
            return (path: filePath, text: text)
        }()
        return AgentWorkspaceFacts(activeFile: activeFile,
                                   selection: selectionText(in: text, range: selection, path: filePath),
                                   terminalText: terminalText,
                                   workspacePath: workspacePath,
                                   workspaceEntries: workspaceEntries)
    }

    /// 选区 → （路径 + 选中的正文 + 起始行）。
    ///
    /// 拿不到就说拿不到（返回 `nil`），**不编**一段文字出来：`location` 落在文档之外、
    /// 或夹完长度为 0，都当作「这一刻没有选中」。
    public static func selectionText(in text: String?,
                                     range: NSRange?,
                                     path: String?) -> (path: String, text: String, firstLine: Int?)? {
        guard let text, let path, let range,
              range.location != NSNotFound, range.length > 0 else { return nil }
        let document = text as NSString
        guard range.location >= 0, range.location < document.length else { return nil }
        // 越界就夹到末尾（长度取到文档结束为止）。
        let clipped = NSRange(location: range.location,
                              length: min(range.length, document.length - range.location))
        return (path: path,
                text: document.substring(with: clipped),
                firstLine: firstLine(ofUTF16Offset: clipped.location, in: text))
    }

    /// UTF-16 偏移 → 行号（1 起）。
    public static func firstLine(ofUTF16Offset offset: Int, in text: String) -> Int {
        guard offset > 0 else { return 1 }
        let document = text as NSString
        let end = min(offset, document.length)
        var line = 1
        var index = 0
        while index < end {
            if document.character(at: index) == 0x0A { line += 1 }
            index += 1
        }
        return line
    }
}
