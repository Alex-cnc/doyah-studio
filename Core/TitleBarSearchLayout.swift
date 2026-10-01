import Foundation

/// 标题栏搜索栏的**宽度策略**（队列 `L-141`，内测清单 **甲1**）—— 纯逻辑，可单测。
///
/// ## 由头（需求提出者 2026-09-30 内测原话）
///
/// 「**不是全屏时搜索框没有同步缩小，遮住了 `Doyah Studio - Workspace` 标题**」。
///
/// 一句原话里有两个事实：搜索栏是**居中**的（`FR-EDIT-37` 原话「标题后面居中可以放一个长长的
/// 搜索栏」），而窗口变窄时它**不收敛** —— `.searchable(placement: .toolbarPrincipal)` 把宽度
/// 交给系统，系统给的是一个**与窗口宽度无关**的宽度 ⇒ 宽窗口下两者各占一处相安无事，
/// 窗口一窄就打架。
///
/// ## 几何模型（口径的唯一出处，界面照着摆）
///
/// 搜索栏**居中**，标题占它左边那一段（标题栏左端还有交通灯 —— `leadingInset`）。
/// 居中意味着**两侧对称让位**：搜索栏给左边让出多少，右边也就跟着让出同样多的一块。
/// 于是「不长到标题带上」的条件是
///
///     搜索栏宽度 ≤ 窗口宽度 − 2 ×（leadingInset + 标题宽度 + titleGap）
///
/// 取的是**居中标题**这一档（最保守的一档）—— 系统把标题画在哪一侧都不会比这更差。
/// 值里**不含**任何像素谈判：宽度由这里给，界面只负责把结果摆上去。
///
/// ## 两条不变量（判据就是它们）
///
/// 1. **标题永远完整可见** —— 任何窗口宽度下搜索栏都不侵入标题带（含下面那一档）；
/// 2. **不挤成一条缝** —— 可用宽度连 `minimumWidth` 都不到时，搜索栏**收成 0**（这一档不显示，
///    回车入口仍在 ⌘K 与命令面板），不做「宽 40pt 的搜索框」这种既不显示标题、也不能用的东西。
public enum TitleBarSearchLayout {

    /// 搜索栏的**理想**宽度：够放一句检索词，也不至于霸占标题左侧那一块
    /// （需求提出者原话要的是「一个**长长**的搜索栏」，不是一条窄缝）。
    public static let idealWidth: CGFloat = 360

    /// 能让搜索栏**真的可用**的最小宽度；低于它就不该挤在那里（见不变量 2）。
    public static let minimumWidth: CGFloat = 180

    /// 搜索栏与标题之间**必须留出的空档**。
    public static let titleGap: CGFloat = 24

    /// 标题左端之外还要占掉的固定 chrome（交通灯三件 + 标题栏左内边距）。
    public static let leadingInset: CGFloat = 90

    /// 这一档**留给搜索栏**的宽度（小于 0 按 0 计 —— 不猜、不取绝对值）。
    public static func availableWidth(windowWidth: CGFloat, titleWidth: CGFloat) -> CGFloat {
        guard windowWidth.isFinite, titleWidth.isFinite else { return 0 }
        let band = leadingInset + max(titleWidth, 0) + titleGap
        return max(0, windowWidth - 2 * band)
    }

    /// 搜索栏宽度：`0` = 这一档放不下、整条不显示（此时只剩标题与 ⌘K）。
    public static func searchFieldWidth(windowWidth: CGFloat, titleWidth: CGFloat) -> CGFloat {
        let available = availableWidth(windowWidth: windowWidth, titleWidth: titleWidth)
        guard available >= minimumWidth else { return 0 }
        return min(idealWidth, available)
    }

    /// 给定一个宽度摆上去，会不会**压到标题带**（不变量 1 的机械形式）。
    ///
    /// 它同时是判据的「能判红」那一半：写死宽度的旧口径（`320`）在窄窗口上必须判 `false`，
    /// 否则这条不变量等于没写。
    public static func fitsWithoutCoveringTitle(
        windowWidth: CGFloat,
        titleWidth: CGFloat,
        searchFieldWidth: CGFloat
    ) -> Bool {
        guard searchFieldWidth.isFinite else { return false }
        return max(searchFieldWidth, 0) <= availableWidth(windowWidth: windowWidth, titleWidth: titleWidth)
    }
}
