import AppKit
import DoyahCore

/// 「打开文件…」的**唯一实现**：工具栏图标、页签条按钮、文件菜单三项都调它。
///
/// 为什么收成一处：同一动作原来在两个视图里各写了一份 `NSOpenPanel`（页签条 + 工作区动作行），
/// 现在菜单也要一个入口 —— 三份必然走散（人类主人 2026-10-18 实测：「工作区菜单里打开文件没了」）。
/// 面板参数、提示文案、失败处理从此只有一份。
enum WorkspaceOpenFilePanel {

    /// 弹面板；用户选中就回调并返回 URL，取消返回 `nil`。
    @discardableResult
    static func present(open: (URL) -> Void) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = L(.workspaceOpenFileButton)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        open(url)
        return url
    }
}
