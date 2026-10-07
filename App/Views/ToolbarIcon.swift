import SwiftUI
import DoyahCore

/// **工具条图标的唯一出处**（片 `N2-2` · 基准 = `App/Views/QueryToolbar.swift`）。
///
/// 本片之前，这一套「图标 + 固定命中区（28 × 22）」的呈现**私有地长在 SQL 编辑区的工具条里**
/// （`QueryToolbar` 的 `private func toolbarIcon(_:)`），而笔记面 / 待办面的操作栏各画各的图标 ——
/// 于是同一个窗口里有两套呈现函数：一处换了字号 / 命中区，另一处不会跟着走（`N2-2` 判据③
/// 「第二套工具条 / 分段条实现 = 0」量到的就是它）。
///
/// 收成一处之后，三个面共用它：SQL 编辑区工具条（经 `QueryToolbar.toolbarIcon` 转发）、
/// 笔记面的增删查改入口、待办面的日历翻页 —— **调用点 ≥ 2**，也就没有「第二套」可言。
struct ToolbarIcon: View {

    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(Theme.font(.icon)).fontWeight(.semibold)
            .foregroundStyle(Theme.text(.secondary))
            .frame(width: Metrics.toolbarButtonWidth, height: Metrics.toolbarButtonHeight)
            .contentShape(Rectangle())
    }
}

/// **工具条图标按钮的唯一出处**：一枚纯图标按钮 = 图标 + **悬停提示**（`L(...)` 单点）。
///
/// 为什么必须是组件而不是各写一遍 `Button { } label: { Image(systemName:) } .help(...)`：
/// 那样「有图标没提示」这件事只能靠人眼查（图标按钮没有文字，提示是**唯一**说出它干什么的地方）；
/// 走这一个组件，提示是**构造参数**，漏了当场编译不过 —— 判据②「`Image(systemName:` ↔ `.help(`
/// 未配对数 = 0」在结构上就成立，不靠事后扫描。
///
/// 形态与 SQL 编辑区工具条同形（`.buttonStyle(.plain)` + 固定命中区），所以三处看起来是一套东西。
struct ToolbarIconButton: View {

    let systemName: String
    /// 悬停提示（与 `accessibilityIdentifier` 是两件事：提示给人看、标识给探针看）。
    let help: String
    var role: ButtonRole? = nil
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            ToolbarIcon(systemName: systemName)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
