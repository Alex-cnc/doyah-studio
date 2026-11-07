import AppKit
import SwiftUI

import DoyahCore

/// 把某个 `SwiftUI.ScrollView` 的**真实滚动位置**报出来（详设 §3.33.2 ③）。
///
/// ## 为什么不用几何读数
///
/// 「离底多远」最直觉的算法是 `GeometryReader` + 命名坐标空间量内容底边的 `maxY`。
/// 但那个读数**在内容长高的那一帧就变了** ⇒「贴着底 + 新内容刚到、还没跟」这一瞬
/// 会被算成「用户往上翻了」⇒ 跟随当场断掉（表现就是「有时跟、有时停在半路」）。
///
/// 偏移**只在真的滚动时**变。所以这里只订阅 clip view 的 `boundsDidChange`：
/// 内容长高**不刷新**跟随状态，跟随只被「人真的滚了」改写。
///
/// ## 落点
///
/// 必须挂在**滚动内容里面**（本例挂在内容末尾那个 1pt 哨兵上）—— 只有这样
/// `enclosingScrollView` 才是那个 `ScrollView`；挂在外层拿到的是父级（或 `nil`）。
struct ScrollOffsetSpy: NSViewRepresentable {

    /// **距底距离**（pt，≥ 0）：0 = 贴着底。只在滚动时回调。
    let onDistanceToBottom: (CGFloat) -> Void

    func makeNSView(context: Context) -> SpyView {
        let view = SpyView()
        view.onDistanceToBottom = onDistanceToBottom
        return view
    }

    func updateNSView(_ view: SpyView, context: Context) {
        view.onDistanceToBottom = onDistanceToBottom
        view.attachIfNeeded()
    }

    final class SpyView: NSView {

        var onDistanceToBottom: ((CGFloat) -> Void)?
        private var observer: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            attachIfNeeded()
            // SwiftUI 有时先把视图插进层级、下一拍才插进 NSScrollView 的文档视图。
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
        }

        /// 一次滚动读数 → 距底距离。
        private func report() {
            guard let scroll = enclosingScrollView else { return }
            let clip = scroll.contentView
            let contentHeight = scroll.documentView?.bounds.height ?? 0
            let viewportHeight = clip.bounds.height
            let maxOffset = max(0, contentHeight - viewportHeight)
            // 归一化成「距顶」：SwiftUI 的文档视图是翻转坐标（origin.y = 0 在顶）；
            // 非翻转时 origin.y = 0 在底，换算一次（否则「上下」整个反了）。
            let flipped = scroll.documentView?.isFlipped ?? true
            let offsetFromTop = flipped ? clip.bounds.origin.y : (maxOffset - clip.bounds.origin.y)
            let distance = AgentScrollFollow.distanceToBottom(contentHeight: contentHeight,
                                                              viewportHeight: viewportHeight,
                                                              offsetFromTop: offsetFromTop)
            onDistanceToBottom?(distance)
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }
}
