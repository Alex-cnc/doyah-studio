import AppKit
import SwiftUI

import DoyahCore

/// **当前轮那条提问**的标记视图（详设 §3.34）。
///
/// 它自己不报任何数：只作为「这一行是当前轮提问」的记号挂在那一行的背景上，
/// 让 `StickyQuestionSpy` 在文档视图里找得到它、量得到它的顶边。
///
/// 为什么不让这个视图**自己**往回写状态：那一行会被 `LazyVStack` 回收（长输出把它顶远），
/// 回收后回调就断了；更要命的是「从被回收那一行的闭包里写宿主 `@State`」在 SwiftUI 里会踩
/// 「Modifying state during view update」（本轮实测：`AgentChatView.swift: Modifying state
/// during view update, this will cause undefined behavior`）—— 写进去的值会被丢掉，
/// 条永远不出现。所以读数与缓存都只放在**长命**的那一件上（`StickyQuestionSpy`，
/// 挂在滚动内容根上、内容多长它都在）。
final class StickyQuestionRowMarker: NSView {}

/// 把标记挂到当前轮那一行上（零行为，只提供身份与坐标）。
struct StickyQuestionRowAnchor: NSViewRepresentable {
    func makeNSView(context: Context) -> StickyQuestionRowMarker {
        StickyQuestionRowMarker()
    }

    func updateNSView(_ view: StickyQuestionRowMarker, context: Context) {}
}

/// 点吸顶条时用的**滚动命令**（详设 §3.34 契约③）。
///
/// 为什么不用 `ScrollViewProxy.scrollTo(message.id, anchor: .top)`：那一行的 id 同时是
/// `ForEach` 的条目身份，`scrollTo` 解析到的是**条目容器**（它前面还有一条轮次分隔线
/// `12 + 0.5 + 12` 与 4pt 块间距）—— 实测落点比行顶低 **28.5pt**，正是这三段之和。
/// 契约③ 要的是「定位到**该消息**顶部」，所以落点直接按内容坐标给：
/// `NSClipView.scroll(to:)` 到「提问顶边」那个偏移，再按刷新后的真值补一次
/// （`LazyVStack` 对未物化行只有估值，第一次落定后坐标可能变）。
final class StickyQuestionScroller {

    weak var spy: StickyQuestionSpy.SpyView?

    /// 把视口顶滚到「当前轮提问的顶边」。没量到那一行（还没渲染过）就什么都不做。
    func scrollQuestionToTop() {
        spy?.scrollQuestionToTop()
    }

    /// 把视口滚到**内容底边**（贴底跟随的唯一落点，§3.33.3 契约①）。
    func scrollToBottom() {
        spy?.scrollToBottom()
    }

    /// 新轮开口：重置贴底状态机并贴底（§3.33.3）。
    func repinToBottom() {
        spy?.repinToBottom()
    }
}

/// 对话区滚动读数的**唯一出口**（详设 §3.34；贴底跟随沿用 §3.33.2 ③）：一次滚动，三个读数。
///
/// · `offsetFromTop`：视口顶在内容坐标里的位置（吸顶判定的一半）；
/// · `isStuck`：当前轮那条提问是否已经**滚出视口顶**（= `AgentStickyQuestion.shouldStick`）；
/// · `distanceToBottom`：距底距离（贴底跟随）。
///
/// ## 为什么三样都从这一处出
///
/// 判定的两个量必须在**同一次读数**里取：`clip.bounds.origin` 一次只变一个新值，分开订阅
/// 就会在「滚动刚到、布局还没跟」的那一拍拼出互相矛盾的组合（一边新一边旧）⇒ 条闪。
///
/// ## 为什么由它去找那一行、而不是那一行来找它
///
/// 「当前轮提问顶边在内容里的位置」只在那一行**还活着**时量得到；长输出会把它顶到很远，
/// `LazyVStack` 会把它回收。所以缓存必须留在**不会死的对象**上（这个 Spy 挂在滚动内容根），
/// 并且按「标记视图的实例身份」判断缓存是否还有效：
///
/// · 找到标记 ⇒ 记下它的顶边；换了实例（新的一轮 / 行被重建）⇒ 重记；
/// · 找不到（行被回收）⇒ **沿用上一份**。清掉就等于「滚远了反而不吸顶」，正是要修的现象。
///
/// 三样读数都只在**真的滚动**时算（`clip.boundsDidChange`）：内容长高不改它们 ——
/// 否则「贴着底 + 新内容刚到、还没跟」这一瞬会被误判成「用户往上翻」（§3.33.2 的同一条教训）。
struct StickyQuestionSpy: NSViewRepresentable {

    struct Reading: Equatable {
        /// 视口顶在内容坐标里的位置（pt，≥ 0）。
        var offsetFromTop: CGFloat
        /// 距底距离（pt，≥ 0）。
        var distanceToBottom: CGFloat
        /// 当前轮提问是否已经滚出视口顶（条该出现）。
        var isStuck: Bool
        /// 外层对话区是不是**贴着底**（唯一判定：`AgentScrollFollow` 的状态机，住在读数器里）。
        var isPinned: Bool = true
        /// 内容总高 / 视口高（pt）：只给判据读数用，判定不读它们。
        var contentHeight: CGFloat = 0
        var viewportHeight: CGFloat = 0
    }

