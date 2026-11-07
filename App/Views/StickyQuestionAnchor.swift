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
        private var observer: NSObjectProtocol?

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
            guard observer == nil, let scroll = enclosingScrollView else { return }
            let clip = scroll.contentView
            clip.postsBoundsChangedNotifications = true
            observer = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
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
            guard let scroll = enclosingScrollView, let document = scroll.documentView else { return }
            let clip = scroll.contentView
            let contentHeight = document.bounds.height
            let viewportHeight = clip.bounds.height
            let maxOffset = max(0, contentHeight - viewportHeight)
            // 文档视图是翻转坐标（origin.y = 0 在顶）；非翻转时换算一次。
            let flipped = document.isFlipped
            let offsetFromTop = flipped ? clip.bounds.origin.y : (maxOffset - clip.bounds.origin.y)

            refreshQuestionTopIfNeeded(in: document, flipped: flipped)

            let stuck = questionTop.map {
                AgentStickyQuestion.shouldStick(viewportTop: offsetFromTop, questionTop: $0)
            } ?? false
            let distance = AgentScrollFollow.distanceToBottom(contentHeight: contentHeight,
                                                              viewportHeight: viewportHeight,
                                                              offsetFromTop: offsetFromTop)
            let reading = Reading(offsetFromTop: offsetFromTop,
                                  distanceToBottom: distance,
                                  isStuck: stuck)
            // 回写走**下一拍**：`boundsDidChange` 可能就发生在 SwiftUI 的一次布局 / 更新里，
            // 当场写宿主 `@State` 会踩「Modifying state during view update」
            // （本轮实测原话：`AgentChatView.swift:197: Modifying state during view update`）。
            DispatchQueue.main.async { [weak self] in self?.onReading?(reading) }
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
            guard let scroll = enclosingScrollView, let document = scroll.documentView else { return }
            let clip = scroll.contentView
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
        }
    }
}
