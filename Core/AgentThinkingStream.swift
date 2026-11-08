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

// MARK: - 思考区视口（详设 §3.33.2 ② / §3.37）

/// 思考区的**上限**与「高度 = min(内容实测高, 上限)」的量化规则（详设 §3.37）。
///
/// ## 两轮反例各修了一半，本轮才是正解
///
/// · beta1.0.4 之前：内容格是 `.frame(maxHeight: 178)` —— 纯上限，`ScrollView` 在内容
///   比 178pt 短时缩到内容高 ⇒ **高度一个 token 变一次**，下面的正文被一遍遍往下推（「闪」）；
/// · beta1.0.4~1.0.7：改成**恒 200pt 定高**压住了抖动，但内容只有一两行时下面空出
///   一大块（beta1.0.8 主人原话：「固定高度，中间空一个大空白区域」）；
/// · 本轮：**高度 = min(内容实测高, 200)**，且内容高**按整行向上取**（`lineHeight` = 一行
///   等宽字）—— 一行的思考就只占一行，超上限才卡在 200 + 内部滚动；高度只在**跨过行高
///   倍数**时变，所以不会退回「一个 token 抖一次」。
///
/// 量化（而不是直接用实测 pt）是这套口径的关键：实测高是连续量，每来半个字就可能
/// 多出 0.3pt ⇒ 状态写一次、正文被推 0.3pt。按行取整之后，一次上屏最多把一个区
/// 往前推**一整行**，而推的总量 = 内容真的长出来的高度（判据④⑤）。
public enum AgentThinkingViewport {

    /// 展开态**上限**（不是定高）：内容再长也到 200pt 停，超出部分在视口里滚。
    public static let totalHeight: CGFloat = 200

    /// 折叠态 = 一行摘要。
    public static let collapsedHeight: CGFloat = Metrics.listRowHeight

    /// 抬头的发丝间距（`VStack` 的 `spacing`）。
    public static let hairGap: CGFloat = Spacing.hair

    /// 上限对应的内容视口高 = 200 − 20 − 2 = **178pt**。
    public static var viewportHeight: CGFloat {
        totalHeight - collapsedHeight - hairGap
    }

    /// 量化步长 = **一行等宽字**（`Metrics.listRowHeight`，与列表行、折叠行同档）。
    public static var lineHeight: CGFloat { Metrics.listRowHeight }

    /// 内容实测高 → **按整行向上取**。
    ///
    /// `0` / 负值 / 非有限值一律归 0（还没量到 ⇒ 视口先不占高度，等实测落定）。
    public static func quantizedContentHeight(_ raw: CGFloat) -> CGFloat {
        guard raw.isFinite, raw > 0 else { return 0 }
        return (raw / lineHeight).rounded(.up) * lineHeight
    }

    /// 展开态**内容视口**高 = min(量化后的实测高, 178)。
    public static func expandedViewportHeight(contentHeight raw: CGFloat) -> CGFloat {
        min(quantizedContentHeight(raw), viewportHeight)
    }

    /// 展开态**整块**高 = 抬头 + 间距 + 视口（≤ 200）。
    public static func expandedHeight(contentHeight raw: CGFloat) -> CGFloat {
        collapsedHeight + hairGap + expandedViewportHeight(contentHeight: raw)
    }

    /// 内容是否已经顶到上限（⇒ 内部滚动生效、按 §3.33.2 ⑤ 的指示器策略走）。
    public static func isOverflowing(contentHeight raw: CGFloat) -> Bool {
        quantizedContentHeight(raw) >= viewportHeight
    }

    /// 展开态对外高度：实现里 `expanded` 由 `AgentThinkingFold` 判，这里只兜折叠态。
    public static func height(expanded: Bool, contentHeight raw: CGFloat = 0) -> CGFloat {
        expanded ? expandedHeight(contentHeight: raw) : collapsedHeight
    }
}

// MARK: - 过程行体的自适应高度（详设 §3.37）

/// 工具块 / `Tool calls` 行体：**行数是整数、行高是常量** ⇒ 高度可直接算，不用实测。
///
/// 与思考区同一口径（`min(内容高, 上限)`），但不走量化：这里的「一行」本来就是
/// 一次调用 / 一条工具条目（各 `Metrics.listRowHeight`），天然只在整行边界变化。
public enum AgentProcessBody {

