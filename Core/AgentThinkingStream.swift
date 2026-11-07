import Foundation

// MARK: - 流式增量的合并（详设 §3.33.2）

/// **思考 / 正文流式增量的合并器**（详设 §3.33.2）。
///
/// ## 为什么要有它（人类主人 2026-11-07 真机 beta1.0.4）
///
/// > 「思考过程中，流式输出让滚动条很闪，不像 hermes 的输出这么丝滑」
///
/// 根因不在「滚动条画得不好」，而在**上屏频率**：模型是 token 级回调，一条回调就把
/// 整段文本的长度改一次 ⇒ `@Published state` 发一次 ⇒ SwiftUI 重算一帧 ⇒ 思考区
/// `ScrollView` 的内容尺寸变一次、滚动指示器按新尺寸重算一次。端点每秒吐 50~200 个
/// 增量就是每秒 50~200 次重排，人眼看就是「闪」。
///
/// Hermes TUI 之所以丝滑，是因为它**按帧刷**：增量只是往缓冲里追加，真正重画一帧
/// 是有节奏的。这里照同一口径：**一条增量先进 buffer，一个合并窗口（默认 50ms =
/// 20 次/秒，高于 60Hz 的 3 帧、低于人眼可辨的抖动）到期才一次性上屏**。
///
/// ## 三条口径
///
/// 1. **头一条不等**（leading edge）：buffer 空且距上次上屏已过窗口 ⇒ 立刻上屏。
///    「第一句字马上出现」是体感的一半；憋 50ms 再显示第一句是另一种不丝滑。
/// 2. **窗口内全合**（trailing edge）：窗口里堆的增量攒到一次 `takeAll` 里，
///    调用方用**一次状态变更**落地（`AgentChatState.applyBatch`）⇒ 只发一次
///    `@Published`、只重算一帧。
/// 3. **结构边界强刷**（`flush()`）：工具调用 / 跳 / 终态这类**非增量**事件到达前
///    必须先把积压的字上屏 —— 否则过程行会跑到正文前面（顺序错乱比闪更难查）。
///    一轮收尾同样强刷，不留半句在 buffer 里。
///
/// ## 读数（`Tests/AgentThinkingStreamTests.swift`）
///
/// 200 条增量、每条间隔 2ms（模拟端点最密的一档）：真合并 **9 次上屏**（4.5%）；
/// `interval = 0`（关节流的反例）**200 次上屏**（100%）⇒ 判据有牙齿。
public struct AgentStreamCoalescer: Sendable {

    /// 合并窗口。50ms = 20 次/秒：**低于** SwiftUI 一帧的量级（16.7ms 不会漏），
    /// 又远高于「看得出在流」的下限；再短就回到刷屏，再长字会一顿一顿地跳。
    public static let interval: TimeInterval = 0.05

    /// 本实例的窗口（0 = 不合并，只给反例判据用）。
    public let interval: TimeInterval

    private var pending: [AgentLoopEvent] = []
    private var lastFlushAt: TimeInterval = -.infinity

    /// 进来了多少条增量（读数：与 `flushCount` 相比就是合并率）。
    public private(set) var ingestedCount = 0
    /// 真正上屏了多少次（读数：判据 ① 的分子）。
    public private(set) var flushCount = 0

    public init(interval: TimeInterval = AgentStreamCoalescer.interval) {
        self.interval = interval
    }

    /// 有没有积压（收尾前必须为空）。
    public var isEmpty: Bool { pending.isEmpty }
    public var pendingCount: Int { pending.count }

    /// 进一条增量。**到点就返回这一批**（调用方一次性上屏），没到点返回 `nil`（继续攒）。
    @discardableResult
    public mutating func ingest(_ event: AgentLoopEvent, at now: TimeInterval) -> [AgentLoopEvent]? {
        pending.append(event)
        ingestedCount += 1
        guard isDue(at: now) else { return nil }
        return takeAll(at: now)
    }

    /// 现在到点没有（头一条增量用 leading edge 语义：`lastFlushAt = -inf` ⇒ 立刻为真）。
    public func isDue(at now: TimeInterval) -> Bool {
        now - lastFlushAt >= interval
    }

    /// 距下次可上屏还要多久（0 = 现在）。
    public func timeUntilDue(at now: TimeInterval) -> TimeInterval {
        max(0, interval - (now - lastFlushAt))
    }

    /// 取走积压（**强刷**：收尾 / 结构边界用，不看窗口）。
    public mutating func takeAll(at now: TimeInterval) -> [AgentLoopEvent]? {
        guard !pending.isEmpty else { return nil }
        let batch = pending
        pending.removeAll(keepingCapacity: true)
        lastFlushAt = now
        flushCount += 1
        return batch
    }

    /// 丢弃积压（新一轮开始：上一轮的字不许漏进这一轮）。
    public mutating func discard() {
        pending.removeAll(keepingCapacity: true)
    }

    /// 这条事件**是不是可合并的增量**（其余一律是结构边界）。
    public static func isStreamPiece(_ event: AgentLoopEvent) -> Bool {
        switch event {
        case .delta, .reasoningDelta: return true
        default: return false
        }
    }
}

// MARK: - 思考区视口（详设 §3.33.2）

/// 思考区的**固定视口**与「两档高度」常量（详设 §3.33.2）。
///
/// 改前：内容那一格是 `.frame(maxHeight: 178)` —— 上限而不是定高。`ScrollView` 在
/// 内容比 178pt 短的时候会缩到内容高，于是**运行中思考区的高度跟着字数长**：
/// 每来一段增量整块高度就变一次，它下面的正文整块往下推一次 —— 主人看到的
/// 「闪」有一半是这一条（滚动条只是跟着重算的那个零件）。
///
/// 现在的口径：**运行中与手动展开都是 200pt 定高**（抬头 20 + 发丝 2 + 视口 178），
/// 内容只在视口**内部**滚。整块高度对外恒为常量 ⇒ 探针 200 次采样
/// max == min == 200pt（方差 0），下面的正文一寸不动。
public enum AgentThinkingViewport {

