import AppKit
import SwiftUI

/// 每行在**窗口坐标**里的框（右键按指针位置定位行用）。
///
/// 为什么需要它：整棵树渲染成 `List` 里的**一个**行（为控行距），行级 hover 状态在整树重算后
/// 会被 SwiftUI 补一个**假的 `mouseExited`** 清掉；指针没动就不会再来 `mouseEntered`
/// ⇒「鼠标底下那一行」在右键那一刻是**空的**。于是右键只能退回"上次左键点过的那一行"，
/// 表现就是需求提出者 2026-09-29 报的：**已经选中 A 之后，右键 B 选不中 B**。
/// 真正的指针位置永远可靠 ⇒ 记下每行的框，右键时按 `NSEvent.locationInWindow` 命中。
final class ObjectTreeFramesBox {
    /// 行 id → 该行在窗口坐标里的框。写它**不触发重绘**（无观察者），
    /// 与 `HoverBox` 同一套路（`@State` 一写就让整树重算，反而会把 hover 清掉）。
    var frames: [String: CGRect] = [:]
}

private struct ObjectTreeRowFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// 记一行自己在窗口里的框（挂在行背景上，`Color.clear` 不参与命中）。
struct ObjectTreeRowFrameRecorder: View {
    let id: String

    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: ObjectTreeRowFramesKey.self,
                value: [id: proxy.frame(in: .global)]
            )
        }
    }
}

/// 把每行的框收进盒子的修饰符。
struct ObjectTreeFrameCollector: ViewModifier {
    let box: ObjectTreeFramesBox

    func body(content: Content) -> some View {
        content.onPreferenceChange(ObjectTreeRowFramesKey.self) { frames in
            box.frames = frames
        }
    }
}

/// **右键即选中**：指针在哪一行，右键就把那一行设为选中 —— 菜单内容因此永远对得上眼前这一行。
///
/// 用本地事件监听（进程内，不需要任何 TCC 授权），而不是给每行挂手势：
/// ① 行的内容是非交互的文本/图标，SwiftUI 的 `contextMenu` 由外层 `List` 行统一承接，
///    行级手势拿不到"是哪一个被点了"；② 指针位置本身是最可靠的事实来源。
/// 监听器**只吞事件不改事件**：返回 `event` 让系统照常弹出菜单。
struct RightClickRowSelector: NSViewRepresentable {
    let box: ObjectTreeFramesBox
    /// 命中行的 id（没命中就不调）。
    let onPick: (String) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(to: view, box: box, onPick: onPick)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.attach(to: nsView, box: box, onPick: onPick)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private var monitor: Any?
        private weak var view: NSView?
        private var onPick: ((String) -> Void)?
        private var box: ObjectTreeFramesBox?

        func attach(to view: NSView, box: ObjectTreeFramesBox, onPick: @escaping (String) -> Void) {
            self.view = view
            self.box = box
            self.onPick = onPick
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown]) { [weak self] event in
                self?.handle(event)
                return event
            }
        }

        func detach() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        deinit { detach() }

        private func handle(_ event: NSEvent) {
            log("monitor fired window=\(event.window != nil)")
            guard let view, let window = view.window, event.window === window else {
                log("skip: view/window 不匹配")
                return
            }
            let point = Self.swiftUIPoint(for: event, in: window)
            let frames = box?.frames ?? [:]
            let id = Self.rowID(at: point, in: frames)
            log("point(窗口内容·左上原点)=\(point) frames=\(frames.count) hit=\(id ?? "nil")")
            guard let id else { return }
            onPick?(id)
        }

        /// **坐标系换算（这是 2026-09-29 第一次改漏的地方）**：
        /// `NSEvent.locationInWindow` 是 AppKit 坐标（原点在**窗口左下**）；
        /// SwiftUI 的 `.global` 是**窗口内容坐标、原点左上**。两者不做换算就直接比，
        /// 命中判定永远不成立 —— 表现就是"右键什么也没发生"。
        static func swiftUIPoint(for event: NSEvent, in window: NSWindow) -> CGPoint {
            let content = window.contentView
            let inContent = content?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow
            let height = content?.bounds.height ?? window.frame.height
            return CGPoint(x: inContent.x, y: height - inContent.y)
        }

        /// 调试日志（只在 `DOYAH_TREE_RIGHTCLICK_DEBUG=1` 时写；用来在**没有界面截图权限**的条件下取证）。
        private func log(_ message: String) {
            guard ProcessInfo.processInfo.environment["DOYAH_TREE_RIGHTCLICK_DEBUG"] == "1" else { return }
            let line = "\(Date()) \(message)\n"
            let path = "/tmp/doyah-tree-rightclick.log"
            if let handle = FileHandle(forWritingAtPath: path) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? line.write(toFile: path, atomically: true, encoding: .utf8)
            }
        }

        /// 纯函数：指针在哪个行的框里（自上而下第一个命中；重叠时取靠下的那行 —— 行是顺序排布的，
        /// 边框可能重叠 1pt）。抽出来是为了能被判据直接断言。
        static func rowID(at point: CGPoint, in frames: [String: CGRect]) -> String? {
            frames
                .filter { $0.value.contains(point) }
                .min { $0.value.minY < $1.value.minY }?
                .key
        }
    }
}
