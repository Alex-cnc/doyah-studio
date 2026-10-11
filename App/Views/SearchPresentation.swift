import DoyahCore
import SwiftUI

/// **搜索呈现的唯一出处**（`FR-NOTEUI-04` · 笔记面与工作区面**同一设计语言**）。
///
/// 人类主人 2026-10-10 原话逐字：「**笔记搜索不要那么大一个框子，有个搜索图标就行，
/// 用户点击时再出现框子，跟工作区的搜索保持相同设计语言。**」
///
/// 这一句里有两半，两半都落在本文件：
///   · 「**有个搜索图标就行**」⇒ `SearchRevealButton`（收起态那一枚纯图标 + 悬停提示）；
///   · 「**跟工作区的搜索保持相同设计语言**」⇒ `SearchField`：**框子本身**的呈现函数。
///     工作区标头那个框（`WorkspaceHeaderSearch.field`）与笔记面点图标之后浮出来的那个框
///     用的是**同一段代码** —— 不是各画一遍（两处各写一份的症状：一处换了图标 / 圆角 / 描边、
///     另一处不会跟着走，两个框并排站着就不是一套东西了）。
///
/// 「同一呈现函数」在**机械上**的意思是：`App/Views/` 里画搜索框的那段
/// 「放大镜 + 圆角底 + 描边」只出现一次（就这里），两个面的 `TextField` 都塞进 `SearchField { }`。
/// 判据 `TestsUISnapshot/NotesSearchRevealProbeTests.swift` 把这件事钉成两条：
/// ① 两个面渲染出来的框**几何同形**（同高、同样式，逐点量）；② 图标符号**只有一处定义**
/// （`SearchPresentation.symbolName`），两处引用的都是它。
///
/// 边界（如实登记）：本文件只给**形态**，不给检索语义 —— 词绑在哪儿、往哪儿查、结果怎么画，
/// 仍归各自的面（工作区 = `WorkspaceHeaderSearch` + `Core/WorkspaceSearch`；
/// 笔记 = `AppState.notesQuery` + 库检索）。这里改一个圆角，两个面一起变；
/// 这里改不了「搜什么」。
enum SearchPresentation {

    /// **图标形制（唯一出处）**：收起态那一枚按钮的图标，与展开态框内那枚放大镜，
    /// 是**同一个符号** —— 两处各写一个字符串，改一处必然漏一处。
    static let symbolName = "magnifyingglass"
}

/// **看到的那一个搜索框**（放大镜 + 内容 + 圆角底 + 描边）——
/// 工作区标头的常驻框与笔记面浮出来的框，都是它画出来的。
///
/// 内容由调用点给（`TextField` 及其随附的按钮 / 选择器），本视图只管**壳**：
/// 横向内边距 `Spacing.s`、纵向 `Spacing.xs`、`Radius.control` 圆角、
/// `Theme.surface(.raised)` 底、`Metrics.hairline` 描边 —— 与 `N2-2`
/// 「与 SQL 编辑区同一设计语言」那一族的取值同源（全部取自令牌，不写魔数）。
struct SearchField<Content: View>: View {

    @Environment(\.colorScheme) private var scheme

    /// 框里的东西（放大镜之后那一串）。
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: SearchPresentation.symbolName)
                .imageScale(.small)
                .foregroundStyle(Theme.text(.tertiary))
            content()
        }
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(Theme.surface(.raised))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .strokeBorder(Theme.hairline(scheme), lineWidth: Metrics.hairline)
        )
    }
}

/// **收起态那一枚搜索图标**（`FR-NOTEUI-04` 的「有个搜索图标就行」）。
///
/// 走的是 `ToolbarIconButton`（工具条图标的**唯一出处**）：固定命中区 + `.help` 悬停提示，
/// 与左栏那三枚增改删入口**同一形态**（漏了提示当场编译不过）。
struct SearchRevealButton: View {

    /// 悬停提示（给人看的那一句）。
    let help: String

    let action: () -> Void

    var body: some View {
        ToolbarIconButton(systemName: SearchPresentation.symbolName, help: help, action: action)
    }
}
