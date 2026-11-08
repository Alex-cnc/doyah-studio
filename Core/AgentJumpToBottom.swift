import Foundation

/// **「回到消息底部」浮动入口**的判定与尺寸（详设 §3.39）。
///
/// 为什么判定要住在 Core 而不是视图里：它是**产品契约**（出现条件 / 消失条件 / 高度 /
/// 预留带），判据与视图必须数同一个数 —— 视图里写 `> 40`、判据里写 `> 41` 那种「两个
/// 阈值」正是本节要关掉的口子。视图只负责把这个判定结果画出来。
///
/// ## 三条口径
///
/// · **出现**：距底 **> 40pt** 且**不在贴底态**（`AgentScrollFollow` 判）——
///   后者把「内容刚长高、我们还没跟上」那一帧挡在外面（那一帧距底也可能 > 40pt，
///   但它是**我们自己**落后，不是人往上翻，弹出入口反而像在催人）；
/// · **消失**：距底回落到 **≤ 4pt**（= `AgentScrollFollow.bottomTolerance`，与贴底同一
///   容差）。两档之间**保持现状**（滞回）—— 否则在 40pt 上下抖一像素，入口就闪一次；
/// · **点它** = 滚到内容底边 + **恢复自动跟随**（`jumpToBottomRestoringFollow()`），
///   此后新内容仍贴底（不是「只滚这一次」）。
public struct AgentJumpToBottom: Sendable {

    /// 出现门槛（pt）：距底超过它才出现。
    public static let appearDistance: CGFloat = 40

    /// 消失门槛（pt）：距底回落到它以内就消失。**与贴底容差同源**，不另立一个数。
    public static let disappearDistance: CGFloat = AgentScrollFollow.bottomTolerance

    /// 入口自身高度（pt）：胶囊一行，落在 20–24 的带里（判据②按这个数对账）。
    public static let barHeight: CGFloat = 22

    /// 入口底边到对话区底边的距离（pt）= 块间距 `Spacing.m`：与「这一列里块与块之间」同一个数，
    /// 不新造一个边距。
    public static let bottomGap: CGFloat = 12

    /// 内容底部**恒留**的带（pt）= 入口高度 + 4pt 呼吸。
    ///
    /// 为什么要**恒留**而不是「出现时再加」：入口压着的这 22pt 若在出现/消失时挤进挤出，
    /// 内容就会跟着上下跳一行 —— 那既是「遮一下正文」，也会让「距底」在出现那一刻变大，
    /// 形成「出现 ⇒ 更远 ⇒ 更该出现」的自激（§3.34 条那一课的另一面）。恒留之后，
    /// 入口在不在都不改任何一段正文的位置，判据⑤ 才有「逐点相同」这个读数。
    public static let contentInset: CGFloat = barHeight + 4

    /// 这次的读数下，入口该不该出现（滞回：`currently` 决定用哪个门槛）。
    ///
    /// - Parameters:
    ///   - currently: 上一拍是否已经显示（`false` = 按出现门槛判）。
    ///   - distanceToBottom: 距底距离（pt，来自 `StickyQuestionSpy.Reading`，与跟随同一份读数）。
    ///   - isPinnedToBottom: 读数器状态机判的「贴着底」。贴底 ⇒ **一律不出现**。
    public static func isVisible(currently: Bool,
                                 distanceToBottom: CGFloat,
                                 isPinnedToBottom: Bool) -> Bool {
        guard !isPinnedToBottom else { return false }
        let threshold = currently ? disappearDistance : appearDistance
        return distanceToBottom > threshold
    }
}
