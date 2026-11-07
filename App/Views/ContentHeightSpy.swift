import AppKit
import SwiftUI

/// **内容实测高**的读数器（详设 §3.37）：把「这一块内容自己有多高」报回视图层。
///
/// ## 为什么要一个 AppKit 视图
///
/// 思考区的高度现在是 `min(内容实测高, 200)` —— 头一条要的就是**实测**。
/// 两条常见做法在这里都不可用（都是本仓量过的坑，不是猜的）：
/// · `GeometryReader` + 偏好回传：离屏宿主里**收不到值**（实测恒 0，§3.33.2 探针边界）；
/// · `maxHeight` 让 `ScrollView` 自己缩：这正是 beta1.0.4 之前「一个 token 抖一次」的形态。
///
/// 这里取的读数点与 `ScrollOffsetSpy` 同一路：一个零行为 `NSView` 挂在内容根上，
/// 尺寸由 SwiftUI 排好之后回读 `frame.height`。`ScrollView` 沿滚动轴给内容的是
/// **无约束高度**，所以这个数就是内容的**自然高**（不是被视口裁过的）。
///
/// ## 两条纪律
///
/// 1. **回调拖到下一拍**：`setFrameSize` 发生在布局中，当场改 `@State` 就是
///    「Publishing changes from within view updates」，SwiftUI 会重排两遍；
/// 2. **回调只在高度真的变了时报**（`> 0.01pt`）：量化与限高由调用方做，这里不判语义，
///    但同一个高度重复上报没有意义 —— 那是纯抖。
struct ContentHeightSpy: NSViewRepresentable {

    /// 内容根的**自然高度**（pt）。高度变化时才回调。
    let onHeight: (CGFloat) -> Void

    func makeNSView(context: Context) -> SpyView {
        let view = SpyView()
        view.onHeight = onHeight
        return view
    }

    func updateNSView(_ view: SpyView, context: Context) {
        view.onHeight = onHeight
    }

    final class SpyView: NSView {

        var onHeight: ((CGFloat) -> Void)?
        private var lastReported: CGFloat = -1

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            guard abs(newSize.height - lastReported) > 0.01 else { return }
            lastReported = newSize.height
            // 下一拍再取：读的是**那一刻**的 frame（同一拍里可能又变了一次）。
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.onHeight?(self.frame.height)
            }
        }
    }
}
