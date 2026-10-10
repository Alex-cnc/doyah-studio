import SwiftUI
import DoyahCore

/// **工具条图标的唯一出处**（片 `N2-2` · 基准 = `App/Views/QueryToolbar.swift`）。
///
/// 本片之前，这一套「图标 + 固定命中区（28 × 28）」的呈现**私有地长在 SQL 编辑区的工具条里**
/// （`QueryToolbar` 的 `private func toolbarIcon(_:)`），而笔记面 / 待办面的操作栏各画各的图标 ——
/// 于是同一个窗口里有两套呈现函数：一处换了字号 / 命中区，另一处不会跟着走（`N2-2` 判据③
/// 「第二套工具条 / 分段条实现 = 0」量到的就是它）。
///
/// 收成一处之后，三个面共用它：SQL 编辑区工具条（经 `QueryToolbar.toolbarIcon` 转发）、
/// 笔记面的增删查改入口、待办面的日历翻页 —— **调用点 ≥ 2**，也就没有「第二套」可言。
///
/// ## 两道尺寸都收在令牌层（`FR-NOTEUI-21` · 派单 `T-20261010-166` §三.3）
///
/// 人类主人 2026-10-10 原话逐字：「**笔记左栏上面的增改删图标间距太大了，不够精致。**」
/// 那条抱怨量出来的东西与修法都在这一处：
///   · **命中区** `Metrics.toolbarButtonWidth × Metrics.toolbarButtonHeight` —— 由 **28 × 22**
///     提到 **28 × 28**（契约「热区 ≥ 28 × 28」）；
///   · **图标字号** `Metrics.toolbarIconSize` —— 由「与正文同字号」（13）提到 **17**
///     （契约「图标 16–18pt」）。
///
/// **为什么「不够精致」的根在这两个数**：命中区 28pt 宽、图标只有 13pt 时，相邻两枚之间
/// **看得见的留白**接近 19pt（`28 − 13 + 4`）—— 一簇入口看着就是「稀稀拉拉」；把图标画到 17pt
/// 之后同一簇收紧到 ≈15pt，而命中区仍 ≥28×28。
///
/// **「看得见的留白」为什么不追契约那句「相邻 ≤ 8pt」**：契约那句量的主体是**入口控件的 frame**
/// （命中区）—— 两枚命中区之间的间距 = `Spacing.xs` = **4pt** ≤ 8pt ✅，判据由
/// `TestsUISnapshot/NotesCrudIconSpacingProbeTests.swift` 在活宿主里逐个量。
/// 命中区一旦定了 ≥28pt 宽，两枚图形**边缘**之间就至少是「命中区宽 − 图标字号」pt ——
/// 想把它压到 8pt 就得把图标画到 20pt 以上（越出契约的 16–18pt）或把命中区收到 21pt 以下
/// （违反「≥ 28 × 28」）。所以这一档的可度量口径 = **命中区间距 ≤ 8pt + 图标 16–18pt**，
/// 两者合起来把观感收紧；像素上的留白（≈19 → ≈15pt）另由探针的成对读数留档。
struct ToolbarIcon: View {

    let systemName: String
    /// **选中态高亮**（人类主人令 `T-20261007-080`：模式切换的「当前在哪一面」用**高亮**表示，
    /// 不写文字、不加标签）。与「悬停底」两回事：悬停是鼠标位置、选中是真状态 ——
    /// `ActivityBarView` 里那一对（强调条 + 极淡底）分的也是这两层，这里量的是同一件事。
    var isSelected: Bool = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: Metrics.toolbarIconSize, weight: .semibold))
            .foregroundStyle(isSelected ? Theme.accentColor : Theme.text(.secondary))
            .frame(width: Metrics.toolbarButtonWidth, height: Metrics.toolbarButtonHeight)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(isSelected
                          ? Theme.accentColor.opacity(Theme.isDarkAppearance
                                                      ? Overlay.Selection.darkAlpha
                                                      : Overlay.Selection.lightAlpha)
                          : Color.clear)
            )
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
    /// 选中态高亮（透传给 `ToolbarIcon`；默认不选中 —— 既有调用点一个都不动）。
    var isSelected: Bool = false
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            ToolbarIcon(systemName: systemName, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .help(help)
        // **讲得出名字**（人类主人令 `T-20261007-080` 判据②）：图标按钮没有文字，
        // 悬停提示与辅助功能标签是它**唯一**的两条说明。`help` 是构造参数（漏了编译不过），
        // 辅助功能标签由调用点用 `.accessibilityLabel` 显式给 —— 探针按它挑控件，不靠遍历顺序。
        .accessibilityLabel(Text(help))
    }
}