    /// 点条时的滚动命令（`nil` = 不需要 / 探针自己滚）。
    var scroller: StickyQuestionScroller?
    let onReading: (Reading) -> Void

    func makeNSView(context: Context) -> SpyView {
        let view = SpyView()
        view.onReading = onReading
        scroller?.spy = view
        return view
    }

    func updateNSView(_ view: SpyView, context: Context) {
        view.onReading = onReading
        scroller?.spy = view
        view.attachIfNeeded()
    }

    final class SpyView: NSView {

        var onReading: ((Reading) -> Void)?

        /// **贴底判定唯一的状态机**（§3.33.3）。
        ///
        /// 为什么住在读数器里而不是宿主的 `@State` 里：它要记住「上一次的偏移」才能分清
        /// 「人往上滚了」与「内容长高了」。放进 `@State` 结构体，就得每次读数都写一次状态
        /// ⇒ 每一个滚动帧都重算一屏（那正是 §3.33.2 要消掉的「闪」）。这里只是一块内存，
        /// 宿主只在**判定翻转**时被通知一次。
        private var follow = AgentScrollFollow()

        private var observer: NSObjectProtocol?
        /// 内容高变化的那一路（新内容 / 折展都会改它）。
        private var frameObserver: NSObjectProtocol?
        /// 视口高变化的那一路（吸顶条进出 / 窗口改宽高）。
        private var clipFrameObserver: NSObjectProtocol?
        /// 正在由**我们自己**滚（防止「补跟 → 读数 → 再补跟」在同一个调用栈里递归）。
        private var isScrolling = false
        /// **订阅时那一个 clip**：读数永远只从它来（子滚动区 —— 比如内层思考视口 —— 的
        /// `boundsDidChange` 通知 object 不是它，因此进不来）。
        private weak var attachedClip: NSClipView?

        /// 当前轮提问顶边在内容坐标里的位置，以及它是从哪个标记实例量来的。
        private var questionTop: CGFloat?
        private weak var questionMarker: StickyQuestionRowMarker?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            attachIfNeeded()
            // SwiftUI 有时先把视图插进层级、下一拍才插进 `NSScrollView` 的文档视图。
            DispatchQueue.main.async { [weak self] in self?.attachIfNeeded() }
        }

