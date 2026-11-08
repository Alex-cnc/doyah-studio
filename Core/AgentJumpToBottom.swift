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

    /// 入口上方与视口之间的呼吸（pt）：**眼睛看到的那个间隙**（判据量的也是它）。
    public static let topGap: CGFloat = 4

    /// 滚动视口在底部占掉的那 2pt（实测：`NSScrollView` 的框比可见内容区高 2pt，滚动条那条边）。
    ///
    /// 带高要把这 2pt 算进去，否则入口会贴着视口下沿（实测只剩 2pt）；这是**布局事实的补偿**，
    /// 不是又一个设计边距 —— 所以单独一个常量、单独一句注释，不和上面三个混用。
    public static let viewportInset: CGFloat = 2

    /// **保留窄条**的高（pt）= 呼吸 4 + 入口 22 + 底边间距 12 + 视口内衬 2 = 40。
    ///
    /// 这根条只在入口**出现时**占位；**不出现时它整个不存在（高 0）**，空间还给正文。
    /// 三个决定都必须记下来：
    ///
    /// ① **在视口之外**（不是浮在正文上）：条是滚动区下面的兄弟，视口到条的上沿为止 ——
    ///    所以正文**任何一行**都不会被入口压住（浮在正文上的写法只在「正好贴底」时不遮，
    ///    上翻途中经过入口那一条的正文会被压掉半行，本轮实测截图上就是压住了最后可见的一行）。
    /// ② **条件占位，不是恒留**：恒留一条 40pt 的空带等于「入口不在时也长期白占一格」。
    ///    条件占位的反对意见是「出现 ⇒ 视口矮 40 ⇒ 距底凭空 +40 ⇒ 滚到底仍 > 4pt ⇒ 关不掉」——
    ///    这条推理不成立：滚到内容底边时 `NSClipView` 把偏移**夹到** `内容高 − 视口高`，
    ///    距底恒为 0 ⇒ 消失条件（≤ 4pt）永远可达（判据②/④ 真跑量的是这个数）。
    /// ③ **条高 ≤ 出现门槛**（`appearDistance` 40 ≥ 40）：入口出现那一拍视口正好矮一条，
    ///    而出现要求「距底 > 40」⇒ 出现时偏移离底已超过一条，视口缩短**不需要**夹紧偏移，
    ///    **正文一行都不跳**（`appearsWithoutShiftingContent` 把这条关系钉在这里）。
    public static let stripHeight: CGFloat = topGap + barHeight + bottomGap + viewportInset

    /// 这一拍该占的高：出现 ⇒ `stripHeight`；不出现 ⇒ **0**（把空间还给正文）。
    public static func reservedHeight(visible: Bool) -> CGFloat { visible ? stripHeight : 0 }

    /// 出现门槛是否盖得住保留条（见 `stripHeight` 的第 ③ 条）—— 判据按它判红，不许静默违反。
    public static var appearsWithoutShiftingContent: Bool { appearDistance >= stripHeight }

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