    /// 整块高度（运行中 / 手动展开：**恒为 200pt**）。
    public static let totalHeight: CGFloat = 200

    /// 折叠态 = 一行摘要。
    public static let collapsedHeight: CGFloat = Metrics.listRowHeight

    /// 抬头的发丝间距（`VStack` 的 `spacing`）。
    public static let hairGap: CGFloat = Spacing.hair

    /// 内容视口高度 = 200 − 20 − 2 = **178pt**。
    public static var viewportHeight: CGFloat {
        totalHeight - collapsedHeight - hairGap
    }

    /// 展开态取哪一档高度：**只有两档，没有中间值**（§3.33.2 ④）。
    public static func height(expanded: Bool) -> CGFloat {
        expanded ? totalHeight : collapsedHeight
    }
}

// MARK: - 条件跟随（详设 §3.33.2）

/// 「内容变了要不要自动跟到底」的**唯一判定**（详设 §3.33.2 ③）。
///
/// 改前：`AgentChatView.follow(_:)` 在 `scrollTick` 每次变化时无条件
/// `withAnimation(.easeOut(0.15)) { proxy.scrollTo(bottom) }`，而 `scrollTick`
/// 每个 token 都变 ⇒ **每个 token 都重启一次 150ms 的滚动动画**，动画永远跑不完、
/// 滚动条一直处于「正在滑」的状态（这就是闪的第二个来源），而且用户往上翻也照样被拽回去。
///
/// 现在：跟随只在**用户当前就贴在底部**时发生；用户往上滚一像素就停手，
/// 滚回底部才重新跟随。判定只吃一个读数（距底部多少 pt），纯函数，可判红。
public struct AgentScrollFollow: Sendable {

    /// 「算贴着底」的容差（pt）：整像素舍入 + 行内换行的高度误差都不会超过它。
    public static let bottomTolerance: CGFloat = 4

    /// 「偏移往上挪了多少才算人翻上去了」（pt）：小于它的位移是整像素舍入抖动，不算上翻。
    public static let upwardSlop: CGFloat = 0.5

    /// 现在是不是贴着底（`true` = 新内容到了就跟）。
    public private(set) var isPinnedToBottom: Bool

    /// 上一次读数的「距顶偏移」。判「是不是人往上滚了」**只看这一项的变化方向**。
    ///
    /// 为什么要它（2026-11-07 beta1.0.6 真机「整个界面不滚动，要手工拖」）：
    /// 单看「距底多少」分不清两件完全不同的事 ——
    /// · **人往上滚了** ⇒ 偏移**变小**（该停跟）；
    /// · **内容长高了 / 视口变矮了** ⇒ 偏移不动、距底变大（**不该**停跟，跟一次就好）。
    /// 旧实现只看后者，于是「贴底 + 新内容刚到、还没跟」这一瞬被判成「人上翻」，
    /// 跟随当场断掉，而且之后再也不会自己回来（`follow` 是先 `guard pinned` 的）。
    private var previousOffsetFromTop: CGFloat?

    public init(isPinnedToBottom: Bool = true) {
        self.isPinnedToBottom = isPinnedToBottom
    }

    /// 用一次**完整读数**刷新（`contentHeight` / `viewportHeight` / `offsetFromTop` 都来自
    /// 同一次 `clip.boundsDidChange` 或同一次内容高变化）。
    ///
    /// 三条口径：
    /// 1. 距底 ≤ 容差 ⇒ **贴底**（人滚回底部、或我们自己的跟随落定了）；
    /// 2. 距底 > 容差 **且偏移比上次小** ⇒ **人往上滚了** ⇒ 停跟；
    /// 3. 其余（内容长高 / 视口变矮 / 我们的跟随还没落定）⇒ **保持原判定**。
    public mutating func update(contentHeight: CGFloat,
                               viewportHeight: CGFloat,
                               offsetFromTop: CGFloat) {
        let distance = Self.distanceToBottom(contentHeight: contentHeight,
                                             viewportHeight: viewportHeight,
                                             offsetFromTop: offsetFromTop)
        if distance <= Self.bottomTolerance {
            isPinnedToBottom = true
        } else if let previous = previousOffsetFromTop, offsetFromTop < previous - Self.upwardSlop {
            isPinnedToBottom = false
        }
        previousOffsetFromTop = offsetFromTop
    }

    /// 只有「距底多少」这一项时的口径（内层思考视口用它：那里没有 padding，落点即底边）。
    ///
    /// 外层对话区**不许**用它 —— 外层要能分清「人上翻」与「内容长高」，见上面 `update` 的三条口径。
    public mutating func update(distanceToBottom: CGFloat) {
        isPinnedToBottom = distanceToBottom <= Self.bottomTolerance
    }

    /// 内容变了要不要跟。
    public var shouldFollow: Bool { isPinnedToBottom }

    /// 距底距离（给视图侧算读数用；翻转坐标系由调用方归一化成「距底」）。
    public static func distanceToBottom(contentHeight: CGFloat,
                                        viewportHeight: CGFloat,
                                        offsetFromTop: CGFloat) -> CGFloat {
        let maxOffset = max(0, contentHeight - viewportHeight)
        return max(0, maxOffset - offsetFromTop)
    }
}