        func attachIfNeeded() {
            guard observer == nil, let scroll = enclosingScrollView, let document = scroll.documentView else { return }
            let clip = scroll.contentView
            attachedClip = clip
            clip.postsBoundsChangedNotifications = true
            observer = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clip,
                queue: .main
            ) { [weak self] _ in
                self?.report()
            }
            // **内容高变化也要报一次**（§3.33.3 契约①）：流式逐段、新步骤、思考区折/展、
            // 吸顶条进出都只改**内容高**而不改偏移 —— 等 `boundsDidChange` 就等于永远等不到。
            document.postsFrameChangedNotifications = true
            frameObserver = NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: document,
                queue: .main
            ) { [weak self] _ in
                self?.report()
            }
            // **视口高变化也要报一次**：吸顶条进出（§3.34）让视口少/多 20pt，内容高一点没变、
            // 偏移也一点没动 —— 只有「视口变矮」这一件事把距底撑开 20pt（实测 T-① 第 6 次）。
            clip.postsFrameChangedNotifications = true
            clipFrameObserver = NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: clip,
                queue: .main
            ) { [weak self] _ in
                self?.report()
            }
            // 首报走下一拍：`attachIfNeeded` 常在视图更新中途被调，同步回写状态会踩
            // 「在更新中修改状态」（见文件头的实测记录）。
            DispatchQueue.main.async { [weak self] in self?.report() }
        }

        private func report() {
            // **只读我们自己订阅的那一个 clip**：视图被挪进子滚动区时这条守卫会挡住
            // 「内层滚动当外层读数」（§3.33.3 契约②）。
            guard let clip = attachedClip, clip.window != nil,
                  let scroll = clip.enclosingScrollView, let document = scroll.documentView
            else { return }
            let contentHeight = document.bounds.height
            let viewportHeight = clip.bounds.height
            let maxOffset = max(0, contentHeight - viewportHeight)
            // 文档视图是翻转坐标（origin.y = 0 在顶）；非翻转时换算一次。
            let flipped = document.isFlipped
            let offsetFromTop = flipped ? clip.bounds.origin.y : (maxOffset - clip.bounds.origin.y)

            refreshQuestionTopIfNeeded(in: document, flipped: flipped)

            // 贴底判定：一次完整读数进状态机（分得清「人上翻」与「内容长高」）。
            follow.update(contentHeight: contentHeight,
                          viewportHeight: viewportHeight,
                          offsetFromTop: offsetFromTop)

            let distance = AgentScrollFollow.distanceToBottom(contentHeight: contentHeight,
                                                              viewportHeight: viewportHeight,
                                                              offsetFromTop: offsetFromTop)

            // **贴底态的自愈**（§3.33.3 契约①）：内容刚长高、偏移还没跟上 ⇒ 当场补跟，
            // 不等「通知 → 下一拍回写 → 再重排」那条链（少两帧，实测会漏出 20pt）。
            // 只在**贴底**时做：人往上翻之后 `follow` 已经是假，这里一次都不会触发。
            if follow.isPinnedToBottom, distance > AgentScrollFollow.bottomTolerance, !isScrolling {
                scrollToBottom()
                return
            }

            let stuck = questionTop.map {
                AgentStickyQuestion.shouldStick(viewportTop: offsetFromTop, questionTop: $0)
            } ?? false
            let reading = Reading(offsetFromTop: offsetFromTop,
                                  distanceToBottom: distance,
                                  isStuck: stuck,
                                  isPinned: follow.isPinnedToBottom,
                                  contentHeight: contentHeight,
                                  viewportHeight: viewportHeight)
            // 回写走**下一拍**：`boundsDidChange` 可能就发生在 SwiftUI 的一次布局 / 更新里，
            // 当场写宿主 `@State` 会踩「Modifying state during view update」
            // （本轮实测原话：`AgentChatView.swift:197: Modifying state during view update`）。
            DispatchQueue.main.async { [weak self] in self?.onReading?(reading) }
        }

        /// 把视口滚到**内容底边**（贴底跟随的唯一落点，§3.33.3 契约①）。
        ///
        /// 为什么不走 `ScrollViewProxy.scrollTo(底部哨兵, anchor: .bottom)`：那个落点对齐的是
        /// **哨兵**的底边，而内容末尾还有 12pt 的 `.padding(.vertical)`（`Spacing.m`）——
        /// 实测（beta1.0.6 真机 / 探针）贴底后距底**恒为 12.0pt**，超过 4pt 容差 ⇒
        /// 每跟一次就立刻被判成「用户上翻」⇒ 整段流式再也不跟。落点必须**同一个分母**。
        func scrollToBottom() {
            applyScroll(offsetFromTop: .greatestFiniteMagnitude)
        }

        /// **新轮开口**：状态机整个重置（上一轮翻到哪都作废）再贴底。
        ///
        /// 为什么不只是「贴底一次」：人刚发了消息就该看见这一轮的回答 —— 哪怕他上一轮
        /// 翻到半路停着。重置状态机是刻意的：那一刻的「上翻」意图已经失效了。
        func repinToBottom() {
            follow = AgentScrollFollow()
            scrollToBottom()
        }

        /// 把视口顶滚到「当前轮那一行提问的顶边」（§3.34 契约③）。
        ///
        /// 两次落点：第一次按当前的 content 坐标滚；落定后那一行就物化了，`LazyVStack`
        /// 对它的位置从「估值」变成真值 ⇒ 再按新值补一次（实测估值误差 28.5pt 量级）。
        func scrollQuestionToTop() {
            guard let top = questionTop else { return }
            applyScroll(offsetFromTop: top)
            DispatchQueue.main.async { [weak self] in
                guard let self, let refreshed = self.questionTop else { return }
                self.applyScroll(offsetFromTop: refreshed)
            }
        }

        private func applyScroll(offsetFromTop: CGFloat) {
            guard let clip = attachedClip ?? enclosingScrollView?.contentView,
                  let scroll = clip.enclosingScrollView,
                  let document = scroll.documentView
            else { return }
            isScrolling = true
            defer { isScrolling = false }
            let maxOffset = max(0, document.bounds.height - clip.bounds.height)
            let clamped = min(max(0, offsetFromTop), maxOffset)
            let y = document.isFlipped ? clamped : (maxOffset - clamped)
            clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: y))
            scroll.reflectScrolledClipView(clip)
            // 不必等 `boundsDidChange`：位置已经定了，当场重算一次读数（回写仍走下一拍）。
            report()
        }

        /// 找到那一行的标记就重记它的顶边；标记换了实例就作废重记；找不到就**留着**上一份。
        private func refreshQuestionTopIfNeeded(in document: NSView, flipped: Bool) {
            let markers = Self.findMarkers(in: document).filter { $0.window != nil && $0 !== self }
            guard let marker = markers.first else { return }
            if marker !== questionMarker {
                questionMarker = marker
                questionTop = nil
            }
            let rect = marker.convert(marker.bounds, to: document)
            let top = flipped ? rect.minY : (document.bounds.height - rect.maxY)
            if let last = questionTop, abs(last - top) <= 0.5 { return }
            questionTop = top
        }

        private static func findMarkers(in view: NSView) -> [StickyQuestionRowMarker] {
            var found: [StickyQuestionRowMarker] = []
            if let marker = view as? StickyQuestionRowMarker { found.append(marker) }
            for subview in view.subviews {
                found.append(contentsOf: findMarkers(in: subview))
            }
            return found
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
            if let frameObserver { NotificationCenter.default.removeObserver(frameObserver) }
            if let clipFrameObserver { NotificationCenter.default.removeObserver(clipFrameObserver) }
        }
    }
}
