import SwiftUI

/// **二级对话框里的动作按钮（带文字）**。
///
/// ## 为什么要有它
///
/// 人类主人 2026-10-18：「点击菜单弹出来的二级对话框里基本都还是图标，没有恢复按钮语义」。
/// 工具条 / 顶带 / 左栏用图标是对的（横向空间被文案挤压），但**对话框是竖向表单**，
/// 一排只有一两个动作，图标省不出空间、只省掉了"这是什么"。所以对话框里的动作按钮
/// **图标 + 文字**：图标负责一眼定位，文字负责讲清语义。
///
/// ## 与 `ToolbarIconButton` 的分工（一条线，不许混）
///
/// - 工具条 / 顶带 / 左栏 / 空态操作 ⇒ `ToolbarIconButton`（纯图标，必须有 `help`）；
/// - 对话框 / 弹层 / 表单动作行 ⇒ `DialogActionButton`（图标 + 文字，`title` 即提示与无障碍标签）。
struct DialogActionButton: View {

    let systemName: String
    /// 按钮文字（已本地化的字符串，调用点写 `L(.key)`）。
    let title: String
    var role: ButtonRole? = nil
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemName)
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(isDisabled)
        // 有文字了，提示仍留着（鼠标停一会儿也能看到全称），无障碍标签与文字同源
        .help(title)
        .accessibilityLabel(Text(title))
    }
}