    /// 一行条目高。
    public static var rowHeight: CGFloat { Metrics.listRowHeight }

    /// 行体高 = min(行数 × 行高 + (行数−1) × 间距, 上限)；0 行 ⇒ 0（不留空壳）。
    public static func height(rows: Int, spacing: CGFloat, cap: CGFloat) -> CGFloat {
        guard rows > 0 else { return 0 }
        let natural = CGFloat(rows) * rowHeight + CGFloat(rows - 1) * max(0, spacing)
        return min(natural, cap)
    }
}

// MARK: - 三行汇总的几何口径（详设 §3.33.4 契约九 / §3.37）

/// **一轮三行汇总**（`Thinking` / `Tool calls (N)` / `Σ total`）的尺寸口径。
///
/// 三行各是一行（`Metrics.listRowHeight` = 20pt），**行间不留间距** —— 折叠态过程区高
/// 就是三行之和 **60pt**。改前这里是 `Spacing.hair`（2pt）× 2 = 4pt 的额外竖向空隙，
/// 视觉上就是「汇总区自己空了一块」，读数上也对不上「三行之和」。
public enum AgentProcessBlock {

    /// 三行之间的间距：**0**（三行是同一条读数带，不是三个卡片）。
    public static let rowSpacing: CGFloat = 0

    /// 折叠态过程区高 = 三行之和（60pt）。
    public static var collapsedHeight: CGFloat { 3 * Metrics.listRowHeight }

    /// **汇总区与结论之间的块间距**：取转写区**既有的块间距**（`Spacing.xs` = 4pt）。
    ///
    /// 为什么要有这个常量：这条距离是契约（§3.37 契约⑩），不许由「中间还夹了几条
    /// 被折进汇总的行」决定 —— 那些行必须**一个都不占位**（`AgentTranscriptRow.draws`），
    /// 于是「Σ 行底边 → 结论首行顶边」恒等于一个块间距，与轮内步数无关。
    public static var answerGap: CGFloat { Spacing.xs }
}

// MARK: - 转写区一行「画不画」（详设 §3.37 契约⑩）

/// **这一条消息在转写区里占不占一行**（唯一判定；视图与判据读同一份）。
///
/// 为什么必须有一个显式判定：过程信息被折进三行汇总之后，被折的那些消息
/// （工具行、轮内中间叙述）**内容一个字都不画了**，可它们的行还在 —— 行首栏的时间戳
/// 与悬停操作条（`.opacity(0)` 仍然占布局）各占一行高。beta1.0.9 真机
/// 「汇总与结论部分仍然有一块空白」就是这些**空行**堆出来的：
/// 一条 6 条消息的轮次里，Σ 行到结论之间有 3 个空行 ⇒ 空白 61pt。
///
/// 判据（`AgentSummaryGapProbeTests` ①）量的就是「这些空行是否真的不占位」。
public enum AgentTranscriptRow {

    /// 这一条消息要不要占一行。
    ///
    /// - Parameters:
    ///   - foldedIntoTurnSummary: 这一条的内容已经被折进本轮三行汇总（工具行）⇒ 不再单独成行。
    public static func draws(role: AgentChatRole,
                             text: String,
                             isStreaming: Bool,
                             isFinalAssistant: Bool,
                             foldedIntoTurnSummary: Bool,
                             streamingEnabled: Bool) -> Bool {
        switch role {
        case .user, .notice:
            return true
        case .tool:
            // 折进汇总的工具行不占位（明细在 `Tool calls` 那一行展开后逐条 20pt）。
            return !foldedIntoTurnSummary
        case .assistant:
            // 「流式输出 = 关」时这一条收齐前一个字都不画（`FR-AGT-UX-CONV-012`）。
            if isStreaming && !streamingEnabled { return false }
            // 还在收、还没有第一个字 ⇒ 有占位行（加载中），要占位。
            if isStreaming && text.isEmpty { return true }
            // 轮内中间叙述整条进思考区 ⇒ 正文区不画、行也不占。
            guard isFinalAssistant else { return false }
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
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
