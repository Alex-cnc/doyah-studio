import Foundation

/// 下方面板（`LowerPaneView`）在**折叠 / 展开**两态下的高度提示 —— 纯逻辑，可单测。
///
/// 为什么要有这一层（2026-09-30 需求提出者实测报缺陷，队列 `L-121`）：
/// 原话「**在工作区界面，最小化折叠底部区域后，最下面有一个比底部区域标题栏宽很多的空白区域，
/// 看上去是工作区的背景不可编辑区域**」。
///
/// 根因是**同一件事有两处口径**，而且互相打架：
/// · 面板自己（`App/Views/LowerPaneView.swift`）在折叠态把自己收成「标题栏一行的理想高度」，
///   背景只画在**自己那份内容**上（`Theme.surface(.panel)`）；
/// · 外层（`App/Views/MainWindow.swift` 的 `sectionWithLowerPane`）又给它套了一个
///   `.frame(minHeight: 90, idealHeight: 200)` —— 折叠后内层只占一行（约 28pt），
///   外层那个 90pt 的框**还留着**，多出来的高度由**外层框**填，而外层框没有面板的底色
///   ⇒ 透出来的是工作区背景；水平方向也不受面板内边距约束 ⇒ 观感就是
///   「比标题栏宽很多的空白带」。
///
/// 口径收成一处：**折叠态不许留最小高度**（`nil` = 不设约束），让面板按自己的内容自量；
/// 展开态才要「至少一行按钮 + 一点内容」。两态都由这里给，调用点不再自己写数字。
public enum LowerPaneSizing {

    /// 展开态的最小高度 —— 沿用 L-84 ㈠「下方面板默认占两成」那条旧口径的下限。
    public static let expandedMinHeight: CGFloat = 90

    /// 展开态的理想高度（首次出现时按这个高度落位，之后由用户拖拽调高）。
    public static let expandedIdealHeight: CGFloat = 200

    /// 最小高度提示：**折叠态 = `nil`（不设约束）** —— 这是本缺陷的判据本体。
    public static func minHeight(collapsed: Bool) -> CGFloat? {
        collapsed ? nil : expandedMinHeight
    }

    /// 理想高度提示：折叠态同样不设 —— 让面板按标题栏一行自量，字号 / 语言变了会自己跟着变。
    public static func idealHeight(collapsed: Bool) -> CGFloat? {
        collapsed ? nil : expandedIdealHeight
    }

    // MARK: 用户拖出来的高度（队列 `L-181`）

    /// 拖拽允许的最小高度 —— 与展开态下限同源（一行按钮 + 一点内容），不另立数字。
    public static let draggableMinHeight: CGFloat = expandedMinHeight

    /// 高度上限**按可用高度的比例**算，不写死绝对值：矮窗口里也不许把编辑区挤没。
    public static let maxHeightRatio: CGFloat = 0.75

    /// 拿不到可用高度时的绝对兜底上限。
    public static let fallbackMaxHeight: CGFloat = 600

    /// 把用户拖出来的高度夹进合法范围。
    ///
    /// `available` = 面板所在段的总高（App 层拿窗口内容高度当代理）；`nil` 或 ≤ 0 ⇒ 走兜底上限。
    /// 上限与下限的相对关系也要兜住：可用高度很小时，上限不许低于下限（否则结果会随可用高度反向跑）。
    public static func clamped(height: CGFloat, available: CGFloat?) -> CGFloat {
        let lower = draggableMinHeight
        let upper: CGFloat
        if let available, available > 0 {
            upper = max(lower, (available * maxHeightRatio).rounded())
        } else {
            upper = fallbackMaxHeight
        }
        return min(max(height, lower), upper)
    }
}
