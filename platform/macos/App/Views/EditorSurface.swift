import SwiftUI

/// 编辑面（能编辑多行文本的那一块）的**底色与字色**：全工程唯一写法。
///
/// ## 为什么要有它（队列 `L-142` · 内测清单 **甲2**）
///
/// 需求提出者 2026-09-30 内测原话：「**笔记的正文编辑区背景色明显不符合其他 2 个的配色方案**」。
/// 「其他 2 个」= 工作区代码编辑器（`App/Views/CodeEditorView.swift`）与数据库 SQL 编辑器
/// （`App/Views/SQLEditorView.swift`）—— 那两个都是 AppKit `NSTextView`，**底色与字色早就在用
/// 主题令牌**（`textView.backgroundColor = Theme.nsColor(Surface.content)` /
/// `textColor = Theme.nsColor(TextTone.primary)`，见 `L-111` 那一批）。
///
/// 而笔记正文用的是 SwiftUI `TextEditor`：它**默认画系统的 `textBackgroundColor`** ——
/// 「跟随系统外观」而不是「跟随本产品的主题令牌」，于是同一个窗口里出现两种底：
/// 工作区是科技蓝、笔记是系统灰（深色下更明显：一边深海军蓝、一边中性近黑）。
/// **门禁当时全绿**：设计令牌棘轮（`Scripts/check-design-tokens.py`）扫的是「裸颜色 / 裸字号 /
/// 裸间距」这类**写坏的值**，而这里的问题是**什么都没写**（把底色交给了系统），
/// 正是「覆盖面缺口」。判据因此单独一条，见 `Scripts/check-editor-surface-tokens.py`（闭环第 6 项）。
///
/// ## 口径（契约 `Docs/概要设计.md` §3.31）
///
/// · **底色 = `Surface.content`、字色 = `TextTone.primary`** —— 与另两个编辑面同一档；
/// · `.scrollContentBackground(.hidden)` 是**先决条件**：不把系统那层底色让出来，
///   后面挂的 `.background(...)` 会被它盖住（画了等于没画，而且看不出是没画）；
/// · 唯一出处 = 本文件。视图里写 `.editorSurface()`，**不许**各自写
///   `scrollContentBackground` / 编辑器底色（`Scripts/check-editor-surface-tokens.py` 判这一条）。
///
/// ## 边界（如实登记）
///
/// 本写法管的是**底色与字色**两件事到源码这一层；「渲染出来到底什么颜色」由探针
/// `TestsUISnapshot/NotesEditorSaveProbeTests.swift` 在**像素上**判（编辑区取一点，必须等于
/// 当前主题的 `Surface.content`，且**不等于**系统 `textBackgroundColor`）。
/// 行号列的规矩是另一条（`L-111`，`.editorSurface()` 不管行号）。
extension View {

    /// 把这一块做成「编辑面」：系统底色让位 ⇒ 底色与字色一律走主题令牌。
    ///
    /// 用法（`TextEditor` / 任何自带系统底色的可编辑面都适用）：
    ///
    /// ```swift
    /// TextEditor(text: $body)
    ///     .font(Theme.font(.mono))
    ///     .editorSurface()
    ///     .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.surface(.panel), lineWidth: 1))
    /// ```
    func editorSurface() -> some View {
        self
            // 先让位：`TextEditor` / `List` / `Form` 这类自带滚动底色的控件，
            // 不写这一行的话下面那个 `.background` 会被系统底色压在底下（看不见、也不报错）。
            .scrollContentBackground(.hidden)
            .background(Theme.surface(.content))
            .foregroundStyle(Theme.text(.primary))
    }
}
